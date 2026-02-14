# Emacs C++20 Migration Strategy v2.0

**Version:** 2.0  
**Date:** 2025-02-03  
**Status:** Active  
**Supersedes:** strategy.md v1.0

---

## Executive Summary

This document outlines a revised comprehensive strategy for migrating GNU Emacs from C to C++20. Based on analysis of the current codebase (152 C files, ~515K lines), Neovim's TUI architecture research, and architectural consultation, this strategy prioritizes:

1. **Incremental migration** with test validation at each step
2. **Custom TUI implementation** inspired by Neovim (libuv + terminfo + double-buffered grid)
3. **Dual-build system** through Phase 4, then gradual autotools deprecation
4. **gnulib elimination** via strangler pattern with shim headers
5. **SDL3-ready architecture** without immediate GUI replacement

### Key Changes from v1.0

| Aspect | v1.0 | v2.0 |
|--------|------|------|
| TUI Library | termbox2 | Custom (libuv + terminfo) |
| Dual-build | Indefinite | Time-boxed (remove after Phase 6) |
| gnulib Strategy | Progressive replacement | Strangler pattern with shims |
| Phase Order | Terminal → Lisp | Infrastructure → Terminal → Lisp |
| Windows TUI | termbox2 (broken) | VT sequences + Console API fallback |

---

## Architecture Decisions

### 1. Build System Strategy

**Decision:** Dual-build through Phase 4, then time-boxed deprecation.

**Timeline:**
```
Phase 0-4: Dual-build (autotools + CMake both active)
Phase 5:   CMake becomes CI-authoritative
Phase 6:   Autotools frozen (no new features)
Phase 7-8: Autotools removed after 2 release cycles
```

**Rationale:**
- Allows upstream Emacs sync during core migration
- CMake can be offered as optional upstream contribution
- Avoids blocking on upstream acceptance

**Implementation:**
```bash
# Development workflow
./configure && make        # Legacy C build (upstream sync)
cmake -B build -S . && cmake --build build  # C++20 build

# CI workflow
act -j build-cmake        # Primary
act -j build-autotools    # Parity check
```

### 2. TUI Architecture (Revised)

**Decision:** Replace termbox2 with custom cross-platform terminal abstraction.

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│                    Emacs Display Layer                   │
├─────────────────────────────────────────────────────────┤
│                     Grid Renderer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Double Buffer │  │ Dirty Region │  │  Diff Engine  │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                  Terminal Backend                        │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Unix/POSIX   │  │   Windows    │  │    macOS      │  │
│  │  (terminfo)  │  │ (VT + ConAPI)│  │  (terminfo)   │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Event Loop (libuv)                    │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  TTY Read    │  │  TTY Write   │  │    Signals    │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                   Input Parser                           │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Key Parser  │  │ Mouse Parser │  │ Paste Detect  │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                 Capabilities Provider                    │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  unibilium   │  │ Built-in DB  │  │  Runtime Caps │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Key Components:**

1. **Event Loop (libuv)**
   - Cross-platform async I/O
   - TTY handle management
   - Signal handling (SIGWINCH, SIGTERM)
   - Timer management (escape sequence timeout)

2. **Input Parser**
   - UTF-8 aware key parsing
   - Modifier key handling (Ctrl, Alt, Shift, Super)
   - Mouse event parsing (SGR, X10, normal modes)
   - Bracketed paste detection
   - Escape sequence timeout handling

3. **Capabilities Provider**
   - Primary: unibilium (terminfo database)
   - Fallback: Built-in terminal definitions
   - Runtime capability queries (RGB, cursor shape)
   - Windows: VT sequence support detection

4. **Grid Renderer**
   - Double-buffered cell grid
   - Dirty region tracking
   - Diff-based output minimization
   - Unicode/wide character support

5. **Terminal Backend**
   - Unix: terminfo + POSIX TTY
   - Windows: ENABLE_VIRTUAL_TERMINAL_INPUT + Console API fallback
   - macOS: Same as Unix

**Dependencies (vcpkg):**
```json
{
  "dependencies": [
    "libuv",
    "unibilium"
  ]
}
```

**C++20 Interface:**
```cpp
namespace emacs::tui {

// Concept for terminal backends
template<typename T>
concept TerminalBackend = requires(T t, const Grid& grid) {
    { t.init() } -> std::same_as<Result<void>>;
    { t.shutdown() } -> std::same_as<void>;
    { t.read_input() } -> std::same_as<std::optional<InputEvent>>;
    { t.render(grid) } -> std::same_as<void>;
    { t.resize() } -> std::same_as<TerminalSize>;
    { t.capabilities() } -> std::same_as<const Capabilities&>;
};

// Cell in the grid
struct Cell {
    char32_t codepoint;
    uint8_t width;        // 1 or 2 for wide chars
    Attributes attrs;     // fg, bg, bold, etc.
};

// Double-buffered grid
class Grid {
public:
    void set_cell(int row, int col, Cell cell);
    void swap_buffers();
    std::vector<DirtyRegion> get_dirty_regions() const;
private:
    std::vector<std::vector<Cell>> front_buffer_;
    std::vector<std::vector<Cell>> back_buffer_;
};

} // namespace emacs::tui
```

### 3. gnulib Replacement Strategy

**Decision:** Strangler pattern with shim headers.

**Approach:**
```
┌─────────────────────────────────────────────────────────┐
│  Phase 1: Inventory & Categorize                        │
│  ├── strings: strdup, strndup, stpcpy, asprintf (DONE)  │
│  ├── memory: malloc, realloc, free (DONE - allocator)   │
│  ├── file: faccessat, lstat, tempfile                   │
│  ├── locale: mbrtowc, wcwidth                           │
│  ├── time: timespec, gettimeofday                       │
│  └── regex: regex_t, regcomp                            │
├─────────────────────────────────────────────────────────┤
│  Phase 2: Create C++ Wrappers (shim headers)            │
│  ├── emacs/strings.hpp    (DONE)                        │
│  ├── emacs/allocator.hpp  (DONE)                        │
│  ├── emacs/filesystem.hpp                               │
│  ├── emacs/locale.hpp                                   │
│  ├── emacs/time.hpp                                     │
│  └── emacs/regex.hpp                                    │
├─────────────────────────────────────────────────────────┤
│  Phase 3: Gradual Swap                                  │
│  - Replace call sites one module at a time              │
│  - Run compatibility tests after each swap              │
│  - Keep gnulib for C code paths                         │
├─────────────────────────────────────────────────────────┤
│  Phase 4: Remove gnulib                                 │
│  - When all C++ paths use wrappers                      │
│  - Remove lib/ directory from CMake build               │
└─────────────────────────────────────────────────────────┘
```

**C++20 Shim Example:**
```cpp
// emacs/filesystem.hpp
#pragma once
#include <filesystem>
#include <expected>
#include <system_error>

namespace emacs::fs {

using path = std::filesystem::path;

// Replaces gnulib faccessat
inline auto access(const path& p, int mode) -> std::expected<bool, std::error_code> {
    std::error_code ec;
    auto status = std::filesystem::status(p, ec);
    if (ec) return std::unexpected(ec);
    
    auto perms = status.permissions();
    if (mode & R_OK && (perms & std::filesystem::perms::owner_read) == std::filesystem::perms::none)
        return false;
    if (mode & W_OK && (perms & std::filesystem::perms::owner_write) == std::filesystem::perms::none)
        return false;
    if (mode & X_OK && (perms & std::filesystem::perms::owner_exec) == std::filesystem::perms::none)
        return false;
    return true;
}

// Replaces gnulib tempfile
inline auto temp_path(std::string_view prefix = "emacs") -> path {
    return std::filesystem::temp_directory_path() / 
           std::format("{}_{}", prefix, std::chrono::system_clock::now().time_since_epoch().count());
}

} // namespace emacs::fs
```

### 4. Migration Phase Order (Revised)

**New Order:**
```
Phase 0: Foundation Setup          [DONE]
Phase 1: Core Infrastructure       [DONE]
Phase 2: Entry Point & Startup     [DONE]
Phase 3: Shared Infrastructure     [NEW - extracted from later phases]
Phase 4: Terminal/TUI              [Was Phase 3]
Phase 5: Lisp Interpreter Core     [Was Phase 4]
Phase 6: Platform-Specific GUI     [Was Phase 5]
Phase 7: File I/O & System         [Was Phase 6]
Phase 8: Testing & Validation      [Was Phase 7]
Phase 9: Build System Cleanup      [Was Phase 8]
```

**Phase 3 (NEW): Shared Infrastructure**

Extract common infrastructure needed by multiple modules:

| Component | Purpose | Files |
|-----------|---------|-------|
| Error Handling | Result<T>, error codes | emacs/error.hpp |
| Logging | Structured logging | emacs/log.hpp |
| Platform Abstraction | OS detection, feature flags | emacs/platform.hpp |
| GC-aware Containers | vector, string with GC | emacs/containers.hpp |
| Unicode Utilities | UTF-8, code points, graphemes | emacs/unicode.hpp |
| Path Utilities | Cross-platform paths | emacs/path.hpp |

---

## Testing Strategy

### Test Tiers

```
Tier 0: Build Smoke (< 30s)
├── CMake configure
├── CMake build (Debug + Release)
└── Basic unit test subset

Tier 1: Core Tests (< 5 min)
├── CTest full suite
├── Lisp smoke tests
└── Terminal backend tests

Tier 2: Full Validation (< 30 min)
├── make check (autotools)
├── Memory sanitizers (ASAN, MSAN)
└── Platform matrix (Linux, macOS, Windows)

Tier 3: Nightly (< 2 hours)
├── Full Lisp test suite
├── Performance benchmarks
└── Coverage report
```

### CI/CD Workflow

```yaml
# .github/workflows/cxx-builder.yml
name: C++20 Build

on:
  push:
    branches: [cxx-builder, main]
  pull_request:
    branches: [cxx-builder]

jobs:
  tier0-smoke:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: lukka/get-cmake@latest
      - uses: lukka/run-vcpkg@v11
      - name: Configure
        run: cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
      - name: Build
        run: cmake --build build --config Debug
      - name: Test (smoke)
        run: ctest --test-dir build --output-on-failure -R "smoke"

  tier1-core:
    needs: tier0-smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: lukka/get-cmake@latest
      - uses: lukka/run-vcpkg@v11
      - name: Build
        run: cmake -B build && cmake --build build
      - name: Test (core)
        run: ctest --test-dir build --output-on-failure

  tier2-full:
    needs: tier1-core
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        build_type: [Debug, Release]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: lukka/get-cmake@latest
      - uses: lukka/run-vcpkg@v11
      - name: Build
        run: |
          cmake -B build -DCMAKE_BUILD_TYPE=${{ matrix.build_type }}
          cmake --build build --config ${{ matrix.build_type }}
      - name: Test
        run: ctest --test-dir build --output-on-failure
```

### Local Testing with `act`

```bash
# Install act
brew install act  # macOS
# or: https://github.com/nektos/act

# Run smoke tests locally
act -j tier0-smoke

# Run full pipeline
act push

# Test specific platform
act -j tier0-smoke -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

---

## Detailed Phase Plans

### Phase 3: Shared Infrastructure (Week 9-10) [NEW]

**Goal:** Build foundational C++ infrastructure used by all subsequent phases.

**Deliverables:**

1. **Error Handling** (`emacs/error.hpp`)
   ```cpp
   template<typename T>
   using Result = std::expected<T, std::error_code>;
   
   enum class EmcErrorCode { Success, OutOfMemory, InvalidArgument, ... };
   ```

2. **Logging** (`emacs/log.hpp`)
   ```cpp
   namespace emacs::log {
       void debug(std::string_view fmt, auto&&... args);
       void info(std::string_view fmt, auto&&... args);
       void warn(std::string_view fmt, auto&&... args);
       void error(std::string_view fmt, auto&&... args);
   }
   ```

3. **Platform Abstraction** (`emacs/platform.hpp`)
   ```cpp
   namespace emacs::platform {
       constexpr bool is_windows = /* ... */;
       constexpr bool is_macos = /* ... */;
       constexpr bool is_linux = /* ... */;
       
       auto get_terminal_size() -> TerminalSize;
       auto get_executable_path() -> std::filesystem::path;
   }
   ```

4. **GC-aware Containers** (`emacs/containers.hpp`)
   ```cpp
   template<typename T>
   using gc_vector = std::vector<T, emacs_allocator<T>>;
   
   using gc_string = std::basic_string<char, std::char_traits<char>, emacs_allocator<char>>;
   ```

5. **Unicode Utilities** (`emacs/unicode.hpp`)
   ```cpp
   namespace emacs::unicode {
       auto codepoint_width(char32_t cp) -> int;  // wcwidth replacement
       auto is_combining(char32_t cp) -> bool;
       auto utf8_to_codepoints(std::string_view s) -> std::vector<char32_t>;
   }
   ```

**Tests:**
- `test/test_error.cpp`
- `test/test_log.cpp`
- `test/test_platform.cpp`
- `test/test_containers.cpp`
- `test/test_unicode.cpp`

### Phase 4: Terminal/TUI (Week 11-16)

**Goal:** Replace termbox2 with robust cross-platform terminal implementation.

**Tasks:**

| ID | Task | Priority | Est. Days |
|----|------|----------|-----------|
| 4.1 | Design TUI architecture | High | 2 |
| 4.2 | Integrate libuv event loop | High | 3 |
| 4.3 | Implement input parser | High | 5 |
| 4.4 | Implement capabilities provider | High | 3 |
| 4.5 | Implement Unix backend | High | 4 |
| 4.6 | Implement Windows backend (VT) | Critical | 6 |
| 4.7 | Implement Grid + renderer | High | 5 |
| 4.8 | Port display system (dispnew) | High | 7 |
| 4.9 | Integration tests | High | 3 |
| 4.10 | Performance benchmarks | Medium | 2 |

**Files:**
```
src/tui/
├── backend.hpp           # TerminalBackend concept
├── backend_unix.cpp      # Unix/POSIX implementation
├── backend_windows.cpp   # Windows VT + Console API
├── capabilities.hpp      # Terminfo + built-in DB
├── capabilities.cpp
├── event_loop.hpp        # libuv wrapper
├── event_loop.cpp
├── grid.hpp              # Double-buffered grid
├── grid.cpp
├── input.hpp             # Input parser
├── input.cpp
├── renderer.hpp          # Diff-based renderer
├── renderer.cpp
└── tui.hpp               # Public API
```

**Success Criteria:**
- [ ] Windows TUI works in Windows Terminal, cmd.exe, and PowerShell
- [ ] Mouse support on all platforms
- [ ] UTF-8/CJK character display correct
- [ ] Performance ≥ current termbox2 implementation
- [ ] All terminal tests pass

### Phase 5: Lisp Interpreter Core (Week 17-28)

**Goal:** Migrate Lisp data types and interpreter to C++.

**Tasks:**

| ID | Task | Priority | Est. Days |
|----|------|----------|-----------|
| 5.1 | Design Lisp_Object C++ class | High | 3 |
| 5.2 | Port lisp.h to lisp.hpp | High | 5 |
| 5.3 | Port data.c to data.cpp | High | 7 |
| 5.4 | Port eval.c to eval.cpp | High | 10 |
| 5.5 | Port bytecode.c to bytecode.cpp | High | 5 |
| 5.6 | Port alloc.c GC to C++ | High | 8 |
| 5.7 | Integrate with C++ containers | Medium | 4 |
| 5.8 | Port fns.c to fns.cpp | Medium | 6 |
| 5.9 | Lisp test suite green | Critical | 7 |

**C++ Lisp Design:**
```cpp
// Using std::variant for type safety
namespace emacs::lisp {

using Lisp_Object = std::variant<
    std::monostate,           // nil
    int64_t,                  // fixnum
    double,                   // float
    gc_string,                // string
    std::shared_ptr<Cons>,    // cons
    std::shared_ptr<Symbol>,  // symbol
    std::shared_ptr<Vector>,  // vector
    std::shared_ptr<Buffer>,  // buffer
    std::function<Lisp_Object(std::span<Lisp_Object>)>  // subr
>;

} // namespace emacs::lisp
```

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Dual-build divergence | Medium | High | CI parity checks, build artifact comparison |
| Windows TUI regression | High | High | Keep old backend as fallback; A/B testing |
| gnulib semantic mismatch | Medium | Medium | Focused regression tests, especially locale/encoding |
| Performance regression | Low | High | Benchmarks in CI, profile before/after |
| Upstream sync conflicts | Medium | Low | Minimize C file changes; keep autotools green |

---

## Milestones & Exit Criteria

| Milestone | Target Date | Exit Criteria |
|-----------|-------------|---------------|
| M1: Infrastructure | Week 10 | All Phase 3 tests pass |
| M2: TUI Alpha | Week 14 | Basic rendering on all platforms |
| M3: TUI Beta | Week 16 | Mouse + full UTF-8 + Windows usable |
| M4: Lisp Alpha | Week 22 | Basic eval works, 50% tests pass |
| M5: Lisp Beta | Week 28 | All Lisp tests pass |
| M6: Autotools Frozen | Week 32 | CMake-only for new development |
| M7: Release Candidate | Week 36 | Full test suite, benchmarks |

---

## Documentation Requirements

All migration work must be documented in `doc/cxx-builder/`:

```
doc/cxx-builder/
├── README.md                 # Overview and quick start
├── strategy-v2.md            # This document
├── phases/
│   ├── phase3-infrastructure.md
│   ├── phase4-tui.md
│   ├── phase5-lisp.md
│   └── ...
├── progress/
│   ├── phase-tracker.md
│   └── weekly-reports/
├── technical/
│   ├── tui-architecture.md
│   ├── gnulib-replacement.md
│   ├── lisp-object-design.md
│   └── cmake-patterns.md
└── build/
    ├── github-actions.md
    ├── local-testing.md
    └── vcpkg-setup.md
```

---

## Appendix A: gnulib Function Inventory

### Category: Strings (Priority: HIGH - DONE)

| Function | Usage Count | C++20 Replacement | Status |
|----------|-------------|-------------------|--------|
| strdup | 100+ | std::string | ✅ |
| strndup | 50+ | std::string(data, n) | ✅ |
| stpcpy | 10+ | std::strcpy + ptr | ✅ |
| strnlen | 30+ | std::char_traits | ✅ |
| asprintf | 20+ | std::format | ✅ |
| getline | 15+ | std::getline | ✅ |

### Category: Memory (Priority: HIGH - DONE)

| Function | Usage Count | C++20 Replacement | Status |
|----------|-------------|-------------------|--------|
| malloc | 100+ | emacs_allocator | ✅ |
| realloc | 50+ | emacs_allocator | ✅ |
| free | 100+ | emacs_allocator | ✅ |

### Category: File I/O (Priority: MEDIUM)

| Function | Usage Count | C++20 Replacement | Status |
|----------|-------------|-------------------|--------|
| faccessat | 10+ | std::filesystem::status | ⬜ |
| lstat | 20+ | std::filesystem::symlink_status | ⬜ |
| tempfile | 5+ | std::filesystem::temp_directory_path | ⬜ |
| mkdtemp | 3+ | std::filesystem::create_directory | ⬜ |

### Category: Locale (Priority: MEDIUM)

| Function | Usage Count | C++20 Replacement | Status |
|----------|-------------|-------------------|--------|
| mbrtowc | 30+ | std::mbrtoc32 (C++20) | ⬜ |
| wcwidth | 50+ | Custom implementation | ⬜ |
| iswprint | 20+ | std::iswprint | ⬜ |

### Category: Time (Priority: LOW)

| Function | Usage Count | C++20 Replacement | Status |
|----------|-------------|-------------------|--------|
| gettimeofday | 10+ | std::chrono::system_clock | ⬜ |
| timespec | 15+ | std::chrono::duration | ⬜ |
| nanosleep | 5+ | std::this_thread::sleep_for | ⬜ |

---

## Appendix B: Build Command Reference

### Development Build

```bash
# Configure (Debug)
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug

# Configure with vcpkg
cmake -B build -S . \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
  -DCMAKE_BUILD_TYPE=Debug

# Build
cmake --build build --config Debug -j$(nproc)

# Test
ctest --test-dir build --output-on-failure

# Test with verbose
ctest --test-dir build --output-on-failure -V
```

### Release Build

```bash
cmake -B build-release -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --config Release -j$(nproc)
```

### Cross-Platform Notes

**Windows (MSVC):**
```powershell
cmake -B build -S . -G "Visual Studio 17 2022" -A x64
cmake --build build --config Debug
```

**Windows (MinGW):**
```bash
cmake -B build -S . -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

**macOS (Apple Clang):**
```bash
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(sysctl -n hw.ncpu)
```

---

**Document History:**
- 2025-02-03: v2.0 - Major revision based on analysis and expert consultation
- 2026-02-01: v1.0 - Initial strategy document
