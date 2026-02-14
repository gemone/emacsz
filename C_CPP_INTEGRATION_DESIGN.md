# C/C++ Integration Design - Phase 11

**Created**: 2026-02-12
**Purpose**: Define integration strategy between C++ infrastructure (Phase 0-10) and original Emacs C code

---

## Overview

GNU Emacs has ~515K lines of C code that needs to integrate with ~13K lines of new C++20 code. This document defines how to achieve seamless integration.

---

## Integration Principles

### 1. Incremental Migration
- **Strategy**: Migrate one module at a time
- **Benefit**: Maintain working system throughout
- **Requirement**: Each step must be testable

### 2. Dual-Build Capability
- **Strategy**: Keep both C and C++ versions active during transition
- **Benefit**: Rollback possible at any point
- **Requirement**: Feature flags to switch implementations

### 3. Memory Management Compatibility
- **Strategy**: C++ allocator uses lisp_malloc/lisp_free
- **Benefit**: GC integration from day one
- **Requirement**: All C++ allocations go through emacs_allocator

### 4. Error Handling Bridge
- **Strategy**: extern "C" never propagates C++ exceptions
- **Benefit**: C code remains exception-safe
- **Requirement**: All bridges catch and convert exceptions

---

## extern "C" Bridge Pattern

### Header Pattern

```cpp
// src/lisp_data.hpp
#pragma once

#include "lisp.h"  // Original C header

namespace emacs {
namespace lisp {

// C++ wrapper for Lisp_Object
class Object {
public:
    Object() : obj_{} {}
    explicit Object(Lisp_Object obj) : obj_(obj) {}
    
    // Type-safe accessors
    bool is_nil() const noexcept;
    bool is_cons() const noexcept;
    bool is_string() const noexcept;
    // ... etc
    
    Lisp_Object raw() const noexcept { return obj_; }
    
private:
    Lisp_Object obj_;
};

} // namespace lisp
} // namespace emacs

// extern "C" bridge functions
extern "C" {
    // C-callable wrappers for C++ functionality
    int emacs_lisp_object_is_nil(Lisp_Object obj) noexcept;
    int emacs_lisp_object_is_cons(Lisp_Object obj) noexcept;
    // ... etc
}
```

### Implementation Pattern

```cpp
// src/lisp_data.cpp
#include "lisp_data.hpp"

namespace emacs {
namespace lisp {

bool Object::is_nil() const noexcept {
    return NILP(obj_);
}

bool Object::is_cons() const noexcept {
    return CONSP(obj_);
}

// ... more implementations

} // namespace lisp
} // namespace emacs

// extern "C" bridge implementations
extern "C" {

int emacs_lisp_object_is_nil(Lisp_Object obj) noexcept {
    try {
        return emacs::lisp::Object(obj).is_nil() ? 1 : 0;
    } catch (...) {
        // Never let exceptions cross to C
        return -1;  // Error indicator
    }
}

int emacs_lisp_object_is_cons(Lisp_Object obj) noexcept {
    try {
        return emacs::lisp::Object(obj).is_cons() ? 1 : 0;
    } catch (...) {
        return -1;
    }
}

} // extern "C"
```

---

## Memory Management

### Allocation Strategy

```cpp
// All C++ allocations use emacs_allocator
#include "allocator.hpp"

namespace emacs {
namespace lisp {

class ConsCell {
public:
    ConsCell(Lisp_Object car, Lisp_Object cdr);
    
    void* operator new(size_t size) {
        return lisp_malloc(size);  // GC-managed
    }
    
    void operator delete(void* ptr) noexcept {
        lisp_free(ptr);  // GC-managed
    }
    
private:
    Lisp_Object car_;
    Lisp_Object cdr_;
};

} // namespace lisp
} // namespace emacs
```

### GC Integration

```cpp
// C++ objects are GC-managed via lisp_malloc
// GC roots registered via:
extern "C" void register_gc_root(Lisp_Object* root);

namespace emacs {
namespace lisp {

class Root {
public:
    Root(Lisp_Object obj) : obj_(obj) {
        register_gc_root(&obj_);
    }
    
    ~Root() {
        unregister_gc_root(&obj_);
    }
    
private:
    Lisp_Object obj_;
};

} // namespace lisp
} // namespace emacs
```

---

## Build System Integration

### CMake Configuration

```cmake
# src/CMakeLists.txt additions for Phase 11

# Lisp core library
add_library(emacs_lisp_core STATIC
    lisp_data.cpp
    lisp_eval.cpp
    lisp_buffer_bridge.cpp
)

target_include_directories(emacs_lisp_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..  # For original C headers
)

target_link_libraries(emacs_lisp_core PUBLIC
    emacs_allocator
    emacs_buffer
)

# Feature flags for C/C++ switching
option(EMACS_USE_CPP_LISP "Use C++ Lisp implementation" OFF)
option(EMACS_USE_CPP_BUFFER "Use C++ buffer implementation" ON)
```

### Feature Flags

```cpp
// src/feature_flags.hpp
#pragma once

// Compile-time feature flags
#define EMACS_USE_CPP_LISP 0  // 0 = C, 1 = C++
#define EMACS_USE_CPP_BUFFER 1  // Already using C++ buffer

// Runtime feature flags
namespace emacs {
    bool use_cpp_lisp() noexcept;
    void set_use_cpp_lisp(bool value) noexcept;
}
```

---

## Migration Workflow

### Step 1: Analyze C Module
```bash
# Analyze dependencies
grep -h '#include' src/module.c | sort -u

# Analyze exports
grep -h '^[A-Za-z_][A-Za-z0-9_]* (' src/module.c

# Analyze size
wc -l src/module.c
```

### Step 2: Create C++ Header
```bash
# Create C++ wrapper header
touch src/module.hpp

# Define namespace and class
# Define extern "C" bridges
```

### Step 3: Implement C++ Wrapper
```bash
# Create implementation
touch src/module.cpp

# Implement C++ methods
# Implement extern "C" bridges
```

### Step 4: Update Build
```cmake
# Add to CMakeLists.txt
add_library(emacs_module STATIC module.cpp)
```

### Step 5: Test
```bash
# Build
cmake --build build-cpp

# Run tests
./build-cpp/bin/test_module
```

### Step 6: Integrate
```cmake
# Link with existing code
target_link_libraries(emacs_minimal emacs_module)
```

---

## Testing Strategy

### Unit Tests
```cpp
// test/cxx/test_lisp_data.cpp
#include "lisp_data.hpp"
#include <cassert>

int main() {
    // Test Object creation
    emacs::lisp::Object obj;
    assert(obj.is_nil());
    
    // Test type predicates
    // ...
    
    return 0;
}
```

### Integration Tests
```cpp
// test/cxx/test_lisp_integration.cpp
#include "lisp_data.hpp"
#include "lisp_eval.hpp"

int main() {
    // Test C++ evaluator with C data
    // ...
    
    return 0;
}
```

### ERT Compatibility
```lisp
;; test/ert/test-cpp-compat.el
(ert-deftest test-cpp-lisp-eval ()
  "Test C++ Lisp evaluator compatibility."
  (should (equal (eval '(+ 1 2)) 3)))
```

---

## Performance Considerations

### Benchmarking Points
1. Lisp evaluation speed
2. Memory allocation overhead
3. GC pause times
4. Startup time

### Optimization Strategies
1. Inline critical paths
2. Avoid virtual functions in hot paths
3. Use constexpr where possible
4. Profile before optimizing

---

## Rollback Plan

### Per-Module Rollback
```cmake
# If module fails, switch flag
if(NOT EMACS_MODULE_WORKING)
    set(EMACS_USE_CPP_MODULE OFF)
endif()
```

### Full Rollback
```bash
# Revert to all-C implementation
cmake -DEMACS_USE_CPP_LISP=OFF ..
cmake --build .
```

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Test Coverage | > 90% | ctest output |
| Performance | Within 10% of C | Benchmark comparison |
| Memory Usage | < 105% of C | Memory profiling |
| Compatibility | All ERT tests pass | make check |
| Build Time | < 30s | time cmake --build |

---

## Next Actions

1. **Complete background agent analysis** of data.c, eval.c, buffer.c
2. **Begin data.cpp implementation** based on analysis
3. **Create test suite** for lisp_data module
4. **Integrate with build system**
5. **Verify with existing ERT tests**

---

**Last Updated**: 2026-02-12 21:40:00
