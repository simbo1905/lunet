#include "postgres.h"

#include <lauxlib.h>
#include <libpq-fe.h>
#include <lua.h>
#include <stdlib.h>
#include <string.h>

#include "co.h"
#include "uv.h"

typedef struct {
  uv_work_t req;
  lua_State* L;
  int co_ref;

  PGconn* conn;
  char err[256];

  char conninfo[1024];
} db_open_ctx_t;

typedef struct {
  PGconn* conn;
  uv_mutex_t mu;
} db_conn_t;

static void db_open_work_cb(uv_work_t* req) {
  db_open_ctx_t* ctx = (db_open_ctx_t*)req->data;

  ctx->conn = PQconnectdb(ctx->conninfo);
  if (PQstatus(ctx->conn) != CONNECTION_OK) {
    snprintf(ctx->err, sizeof(ctx->err), "%s", PQerrorMessage(ctx->conn));
    PQfinish(ctx->conn);
    ctx->conn = NULL;
    return;
  }
}

static void db_open_after_cb(uv_work_t* req, int status) {
  db_open_ctx_t* ctx = (db_open_ctx_t*)req->data;
  lua_State* L = ctx->L;

  lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->co_ref);
  luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
  if (!lua_isthread(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "invalid coroutine in db.open\n");
    if (ctx->conn) PQfinish(ctx->conn);
    ctx->conn = NULL;
    free(ctx);
    return;
  }
  lua_State* co = lua_tothread(L, -1);
  lua_pop(L, 1);

  if (ctx->conn) {
    db_conn_t* wrapper = (db_conn_t*)lua_newuserdata(co, sizeof(db_conn_t));
    wrapper->conn = ctx->conn;
    uv_mutex_init(&wrapper->mu);
    lua_pushnil(co);
  } else {
    lua_pushnil(co);
    lua_pushstring(co, ctx->err);
  }
  lua_resume(co, 2);
  free(ctx);
}

int lunet_db_open(lua_State* L) {
  if (lunet_ensure_coroutine(L, "db.open")) {
    return lua_error(L);
  }
  if (lua_gettop(L) < 1 || !lua_istable(L, 1)) {
    lua_pushstring(L, "db.open requires params table");
    return lua_error(L);
  }

  db_open_ctx_t* ctx = malloc(sizeof(db_open_ctx_t));
  if (!ctx) {
    lua_pushnil(L);
    lua_pushstring(L, "db.open: out of memory");
    return lua_error(L);
  }
  memset(ctx->err, 0, sizeof(ctx->err));
  ctx->L = L;
  ctx->req.data = ctx;

  char host[256] = "localhost";
  int port = 5432;
  char user[256] = "";
  char password[256] = "";
  char database[256] = "";

  lua_getfield(L, 1, "host");
  if (lua_isstring(L, -1)) {
    strncpy(host, lua_tostring(L, -1), sizeof(host) - 1);
    host[sizeof(host) - 1] = '\0';
  }
  lua_getfield(L, 1, "port");
  if (lua_isnumber(L, -1)) port = lua_tointeger(L, -1);
  lua_getfield(L, 1, "user");
  if (lua_isstring(L, -1)) {
    strncpy(user, lua_tostring(L, -1), sizeof(user) - 1);
    user[sizeof(user) - 1] = '\0';
  }
  lua_getfield(L, 1, "password");
  if (lua_isstring(L, -1)) {
    strncpy(password, lua_tostring(L, -1), sizeof(password) - 1);
    password[sizeof(password) - 1] = '\0';
  }
  lua_getfield(L, 1, "database");
  if (lua_isstring(L, -1)) {
    strncpy(database, lua_tostring(L, -1), sizeof(database) - 1);
    database[sizeof(database) - 1] = '\0';
  }
  lua_pop(L, 5);

  snprintf(ctx->conninfo, sizeof(ctx->conninfo),
           "host='%s' port='%d' user='%s' password='%s' dbname='%s'",
           host, port, user, password, database);
  
  /* printf("DEBUG: conninfo='%s'\n", ctx->conninfo); */

  lua_pushthread(L);
  ctx->co_ref = luaL_ref(L, LUA_REGISTRYINDEX);

  int ret = uv_queue_work(uv_default_loop(), &ctx->req, db_open_work_cb, db_open_after_cb);
  if (ret < 0) {
    luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
    free(ctx);
    lua_pushnil(L);
    lua_pushfstring(L, "db.open: uv_queue_work failed: %s", uv_strerror(ret));
    return lua_error(L);
  }

  return lua_yield(L, 0);
}

int lunet_db_close(lua_State* L) {
  if (lunet_ensure_coroutine(L, "db.close")) {
    return lua_error(L);
  }
  if (lua_gettop(L) < 1) {
    lua_pushstring(L, "db.close requires a connection");
    return 1;
  }
  if (!lua_isuserdata(L, 1)) {
    lua_pushstring(L, "db.close requires a connection");
    return 1;
  }

  db_conn_t* wrapper = (db_conn_t*)lua_touserdata(L, 1);
  if (!wrapper || !wrapper->conn) {
    lua_pushstring(L, "invalid connection");
    return 1;
  }

  uv_mutex_lock(&wrapper->mu);
  PQfinish(wrapper->conn);
  wrapper->conn = NULL;
  uv_mutex_unlock(&wrapper->mu);
  uv_mutex_destroy(&wrapper->mu);
  lua_pushnil(L);
  return 1;
}

typedef struct {
  uv_work_t req;
  lua_State* L;
  int co_ref;

  db_conn_t* wrapper;
  char* query;

  PGresult* result;
  char err[256];
} db_query_ctx_t;

static void db_query_work_cb(uv_work_t* req) {
  db_query_ctx_t* ctx = (db_query_ctx_t*)req->data;

  uv_mutex_lock(&ctx->wrapper->mu);
  PGconn* conn = ctx->wrapper->conn;
  if (!conn) {
    snprintf(ctx->err, sizeof(ctx->err), "%s", "invalid connection");
    uv_mutex_unlock(&ctx->wrapper->mu);
    ctx->result = NULL;
    return;
  }

  ctx->result = PQexec(conn, ctx->query);
  ExecStatusType status = PQresultStatus(ctx->result);

  if (status != PGRES_TUPLES_OK && status != PGRES_COMMAND_OK) {
    snprintf(ctx->err, sizeof(ctx->err), "%s", PQerrorMessage(conn));
    PQclear(ctx->result);
    ctx->result = NULL;
    uv_mutex_unlock(&ctx->wrapper->mu);
    return;
  }
  uv_mutex_unlock(&ctx->wrapper->mu);
}

static void db_query_after_cb(uv_work_t* req, int status) {
  db_query_ctx_t* ctx = (db_query_ctx_t*)req->data;
  lua_State* L = ctx->L;

  lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->co_ref);
  luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
  if (!lua_isthread(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "invalid coroutine in db.query\n");
    if (ctx->result) PQclear(ctx->result);
    free(ctx->query);
    free(ctx);
    return;
  }
  lua_State* co = lua_tothread(L, -1);
  lua_pop(L, 1);

  if (ctx->result) {
    lua_newtable(co);
    int nrows = PQntuples(ctx->result);
    int ncols = PQnfields(ctx->result);

    for (int i = 0; i < nrows; i++) {
      lua_newtable(co);
      for (int j = 0; j < ncols; j++) {
        const char* fname = PQfname(ctx->result, j);
        lua_pushstring(co, fname);

        if (PQgetisnull(ctx->result, i, j)) {
          lua_pushnil(co);
        } else {
          const char* val = PQgetvalue(ctx->result, i, j);
          Oid ftype = PQftype(ctx->result, j);

          switch (ftype) {
            case 21:   // INT2OID
            case 23:   // INT4OID
            case 20:   // INT8OID
              lua_pushinteger(co, strtoll(val, NULL, 10));
              break;
            case 700:  // FLOAT4OID
            case 701:  // FLOAT8OID
            case 1700: // NUMERICOID
              lua_pushnumber(co, strtod(val, NULL));
              break;
            case 16:   // BOOLOID
              lua_pushboolean(co, val[0] == 't' || val[0] == 'T');
              break;
            default:
              lua_pushstring(co, val);
              break;
          }
        }
        lua_settable(co, -3);
      }
      lua_rawseti(co, -2, i + 1);
    }

    PQclear(ctx->result);
    ctx->result = NULL;

    lua_pushnil(co);
    lua_resume(co, 2);
  } else {
    lua_pushnil(co);
    lua_pushstring(co, ctx->err);
    lua_resume(co, 2);
  }

  free(ctx->query);
  free(ctx);
}

int lunet_db_query(lua_State* L) {
  if (lunet_ensure_coroutine(L, "db.query")) {
    return lua_error(L);
  }
  if (lua_gettop(L) < 2) {
    lua_pushnil(L);
    lua_pushstring(L, "db.query requires connection and sql string");
    return 2;
  }

  if (!lua_isuserdata(L, 1) && !lua_islightuserdata(L, 1)) {
    lua_pushnil(L);
    lua_pushstring(L, "db.query requires a connection");
    return 2;
  }

  db_conn_t* wrapper = (db_conn_t*)lua_touserdata(L, 1);
  if (!wrapper || !wrapper->conn) {
    lua_pushnil(L);
    lua_pushstring(L, "invalid connection");
    return 2;
  }

  const char* query = luaL_checkstring(L, 2);

  db_query_ctx_t* ctx = malloc(sizeof(db_query_ctx_t));
  if (!ctx) {
    lua_pushstring(L, "out of memory");
    return lua_error(L);
  }
  memset(ctx, 0, sizeof(*ctx));
  ctx->L = L;
  ctx->req.data = ctx;
  ctx->wrapper = wrapper;
  ctx->query = strdup(query);
  if (!ctx->query) {
    free(ctx);
    lua_pushnil(L);
    lua_pushstring(L, "out of memory");
    return 2;
  }

  lua_pushthread(L);
  ctx->co_ref = luaL_ref(L, LUA_REGISTRYINDEX);

  int ret = uv_queue_work(uv_default_loop(), &ctx->req, db_query_work_cb, db_query_after_cb);
  if (ret < 0) {
    luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
    free(ctx->query);
    free(ctx);
    lua_pushnil(L);
    lua_pushstring(L, uv_strerror(ret));
    return 2;
  }

  return lua_yield(L, 0);
}

typedef struct {
  uv_work_t req;
  lua_State* L;
  int co_ref;

  db_conn_t* wrapper;
  char* query;

  long long affected_rows;
  unsigned long long insert_id;
  char err[256];
} db_exec_ctx_t;

static void db_exec_work_cb(uv_work_t* req) {
  db_exec_ctx_t* ctx = (db_exec_ctx_t*)req->data;

  uv_mutex_lock(&ctx->wrapper->mu);
  PGconn* conn = ctx->wrapper->conn;
  if (!conn) {
    snprintf(ctx->err, sizeof(ctx->err), "%s", "invalid connection");
    uv_mutex_unlock(&ctx->wrapper->mu);
    return;
  }

  PGresult* result = PQexec(conn, ctx->query);
  ExecStatusType status = PQresultStatus(result);

  if (status != PGRES_COMMAND_OK && status != PGRES_TUPLES_OK) {
    snprintf(ctx->err, sizeof(ctx->err), "%s", PQerrorMessage(conn));
    PQclear(result);
    uv_mutex_unlock(&ctx->wrapper->mu);
    return;
  }

  const char* affected = PQcmdTuples(result);
  ctx->affected_rows = affected[0] ? strtoll(affected, NULL, 10) : 0;
  ctx->insert_id = (unsigned long long)PQoidValue(result);

  PQclear(result);
  uv_mutex_unlock(&ctx->wrapper->mu);
}

static void db_exec_after_cb(uv_work_t* req, int status) {
  db_exec_ctx_t* ctx = (db_exec_ctx_t*)req->data;
  lua_State* L = ctx->L;

  lua_rawgeti(L, LUA_REGISTRYINDEX, ctx->co_ref);
  luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
  if (!lua_isthread(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "invalid coroutine in db.exec\n");
    free(ctx->query);
    free(ctx);
    return;
  }
  lua_State* co = lua_tothread(L, -1);
  lua_pop(L, 1);

  if (ctx->err[0] != '\0') {
    lua_pushnil(co);
    lua_pushstring(co, ctx->err);
    lua_resume(co, 2);
  } else {
    lua_newtable(co);
    lua_pushstring(co, "affected_rows");
    lua_pushinteger(co, ctx->affected_rows);
    lua_settable(co, -3);
    lua_pushstring(co, "last_insert_id");
    lua_pushinteger(co, ctx->insert_id);
    lua_settable(co, -3);
    lua_pushnil(co);
    lua_resume(co, 2);
  }

  free(ctx->query);
  free(ctx);
}

int lunet_db_exec(lua_State* L) {
  if (lunet_ensure_coroutine(L, "db.exec")) {
    return lua_error(L);
  }
  if (lua_gettop(L) < 2) {
    lua_pushnil(L);
    lua_pushstring(L, "db.exec requires connection and sql string");
    return 2;
  }
  if (!lua_isuserdata(L, 1) && !lua_islightuserdata(L, 1)) {
    lua_pushnil(L);
    lua_pushstring(L, "db.exec requires a connection");
    return 2;
  }

  db_conn_t* wrapper = (db_conn_t*)lua_touserdata(L, 1);
  if (!wrapper || !wrapper->conn) {
    lua_pushnil(L);
    lua_pushstring(L, "invalid connection");
    return 2;
  }

  const char* query = luaL_checkstring(L, 2);

  db_exec_ctx_t* ctx = malloc(sizeof(db_exec_ctx_t));
  if (!ctx) {
    lua_pushnil(L);
    lua_pushstring(L, "out of memory");
    return 2;
  }
  memset(ctx, 0, sizeof(*ctx));
  ctx->L = L;
  ctx->req.data = ctx;
  ctx->wrapper = wrapper;
  ctx->query = strdup(query);
  if (!ctx->query) {
    free(ctx);
    lua_pushnil(L);
    lua_pushstring(L, "out of memory");
    return 2;
  }

  lua_pushthread(L);
  ctx->co_ref = luaL_ref(L, LUA_REGISTRYINDEX);

  int ret = uv_queue_work(uv_default_loop(), &ctx->req, db_exec_work_cb, db_exec_after_cb);
  if (ret < 0) {
    luaL_unref(L, LUA_REGISTRYINDEX, ctx->co_ref);
    free(ctx->query);
    free(ctx);
    lua_pushnil(L);
    lua_pushstring(L, uv_strerror(ret));
    return 2;
  }

  return lua_yield(L, 0);
}

int lunet_db_escape(lua_State* L) {
  luaL_checkstring(L, 1);
  lua_getglobal(L, "string");
  lua_getfield(L, -1, "gsub");
  lua_remove(L, -2); /* remove string table */

  if (!lua_isfunction(L, -1)) {
    return luaL_error(L, "string.gsub is not available");
  }

  lua_pushvalue(L, 1); /* subject */
  lua_pushstring(L, "(['\\\\])"); /* pattern */
  
  lua_newtable(L); /* replacement table */
  lua_pushstring(L, "'");
  lua_pushstring(L, "''");
  lua_settable(L, -3);
  lua_pushstring(L, "\\");
  lua_pushstring(L, "\\\\");
  lua_settable(L, -3);

  if (lua_pcall(L, 3, 1, 0) != LUA_OK) {
    return lua_error(L);
  }
  return 1;
}
