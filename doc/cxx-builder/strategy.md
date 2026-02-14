# Emacs C++20 Migration Strategy

**Version:** 1.0
**Date:** 2026-02-01
**Status:** Design Phase

---

## Executive Summary

This document outlines a comprehensive strategy for migrating GNU Emacs from C to C++20, replacing the autotools build system with CMake + vcpkg, and eliminating gnulib dependencies while maintaining cross-platform compatibility.

### Key Objectives

1. **CMake + C++20 Build System**: Replace autotools with modern CMake
2. **Standard Library Migration**: Replace gnulib with C++20 standard library
3. **Incremental Migration**: Ensure each migration step is testable and functional
4. **Upstream Sync Strategy**: Maintain compatibility with upstream Emacs development
5. **Cross-Platform Support**: Support Linux, macOS, Windows, Haiku, and Android

### Migration Scope

- **C Source Files:** ~152 files in `src/` (515,179 lines of C code)
- **gnulib Dependencies:** 127 gnulib modules in `lib/` directory
- **Platform-Specific Code:** Extensive `#ifdef` blocks for Windows, macOS, Android, Haiku
- **Existing C++:** 21 C++ files (Haiku GUI: 4 files, tests: 14 files, lib-src: 1 file, src: 2 files)

---

## Architecture Decisions

### 1. Migration Approach: Incremental Dual-Build

**Decision:** Maintain **both** autotools (for upstream sync) and CMake (for C++20) builds simultaneously.

**Rationale:**
- Allows continuous upstream Emacs updates without breaking migration
- Enables gradual, testable migration of individual modules
- Reduces risk of breaking the entire codebase
- Provides fallback during development

**Implementation:**
```bash
# Dual build system
./autogen.sh && ./configure    # Upstream autotools build
cmake -B build-cpp            # New C++20 build
```

### 2. Code Retention vs. Replacement Strategy

**Decision:** **Retain original C code** and create C++20 wrappers/translations.

**Rationale:**
- Enables upstream merge with minimal conflicts
- Allows testing C++ implementation alongside C implementation
- Provides reference implementation during development
- Facilitates gradual adoption by community

**Pattern:**
```cpp
// New C++ implementation
#include <emacs/legacy.h>

namespace emacs {
    // Modern C++ implementation
    class BufferManager {
        // C++20 features
    };
}

// Legacy C bridge (for compatibility)
extern "C" {
    void legacy_buffer_operation();
}
```

### 3. gnulib Replacement Strategy

**Decision:** **Progressive replacement** of gnulib functions with C++20 equivalents.

**Phases:**
1. **Phase 1:** Create C++ wrapper layer (transitional)
2. **Phase 2:** Replace core gnulib functions with `std::` equivalents
3. **Phase 3:** Eliminate gnulib dependency entirely

**Mapping Table:**

| gnulib Function | C++20 Equivalent | Priority |
|----------------|------------------|----------|
| `malloc/realloc` | `std::unique_ptr`, `std::vector` | HIGH |
| `strdup` | `std::string` copy constructors | HIGH |
| `qsort` | `std::sort` with lambdas | MEDIUM |
| `asprintf` | `std::format` (C++20) | HIGH |
| `getline` | `std::getline` (C++20) | HIGH |
| `faccessat/lstat` | `std::filesystem` | MEDIUM |
| `tempfile` | `std::filesystem::temp_directory_path` | LOW |

### 4. Platform Abstraction Strategy

**Decision:** Use **C++20 concepts** and **template metaprogramming** for platform abstraction.

**Pattern:**
```cpp
// Platform abstraction using C++20 concepts
template<typename Platform>
concept TerminalBackend = requires(Platform t) {
    { t.init() } -> void;
    { t.write_glyphs() } -> void;
    { t.set_cursor() } -> void;
};

// Platform-specific implementations
class X11Terminal : public TerminalBackend<X11> { /* ... */ };
class WindowsTerminal : public TerminalBackend<Windows> { /* ... */ };
class HaikuTerminal : public TerminalBackend<Haiku> { /* ... */ };

// Generic terminal interface
template<typename T>
class Terminal {
    T backend;
public:
    void init() { backend.init(); }
    void write_glyphs() { backend.write_glyphs(); }
};
```

---

## Migration Phases

### Phase 0: Foundation Setup (Week 1-2)

**Goal:** Establish CMake build system infrastructure.

**Tasks:**
1. Create root `CMakeLists.txt` with basic project structure
2. Set up vcpkg integration with `vcpkg.json`
3. Configure C++20 standard requirements
4. Create dual-build scripts (autotools + CMake)
5. Set up GitHub Actions workflow

**Deliverables:**
- `CMakeLists.txt` (root)
- `vcpkg.json` (dependencies)
- `.github/workflows/cxx-builder.yml`
- Dual-build script: `build.sh`

**Success Criteria:**
- `cmake -B build-cpp` succeeds
- `cmake --build build-cpp` builds a minimal C++ "hello world"
- GitHub Actions workflow runs successfully

---

### Phase 1: Core Infrastructure (Week 3-6)

**Goal:** Establish C++20 core infrastructure and build system.

**Tasks:**
1. **Memory Management:**
   - Create C++ allocator wrapper for Emacs GC
   - Implement `std::allocator` adapter for `MALLOC_ALIGNMENT`
   - Replace gnulib `allocator` module

2. **String Utilities:**
   - Create `std::string_view` adapters for Lisp strings
   - Replace gnulib string functions (`strndup`, `stpcpy`, `strnlen`)
   - Implement `std::format` migration

3. **Build System:**
   - Add `src/` subdirectory to CMake
   - Create C++ library targets for core modules
   - Set up linking with existing C libraries

**Files to Migrate:**
- `src/alloc.c` → `src/alloc.cpp`
- `src/data.c` → `src/data.cpp` (string operations)
- `src/lisp.h` → `src/lisp.hpp` (header modernization)

**Deliverables:**
- C++ allocator implementation compatible with Emacs GC
- String utility library using C++20 `std::string`
- CMake targets for core modules
- Initial tests passing

**Success Criteria:**
- All existing C tests pass with C++ allocator
- String operations work with `std::string` and `std::string_view`
- No gnulib string functions remain in migrated code

---

### Phase 2: Entry Point & Startup (Week 7-8)

**Goal:** Migrate main entry point and startup sequence to C++.

**Tasks:**
1. **Main Entry:**
   - Convert `src/emacs.c` to `src/main.cpp`
   - Preserve platform-specific initialization blocks
   - Use C++20 `if constexpr` for compile-time decisions

2. **Startup Sequence:**
   - Modernize `main()` function with RAII
   - Use `std::unique_ptr` for resource management
   - Replace C-style error handling with exceptions (controlled)

3. **Command Line Parsing:**
   - Use C++20 `std::span` for argv
   - Replace `copy_args()` with modern alternatives

**Files to Migrate:**
- `src/emacs.c` → `src/main.cpp`

**Deliverables:**
- C++20 main entry point
- Startup sequence using RAII
- Command line parser with `std::span`

**Success Criteria:**
- `build-cpp/bin/emacs` starts successfully
- `-Q`, `--version`, and basic commands work
- All startup tests pass

---

### Phase 3: Terminal Abstraction (Week 9-12)

**Goal:** Modernize terminal subsystem with C++20 concepts and improve Windows TUI.

**Tasks:**
1. **Terminal Interface:**
   - Define C++20 concept-based terminal interface
   - Refactor `src/termhooks.h` to use C++ classes
   - Implement platform-specific terminal backends as C++ templates

2. **Windows TUI Improvement:**
   - Research Neovim's TUI implementation
   - Design cross-platform terminal output using C++20
   - Replace termcap with `std::string`-based terminal database
   - Implement proper Windows console support (not just w32console)

3. **Display Abstraction:**
   - Create C++20 `std::variant` for terminal types
   - Refactor `src/termchar.h` to use C++ structures
   - Replace terminal state machine with modern C++ patterns

**Files to Migrate:**
- `src/term.c` → `src/term.cpp` (core terminal logic)
- `src/dispnew.c` → `src/dispnew.cpp` (display updates)
- `src/terminal.c` → `src/terminal.cpp` (terminal management)
- `src/w32console.c` → `src/console.cpp` (improved Windows console)

**Deliverables:**
- C++20 concept-based terminal interface
- Improved Windows TUI implementation
- Platform-specific terminal backends (X11, Windows, macOS, Haiku, Android)
- TUI tests for Windows compatibility

**Success Criteria:**
- Terminal operations work on Windows, Linux, macOS
- TUI tests pass on all platforms
- Performance comparable to C implementation
- Windows TUI is usable (not just functional)

---

### Phase 4: Lisp Interpreter Core (Week 13-20)

**Goal:** Migrate core Lisp interpreter to C++20.

**Tasks:**
1. **Data Types:**
   - Convert Lisp objects to C++ classes with RAII
   - Use `std::variant` for Lisp value types
   - Implement move semantics for Lisp objects

2. **Evaluation Engine:**
   - Refactor `src/eval.c` to C++20
   - Use C++20 coroutines for evaluation
   - Replace goto-based control flow with structured control

3. **Garbage Collection:**
   - Integrate C++ allocator with Emacs GC
   - Use `std::atomic` for thread-safe GC
   - Implement RAII-based cleanup

**Files to Migrate:**
- `src/lisp.h` → `src/lisp.hpp` (Lisp type definitions)
- `src/data.c` → `src/data.cpp` (Lisp data types)
- `src/eval.c` → `src/eval.cpp` (Lisp interpreter)
- `src/bytecode.c` → `src/bytecode.cpp` (bytecode interpreter)

**Deliverables:**
- C++20 Lisp data type system
- Modern evaluation engine with coroutines
- GC-aware allocator integration

**Success Criteria:**
- All Lisp tests pass
- Performance benchmarks comparable to C implementation
- Memory usage stable or improved

---

### Phase 5: Platform-Specific GUI (Week 21-24)

**Goal:** Migrate GUI subsystems while maintaining compatibility.

**Tasks:**
1. **macOS (NextStep):**
   - Modernize `src/nsterm.m` (Objective-C++)
   - Replace C-style callbacks with C++ lambdas
   - Use C++20 `std::function` for event handlers

2. **Windows (w32):**
   - Refactor `src/w32gui.c` to C++
   - Use `std::unique_ptr` for Windows handles
   - Replace C error handling with C++ exceptions

3. **Haiku:**
   - Modernize existing C++ files (`src/haiku_*.cc`)
   - Ensure C++20 compliance

4. **X11/GTK+:**
   - Refactor `src/xterm.c` and `src/xfns.c` to C++
   - Use C++20 `std::variant` for X11 event types

**GUI Retention Strategy:**
- **Keep existing GUI implementations** functional
- **Modernize interfaces** only (no UI redesign)
- **Reserve SDL3 interface** for future use

**Files to Migrate:**
- `src/nsterm.m` → modernize (keep Objective-C++)
- `src/w32gui.c` → `src/w32gui.cpp`
- `src/xterm.c` → `src/xterm.cpp`
- `src/xfns.c` → `src/xfns.cpp`
- `src/haiku_*.cc` → ensure C++20 compliance

**Deliverables:**
- Modernized GUI backends with C++20
- SDL3 interface stubs (for future use)
- GUI tests for all platforms

**Success Criteria:**
- All GUI features work
- No regressions in UI
- SDL3 interface stubs exist

---

### Phase 6: File I/O & System (Week 25-28)

**Goal:** Migrate file I/O and system operations to C++20.

**Tasks:**
1. **File Operations:**
   - Replace gnulib file functions with `std::filesystem`
   - Use C++20 `std::fstream` for file I/O
   - Implement cross-platform path handling

2. **System Calls:**
   - Modernize `src/sysdep.c` to C++
   - Use C++20 `<filesystem>` for platform abstraction
   - Replace C preprocessor with C++ `if constexpr`

**Files to Migrate:**
- `src/fileio.c` → `src/fileio.cpp`
- `src/sysdep.c` → `src/sysdep.cpp`
- All gnulib file operation dependencies

**Deliverables:**
- C++20 file I/O system
- Platform-agnostic system operations
- Filesystem abstraction using `std::filesystem`

**Success Criteria:**
- All file operations work
- Cross-platform compatibility maintained
- No gnulib file dependencies remain

---

### Phase 7: Testing & Validation (Week 29-32)

**Goal:** Ensure comprehensive testing and validation.

**Tasks:**
1. **Test Suite:**
   - Port C tests to C++ (where applicable)
   - Add C++20-specific tests
   - Ensure 100% test coverage for migrated code

2. **Performance Benchmarking:**
   - Benchmark C++ vs C implementation
   - Identify performance regressions
   - Optimize critical paths

3. **Integration Testing:**
   - Test complete Emacs build
   - Run Lisp test suite
   - Validate GUI functionality

**Deliverables:**
- Complete test suite for C++ codebase
- Performance benchmarks
- Integration test results

**Success Criteria:**
- All tests pass
- Performance within 10% of C implementation
- No known regressions

---

### Phase 8: Build System Cleanup (Week 33-36)

**Goal:** Complete migration and remove autotools dependency.

**Tasks:**
1. **Documentation:**
   - Document CMake build process
   - Create migration guide for contributors
   - Update README files

2. **Tooling:**
   - Set up `clang-tidy` for C++20 code quality
   - Configure `clang-format` for consistent formatting
   - Create GitHub Actions for CI/CD

3. **Final Cleanup:**
   - Remove autotools build files (optional, for final release)
   - Update `INSTALL` instructions
   - Create release notes

**Deliverables:**
- Complete documentation in `docs/cxx-builder/`
- GitHub Actions CI/CD workflow
- Contributor migration guide

**Success Criteria:**
- Documentation is complete and accurate
- CI/CD pipeline works
- Project can be built with CMake only

---

## CMake Build System Design

### Root CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.20)
project(Emacs VERSION 31.0 LANGUAGES C CXX)

# C++20 Standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Build options
option(BUILD_WITH_AUTOTOOLS "Build with autotools (legacy)" ON)
option(BUILD_TESTS "Build test suite" ON)
option(BUILD_NATIVE_COMP "Build with native compilation" ON)

# Dual build system support
if(BUILD_WITH_AUTOTOOLS)
    message("=== Building with Autotools ===")
    add_custom_target(autotools
        COMMAND ./autogen.sh && ./configure ${EMACS_CONFIGURE_OPTIONS}
        COMMAND make -j${BUILD_JOBS}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    add_custom_target(build_autotools ALL DEPENDS autotools)
else()
    message("=== Building with CMake + C++20 ===")
endif()

# vcpkg integration
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/vcpkg.json")
    set(VCPKG_MANIFEST_MODE ON)
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
    set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/install")
endif()

# Dependencies
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)
find_package(PNG)
find_package(JPEG)
find_package(TIFF)
find_package(GIF)
find_package(GNUTLS)
find_package(SQLite3)
find_package(LibXml2)
find_package(GMP)
find_package(TreeSitter)

# Subdirectories
add_subdirectory(lib)
add_subdirectory(src)
add_subdirectory(lwlib)
add_subdirectory(lib-src)
add_subdirectory(test)

# Installation
install(TARGETS emacs
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib)
```

### src/CMakeLists.txt

```cmake
# Source code build configuration
add_library(emacs_core OBJECT
    alloc.cpp
    data.cpp
    eval.cpp
    lisp_interface.cpp
    bytecode.cpp
    main.cpp
    term.cpp
    dispnew.cpp
    terminal.cpp
    fileio.cpp
    sysdep.cpp
    # ... more source files
)

target_include_directories(emacs_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)

target_compile_features(emacs_core PUBLIC cxx_std_20)

# Platform-specific sources
if(WIN32)
    target_sources(emacs_core PRIVATE
        w32gui.cpp
        w32console.cpp
        w32term.cpp
    )
elseif(APPLE)
    target_sources(emacs_core PRIVATE
        nsterm.mm
        nsfns.mm
    )
elseif(UNIX AND NOT APPLE)
    target_sources(emacs_core PRIVATE
        xterm.cpp
        xfns.cpp
    )
endif()

# Link with existing C libraries
target_link_libraries(emacs_core PUBLIC
    Threads::Threads
    ZLIB::ZLIB
    PNG::PNG
    JPEG::JPEG
    TIFF::TIFF
    GNUTLS::GNUTLS
    SQLite3::SQLite3
    LibXml2::LibXml2
    GMP::GMP
    TreeSitter::TreeSitter
)

# Main executable
add_executable(emacs main.cpp)
target_link_libraries(emacs PRIVATE emacs_core)

# C library bridge (for linking with legacy code)
add_library(emacs_c_bridge INTERFACE
    target_sources(emacs_c_bridge INTERFACE
        # List all C files that remain
        emacs.c
        buffer.c
        window.c
        # ... etc
    )
)
```

### vcpkg.json

```json
{
  "name": "emacs",
  "version-string": "31.0.50",
  "description": "GNU Emacs text editor - C++20 migration",
  "dependencies": [
    {
      "name": "zlib",
      "platform": "!windows"
    },
    {
      "name": "libpng",
      "platform": "!windows"
    },
    {
      "name": "libjpeg-turbo",
      "platform": "!windows"
    },
    {
      "name": "libtiff",
      "platform": "!windows"
    },
    {
      "name": "giflib",
      "platform": "!windows"
    },
    {
      "name": "gnutls",
      "platform": "!windows"
    },
    {
      "name": "sqlite3"
    },
    {
      "name": "libxml2"
    },
    {
      "name": "gmp"
    },
    {
      "name": "tree-sitter-cpp"
    }
  ],
  "features": {
    "tests": {
      "description": "Build test suite",
      "dependencies": [
        "gtest"
      ]
    },
    "native-comp": {
      "description": "Build with native compilation",
      "dependencies": [
        "libgccjit"
      ]
    },
    "x11": {
      "description": "Build with X11 support",
      "dependencies": [
        "xorg",
        "gtk3"
      ]
    },
    "windows": {
      "description": "Build with Windows GUI",
      "dependencies": [
        "directx"
      ]
    },
    "haiku": {
      "description": "Build with Haiku OS support"
    },
    "android": {
      "description": "Build with Android support",
      "dependencies": [
        "android-ndk"
      ]
    }
  }
}
```

---

## GitHub Actions Workflow

### .github/workflows/cxx-builder.yml

```yaml
name: C++20 Build and Test

on:
  push:
    branches: [cxx-builder, cxx-build-step-*]
  pull_request:
    branches: [cxx-builder]
  schedule:
    # Weekly on Sunday at 00:00 UTC
    - cron: '0 0 * * 0'
  workflow_dispatch:

env:
  VCPKG_VERSION: "2025-01-08"
  CMAKE_VERSION: "3.29"

jobs:
  # Job 1: Multi-platform Build
  build:
    name: Build (${{ matrix.os }}, ${{ matrix.build-type }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        build-type: [cmake, cmake-release]
        include:
          - os: ubuntu-latest
            vcpkg_triplet: x64-linux
          - os: macos-latest
            vcpkg_triplet: x64-osx
          - os: windows-latest
            vcpkg_triplet: x64-windows
        exclude:
          - os: windows-latest
            build-type: cmake  # Debug builds on Windows are slow
          - os: macos-latest
            build-type: cmake  # Debug builds on macOS are slow

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install vcpkg
        uses: lukka/run-vcpkg@v11
        with:
          vcpkgJsonPath: vcpkg.json
          vcpkgTriplet: ${{ matrix.vcpkg_triplet }}

      - name: Setup CMake
        uses: lukka/run-cmake@v10
        with:
          buildType: ${{ matrix.build-type == 'cmake' && 'Debug' || 'Release' }}
          vcpkgJsonPath: vcpkg.json

      - name: Build with CMake
        uses: lukka/run-cmake@v10
        with:
          arguments: --build --config ${{ matrix.build-type == 'cmake' && 'Debug' || 'Release' }}

      - name: Test basic execution
        run: |
          if [ "${{ matrix.build-type }}" = "cmake" ]; then
            ./build-cpp/bin/emacs --version
          else
            ./build-cpp/bin/emacs --version
          fi

      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: emacs-${{ matrix.os }}-${{ matrix.build-type }}
          path: |
            build-cpp/bin/emacs
            build-cpp/lib/
          retention-days: 7

  # Job 2: C Test Suite
  c-tests:
    name: C Tests
    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install vcpkg
        uses: lukka/run-vcpkg@v11
        with:
          vcpkgJsonPath: vcpkg.json

      - name: Setup CMake
        uses: lukka/run-cmake@v10
        with:
          buildType: Release
          vcpkgJsonPath: vcpkg.json

      - name: Build
        uses: lukka/run-cmake@v10
        with:
          arguments: --build --config Release

      - name: Run C tests
        run: |
          cd build-cpp && ctest --output-on-failure

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: c-test-results
          path: build-cpp/Testing/
          retention-days: 30

  # Job 3: Lisp Test Suite
  lisp-tests:
    name: Lisp Tests
    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install vcpkg
        uses: lukka/run-vcpkg@v11
        with:
          vcpkgJsonPath: vcpkg.json

      - name: Setup CMake
        uses: lukka/run-cmake@v10
        with:
          buildType: Release
          vcpkgJsonPath: vcpkg.json

      - name: Build
        uses: lukka/run-cmake@v10
        with:
          arguments: --build --config Release

      - name: Run Lisp tests
        run: |
          ./build-cpp/bin/emacs -batch -l ert -l test/lisp --eval "(ert-run-tests-batch-and-exit)"

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: lisp-test-results
          path: test/**/*.log
          retention-days: 30

  # Job 4: Memory Leak Detection
  memory-check:
    name: Memory Leak Detection
    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install vcpkg
        uses: lukka/run-vcpkg@v11
        with:
          vcpkgJsonPath: vcpkg.json

      - name: Setup CMake
        uses: lukka/run-cmake@v10
        with:
          buildType: Debug
          vcpkgJsonPath: vcpkg.json

      - name: Build with sanitizers
        run: |
          cmake -B build-cpp -S . \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_CXX_FLAGS="-fsanitize=address -fno-omit-frame-pointer" \
            -DCMAKE_LINKER_FLAGS="-fsanitize=address"

      - name: Run with Valgrind/ASAN
        run: |
          cd build-cpp && ./bin/emacs --batch --eval "(message \"OK\") (kill-emacs)"

      - name: Upload memory report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: memory-report
          path: build-cpp/*.log
          retention-days: 30
```

---

## Risk Mitigation

### 1. Build System Complexity

**Risk:** Managing dual build systems (autotools + CMake).

**Mitigation:**
- Use CMake as primary, autotools as fallback
- Document clear separation of concerns
- Automate synchronization between systems

### 2. Binary Compatibility

**Risk:** C++ name mangling vs C linkage.

**Mitigation:**
- Use `extern "C"` for all C interfaces
- Maintain C ABI for public APIs
- Test cross-language linking extensively

### 3. Performance Regression

**Risk:** C++ overhead (exceptions, RTTI, etc.).

**Mitigation:**
- Use `-fno-exceptions` for critical paths
- Benchmark at every phase
- Profile hot paths aggressively

### 4. gnulib Dependency Hell

**Risk:** Removing gnulib breaks platform compatibility.

**Mitigation:**
- Progressive replacement with testing
- Maintain compatibility layer during transition
- Test on all platforms (Linux, macOS, Windows, Haiku, Android)

### 5. Upstream Sync Conflicts

**Risk:** C++ migration diverges from upstream Emacs.

**Mitigation:**
- Keep original C files intact
- Use feature flags to enable/disable C++ code
- Regular upstream merges with conflict resolution

---

## Success Metrics

### Phase Completion Criteria

Each phase must meet the following criteria before proceeding:

1. **Tests:** All existing tests pass
2. **Performance:** Within 10% of C implementation
3. **Memory:** No memory leaks (Valgrind/ASAN clean)
4. **Platforms:** Works on Linux, macOS, Windows
5. **Documentation:** Updated and accurate

### Overall Success Criteria

Project is considered complete when:

1. **CMake Build:** Primary build system
2. **C++20 Codebase:** 100% core code in C++
3. **gnulib-Free:** No gnulib dependencies
4. **Cross-Platform:** Tested on all supported platforms
5. **CI/CD:** Automated testing and release
6. **Documentation:** Complete migration guide
7. **Performance:** Equal or better than C implementation
8. **Community Ready:** Contributors can build and develop

---

## Testing Strategy

### Incremental Testing

**Principle:** Test each migration incrementally.

**Workflow:**
```bash
# For each migrated module
1. Build CMake target for module
2. Run module-specific tests
3. Run integration tests
4. Benchmark performance
5. If all pass → commit
6. If any fail → rollback and fix
```

### Test Categories

1. **Unit Tests:** Individual component tests
2. **Integration Tests:** Cross-component tests
3. **Lisp Tests:** Emacs Lisp test suite
4. **GUI Tests:** Platform-specific GUI tests
5. **Performance Tests:** Benchmark suite
6. **Memory Tests:** Leak detection

### Platform Testing Matrix

| Platform | Priority | Test Coverage |
|----------|----------|----------------|
| Linux (Ubuntu) | HIGH | Full |
| macOS | HIGH | Full |
| Windows | MEDIUM | Core + GUI |
| Haiku | LOW | Core |
| Android | LOW | Core |

---

## Upstream Synchronization Strategy

### Regular Merge Process

1. **Weekly Upstream Merge:**
   ```bash
   git fetch upstream
   git merge upstream/master
   # Resolve conflicts (mostly in C files we retain)
   # Test C++ build
   # Commit if successful
   ```

2. **Conflict Resolution:**
   - Keep upstream C files unchanged
   - Update C++ wrappers as needed
   - Document divergences in `docs/cxx-builder/divergences.md`

3. **Cherry-Pick Strategy:**
   - For bug fixes: cherry-pick to C++ branch
   - For new features: evaluate impact on C++ code
   - For large changes: defer until stable

### Feature Flags

```cpp
// Use feature flags to enable/disable C++ implementations
#ifdef USE_CPP20_ALLOCATOR
    // C++20 allocator
#else
    // Original C allocator
#endif
```

---

## Documentation Structure

```
docs/cxx-builder/
├── README.md                    # Main documentation index
├── strategy.md                  # This document
├── phases/                      # Phase-specific documentation
│   ├── phase0-foundation.md
│   ├── phase1-infrastructure.md
│   ├── phase2-entry-point.md
│   ├── phase3-terminal.md
│   ├── phase4-lisp-core.md
│   ├── phase5-gui.md
│   ├── phase6-fileio.md
│   ├── phase7-testing.md
│   └── phase8-cleanup.md
├── progress/                    # Progress tracking
│   ├── phase-tracker.md
│   └── status-report.md
├── technical/                   # Technical deep-dives
│   ├── gnulib-replacement.md
│   ├── cmake-patterns.md
│   └── tui-redesign.md
└── reference/                   # Reference material
    ├── c++20-features.md
    └── platform-abstraction.md
```

---

## Next Steps

### Immediate Actions (This Week)

1. ✅ Review and approve this strategy document
2. ⬜ Create `CMakeLists.txt` (root) with basic structure
3. ⬜ Create `vcpkg.json` with dependencies
4. ⬜ Create `.github/workflows/cxx-builder.yml`
5. ⬜ Set up `build.sh` dual-build script
6. ⬜ Create `docs/cxx-builder/` directory structure

### Phase 0 Tasks (Week 1-2)

See Phase 0 section above.

---

## Conclusion

This strategy provides a **comprehensive, incremental, and low-risk** path to migrating GNU Emacs to C++20 while:

- ✅ Maintaining upstream compatibility
- ✅ Ensuring continuous testability
- ✅ Eliminating gnulib dependencies
- ✅ Improving Windows TUI support
- ✅ Preparing for SDL3 integration
- ✅ Using modern CMake + vcpkg build system
- ✅ Providing full C++20 language features

The **key principle** is: **incremental migration with continuous validation**.

Each phase must pass all tests and meet performance criteria before proceeding to the next phase.

---

## Appendix: Resources

### External References

1. **CMake Documentation:** https://cmake.org/documentation/
2. **vcpkg Documentation:** https://vcpkg.io/en/
3. **C++20 Reference:** https://en.cppreference.com/w/cpp/20
4. **Neovim TUI:** https://neovim.io/doc/dev/internals/ui.html
5. **LLVM Migration:** https://llvm.org/docs/GettingStarted.html

### Internal References

1. **Emacs Build System:** `configure.ac`, `src/Makefile.in`
2. **gnulib Modules:** `lib/gnulib.mk`
3. **Existing C++ Files:** `src/haiku_*.cc`, `src/Makefile.in`
4. **Test Suite:** `test/README`

---

**Document Status:** Draft v1.0
**Next Review:** Week 1, Phase 0 Kickoff
**Owner:** Migration Team
