# Lunet

A high-performance coroutine-based networking library for LuaJIT, built on top of libuv.

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language](https://img.shields.io/badge/Language-C%2BLuaJIT-green.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)]()

[中文文档](README-CN.md)

## Overview

Lunet is a coroutine-based networking library that provides synchronous APIs with asynchronous execution. It combines the power of C, LuaJIT, and libuv to deliver high-performance I/O operations while maintaining clean, readable code.

### Key Features

- **Coroutine-based**: Write synchronous-style code that runs asynchronously
- **High Performance**: Built on LuaJIT and libuv for optimal performance
- **Comprehensive**: Includes filesystem, networking, database, signal, and timer operations
- **Type Safety**: Complete type definitions for IDE support
- **Cross-platform**: Works on Linux, macOS, and Windows

## Architecture

- **C Core**: High-performance native implementation
- **LuaJIT**: Fast Lua execution with FFI support
- **libuv**: Cross-platform asynchronous I/O
- **Coroutines**: Lua coroutines for concurrent programming

## Modules

### Core Module (`lunet`)
- `spawn(func)`: Create and run a new coroutine
- `sleep(ms)`: Suspend coroutine for specified milliseconds

### Socket Module (`lunet.socket`)
- `listen(protocol, host, port)`: Create TCP server
- `accept(listener)`: Accept incoming connections
- `connect(host, port)`: Connect to remote server
- `read(client)`: Read data from socket
- `write(client, data)`: Write data to socket
- `getpeername(client)`: Get peer address
- `close(handle)`: Close socket
- `set_read_buffer_size(size)`: Configure buffer size

### Filesystem Module (`lunet.fs`)
- `open(path, mode)`: Open file
- `close(fd)`: Close file
- `read(fd, size)`: Read from file
- `write(fd, data)`: Write to file
- `stat(path)`: Get file statistics
- `scandir(path)`: List directory contents

### Database Module (`lunet.db`)

The database module provides a unified API for database operations. The backend is selected at compile time via CMake option.

- `open(params)`: Open database connection
- `close(conn)`: Close database connection
- `query(conn, sql)`: Execute SELECT query, returns array of rows
- `exec(conn, sql)`: Execute INSERT/UPDATE/DELETE, returns `{affected_rows, last_insert_id}`

Supported backends: MySQL, PostgreSQL, SQLite3 (or none)

### Signal Module (`lunet.signal`)
- `wait(signal)`: Wait for system signal

## Installation

### Prerequisites

- CMake 3.10+
- LuaJIT 2.1+
- libuv 1.x
- Database library (optional, based on chosen backend):
  - MySQL: libmysqlclient
  - PostgreSQL: libpq
  - SQLite3: libsqlite3

### Build from Source

```bash
git clone https://github.com/xialeistudio/lunet.git
cd lunet
mkdir build && cd build

# Build without database (default)
cmake ..
make

# Build with MySQL
cmake -DLUNET_DB=mysql ..
make

# Build with PostgreSQL
cmake -DLUNET_DB=postgres ..
make

# Build with SQLite3
cmake -DLUNET_DB=sqlite3 ..
make
```

### Build with Custom Library Paths

If you have libraries installed in non-standard locations, you can specify the paths explicitly:

```bash
cmake .. \
  -DLUAJIT_INCLUDE_DIR=/path/to/luajit/include \
  -DLUAJIT_LIBRARY=/path/to/luajit/lib/libluajit-5.1.dylib \
  -DLIBUV_INCLUDE_DIR=/path/to/libuv/include \
  -DLIBUV_LIBRARY=/path/to/libuv/lib/libuv.dylib

# For MySQL backend:
cmake -DLUNET_DB=mysql .. \
  -DMYSQL_INCLUDE_DIR=/path/to/mysql/include \
  -DMYSQL_LIBRARY=/path/to/mysql/lib/libmysqlclient.dylib

# For PostgreSQL backend:
cmake -DLUNET_DB=postgres .. \
  -DPQ_INCLUDE_DIR=/path/to/postgresql/include \
  -DPQ_LIBRARY=/path/to/postgresql/lib/libpq.dylib

# For SQLite3 backend:
cmake -DLUNET_DB=sqlite3 .. \
  -DSQLITE3_INCLUDE_DIR=/path/to/sqlite3/include \
  -DSQLITE3_LIBRARY=/path/to/sqlite3/lib/libsqlite3.dylib
```

### Database Backend Options

Use the `LUNET_DB` CMake option to select a database backend:

| Value | Backend | Library Required |
|-------|---------|------------------|
| `none` | No database (default) | None |
| `mysql` | MySQL | libmysqlclient |
| `postgres` | PostgreSQL | libpq |
| `sqlite3` | SQLite3 | libsqlite3 |

### macOS with Homebrew

```bash
# Install core dependencies
brew install luajit libuv

# Install database libraries as needed
brew install mysql          # For MySQL backend
brew install libpq          # For PostgreSQL backend
brew install sqlite3        # For SQLite3 backend

# Build with your chosen backend
mkdir build && cd build
cmake -DLUNET_DB=postgres ..
make
```

### Ubuntu/Debian

```bash
# Install core dependencies
sudo apt update
sudo apt install build-essential cmake libluajit-5.1-dev libuv1-dev

# Install database libraries as needed
sudo apt install libmysqlclient-dev   # For MySQL
sudo apt install libpq-dev            # For PostgreSQL
sudo apt install libsqlite3-dev       # For SQLite3

# Build with your chosen backend
mkdir build && cd build
cmake -DLUNET_DB=sqlite3 ..
make
```

### CentOS/RHEL

```bash
# Install core dependencies
sudo yum install gcc gcc-c++ cmake luajit-devel libuv-devel

# Install database libraries as needed
sudo yum install mysql-devel           # For MySQL
sudo yum install postgresql-devel      # For PostgreSQL
sudo yum install sqlite-devel          # For SQLite3

# Build with your chosen backend
mkdir build && cd build
cmake -DLUNET_DB=postgres ..
make
```

## Quick Start

### Simple HTTP Server

```lua
local lunet = require('lunet')
local socket = require('lunet.socket')

-- Create server
local listener, err = socket.listen("tcp", "127.0.0.1", 8080)
if not listener then
    error("Failed to listen: " .. err)
end

print("Server listening on http://127.0.0.1:8080")

-- Accept connections
lunet.spawn(function()
    while true do
        local client, err = socket.accept(listener)
        if client then
            -- Handle client in new coroutine
            lunet.spawn(function()
                local data, err = socket.read(client)
                if data then
                    local response = "HTTP/1.1 200 OK\r\n" ..
                                   "Content-Type: text/plain\r\n" ..
                                   "Content-Length: 13\r\n\r\n" ..
                                   "Hello, World!"
                    socket.write(client, response)
                end
                socket.close(client)
            end)
        end
    end
end)
```

### File Operations

```lua
local lunet = require('lunet')
local fs = require('lunet.fs')

lunet.spawn(function()
    -- Write file
    local file, err = fs.open('example.txt', 'w')
    if file then
        fs.write(file, 'Hello, Lunet!')
        fs.close(file)
    end
    
    -- Read file
    local file, err = fs.open('example.txt', 'r')
    if file then
        local data, err = fs.read(file, 1024)
        if data then
            print('File content:', data)
        end
        fs.close(file)
    end
    
    -- Directory listing
    local entries, err = fs.scandir('.')
    if entries then
        for i, entry in ipairs(entries) do
            print('Entry:', entry.name, entry.type)
        end
    end
end)
```

### Database Operations

The `lunet.db` module provides a unified API regardless of which database backend was compiled in.

**Note:** You must compile lunet with a database backend enabled to use this module. See [Database Backend Options](#database-backend-options) for details.

```lua
local lunet = require('lunet')
local db = require('lunet.db')

lunet.spawn(function()
    -- Connect to database
    local conn, err = db.open({
        host = "localhost",
        port = 3306,
        user = "root",
        password = "password",
        database = "testdb"
    })
    
    if conn then
        -- Execute query
        local result, err = db.query(conn, "SELECT * FROM users")
        if result then
            for i, row in ipairs(result) do
                print('User:', row.name, row.email)
            end
        end
        
        -- Execute update
        local result, err = db.exec(conn, "INSERT INTO users (name, email) VALUES ('John', 'john@example.com')")
        if result then
            print('Affected rows:', result.affected_rows)
            print('Last insert ID:', result.last_insert_id)
        end
        
        db.close(conn)
    end
end)
```

#### Running the Examples

Complete working examples are provided in the `examples/` directory:

**SQLite3** (no server required - runs purely local):
```bash
cd build
cmake -DLUNET_DB=sqlite3 .. && make
./lunet ../examples/sqlite3.lua
```

**MySQL** (requires MySQL server and `lunet_demo` database):
```bash
cd build
cmake -DLUNET_DB=mysql .. && make
./lunet ../examples/demo_mysql.lua
```

**PostgreSQL** (requires PostgreSQL server and `lunet_demo` database):
```bash
cd build
cmake -DLUNET_DB=postgres .. && make
./lunet ../examples/demo_postgresql.lua
```

## Usage

Run your Lua script with lunet:

```bash
./lunet script.lua
```

## Type Definitions

Lunet includes comprehensive type definitions for IDE support. The type files are located in the `types/` directory:

- `types/lunet.lua` - Core module types
- `types/lunet/socket.lua` - Socket module types  
- `types/lunet/fs.lua` - Filesystem module types
- `types/lunet/db.lua` - Database module types (unified API)
- `types/lunet/signal.lua` - Signal module types

## Performance

Lunet is designed for high performance:

- **Zero-copy**: Minimal memory allocation and copying
- **Coroutines**: Efficient cooperative multitasking
- **libuv**: Battle-tested asynchronous I/O
- **LuaJIT**: Just-in-time compilation for fast execution

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### Development

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [LuaJIT](https://luajit.org/) - Fast Lua implementation
- [libuv](https://libuv.org/) - Cross-platform asynchronous I/O
- [MySQL](https://www.mysql.com/) - Database connectivity
- [PostgreSQL](https://www.postgresql.org/) - Database connectivity
- [SQLite](https://www.sqlite.org/) - Embedded database
