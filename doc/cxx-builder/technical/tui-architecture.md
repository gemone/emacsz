# TUI Architecture Design

**Version:** 1.0  
**Date:** 2025-02-03  
**Status:** Design Phase  
**Phase:** Phase 4 (Terminal/TUI)

---

## Overview

This document describes the architecture for Emacs's new cross-platform Terminal User Interface (TUI) implementation, designed to replace the current termbox2-based solution with a more robust, Windows-friendly implementation inspired by Neovim's TUI architecture.

### Goals

1. **Cross-platform compatibility** - Linux, macOS, Windows, BSD
2. **Windows usability** - First-class Windows Terminal, cmd.exe, PowerShell support
3. **Performance** - Match or exceed current TUI performance
4. **Modern C++20** - Leverage concepts, coroutines, std::span
5. **SDL3-ready** - Clean abstraction layer for future GUI integration

### Non-Goals

1. GUI rendering (reserved for SDL3)
2. Network transparency (like X11 forwarding)
3. Supporting legacy terminals without VT100

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Emacs Core                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Lisp      │  │   Buffer    │  │   Window    │  │    Display      │  │
│  │  Interpreter│  │   Manager   │  │   Manager   │  │    Engine       │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
│         └─────────────────┴─────────────────┴────────────────┘           │
│                                    │                                      │
│                           Display Interface                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                    │                                      │
│                              ┌─────▼─────┐                               │
│                              │  TUI API  │                               │
│                              │ (tui.hpp) │                               │
│                              └─────┬─────┘                               │
│                                    │                                      │
│    ┌───────────────────────────────┼───────────────────────────────┐     │
│    │                               │                               │     │
│    ▼                               ▼                               ▼     │
│ ┌──────────────┐           ┌───────────────┐           ┌──────────────┐ │
│ │    Input     │           │     Grid      │           │   Renderer   │ │
│ │   System     │           │    System     │           │    System    │ │
│ └──────┬───────┘           └───────┬───────┘           └──────┬───────┘ │
│        │                           │                          │         │
│        ▼                           ▼                          ▼         │
│ ┌──────────────┐           ┌───────────────┐           ┌──────────────┐ │
│ │ Input Parser │           │ Double Buffer │           │ Diff Engine  │ │
│ │  (termkey)   │           │    Grid       │           │              │ │
│ └──────┬───────┘           └───────────────┘           └──────┬───────┘ │
│        │                                                      │         │
└────────┼──────────────────────────────────────────────────────┼─────────┘
         │                                                      │
         ▼                                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Terminal Backend                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │   Unix Backend   │  │  Windows Backend │  │   macOS Backend      │   │
│  │  (POSIX + VT)    │  │  (VT + ConAPI)   │  │   (POSIX + VT)       │   │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────┬───────────┘   │
│           │                     │                       │               │
│           ▼                     ▼                       ▼               │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                      Event Loop (libuv)                          │   │
│  │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │   │
│  │  │TTY Read │  │TTY Write │  │ Signals  │  │ Timers (esc seq)  │  │   │
│  │  └─────────┘  └──────────┘  └──────────┘  └───────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                   Capabilities Provider                          │   │
│  │  ┌─────────────┐  ┌───────────────┐  ┌─────────────────────────┐ │   │
│  │  │  unibilium  │  │  Built-in DB  │  │  Runtime Query (DA1)   │ │   │
│  │  └─────────────┘  └───────────────┘  └─────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Design

### 1. TUI API (`src/tui/tui.hpp`)

Public interface for the TUI system.

```cpp
namespace emacs::tui {

class TUI {
public:
    static auto create() -> std::unique_ptr<TUI>;
    
    auto init() -> Result<void>;
    auto shutdown() -> void;
    
    auto run_event_loop() -> void;
    auto stop_event_loop() -> void;
    
    auto get_size() -> TerminalSize;
    auto set_cursor(CursorPosition pos) -> void;
    auto set_cursor_visible(bool visible) -> void;
    
    auto render(const Grid& grid) -> void;
    auto flush() -> void;
    
    auto read_input() -> std::optional<InputEvent>;
    auto peek_input() -> std::optional<InputEvent>;
    
    auto capabilities() -> const Capabilities&;
    
    using ResizeCallback = std::function<void(TerminalSize)>;
    auto on_resize(ResizeCallback cb) -> void;
    
private:
    std::unique_ptr<Backend> backend_;
    std::unique_ptr<InputParser> input_parser_;
    Grid grid_;
    Renderer renderer_;
};

} // namespace emacs::tui
```

### 2. Grid System (`src/tui/grid.hpp`)

Double-buffered cell grid with dirty region tracking.

```cpp
namespace emacs::tui {

struct Cell {
    char32_t codepoint = U' ';
    uint8_t width = 1;
    Attributes attrs{};
    
    auto operator==(const Cell&) const -> bool = default;
};

struct Attributes {
    Color fg = Color::Default;
    Color bg = Color::Default;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool reverse = false;
    bool strikethrough = false;
    
    auto operator==(const Attributes&) const -> bool = default;
};

class Grid {
public:
    Grid(int width, int height);
    
    auto resize(int width, int height) -> void;
    auto width() const -> int;
    auto height() const -> int;
    
    auto set_cell(int row, int col, Cell cell) -> void;
    auto get_cell(int row, int col) const -> const Cell&;
    
    auto clear() -> void;
    auto clear_row(int row) -> void;
    auto clear_region(int top, int left, int bottom, int right) -> void;
    
    auto swap_buffers() -> void;
    auto get_dirty_regions() const -> std::vector<Rect>;
    auto mark_all_dirty() -> void;
    
private:
    std::vector<std::vector<Cell>> front_buffer_;
    std::vector<std::vector<Cell>> back_buffer_;
    std::vector<bool> dirty_rows_;
    int width_;
    int height_;
};

} // namespace emacs::tui
```

### 3. Input System (`src/tui/input.hpp`)

Input event parsing with escape sequence handling.

```cpp
namespace emacs::tui {

enum class KeyType {
    Unicode,
    Function,
    Special,
    Mouse,
    Paste,
    Focus
};

enum class SpecialKey {
    Escape, Enter, Tab, Backspace, Delete,
    Up, Down, Left, Right,
    Home, End, PageUp, PageDown,
    Insert, F1, F2, /* ... */ F12
};

struct Modifiers {
    bool ctrl = false;
    bool alt = false;
    bool shift = false;
    bool super = false;
    
    auto operator==(const Modifiers&) const -> bool = default;
};

struct KeyEvent {
    KeyType type;
    std::variant<char32_t, SpecialKey> key;
    Modifiers modifiers;
};

struct MouseEvent {
    enum class Button { Left, Middle, Right, ScrollUp, ScrollDown, None };
    enum class Action { Press, Release, Move, Drag };
    
    Button button;
    Action action;
    int row;
    int col;
    Modifiers modifiers;
};

struct PasteEvent {
    std::string content;
};

struct FocusEvent {
    bool focused;
};

using InputEvent = std::variant<KeyEvent, MouseEvent, PasteEvent, FocusEvent>;

class InputParser {
public:
    explicit InputParser(std::chrono::milliseconds escape_timeout = 100ms);
    
    auto feed(std::span<const uint8_t> data) -> void;
    auto poll() -> std::optional<InputEvent>;
    auto timeout_elapsed() -> bool;
    
private:
    std::vector<uint8_t> buffer_;
    std::chrono::milliseconds escape_timeout_;
    std::chrono::steady_clock::time_point last_input_;
    
    auto parse_escape_sequence() -> std::optional<InputEvent>;
    auto parse_csi_sequence() -> std::optional<InputEvent>;
    auto parse_mouse_event() -> std::optional<MouseEvent>;
    auto parse_utf8() -> std::optional<char32_t>;
};

} // namespace emacs::tui
```

### 4. Terminal Backend (`src/tui/backend.hpp`)

Platform-specific terminal operations.

```cpp
namespace emacs::tui {

template<typename T>
concept TerminalBackend = requires(T t, const Grid& grid) {
    { t.init() } -> std::same_as<Result<void>>;
    { t.shutdown() } -> std::same_as<void>;
    { t.read(std::declval<std::span<uint8_t>>()) } -> std::same_as<ssize_t>;
    { t.write(std::declval<std::span<const uint8_t>>()) } -> std::same_as<ssize_t>;
    { t.flush() } -> std::same_as<void>;
    { t.get_size() } -> std::same_as<TerminalSize>;
    { t.capabilities() } -> std::same_as<const Capabilities&>;
};

class UnixBackend {
public:
    auto init() -> Result<void>;
    auto shutdown() -> void;
    auto read(std::span<uint8_t> buffer) -> ssize_t;
    auto write(std::span<const uint8_t> data) -> ssize_t;
    auto flush() -> void;
    auto get_size() -> TerminalSize;
    auto capabilities() -> const Capabilities&;
    
private:
    int tty_fd_ = -1;
    struct termios original_termios_{};
    Capabilities caps_;
    std::vector<uint8_t> write_buffer_;
};

class WindowsBackend {
public:
    auto init() -> Result<void>;
    auto shutdown() -> void;
    auto read(std::span<uint8_t> buffer) -> ssize_t;
    auto write(std::span<const uint8_t> data) -> ssize_t;
    auto flush() -> void;
    auto get_size() -> TerminalSize;
    auto capabilities() -> const Capabilities&;
    
private:
    HANDLE input_handle_ = INVALID_HANDLE_VALUE;
    HANDLE output_handle_ = INVALID_HANDLE_VALUE;
    DWORD original_input_mode_ = 0;
    DWORD original_output_mode_ = 0;
    Capabilities caps_;
    bool vt_supported_ = false;
};

} // namespace emacs::tui
```

### 5. Capabilities Provider (`src/tui/capabilities.hpp`)

Terminal capability detection and management.

```cpp
namespace emacs::tui {

struct Capabilities {
    int max_colors = 8;
    bool true_color = false;
    bool bce = false;
    bool cursor_shape = false;
    bool mouse_sgr = false;
    bool mouse_urxvt = false;
    bool bracketed_paste = false;
    bool focus_events = false;
    bool title = false;
    bool strikethrough = false;
    bool underline_style = false;
    
    std::string_view enter_ca;
    std::string_view exit_ca;
    std::string_view enter_keypad;
    std::string_view exit_keypad;
    std::string_view show_cursor;
    std::string_view hide_cursor;
    std::string_view clear_screen;
    std::string_view set_cursor;
    std::string_view set_attrs;
    std::string_view reset_attrs;
    std::string_view set_fg;
    std::string_view set_bg;
};

class CapabilitiesProvider {
public:
    static auto from_env() -> Capabilities;
    static auto from_terminfo(std::string_view term) -> std::optional<Capabilities>;
    static auto builtin(std::string_view term) -> Capabilities;
    static auto query_terminal() -> Capabilities;
    
private:
    static auto detect_true_color() -> bool;
    static auto detect_cursor_shape() -> bool;
};

} // namespace emacs::tui
```

### 6. Renderer (`src/tui/renderer.hpp`)

Diff-based screen rendering.

```cpp
namespace emacs::tui {

class Renderer {
public:
    explicit Renderer(Backend& backend);
    
    auto render(const Grid& grid) -> void;
    auto full_refresh(const Grid& grid) -> void;
    auto flush() -> void;
    
    auto set_cursor(CursorPosition pos) -> void;
    auto set_cursor_visible(bool visible) -> void;
    
private:
    Backend& backend_;
    std::string output_buffer_;
    CursorPosition cursor_{0, 0};
    bool cursor_visible_ = true;
    Attributes current_attrs_{};
    
    auto move_cursor(int row, int col) -> void;
    auto set_attributes(const Attributes& attrs) -> void;
    auto emit_cell(const Cell& cell) -> void;
    auto render_region(const Grid& grid, const Rect& region) -> void;
};

} // namespace emacs::tui
```

---

## Windows Implementation Details

### VT Sequence Support Detection

```cpp
auto WindowsBackend::init() -> Result<void> {
    input_handle_ = GetStdHandle(STD_INPUT_HANDLE);
    output_handle_ = GetStdHandle(STD_OUTPUT_HANDLE);
    
    if (input_handle_ == INVALID_HANDLE_VALUE || 
        output_handle_ == INVALID_HANDLE_VALUE) {
        return std::unexpected(std::error_code{});
    }
    
    GetConsoleMode(input_handle_, &original_input_mode_);
    GetConsoleMode(output_handle_, &original_output_mode_);
    
    DWORD input_mode = ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT;
    DWORD output_mode = ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT;
    
    if (SetConsoleMode(output_handle_, output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)) {
        vt_supported_ = true;
        input_mode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
    }
    
    SetConsoleMode(input_handle_, input_mode);
    
    caps_ = vt_supported_ 
        ? CapabilitiesProvider::builtin("vtpcon")
        : CapabilitiesProvider::builtin("win32con");
    
    return {};
}
```

### Fallback for Legacy Windows Console

```cpp
auto WindowsBackend::write_legacy(const Cell& cell, int row, int col) -> void {
    COORD pos{static_cast<SHORT>(col), static_cast<SHORT>(row)};
    SetConsoleCursorPosition(output_handle_, pos);
    
    WORD attrs = 0;
    if (cell.attrs.bold) attrs |= FOREGROUND_INTENSITY;
    if (cell.attrs.reverse) {
        attrs |= COMMON_LVB_REVERSE_VIDEO;
    }
    
    attrs |= fg_to_windows_attr(cell.attrs.fg);
    attrs |= bg_to_windows_attr(cell.attrs.bg);
    
    SetConsoleTextAttribute(output_handle_, attrs);
    
    char utf8[4];
    int len = encode_utf8(cell.codepoint, utf8);
    DWORD written;
    WriteConsoleA(output_handle_, utf8, len, &written, nullptr);
}
```

---

## Event Loop Integration

Using libuv for cross-platform async I/O:

```cpp
class EventLoop {
public:
    auto init() -> Result<void> {
        uv_loop_init(&loop_);
        uv_tty_init(&loop_, &tty_, 0, 1);
        uv_tty_set_mode(&tty_, UV_TTY_MODE_RAW);
        
        uv_signal_init(&loop_, &sigwinch_);
        uv_signal_start(&sigwinch_, on_resize, SIGWINCH);
        
        uv_timer_init(&loop_, &escape_timer_);
        
        return {};
    }
    
    auto run() -> void {
        uv_run(&loop_, UV_RUN_DEFAULT);
    }
    
    auto stop() -> void {
        uv_stop(&loop_);
    }
    
    auto start_read(ReadCallback cb) -> void {
        read_callback_ = std::move(cb);
        uv_read_start(
            reinterpret_cast<uv_stream_t*>(&tty_),
            alloc_buffer,
            on_read
        );
    }
    
private:
    uv_loop_t loop_{};
    uv_tty_t tty_{};
    uv_signal_t sigwinch_{};
    uv_timer_t escape_timer_{};
    ReadCallback read_callback_;
};
```

---

## Built-in Terminal Database

For environments without terminfo, we provide built-in definitions:

```cpp
namespace emacs::tui::builtin_terms {

inline constexpr Capabilities xterm_256color = {
    .max_colors = 256,
    .true_color = false,
    .bce = true,
    .cursor_shape = true,
    .mouse_sgr = true,
    .bracketed_paste = true,
    .focus_events = true,
    .title = true,
    .enter_ca = "\x1b[?1049h",
    .exit_ca = "\x1b[?1049l",
    .enter_keypad = "\x1b[?1h\x1b=",
    .exit_keypad = "\x1b[?1l\x1b>",
    .show_cursor = "\x1b[?25h",
    .hide_cursor = "\x1b[?25l",
    .clear_screen = "\x1b[H\x1b[2J",
    .set_cursor = "\x1b[{};{}H",
    .reset_attrs = "\x1b[0m",
};

inline constexpr Capabilities vtpcon = {
    .max_colors = 256,
    .true_color = true,
    .bce = false,
    .cursor_shape = true,
    .mouse_sgr = true,
    .bracketed_paste = true,
    .focus_events = false,
    .title = true,
    // ... same sequences as xterm
};

inline constexpr Capabilities win32con = {
    .max_colors = 16,
    .true_color = false,
    .bce = false,
    .cursor_shape = false,
    .mouse_sgr = false,
    .bracketed_paste = false,
    .focus_events = false,
    .title = true,
    // Legacy console - no VT sequences
};

auto get_builtin(std::string_view term) -> const Capabilities* {
    if (term.starts_with("xterm")) return &xterm_256color;
    if (term == "vtpcon") return &vtpcon;
    if (term == "win32con") return &win32con;
    // ... more terminals
    return nullptr;
}

} // namespace emacs::tui::builtin_terms
```

---

## File Structure

```
src/tui/
├── tui.hpp              # Public API
├── tui.cpp              # TUI implementation
├── grid.hpp             # Grid system
├── grid.cpp
├── input.hpp            # Input events and parser
├── input.cpp
├── backend.hpp          # Backend concept
├── backend_unix.cpp     # Unix/POSIX backend
├── backend_windows.cpp  # Windows backend
├── capabilities.hpp     # Terminal capabilities
├── capabilities.cpp
├── builtin_terms.hpp    # Built-in terminal database
├── renderer.hpp         # Screen renderer
├── renderer.cpp
├── event_loop.hpp       # libuv event loop wrapper
├── event_loop.cpp
└── color.hpp            # Color types and conversion
```

---

## Testing Strategy

### Unit Tests

```cpp
TEST_CASE("Grid double buffering") {
    Grid grid(80, 24);
    
    grid.set_cell(0, 0, {.codepoint = U'A'});
    REQUIRE(grid.get_dirty_regions().size() > 0);
    
    grid.swap_buffers();
    REQUIRE(grid.get_dirty_regions().empty());
    
    grid.set_cell(0, 1, {.codepoint = U'B'});
    auto regions = grid.get_dirty_regions();
    REQUIRE(regions.size() == 1);
}

TEST_CASE("Input parser escape sequence") {
    InputParser parser;
    
    parser.feed(std::span{"\x1b[A", 3});
    auto event = parser.poll();
    
    REQUIRE(event.has_value());
    auto* key = std::get_if<KeyEvent>(&*event);
    REQUIRE(key != nullptr);
    REQUIRE(key->key == SpecialKey::Up);
}

TEST_CASE("Windows VT detection") {
    WindowsBackend backend;
    auto result = backend.init();
    
    REQUIRE(result.has_value());
    
    auto& caps = backend.capabilities();
    if (caps.max_colors > 16) {
        REQUIRE(caps.true_color || caps.max_colors >= 256);
    }
}
```

### Integration Tests

```cpp
TEST_CASE("TUI render and input") {
    auto tui = TUI::create();
    REQUIRE(tui->init().has_value());
    
    Grid grid(tui->get_size().width, tui->get_size().height);
    grid.set_cell(0, 0, {.codepoint = U'H'});
    grid.set_cell(0, 1, {.codepoint = U'i'});
    
    tui->render(grid);
    tui->flush();
    
    tui->shutdown();
}
```

---

## Migration Path

### Phase 1: Core Infrastructure

1. Implement Grid class
2. Implement Cell and Attributes
3. Implement basic Capabilities
4. Unit tests for all

### Phase 2: Event Loop

1. Integrate libuv
2. Implement basic read/write
3. Signal handling (SIGWINCH)
4. Timer for escape sequences

### Phase 3: Input Parser

1. UTF-8 parsing
2. Basic escape sequences
3. CSI sequences (arrows, function keys)
4. Mouse events (SGR mode)
5. Bracketed paste

### Phase 4: Backends

1. Unix backend (complete)
2. Windows backend (VT mode)
3. Windows backend (legacy fallback)
4. Capability detection

### Phase 5: Renderer

1. Basic rendering
2. Diff-based updates
3. Cursor management
4. Performance optimization

### Phase 6: Integration

1. Connect to Emacs display system
2. Replace termbox2 calls
3. Test on all platforms
4. Performance benchmarks

---

## Dependencies

| Library | Purpose | vcpkg |
|---------|---------|-------|
| libuv | Event loop, async I/O | ✅ |
| unibilium | Terminfo parsing | ✅ (optional) |

---

## Performance Considerations

1. **Output buffering** - Batch writes to reduce syscalls
2. **Dirty region tracking** - Only render changed cells
3. **Escape sequence caching** - Pre-compute common sequences
4. **Memory pooling** - Reuse Cell allocations
5. **Unicode caching** - Cache wcwidth results

---

## References

1. [Neovim TUI source](https://github.com/neovim/neovim/tree/master/src/nvim/tui)
2. [libuv documentation](https://docs.libuv.org/)
3. [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
4. [Windows Console VT](https://docs.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences)
5. [terminfo manual](https://man7.org/linux/man-pages/man5/terminfo.5.html)

---

**Document History:**
- 2025-02-03: v1.0 - Initial architecture design
