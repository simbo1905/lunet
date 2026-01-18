--[[
  Corfu Storage Unit Test Client
  
  Tests the write-once semantics and basic operations of the storage unit.
]]

local lunet = require('lunet')
local socket = require('lunet.socket')

-- Constants (must match server)
local BLOCK_SIZE = 4096
local MSG_WRITE = 1
local MSG_READ = 2
local MSG_PING = 5

local STATUS_OK = 0
local STATUS_ALREADY_WRITTEN = 1
local STATUS_NOT_WRITTEN = 2

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

------------------------------------------------------------------------------
-- Client operations
------------------------------------------------------------------------------

local request_counter = 0

local function send_request(conn, msg_type, payload)
    request_counter = request_counter + 1
    local body = encode_u8(msg_type) .. encode_u32(request_counter) .. payload
    local frame = encode_u32(#body) .. body
    
    local err = socket.write(conn, frame)
    if err then
        return nil, "write error: " .. err
    end
    
    return request_counter
end

local function recv_response(conn)
    -- Read frame header
    local header, err = socket.read(conn)
    if not header or #header < 4 then
        return nil, "failed to read response header"
    end
    
    local frame_len = decode_u32(header, 1)
    local data = string.sub(header, 5)
    
    -- Read remaining data if needed
    while #data < frame_len do
        local more, merr = socket.read(conn)
        if not more then
            return nil, "failed to read response body"
        end
        data = data .. more
    end
    
    -- Parse response
    local msg_type = decode_u8(data, 1)
    local request_id = decode_u32(data, 2)
    local status = decode_u8(data, 6)
    local payload = string.sub(data, 7)
    
    return {
        msg_type = msg_type,
        request_id = request_id,
        status = status,
        payload = payload
    }
end

local function ping(conn)
    local req_id, err = send_request(conn, MSG_PING, "")
    if not req_id then return nil, err end
    
    local resp, rerr = recv_response(conn)
    if not resp then return nil, rerr end
    
    return resp.status == STATUS_OK
end

local function write_block(conn, address, data)
    -- Pad data to BLOCK_SIZE
    if #data < BLOCK_SIZE then
        data = data .. string.rep("\0", BLOCK_SIZE - #data)
    elseif #data > BLOCK_SIZE then
        data = string.sub(data, 1, BLOCK_SIZE)
    end
    
    local payload = encode_u64(address) .. data
    local req_id, err = send_request(conn, MSG_WRITE, payload)
    if not req_id then return nil, err end
    
    local resp, rerr = recv_response(conn)
    if not resp then return nil, rerr end
    
    return resp.status, resp.payload
end

local function read_block(conn, address)
    local payload = encode_u64(address)
    local req_id, err = send_request(conn, MSG_READ, payload)
    if not req_id then return nil, nil, err end
    
    local resp, rerr = recv_response(conn)
    if not resp then return nil, nil, rerr end
    
    if resp.status == STATUS_OK then
        return resp.status, resp.payload, nil
    else
        return resp.status, nil, resp.payload
    end
end

------------------------------------------------------------------------------
-- Test cases
------------------------------------------------------------------------------

local function run_tests()
    print("=== Corfu Storage Unit Test Client ===\n")
    
    -- Connect to server
    print("Connecting to server...")
    local conn, err = socket.connect("127.0.0.1", 9000)
    if not conn then
        print("FAILED: Could not connect - " .. (err or "unknown"))
        return
    end
    print("Connected!\n")
    
    -- Test 1: Ping
    print("Test 1: PING")
    local ok = ping(conn)
    if ok then
        print("  PASS: Server responded to ping\n")
    else
        print("  FAIL: Ping failed\n")
    end
    
    -- Test 2: Write a block
    print("Test 2: WRITE to address 0")
    local test_data = "Hello, Corfu! This is test data for address 0."
    local status, resp_data = write_block(conn, 0, test_data)
    if status == STATUS_OK then
        print("  PASS: Write succeeded\n")
    else
        print("  FAIL: Write failed with status " .. status .. "\n")
    end
    
    -- Test 3: Read the block back
    print("Test 3: READ from address 0")
    status, resp_data, err = read_block(conn, 0)
    if status == STATUS_OK then
        -- Check if data matches (compare prefix since we padded with zeros)
        local read_data = string.sub(resp_data, 1, #test_data)
        if read_data == test_data then
            print("  PASS: Read succeeded and data matches\n")
        else
            print("  FAIL: Data mismatch\n")
            print("    Expected: " .. test_data)
            print("    Got: " .. read_data)
        end
    else
        print("  FAIL: Read failed with status " .. status .. "\n")
    end
    
    -- Test 4: Try to overwrite (should fail - write-once!)
    print("Test 4: WRITE-ONCE - Try to overwrite address 0")
    local new_data = "This should NOT overwrite the original data!"
    status, resp_data = write_block(conn, 0, new_data)
    if status == STATUS_ALREADY_WRITTEN then
        print("  PASS: Write correctly rejected (ALREADY_WRITTEN)\n")
    elseif status == STATUS_OK then
        print("  FAIL: Write-once violation! Overwrite succeeded!\n")
    else
        print("  UNEXPECTED: Status " .. status .. "\n")
    end
    
    -- Test 5: Verify original data is intact
    print("Test 5: Verify original data intact after rejected overwrite")
    status, resp_data, err = read_block(conn, 0)
    if status == STATUS_OK then
        local read_data = string.sub(resp_data, 1, #test_data)
        if read_data == test_data then
            print("  PASS: Original data preserved!\n")
        else
            print("  FAIL: Data corruption detected!\n")
        end
    else
        print("  FAIL: Read failed\n")
    end
    
    -- Test 6: Read unwritten address
    print("Test 6: READ from unwritten address 999")
    status, resp_data, err = read_block(conn, 999)
    if status == STATUS_NOT_WRITTEN then
        print("  PASS: Correctly returned NOT_WRITTEN\n")
    else
        print("  FAIL: Expected NOT_WRITTEN, got status " .. status .. "\n")
    end
    
    -- Test 7: Write to different addresses
    print("Test 7: WRITE to multiple addresses (1, 2, 3)")
    local all_ok = true
    for i = 1, 3 do
        local data = "Block data for address " .. i
        status, resp_data = write_block(conn, i, data)
        if status ~= STATUS_OK then
            print("  FAIL: Write to address " .. i .. " failed\n")
            all_ok = false
            break
        end
    end
    if all_ok then
        print("  PASS: All writes succeeded\n")
    end
    
    -- Test 8: Read back all addresses
    print("Test 8: READ back all written addresses")
    all_ok = true
    for i = 0, 3 do
        status, resp_data, err = read_block(conn, i)
        if status ~= STATUS_OK then
            print("  FAIL: Read from address " .. i .. " failed\n")
            all_ok = false
            break
        end
    end
    if all_ok then
        print("  PASS: All reads succeeded\n")
    end
    
    -- Close connection
    socket.close(conn)
    
    print("=== Tests Complete ===")
end

-- Run tests in coroutine
lunet.spawn(function()
    run_tests()
end)
