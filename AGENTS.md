# AGENTS.md - GNU Emacs C++20 Migration Guide

**Project**: GNU Emacs - C++20 Migration Branch  
**Build System**: CMake (C++20) + autotools (legacy)  
**Language**: C11 → C++20 (incremental migration)  
**Current Phase**: Phase 4 - Terminal/TUI (Phase 0-3 Complete ✅)  
**Overall Progress**: 31.4%  
**Last Updated**: 2026-02-05  

---

## 🎯 Migration Status

```
Phase 0: Foundation Setup        ████████████████  100%  ✅
Phase 1: Core Infrastructure     ████████████████  100%  ✅
Phase 2: Entry Point & Startup  ████████████████  100%  ✅
Phase 3: Shared Infrastructure  ████████████████  100%  ✅
Phase 4: Terminal/TUI          ░░░░░░░░░░░░░░░░    0%  ← NEXT
Phase 5: Lisp Interpreter Core  ░░░░░░░░░░░░░░░░    0%
Phase 6-9: GUI, I/O, Test      ░░░░░░░░░░░░░░░░    0%
```

**Completed Modules:**
- ✅ Memory allocator (GC-aware C++20 allocator)
- ✅ String utilities (std::string, std::format replacements)
- ✅ Error handling (Result<T>, exceptions)
- ✅ Logging (structured thread-safe logging)
- ✅ Platform abstraction (OS/arch detection)
- ✅ GC-aware containers (gc_vector, gc_string, etc.)
- ✅ Entry point (C++20 main with RAII)
- ✅ Termbox2 TUI backend (working demo)

**Next Priority:** Phase 4 - Custom TUI (replace termbox2, fix Windows)

---

## 🔨 Build Commands

### CMake Build (Primary - C++20)
```bash
# Configure (Debug)
cmake -B build-cpp -S . -DCMAKE_BUILD_TYPE=Debug

# Build
cmake --build build-cpp --config Debug

# Release build
cmake -B build-release -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --config Release

# Using build script (recommended)
./build.sh --cmake --debug
./build.sh --cmake --release
```

### Autotools Build (Legacy - upstream compatibility)
```bash
# Generate configure script (first time)
./autogen.sh

# Configure and build
./configure && make -j$(nproc)

# Or use build script
./build.sh --autotools
```

---

## 🧪 Test Commands

### All Tests
```bash
# CMake/CTest (C++ modules)
cd build-cpp && ctest --output-on-failure

# Make (Emacs Lisp tests - default, excludes expensive/unstable)
cd test && make check

# All tests including expensive
cd test && make check-all

# Or from project root
make check
```

### Single Test
```bash
# Lisp/ERT tests (by filename)
cd test && make lisp/abbrev-tests          # Output to terminal
cd test && make lisp/abbrev-tests.log      # Output to log file
cd test && make abbrev-tests               # Short form

# With specific test selector
cd test && make <filename> SELECTOR='test-foo'

# C++ tests (run executables directly)
./build-cpp/bin/emacs_minimal
./build-cpp/bin/emacs_tui_demo

# C++ unit tests (compile and run)
cd test/cxx
g++ -std=c++20 -I../../src smoke_test.cpp -o smoke_test && ./smoke_test
```

### Test Subsets
```bash
# By directory
cd test && make check-src          # C core tests only
cd test && make check-lisp         # Lisp tests only
cd test && make check-lib-src      # Lib-src tests

# By ERT selector
cd test && make check SELECTOR='(not (tag :expensive-test))'
cd test && make <file> SELECTOR='(tag :unstable)'

# Summarize slowest tests
cd test && make SUMMARIZE_TESTS=10 check
```

---

## 📝 Code Style Guidelines

### C++20 Standards
- **Language**: C++20 standard (CMAKE_CXX_STANDARD 20)
- **Extensions**: OFF (CMAKE_CXX_EXTENSIONS OFF)
- **Compiler Flags**: `-Wall -Wextra -Wpedantic -Wno-unused-variable`
- **Standard Library**: Prefer C++20 `std::*` over gnulib functions

### Formatting (clang-format)
```bash
# Format all C++ files
clang-format -i src/**/*.cpp src/**/*.hpp

# Check formatting without modifying
clang-format --dry-run --Werror src/**/*.cpp
```

**Configuration** (.clang-format):
- **Style**: GNU
- **Column Limit**: 70
- **Indent**: Tabs (UseTab: Always)
- **Brace Style**: GNU (break before braces)
- **Include Order**: config.h > system > lisp.h > local

### Naming Conventions

**C Code (Legacy - Preserve)**:
```c
void snake_case_function();          // Functions
#define UPPER_CASE_MACRO 42          // Macros
struct buffer { ... };               // Types
```

**C++ Code (New)**:
```cpp
class StartupResourceManager {};     // Classes: PascalCase
void init_emacs();                   // Functions: snake_case()
bool initialized_;                   // Members: snake_case_
namespace emacs { }                  // Namespaces: lowercase
```

**Files**:
- C code: `foo.c`, `foo.h`
- C++20 code: `foo.cpp`, `foo.hpp`

### Include Order (REQUIRED)

```cpp
#include <config.h>              // 1. MUST be first
#include <algorithm>             // 2. System headers
#include <string>
#include "lisp.h"                // 3. Core Emacs headers
#include "allocator.hpp"         // 4. Local headers
```

**Why config.h first?** Contains platform-specific definitions and feature macros that affect system headers.

### Modern C++20 Features (USE THESE!)

```cpp
// Attributes (1,393 uses in codebase)
[[nodiscard]] T* allocate(size_t n);     // Must use return value
[[maybe_unused]] int argc;               // Intentionally unused
[[noreturn]] void fatal_error();         // Never returns

// noexcept (use for performance-critical paths)
void deallocate(T* ptr) noexcept;

// constexpr (compile-time evaluation)
constexpr bool is_windows = PLATFORM == WINDOWS;

// if constexpr (zero runtime overhead)
if constexpr (platform == Windows) {
    // Windows-specific code
} else {
    // Unix-specific code
}

// C++20 concepts
template<typename T>
concept TerminalBackend = requires(T t) {
    { t.init() } -> std::same_as<void>;
    { t.write_glyphs() } -> std::same_as<void>;
};

// Modern types
std::span<char*> args;              // Array view
std::string_view message;           // Non-owning string
std::optional<int> maybe_value;     // Nullable value
auto result = std::format("Val: {}", 42);  // C++20 formatting
```

### Type Patterns

**Preserve C Types** (for ABI compatibility):
```c
typedef long int EMACS_INT;         // From lisp.h
struct Lisp_String { ... };
```

**Use C++20 Types** (in new code):
```cpp
// Type aliases
using string_view = std::string_view;
using span_t = std::span<char*>;

// GC-aware containers (use emacs_allocator!)
std::vector<int, emacs_allocator<int>> gc_vec;
gc_vector<char> str;  // Type alias in containers.hpp

// Preserve Lisp objects with extern "C"
extern "C" {
    struct Lisp_Object { ... };
}
```

### Error Handling Patterns

**C Style** (legacy compatibility):
```c
if (error_condition) {
    fatal("Error: %s", reason);
    return NULL;
}
```

**C++ Style** (new code - TWO approaches):

**Approach 1: noexcept + return codes** (prefer for performance):
```cpp
[[nodiscard]] bool try_operation() noexcept {
    if (error_condition) {
        return false;  // Error
    }
    return true;  // Success
}
```

**Approach 2: Exceptions** (use sparingly):
```cpp
void risky_operation() {
    if (error_condition) {
        throw gnu_error("Operation failed");
    }
}

// Catch at top level
try {
    risky_operation();
} catch (const std::exception& e) {
    std::cerr << "Error: " << e.what() << "\n";
    return EXIT_FAILURE;
}
```

### Memory Management (CRITICAL!)

**Core Principle**: Always use Emacs GC-aware allocator in new C++ code

```cpp
// ALWAYS use emacs_allocator for heap allocation
#include "allocator.hpp"

// With STL containers (RECOMMENDED)
std::vector<int, emacs_allocator<int>> gc_vec;
gc_vector<char> gc_str;  // Type alias
gc_string msg;           // Type alias for std::basic_string with GC

// Direct allocation (if needed)
emacs_allocator<MyType> alloc;
MyType* ptr = alloc.allocate(1);
// ... use ptr ...
alloc.deallocate(ptr, 1);

// RAII pattern for resources
class ResourceGuard {
public:
    ResourceGuard() = default;
    ~ResourceGuard() { cleanup(); }  // Automatic cleanup
};
```

**DON'T**:
```cpp
// ❌ DON'T use raw new/delete (breaks GC!)
auto* ptr = new int[100];  // BAD!
delete[] ptr;

// ❌ DON'T use std::vector without allocator
std::vector<int> vec;  // BAD! Won't integrate with GC
```

**DO**:
```cpp
// ✅ DO use GC-aware containers
gc_vector<int> vec;  // GOOD!
vec.push_back(42);   // Uses lisp_malloc internally

// ✅ DO use RAII
StartupResourceManager resources;  // Automatic cleanup on scope exit
```

### extern "C" Bridges (ABI Compatibility)

**Why?** Maintain compatibility between C++ and existing C code

```cpp
// In header (.hpp):
extern "C" {
    // C functions callable from C++
    void *lisp_malloc(size_t size);
    void lisp_free(void *ptr);
    
    // C++ functions callable from C
    int display_init_c();
    int display_update_c(int *rows, int *cols);
}

// In implementation (.cpp):
extern "C" int display_init_c() {
    try {
        Display::instance().init();
        return 0;
    } catch (...) {
        return -1;  // Never let C++ exceptions cross to C!
    }
}
```

**CRITICAL RULE**: Never let C++ exceptions cross extern "C" boundary!

---

## 🏗️ Migration Strategy & Principles

### Core Principles (READ THESE!)

1. **Retain Original C Code**: Keep `.c` files unchanged for upstream compatibility
2. **Create C++ Wrappers**: New `.cpp/.hpp` files provide C++20 interfaces
3. **Use `extern "C"`**: All C↔C++ calls must maintain ABI compatibility
4. **Eliminate gnulib**: Replace with C++20 `std::*` equivalents (in progress)
5. **RAII First**: Prefer smart pointers and RAII over manual resource management
6. **noexcept for Performance**: Use on hot paths (no exception overhead)
7. **Test Everything**: Each phase must pass all tests before moving forward

### Dual-Build Strategy

**Maintain both build systems during migration:**
- **CMake (C++20)**: For active migration development
- **Autotools (C11)**: For upstream Emacs compatibility

**Timeline:**
- Phase 0-4: Both active (currently here)
- Phase 5: CMake becomes CI-authoritative
- Phase 6: Autotools frozen
- Phase 8-9: Autotools removed (after 2 release cycles)

### gnulib Replacement Status

**Completed ✅:**
| Category | Functions | C++20 Equivalent |
|----------|-----------|------------------|
| Strings | strdup, strndup, stpcpy, strnlen | std::string, std::string_view |
| Strings | asprintf, getline | std::format, std::getline |
| Memory | malloc, realloc, free | emacs_allocator<T> |

**Pending ⬜:**
| Category | Functions | Target Phase |
|----------|-----------|--------------|
| File I/O | faccessat, lstat, tempfile | Phase 7 |
| Locale | mbrtowc, wcwidth, iswprint | Phase 5 |
| Time | gettimeofday, nanosleep | Phase 7 |
| Regex | regcomp, regexec | Phase 5 |

---

## 📦 CMake Targets & Modules

### Libraries (Built)
```bash
# View all targets
cd build-cpp && make help

# Core modules
emacs_allocator          # GC-aware C++20 allocator
emacs_strings            # String utilities (currently disabled)
emacs_termbox2_backend   # TUI backend
emacs_gnulib_replacement # gnulib → std:: replacements (header-only)
emacs_terminal_concept   # Terminal interface concept (header-only)
```

### Executables
```bash
emacs_minimal       # Minimal Phase 2 validation (working)
emacs_tui_demo      # TUI demonstration (working)
```

### Header-Only Libraries
- `emacs_terminal_concept` - C++20 concepts for terminal backends
- `emacs_gnulib_replacement` - 32 headers replacing gnulib modules

---

## ⚠️ Known Issues & Blockers

### Critical Issues:

1. **strings.hpp TEMPORARILY DISABLED**
   - **Reason**: SDK header conflicts (read_line, getline redefinition)
   - **Impact**: Can't use std::format in main.cpp
   - **Workaround**: Using iostream for Phase 2
   - **Fix Target**: Phase 6 (File I/O & System)
   
2. **Windows TUI Not Implemented** (HIGHEST PRIORITY)
   - **Status**: Phase 4 not started
   - **Risk**: HIGH (Emacs on Windows barely usable)
   - **Plan**: Custom implementation with VT100 + Console API fallback
   - **Dependencies**: libuv, unibilium

3. **Platform Terminal Backends are Stubs**
   - Only Termbox2Backend fully implemented (555 lines)
   - xterm, nsterm, w32term, haikuterm, androidterm are placeholders
   - **Fix Target**: Phase 4 (Terminal/TUI)

### Medium Issues:

4. **gnulib Unicode Limitation**
   - Full Unicode character properties require ICU library
   - Currently using std::locale + std::wcwidth
   - May need vcpkg integration for ICU

5. **Dual-Build Drift**
   - CMake and autotools may diverge over time
   - **Mitigation**: CI checks, monthly verification
   
---

## 📚 Documentation References

**Essential Reading:**
- `doc/cxx-builder/README.md` - Migration overview
- `doc/cxx-builder/strategy-v2.md` - Complete migration strategy
- `doc/cxx-builder/progress/phase-tracker.md` - Current status
- `doc/cxx-builder/phases/phase4-lisp-core.md` - Next phase details

**Technical Deep-Dives:**
- `doc/cxx-builder/technical/gnulib-replacement.md` - gnulib → std:: mapping
- `doc/cxx-builder/technical/tui-architecture.md` - TUI design (Phase 4)

**Code Examples:**
- `src/allocator.hpp` - GC-aware allocator pattern
- `src/main_minimal.cpp` - RAII entry point pattern
- `src/termbox2_term.cpp` - Terminal backend implementation (555 lines)
- `src/platform.hpp` - constexpr platform detection (432 lines)

---

## 🎓 Quick Reference for AI Agents

### When Writing New C++ Code:

```cpp
// Template for new .cpp file
#include <config.h>        // ALWAYS FIRST!
#include <algorithm>       // System headers
#include <string>
#include "lisp.h"          // Core Emacs
#include "allocator.hpp"   // Local headers

namespace emacs {

class MyFeature {
private:
    bool initialized_ = false;  // Trailing underscore
    
public:
    [[nodiscard]] bool init() noexcept;
    void cleanup() noexcept;
};

// Use GC-aware containers
gc_vector<int> data_;

}  // namespace emacs

// Extern "C" bridge for C code
extern "C" {
int my_feature_init() {
    try {
        return emacs::MyFeature::instance().init() ? 0 : -1;
    } catch (...) {
        return -1;  // Never propagate exceptions to C!
    }
}
}
```

### Common Patterns:

```cpp
// RAII resource management
class ResourceGuard {
public:
    ResourceGuard() { acquire(); }
    ~ResourceGuard() { release(); }
    // Delete copy, allow move
    ResourceGuard(const ResourceGuard&) = delete;
    ResourceGuard(ResourceGuard&&) noexcept = default;
};

// Platform-specific code
if constexpr (Platform::is_windows()) {
    // Windows implementation
} else if constexpr (Platform::is_unix()) {
    // Unix implementation
}

// GC-aware allocation
gc_vector<MyType> vec;  // Uses lisp_malloc
vec.push_back(obj);      // Automatically managed

// Error handling (prefer noexcept)
[[nodiscard]] bool safe_operation() noexcept {
    if (error_check()) return false;
    return true;
}
```

---

## 🎯 Migration Target & Next Steps

### Current Migration Target: Phase 4 - Terminal/TUI

**Objective**: Replace termbox2 with robust cross-platform terminal implementation

**Why Phase 4 is Critical:**
- Windows TUI currently broken/barely usable (HIGHEST PRIORITY)
- Termbox2 is a temporary stopgap (Phase 3 validation only)
- Need libuv-based event loop for proper async I/O
- Must support mouse, UTF-8/CJK, and modern terminal features

### Phase 4 Architecture:
```
User Input → libuv Event Loop → Input Parser (libtermkey-style)
                                      ↓
                                Grid Renderer (double-buffered)
                                      ↓
                         Terminal Backend (Platform-specific)
                                      ↓
                         Unix (terminfo) | Windows (VT100/Console API) | macOS
```

### Phase 4 Tasks (6 weeks, ~40 days):

| ID | Task | Days | Priority | Status |
|----|------|------|----------|--------|
| 4.1 | Design TUI architecture doc | 2 | HIGH | ⬜ |
| 4.2 | Integrate libuv event loop | 3 | HIGH | ⬜ |
| 4.3 | Implement input parser | 5 | HIGH | ⬜ |
| 4.4 | Implement capabilities provider | 3 | HIGH | ⬜ |
| 4.5 | Implement Unix backend | 4 | HIGH | ⬜ |
| 4.6 | **Implement Windows backend (VT)** | **6** | **CRITICAL** | ⬜ |
| 4.7 | Implement Grid + renderer | 5 | HIGH | ⬜ |
| 4.8 | Port display system (dispnew) | 7 | HIGH | ⬜ |
| 4.9 | Integration tests | 3 | HIGH | ⬜ |
| 4.10 | Performance benchmarks | 2 | MEDIUM | ⬜ |

**Dependencies (add to vcpkg.json):**
```json
{
  "dependencies": ["libuv", "unibilium"]
}
```

### Phase 4 Success Criteria:
- [ ] Windows TUI works in Windows Terminal, cmd.exe, PowerShell
- [ ] Mouse support on all platforms
- [ ] UTF-8/CJK character display correct
- [ ] Performance ≥ termbox2 implementation
- [ ] All terminal tests pass

---

## 📋 Next Action Plan (Immediate)

### For Phase 4 Kickoff:

1. **Review Architecture** (1 hour)
   - Read `doc/cxx-builder/technical/tui-architecture.md`
   - Study Neovim's TUI implementation
   - Review libuv documentation

2. **Set Up Dependencies** (30 min)
   - Add libuv and unibilium to `vcpkg.json`
   - Run `cmake -B build-cpp -S .` to fetch deps
   - Verify compilation

3. **Create Phase 4 Branch** (5 min)
   ```bash
   git checkout -b phase4-terminal-tui
   ```

4. **Start with Grid System** (2-3 days)
   - Lowest risk component
   - Create `src/grid.hpp` and `src/grid.cpp`
   - Double-buffered grid with dirty tracking
   - Unit tests in `test/cxx/test_grid.cpp`

5. **Implement libuv Integration** (3 days)
   - Event loop wrapper `src/event_loop.hpp`
   - Async I/O handlers
   - Platform-specific file descriptor handling

6. **Windows Backend Development** (1 week - CRITICAL PATH)
   - Study Windows Console API 2.0
   - VT100 emulation via ENABLE_VIRTUAL_TERMINAL_PROCESSING
   - Fallback to legacy Console API for Windows 7/8
   - Test on Windows 10, 11, Server 2019+

### Immediate Commands:

```bash
# 1. Create phase 4 branch
git checkout -b phase4-terminal-tui

# 2. Update vcpkg.json (add libuv, unibilium)
# Edit vcpkg.json manually

# 3. Reconfigure CMake
cmake -B build-cpp -S . -DCMAKE_BUILD_TYPE=Debug

# 4. Build current state
cmake --build build-cpp --config Debug

# 5. Run existing tests
cd test && make check-src
cd build-cpp && ctest --output-on-failure
```

---

**Last Updated**: 2026-02-05  
**Current Phase**: Phase 4 - Terminal/TUI (Not Started)  
**Next Milestone**: M2 - TUI Alpha (Week 14)  
**Critical Path**: Windows TUI backend implementation  

**For Questions**: See `doc/cxx-builder/README.md` or consult phase documentation in `doc/cxx-builder/phases/`
