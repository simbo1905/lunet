cmake_minimum_required(VERSION 3.12)
project(lunet C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Helper macro to find dependencies via Config, PkgConfig, or standard paths
macro(find_dependency_flexible NAME PKG_NAME HEADER LIB_NAMES)
    # 1. Try Config mode (vcpkg, etc.)
    find_package(${NAME} CONFIG QUIET)
    
    if(${NAME}_FOUND)
        message(STATUS "Found ${NAME} via Config")
    else()
        # 2. Try PkgConfig
        find_package(PkgConfig QUIET)
        if(PKG_CONFIG_FOUND)
            pkg_check_modules(${NAME}_PKG ${PKG_NAME} QUIET)
        endif()

        if(${NAME}_PKG_FOUND)
            message(STATUS "Found ${NAME} via PkgConfig")
            set(${NAME}_INCLUDE_DIRS ${${NAME}_PKG_INCLUDE_DIRS})
            set(${NAME}_LIBRARIES ${${NAME}_PKG_LIBRARIES})
            set(${NAME}_FOUND TRUE)
        else()
            # 3. Try standard paths
            find_path(${NAME}_INCLUDE_DIR ${HEADER}
                HINTS ENV ${NAME}_DIR
                PATH_SUFFIXES include
            )
            find_library(${NAME}_LIBRARY NAMES ${LIB_NAMES}
                HINTS ENV ${NAME}_DIR
                PATH_SUFFIXES lib
            )
            if(${NAME}_INCLUDE_DIR AND ${NAME}_LIBRARY)
                message(STATUS "Found ${NAME} via standard paths: ${${NAME}_LIBRARY}")
                set(${NAME}_INCLUDE_DIRS ${${NAME}_INCLUDE_DIR})
                set(${NAME}_LIBRARIES ${${NAME}_LIBRARY})
                set(${NAME}_FOUND TRUE)
            endif()
        endif()
    endif()

    if(NOT ${NAME}_FOUND)
        message(FATAL_ERROR "${NAME} not found. Please install it.")
    endif()
endmacro()

# === Dependencies ===

# LuaJIT
find_dependency_flexible(LUAJIT luajit luajit.h "luajit-5.1;luajit;lua51")

# libuv
find_package(libuv CONFIG QUIET)
if(NOT libuv_FOUND)
    find_dependency_flexible(LIBUV libuv uv.h "uv;libuv")
endif()

# libsodium
find_package(unofficial-sodium CONFIG QUIET)
if(NOT unofficial-sodium_FOUND)
    find_dependency_flexible(SODIUM libsodium sodium.h "sodium;libsodium")
endif()

# === Database Backend Option ===
set(LUNET_DB "mysql" CACHE STRING "Database backend: none, mysql, postgres, sqlite3")
set_property(CACHE LUNET_DB PROPERTY STRINGS none mysql postgres sqlite3)
message(STATUS "Database backend: ${LUNET_DB}")

# === Source files ===
set(SOURCES
    src/main.c
    src/co.c
    src/fs.c
    src/rt.c
    src/signal.c
    src/socket.c
    src/stl.c
    src/timer.c
)

set(DB_LIBRARY "")

# === Database Backend Configuration ===
if(LUNET_DB STREQUAL "mysql")
  find_dependency_flexible(MYSQL mysql mysql.h "mysqlclient;mysql")
  
  include_directories(ext/mysql)
  include_directories(${MYSQL_INCLUDE_DIRS})
  message(STATUS "Found MySQL: ${MYSQL_LIBRARIES}")
  list(APPEND SOURCES ext/mysql/mysql.c)
  # list(APPEND HEADERS ext/mysql/mysql.h)
  set(DB_LIBRARY ${MYSQL_LIBRARIES})
  add_definitions(-DLUNET_HAS_DB)
  set(LUNET_DB_DRIVER "mysql")

elseif(LUNET_DB STREQUAL "postgres")
  find_dependency_flexible(PostgreSQL libpq libpq-fe.h "pq;libpq")
  
  include_directories(${PostgreSQL_INCLUDE_DIRS})
  include_directories(ext/postgres)
  message(STATUS "Found PostgreSQL: ${PostgreSQL_LIBRARIES}")
  list(APPEND SOURCES ext/postgres/postgres.c)
  # list(APPEND HEADERS ext/postgres/postgres.h)
  set(DB_LIBRARY ${PostgreSQL_LIBRARIES})
  add_definitions(-DLUNET_HAS_DB)
  set(LUNET_DB_DRIVER "postgres")

elseif(LUNET_DB STREQUAL "sqlite3")
  find_dependency_flexible(SQLITE3 sqlite3 sqlite3.h "sqlite3")
  
  include_directories(${SQLITE3_INCLUDE_DIRS})
  include_directories(ext/sqlite3)
  message(STATUS "Found SQLite3: ${SQLITE3_LIBRARIES}")
  list(APPEND SOURCES ext/sqlite3/sqlite3.c)
  # list(APPEND HEADERS ext/sqlite3/sqlite3.h)
  set(DB_LIBRARY ${SQLITE3_LIBRARIES})
  add_definitions(-DLUNET_HAS_DB)
  set(LUNET_DB_DRIVER "sqlite")

elseif(LUNET_DB STREQUAL "none")
  message(STATUS "Building without database support")
  set(LUNET_DB_DRIVER "none")

else()
  message(FATAL_ERROR "Invalid LUNET_DB value: ${LUNET_DB}. Must be one of: none, mysql, postgres, sqlite3")
endif()

# Generate app/db_config.lua from app/db_config.lua.in
configure_file(app/db_config.lua.in ${CMAKE_SOURCE_DIR}/app/db_config.lua @ONLY)

# === Targets ===
include_directories(include)
include_directories(${LUAJIT_INCLUDE_DIRS})
include_directories(${LIBUV_INCLUDE_DIRS})
include_directories(${SODIUM_INCLUDE_DIRS})

add_executable(lunet ${SOURCES})

target_link_libraries(lunet PRIVATE
  ${LUAJIT_LIBRARIES}
  ${LIBUV_LIBRARIES}
  ${SODIUM_LIBRARIES}
  ${DB_LIBRARY}
)

if(WIN32)
    target_link_libraries(lunet PRIVATE ws2_32 iphlpapi userenv psapi)
endif()

# === Installation / Post-build ===
if(WIN32)
    # Only copy if targets exist (vcpkg mode)
    if(TARGET unofficial-sodium::sodium)
        add_custom_command(TARGET lunet POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:unofficial-sodium::sodium>
            $<TARGET_FILE_DIR:lunet>
        )
    endif()
    if(TARGET sqlite3::sqlite3 AND LUNET_DB STREQUAL "sqlite3")
        add_custom_command(TARGET lunet POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:sqlite3::sqlite3>
            $<TARGET_FILE_DIR:lunet>
        )
    endif()
endif()