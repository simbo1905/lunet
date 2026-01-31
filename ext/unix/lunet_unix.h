#ifndef LUNET_UNIX_H
#define LUNET_UNIX_H

#include "lunet_lua.h"

int lunet_unix_listen(lua_State *L);
int lunet_unix_accept(lua_State *L);
int lunet_unix_getpeername(lua_State *L);
int lunet_unix_close(lua_State *L);
int lunet_unix_read(lua_State *L);
int lunet_unix_write(lua_State *L);
int lunet_unix_connect(lua_State *L);
int lunet_unix_set_read_buffer_size(lua_State *L);

#endif // LUNET_UNIX_H
