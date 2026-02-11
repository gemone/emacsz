# C++20 Terminal module (Phase 3)
cmake_minimum_required(VERSION 3.20)

project(Emacs VERSION 29.4 DESCRIPTION "Emacs text editor" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(BUILD_WITH_AUTOTOOLS "Enable dual-build system with autotools support" OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Build type: Debug, Release")
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

include(FetchContent)

include(cmake/termbox2.cmake)

add_subdirectory(src)
