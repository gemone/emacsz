# AGENTS.md - GNU Emacs C++20 Migration Guide

**Project**: GNU Emacs - C++20 Migration Branch
**Build System**: CMake (C++20) + autotools (legacy)
**Language**: C11 → C++20 (incremental migration)
**Current Phase**: Phase 9.2 - Platform Backends (Phase 0-9.1 Complete ✅)
**Overall Progress**: 87.2%

**Last Updated**: 2026-02-07

---

## 🎯 Migration Status

```
Phase 0: Foundation Setup        ████████████████  100%  ✅
Phase 1: Core Infrastructure     ████████████████  100%  ✅
Phase 2: Entry Point & Startup  ████████████████  100%  ✅
Phase 3: Shared Infrastructure  ████████████████  100%  ✅
Phase 4: Terminal/TUI           ████████████████  100%  ✅
Phase 5: Emacs Core Integration ████████████████  100%  ✅
Phase 6: Lisp Interpreter Core  ████████████████  100%  ✅
Phase 7: Command System         ████████████████  100%  ✅
Phase 8: GUI & Platform         ███████████░░░░░   70%  ✅
Phase 9: I/O, Test & Polish    ██░░░░░░░░░░░░░░   10%  ← CURRENT
```

**Completed Modules (Phase 0-3):**
- ✅ Memory allocator (GC-aware C++20 allocator) — `src/allocator.hpp/cpp`
- ✅ String utilities (std::string, std::format replacements) — `src/strings.hpp/cpp`
- ✅ Error handling (Result<T>, exceptions)
- ✅ Logging (structured thread-safe logging) — `src/log.hpp`
- ✅ Platform abstraction (OS/arch detection) — `src/platform.hpp` (432 lines)
- ✅ GC-aware containers (gc_vector, gc_string, gc_deque, gc_map) — `src/containers.hpp`
- ✅ Entry point (C++20 main with RAII) — `src/main_minimal.cpp`
- ✅ Termbox2 TUI backend (working demo) — `src/termbox2_term.cpp` (555 lines)
- ✅ gnulib replacements (32 headers) — `src/gnulib/`
- ✅ POSIX TTY backend (termios + ANSI) — `src/xterm.hpp/cpp` (rewritten)
- ✅ Platform stub backends — `src/w32term.hpp/cpp`, `src/nsterm.hpp/cpp`, `src/haikuterm.hpp/cpp`, `src/androidterm.hpp/cpp`

**Completed Modules (Phase 4 - Terminal/TUI):**
- ✅ Grid system — double-buffered `Cell` grid with dirty region tracking (436 lines)
- ✅ Input parser — terminal escape sequence → `InputEvent` (Key/Mouse/Resize) (650 lines)
- ✅ Event loop — non-blocking stdin reader with `EventCallback` (206 lines)
- ✅ Renderer — Grid → ANSI escape sequences, dirty-region-only rendering (261 lines)

**Completed Modules (Phase 5 - Emacs Core Integration):**
- ✅ Display adapter — `struct face` → `CellAttributes`, `struct glyph` → Grid cells (411 lines, 9 tests)
- ✅ Input adapter — `InputEvent` → Emacs `struct input_event`, X11 keysyms (428 lines, 10 tests)
- ✅ Window adapter — Emacs `struct window` glyph matrix → Grid sync (619 lines, 11 tests)
- ✅ Event loop adapter — EventLoop → kbd_buffer ring (gc_deque, capacity 256) (423 lines, 12 tests)
- ✅ Redisplay adapter — frame → windows → Grid → Renderer → TTY orchestrator (667 lines, 11 tests)
- ✅ Mouse adapter — terminal (row,col) → window → buffer position, drag tracking (383 lines, 12 tests)
- ✅ Integration tests — 12 end-to-end pipeline tests + interactive TUI demo (634 lines)

**Completed Modules (Phase 6 - Lisp Interpreter Core):**
- ✅ Gap buffer — C++20 gap buffer with `gc_vector_t<char>`, 1-based positions, UTF-8 aware (513 lines, 17 tests)
- ✅ Buffer object — `EmacsBuffer` wrapping `GapBuffer` with Emacs buffer semantics, `extern "C"` bridge (490 lines, 20 tests)
- ✅ Marker system — position markers that auto-adjust on edits, BEFORE/AFTER insertion types (integrated in buffer)
- ✅ Undo system — `UndoManager` with INSERT/DELETE records, undo groups, redo support (265 lines, 16 tests)
- ✅ Buffer↔Window bridge — `BufferBridge` connecting buffer → Grid cells, tab expansion, cursor mapping (388 lines, 17 tests)
- ✅ Integration tests — 15 end-to-end tests covering full edit→display→render pipeline (680 lines)
- ⏭️ Text properties — deferred to Phase 8 (overlays, faces, syntax properties)

**Completed Modules (Phase 7 - Command System & Minibuffer):**
- ✅ Command registry — `CommandRegistry` singleton, named commands with `std::function`, metadata, prefix completion (194 lines, 16 tests)
- ✅ Keymap system — hierarchical keymaps (global → major → minor → local), prefix keys, key sequences (403 lines, 20 tests)
- ✅ Command dispatcher — `InputEvent` → keymap lookup → command execution, C-u prefix arg, self-insert fallback (364 lines, 18 tests)
- ✅ Minibuffer — single-line input with prompt, tab completion, completion cycling, echo area, M-x support (404 lines, 18 tests)
- ✅ Basic commands — 15 editing commands: self-insert, forward/backward-char, beginning/end-of-line, delete, newline, kill-line, undo/redo, next/previous-line (567 lines, 21 tests)
- ✅ Integration tests — 12 end-to-end tests covering full keystroke→command→buffer→display pipeline (12 tests)

**Next Priority:** Phase 9 - I/O, Test & Polish

**Completed Modules (Phase 8 - GUI & Platform):**
- ✅ Buffer correctness (8.1) — mark, narrowing, integrated undo, undo amalgamation — `src/emacs_buffer.hpp/cpp` (expanded, 33 tests)
- ✅ MCP Server (8.2) — JSON-RPC 2.0 stdio server for AI agent control — `src/emacs_mcp_server.hpp/cpp` (~724 lines, 20 tests)
  - Tools: buffer_open, buffer_list, buffer_content, buffer_insert, buffer_delete, execute_command, cursor_get, cursor_set, buffer_state
  - Vendored: `third_party/nlohmann/json.hpp` (nlohmann/json v3.11.3)
- ✅ SDL2 Backend (8.3) — graphical GUI backend with font rendering and glyph caching — `src/sdl2_term.hpp/cpp` (~597 lines, 15 mock tests)
  - Guarded by `#ifdef EMACS_USE_SDL2`, requires SDL2 + SDL2_ttf
  - Satisfies `TerminalBackend` concept
- ✅ Mode System (8.4) — major/minor mode infrastructure — `src/emacs_mode.hpp/cpp` (416 lines, 20 tests)
  - ModeManager singleton with define/activate/enable/disable
  - Keymap wiring through KeymapManager, mode inheritance (parent keymap fallback)
  - extern "C" bridge for C interop
- ✅ Integration Tests (8.5) — 15 cross-component tests — `test/cxx/test_phase8_integration.cpp`
- ⏭️ Platform backends (8.6) — xterm, Windows TUI, nsterm, haiku, android — deferred to Phase 9

**Completed Modules (Phase 9 - I/O, Test & Polish):**
- ✅ Text Properties (9.1) — interval-based text property system with face rendering — `src/text_properties.hpp/cpp` (~340 lines, 30 tests)
  - PropertyInterval: half-open [start,end), 1-based, front/rear sticky
  - TextPropertyValue: variant<CellAttributes, gc_string, ptrdiff_t>
  - put/get/remove/get_face/put_face, for_each_in_range, next_property_change
  - Auto-adjust on insert/delete (hooked into EmacsBuffer)
  - Per-character face rendering in BufferBridge
  - extern "C" bridge: put_text_property, put_face, remove_text_property, has_text_property
- ✅ POSIX TTY Backend (9.2) — full terminal emulation using termios + ANSI escape sequences — `src/xterm.hpp/cpp` (~560 lines)
  - PosixTtyBackend class satisfying TerminalBackend concept
  - termios raw mode, alternate screen buffer, mouse tracking (SGR mode)
  - 24-bit TrueColor support (RGB foreground/background)
  - ANSI attributes: bold, italic, underline, blink, inverse
  - Cursor positioning, clear operations, line/glyph operations
  - Guarded by `#ifdef EMACS_USE_POSIX_TTY` with clean stub when disabled
  - input parsing for keys and mouse events
  - ioctl TIOCGWINSZ for terminal size detection
- ✅ Platform Stub Backends (9.2) — cross-platform guarded stub implementations — `src/w32term.hpp/cpp`, `src/nsterm.hpp/cpp`, `src/haikuterm.hpp/cpp`, `src/androidterm.hpp/cpp`
  - WindowsConsoleBackend (EMACS_USE_W32): Windows Console API + VT100 fallback
  - MacOSNativeBackend (EMACS_USE_NSTERM): macOS-enhanced POSIX TTY (termios + ANSI)
  - HaikuBackend (EMACS_USE_HAIKU): Haiku Be API stub
  - AndroidBackend (EMACS_USE_ANDROID): Android NDK stub
  - All satisfy TerminalBackend concept via `static_assert`
  - Stub implementations compile on all platforms (verified on macOS)
- ✅ Buffer correctness (8.1) — mark, narrowing, integrated undo, undo amalgamation — `src/emacs_buffer.hpp/cpp` (expanded, 33 tests)
- ✅ MCP Server (8.2) — JSON-RPC 2.0 stdio server for AI agent control — `src/emacs_mcp_server.hpp/cpp` (~724 lines, 20 tests)
  - Tools: buffer_open, buffer_list, buffer_content, buffer_insert, buffer_delete, execute_command, cursor_get, cursor_set, buffer_state
  - Vendored: `third_party/nlohmann/json.hpp` (nlohmann/json v3.11.3)
- ✅ SDL2 Backend (8.3) — graphical GUI backend with font rendering and glyph caching — `src/sdl2_term.hpp/cpp` (~597 lines, 15 mock tests)
  - Guarded by `#ifdef EMACS_USE_SDL2`, requires SDL2 + SDL2_ttf
  - Satisfies `TerminalBackend` concept
- ✅ Mode System (8.4) — major/minor mode infrastructure — `src/emacs_mode.hpp/cpp` (416 lines, 20 tests)
  - ModeManager singleton with define/activate/enable/disable
  - Keymap wiring through KeymapManager, mode inheritance (parent keymap fallback)
  - extern "C" bridge for C interop
- ✅ Integration Tests (8.5) — 15 cross-component tests — `test/cxx/test_phase8_integration.cpp`
- ⏭️ Platform backends (8.6) — xterm, Windows TUI, nsterm, haiku, android — deferred to Phase 9

**Completed Modules (Phase 9 - I/O, Test & Polish):**
- ✅ Text Properties (9.1) — interval-based text property system with face rendering — `src/text_properties.hpp/cpp` (~340 lines, 30 tests)
  - PropertyInterval: half-open [start,end), 1-based, front/rear sticky
  - TextPropertyValue: variant<CellAttributes, gc_string, ptrdiff_t>
  - put/get/remove/get_face/put_face, for_each_in_range, next_property_change
  - Auto-adjust on insert/delete (hooked into EmacsBuffer)
  - Per-character face rendering in BufferBridge
  - extern "C" bridge: put_text_property, put_face, remove_text_property, has_text_property
- ⏭️ Platform backends (9.2) — xterm, Windows TUI, nsterm, haiku, android
- ⏭️ File I/O & System (9.3) — gnulib replacements (filesystem, locale, chrono, regex)

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

# Phase 5 integration tests (all 12 end-to-end tests)
g++ -std=c++20 -I src test/cxx/test_phase5_integration.cpp \
    src/emacs_mouse_adapter.cpp src/emacs_redisplay_adapter.cpp \
    src/emacs_event_loop_adapter.cpp src/emacs_display_adapter.cpp \
    src/emacs_input_adapter.cpp src/emacs_window_adapter.cpp \
    src/event_loop.cpp src/input_parser.cpp src/grid.cpp \
    src/renderer.cpp src/allocator.cpp \
    -o /tmp/test_phase5_integration && /tmp/test_phase5_integration

# Phase 5 standalone adapter tests (per module)
g++ -std=c++20 -I src test/cxx/test_display_adapter_standalone.cpp \
    src/emacs_display_adapter.cpp src/grid.cpp src/allocator.cpp \
    -o /tmp/test_display && /tmp/test_display

g++ -std=c++20 -I src test/cxx/test_mouse_adapter_standalone.cpp \
    src/emacs_mouse_adapter.cpp src/emacs_input_adapter.cpp \
    src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_mouse && /tmp/test_mouse

# Phase 6 unit tests (per module)
g++ -std=c++20 -I src test/cxx/test_gap_buffer.cpp \
    src/gap_buffer.cpp src/allocator.cpp \
    -o /tmp/test_gap_buffer && /tmp/test_gap_buffer

g++ -std=c++20 -I src test/cxx/test_emacs_buffer.cpp \
    src/emacs_buffer.cpp src/gap_buffer.cpp src/emacs_undo.cpp \
    src/text_properties.cpp src/allocator.cpp \
    -o /tmp/test_emacs_buffer && /tmp/test_emacs_buffer

g++ -std=c++20 -I src test/cxx/test_emacs_undo.cpp \
    src/emacs_undo.cpp src/allocator.cpp \
    -o /tmp/test_emacs_undo && /tmp/test_emacs_undo

g++ -std=c++20 -I src test/cxx/test_buffer_bridge.cpp \
    src/emacs_buffer_bridge.cpp src/emacs_buffer.cpp \
    src/gap_buffer.cpp src/emacs_undo.cpp src/grid.cpp src/allocator.cpp \
    -o /tmp/test_buffer_bridge && /tmp/test_buffer_bridge

# Phase 6 integration tests (15 end-to-end tests)
g++ -std=c++20 -I src test/cxx/test_phase6_integration.cpp \
    src/emacs_buffer_bridge.cpp src/emacs_buffer.cpp src/gap_buffer.cpp \
    src/emacs_undo.cpp src/text_properties.cpp src/emacs_mouse_adapter.cpp \
    src/emacs_redisplay_adapter.cpp src/emacs_event_loop_adapter.cpp \
    src/emacs_display_adapter.cpp src/emacs_input_adapter.cpp \
    src/emacs_window_adapter.cpp src/event_loop.cpp src/input_parser.cpp \
    src/grid.cpp src/renderer.cpp src/allocator.cpp \
    -o /tmp/test_phase6_integration && /tmp/test_phase6_integration

# Phase 7 unit tests (per module)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_command_registry.cpp src/emacs_command_registry.cpp \
    src/allocator.cpp \
    -o /tmp/test_command_registry && /tmp/test_command_registry

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_keymap.cpp src/emacs_keymap.cpp \
    src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_keymap && /tmp/test_keymap

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_command_dispatcher.cpp src/emacs_command_dispatcher.cpp \
    src/emacs_command_registry.cpp src/emacs_keymap.cpp \
    src/emacs_buffer.cpp src/gap_buffer.cpp src/emacs_undo.cpp \
    src/text_properties.cpp src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_command_dispatcher && /tmp/test_command_dispatcher

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_minibuffer.cpp src/emacs_minibuffer.cpp \
    src/emacs_command_registry.cpp src/emacs_command_dispatcher.cpp \
    src/emacs_keymap.cpp src/emacs_buffer.cpp src/gap_buffer.cpp \
    src/emacs_undo.cpp src/text_properties.cpp src/input_parser.cpp \
    src/allocator.cpp \
    -o /tmp/test_minibuffer && /tmp/test_minibuffer

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_basic_commands.cpp src/emacs_basic_commands.cpp \
    src/emacs_command_dispatcher.cpp src/emacs_command_registry.cpp \
    src/emacs_keymap.cpp src/emacs_buffer.cpp src/gap_buffer.cpp \
    src/emacs_undo.cpp src/text_properties.cpp src/input_parser.cpp \
    src/allocator.cpp \
    -o /tmp/test_basic_commands && /tmp/test_basic_commands

# Phase 7 integration tests (12 end-to-end tests)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_phase7_integration.cpp src/emacs_basic_commands.cpp \
    src/emacs_minibuffer.cpp src/emacs_command_dispatcher.cpp \
    src/emacs_command_registry.cpp src/emacs_keymap.cpp \
    src/emacs_buffer.cpp src/gap_buffer.cpp src/emacs_undo.cpp \
    src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_phase7_integration && /tmp/test_phase7_integration

# Phase 8 unit tests (per module)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    -I third_party test/cxx/test_mcp_server.cpp \
    src/emacs_mcp_server.cpp src/emacs_buffer.cpp src/gap_buffer.cpp \
    src/emacs_undo.cpp src/emacs_command_registry.cpp src/allocator.cpp \
    -o /tmp/test_mcp_server && /tmp/test_mcp_server

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_sdl2_backend.cpp src/allocator.cpp \
    -o /tmp/test_sdl2_backend && /tmp/test_sdl2_backend

g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_mode.cpp src/emacs_mode.cpp \
    src/emacs_keymap.cpp src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_mode && /tmp/test_mode

# Phase 8 integration tests (15 cross-component tests)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    -I third_party test/cxx/test_phase8_integration.cpp \
    src/emacs_mcp_server.cpp src/emacs_mode.cpp \
    src/emacs_basic_commands.cpp src/emacs_command_dispatcher.cpp \
    src/emacs_command_registry.cpp src/emacs_keymap.cpp \
    src/emacs_buffer.cpp src/gap_buffer.cpp src/emacs_undo.cpp \
    src/input_parser.cpp src/allocator.cpp \
    -o /tmp/test_phase8_integration && /tmp/test_phase8_integration

# Phase 9 unit tests (per module)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_text_properties.cpp src/text_properties.cpp \
    src/emacs_buffer.cpp src/emacs_buffer_bridge.cpp \
    src/gap_buffer.cpp src/emacs_undo.cpp src/grid.cpp src/allocator.cpp \
    -o /tmp/test_text_properties && /tmp/test_text_properties
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
- Phase 0-7: Both active (currently here ✅)
- Phase 6: CMake becomes CI-authoritative
- Phase 7: Autotools frozen
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
| Locale | mbrtowc, wcwidth, iswprint | Phase 7 |
| Time | gettimeofday, nanosleep | Phase 7 |
| Regex | regcomp, regexec | Phase 7 |

---

## 📦 CMake Targets & Modules

### Libraries (Built)
```bash
# View all targets
cd build-cpp && make help

# Core modules (Phase 0-3)
emacs_allocator          # GC-aware C++20 allocator
emacs_strings            # String utilities (currently disabled)
emacs_termbox2_backend   # TUI backend
emacs_gnulib_replacement # gnulib → std:: replacements (header-only)
emacs_terminal_concept   # Terminal interface concept (header-only)

# Phase 4 modules
emacs_grid               # Double-buffered cell grid
emacs_input_parser       # Terminal escape sequence parser
emacs_event_loop         # Non-blocking async event loop
emacs_renderer           # Grid → ANSI terminal output

# Phase 5 modules (Emacs adapters)
emacs_display_adapter    # face/glyph → CellAttributes/Grid
emacs_input_adapter      # InputEvent → Emacs input_event
emacs_window_adapter     # Emacs window → Grid sync
emacs_event_loop_adapter # EventLoop → kbd_buffer ring
emacs_redisplay_adapter  # frame → Grid → Renderer pipeline
emacs_mouse_adapter      # terminal pos → window/buffer pos

# Phase 6 modules (Buffer/Text engine)
emacs_gap_buffer         # C++20 gap buffer with GC-aware allocation
emacs_buffer             # EmacsBuffer wrapper with markers
emacs_undo               # Undo/redo manager
emacs_buffer_bridge      # Buffer → Grid/glyph matrix bridge

# Phase 7 modules (Command system)
emacs_command_registry   # Named commands with std::function
emacs_keymap             # Hierarchical keymaps (global→major→minor→local)
emacs_command_dispatcher # InputEvent → keymap → command execution
emacs_minibuffer         # Single-line input with completion
emacs_basic_commands     # 15 core editing commands

# Phase 8 modules (GUI & Platform)
emacs_mcp_server         # JSON-RPC 2.0 MCP server for AI agents
emacs_sdl2_backend       # SDL2 graphical backend (ifdef EMACS_USE_SDL2)
emacs_mode               # Major/minor mode system

# Phase 9 modules (I/O, Test & Polish)
emacs_text_properties    # Interval-based text properties with face rendering
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
   - **Fix Target**: Phase 8 (GUI/Platform)

### Medium Issues:

4. **gnulib Unicode Limitation**
   - Full Unicode character properties require ICU library
   - Currently using std::locale + std::wcwidth
   - May need vcpkg integration for ICU

5. **Dual-Build Drift**
   - CMake and autotools may diverge over time
   - **Mitigation**: CI checks, monthly verification

### Minor Issues (Pre-existing, Harmless):

6. **allocator.hpp:237 warning** — `get_emacs_allocator` has C-linkage but returns C++ type
7. **input_parser.hpp:154 warning** — anonymous types in anonymous union
8. **`[[nodiscard]]` warnings** — `grid.set_cell()` return value unused in display/window adapters
   
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
- `src/grid.hpp` - Double-buffered cell grid with CellAttributes (290 lines)
- `src/input_parser.hpp` - Terminal escape sequence parser (276 lines)
- `src/emacs_redisplay_adapter.hpp/cpp` - Full redisplay pipeline (667 lines)
- `src/emacs_mouse_adapter.hpp/cpp` - Mouse position → window/buffer mapping (383 lines)
- `src/gap_buffer.hpp/cpp` - C++20 gap buffer with GC-aware allocation (513 lines)
- `src/emacs_buffer.hpp/cpp` - Buffer object with markers and extern "C" bridge (490 lines)
- `src/emacs_undo.hpp/cpp` - Undo/redo manager with undo groups (265 lines)
- `src/emacs_buffer_bridge.hpp/cpp` - Buffer → Grid/glyph matrix bridge (388 lines)
- `src/emacs_command_registry.hpp/cpp` - Command registry with named commands (194 lines)
- `src/emacs_keymap.hpp/cpp` - Hierarchical keymaps with prefix keys (403 lines)
- `src/emacs_command_dispatcher.hpp/cpp` - Key dispatch with prefix arg (364 lines)
- `src/emacs_minibuffer.hpp/cpp` - Minibuffer with tab completion (404 lines)
- `src/emacs_basic_commands.hpp/cpp` - 15 core editing commands (567 lines)
- `src/emacs_mcp_server.hpp/cpp` - JSON-RPC 2.0 MCP server for AI agents (~724 lines)
- `src/sdl2_term.hpp/cpp` - SDL2 graphical backend with glyph caching (~597 lines)
- `src/emacs_mode.hpp/cpp` - Major/minor mode system (416 lines)
- `src/text_properties.hpp/cpp` - Interval-based text properties with face rendering (~340 lines)

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

### Phase 7 Completion Summary:

**All success criteria met ✅:**
- [x] Command registry with named commands and metadata
- [x] Hierarchical keymap system (global → major → minor → local)
- [x] Key dispatch: InputEvent → keymap lookup → command execution
- [x] C-u prefix argument handling (×4 multiplier)
- [x] Minibuffer with prompt, tab completion, and M-x support
- [x] 15 basic editing commands registered and working
- [x] All Phase 5-6 tests still pass (no regressions)
- [x] New Phase 7 unit + integration tests pass — 105 tests

**Phase 7 Test Summary:**
| Module | Tests | Test File |
|--------|-------|-----------|
| Command Registry | 16 | `test/cxx/test_command_registry.cpp` |
| Keymap System | 20 | `test/cxx/test_keymap.cpp` |
| Command Dispatcher | 18 | `test/cxx/test_command_dispatcher.cpp` |
| Minibuffer | 18 | `test/cxx/test_minibuffer.cpp` |
| Basic Commands | 21 | `test/cxx/test_basic_commands.cpp` |
| Integration (E2E) | 12 | `test/cxx/test_phase7_integration.cpp` |
| **Total** | **105** | |

**Cumulative Test Summary (Phases 5-7):**
| Phase | Tests |
|-------|-------|
| Phase 5 (Emacs Core Integration) | 12 |
| Phase 6 (Buffer/Text Engine) | 85 |
| Phase 7 (Command System) | 105 |
| **Grand Total** | **202** |

**Architecture (Phases 4-7, all tested, 202 tests total):**
```
Terminal (stdin) → EventLoop → InputParser → InputEvent
                                                ↓
                              EmacsInputAdapter (KeyEvent → input_event)
                              EmacsMouseAdapter (MouseEvent → window/buffer pos)
                                                ↓
                              EmacsEventLoopAdapter (kbd_buffer ring, gc_deque)
                                                ↓
                    ┌─────────── Phase 7 ──────────────────────┐
                    │ CommandDispatcher                         │
                    │   → KeymapManager.lookup_sequence()       │
                    │   → CommandRegistry.execute()              │
                    │ Minibuffer (M-x, prompts, completion)      │
                    │ Basic Commands (15 editing commands)        │
                    └──────────────┬───────────────────────────┘
                                   ↓
                    ┌─────────── Phase 6 ──────────────┐
                    │ EmacsBuffer (GapBuffer + Markers) │
                    │ UndoManager (undo/redo groups)    │
                    └──────────────┬───────────────────┘
                                   ↓
                    ┌─── BufferBridge (6.5) ───┐
                    │ buffer → Grid cells      │
                    │ buffer → glyph matrix    │
                    │ point → cursor (row,col) │
                    └──────────┬───────────────┘
                               ↓
                    EmacsRedisplayAdapter
                      ├── EmacsWindowAdapter (window → Grid sync)
                      ├── EmacsDisplayAdapter (face/glyph → Cell)
                      ├── Grid (double-buffered cells)
                      └── Renderer (Grid → ANSI → TTY)
```

### Current Migration Target: Phase 9.3 - File I/O & System (gnulib replacements) (Phase 0-9.2 Complete ✅)

### Phase 9.2 Planned Components:

| ID | Component | Description | Status |
|----|-----------|-------------|--------|
| 9.1 | Text Properties | Interval-based text properties with face rendering | ✅ DONE |
| 9.2 | Platform Backends | xterm, Windows TUI, nsterm, haiku, android | ⏭️ Pending |
| 9.3 | File I/O & System | gnulib replacements (filesystem, locale, chrono, regex) | ⏭️ Pending |

### Phase 9 Test Summary:
| Module | Tests | Test File |
|--------|-------|-----------|
| Text Properties | 30 | `test/cxx/test_text_properties.cpp` |
| **Total** | **30** | |

**Cumulative Test Summary (Phases 5-9):**
| Phase | Tests |
|-------|-------|
| Phase 5 (Emacs Core Integration) | 12 |
| Phase 6 (Buffer/Text Engine) | 85 |
| Phase 7 (Command System) | 105 |
| Phase 8 (GUI & Platform) | 103 |
| Phase 9 (I/O, Test & Polish) | 35 |
| **Grand Total** | **340** |

### Phase 8 Test Summary:
| Module | Tests | Test File |
|--------|-------|-----------|
| Buffer (expanded) | 33 | `test/cxx/test_emacs_buffer.cpp` |
| MCP Server | 20 | `test/cxx/test_mcp_server.cpp` |
| SDL2 Backend (mock) | 15 | `test/cxx/test_sdl2_backend.cpp` |
| Mode System | 20 | `test/cxx/test_mode.cpp` |
| Integration (E2E) | 15 | `test/cxx/test_phase8_integration.cpp` |
| **Total** | **103** | |

### Phase 9 Test Summary:
| Module | Tests | Test File |
|--------|-------|-----------|
| Text Properties | 30 | `test/cxx/test_text_properties.cpp` |
| Filesystem (gnulib) | 5 | `test/cxx/test_phase93_gnulib.cpp` |
| **Total** | **35** | |

**Cumulative Test Summary (Phases 5-9):**
| Phase | Tests |
|-------|-------|
| Phase 5 (Emacs Core Integration) | 12 |
| Phase 6 (Buffer/Text Engine) | 85 |
| Phase 7 (Command System) | 105 |
| Phase 8 (GUI & Platform) | 103 |
| Phase 9 (I/O, Test & Polish) | 35 |
| **Grand Total** | **335** |

**Architecture (Phases 4-9, all tested, 335 tests total):**
```
Terminal (stdin) → EventLoop → InputParser → InputEvent
    OR                                         ↓
SDL2 Window → SDL_Event → InputEvent      EmacsInputAdapter
                                               ↓
                              EmacsEventLoopAdapter (kbd_buffer)
                                               ↓
                    ┌─────── Phase 7 ─────────────────────────┐
                    │ CommandDispatcher → KeymapManager        │
                    │   → CommandRegistry.execute()            │
                    │ Minibuffer (M-x, prompts, completion)    │
                    │ Basic Commands (15 editing commands)      │
                    └──────────────┬──────────────────────────┘
                                   ↓
                    ┌─── Phase 8 ──────────────────────────┐
                    │ ModeManager (8.4)                     │
                    │   → major/minor mode activation       │
                    │   → keymap wiring + hooks             │
                    │ EmacsBuffer (6 + 8.1)                │
                    │   + Mark, Narrowing, Integrated Undo  │
                    │ UndoManager (undo/redo groups)        │
                    └──────────────┬───────────────────────┘
                                   ↓
                    ┌─── BufferBridge (6.5) ───┐
                    │ buffer → Grid cells      │
                    │ point → cursor (row,col) │
                    │ TextProperties (9.1)     │
                    │   → per-char face render  │
                    └──────────┬───────────────┘
                               ↓
                    Grid → Renderer → TerminalBackend
                                        ├── Termbox2Backend (TUI)
                                        └── SDL2Backend (8.3, GUI)

   MCP Server (8.2) ←→ EmacsBuffer + CommandRegistry
   (stdio JSON-RPC)     (AI agent control interface)
```

---

## 📋 Next Action Plan (Immediate)

### For Phase 9 Continuation:

1. **Platform Backends** (HIGH PRIORITY)
   - xterm backend (full terminal emulation)
   - Windows TUI (VT100 + Console API fallback)
   - nsterm backend (macOS native)
   - haikuterm, androidterm real implementations

2. **File I/O & System** (gnulib replacements)
   - faccessat, lstat, tempfile → std::filesystem
   - mbrtowc, wcwidth, iswprint → std::locale
   - gettimeofday, nanosleep → std::chrono
   - regcomp, regexec → std::regex

### Immediate Commands:

```bash
# 1. Verify all tests pass (Phase 9.1 text properties)
g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-unused-variable -I src \
    test/cxx/test_text_properties.cpp src/text_properties.cpp \
    src/emacs_buffer.cpp src/emacs_buffer_bridge.cpp \
    src/gap_buffer.cpp src/emacs_undo.cpp src/grid.cpp src/allocator.cpp \
    -o /tmp/test_text_properties && /tmp/test_text_properties

# 2. Reconfigure CMake
cmake -B build-cpp -S . -DCMAKE_BUILD_TYPE=Debug

# 3. Build current state
cmake --build build-cpp --config Debug
```

---

**Last Updated**: 2026-02-07
**Current Phase**: Phase 9 - I/O, Test & Polish (Phase 0-8.5, 9.1 Complete ✅)
**Next Milestone**: Phase 9.2 - Platform Backends
**Critical Path**: Platform backends → File I/O → Polish

**For Questions**: See `doc/cxx-builder/README.md` or consult phase documentation in `doc/cxx-builder/phases/`
