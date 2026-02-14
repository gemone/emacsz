# Phase 4: Lisp Interpreter Core

**Duration:** Week 11-28  
**Dependencies:** Phase 3 completion  
**Target:** Week 28 (2026-04-19)

---

## Objectives

1. **Modernize Lisp object system** with C++20 type safety
2. **Port core interpreter** to C++ with RAII patterns
3. **Integrate with GC** through custom allocators
4. **Maintain C compatibility** for upstream sync

---

## Overview

Phase 4 migrates the Emacs Lisp interpreter core from C to C++20. This is the most complex phase because:

- **Lisp is the heart of Emacs** - Every subsystem depends on it
- **Complex data structures** - Cons cells, vectors, hash tables, symbols
- **Bytecode interpreter** - Performance-critical evaluation engine
- **GC integration** - All Lisp objects must work with Emacs garbage collector
- **C/C++ interoperability** - Must maintain ABI for upstream sync

### Why This Phase Fourth

Before migrating Lisp, we need:
1. ✅ **Memory management** (Phase 1-2) - allocator with GC integration
2. ✅ **String utilities** (Phase 1-2) - C++20 string handling
3. ✅ **Platform abstraction** (Phase 3) - OS detection and features
4. ✅ **Logging** (Phase 3) - Structured error reporting
5. ✅ **Terminal** (Phase 3/4) - Display infrastructure
6. ✅ **Containers** (Phase 3) - GC-aware STL wrappers

**All prerequisites are now complete.**

---

## Key Design Decisions

### 1. Lisp_Object Representation

**Decision:** Use `std::variant` for type-safe Lisp objects

**Rationale:**
- Type safety at compile-time
- No manual type tagging/untagging
- Easy to add new types
- Zero-cost abstraction (compiler optimizes away)

**Structure:**
```cpp
using Lisp_Object = std::variant<
    Lisp_Integer,
    Lisp_Float,
    Lisp_Cons,
    Lisp_String,
    Lisp_Vector,
    Lisp_Symbol,
    Lisp_Hash_Table,
    Lisp_Function,
    Lisp_Bool,
    Lisp_Void
>;
```

### 2. GC Integration Strategy

**Decision:** Custom allocator with smart pointers, keep existing C GC API

**Rationale:**
- Don't rewrite GC - too risky and complex
- Use RAII wrappers around existing GC
- Incremental migration possible
- Upstream compatibility preserved

**Pattern:**
```cpp
template<typename T>
using Lisp_Ptr = std::unique_ptr<T, Lisp_Deleter<T>>;

class Lisp_Deleter {
public:
    void operator()(T* ptr) const {
        lisp_free(ptr);  // Use existing GC
    }
};
```

### 3. Bytecode Interpreter

**Decision:** Keep C bytecode format, C++ wrapper for evaluation

**Rationale:**
- Bytecode format is stable (must not break)
- Performance through native execution
- C++20 can optimize hot paths
- Separate interpreter state from data

**Structure:**
```cpp
class Bytecode_Interpreter {
    struct State {
        std::vector<Lisp_Object> stack;
        Lisp_Object current_op;
        size_t pc;
    };
    
    Lisp_Object eval(const Lisp_Object& code);
    void step();
};
```

### 4. Symbol Interning

**Decision:** Keep existing intern table, add C++ interface

**Rationale:**
- Symbol equality is pointer equality (interning essential)
- Existing implementation is battle-tested
- Performance-critical for Emacs
- C++ wrapper provides modern API

---

## Task Breakdown

### 4.1 Design Lisp Object Type System (Week 11-12)

**Objectives:**
- Define C++20 variant-based Lisp_Object
- Implement all Lisp types
- Add type-safe accessors
- Design C compatibility layer

**Deliverables:**
- [ ] `src/lisp_object.hpp` - Core type definitions
- [ ] `src/lisp_object.cpp` - Type implementations
- [ ] Type conversion helpers
- [ ] C compatibility macros

**Success Criteria:**
- All Lisp types defined
- Type-safe accessors compile
- C compatibility verified

---

### 4.2 Port Lisp Core Data Types (Week 13-16)

**Objectives:**
- Port cons cells to C++
- Port strings to C++
- Port vectors to C++
- Port hash tables to C++
- Port symbols to C++

**Files:**
- [ ] Port `src/lisp.h` → `src/lisp.hpp`
- [ ] Port `src/data.c` → `src/lisp_data.cpp`
- [ ] Port `src/alloc.c` GC parts → C++ wrappers

**Success Criteria:**
- All core data types ported
- Memory management uses GC allocator
- Tests pass for each type

---

### 4.3 Port Bytecode Interpreter (Week 17-20)

**Objectives:**
- Port `src/bytecode.c` → `src/bytecode.cpp`
- Implement interpreter loop in C++
- Optimize hot paths with constexpr
- Maintain bytecode compatibility

**Deliverables:**
- [ ] `src/bytecode.hpp` - Bytecode definitions
- [ ] `src/bytecode.cpp` - Interpreter implementation
- [ ] Performance benchmarks

**Success Criteria:**
- Bytecode executes correctly
- Performance within 10% of C
- All bytecode tests pass

---

### 4.4 Port Evaluator (Week 21-24)

**Objectives:**
- Port `src/eval.c` → `src/eval.cpp`
- Implement function call handling
- Handle special forms
- Implement macro expansion

**Deliverables:**
- [ ] `src/eval.hpp` - Evaluator interface
- [ ] `src/eval.cpp` - Implementation
- [ ] Special form handlers

**Success Criteria:**
- All eval tests pass
- Special forms work correctly
- Macro expansion functional

---

### 4.5 Integration & Testing (Week 25-28)

**Objectives:**
- Integrate all components
- Write comprehensive tests
- Performance benchmarking
- Documentation

**Deliverables:**
- [ ] Integration tests (`test/lisp/test_*.cpp`)
- [ ] Performance benchmarks
- [ ] Migration guide
- [ ] C compatibility tests

**Success Criteria:**
- All Lisp tests pass (test/lisp)
- Performance comparable to C
- Documentation complete
- C compatibility verified

---

## Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|-------|-------------|--------|------------|
| Performance regression | High | High | Benchmarking, hot-path optimization |
| GC integration bugs | Medium | High | Fallback to C allocator, ASAN testing |
| C compatibility break | Medium | High | ABI verification, upstream sync tests |
| Complex macros | Low | Medium | Keep existing macro system, add C++ layer |
| Memory leaks | Medium | High | Valgrind/ASAN testing, RAII everywhere |

---

## Success Criteria

- [ ] All Lisp types use C++20 variant
- [ ] GC integration working (no double-free)
- [ ] Bytecode interpreter functional
- [ ] Evaluator handles all forms
- [ ] All Lisp tests pass
- [ ] Performance within 10% of C
- [ ] No memory leaks (ASAN clean)
- [ ] C compatibility preserved (upstream syncs)

---

## Dependencies

- **Phase 3 Complete** ✅
- **CMake build system** ✅
- **Emacs GC integration** ✅
- **Platform detection** ✅

---

**Last Updated:** 2026-02-05
**Next Review:** End of Week 16 (2026-02-23)
