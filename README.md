# Lunet

A high-performance coroutine-based networking library for LuaJIT, built on top of libuv.

[中文文档](README-CN.md)

> This project is based on [xialeistudio/lunet](https://github.com/xialeistudio/lunet) by [夏磊 (Xia Lei)](https://github.com/xialeistudio). See also his excellent write-up: [Lunet: Design and Implementation of a High-Performance Coroutine Network Library](https://www.ddhigh.com/en/2025/07/12/lunet-high-performance-coroutine-network-library/).

## Build

```bash
# Default SQLite build
make build

# Build with tracing (debug mode)
make build-debug
```

## RealWorld Conduit Demo

The implementation of the [RealWorld "Conduit"](https://github.com/gothinkster/realworld) API is in `app/`.

```bash
# 1. Initialize SQLite database
sqlite3 conduit.db < app/schema_sqlite.sql

# 2. Start the server (port 8080)
./build/lunet app/main.lua

# 3. Run integration tests
./bin/test_api.sh
```

## Core Modules

All networking MUST be called within a coroutine spawned via `lunet.spawn`.

### TCP / Unix Sockets (`lunet.socket`)

```lua
local socket = require("lunet.socket")

-- Server
local listener = socket.listen("tcp", "127.0.0.1", 8080)
local client = socket.accept(listener)

-- Client
local conn = socket.connect("127.0.0.1", 8080)

-- I/O
local data = socket.read(conn)
socket.write(conn, "hello")
socket.close(conn)
```

### UDP (`lunet.udp`)

```lua
local udp = require("lunet.udp")

-- Bind
local h = udp.bind("127.0.0.1", 20001)

-- I/O
udp.send(h, "127.0.0.1", 20002, "payload")
local data, host, port = udp.recv(h)

udp.close(h)
```

## Safety: Zero-Cost Tracing

Build with `make build-debug` to enable coroutine reference tracking and stack integrity checks. The runtime will assert and crash on leaks or stack pollution.

## Testing

```bash
make test    # Unit tests
make stress  # Concurrent load test with tracing
```

## License

MIT
