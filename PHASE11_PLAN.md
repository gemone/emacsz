# Phase 11: Emacs Core Integration - Execution Plan

**Created**: 2026-02-12
**Mode**: ULTRAWORK
**Status**: IN PROGRESS

---

## Objective

Complete Phase 11 of GNU Emacs C++20 migration: Integrate C++ infrastructure (Phase 0-10) with original Emacs C core.

**Success Criteria**:
1. Lisp evaluator works in C++ (eval.c migrated)
2. Lisp data types work in C++ (data.c migrated)
3. Buffer system integrated (buffer.c + C++ buffer)
4. All existing ERT tests pass
5. Performance within 10% of C implementation

---

## Wave 1: Core Lisp Infrastructure

### Wave 1.1: Analyze data.c (IN PROGRESS)
**Status**: Background agent running

**Agent**: explore (bg_bc29d6a5)

**Expected Output**:
- File size and structure
- Key data types (Lisp_Object, Lisp_Type)
- Function categories
- Dependencies
- Migration complexity (1-10)

### Wave 1.2: Analyze eval.c
**Status**: Background agent running

**Agent**: explore (bg_407b9255)

**Expected Output**:
- Evaluator structure
- Key functions (Feval, Ffuncall)
- Dependencies
- Migration complexity (1-10)

### Wave 1.3: Analyze buffer.c Integration
**Status**: PENDING

**Task**:
- Analyze original buffer.c
- Compare with C++ emacs_buffer.hpp/cpp
- Define integration points
- Design extern "C" bridge

### Wave 1.4: Design C/C++ Integration Strategy
**Status**: PENDING

**Deliverables**:
- extern "C" bridge design document
- Memory management strategy (GC integration)
- Error handling strategy
- Build system modifications (CMake)

### Wave 1.5: Migrate data.c Core Types
**Status**: PENDING

**Steps**:
1. Create src/lisp_data.hpp
2. Define Lisp_Object in C++
3. Define all Lisp_Type enums
4. Implement type checking functions
5. Create extern "C" bridge
6. Unit tests

### Wave 1.6: Migrate eval.c Evaluator
**Status**: PENDING

**Steps**:
1. Create src/lisp_eval.hpp
2. Port Feval (main evaluator)
3. Port Ffuncall (function calling)
4. Port Fapply, Ffuncall
5. Create extern "C" bridge
6. Unit tests
7. Integration tests

### Wave 1.7: Integrate buffer.c with C++ Buffer
**Status**: PENDING

**Steps**:
1. Analyze buffer.c API
2. Map to emacs_buffer.hpp API
3. Create unified buffer interface
4. Implement extern "C" bridge
5. Integration tests

### Wave 1.8: Create Comprehensive Tests
**Status**: PENDING

**Test Categories**:
1. Unit tests (each function)
2. Integration tests (module interactions)
3. Regression tests (ERT suite compatibility)
4. Performance tests (benchmark vs C)

### Wave 1.9: Performance Benchmark
**Status**: PENDING

**Benchmarks**:
1. Lisp evaluation speed
2. Buffer operations speed
3. Memory usage
4. Startup time

### Wave 1.10: Document Wave 1 Completion
**Status**: PENDING

**Deliverables**:
- Phase 11.1 completion report
- Updated AGENTS.md
- API documentation
- Migration notes for next waves

---

## Wave 2: Display Core

**Modules**: xdisp.c, dispnew.c, term.c, window.c, frame.c

**Dependencies**: Wave 1 complete

**Estimated Effort**: 2-3 weeks

---

## Wave 3: Editing Commands

**Modules**: cmds.c, editfns.c, search.c, syntax.c

**Dependencies**: Waves 1-2 complete

**Estimated Effort**: 1-2 weeks

---

## Wave 4: File I/O

**Modules**: fileio.c, filelock.c, sysdep.c, process.c

**Dependencies**: Waves 1-3 complete

**Estimated Effort**: 1-2 weeks

---

## Wave 5: Input Handling

**Modules**: keyboard.c, keymap.c, callint.c

**Dependencies**: Waves 1-4 complete

**Estimated Effort**: 1 week

---

## Wave 6: Fonts & Images

**Modules**: font.c, fontset.c, image.c

**Dependencies**: Waves 1-5 complete

**Estimated Effort**: 1-2 weeks

---

## Wave 7: GUI Backends (Parallel)

**Parallel Tracks**:
- Track A: X11 (xterm.c, xfns.c, xmenu.c)
- Track B: Windows (w32term.c, w32fns.c)
- Track C: macOS (nsterm.m)
- Track D: Other platforms

**Dependencies**: Waves 1-6 complete

**Estimated Effort**: 2-4 weeks per track

---

## Wave 8: Polish & Release

**Tasks**:
- Performance optimization
- Documentation
- Test coverage verification
- Community preparation

**Dependencies**: Waves 1-7 complete

**Estimated Effort**: 2-4 weeks

---

## Progress Tracking

| Wave | Status | Progress | Tests |
|------|--------|----------|-------|
| Wave 1 | IN PROGRESS | 10% | 0 |
| Wave 2 | PENDING | 0% | 0 |
| Wave 3 | PENDING | 0% | 0 |
| Wave 4 | PENDING | 0% | 0 |
| Wave 5 | PENDING | 0% | 0 |
| Wave 6 | PENDING | 0% | 0 |
| Wave 7 | PENDING | 0% | 0 |
| Wave 8 | PENDING | 0% | 0 |

**Total Progress**: Phase 11 is 1.25% of complete migration (Wave 1 of 8 waves)

---

## Background Agents

| Agent | Task ID | Status |
|-------|---------|--------|
| explore | bg_bc29d6a5 | Running - Analyze data.c |
| explore | bg_407b9255 | Running - Analyze eval.c |
| explore | bg_35a1b170 | Running - Find all C files |

---

## Next Immediate Action

1. Wait for background agents to complete
2. Review analysis results
3. Design C/C++ integration strategy
4. Begin Wave 1.5: Migrate data.c core types

---

**Last Updated**: 2026-02-12 21:35:00
