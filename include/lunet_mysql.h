#ifndef LUNET_MYSQL_H
#define LUNET_MYSQL_H

#include <lua.h>

int lunet_mysql_open(lua_State* L);
int lunet_mysql_close(lua_State* L);
int lunet_mysql_query(lua_State* L);
int lunet_mysql_exec(lua_State* L);
#endif