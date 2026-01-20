# Lunet

基于协程的高性能 LuaJIT 网络库，构建于 libuv 之上。

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language](https://img.shields.io/badge/Language-C%2BLuaJIT-green.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)]()

[English Documentation](README.md)

## 概述

Lunet 是一个基于协程的网络库，提供同步风格的 API，底层异步执行。它结合了 C、LuaJIT 和 libuv 的强大功能，在保持代码清晰可读的同时提供高性能的 I/O 操作。

### 核心特性

- **基于协程**：编写同步风格的代码，异步执行
- **高性能**：构建于 LuaJIT 和 libuv 之上，性能优异
- **功能全面**：包含文件系统、网络、数据库、信号和定时器操作
- **类型安全**：完整的类型定义，支持 IDE 智能提示
- **跨平台**：支持 Linux、macOS 和 Windows

## 架构

- **C 核心**：高性能的原生实现
- **LuaJIT**：快速的 Lua 执行环境，支持 FFI
- **libuv**：跨平台异步 I/O 库
- **协程**：使用 Lua 协程实现并发编程

## 模块

### 核心模块 (`lunet`)
- `spawn(func)`：创建并运行新协程
- `sleep(ms)`：挂起协程指定毫秒数

### 套接字模块 (`lunet.socket`)
- `listen(protocol, host, port)`：创建 TCP 服务器
- `accept(listener)`：接受传入连接
- `connect(host, port)`：连接到远程服务器
- `read(client)`：从套接字读取数据
- `write(client, data)`：向套接字写入数据
- `getpeername(client)`：获取对等地址
- `close(handle)`：关闭套接字
- `set_read_buffer_size(size)`：配置缓冲区大小

### 文件系统模块 (`lunet.fs`)
- `open(path, mode)`：打开文件
- `close(fd)`：关闭文件
- `read(fd, size)`：从文件读取
- `write(fd, data)`：写入文件
- `stat(path)`：获取文件统计信息
- `scandir(path)`：列出目录内容

### 数据库模块 (`lunet.db`)

数据库模块提供统一的数据库操作 API。后端在编译时通过 CMake 选项选择。

- `open(params)`：打开数据库连接
- `close(conn)`：关闭数据库连接
- `query(conn, sql)`：执行 SELECT 查询，返回行数组
- `exec(conn, sql)`：执行 INSERT/UPDATE/DELETE，返回 `{affected_rows, last_insert_id}`
- `escape(str)`：转义字符串以防止 SQL 注入

支持的后端：MySQL、PostgreSQL、SQLite3（或无）

### 信号模块 (`lunet.signal`)
- `wait(signal)`：等待系统信号

## 安装

### 前置条件

- CMake 3.10+
- LuaJIT 2.1+
- libuv 1.x
- 数据库库（可选，根据选择的后端）：
  - MySQL：libmysqlclient
  - PostgreSQL：libpq
  - SQLite3：libsqlite3

### 从源码构建

```bash
git clone https://github.com/xialeistudio/lunet.git
cd lunet
mkdir build && cd build

# 不带数据库构建（默认）
cmake ..
make

# 带 MySQL 构建
cmake -DLUNET_DB=mysql ..
make

# 带 PostgreSQL 构建
cmake -DLUNET_DB=postgres ..
make

# 带 SQLite3 构建
cmake -DLUNET_DB=sqlite3 ..
make
```

### 指定库路径构建

如果您的库安装在非标准位置，可以显式指定路径：

```bash
cmake .. \
  -DLUAJIT_INCLUDE_DIR=/path/to/luajit/include \
  -DLUAJIT_LIBRARY=/path/to/luajit/lib/libluajit-5.1.dylib \
  -DLIBUV_INCLUDE_DIR=/path/to/libuv/include \
  -DLIBUV_LIBRARY=/path/to/libuv/lib/libuv.dylib

# MySQL 后端：
cmake -DLUNET_DB=mysql .. \
  -DMYSQL_INCLUDE_DIR=/path/to/mysql/include \
  -DMYSQL_LIBRARY=/path/to/mysql/lib/libmysqlclient.dylib

# PostgreSQL 后端：
cmake -DLUNET_DB=postgres .. \
  -DPQ_INCLUDE_DIR=/path/to/postgresql/include \
  -DPQ_LIBRARY=/path/to/postgresql/lib/libpq.dylib

# SQLite3 后端：
cmake -DLUNET_DB=sqlite3 .. \
  -DSQLITE3_INCLUDE_DIR=/path/to/sqlite3/include \
  -DSQLITE3_LIBRARY=/path/to/sqlite3/lib/libsqlite3.dylib
```

### 数据库后端选项

使用 `LUNET_DB` CMake 选项选择数据库后端：

| 值 | 后端 | 需要的库 |
|-----|---------|------------------|
| `none` | 无数据库（默认） | 无 |
| `mysql` | MySQL | libmysqlclient |
| `postgres` | PostgreSQL | libpq |
| `sqlite3` | SQLite3 | libsqlite3 |

### macOS 使用 Homebrew

```bash
# 安装核心依赖
brew install luajit libuv

# 根据需要安装数据库库
brew install mysql          # MySQL 后端
brew install libpq          # PostgreSQL 后端
brew install sqlite3        # SQLite3 后端

# 使用选择的后端构建
mkdir build && cd build
cmake -DLUNET_DB=postgres ..
make
```

### Ubuntu/Debian

```bash
# 安装核心依赖
sudo apt update
sudo apt install build-essential cmake libluajit-5.1-dev libuv1-dev

# 根据需要安装数据库库
sudo apt install libmysqlclient-dev   # MySQL
sudo apt install libpq-dev            # PostgreSQL
sudo apt install libsqlite3-dev       # SQLite3

# 使用选择的后端构建
mkdir build && cd build
cmake -DLUNET_DB=sqlite3 ..
make
```

### CentOS/RHEL

```bash
# 安装核心依赖
sudo yum install gcc gcc-c++ cmake luajit-devel libuv-devel

# 根据需要安装数据库库
sudo yum install mysql-devel           # MySQL
sudo yum install postgresql-devel      # PostgreSQL
sudo yum install sqlite-devel          # SQLite3

# 使用选择的后端构建
mkdir build && cd build
cmake -DLUNET_DB=postgres ..
make
```

## 快速开始

### 简单的 HTTP 服务器

```lua
local lunet = require('lunet')
local socket = require('lunet.socket')

-- 创建服务器
local listener, err = socket.listen("tcp", "127.0.0.1", 8080)
if not listener then
    error("监听失败: " .. err)
end

print("服务器正在监听 http://127.0.0.1:8080")

-- 接受连接
lunet.spawn(function()
    while true do
        local client, err = socket.accept(listener)
        if client then
            -- 在新协程中处理客户端
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

### 文件操作

```lua
local lunet = require('lunet')
local fs = require('lunet.fs')

lunet.spawn(function()
    -- 写文件
    local file, err = fs.open('example.txt', 'w')
    if file then
        fs.write(file, 'Hello, Lunet!')
        fs.close(file)
    end
    
    -- 读文件
    local file, err = fs.open('example.txt', 'r')
    if file then
        local data, err = fs.read(file, 1024)
        if data then
            print('文件内容:', data)
        end
        fs.close(file)
    end
    
    -- 目录列表
    local entries, err = fs.scandir('.')
    if entries then
        for i, entry in ipairs(entries) do
            print('条目:', entry.name, entry.type)
        end
    end
end)
```

### 数据库操作

`lunet.db` 模块提供统一的 API，无论编译了哪个数据库后端。

**注意**：您必须使用启用的数据库后端编译 lunet 才能使用此模块。详情请参阅[数据库后端选项](#数据库后端选项)。

```lua
local lunet = require('lunet')
local db = require('lunet.db')

lunet.spawn(function()
    -- 连接数据库
    local conn, err = db.open({
        host = "localhost",
        port = 3306,
        user = "root",
        password = "password",
        database = "testdb"
    })
    
    if conn then
        -- 执行查询
        local result, err = db.query(conn, "SELECT * FROM users")
        if result then
            for i, row in ipairs(result) do
                print('用户:', row.name, row.email)
            end
        end
        
        -- 执行更新
        local result, err = db.exec(conn, "INSERT INTO users (name, email) VALUES ('John', 'john@example.com')")
        if result then
            print('影响行数:', result.affected_rows)
            print('最后插入 ID:', result.last_insert_id)
        end
        
        db.close(conn)
    end
end)
```

#### 运行示例

完整的工作示例在 `examples/` 目录中提供：

**SQLite3**（无需服务器 - 纯本地运行）：
```bash
cd build
cmake -DLUNET_DB=sqlite3 .. && make
./lunet ../examples/sqlite3.lua
```

**MySQL**（需要 MySQL 服务器和 `lunet_demo` 数据库）：
```bash
cd build
cmake -DLUNET_DB=mysql .. && make
./lunet ../examples/demo_mysql.lua
```

**PostgreSQL**（需要 PostgreSQL 服务器和 `lunet_demo` 数据库）：
```bash
cd build
cmake -DLUNET_DB=postgres .. && make
./lunet ../examples/demo_postgresql.lua
```

## 使用方法

使用 lunet 运行您的 Lua 脚本：

```bash
./lunet script.lua
```

## 类型定义

Lunet 包含完整的类型定义以支持 IDE 智能提示。类型文件位于 `types/` 目录：

- `types/lunet.lua` - 核心模块类型
- `types/lunet/socket.lua` - 套接字模块类型  
- `types/lunet/fs.lua` - 文件系统模块类型
- `types/lunet/db.lua` - 数据库模块类型（统一 API）
- `types/lunet/signal.lua` - 信号模块类型

## 性能

Lunet 专为高性能而设计：

- **零拷贝**：最少的内存分配和拷贝
- **协程**：高效的协作式多任务
- **libuv**：经过实战考验的异步 I/O
- **LuaJIT**：即时编译实现快速执行

## 贡献

欢迎贡献！请随时提交问题和拉取请求。

### 开发

1. Fork 仓库
2. 创建功能分支
3. 进行更改
4. 添加测试（如适用）
5. 提交拉取请求

## 许可证

本项目采用 MIT 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件。

## 致谢

- [LuaJIT](https://luajit.org/) - 快速的 Lua 实现
- [libuv](https://libuv.org/) - 跨平台异步 I/O
- [MySQL](https://www.mysql.com/) - 数据库连接
- [PostgreSQL](https://www.postgresql.org/) - 数据库连接
- [SQLite](https://www.sqlite.org/) - 嵌入式数据库
