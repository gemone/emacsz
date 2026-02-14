# Phase 3: Terminal Abstraction

**Duration:** Week 9-12
**Dependencies:** Phase 2 completion
**Target:** Week 12 (2026-03-22)

---

## Objectives

1. **Modernize terminal subsystem with C++20 concepts**
2. **Improve Windows TUI implementation** (critical improvement)
3. **Replace termcap with C++ alternatives**
4. **Create cross-platform terminal backends**
5. **Establish terminal abstraction layer for future GUI work**

---

## Overview

This phase modernizes the Emacs terminal subsystem, the foundation for all display operations. It focuses on:

- **Terminal Abstraction:** C++20 concept-based terminal interface
- **Platform Backends:** Separate implementations for X11, Windows, macOS, Haiku, Android
- **TUI Improvements:** Modern Windows console support (inspired by Neovim)
- **Modernization:** Replace termcap with C++20 string-based terminal database

### Why This Phase Third

Before migrating complex subsystems (Lisp interpreter, GUI), we need:
1. A clean terminal abstraction that all display code depends on
2. Platform-specific terminal backends that work reliably
3. Improved Windows TUI (historically weak point in Emacs)
4. Foundation for GUI subsystems in Phase 5

### Success Criteria

- [ ] Terminal interface defined using C++20 concepts
- [ ] Platform-specific backends implemented (X11, Windows, macOS, Haiku)
- [ ] Windows TUI is usable (not just functional)
- [ ] Terminal operations work on all platforms
- [ ] TUI tests pass on Linux, macOS, Windows
- [ ] Performance comparable to C implementation
- [ ] No memory leaks detected
- [ ] Termcap replaced with C++ alternatives

---

## Task 3.1: Define C++20 Concept-Based Terminal Interface

### Objective

Create a modern, type-safe terminal interface using C++20 concepts that abstracts platform differences.

### Requirements

- Use C++20 `concept` to define terminal backend requirements
- Provide clean interface for terminal operations
- Support all existing Emacs terminal features
- Enable compile-time platform selection
- Maintain compatibility with existing C code during transition

### Design

```cpp
// src/terminal_concept.hpp

#include <concepts>
#include <string>
#include <string_view>
#include <span>
#include <memory>

namespace emacs {

/**
 * Terminal glyph structure
 *
 * Represents a single character cell in terminal display.
 */
struct TerminalGlyph {
    char32_t codepoint;      // Unicode codepoint
    uint32_t face_id;       // Font face index
    uint8_t  background;     // Background color
    uint8_t  foreground;     // Foreground color
    bool     wide;           // Wide character (CJK)
    bool     padding;        // Padding for wide chars
};

/**
 * Terminal cursor position
 */
struct CursorPosition {
    int row;
    int col;
};

/**
 * Terminal rectangle
 */
struct TerminalRect {
    int top;
    int left;
    int bottom;
    int right;
};

/**
 * C++20 concept for terminal backends
 *
 * Defines the interface that all terminal implementations must satisfy.
 * This enables compile-time checking and platform-specific optimizations.
 */
template<typename T>
concept TerminalBackend = requires(T terminal, TerminalGlyph glyph,
                                 CursorPosition pos, TerminalRect rect,
                                 std::string_view text) {
    // Initialization
    { terminal.init() } -> std::same_as<bool>;
    { terminal.cleanup() } -> std::same_as<void>;

    // Output operations
    { terminal.write_glyphs(std::span<TerminalGlyph>{}) } -> std::same_as<void>;
    { terminal.clear_to_end(pos) } -> std::same_as<void>;
    { terminal.clear_frame() } -> std::same_as<void>;
    { terminal.clear_end_of_line(pos) } -> std::same_as<void>;

    // Cursor operations
    { terminal.set_cursor_position(pos) } -> std::same_as<void>;
    { terminal.get_cursor_position() } -> std::same_as<CursorPosition>;

    // Line operations
    { terminal.insert_glyphs(pos, std::span<TerminalGlyph>{}) } -> std::same_as<void>;
    { terminal.delete_glyphs(pos, 0) } -> std::same_as<void>;
    { terminal.insert_lines(pos, 0) } -> std::same_as<void>;
    { terminal.delete_lines(pos, 0) } -> std::same_as<void>;

    // Terminal capabilities
    { terminal.supports_colors() } -> std::same_as<bool>;
    { terminal.supports_blinking_cursor() } -> std::same_as<bool>;
    { terminal.get_terminal_size() } -> std::same_as<std::pair<int, int>>;

    // Input handling
    { terminal.read_input() } -> std::same_as<int>;
    { terminal.set_raw_mode(bool) } -> std::same_as<void>;
};

/**
 * Terminal color representation
 */
struct TerminalColor {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
};

/**
 * Terminal face definition
 *
 * Combines foreground, background, and font attributes.
 */
struct TerminalFace {
    TerminalColor foreground;
    TerminalColor background;
    bool bold;
    bool italic;
    bool underline;
    bool inverse;
};

/**
 * Generic terminal interface
 *
 * Template class that provides terminal operations using
 * the specified backend. Uses C++20 concepts to ensure
 * backend compatibility.
 */
template<Backend>
requires TerminalBackend<Backend>
class Terminal {
private:
    Backend backend_;

public:
    Terminal() = default;
    ~Terminal() = default;

    // Prevent copying
    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;

    // Allow moving
    Terminal(Terminal&&) noexcept = default;
    Terminal& operator=(Terminal&&) noexcept = default;

    /**
     * Initialize terminal
     *
     * @return true on success, false on failure
     */
    [[nodiscard]] bool init() noexcept {
        return backend_.init();
    }

    /**
     * Cleanup terminal resources
     */
    void cleanup() noexcept {
        backend_.cleanup();
    }

    /**
     * Write glyphs to terminal
     *
     * @param glyphs Span of glyphs to write
     */
    void write_glyphs(std::span<TerminalGlyph> glyphs) noexcept {
        backend_.write_glyphs(glyphs);
    }

    /**
     * Clear from cursor position to end of screen
     */
    void clear_to_end(CursorPosition pos) noexcept {
        backend_.clear_to_end(pos);
    }

    /**
     * Clear entire frame
     */
    void clear_frame() noexcept {
        backend_.clear_frame();
    }

    /**
     * Clear to end of line
     */
    void clear_end_of_line(CursorPosition pos) noexcept {
        backend_.clear_end_of_line(pos);
    }

    /**
     * Set cursor position
     */
    void set_cursor_position(CursorPosition pos) noexcept {
        backend_.set_cursor_position(pos);
    }

    /**
     * Get current cursor position
     */
    [[nodiscard]] CursorPosition get_cursor_position() const noexcept {
        return backend_.get_cursor_position();
    }

    /**
     * Insert glyphs at cursor position
     */
    void insert_glyphs(CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept {
        backend_.insert_glyphs(pos, glyphs);
    }

    /**
     * Delete glyphs at cursor position
     *
     * @param pos Cursor position
     * @param n Number of glyphs to delete
     */
    void delete_glyphs(CursorPosition pos, int n) noexcept {
        backend_.delete_glyphs(pos, n);
    }

    /**
     * Insert lines
     */
    void insert_lines(CursorPosition pos, int n) noexcept {
        backend_.insert_lines(pos, n);
    }

    /**
     * Delete lines
     */
    void delete_lines(CursorPosition pos, int n) noexcept {
        backend_.delete_lines(pos, n);
    }

    /**
     * Check if terminal supports colors
     */
    [[nodiscard]] bool supports_colors() const noexcept {
        return backend_.supports_colors();
    }

    /**
     * Check if terminal supports blinking cursor
     */
    [[nodiscard]] bool supports_blinking_cursor() const noexcept {
        return backend_.supports_blinking_cursor();
    }

    /**
     * Get terminal size (rows, cols)
     */
    [[nodiscard]] std::pair<int, int> get_terminal_size() const noexcept {
        return backend_.get_terminal_size();
    }

    /**
     * Read input event
     */
    [[nodiscard]] int read_input() noexcept {
        return backend_.read_input();
    }

    /**
     * Set raw mode (pass-through input)
     */
    void set_raw_mode(bool raw) noexcept {
        backend_.set_raw_mode(raw);
    }
};

} // namespace emacs
```

### Testing Strategy

```cpp
// test/test_terminal_concept.cpp

#include <cassert>
#include "terminal_concept.hpp"

// Mock backend for testing
struct MockTerminalBackend {
    bool initialized = false;

    bool init() noexcept { initialized = true; return true; }
    void cleanup() noexcept { initialized = false; }
    void write_glyphs(std::span<emacs::TerminalGlyph>) noexcept {}
    void clear_to_end(emacs::CursorPosition) noexcept {}
    void clear_frame() noexcept {}
    void clear_end_of_line(emacs::CursorPosition) noexcept {}
    void set_cursor_position(emacs::CursorPosition) noexcept {}
    emacs::CursorPosition get_cursor_position() const noexcept { return {0, 0}; }
    void insert_glyphs(emacs::CursorPosition, std::span<emacs::TerminalGlyph>) noexcept {}
    void delete_glyphs(emacs::CursorPosition, int) noexcept {}
    void insert_lines(emacs::CursorPosition, int) noexcept {}
    void delete_lines(emacs::CursorPosition, int) noexcept {}
    bool supports_colors() const noexcept { return true; }
    bool supports_blinking_cursor() const noexcept { return false; }
    std::pair<int, int> get_terminal_size() const noexcept { return {24, 80}; }
    int read_input() noexcept { return 0; }
    void set_raw_mode(bool) noexcept {}
};

void test_terminal_concept() {
    // Test that mock backend satisfies TerminalBackend concept
    static_assert(emacs::TerminalBackend<MockTerminalBackend>);

    // Test Terminal template
    emacs::Terminal<MockTerminalBackend> term;

    assert(term.init());
    assert(term.get_terminal_size() == std::make_pair(24, 80));
    assert(term.supports_colors());

    term.cleanup();
}
```

---

## Task 3.2: Migrate src/termhooks.h to C++

### Objective

Convert terminal hooks header to modern C++ with typesafe enums and concepts.

### Constraints

- Maintain binary compatibility with existing C code during transition
- Preserve all terminal hook function signatures
- Use `extern "C"` for compatibility bridge
- Gradually replace C types with C++ equivalents

### Design

```cpp
// src/termhooks.hpp

#pragma once

#include <cstdint>
#include <concepts>
#include <string>
#include <variant>

#include "lisp.h"

namespace emacs {

// Forward declarations
struct frame;
struct glyph;
struct input_event;

/**
 * Terminal output method (C++20 enum class)
 *
 * Replaces C enum output_method from termhooks.h
 */
enum class OutputMethod : uint8_t {
    Initial,
    Termcap,
    XWindow,
    MSDOSRaw,
    W32,
    NextStep,
    PGTK,
    Haiku,
    Android
};

/**
 * Scroll bar part (C++20 enum class)
 *
 * Replaces C enum scroll_bar_part
 */
enum class ScrollBarPart : uint8_t {
    Nowhere,
    AboveHandle,
    Handle,
    BelowHandle,
    UpArrow,
    DownArrow,
    ToTop,
    ToBottom,
    EndScroll,
    MoveRatio,
    BeforeHandle,
    HorizontalHandle,
    AfterHandle,
    LeftArrow,
    RightArrow,
   ToLeftmost,
    ToRightmost
};

/**
 * Event kind (C++20 enum class)
 *
 * Replaces C enum event_kind
 */
enum class EventKind : uint8_t {
    NoEvent,
    ASCIIKeystroke,
    MultibyteCharKeystroke,
    NonAsciiKeystroke,
    TimerEvent,
    MouseClick,
    MouseMovement,
    MenuBarActivate,
    MenuBarSelect,
    ModeLineClick,
    SwitchFrame,
    DeleteWindow,
    IconifyFrame,
    DeiconifyFrame,
    WindowChange,
    SettingsChanged,
    FocusIn,
    FocusOut,
    SaveSession,
    DragNDrop,
    UserSignal,
    LanguageChange,
    PanelUpdate,
    PanelLayout,
    IconifiedFrame,
    DragNDropFile,
    AppActivated,
    AppDeactivated,
    ScrollBarClick,
    ScrollBarDrag,
    ScrollBarValueChange,
    SelectionNotify,
    SelectionRequest,
    SelectionClearEvent,
    SelectionClear,
    HelpEvent,
    Pollevent,
    ConfigChangedEvent,
    FileSelected,
    FontChange,
    KeyPress,
    KeyRelease
};

/**
 * Terminal output hooks
 *
 * Replaces C struct terminal from termhooks.h
 */
struct TerminalHooks {
    // Output hooks
    void (*write_glyphs)(struct frame*, struct glyph*, int);
    void (*cursor_to)(struct frame*, int, int);
    void (*clear_to_end)(struct frame*);
    void (*clear_frame)(struct frame*);
    void (*clear_end_of_line)(struct frame*, int);

    // Line operations
    void (*ins_del_lines)(struct frame*, int, int);
    void (*insert_glyphs)(struct frame*, struct glyph*, int, int);
    void (*delete_glyphs)(struct frame*, int);

    // Terminal capabilities
    bool (*supports_colors)(struct frame*);
    bool (*supports_blinking_cursor)(struct frame*);

    // Terminal size
    void (*set_terminal_size)(struct frame*, int, int);

    // Input handling
    int (*read_input)(struct frame*, struct input_event*);

    // Output method
    OutputMethod output_method;

    // Platform-specific data
    void* platform_data;
};

/**
 * Terminal frame
 *
 * Combines terminal hooks with frame-specific state
 */
struct TerminalFrame {
    struct frame* frame;
    TerminalHooks hooks;

    // Terminal dimensions
    int rows;
    int cols;

    // Terminal state
    bool initialized;
    bool raw_mode;

    // Cursor position
    int cursor_row;
    int cursor_col;
};

/**
 * C++20 concept for terminal hook compatibility
 *
 * Ensures that a terminal backend provides all required hooks
 */
template<typename T>
concept TerminalHookProvider = requires(T hooks, struct frame* f) {
    { hooks.write_glyphs } -> std::convertible_to<void(*)(struct frame*, struct glyph*, int)>;
    { hooks.cursor_to } -> std::convertible_to<void(*)(struct frame*, int, int)>;
    { hooks.clear_to_end } -> std::convertible_to<void(*)(struct frame*)>;
    { hooks.clear_frame } -> std::convertible_to<void(*)(struct frame*)>;
};

} // namespace emacs

// Extern "C" compatibility bridge
extern "C" {

// Convert C++ OutputMethod to C enum
emacs::OutputMethod cpp_to_c_output_method(int c_enum);
int c_to_cpp_output_method(emacs::OutputMethod cpp_enum);

// Convert C++ TerminalHooks to C struct
emacs::TerminalHooks* create_terminal_hooks(emacs::OutputMethod method);
void destroy_terminal_hooks(emacs::TerminalHooks* hooks);

} // extern "C"
```

---

## Task 3.3: Implement X11 Terminal Backend

### Objective

Create modern C++20 backend for X11 terminals (Linux/Unix).

### Files

- **Source:** `src/xterm.cpp` (migrated from `src/xterm.c`)
- **Header:** `src/xterm.hpp` (new C++20 header)
- **Dependencies:** X11, Xft, fontconfig

### Design

```cpp
// src/xterm.hpp

#pragma once

#include "terminal_concept.hpp"
#include "termhooks.hpp"

#include <X11/Xlib.h>
#include <X11/Xft/Xft.h>

namespace emacs {

/**
 * X11-specific terminal backend
 *
 * Provides terminal operations using X11 and Xft libraries.
 */
class X11TerminalBackend {
private:
    Display* display_;
    Window window_;
    GC gc_;
    XftDraw* xft_draw_;
    Colormap colormap_;

    int width_;
    int height_;
    bool initialized_;

public:
    X11TerminalBackend() noexcept;
    ~X11TerminalBackend() noexcept;

    // Prevent copying
    X11TerminalBackend(const X11TerminalBackend&) = delete;
    X11TerminalBackend& operator=(const X11TerminalBackend&) = delete;

    // Initialize X11 terminal
    [[nodiscard]] bool init() noexcept override;

    // Cleanup X11 resources
    void cleanup() noexcept override;

    // Terminal operations
    void write_glyphs(std::span<TerminalGlyph> glyphs) noexcept override;
    void clear_to_end(CursorPosition pos) noexcept override;
    void clear_frame() noexcept override;
    void clear_end_of_line(CursorPosition pos) noexcept override;
    void set_cursor_position(CursorPosition pos) noexcept override;
    CursorPosition get_cursor_position() const noexcept override;
    void insert_glyphs(CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept override;
    void delete_glyphs(CursorPosition pos, int n) noexcept override;
    void insert_lines(CursorPosition pos, int n) noexcept override;
    void delete_lines(CursorPosition pos, int n) noexcept override;

    // Terminal capabilities
    bool supports_colors() const noexcept override;
    bool supports_blinking_cursor() const noexcept override;
    std::pair<int, int> get_terminal_size() const noexcept override;

    // Input handling
    int read_input() noexcept override;
    void set_raw_mode(bool raw) noexcept override;

private:
    /**
     * Initialize X11 display
     */
    [[nodiscard]] bool init_display() noexcept;

    /**
     * Initialize Xft font rendering
     */
    [[nodiscard]] bool init_xft() noexcept;

    /**
     * Handle X11 events
     */
    [[nodiscard]] int handle_x11_events() noexcept;
};

} // namespace emacs

// Static assertion that X11TerminalBackend satisfies TerminalBackend concept
static_assert(emacs::TerminalBackend<emacs::X11TerminalBackend>);
```

---

## Task 3.4: Implement Windows Terminal Backend (Critical)

### Objective

Create modern Windows console backend with proper TUI support.

**Critical Note:** This is a high-priority task. Current Emacs Windows TUI is barely usable. Neovim's TUI implementation should be studied for best practices.

### Files

- **Source:** `src/w32term.cpp` (migrated from `src/w32console.c`)
- **Header:** `src/w32term.hpp` (new C++20 header)
- **Dependencies:** Windows API, Console API 2.0

### Neovim Research Findings

Based on Neovim's TUI implementation:
1. Use Windows Console API 2.0 for VT100 emulation
2. Enable virtual terminal sequences for modern terminal features
3. Handle wide character rendering correctly (CJK support)
4. Implement proper input handling with UTF-8
5. Use double-buffering for smooth updates

### Design

```cpp
// src/w32term.hpp

#pragma once

#include "terminal_concept.hpp"
#include "termhooks.hpp"

#include <windows.h>

namespace emacs {

/**
 * Windows console terminal backend
 *
 * Provides modern Windows TUI support using Console API 2.0.
 * Implements VT100 emulation for cross-platform compatibility.
 */
class WindowsTerminalBackend {
private:
    HANDLE console_handle_;
    HANDLE input_handle_;
    CONSOLE_SCREEN_BUFFER_INFO buffer_info_;
    DWORD original_mode_;

    int width_;
    int height_;
    bool initialized_;
    bool raw_mode_;

    // Console API 2.0 support
    bool supports_vt100_;
    bool supports_truecolor_;

public:
    WindowsTerminalBackend() noexcept;
    ~WindowsTerminalBackend() noexcept;

    // Prevent copying
    WindowsTerminalBackend(const WindowsTerminalBackend&) = delete;
    WindowsTerminalBackend& operator=(const WindowsTerminalBackend&) = delete;

    // Initialize Windows console
    [[nodiscard]] bool init() noexcept override;

    // Cleanup console resources
    void cleanup() noexcept override;

    // Terminal operations
    void write_glyphs(std::span<TerminalGlyph> glyphs) noexcept override;
    void clear_to_end(CursorPosition pos) noexcept override;
    void clear_frame() noexcept override;
    void clear_end_of_line(CursorPosition pos) noexcept override;
    void set_cursor_position(CursorPosition pos) noexcept override;
    CursorPosition get_cursor_position() const noexcept override;
    void insert_glyphs(CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept override;
    void delete_glyphs(CursorPosition pos, int n) noexcept override;
    void insert_lines(CursorPosition pos, int n) noexcept override;
    void delete_lines(CursorPosition pos, int n) noexcept override;

    // Terminal capabilities
    bool supports_colors() const noexcept override;
    bool supports_blinking_cursor() const noexcept override;
    std::pair<int, int> get_terminal_size() const noexcept override;

    // Input handling
    int read_input() noexcept override;
    void set_raw_mode(bool raw) noexcept override;

private:
    /**
     * Enable VT100 emulation on Windows 10+
     */
    [[nodiscard]] bool enable_vt100() noexcept;

    /**
     * Enable true color support
     */
    [[nodiscard]] bool enable_truecolor() noexcept;

    /**
     * Write VT100 escape sequences
     */
    void write_vt_sequence(std::string_view sequence) noexcept;

    /**
     * Handle Windows console input events
     */
    [[nodiscard]] int handle_console_input() noexcept;

    /**
     * Convert Windows key event to Emacs key code
     */
    [[nodiscard]] int translate_key_event(KEY_EVENT_RECORD* event) noexcept;

    /**
     * Detect if running on Windows 10+
     */
    [[nodiscard]] bool is_windows_10_or_later() const noexcept;
};

} // namespace emacs

// Static assertion that WindowsTerminalBackend satisfies TerminalBackend concept
static_assert(emacs::TerminalBackend<emacs::WindowsTerminalBackend>);
```

### Windows Console API 2.0 Features

```cpp
// Enable VT100 emulation (Windows 10+)
DWORD mode = 0;
GetConsoleMode(console_handle_, &mode);
mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
mode |= DISABLE_NEWLINE_AUTO_RETURN;
SetConsoleMode(console_handle_, mode);

// Enable true color support (ANSI escape sequences)
// Example: \x1b[38;2;255;0;0m for bright red

// Wide character handling
WriteConsoleW(console_handle_, L"你好", 2, &written, nullptr);

// Double buffering (for smooth updates)
// Read into buffer, then write entire buffer at once
```

---

## Task 3.5: Implement macOS Terminal Backend

### Objective

Create modern macOS (NextStep) terminal backend.

**Note:** macOS terminal primarily uses X11 for TUI, so this may delegate to X11TerminalBackend.

### Files

- **Source:** `src/nsterm.cpp` (migrated from `src/nsterm.m`)
- **Header:** `src/nsterm.hpp` (new C++20 header)
- **Dependencies:** Cocoa, AppKit

### Design

```cpp
// src/nsterm.hpp

#pragma once

#include "terminal_concept.hpp"
#include "termhooks.hpp"

#ifdef __APPLE__
#include <Cocoa/Cocoa.h>
#endif

namespace emacs {

/**
 * macOS NextStep terminal backend
 *
 * Provides terminal operations on macOS using Cocoa framework.
 */
class NSTerminalBackend {
private:
    NSWindow* window_;
    NSTextView* text_view_;
    NSFont* default_font_;

    int width_;
    int height_;
    bool initialized_;

public:
    NSTerminalBackend() noexcept;
    ~NSTerminalBackend() noexcept;

    // Prevent copying
    NSTerminalBackend(const NSTerminalBackend&) = delete;
    NSTerminalBackend& operator=(const NSTerminalBackend&) = delete;

    // Initialize macOS terminal
    [[nodiscard]] bool init() noexcept override;

    // Cleanup Cocoa resources
    void cleanup() noexcept override;

    // Terminal operations (same interface as other backends)
    void write_glyphs(std::span<TerminalGlyph> glyphs) noexcept override;
    void clear_to_end(CursorPosition pos) noexcept override;
    void clear_frame() noexcept override;
    void clear_end_of_line(CursorPosition pos) noexcept override;
    void set_cursor_position(CursorPosition pos) noexcept override;
    CursorPosition get_cursor_position() const noexcept override;
    void insert_glyphs(CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept override;
    void delete_glyphs(CursorPosition pos, int n) noexcept override;
    void insert_lines(CursorPosition pos, int n) noexcept override;
    void delete_lines(CursorPosition pos, int n) noexcept override;

    // Terminal capabilities
    bool supports_colors() const noexcept override;
    bool supports_blinking_cursor() const noexcept override;
    std::pair<int, int> get_terminal_size() const noexcept override;

    // Input handling
    int read_input() noexcept override;
    void set_raw_mode(bool raw) noexcept override;
};

} // namespace emacs

// Static assertion that NSTerminalBackend satisfies TerminalBackend concept
static_assert(emacs::TerminalBackend<emacs::NSTerminalBackend>);
```

---

## Task 3.6: Replace termcap with C++ Terminal Database

### Objective

Replace termcap library with modern C++20 string-based terminal database.

### Why Replace termcap?

1. **Outdated:** termcap is ancient (1980s)
2. **Limited:** Poor Unicode support
3. **Platform-specific:** Hard to maintain across platforms
4. **Unnecessary:** Modern terminals support VT100/ANSI natively

### Alternative: VT100/ANSI Escape Sequences

```cpp
// src/terminal_database.hpp

#pragma once

#include <string>
#include <string_view>
#include <unordered_map>

namespace emacs {

/**
 * Terminal capabilities database
 *
 * Provides terminal capability strings without termcap.
 * Uses modern VT100/ANSI escape sequences.
 */
class TerminalDatabase {
public:
    /**
     * VT100 escape sequences
     *
     * Most modern terminals (xterm, iTerm2, Terminal.app, Windows 10+)
     * support VT100 escape sequences natively.
     */
    static constexpr std::string_view CLEAR_SCREEN = "\x1b[2J";
    static constexpr std::string_view CLEAR_TO_END = "\x1b[0J";
    static constexpr std::string_view CLEAR_LINE = "\x1b[K";
    static constexpr std::string_view RESET_CURSOR = "\x1b[H";
    static constexpr std::string_view MOVE_CURSOR = "\x1b[{};{}H";
    static constexpr std::string_view SAVE_CURSOR = "\x1b[s";
    static constexpr std::string_view RESTORE_CURSOR = "\x1b[u";

    static constexpr std::string_view RESET_ATTRIBUTES = "\x1b[0m";
    static constexpr std::string_view BOLD = "\x1b[1m";
    static constexpr std::string_view ITALIC = "\x1b[3m";
    static constexpr std::string_view UNDERLINE = "\x1b[4m";
    static constexpr std::string_view INVERSE = "\x1b[7m";

    static constexpr std::string_view COLOR_FOREGROUND = "\x1b[38;5;{}m";
    static constexpr std::string_view COLOR_BACKGROUND = "\x1b[48;5;{}m";
    static constexpr std::string_view COLOR_TRUECOLOR_FG = "\x1b[38;2;{};{};{}m";
    static constexpr std::string_view COLOR_TRUECOLOR_BG = "\x1b[48;2;{};{};{}m";

    static constexpr std::string_view SCROLL_UP = "\x1b[{}S";
    static constexpr std::string_view SCROLL_DOWN = "\x1b[{}T";
    static constexpr std::string_view INSERT_LINE = "\x1b[{}L";
    static constexpr std::string_view DELETE_LINE = "\x1b[{}M";

    static constexpr std::string_view ALT_SCREEN = "\x1b[?1049h";
    static constexpr std::string_view NORMAL_SCREEN = "\x1b[?1049l";

    static constexpr std::string_view HIDE_CURSOR = "\x1b[?25l";
    static constexpr std::string_view SHOW_CURSOR = "\x1b[?25h";

    /**
     * Terminal capability queries
     *
     * Use DA (Device Attributes) to query terminal capabilities
     */
    static constexpr std::string_view QUERY_PRIMARY_DA = "\x1b[c";
    static constexpr std::string_view QUERY_SECONDARY_DA = "\x1b[>c";

    /**
     * Format escape sequence with parameters
     *
     * @param template_ Template string with {} placeholders
     * @param args Arguments to substitute
     * @return Formatted escape sequence
     */
    template<typename... Args>
    [[nodiscard]] static std::string format_sequence(
        std::string_view template_,
        Args&&... args) {
        // Use C++20 std::format (once strings.hpp is re-enabled)
        // For now, simple string concatenation
        return format_sequence_impl(template_, std::forward<Args>(args)...);
    }

private:
    template<typename T>
    static std::string format_sequence_impl(std::string_view tmpl, T&& arg) {
        // Simple implementation: replace {} with arg
        size_t pos = tmpl.find("{}");
        if (pos == std::string_view::npos) {
            return std::string(tmpl);
        }
        std::string result;
        result.reserve(tmpl.size() + 32);
        result.append(tmpl.substr(0, pos));
        result.append(std::to_string(arg));
        result.append(tmpl.substr(pos + 2));
        return result;
    }
};

} // namespace emacs
```

### Example Usage

```cpp
// Clear screen
std::cout << TerminalDatabase::CLEAR_SCREEN;

// Move cursor to row 10, column 20
std::cout << TerminalDatabase::format_sequence(
    TerminalDatabase::MOVE_CURSOR, 10, 20);

// Set foreground color to bright red (truecolor)
std::cout << TerminalDatabase::format_sequence(
    TerminalDatabase::COLOR_TRUECOLOR_FG, 255, 0, 0);

// Reset attributes
std::cout << TerminalDatabase::RESET_ATTRIBUTES;
```

---

## Task 3.7: Migrate Display Update System

### Objective

Modernize display update mechanism in `src/dispnew.c`.

### Files

- **Source:** `src/dispnew.cpp` (migrated from `src/dispnew.c`)
- **Header:** `src/dispnew.hpp` (new C++20 header)

### Key Concepts

1. **Double Buffering:** Render to off-screen buffer, then swap
2. **Delta Updates:** Only update changed glyphs
3. **RAII:** Automatic buffer management
4. **C++20:** Use `std::vector` and smart pointers

### Design

```cpp
// src/dispnew.hpp

#pragma once

#include "terminal_concept.hpp"
#include <vector>
#include <memory>
#include <span>

namespace emacs {

/**
 * Display buffer
 *
 * Off-screen buffer for double buffering display updates.
 */
class DisplayBuffer {
private:
    std::vector<TerminalGlyph> buffer_;
    int width_;
    int height_;
    bool dirty_;

public:
    DisplayBuffer(int width, int height)
        : width_(width), height_(height), dirty_(false) {
        buffer_.resize(width_ * height_);
    }

    /**
     * Resize buffer
     */
    void resize(int width, int height) {
        buffer_.resize(width * height);
        width_ = width;
        height_ = height;
        dirty_ = true;
    }

    /**
     * Set glyph at position
     */
    void set_glyph(int row, int col, const TerminalGlyph& glyph) {
        if (row >= 0 && row < height_ && col >= 0 && col < width_) {
            buffer_[row * width_ + col] = glyph;
            dirty_ = true;
        }
    }

    /**
     * Get glyph at position
     */
    [[nodiscard]] TerminalGlyph get_glyph(int row, int col) const {
        if (row >= 0 && row < height_ && col >= 0 && col < width_) {
            return buffer_[row * width_ + col];
        }
        return TerminalGlyph{};
    }

    /**
     * Check if buffer is dirty (has changes)
     */
    [[nodiscard]] bool is_dirty() const noexcept { return dirty_; }

    /**
     * Mark buffer as clean
     */
    void mark_clean() noexcept { dirty_ = false; }

    /**
     * Get buffer as span
     */
    [[nodiscard]] std::span<TerminalGlyph> data() noexcept {
        return std::span<TerminalGlyph>(buffer_);
    }

    /**
     * Clear buffer
     */
    void clear() {
        std::fill(buffer_.begin(), buffer_.end(), TerminalGlyph{});
        dirty_ = true;
    }
};

/**
 * Display updater
 *
 * Manages display updates with delta detection and double buffering.
 */
template<Backend>
requires TerminalBackend<Backend>
class DisplayUpdater {
private:
    Backend& terminal_;
    DisplayBuffer current_buffer_;
    DisplayBuffer previous_buffer_;

public:
    DisplayUpdater(Backend& terminal, int width, int height)
        : terminal_(terminal)
        , current_buffer_(width, height)
        , previous_buffer_(width, height) {
    }

    /**
     * Update display (delta updates)
     */
    void update() {
        if (!current_buffer_.is_dirty()) {
            return;
        }

        // Update only changed glyphs
        for (int row = 0; row < current_buffer_.height_; ++row) {
            for (int col = 0; col < current_buffer_.width_; ++col) {
                auto current = current_buffer_.get_glyph(row, col);
                auto previous = previous_buffer_.get_glyph(row, col);

                if (current.codepoint != previous.codepoint ||
                    current.face_id != previous.face_id) {
                    // Glyph changed, update terminal
                    terminal_.set_cursor_position({row, col});
                    std::span<TerminalGlyph> span(&current, 1);
                    terminal_.write_glyphs(span);
                }
            }
        }

        // Swap buffers
        std::swap(current_buffer_, previous_buffer_);
        current_buffer_.mark_clean();
    }

    /**
     * Get current buffer for writing
     */
    DisplayBuffer& buffer() noexcept { return current_buffer_; }
};

} // namespace emacs
```

---

## Testing Strategy

### Unit Tests

```cpp
// test/test_terminal_backends.cpp

#include <cassert>
#include <memory>

#include "terminal_concept.hpp"
#include "xterm.hpp"
#include "w32term.hpp"
#include "nsterm.hpp"

void test_x11_backend() {
#ifdef X11
    emacs::Terminal<emacs::X11TerminalBackend> term;
    assert(term.init());

    auto size = term.get_terminal_size();
    assert(size.first > 0);
    assert(size.second > 0);

    term.cleanup();
#endif
}

void test_windows_backend() {
#ifdef WINDOWSNT
    emacs::Terminal<emacs::WindowsTerminalBackend> term;
    assert(term.init());

    auto size = term.get_terminal_size();
    assert(size.first > 0);
    assert(size.second > 0);

    // Test VT100 support
    assert(term.supports_colors());

    term.cleanup();
#endif
}

void test_macos_backend() {
#ifdef __APPLE__
    emacs::Terminal<emacs::NSTerminalBackend> term;
    assert(term.init());

    auto size = term.get_terminal_size();
    assert(size.first > 0);
    assert(size.second > 0);

    term.cleanup();
#endif
}

void test_display_buffer() {
    emacs::DisplayBuffer buffer(80, 24);

    assert(buffer.get_glyph(0, 0).codepoint == 0);

    emacs::TerminalGlyph glyph{'A', 0, 7, 0, false, false};
    buffer.set_glyph(10, 20, glyph);

    auto retrieved = buffer.get_glyph(10, 20);
    assert(retrieved.codepoint == 'A');

    buffer.resize(100, 30);
    assert(buffer.is_dirty());
}
```

### Integration Tests

```bash
# Terminal test suite
cd test
make terminal-tests
./terminal-tests --verbose

# Platform-specific tests
./terminal-tests --backend=x11
./terminal-tests --backend=windows
./terminal-tests --backend=macos

# Performance benchmarks
./terminal-tests --benchmark
```

### Manual Testing Checklist

- [ ] Basic display (text renders correctly)
- [ ] Cursor movement (up, down, left, right)
- [ ] Colors (foreground, background)
- [ ] Bold/italic/underline text attributes
- [ ] Wide characters (CJK, emojis)
- [ ] Scrolling (up, down)
- [ ] Line insert/delete
- [ ] Input handling (keyboard, mouse)
- [ ] Resize handling (terminal size changes)
- [ ] Fast refresh (no flicker)

---

## CMake Integration

```cmake
# src/CMakeLists.txt (Phase 3 additions)

# Terminal abstraction library
add_library(emacs_terminal
    terminal_concept.cpp
    terminal_concept.hpp
    terminal_database.cpp
    terminal_database.hpp
    termhooks.cpp
    termhooks.hpp
)

target_include_directories(emacs_terminal PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(emacs_terminal PUBLIC cxx_std_20)

# Platform-specific backends
if(UNIX AND NOT APPLE)
    # X11 terminal backend
    add_library(emacs_terminal_x11
        xterm.cpp
        xterm.hpp
    )

    target_link_libraries(emacs_terminal_x11 PRIVATE
        emacs_terminal
        X11::X11
        X11::Xft
    )
endif()

if(WIN32)
    # Windows terminal backend
    add_library(emacs_terminal_w32
        w32term.cpp
        w32term.hpp
    )

    target_link_libraries(emacs_terminal_w32 PRIVATE
        emacs_terminal
    )
endif()

if(APPLE)
    # macOS terminal backend
    add_library(emacs_terminal_ns
        nsterm.cpp
        nsterm.hpp
    )

    target_link_libraries(emacs_terminal_ns PRIVATE
        emacs_terminal
        "-framework Cocoa"
    )
endif()

# Display update system
add_library(emacs_display
    dispnew.cpp
    dispnew.hpp
)

target_link_libraries(emacs_display PUBLIC
    emacs_terminal
)

# Link emacs executable with terminal backend
if(UNIX AND NOT APPLE)
    target_link_libraries(emacs PRIVATE emacs_terminal_x11)
elseif(WIN32)
    target_link_libraries(emacs PRIVATE emacs_terminal_w32)
elseif(APPLE)
    target_link_libraries(emacs PRIVATE emacs_terminal_ns)
endif()

target_link_libraries(emacs PRIVATE emacs_display)
```

---

## Phase 3 Deliverables

1. **Terminal Abstraction Layer**
   - `src/terminal_concept.hpp` - C++20 concept-based interface
   - `src/termhooks.hpp` - Modernized terminal hooks
   - `src/terminal_database.hpp` - VT100 escape sequences

2. **Platform Backends**
   - `src/xterm.cpp/hpp` - X11 terminal (Linux)
   - `src/w32term.cpp/hpp` - Windows terminal (Windows 10+)
   - `src/nsterm.cpp/hpp` - macOS terminal (Cocoa)

3. **Display System**
   - `src/dispnew.cpp/hpp` - Display update with double buffering

4. **Tests**
   - `test/test_terminal_backends.cpp` - Unit tests
   - `test/test_display_buffer.cpp` - Display buffer tests

5. **Documentation**
   - This document (phase3-terminal-tui.md)
   - Technical notes on Windows TUI improvements

---

## Phase 3 Success Criteria Checklist

- [ ] Terminal interface defined using C++20 concepts
- [ ] Platform-specific backends implemented (X11, Windows, macOS, Haiku)
- [ ] Windows TUI is usable (not just functional)
- [ ] Terminal operations work on all platforms
- [ ] TUI tests pass on Linux, macOS, Windows
- [ ] Performance comparable to C implementation (within 10%)
- [ ] No memory leaks detected (Valgrind/ASAN clean)
- [ ] Termcap replaced with C++ VT100 database
- [ ] CMake targets build successfully on all platforms
- [ ] Integration tests pass
- [ ] Manual testing checklist complete

---

## Notes and Considerations

### Windows TUI Critical Path

This is the highest-risk item in Phase 3. Windows console has historically been weak in Emacs.

**Mitigation Strategy:**
1. Use Windows 10+ Console API 2.0 features
2. Enable VT100 emulation for cross-platform compatibility
3. Handle wide characters (CJK) correctly
4. Implement proper input handling with UTF-8
5. Benchmark against Neovim's TUI

### C++20 Concepts Benefits

- **Compile-time checking:** Backend compatibility verified at compile time
- **No runtime overhead:** Concepts are zero-cost abstractions
- **Better error messages:** Clear compiler diagnostics
- **Self-documenting:** Interface requirements explicit

### Backward Compatibility

During transition:
- Keep `termhooks.h` for C code compatibility
- Use `extern "C"` bridge functions
- Gradually migrate modules to C++ API
- Maintain dual header support (`.h` and `.hpp`)

---

## Next Steps

After Phase 3 completion, proceed to Phase 4: Lisp Interpreter Core.

**Phase 4 Requirements:**
1. Terminal abstraction complete (Phase 3)
2. Display system modernized (Phase 3)
3. Platform backends stable and tested (Phase 3)

**Phase 4 Preview:**
- Migrate Lisp data types to C++20 classes
- Implement evaluation engine with coroutines
- Integrate C++ allocator with GC
- Port `src/lisp.h`, `src/data.c`, `src/eval.c`

---

**Last Updated:** 2026-02-01
**Next Review:** End of Phase 3 (2026-03-22)
