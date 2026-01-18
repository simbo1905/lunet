--[[
  Corfu Storage Unit - Write-Once Block Storage
  
  Implements the Corfu distributed log storage unit protocol with write-once
  semantics per 4KB block, as specified in the Corfu paper.
  
  Wire Protocol (big-endian framed messages):
    Request Frame:
      u32 total_len     -- bytes following this field
      u8  msg_type      -- 1=WRITE, 2=READ, 3=TRIM, 4=SEAL, 5=PING
      u32 request_id    -- client correlation id
      ... payload ...
      
    WRITE payload:
      u64 address       -- log address
      bytes[4096] data  -- block data
      
    READ payload:
      u64 address       -- log address
      
    Response Frame:
      u32 total_len
      u8  msg_type      -- same as request
      u32 request_id
      u8  status        -- 0=OK, 1=ALREADY_WRITTEN, 2=NOT_WRITTEN, 3=SEALED, 4=TRIMMED, 5=ERROR
      ... payload ...
      
    READ OK response includes:
      bytes[4096] data
      
  Safety Properties:
    1. Write-Once Immutability: Once written, a block never changes
    2. Single-Assignment: At most one successful write per address
    3. Atomicity: Reads observe full 4KB or nothing
    4. Crash Recovery: Written bitmap persists across restarts
]]

local lunet = require('lunet')
local socket = require('lunet.socket')
local fs = require('lunet.fs')

-- Constants
local BLOCK_SIZE = 4096
local BITMAP_MAGIC = 0x5355424D  -- "SUBM" (Storage Unit BitMap)
local BITMAP_VERSION = 1
local BITMAP_HEADER_SIZE = 16    -- magic(4) + version(4) + max_addresses(8)

-- Message types
local MSG_WRITE = 1
local MSG_READ = 2
local MSG_TRIM = 3
local MSG_SEAL = 4
local MSG_PING = 5

-- Response status codes
local STATUS_OK = 0
local STATUS_ALREADY_WRITTEN = 1
local STATUS_NOT_WRITTEN = 2
local STATUS_SEALED = 3
local STATUS_TRIMMED = 4
local STATUS_ERROR = 5

-- Storage Unit state
local StorageUnit = {
    data_fd = nil,           -- File descriptor for data file
    bitmap_fd = nil,         -- File descriptor for bitmap file
    bitmap_cache = {},       -- In-memory bitmap cache (address -> true)
    max_addresses = 0,       -- Maximum number of addresses
    sealed = false,          -- Whether the unit is sealed
    trim_mark = -1,          -- Addresses below this are trimmed
    pending_locks = {},      -- Per-address locks for concurrency
    data_path = nil,
    bitmap_path = nil,
}

------------------------------------------------------------------------------
-- Binary encoding/decoding utilities (big-endian)
------------------------------------------------------------------------------

local function encode_u8(val)
    return string.char(val % 256)
end

local function encode_u32(val)
    return string.char(
        math.floor(val / 16777216) % 256,
        math.floor(val / 65536) % 256,
        math.floor(val / 256) % 256,
        val % 256
    )
end

local function encode_u64(val)
    -- Handle as two u32s for Lua number precision
    local high = math.floor(val / 4294967296)
    local low = val % 4294967296
    return encode_u32(high) .. encode_u32(low)
end

local function decode_u8(data, offset)
    offset = offset or 1
    return string.byte(data, offset)
end

local function decode_u32(data, offset)
    offset = offset or 1
    local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

local function decode_u64(data, offset)
    offset = offset or 1
    local high = decode_u32(data, offset)
    local low = decode_u32(data, offset + 4)
    return high * 4294967296 + low
end

------------------------------------------------------------------------------
-- Bitmap management
------------------------------------------------------------------------------

-- Calculate byte index and bit position for an address
local function address_to_bitmap_pos(address)
    local byte_index = math.floor(address / 8)
    local bit_pos = address % 8
    return byte_index, bit_pos
end

-- Check if address is written (in-memory check)
local function is_address_written(address)
    return StorageUnit.bitmap_cache[address] == true
end

-- Mark address as written in bitmap (both memory and disk)
local function mark_address_written(address)
    if StorageUnit.bitmap_cache[address] then
        return false, "already written"
    end
    
    -- Calculate position in bitmap file
    local byte_index, bit_pos = address_to_bitmap_pos(address)
    local file_offset = BITMAP_HEADER_SIZE + byte_index
    
    -- Read current byte from bitmap file
    local current_byte_str, err = fs.pread(StorageUnit.bitmap_fd, 1, file_offset)
    local current_byte = 0
    if current_byte_str and #current_byte_str == 1 then
        current_byte = string.byte(current_byte_str)
    end
    
    -- Set the bit
    local new_byte = bit.bor(current_byte, bit.lshift(1, bit_pos))
    
    -- Write back to bitmap file
    local written, werr = fs.pwrite(StorageUnit.bitmap_fd, string.char(new_byte), file_offset)
    if not written then
        return false, "failed to write bitmap: " .. (werr or "unknown")
    end
    
    -- Sync bitmap to disk for durability
    local sync_err = fs.fsync(StorageUnit.bitmap_fd)
    if sync_err then
        return false, "failed to sync bitmap: " .. sync_err
    end
    
    -- Update in-memory cache
    StorageUnit.bitmap_cache[address] = true
    
    return true
end

-- Initialize bitmap file
local function init_bitmap(path, max_addresses)
    StorageUnit.bitmap_path = path
    StorageUnit.max_addresses = max_addresses
    
    -- Calculate required bitmap size
    local bitmap_bytes = math.ceil(max_addresses / 8)
    local total_size = BITMAP_HEADER_SIZE + bitmap_bytes
    
    -- Check if file exists
    local stat, _ = fs.stat(path)
    
    if stat then
        -- File exists, open for read/write
        local fd, err = fs.open(path, "r+")
        if not fd then
            return false, "failed to open bitmap: " .. (err or "unknown")
        end
        StorageUnit.bitmap_fd = fd
        
        -- Read and verify header
        local header, rerr = fs.pread(fd, BITMAP_HEADER_SIZE, 0)
        if not header or #header < BITMAP_HEADER_SIZE then
            fs.close(fd)
            return false, "failed to read bitmap header"
        end
        
        local magic = decode_u32(header, 1)
        local version = decode_u32(header, 5)
        local stored_max = decode_u64(header, 9)
        
        if magic ~= BITMAP_MAGIC then
            fs.close(fd)
            return false, "invalid bitmap magic"
        end
        
        if version ~= BITMAP_VERSION then
            fs.close(fd)
            return false, "unsupported bitmap version"
        end
        
        -- Load bitmap into memory cache
        local bitmap_data, berr = fs.pread(fd, bitmap_bytes, BITMAP_HEADER_SIZE)
        if not bitmap_data then
            fs.close(fd)
            return false, "failed to read bitmap data"
        end
        
        -- Populate cache from bitmap
        for i = 0, max_addresses - 1 do
            local byte_index, bit_pos = address_to_bitmap_pos(i)
            if byte_index < #bitmap_data then
                local byte_val = string.byte(bitmap_data, byte_index + 1)
                if bit.band(byte_val, bit.lshift(1, bit_pos)) ~= 0 then
                    StorageUnit.bitmap_cache[i] = true
                end
            end
        end
        
        print("[SU] Loaded existing bitmap with " .. table_size(StorageUnit.bitmap_cache) .. " written blocks")
    else
        -- Create new bitmap file
        local fd, err = fs.open(path, "w+")
        if not fd then
            return false, "failed to create bitmap: " .. (err or "unknown")
        end
        StorageUnit.bitmap_fd = fd
        
        -- Write header
        local header = encode_u32(BITMAP_MAGIC) .. 
                       encode_u32(BITMAP_VERSION) .. 
                       encode_u64(max_addresses)
        
        local written, werr = fs.pwrite(fd, header, 0)
        if not written then
            fs.close(fd)
            return false, "failed to write bitmap header"
        end
        
        -- Pre-allocate bitmap space with zeros
        local zero_block = string.rep("\0", math.min(BLOCK_SIZE, bitmap_bytes))
        local offset = BITMAP_HEADER_SIZE
        local remaining = bitmap_bytes
        
        while remaining > 0 do
            local to_write = math.min(#zero_block, remaining)
            local w, we = fs.pwrite(fd, string.sub(zero_block, 1, to_write), offset)
            if not w then
                fs.close(fd)
                return false, "failed to initialize bitmap"
            end
            offset = offset + to_write
            remaining = remaining - to_write
        end
        
        -- Sync to disk
        local sync_err = fs.fsync(fd)
        if sync_err then
            fs.close(fd)
            return false, "failed to sync new bitmap"
        end
        
        print("[SU] Created new bitmap for " .. max_addresses .. " addresses")
    end
    
    return true
end

-- Helper to count table entries
function table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

------------------------------------------------------------------------------
-- Data file management
------------------------------------------------------------------------------

local function init_data_file(path)
    StorageUnit.data_path = path
    
    -- Check if file exists
    local stat, _ = fs.stat(path)
    
    if stat then
        -- Open existing file
        local fd, err = fs.open(path, "r+")
        if not fd then
            return false, "failed to open data file: " .. (err or "unknown")
        end
        StorageUnit.data_fd = fd
        print("[SU] Opened existing data file: " .. path)
    else
        -- Create new file
        local fd, err = fs.open(path, "w+")
        if not fd then
            return false, "failed to create data file: " .. (err or "unknown")
        end
        StorageUnit.data_fd = fd
        print("[SU] Created new data file: " .. path)
    end
    
    return true
end

------------------------------------------------------------------------------
-- Per-address locking for concurrent write safety
------------------------------------------------------------------------------

-- Simple cooperative lock using coroutine yields
-- Since we're single-threaded with coroutines, we use a waiting queue
local address_locks = {}
local address_waiters = {}

local function acquire_lock(address)
    if not address_locks[address] then
        address_locks[address] = true
        return true
    end
    
    -- Address is locked, we need to wait
    if not address_waiters[address] then
        address_waiters[address] = {}
    end
    
    -- This is a simplification - in real impl would use a condition variable
    -- For now, we just fail fast on concurrent access to same address
    return false
end

local function release_lock(address)
    address_locks[address] = nil
    -- Wake up any waiters (not implemented for simplicity)
end

------------------------------------------------------------------------------
-- Core storage operations
------------------------------------------------------------------------------

-- Write a block (write-once semantics)
local function write_block(address, data)
    -- Validate address
    if address < 0 or address >= StorageUnit.max_addresses then
        return STATUS_ERROR, "address out of range"
    end
    
    -- Validate data size
    if #data ~= BLOCK_SIZE then
        return STATUS_ERROR, "data must be exactly " .. BLOCK_SIZE .. " bytes"
    end
    
    -- Check sealed
    if StorageUnit.sealed then
        return STATUS_SEALED, "storage unit is sealed"
    end
    
    -- Check trimmed
    if address <= StorageUnit.trim_mark then
        return STATUS_TRIMMED, "address has been trimmed"
    end
    
    -- Acquire lock for this address
    if not acquire_lock(address) then
        return STATUS_ERROR, "concurrent write to same address"
    end
    
    -- Check if already written (write-once enforcement)
    if is_address_written(address) then
        release_lock(address)
        return STATUS_ALREADY_WRITTEN, "address already written"
    end
    
    -- Calculate file offset
    local offset = address * BLOCK_SIZE
    
    -- Write data block
    local written, werr = fs.pwrite(StorageUnit.data_fd, data, offset)
    if not written then
        release_lock(address)
        return STATUS_ERROR, "failed to write data: " .. (werr or "unknown")
    end
    
    -- Sync data to disk (optional: can be batched for performance)
    local sync_err = fs.fsync(StorageUnit.data_fd)
    if sync_err then
        release_lock(address)
        return STATUS_ERROR, "failed to sync data: " .. sync_err
    end
    
    -- Mark as written in bitmap (atomic commit point)
    local ok, mark_err = mark_address_written(address)
    if not ok then
        release_lock(address)
        -- Note: data is written but not committed - safe to retry
        return STATUS_ERROR, "failed to mark written: " .. (mark_err or "unknown")
    end
    
    release_lock(address)
    return STATUS_OK, nil
end

-- Read a block
local function read_block(address)
    -- Validate address
    if address < 0 or address >= StorageUnit.max_addresses then
        return STATUS_ERROR, nil, "address out of range"
    end
    
    -- Check trimmed
    if address <= StorageUnit.trim_mark then
        return STATUS_TRIMMED, nil, "address has been trimmed"
    end
    
    -- Check if written
    if not is_address_written(address) then
        return STATUS_NOT_WRITTEN, nil, nil
    end
    
    -- Calculate file offset
    local offset = address * BLOCK_SIZE
    
    -- Read data block
    local data, rerr = fs.pread(StorageUnit.data_fd, BLOCK_SIZE, offset)
    if not data then
        return STATUS_ERROR, nil, "failed to read data: " .. (rerr or "unknown")
    end
    
    if #data ~= BLOCK_SIZE then
        return STATUS_ERROR, nil, "incomplete read"
    end
    
    return STATUS_OK, data, nil
end

------------------------------------------------------------------------------
-- Protocol handling
------------------------------------------------------------------------------

local function build_response(msg_type, request_id, status, payload)
    payload = payload or ""
    local body = encode_u8(msg_type) .. encode_u32(request_id) .. encode_u8(status) .. payload
    return encode_u32(#body) .. body
end

local function handle_write_request(request_id, payload)
    if #payload < 8 + BLOCK_SIZE then
        return build_response(MSG_WRITE, request_id, STATUS_ERROR, "invalid payload size")
    end
    
    local address = decode_u64(payload, 1)
    local data = string.sub(payload, 9, 8 + BLOCK_SIZE)
    
    local status, err = write_block(address, data)
    local err_payload = err and err or ""
    return build_response(MSG_WRITE, request_id, status, err_payload)
end

local function handle_read_request(request_id, payload)
    if #payload < 8 then
        return build_response(MSG_READ, request_id, STATUS_ERROR, "invalid payload size")
    end
    
    local address = decode_u64(payload, 1)
    local status, data, err = read_block(address)
    
    if status == STATUS_OK and data then
        return build_response(MSG_READ, request_id, status, data)
    else
        local err_payload = err and err or ""
        return build_response(MSG_READ, request_id, status, err_payload)
    end
end

local function handle_ping_request(request_id, payload)
    return build_response(MSG_PING, request_id, STATUS_OK, "PONG")
end

local function handle_seal_request(request_id, payload)
    StorageUnit.sealed = true
    print("[SU] Storage unit sealed")
    return build_response(MSG_SEAL, request_id, STATUS_OK, "")
end

local function handle_trim_request(request_id, payload)
    if #payload < 8 then
        return build_response(MSG_TRIM, request_id, STATUS_ERROR, "invalid payload size")
    end
    
    local address = decode_u64(payload, 1)
    if address > StorageUnit.trim_mark then
        StorageUnit.trim_mark = address
        print("[SU] Trim mark set to " .. address)
    end
    return build_response(MSG_TRIM, request_id, STATUS_OK, "")
end

local function process_request(frame)
    if #frame < 5 then
        return nil, "frame too short"
    end
    
    local msg_type = decode_u8(frame, 1)
    local request_id = decode_u32(frame, 2)
    local payload = string.sub(frame, 6)
    
    if msg_type == MSG_WRITE then
        return handle_write_request(request_id, payload)
    elseif msg_type == MSG_READ then
        return handle_read_request(request_id, payload)
    elseif msg_type == MSG_PING then
        return handle_ping_request(request_id, payload)
    elseif msg_type == MSG_SEAL then
        return handle_seal_request(request_id, payload)
    elseif msg_type == MSG_TRIM then
        return handle_trim_request(request_id, payload)
    else
        return build_response(msg_type, request_id, STATUS_ERROR, "unknown message type")
    end
end

------------------------------------------------------------------------------
-- Client connection handler
------------------------------------------------------------------------------

local function handle_client(client)
    local peer, _ = socket.getpeername(client)
    print("[SU] Client connected: " .. (peer or "unknown"))
    
    local buffer = ""
    
    while true do
        -- Read data from client
        local data, err = socket.read(client)
        
        if not data then
            if err then
                print("[SU] Read error: " .. err)
            end
            break
        end
        
        -- Append to buffer
        buffer = buffer .. data
        
        -- Process complete frames
        while #buffer >= 4 do
            local frame_len = decode_u32(buffer, 1)
            
            if #buffer < 4 + frame_len then
                -- Incomplete frame, wait for more data
                break
            end
            
            -- Extract frame
            local frame = string.sub(buffer, 5, 4 + frame_len)
            buffer = string.sub(buffer, 5 + frame_len)
            
            -- Process request and send response
            local response, proc_err = process_request(frame)
            if response then
                local write_err = socket.write(client, response)
                if write_err then
                    print("[SU] Write error: " .. write_err)
                    break
                end
            else
                print("[SU] Process error: " .. (proc_err or "unknown"))
            end
        end
    end
    
    print("[SU] Client disconnected: " .. (peer or "unknown"))
    socket.close(client)
end

------------------------------------------------------------------------------
-- Main server
------------------------------------------------------------------------------

local function start_server(config)
    config = config or {}
    local host = config.host or "127.0.0.1"
    local port = config.port or 9000
    local data_path = config.data_path or "corfu_data.bin"
    local bitmap_path = config.bitmap_path or "corfu_bitmap.bin"
    local max_addresses = config.max_addresses or 1048576  -- 1M blocks = 4GB
    
    print("[SU] Corfu Storage Unit starting...")
    print("[SU] Data file: " .. data_path)
    print("[SU] Bitmap file: " .. bitmap_path)
    print("[SU] Max addresses: " .. max_addresses .. " (" .. (max_addresses * BLOCK_SIZE / 1073741824) .. " GB)")
    
    -- Initialize bitmap
    local ok, err = init_bitmap(bitmap_path, max_addresses)
    if not ok then
        print("[SU] Failed to initialize bitmap: " .. (err or "unknown"))
        return
    end
    
    -- Initialize data file
    ok, err = init_data_file(data_path)
    if not ok then
        print("[SU] Failed to initialize data file: " .. (err or "unknown"))
        return
    end
    
    -- Set larger read buffer for 4KB blocks
    socket.set_read_buffer_size(BLOCK_SIZE + 1024)
    
    -- Create TCP listener
    local listener, listen_err = socket.listen("tcp", host, port)
    if not listener then
        print("[SU] Failed to listen: " .. (listen_err or "unknown"))
        return
    end
    
    print("[SU] Listening on " .. host .. ":" .. port)
    print("[SU] Write-once semantics enforced at 4KB block granularity")
    
    -- Accept connections
    while true do
        local client, accept_err = socket.accept(listener)
        if client then
            -- Handle each client in a new coroutine
            lunet.spawn(function()
                handle_client(client)
            end)
        else
            if accept_err then
                print("[SU] Accept error: " .. accept_err)
            end
        end
    end
end

------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------

-- Parse command line config or use defaults
local config = {
    host = os.getenv("CORFU_HOST") or "0.0.0.0",
    port = tonumber(os.getenv("CORFU_PORT")) or 9000,
    data_path = os.getenv("CORFU_DATA_PATH") or "corfu_data.bin",
    bitmap_path = os.getenv("CORFU_BITMAP_PATH") or "corfu_bitmap.bin",
    max_addresses = tonumber(os.getenv("CORFU_MAX_ADDRESSES")) or 1048576,
}

-- Start in a coroutine
lunet.spawn(function()
    start_server(config)
end)
