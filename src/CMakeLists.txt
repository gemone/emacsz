# CMakeLists.txt for src/ (Core Infrastructure + TUI)
#
# This CMakeLists.txt compiles Emacs C++20 core infrastructure
# including allocator, string utilities, terminal modules, and TUI.
#
# Created: 2026-02-01
# Updated: 2026-02-02 - Added termbox2 TUI support
# Phase: Phase 3 - Terminal/TUI Integration

cmake_minimum_required(VERSION 3.20)

# C++20 Standard (inherited from parent, but ensure it's set)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Find dependencies
find_package(Threads REQUIRED)

# Compilation options
add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-variable -Wno-unused-parameter)

# Platform-specific definitions
if(WIN32)
    add_definitions(-DWINDOWSNT)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
elseif(APPLE)
    add_definitions(-Ddarwin)
endif()

# ==============================================================================
# C++20 Allocator Module
# ==============================================================================
add_library(emacs_allocator STATIC
    allocator.cpp
    allocator.hpp
)
target_include_directories(emacs_allocator PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_compile_features(emacs_allocator PUBLIC cxx_std_20)

# ==============================================================================
# C++20 Strings Module
# ==============================================================================
add_library(emacs_strings STATIC
    strings.cpp
    strings.hpp
)
target_include_directories(emacs_strings PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_compile_features(emacs_strings PUBLIC cxx_std_20)

# ==============================================================================
# C++20 gnulib Replacement Library (Header-only)
# Provides C++20 replacements for gnulib modules
# ==============================================================================
add_library(emacs_gnulib_replacement INTERFACE)
target_include_directories(emacs_gnulib_replacement INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib
)
target_sources(emacs_gnulib_replacement INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/gnulib_replacement.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/compat_macros.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/crypto.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/filesystem.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/io_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/math_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/memory_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/regex_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/string_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/system_info.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/system_utils.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/gnulib/time_utils.hpp
)
target_compile_features(emacs_gnulib_replacement INTERFACE cxx_std_20)
target_link_libraries(emacs_gnulib_replacement INTERFACE Threads::Threads)

# ==============================================================================
# Terminal Concept Library (Header-only)
# ==============================================================================
add_library(emacs_terminal_concept INTERFACE)
target_include_directories(emacs_terminal_concept INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
target_sources(emacs_terminal_concept INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/terminal_concept.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/termhooks.hpp
)

# ==============================================================================
# Grid System (Phase 4 TUI)
# ==============================================================================
add_library(emacs_grid STATIC
    grid.cpp
    grid.hpp
)
target_include_directories(emacs_grid PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(emacs_grid PUBLIC
    emacs_allocator
)
target_compile_features(emacs_grid PUBLIC cxx_std_20)

# ==============================================================================
# Input Parser (Phase 4 TUI)
# ==============================================================================
add_library(emacs_input_parser STATIC
    input_parser.cpp
    input_parser.hpp
)
target_include_directories(emacs_input_parser PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(emacs_input_parser PUBLIC
    emacs_allocator
)
target_compile_features(emacs_input_parser PUBLIC cxx_std_20)

# ==============================================================================
# Event Loop (Phase 4 TUI)
# ==============================================================================
add_library(emacs_event_loop STATIC
    event_loop.cpp
    event_loop.hpp
)
target_include_directories(emacs_event_loop PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(emacs_event_loop PUBLIC
    emacs_allocator
    emacs_input_parser
)
target_compile_features(emacs_event_loop PUBLIC cxx_std_20)

# ==============================================================================
# Termbox2 TUI Backend
# ==============================================================================
add_library(emacs_termbox2_backend STATIC
    termbox2_term.cpp
    termbox2_term.hpp
)

target_include_directories(emacs_termbox2_backend PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)

# Link termbox2 library from cmake module
target_link_libraries(emacs_termbox2_backend PUBLIC
    termbox2::termbox2
    emacs_terminal_concept
    Threads::Threads
)

# Add TB_IMPL definition for one compilation unit
target_compile_definitions(emacs_termbox2_backend PRIVATE TB_IMPL)

target_compile_features(emacs_termbox2_backend PUBLIC cxx_std_20)

# Platform-specific definitions for terminal backend
if(WIN32)
    target_compile_definitions(emacs_termbox2_backend PRIVATE WINDOWSNT)
elseif(APPLE)
    target_compile_definitions(emacs_termbox2_backend PRIVATE darwin)
endif()

# ==============================================================================
# Platform-specific Terminal Backends (Future)
# ==============================================================================

# Windows Terminal (w32term)
if(WIN32)
    add_library(emacs_w32term STATIC
        w32term.cpp
        w32term.hpp
    )
    target_include_directories(emacs_w32term PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(emacs_w32term PUBLIC
        emacs_terminal_concept
    )
    target_compile_features(emacs_w32term PUBLIC cxx_std_20)
    target_compile_definitions(emacs_w32term PRIVATE WINDOWSNT)
endif()

# macOS Terminal (nsterm) - future
if(APPLE)
    # add_library(emacs_nsterm STATIC
    #     nsterm.cpp
    #     nsterm.hpp
    # )
    # target_link_libraries(emacs_nsterm PUBLIC emacs_terminal_concept)
endif()

# ==============================================================================
# Combined Terminal Library
# ==============================================================================
add_library(emacs_terminal INTERFACE)
target_link_libraries(emacs_terminal INTERFACE
    emacs_terminal_concept
    emacs_termbox2_backend
    emacs_grid
    emacs_input_parser
    emacs_event_loop
)

# ==============================================================================
# Minimal Main Executable (Phase 2/3 validation)
# ==============================================================================
add_executable(emacs_minimal
    main_minimal.cpp
)
target_include_directories(emacs_minimal PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(emacs_minimal PUBLIC
    emacs_allocator
)
target_compile_features(emacs_minimal PUBLIC cxx_std_20)

# ==============================================================================
# TUI Demo/Test Executable
# ==============================================================================
add_executable(emacs_tui_demo
    tui_demo.cpp
)
target_include_directories(emacs_tui_demo PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(emacs_tui_demo PUBLIC
    emacs_termbox2_backend
    emacs_allocator
    emacs_strings
)
target_compile_features(emacs_tui_demo PUBLIC cxx_std_20)

# ==============================================================================
# Installation
# ==============================================================================
include(GNUInstallDirs)

install(TARGETS
    emacs_allocator
    emacs_strings
    emacs_grid
    emacs_input_parser
    emacs_event_loop
    emacs_termbox2_backend
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

install(FILES
    allocator.hpp
    strings.hpp
    grid.hpp
    input_parser.hpp
    event_loop.hpp
    terminal_concept.hpp
    termhooks.hpp
    termbox2_term.hpp
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/emacs
)

install(FILES
    gnulib/gnulib_replacement.hpp
    gnulib/crypto.hpp
    gnulib/filesystem.hpp
    gnulib/math_utils.hpp
    gnulib/memory_utils.hpp
    gnulib/regex_utils.hpp
    gnulib/string_utils.hpp
    gnulib/system_utils.hpp
    gnulib/time_utils.hpp
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/emacs/gnulib
)

# ==============================================================================
# Summary
# ==============================================================================
message(STATUS "Emacs C++20 src/ configuration:")
message(STATUS "  Allocator module: emacs_allocator")
message(STATUS "  Strings module: emacs_strings")
message(STATUS "  Grid module: emacs_grid")
message(STATUS "  Input Parser module: emacs_input_parser")
message(STATUS "  Event Loop module: emacs_event_loop")
message(STATUS "  gnulib replacement: emacs_gnulib_replacement (header-only)")
message(STATUS "  Terminal concept: emacs_terminal_concept")
message(STATUS "  Termbox2 backend: emacs_termbox2_backend")
message(STATUS "  TUI demo: emacs_tui_demo")
