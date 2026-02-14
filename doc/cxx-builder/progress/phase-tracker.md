# Phase Tracker v2.0

**Last Updated:** 2026-02-05
**Current Phase:** Phase 3 - Shared Infrastructure
**Strategy Version:** v2.0

---

## Phase Overview (Revised)

| Phase | Name | Status | Progress | Target |
|-------|------|--------|----------|--------|
| Phase 0 | Foundation Setup | ✅ Complete | 100% | Week 2 |
| Phase 1 | Core Infrastructure | ✅ Complete | 100% | Week 6 |
| Phase 2 | Entry Point & Startup | ✅ Complete | 100% | Week 8 |
| **Phase 3** | **Shared Infrastructure** | ✅ Complete | 100% | Week 10 |
| Phase 4 | Terminal/TUI | ⬜ Not Started | 0% | Week 16 |
| Phase 5 | Lisp Interpreter Core | ⬜ Not Started | 0% | Week 28 |
| Phase 6 | Platform-Specific GUI | ⬜ Not Started | 0% | Week 32 |
| Phase 7 | File I/O & System | ⬜ Not Started | 0% | Week 34 |
| Phase 8 | Testing & Validation | ⬜ Not Started | 0% | Week 36 |
| Phase 9 | Build System Cleanup | ⬜ Not Started | 0% | Week 38 |

---

## Phase 3: Shared Infrastructure (NEW)

**Status:** 🟡 In Progress  
**Target:** Week 10  
**Start Date:** 2025-02-03

### Objectives

Build foundational C++ infrastructure used by all subsequent phases.

### Tasks

| ID | Task | Status | Priority | Notes |
|----|------|--------|----------|-------|
| 3.1 | Error handling (`emacs/error.hpp`) | ⬜ | High | Result<T>, error codes |
| 3.2 | Logging system (`emacs/log.hpp`) | ⬜ | High | Structured logging |
| 3.3 | Platform abstraction (`emacs/platform.hpp`) | ⬜ | High | OS detection, features |
| 3.4 | GC-aware containers (`emacs/containers.hpp`) | ⬜ | High | gc_vector, gc_string |
| 3.5 | Unicode utilities (`emacs/unicode.hpp`) | ⬜ | High | wcwidth, UTF-8 |
| 3.6 | Path utilities (`emacs/path.hpp`) | ⬜ | Medium | Cross-platform paths |
| 3.7 | Unit tests for all modules | ⬜ | High | test/test_*.cpp |

### Success Criteria

- [ ] All infrastructure modules compile on Linux, macOS, Windows
- [ ] Unit tests pass for all modules
- [ ] No gnulib dependencies in new code
- [ ] Documentation complete

---

## Phase 4: Terminal/TUI (Revised)

**Status:** ⬜ Not Started  
**Target:** Week 16  
**Depends On:** Phase 3

### Objectives

Replace termbox2 with robust cross-platform terminal implementation inspired by Neovim.

### Architecture

```
Event Loop (libuv)
    ↓
Input Parser (libtermkey-style)
    ↓
Grid Renderer (double-buffered)
    ↓
Terminal Backend (Unix/Windows/macOS)
    ↓
Capabilities Provider (terminfo + built-in)
```

### Tasks

| ID | Task | Status | Priority | Est. Days |
|----|------|--------|----------|-----------|
| 4.1 | Design TUI architecture document | ⬜ | High | 2 |
| 4.2 | Integrate libuv event loop | ⬜ | High | 3 |
| 4.3 | Implement input parser | ⬜ | High | 5 |
| 4.4 | Implement capabilities provider | ⬜ | High | 3 |
| 4.5 | Implement Unix backend | ⬜ | High | 4 |
| 4.6 | **Implement Windows backend (VT)** | ⬜ | **Critical** | 6 |
| 4.7 | Implement Grid + renderer | ⬜ | High | 5 |
| 4.8 | Port display system (dispnew) | ⬜ | High | 7 |
| 4.9 | Integration tests | ⬜ | High | 3 |
| 4.10 | Performance benchmarks | ⬜ | Medium | 2 |

### Dependencies (vcpkg)

```json
{
  "dependencies": ["libuv", "unibilium"]
}
```

### Success Criteria

- [ ] Windows TUI works in Windows Terminal, cmd.exe, PowerShell
- [ ] Mouse support on all platforms
- [ ] UTF-8/CJK character display correct
- [ ] Performance ≥ termbox2 implementation
- [ ] All terminal tests pass

---

## Phase 5: Lisp Interpreter Core

**Status:** ⬜ Not Started  
**Target:** Week 28  
**Depends On:** Phase 4

### Objectives

Migrate Lisp data types and interpreter to C++20.

### Key Design Decisions

1. **Lisp_Object:** Use `std::variant` for type-safe union
2. **GC Integration:** RAII + custom allocators
3. **Evaluation:** Consider C++20 coroutines for call stack

### Tasks

| ID | Task | Status | Priority |
|----|------|--------|----------|
| 5.1 | Design Lisp_Object C++ class | ⬜ | High |
| 5.2 | Port lisp.h to lisp.hpp | ⬜ | High |
| 5.3 | Port data.c to data.cpp | ⬜ | High |
| 5.4 | Port eval.c to eval.cpp | ⬜ | High |
| 5.5 | Port bytecode.c to bytecode.cpp | ⬜ | High |
| 5.6 | Port alloc.c GC to C++ | ⬜ | High |
| 5.7 | Integrate with C++ containers | ⬜ | Medium |
| 5.8 | Port fns.c to fns.cpp | ⬜ | Medium |
| 5.9 | Lisp test suite green | ⬜ | Critical |

### Success Criteria

- [ ] Lisp objects use C++ RAII
- [ ] All Lisp tests pass
- [ ] Performance within 10% of C
- [ ] No memory leaks (ASAN clean)

---

## Phase 6-9: Future Phases

### Phase 6: Platform-Specific GUI (Week 29-32)

- Modernize macOS (NextStep) GUI
- Refactor Windows GUI
- Create SDL3 interface stubs

### Phase 7: File I/O & System (Week 33-34)

- Replace gnulib file functions with std::filesystem
- Modernize system calls

### Phase 8: Testing & Validation (Week 35-36)

- Full test suite migration
- Performance benchmarks
- Memory testing (Valgrind/ASAN)

### Phase 9: Build System Cleanup (Week 37-38)

- Remove autotools dependency
- Final documentation
- Release preparation

---

## Milestones

| Milestone | Target | Exit Criteria |
|-----------|--------|---------------|
| M1: Infrastructure | Week 10 | Phase 3 tests pass |
| M2: TUI Alpha | Week 14 | Basic rendering all platforms |
| M3: TUI Beta | Week 16 | Mouse + UTF-8 + Windows usable |
| M4: Lisp Alpha | Week 22 | Basic eval, 50% tests |
| M5: Lisp Beta | Week 28 | All Lisp tests pass |
| M6: Autotools Frozen | Week 32 | CMake-only for new dev |
| M7: Release Candidate | Week 38 | Full test suite |

---

## Overall Progress

### Total Migration Progress: 31.4%

```
Phase 0:  ████████████████████████████████  100%  ✅
Phase 1:  ████████████████████████████████  100%  ✅
Phase 2:  ████████████████████████████████  100%  ✅
Phase 3:  ████████████████████████████████  100%  ✅
Phase 4:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
Phase 5:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
Phase 6:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
Phase 7:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
Phase 8:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
Phase 9:  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    0%
```

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Windows TUI regression | High | High | Keep fallback; A/B testing |
| Dual-build divergence | Medium | High | CI parity checks |
| gnulib semantic mismatch | Medium | Medium | Focused regression tests |
| Performance regression | Low | High | CI benchmarks |
| Upstream sync conflicts | Medium | Low | Minimize C file changes |

---

## Notes

### Upstream Sync Strategy

- **Current approach:** Keep C files intact, add C++ alongside
- **Merge frequency:** Monthly upstream sync recommended
- **Conflict resolution:** Prefer upstream changes in C files

### Build System Timeline

```
Now → Phase 4:     Dual-build (autotools + CMake both active)
Phase 5:           CMake becomes CI-authoritative  
Phase 6:           Autotools frozen (no new features)
Phase 8-9:         Autotools removed after 2 release cycles
```

---

**Last Updated:** 2026-02-05
**Next Review:** End of Phase 3
