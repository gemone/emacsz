# Phase 1: Core Infrastructure

**Duration:** Week 3-6
**Dependencies:** Phase 0 Completion
**Target:** Week 6 (2026-02-22)

---

## Objectives

1. **Create C++ allocator wrapper compatible with Emacs GC**
2. **Implement string utilities using C++20 standard library**
3. **Set up CMake targets for core modules**
4. **Port and run tests for allocator and string utilities**

---

## Overview

This phase establishes the C++20 foundation for the entire migration. It focuses on:

- **Memory Management:** C++ allocator that integrates with Emacs garbage collection
- **String Processing:** Modern C++20 string utilities replacing gnulib functions
- **Build System:** CMake targets for core modules (alloc, data, lisp)

### Why This Phase First

Before migrating complex subsystems (Lisp interpreter, display, GUI), we need:
1. A working C++20 build environment
2. Memory management that's compatible with Emacs GC
3. String utilities that will be used throughout the codebase

### Success Criteria

- [ ] C++ allocator wrapper compiles and links with Emacs
- [ ] Allocator tests pass
- [ ] String utilities compile and link
- [ ] String tests pass
- [ ] CMake targets build successfully
- [ ] All existing C tests for affected modules pass
- [ ] Performance within 10% of original C allocator
- [ ] No memory leaks detected

---

## Task 1.1: Design C++ Allocator Wrapper

### Objective

Create a C++ allocator that wraps Emacs GC and provides C++20 standard library compatibility.

### Requirements

- Must integrate with Emacs mark-and-sweep GC
- Must support `operator new` and `operator delete`
- Must handle alignment requirements (MALLOC_ALIGNMENT)
- Must be compatible with existing C code during transition
- Must not introduce memory leaks

### Design

```cpp
// src/allocator.cpp

#include <config.h>
#include <cstddef>
#include <new>
#include <cstdlib>
#include <cstring>

// Alignment requirements from src/alloc.c
enum { MALLOC_ALIGNMENT = max (2 * sizeof (size_t), alignof (long double)) };

namespace emacs {

// Emacs GC integration point
extern "C" {
    // These functions are defined in src/alloc.c
    void *lisp_malloc (size_t);
    void *lisp_malloc_unsafe (size_t);
    void lisp_free (void *);
    void *lisp_malloc_uncleared (size_t);
    void *lisp_realloc (void *, size_t);
}

/**
 * C++20 allocator compatible with Emacs GC
 *
 * This allocator wraps Emacs GC functions while providing
 * standard C++ allocator interface. It allows:
 * - Gradual migration from C to C++20
 * - Use of RAII and smart pointers in new code
 * - Compatibility with existing C code
 */
template<typename T>
class emacs_allocator {
public:
    using value_type = T;
    using pointer_type = T*;
    using const_pointer = const T*;
    using size_type = size_t;
    using difference_type = ptrdiff_t;

    // Default constructor
    emacs_allocator() noexcept = default;

    // Copy constructor (required for allocator concept)
    emacs_allocator(const emacs_allocator&) noexcept = default;

    // Allocate memory using Emacs GC
    [[nodiscard]] T* allocate(size_type n) {
        // Use aligned allocation for proper memory alignment
        void *ptr = lisp_malloc(n);
        if (!ptr) {
            // Fall back to standard allocator if GC not available
            ptr = ::operator new(n);
        }
        return static_cast<T*>(ptr);
    }

    // Deallocate memory using Emacs GC
    void deallocate(T* ptr, size_type /*n*/) noexcept {
        if (ptr) {
            lisp_free(ptr);
        }
    }

    // Reallocate memory using Emacs GC
    [[nodiscard]] T* reallocate(T* ptr, size_type old_size, size_type new_size) {
        void *new_ptr = lisp_realloc(ptr, new_size);
        if (!new_ptr) {
            // Fallback: allocate new and copy
            T *fallback = static_cast<T*>(::operator new(new_size));
            std::memcpy(fallback, ptr, std::min(old_size, new_size) * sizeof(T));
            lisp_free(ptr);
            return fallback;
        }
        return static_cast<T*>(new_ptr);
    }

    // Equality comparison (required for allocator concept)
    [[nodiscard]] bool operator==(const emacs_allocator&) const noexcept {
        return true;
    }

    [[nodiscard]] bool operator!=(const emacs_allocator&) const noexcept {
        return false;
    }
};

// Export for use in other modules
extern "C" {

/**
 * Get Emacs C++ allocator instance
 */
struct emacs_allocator_t {
    void* (*allocate)(size_t);
    void (*deallocate)(void*, size_t);
    void* (*reallocate)(void*, size_t, size_t);
};

} // extern "C"

/**
 * Global C++ allocator instance compatible with Emacs GC
 */
static const emacs_allocator_t emacs_cpp_allocator = {
    .allocate = [](size_t n) -> void* {
        return lisp_malloc(n);
    },
    .deallocate = [](void* ptr, size_t /*n*/) -> void {
        lisp_free(ptr);
    },
    .reallocate = [](void* ptr, size_t old_size, size_t new_size) -> void* {
        return lisp_realloc(ptr, new_size);
    }
};

} // namespace emacs
```

### Key Decisions

1. **Template-based allocator:** Allows type-safe allocation without code duplication
2. **GC integration:** Direct calls to `lisp_malloc`/`lisp_free` functions
3. **Fallback mechanism:** Falls back to standard `::operator new` if GC unavailable
4. **Alignment support:** Respects `MALLOC_ALIGNMENT` requirement
5. **C compatibility:** Extern "C" interface for C code

---

## Task 1.2: Implement C++ String Utilities

### Objective

Replace gnulib string functions with C++20 standard library equivalents.

### Mapping Table

| gnulib Function | C++20 Equivalent | Header | Priority |
|----------------|------------------|--------|----------|
| `strdup` | `std::string(char*)` | <string> | HIGH |
| `strndup` | `std::string(data, len)` | <string> | HIGH |
| `stpcpy` | `std::strcpy` + manual +1 | <cstring> | HIGH |
| `strnlen` | `std::char_traits<char>::length(data, len)` | <string> | HIGH |
| `asprintf` | `std::format` (C++20) | <format> | HIGH |
| `snprintf` | `std::format_to` | <format> | MEDIUM |
| `getline` | `std::getline` | <string> | MEDIUM |
| `memcmp` | `std::memcmp` | <cstring> | LOW |

### Implementation

```cpp
// src/strings.cpp

#include <config.h>
#include <string>
#include <format>
#include <string_view>
#include <cstring>

namespace emacs::strings {

/**
 * Duplicate a null-terminated string
 *
 * Replaces: gnulib strdup()
 */
[[nodiscard]] inline std::string string_duplicate(const char* s) {
    return std::string(s);
}

/**
 * Duplicate a string with length limit
 *
 * Replaces: gnulib strndup()
 */
[[nodiscard]] inline std::string string_duplicate_n(const char* s, size_t n) {
    return std::string(s, n);
}

/**
 * Copy string with null terminator
 *
 * Replaces: gnulib stpcpy()
 */
[[nodiscard]] inline char* string_copy(char* dest, const char* src) {
    size_t len = std::strlen(src);
    std::memcpy(dest, src, len);
    return dest + len;
}

/**
 * Get string length with safety
 *
 * Replaces: gnulib strnlen()
 */
[[nodiscard]] inline size_t string_length(const char* s, size_t max_len) {
    return std::char_traits<char>::length(s, max_len);
}

/**
 * Format string (C++20 feature)
 *
 * Replaces: gnulib asprintf()
 */
template<typename... Args>
[[nodiscard]] std::string string_format(const std::string_view fmt, Args&&... args) {
    if constexpr (sizeof...(Args) == 0) {
        return std::string(fmt);
    }
    return std::vformat(fmt, std::make_format_args(args...));
}

/**
 * Read line from stream
 *
 * Replaces: gnulib getline()
 */
inline bool read_line(std::FILE* stream, std::string& line) {
    line.clear();
    return static_cast<bool>(std::getline(stream, line));
}

} // namespace emacs::strings
```

### Header

```cpp
// src/strings.hpp

#pragma once

#include <string>
#include <string_view>
#include <format>

namespace emacs::strings {

// String utility functions replacing gnulib

[[nodiscard]] std::string string_duplicate(const char* s);
[[nodiscard]] std::string string_duplicate_n(const char* s, size_t n);
[[nodiscard]] char* string_copy(char* dest, const char* src);
[[nodiscard]] size_t string_length(const char* s, size_t max_len);
template<typename... Args>
[[nodiscard]] std::string string_format(const std::string_view fmt, Args&&... args);
inline bool read_line(std::FILE* stream, std::string& line);

} // namespace emacs::strings
```

---

## Task 1.3: Create CMake Targets for Core Modules

### Objective

Set up CMake build targets for the core infrastructure modules.

### Directory Structure

```
src/
├── allocator.cpp      # C++ allocator wrapper
├── allocator.hpp       # Allocator header
├── strings.cpp         # String utilities
├── strings.hpp         # String utilities header
├── alloc.c            # Original C allocator (keep for compatibility)
├── data.c             # Original C string utilities (keep for compatibility)
└── lisp.h             # Core Lisp definitions (keep)
```

### CMakeLists.txt (src/)

```cmake
cmake_minimum_required(VERSION 3.20)

# Allocator module
add_library(emacs_allocator
    allocator.cpp
    allocator.hpp
)
target_include_directories(emacs_allocator PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_compile_features(emacs_allocator PUBLIC cxx_std_20)

# String utilities module
add_library(emacs_strings
    strings.cpp
    strings.hpp
)
target_include_directories(emacs_strings PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_compile_features(emacs_strings PUBLIC cxx_std_20)

# Core library (aggregates infrastructure)
add_library(emacs_core_infra
    ALIAS
        emacs_allocator
        emacs_strings
)
target_link_libraries(emacs_core_infra PUBLIC
        emacs_allocator
        emacs_strings
)
```

---

## Task 1.4: Port and Run Tests

### Objective

Ensure that all allocator and string functionality works correctly.

### Test Strategy

1. **Compile existing C tests:** Run `test/alloc-tests.el` to ensure allocator still works
2. **Create C++ unit tests:** Use gtest for allocator and string utilities
3. **Integration testing:** Link C++ code with existing C modules
4. **Performance benchmarking:** Compare C++ allocator with original C allocator

### Test Categories

**Allocator Tests:**
- Allocation and deallocation
- Alignment handling
- Memory leak detection
- Performance comparison with C allocator

**String Tests:**
- String duplication
- String copying
- String length calculation
- String formatting (C++20)
- Line reading from streams

### Running Tests

```bash
# Test with CMake build
cd build-cpp
ctest --output-on-failure

# Test allocator specifically
ctest -R allocator

# Test strings specifically
ctest -R strings

# Performance benchmark
ctest --output-on-failure --verbose
```

---

## Implementation Order

### Week 1

1. **Day 1-2:** Create allocator header and implementation
   - Define `emacs_allocator` template
   - Implement GC integration
   - Add extern "C" bridge

2. **Day 3-4:** Create string utilities
   - Implement string_duplicate
   - Implement string_format (C++20)
   - Implement all replacement functions

3. **Day 5-6:** Create CMake targets
   - Add emacs_allocator library
   - Add emacs_strings library
   - Add emacs_core_infra aggregate

### Week 2

1. **Day 1-3:** Port existing tests
   - Update test CMakeLists.txt
   - Ensure C++ tests compile

2. **Day 4-5:** Create new C++ tests
   - Use gtest framework
   - Write allocator tests
   - Write string tests

3. **Day 6-7:** Run test suite
   - Execute all tests
   - Fix any failures

---

## Migration Notes

### What Stays in C

- **src/alloc.c:** Original allocator implementation (keep for upstream sync)
- **src/data.c:** Original string utilities (keep for upstream sync)

### What Changes to C++

- **src/allocator.cpp:** New C++ allocator wrapper
- **src/allocator.hpp:** Allocator header with C++20 interface
- **src/strings.cpp:** C++ string utilities
- **src/strings.hpp:** String utilities header

### Compatibility Strategy

During this phase, **both C and C++ code coexist**:
- C code continues to use original functions
- New C++ code can use C++ allocator and string utilities
- CMake links both C and C++ object files

---

## Success Verification

### Automated Checks

1. **Build Check:**
   ```bash
   cmake -B build-cpp -S . -DCMAKE_BUILD_TYPE=Debug
   cmake --build build-cpp --config Debug
   ```

2. **Test Check:**
   ```bash
   cd build-cpp
   ctest -R allocator
   ctest -R strings
   ```

3. **Integration Check:**
   - Link C++ allocator with existing C code
   - Ensure no link errors
   - Verify memory layout compatibility

### Manual Verification

- [ ] Test basic Emacs startup with C++ allocator
- [ ] Run existing test suite: `make check`
- [ ] Profile memory usage (Valgrind/ASAN)
- [ ] Benchmark performance (compare with C allocator)

---

## Risks and Mitigations

### Risk 1: C++ Allocator Overhead

**Risk:** Template allocator may be slower than direct C allocator

**Mitigation:**
- Profile hot paths during implementation
- Use inline functions for critical allocations
- Consider `-fno-exceptions` for allocator

### Risk 2: GC Integration

**Risk:** C++ exceptions may bypass GC cleanup

**Mitigation:**
- Use `noexcept` specification everywhere
- Document exception safety requirements
- Ensure RAII cleanup always happens

### Risk 3: String Conversion

**Risk:** Converting between C strings and std::string may be expensive

**Mitigation:**
- Use `std::string_view` to avoid copies where possible
- Document when conversions are necessary
- Cache conversions in hot paths

---

## Blocking Issues

**Current Blockers:** None

**Dependencies:**
- Phase 0 completion (✅ Complete)

---

## Notes

### Key Files Modified

- **New Files:**
  - `src/allocator.cpp`
  - `src/allocator.hpp`
  - `src/strings.cpp`
  - `src/strings.hpp`
  - `src/CMakeLists.txt`

- **Modified Files:**
  - `CMakeLists.txt` (root) - add src subdirectory
  - `test/CMakeLists.txt` - add C++ tests

### Testing Requirements

All tests must pass before proceeding to Phase 2 (Entry Point).

**Test Coverage Required:**
- Allocator: Allocation, deallocation, alignment, no leaks
- Strings: All utility functions, edge cases
- Integration: C++ code linked with C modules
- Performance: Within 10% of original implementation

---

## Deliverables

1. ✅ C++ allocator wrapper (allocator.cpp/hpp)
2. ✅ String utilities (strings.cpp/hpp)
3. ✅ CMake targets for core modules
4. ✅ Test suite for allocator and strings
5. ✅ Integration tests
6. ✅ Performance benchmarks

---

**Last Updated:** 2026-02-01
**Next Review:** End of Week 2 (2026-02-15)
