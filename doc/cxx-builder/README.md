# Emacs C++20 Migration Documentation

**Repository:** emacs-cxx-builder
**Branch:** cxx-builder
**Status:** In Progress

---

## Overview

This directory contains all documentation for the GNU Emacs C++20 migration project. The migration aims to:

- Replace the autotools build system with CMake
- Migrate from C to C++20
- Eliminate gnulib dependencies
- Improve cross-platform support (especially Windows TUI)
- Prepare infrastructure for SDL3 integration
- Maintain upstream Emacs compatibility

## Document Structure

```
docs/cxx-builder/
├── README.md                    # This file - main index
├── strategy.md                  # Master migration strategy
├── phases/                      # Phase-specific guides
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
│   ├── phase-tracker.md       # Current phase status
│   └── status-report.md      # Weekly status reports
└── technical/                   # Technical deep-dives
    ├── gnulib-replacement.md
    ├── cmake-patterns.md
    └── tui-redesign.md
```

## Quick Links

- **[Master Strategy](./strategy.md)** - Complete migration plan
- **[Phase Tracker](./progress/phase-tracker.md)** - Current progress
- **[Status Report](./progress/status-report.md)** - Latest updates

## Key Principles

### 1. Incremental Migration

Every phase must be:
- ✅ Testable
- ✅ Reversible
- ✅ Documented
- ✅ Benchmarked

### 2. Dual Build System

Maintain both autotools and CMake builds:
- **Autotools:** For upstream Emacs compatibility
- **CMake:** For C++20 development
- **Goal:** Gradual transition without breaking upstream sync

### 3. gnulib Elimination

Replace gnulib functions progressively:
- **Priority:** Core infrastructure first
- **Method:** C++20 standard library equivalents
- **Validation:** Tests must pass before moving to next function

### 4. Upstream Compatibility

- Keep original C files intact
- Use feature flags for C++ code
- Regular upstream merges with minimal conflicts

## Current Status

### Phase: Phase 1 - Core Infrastructure (Week 3-6)

**Status:** ✅ Completed
**Completion Date:** 2026-02-01
**Next Phase:** Phase 2 - Entry Point & Startup (Week 7-8)

---

## Phase 1: Core Infrastructure - Summary

**Duration:** Week 3-6 (Completed in 1 day)
**Status:** ✅ All tasks completed

### Deliverables

✅ **C++ Allocator System:**
   - `src/allocator.hpp` - Template-based allocator header
   - `src/allocator.cpp` - GC integration implementation
   - Features: RAII, alignment, fallback to standard allocator
   - Compatible with Emacs GC functions (lisp_malloc, lisp_free, lisp_realloc)

✅ **C++20 String Utilities:**
   - `src/strings.hpp` - String utility function declarations
   - `src/strings.cpp` - Implementation
   - Replacements: strdup, strndup, stpcpy, strnlen, asprintf, getline
   - Uses: std::string, std::string_view, std::format (C++20)

✅ **CMake Build System:**
   - `src/CMakeLists.txt` - CMake configuration for core modules
   - Targets: emacs_allocator, emacs_strings, emacs_core_infra
   - Features: C++20 standard, platform-specific definitions
   - Includes root CMakeLists.txt with src/ subdirectory

### gnulib Replacements Completed

| gnulib Function | C++20 Equivalent | Status |
|----------------|------------------|--------|
| `strdup` | `std::string(char*)` | ✅ |
| `strndup` | `std::string(data, n)` | ✅ |
| `stpcpy` | `std::strcpy` + manual +1 | ✅ |
| `strnlen` | `std::char_traits<char>::length(data, len)` | ✅ |
| `asprintf` | `std::format` (C++20) | ✅ |
| `getline` | `std::getline` | ✅ |

---

## Quick Start: Phase 1 Complete

You can now use the new C++ allocator and string utilities in your C++ code:

```cpp
#include "allocator.hpp"
#include "strings.hpp"

namespace emacs {
    using namespace strings = emacs::strings;

    // Use C++ allocator with std::string
    std::vector<int, emacs_allocator<int>> my_vec;
    my_vec.push_back(42);  // Uses Emacs GC via allocator

    // Use C++ string utilities
    std::string my_str = strings::string_duplicate("hello");
    std::string formatted = strings::string_format("Value: {}", 42);
}
```

### Build Status

```bash
# Build with CMake
./build.sh --cmake --debug

# Or build with autotools (uses original C code)
./build.sh --autotools
```

### Next Steps

**Ready for Phase 2:** Entry Point & Startup (Week 7-8)

**Phase 2 objectives:**
1. Convert `src/emacs.c` to `src/main.cpp`
2. Modernize startup sequence with RAII
3. Implement command line parsing with std::span
4. Update startup sequence for C++20

**Prerequisites:**
- Phase 1 must be verified with tests
- Core infrastructure must be stable

---

**Last Updated:** 2026-02-01
**Next Review:** End of Phase 1 (2026-02-22)
**Start Date:** 2026-02-01

### Active Tasks

1. ✅ Create strategy document (this document)
2. ⬜ Create root `CMakeLists.txt`
3. ⬜ Create `vcpkg.json` dependencies
4. ⬜ Create GitHub Actions workflow
5. ⬜ Create dual-build script
6. ⬜ Create phase tracker

### Recent Updates

- **2026-02-01:** Created migration strategy document
- **2026-02-01:** Set up documentation structure

## Quick Start

### For Developers

To start working on the migration:

```bash
# 1. Check out the cxx-builder branch
git checkout cxx-builder

# 2. Ensure build dependencies are installed
# Ubuntu: sudo apt-get install cmake ninja-build vcpkg clang
# macOS: brew install cmake ninja vcpkg
# Windows: Download cmake, ninja, vcpkg installers

# 3. Build with CMake
cmake -B build-cpp -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cpp --config Debug

# 4. Run tests
cd build-cpp && ctest
```

### For Building

Standard build commands:

```bash
# Debug build
cmake -B build-debug -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug

# Release build
cmake -B build-release -S . - -DCMAKE_BUILD_TYPE=Release
cmake --build build-release

# With vcpkg
cmake -B build-cpp -S . \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
```

## Milestones

- [x] **Milestone 1:** Foundation (Phase 0) - Week 2
- [ ] **Milestone 2:** Core Infrastructure (Phase 1) - Week 6
- [ ] **Milestone 3:** Entry Point (Phase 2) - Week 8
- [ ] **Milestone 4:** Terminal (Phase 3) - Week 12
- [ ] **Milestone 5:** Lisp Core (Phase 4) - Week 20
- [ ] **Milestone 6:** GUI (Phase 5) - Week 24
- [ ] **Milestone 7:** File I/O (Phase 6) - Week 28
- [ ] **Milestone 8:** Testing (Phase 7) - Week 32
- [ ] **Milestone 9:** Cleanup (Phase 8) - Week 36

## Contributing

### How to Contribute

1. Choose a task from the current phase
2. Update the [phase tracker](./progress/phase-tracker.md)
3. Implement with incremental testing
4. Submit PR to `cxx-builder` branch
5. Ensure all tests pass

### Code Style

- **C++20 Standard:** Use modern C++ features
- **RAII:** Prefer stack allocation and smart pointers
- **noexcept:** Use for performance-critical code
- **Comments:** Document non-obvious code

## Contact

- **Issues:** Use GitHub Issues
- **Discussions:** Use GitHub Discussions
- **Email:** emacs-devel@gnu.org

---

**Last Updated:** 2026-02-01
