cmake_minimum_required(VERSION 3.12)
project(lunet C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Option to enable/disable MySQL support
option(LUNET_ENABLE_MYSQL "Enable MySQL support" OFF)

include_directories(include)

# === LuaJIT ===
# Try vcpkg paths first (Windows), then Homebrew/standard paths (macOS/Linux)
find_path(LUAJIT_INCLUDE_DIR luajit.h
  HINTS 
    ${LUAJIT_INCLUDE_DIR} 
    ENV LUAJIT_INCLUDE_DIR 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include/luajit"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/include/luajit"
    "C:/vcpkg/installed/x64-windows/include/luajit"
    /opt/homebrew/include 
    /usr/local/include
  PATH_SUFFIXES luajit-2.1 luajit
)

# LuaJIT library names: lua51 on Windows (vcpkg), luajit-5.1 on Unix
find_library(LUAJIT_LIBRARY NAMES lua51 luajit-5.1 luajit
  HINTS 
    ${LUAJIT_LIBRARY} 
    ENV LUAJIT_LIBRARY 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
    "C:/vcpkg/installed/x64-windows/lib"
    /opt/homebrew/lib 
    /usr/local/lib
)

if (NOT LUAJIT_INCLUDE_DIR OR NOT LUAJIT_LIBRARY)
  message(FATAL_ERROR "LuaJIT not found. Set -DLUAJIT_INCLUDE_DIR and -DLUAJIT_LIBRARY manually.")
endif()
include_directories(${LUAJIT_INCLUDE_DIR})
message(STATUS "Found LuaJIT include: ${LUAJIT_INCLUDE_DIR}")
message(STATUS "Found LuaJIT library: ${LUAJIT_LIBRARY}")

# === libuv ===
find_path(LIBUV_INCLUDE_DIR uv.h
  HINTS 
    ${LIBUV_INCLUDE_DIR} 
    ENV LIBUV_INCLUDE_DIR 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/include"
    "C:/vcpkg/installed/x64-windows/include"
    /opt/homebrew/include 
    /usr/local/include
)
find_library(LIBUV_LIBRARY NAMES uv libuv
  HINTS 
    ${LIBUV_LIBRARY} 
    ENV LIBUV_LIBRARY 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
    "C:/vcpkg/installed/x64-windows/lib"
    /opt/homebrew/lib 
    /usr/local/lib
)

if (NOT LIBUV_INCLUDE_DIR OR NOT LIBUV_LIBRARY)
  message(FATAL_ERROR "libuv not found. Set -DLIBUV_INCLUDE_DIR and -DLIBUV_LIBRARY manually.")
endif()
include_directories(${LIBUV_INCLUDE_DIR})
message(STATUS "Found libuv include: ${LIBUV_INCLUDE_DIR}")
message(STATUS "Found libuv library: ${LIBUV_LIBRARY}")

# === libsodium ===
find_path(SODIUM_INCLUDE_DIR sodium.h
  HINTS 
    ${SODIUM_INCLUDE_DIR} 
    ENV SODIUM_INCLUDE_DIR 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/include"
    "C:/vcpkg/installed/x64-windows/include"
    /opt/homebrew/include 
    /usr/local/include
)
find_library(SODIUM_LIBRARY NAMES sodium libsodium
  HINTS 
    ${SODIUM_LIBRARY} 
    ENV SODIUM_LIBRARY 
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
    "C:/vcpkg/installed/x64-windows/lib"
    /opt/homebrew/lib 
    /usr/local/lib
)
if (NOT SODIUM_INCLUDE_DIR OR NOT SODIUM_LIBRARY)
  message(FATAL_ERROR "libsodium not found. Please install it.")
endif()
include_directories(${SODIUM_INCLUDE_DIR})
message(STATUS "Found libsodium: ${SODIUM_LIBRARY}")

# === MySQL Client (Optional) ===
if(LUNET_ENABLE_MYSQL)
  find_path(MYSQL_INCLUDE_DIR mysql.h
    HINTS ${MYSQL_INCLUDE_DIR} ENV MYSQL_INCLUDE_DIR /opt/homebrew/include /usr/local/include
    PATH_SUFFIXES mysql mysqlclient
  )
  find_library(MYSQL_LIBRARY NAMES mysqlclient
    HINTS ${MYSQL_LIBRARY} ENV MYSQL_LIBRARY /opt/homebrew/lib /usr/local/lib
  )

  if (NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
    message(FATAL_ERROR "MySQL client not found. Set -DMYSQL_INCLUDE_DIR and -DMYSQL_LIBRARY manually, or disable with -DLUNET_ENABLE_MYSQL=OFF")
  endif()
  include_directories(${MYSQL_INCLUDE_DIR})
  message(STATUS "Found MySQL: ${MYSQL_LIBRARY}")
  add_definitions(-DLUNET_ENABLE_MYSQL)
else()
  message(STATUS "MySQL support disabled")
endif()

# === Database Backend Option ===
set(LUNET_DB "mysql" CACHE STRING "Database backend: none, mysql, postgres, sqlite3")
set_property(CACHE LUNET_DB PROPERTY STRINGS none mysql postgres sqlite3)
message(STATUS "Database backend: ${LUNET_DB}")

# === Tracing Option ===
# Enable with: cmake -DLUNET_TRACE=ON ..
# This adds coroutine reference tracking for debugging.
# When OFF, all tracing code is eliminated by the compiler (zero overhead).
option(LUNET_TRACE "Enable coroutine reference tracing for debugging" OFF)

if(LUNET_TRACE)
  message(STATUS "LUNET_TRACE enabled - coroutine reference tracing active")
  add_compile_definitions(LUNET_TRACE)
else()
  message(STATUS "LUNET_TRACE disabled - zero overhead release build")
endif()

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
  src/trace.c
)

# Only include mysql.c if MySQL is enabled
if(LUNET_ENABLE_MYSQL)
  list(APPEND SOURCES src/mysql.c)
endif()

set(DB_LIBRARY "")

# === Database Backend Configuration ===
if(LUNET_DB STREQUAL "mysql")
  # Already handled by LUNET_ENABLE_MYSQL above but let's reconcile
  if (NOT LUNET_ENABLE_MYSQL)
      message(WARNING "LUNET_DB is mysql but LUNET_ENABLE_MYSQL is OFF. Enabling MySQL.")
      set(LUNET_ENABLE_MYSQL ON)
      add_definitions(-DLUNET_ENABLE_MYSQL)
      # Need to ensure we have the include/lib
  endif()
  
  if(NOT MYSQL_LIBRARY)
       # Duplicate finding logic if not already found above...
      find_path(MYSQL_INCLUDE_DIR mysql.h
        HINTS ${MYSQL_INCLUDE_DIR} ENV MYSQL_INCLUDE_DIR /opt/homebrew/include /usr/local/include
        PATH_SUFFIXES mysql mysqlclient
      )
      find_library(MYSQL_LIBRARY NAMES mysqlclient
        HINTS ${MYSQL_LIBRARY} ENV MYSQL_LIBRARY /opt/homebrew/lib /usr/local/lib
      )
      if (NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
        message(FATAL_ERROR "MySQL client not found. Set -DMYSQL_INCLUDE_DIR and -DMYSQL_LIBRARY manually, or disable with -DLUNET_ENABLE_MYSQL=OFF")
      endif()
      include_directories(${MYSQL_INCLUDE_DIR})
  endif()

  set(DB_LIBRARY ${MYSQL_LIBRARY})
  set(LUNET_DB_DRIVER "mysql")

elseif(LUNET_DB STREQUAL "postgres")
    # Add postgres support if needed, similar to mysql
    message(WARNING "Postgres support not fully merged in this block yet")
    set(LUNET_DB_DRIVER "postgres")

elseif(LUNET_DB STREQUAL "sqlite3")
     # Add sqlite3 support if needed
    message(WARNING "Sqlite3 support not fully merged in this block yet")
    set(LUNET_DB_DRIVER "sqlite")

elseif(LUNET_DB STREQUAL "none")
  message(STATUS "Building without database support")
  set(LUNET_DB_DRIVER "none")

else()
  message(FATAL_ERROR "Invalid LUNET_DB value: ${LUNET_DB}. Must be one of: none, mysql, postgres, sqlite3")
endif()


file(GLOB_RECURSE HEADERS include/*.h)

add_executable(lunet ${SOURCES} ${HEADERS})

# Link libraries
target_link_libraries(lunet
  ${LUAJIT_LIBRARY}
  ${LIBUV_LIBRARY}
  ${SODIUM_LIBRARY}
)

if(LUNET_ENABLE_MYSQL)
  target_link_libraries(lunet ${MYSQL_LIBRARY})
endif()

# Windows-specific: link ws2_32, iphlpapi, userenv, psapi for libuv
if(WIN32)
  target_link_libraries(lunet ws2_32 iphlpapi userenv psapi)
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
