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

# === Gnulib Replacements (Phase 9.3) ===
# Filesystem.hpp/cpp — faccessat, lstat, tempfile → std::filesystem
set(SOURCES ${CMAKE_SOURCE_DIR}/src/filesystem.cpp)

# === Locale utilities (Phase 9.3) ===
# locale.hpp/cpp — mbrtowc, wcwidth, iswprint → std::locale
set(SOURCES ${CMAKE_SOURCE_DIR}/src/locale.cpp)

# === Time utilities (Phase 9.3) ===
# chrono.hpp/cpp — gettimeofday, nanosleep → std::chrono
set(SOURCES ${CMAKE_SOURCE_DIR}/src/chrono.cpp)

# === Regex utilities (Phase 9.3) ===
# regex.hpp/cpp — regcomp, regexec → std::regex
set(SOURCES ${CMAKE_SOURCE_DIR}/src/regex.cpp)

# === Unit Tests (Phase 9.3) ===
# Add test_phase93_gnulib.cpp
set(SOURCES ${CMAKE_SOURCE_DIR}/test/cxx/test_phase93_gnulib.cpp)
