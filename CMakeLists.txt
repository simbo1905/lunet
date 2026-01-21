cmake_minimum_required(VERSION 3.12)
project(lunet C)

# =============================================================================
# Build Configuration
# =============================================================================
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Options
option(LUNET_ENABLE_MYSQL "Enable MySQL support" OFF)

# =============================================================================
# Platform Detection
# =============================================================================
if(WIN32)
  message(STATUS "Platform: Windows")
  # Minimize Windows header pollution
  add_definitions(-DWIN32_LEAN_AND_MEAN -DNOMINMAX)
elseif(APPLE)
  message(STATUS "Platform: macOS")
elseif(UNIX)
  message(STATUS "Platform: Linux/Unix")
endif()

# =============================================================================
# Include Directories
# =============================================================================
include_directories(include)

# =============================================================================
# LuaJIT
# =============================================================================
# Define platform-specific search paths
if(WIN32)
  set(LUAJIT_SEARCH_PATHS
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include/luajit"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/include/luajit"
    "C:/vcpkg/installed/x64-windows/include/luajit"
  )
  set(LUAJIT_LIB_PATHS
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
    "C:/vcpkg/installed/x64-windows/lib"
  )
  set(LUAJIT_LIB_NAMES lua51 luajit-5.1)
elseif(APPLE)
  set(LUAJIT_SEARCH_PATHS
    /opt/homebrew/include
    /usr/local/include
  )
  set(LUAJIT_LIB_PATHS
    /opt/homebrew/lib
    /usr/local/lib
  )
  set(LUAJIT_LIB_NAMES luajit-5.1)
else()
  set(LUAJIT_SEARCH_PATHS
    /usr/include
    /usr/local/include
  )
  set(LUAJIT_LIB_PATHS
    /usr/lib
    /usr/lib/x86_64-linux-gnu
    /usr/local/lib
  )
  set(LUAJIT_LIB_NAMES luajit-5.1)
endif()

find_path(LUAJIT_INCLUDE_DIR luajit.h
  HINTS ${LUAJIT_INCLUDE_DIR} ENV LUAJIT_INCLUDE_DIR ${LUAJIT_SEARCH_PATHS}
  PATH_SUFFIXES luajit-2.1 luajit
)

find_library(LUAJIT_LIBRARY NAMES ${LUAJIT_LIB_NAMES}
  HINTS ${LUAJIT_LIBRARY} ENV LUAJIT_LIBRARY ${LUAJIT_LIB_PATHS}
)

if(NOT LUAJIT_INCLUDE_DIR OR NOT LUAJIT_LIBRARY)
  message(FATAL_ERROR "LuaJIT not found. Set -DLUAJIT_INCLUDE_DIR and -DLUAJIT_LIBRARY manually.")
endif()

include_directories(${LUAJIT_INCLUDE_DIR})
message(STATUS "Found LuaJIT include: ${LUAJIT_INCLUDE_DIR}")
message(STATUS "Found LuaJIT library: ${LUAJIT_LIBRARY}")

# =============================================================================
# libuv
# =============================================================================
if(WIN32)
  set(LIBUV_SEARCH_PATHS
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/include"
    "C:/vcpkg/installed/x64-windows/include"
  )
  set(LIBUV_LIB_PATHS
    "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
    "${CMAKE_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
    "C:/vcpkg/installed/x64-windows/lib"
  )
  set(LIBUV_LIB_NAMES uv libuv)
elseif(APPLE)
  set(LIBUV_SEARCH_PATHS
    /opt/homebrew/include
    /usr/local/include
  )
  set(LIBUV_LIB_PATHS
    /opt/homebrew/lib
    /usr/local/lib
  )
  set(LIBUV_LIB_NAMES uv)
else()
  set(LIBUV_SEARCH_PATHS
    /usr/include
    /usr/local/include
  )
  set(LIBUV_LIB_PATHS
    /usr/lib
    /usr/lib/x86_64-linux-gnu
    /usr/local/lib
  )
  set(LIBUV_LIB_NAMES uv)
endif()

find_path(LIBUV_INCLUDE_DIR uv.h
  HINTS ${LIBUV_INCLUDE_DIR} ENV LIBUV_INCLUDE_DIR ${LIBUV_SEARCH_PATHS}
)

find_library(LIBUV_LIBRARY NAMES ${LIBUV_LIB_NAMES}
  HINTS ${LIBUV_LIBRARY} ENV LIBUV_LIBRARY ${LIBUV_LIB_PATHS}
)

if(NOT LIBUV_INCLUDE_DIR OR NOT LIBUV_LIBRARY)
  message(FATAL_ERROR "libuv not found. Set -DLIBUV_INCLUDE_DIR and -DLIBUV_LIBRARY manually.")
endif()

include_directories(${LIBUV_INCLUDE_DIR})
message(STATUS "Found libuv include: ${LIBUV_INCLUDE_DIR}")
message(STATUS "Found libuv library: ${LIBUV_LIBRARY}")

# =============================================================================
# MySQL Client (Optional)
# =============================================================================
if(LUNET_ENABLE_MYSQL)
  if(WIN32)
    set(MYSQL_SEARCH_PATHS
      "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include"
      "C:/Program Files/MySQL/MySQL Server 8.0/include"
    )
    set(MYSQL_LIB_PATHS
      "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
      "C:/Program Files/MySQL/MySQL Server 8.0/lib"
    )
    set(MYSQL_LIB_NAMES libmysql mysqlclient)
  elseif(APPLE)
    set(MYSQL_SEARCH_PATHS
      /opt/homebrew/include
      /usr/local/include
    )
    set(MYSQL_LIB_PATHS
      /opt/homebrew/lib
      /usr/local/lib
    )
    set(MYSQL_LIB_NAMES mysqlclient)
  else()
    set(MYSQL_SEARCH_PATHS
      /usr/include
      /usr/local/include
    )
    set(MYSQL_LIB_PATHS
      /usr/lib
      /usr/lib/x86_64-linux-gnu
      /usr/local/lib
    )
    set(MYSQL_LIB_NAMES mysqlclient mariadbclient)
  endif()

  find_path(MYSQL_INCLUDE_DIR mysql.h
    HINTS ${MYSQL_INCLUDE_DIR} ENV MYSQL_INCLUDE_DIR ${MYSQL_SEARCH_PATHS}
    PATH_SUFFIXES mysql mariadb
  )

  find_library(MYSQL_LIBRARY NAMES ${MYSQL_LIB_NAMES}
    HINTS ${MYSQL_LIBRARY} ENV MYSQL_LIBRARY ${MYSQL_LIB_PATHS}
  )

  if(NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
    message(FATAL_ERROR "MySQL client not found. Set -DMYSQL_INCLUDE_DIR and -DMYSQL_LIBRARY manually, or disable with -DLUNET_ENABLE_MYSQL=OFF")
  endif()

  include_directories(${MYSQL_INCLUDE_DIR})
  message(STATUS "Found MySQL include: ${MYSQL_INCLUDE_DIR}")
  message(STATUS "Found MySQL library: ${MYSQL_LIBRARY}")
  add_definitions(-DLUNET_ENABLE_MYSQL)
else()
  message(STATUS "MySQL support disabled")
endif()

# =============================================================================
# Source Files
# =============================================================================
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

# Only include mysql.c if MySQL is enabled
if(LUNET_ENABLE_MYSQL)
  list(APPEND SOURCES src/mysql.c)
endif()

file(GLOB_RECURSE HEADERS include/*.h)

# =============================================================================
# Executable Target
# =============================================================================
add_executable(lunet ${SOURCES} ${HEADERS})

# Link libraries
target_link_libraries(lunet
  ${LUAJIT_LIBRARY}
  ${LIBUV_LIBRARY}
)

if(LUNET_ENABLE_MYSQL)
  target_link_libraries(lunet ${MYSQL_LIBRARY})
endif()

# =============================================================================
# Platform-Specific Link Libraries
# =============================================================================
if(WIN32)
  # Windows: link required system libraries for libuv
  target_link_libraries(lunet ws2_32 iphlpapi userenv psapi)
elseif(UNIX AND NOT APPLE)
  # Linux: may need pthread and dl
  find_package(Threads REQUIRED)
  target_link_libraries(lunet Threads::Threads ${CMAKE_DL_LIBS})
endif()

# =============================================================================
# Install Target (Optional)
# =============================================================================
install(TARGETS lunet RUNTIME DESTINATION bin)
