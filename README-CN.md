# Lunet

基于协程的高性能 LuaJIT 网络库，构建于 libuv 之上。

[English Documentation](README.md)

> 本项目基于 [夏磊 (Xia Lei)](https://github.com/xialeistudio) 的 [xialeistudio/lunet](https://github.com/xialeistudio/lunet)。详见他的精彩文章：[Lunet：高性能协程网络库的设计与实现](https://www.ddhigh.com/2025/07/12/lunet-high-performance-coroutine-network-library/)。

## 构建

```bash
# 默认 SQLite 构建
make build

# 调试模式构建（启用追踪）
make build-debug
```

## RealWorld Conduit 示例

[RealWorld "Conduit"](https://github.com/gothinkster/realworld) API 实现位于 `app/` 目录。

```bash
# 1. 初始化 SQLite 数据库
sqlite3 conduit.db < app/schema_sqlite.sql

# 2. 启动服务器（端口 8080）
./build/lunet app/main.lua

# 3. 运行集成测试
./bin/test_api.sh
```

## 核心模块

所有网络操作必须在通过 `lunet.spawn` 创建的协程中调用。

### TCP / Unix 套接字 (`lunet.socket`)

```lua
local socket = require("lunet.socket")

-- 服务器
local listener = socket.listen("tcp", "127.0.0.1", 8080)
local client = socket.accept(listener)

-- 客户端
local conn = socket.connect("127.0.0.1", 8080)

-- I/O
local data = socket.read(conn)
socket.write(conn, "hello")
socket.close(conn)
```

### UDP (`lunet.udp`)

```lua
local udp = require("lunet.udp")

-- 绑定
local h = udp.bind("127.0.0.1", 20001)

-- I/O
udp.send(h, "127.0.0.1", 20002, "payload")
local data, host, port = udp.recv(h)

udp.close(h)
```

## 安全性：零开销追踪

使用 `make build-debug` 构建可启用协程引用追踪和栈完整性检查。运行时会在检测到泄漏或栈污染时触发断言并崩溃。

## 测试

```bash
make test    # 单元测试
make stress  # 带追踪的并发负载测试
```

## 许可证

MIT
