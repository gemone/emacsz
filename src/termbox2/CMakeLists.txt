cmake_minimum_required(VERSION 3.20)

# Use FetchContent to import termbox2 header files from GitHub
FetchContent_Declare(
    NAME termbox2_fetch
    GIT_REPOSITORY https://github.com/termbox/termbox2.git
    GIT_TAG v0.1.9
)

# Check if FetchContent is available
fetchcontent_makefile_available()

# Include directories for termbox2 headers
include_directories(termbox2_fetch PUBLIC
    ${termbox2_fetch_SOURCE_DIR}/src
    ${termbox2_fetch_SOURCE_DIR}/include
)

# Create interface library (header-only)
add_library(termbox2_fetch INTERFACE)

# Install interface library
install(TARGETS termbox2_fetch
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

message(STATUS "Using FetchContent to import termbox2 headers")
message(STATUS "  Repository: https://github.com/termbox/termbox2.git")
message(STATUS "  Tag: v0.1.9")
