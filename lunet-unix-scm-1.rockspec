rockspec_format = "3.0"
package = "lunet-unix"
version = "scm-1"

source = {
    url = "git://github.com/lua-lunet/lunet.git",
    branch = "main"
}

description = {
    summary = "Unix socket driver for lunet",
    detailed = [[
Coroutine-safe Unix socket driver for lunet async I/O framework.
Provides the lunet.unix module.

Features:
- Non-blocking I/O
- Coroutine integration
    ]],
    homepage = "https://github.com/lua-lunet/lunet",
    license = "MIT",
    labels = { "network", "unix", "socket", "async", "lunet" }
}

dependencies = {
    "lua >= 5.1",
    "lunet >= scm-1",
    "luarocks-build-xmake"
}

external_dependencies = {
    LUAJIT = {
        header = "luajit.h"
    },
    LIBUV = {
        header = "uv.h"
    }
}

build = {
    type = "xmake",
    variables = {
        XMAKE_TARGET = "lunet-unix"
    },
    copy_directories = {}
}
