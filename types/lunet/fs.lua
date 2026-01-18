---@meta

---@class fs
local fs = {}

---Open a file
---@param path string The path to the file
---@param mode string The mode to open the file in ("r", "w", "a")
---@return integer|nil fd The file descriptor or nil on error
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'r')
---if err then
---    print('Error opening file: ' .. err)
---end
---print('File opened: ' .. file)
---```
function fs.open(path, mode) end

---Close a file
---@param fd integer The file descriptor to close
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'r')
---if err then
---    print('Error opening file: ' .. err)
---end
---fs.close(file)
---```
function fs.close(fd) end

---Get the size of a file
---@param path string The path to the file
---@return table|nil stat The stat of the file or nil on error
---@return string|nil error Error message if failed
function fs.stat(path) end

---Read from a file
---@param fd integer The file descriptor to read from
---@param size integer The number of bytes to read
---@return string|nil data The data read from the file or nil on error
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'r')
---if err then
---    print('Error opening file: ' .. err)
---end
---local data, err = fs.read(file, 1024)
---if err then
---    print('Error reading file: ' .. err)
---end
---print('Data read: ' .. data)
---```
function fs.read(fd, size) end

---Write to a file
---@param fd integer The file descriptor to write to
---@param data string The data to write to the file
---@return integer|nil written Number of bytes written or nil on error
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'w')
---if err then
---    print('Error opening file: ' .. err)
---end
---fs.write(file, 'Hello, world!')
---```
function fs.write(fd, data) end

---Read from a file at a specific offset (positioned read)
---@param fd integer The file descriptor to read from
---@param size integer The number of bytes to read
---@param offset integer The byte offset to read from
---@return string|nil data The data read from the file or nil on error
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'r')
---if file then
---    local data, err = fs.pread(file, 1024, 0)  -- Read 1KB at offset 0
---    fs.close(file)
---end
---```
function fs.pread(fd, size, offset) end

---Write to a file at a specific offset (positioned write)
---@param fd integer The file descriptor to write to
---@param data string The data to write to the file
---@param offset integer The byte offset to write at
---@return integer|nil written Number of bytes written or nil on error
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'w+')
---if file then
---    fs.pwrite(file, 'Hello', 0)   -- Write at offset 0
---    fs.pwrite(file, 'World', 100) -- Write at offset 100
---    fs.close(file)
---end
---```
function fs.pwrite(fd, data, offset) end

---Sync file to disk for durability
---@param fd integer The file descriptor to sync
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'w')
---if file then
---    fs.write(file, 'Important data')
---    fs.fsync(file)  -- Ensure data is on disk
---    fs.close(file)
---end
---```
function fs.fsync(fd) end

---Truncate or extend file to specified size
---@param fd integer The file descriptor
---@param size integer The new file size in bytes
---@return string|nil error Error message if failed
---@usage
---```lua
---local fs = require('lunet.fs')
---local file, err = fs.open('test.txt', 'w+')
---if file then
---    fs.ftruncate(file, 4096)  -- Extend/truncate to 4KB
---    fs.close(file)
---end
---```
function fs.ftruncate(fd, size) end

---Scan a directory
---@param path string The path to the directory
---@return table|nil entries The entries in the directory or nil on error
---@return string|nil error Error message if failed
function fs.scandir(path) end

return fs
