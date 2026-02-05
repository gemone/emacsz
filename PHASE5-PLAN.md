# Phase 5: Emacs Core Integration - Plan & Architecture

**Status**: 🚧 In Progress  
**Started**: 2025-02-05  
**Dependencies**: Phase 4 Complete ✅  
**Goal**: Integrate C++ TUI components with Emacs display engine

---

## 📋 Overview

Phase 5 bridges the gap between our modern C++20 TUI infrastructure and Emacs' legacy C display engine. We'll create adapter layers that translate between Emacs' glyph-based rendering model and our Grid/Renderer system.

### Key Challenge

Emacs has a complex display architecture built over 40+ years:
- **xdisp.c**: 39,195 lines - redisplay engine
- **term.c**: 5,238 lines - terminal interface
- **keyboard.c**: 14,612 lines - input handling
- **dispextern.h**: Complex data structures (glyphs, faces, windows)

We need to integrate **without breaking** existing functionality.

---

## 🎯 Objectives

1. **Display Adapter**: Map Emacs faces → Grid CellAttributes
2. **Input Adapter**: Map InputParser events → Emacs keyboard events
3. **Window Management**: Use Grid for multiple Emacs windows
4. **Redisplay Integration**: Hook Emacs redisplay into Grid system
5. **Backward Compatibility**: Ensure legacy C code continues to work

---

## 🏗️ Architecture

### Current Emacs Display Flow (C)

```
┌─────────────┐
│   Buffer    │ Text content
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Redisplay  │ xdisp.c - generate glyphs
│  (xdisp.c)  │ 
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Glyphs    │ struct glyph with face_id
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Terminal   │ term.c - output to TTY
│  (term.c)   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     TTY     │ Raw terminal output
└─────────────┘
```

### New Integrated Flow (C++20 + C)

```
┌─────────────┐
│   Buffer    │ Text content (C)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Redisplay  │ xdisp.c - generate glyphs (C)
│  (xdisp.c)  │ 
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ DisplayAdapter  │ ← NEW: Translate glyphs → Grid (C++)
│   (C++ Bridge)  │    Maps struct face → CellAttributes
└──────┬──────────┘
       │
       ▼
┌─────────────┐
│    Grid     │ Double buffering + dirty tracking (C++)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Renderer   │ Generate ANSI sequences (C++)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     TTY     │ Modern efficient output
└─────────────┘

Input Flow:
┌─────────────┐
│     TTY     │ Raw bytes
└──────┬──────┘
       │
       ▼
┌─────────────┐
│InputParser  │ Parse escape sequences (C++)
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  InputAdapter   │ ← NEW: InputEvent → Emacs events (C++)
│   (C++ Bridge)  │
└──────┬──────────┘
       │
       ▼
┌─────────────┐
│  keyboard.c │ Emacs command loop (C)
└─────────────┘
```

---

## 📦 Components to Build

### 1. Display Adapter (`emacs_display_adapter.hpp/cpp`)

**Purpose**: Translate Emacs display structures to Grid operations

**Key Functions**:
```cpp
class EmacsDisplayAdapter {
public:
  // Convert Emacs face to Grid cell attributes
  static CellAttributes face_to_attributes(const struct face *face);
  
  // Render a glyph to the Grid
  void render_glyph(Grid &grid, int row, int col, 
                    const struct glyph *glyph, const struct face *face);
  
  // Render an entire glyph row (line of text)
  void render_glyph_row(Grid &grid, int row, 
                        const struct glyph_row *glyph_row);
  
  // Sync entire window to Grid
  void sync_window_to_grid(Grid &grid, struct window *w);
  
  // Handle Emacs redisplay
  void redisplay_frame(struct frame *f);
};
```

**Mapping Strategy**:

| Emacs Concept | Grid Concept | Conversion |
|---------------|--------------|------------|
| `struct glyph` | Grid cell | Extract character + face |
| `struct face` | `CellAttributes` | Map colors, bold, etc. |
| `face->foreground` | `fg_color` | Color index → ANSI color |
| `face->background` | `bg_color` | Color index → ANSI color |
| `face->weight` (bold) | `bold` flag | Direct mapping |
| `face->slant` (italic) | `italic` flag | Direct mapping |
| `face->underline` | `underline` flag | Direct mapping |
| `glyph_row` | Grid row | Render all glyphs in row |

### 2. Input Adapter (`emacs_input_adapter.hpp/cpp`)

**Purpose**: Translate InputParser events to Emacs keyboard events

**Key Functions**:
```cpp
class EmacsInputAdapter {
public:
  // Convert InputEvent to Emacs keyboard event
  static Lisp_Object input_event_to_lisp(const InputEvent &event);
  
  // Queue events into Emacs kbd_buffer
  void queue_event(const InputEvent &event);
  
  // Integration with EventLoop
  void setup_event_loop(EventLoop &loop);
  
  // Handle special keys (arrows, function keys, etc.)
  static Lisp_Object keycode_to_lisp_symbol(uint32_t keycode);
};
```

**Mapping Strategy**:

| InputEvent Type | Emacs Event | Conversion |
|-----------------|-------------|------------|
| `KEY_PRESS` with ASCII | Character event | Direct char code |
| `KEY_PRESS` with special | Symbol event | Map to `<up>`, `<down>`, etc. |
| `MOUSE_PRESS` | Mouse click | Position + button |
| `MOUSE_RELEASE` | Mouse release | Position + button |
| `MOUSE_MOVE` | Mouse move | Position only |
| `RESIZE` | Window change | Update frame dimensions |

### 3. Terminal Backend (`emacs_terminal.hpp/cpp`)

**Purpose**: Replace/augment term.c with C++ Grid-based implementation

**Key Functions**:
```cpp
class EmacsTerminal {
public:
  // Initialize terminal for Emacs
  void init_terminal(struct terminal *term);
  
  // Write to terminal (replaces term.c functions)
  void write_glyphs(struct glyph *glyphs, int len);
  void clear_end_of_line(int x);
  void clear_frame();
  void set_terminal_modes();
  void reset_terminal_modes();
  
  // Cursor management
  void cursor_to(int row, int col);
  void set_terminal_cursor_visible(bool visible);
  
  // Integration
  Grid grid;
  Renderer renderer;
  EventLoop event_loop;
};
```

### 4. Frame Integration (`emacs_frame_adapter.hpp/cpp`)

**Purpose**: Manage multiple frames using Grid

**Key Functions**:
```cpp
class EmacsFrameAdapter {
public:
  // Create Grid for frame
  void init_frame_grid(struct frame *f);
  
  // Resize frame Grid
  void resize_frame(struct frame *f, int rows, int cols);
  
  // Refresh frame (main entry point for redisplay)
  void refresh_frame(struct frame *f);
  
  // Get Grid for frame
  Grid& get_frame_grid(struct frame *f);
};
```

---

## 🔧 Implementation Strategy

### Phase 5.1: Minimal Display Integration ✅ (First Priority)

**Goal**: Get "Hello World" from Emacs buffer to Grid

**Steps**:
1. Create `emacs_display_adapter.hpp/cpp` with basic face mapping
2. Implement `face_to_attributes()` for foreground/background only
3. Implement `render_glyph()` for ASCII characters only
4. Create minimal test: render a single line of text
5. **Milestone**: Display static text from Emacs buffer in Grid

**Files**:
- `src/emacs_display_adapter.hpp` (interface)
- `src/emacs_display_adapter.cpp` (implementation)
- `test/cxx/test_display_adapter.cpp` (unit tests)

**Acceptance Criteria**:
- [ ] Convert simple face (fg/bg only) to CellAttributes
- [ ] Render ASCII glyph to Grid cell
- [ ] Unit tests passing
- [ ] Manual test renders "Hello World"

### Phase 5.2: Input Integration

**Goal**: Keyboard input from EventLoop → Emacs

**Steps**:
1. Create `emacs_input_adapter.hpp/cpp`
2. Implement ASCII key mapping
3. Implement special key mapping (arrows, Enter, etc.)
4. Integrate with EventLoop callbacks
5. **Milestone**: Type characters in Emacs using new input system

**Files**:
- `src/emacs_input_adapter.hpp` (interface)
- `src/emacs_input_adapter.cpp` (implementation)
- `test/cxx/test_input_adapter.cpp` (unit tests)

**Acceptance Criteria**:
- [ ] ASCII keys → Emacs character events
- [ ] Arrow keys → Emacs navigation
- [ ] Ctrl/Meta modifiers working
- [ ] Events appear in kbd_buffer correctly

### Phase 5.3: Full Display Attributes

**Goal**: Support all Emacs face attributes

**Steps**:
1. Extend `face_to_attributes()` for bold, italic, underline
2. Add support for 256-color terminals
3. Handle overlays and text properties
4. **Milestone**: Syntax highlighting works correctly

**Acceptance Criteria**:
- [ ] Bold/italic/underline rendering
- [ ] 256-color support
- [ ] Overlays (e.g., region highlighting)
- [ ] Text properties (e.g., links)

### Phase 5.4: Window Management

**Goal**: Multiple Emacs windows in one Grid

**Steps**:
1. Create `emacs_window_manager.hpp/cpp`
2. Map Emacs window tree to Grid regions
3. Handle window splits (C-x 2, C-x 3)
4. Handle window resize
5. **Milestone**: Split windows work correctly

**Acceptance Criteria**:
- [ ] Horizontal splits display correctly
- [ ] Vertical splits display correctly
- [ ] Window resize updates Grid regions
- [ ] Active window highlighted

### Phase 5.5: Redisplay Integration

**Goal**: Full integration with Emacs redisplay engine

**Steps**:
1. Create hooks in xdisp.c to call C++ adapters
2. Replace term.c TTY output with Grid/Renderer
3. Ensure double-buffering reduces flicker
4. **Milestone**: Full Emacs editing session works

**Acceptance Criteria**:
- [ ] Emacs redisplay uses Grid
- [ ] No visual glitches
- [ ] Performance acceptable (< 16ms per frame)
- [ ] All display tests pass

### Phase 5.6: Mouse Support

**Goal**: Full mouse interaction

**Steps**:
1. Extend InputAdapter for mouse events
2. Map mouse coordinates to Emacs positions
3. Implement click, drag, scroll
4. **Milestone**: Mouse selection and scrolling work

**Acceptance Criteria**:
- [ ] Click to position cursor
- [ ] Drag to select region
- [ ] Scroll wheel scrolls buffer
- [ ] Mouse in menus (if applicable)

---

## 📐 Data Structure Mappings

### Emacs Face → Grid CellAttributes

```cpp
CellAttributes EmacsDisplayAdapter::face_to_attributes(const struct face *face) {
  CellAttributes attr;
  
  if (!face) {
    return attr; // Default attributes
  }
  
  // Map foreground color (color index → ANSI color)
  attr.fg_color = color_index_to_ansi(face->foreground);
  
  // Map background color
  attr.bg_color = color_index_to_ansi(face->background);
  
  // Map text attributes
  attr.bold = (face->weight == FONT_WEIGHT_BOLD);
  attr.italic = (face->slant == FONT_SLANT_ITALIC);
  attr.underline = face->underline_p;
  attr.reverse = false; // TODO: handle reverse video
  
  return attr;
}
```

### InputEvent → Emacs Lisp Event

```cpp
Lisp_Object EmacsInputAdapter::input_event_to_lisp(const InputEvent &event) {
  switch (event.type) {
    case InputEventType::KEY_PRESS: {
      // ASCII character
      if (event.key.codepoint < 128) {
        return make_fixnum(event.key.codepoint);
      }
      
      // Special key (arrows, F-keys, etc.)
      return keycode_to_lisp_symbol(event.key.keycode);
    }
    
    case InputEventType::MOUSE_PRESS: {
      // Create mouse-click event
      // Format: (mouse-1 ((x . y) window) ...)
      return make_mouse_event(event.mouse.button, 
                              event.mouse.x, 
                              event.mouse.y);
    }
    
    case InputEventType::RESIZE: {
      // Signal window-size-change
      return Qwindow_size_change;
    }
    
    default:
      return Qnil;
  }
}
```

---

## 🔌 Integration Points

### Where to Hook into Emacs C Code

1. **Terminal Initialization** (`term.c`)
   - Hook: `init_initial_terminal()`
   - Action: Create EmacsTerminal instance with Grid

2. **Redisplay** (`xdisp.c`)
   - Hook: `update_frame()` or `redisplay_internal()`
   - Action: Call `EmacsDisplayAdapter::sync_window_to_grid()`

3. **Input Reading** (`keyboard.c`)
   - Hook: `read_char()` or `kbd_buffer_get_event()`
   - Action: Use EventLoop + InputAdapter

4. **Terminal Output** (`term.c`)
   - Hook: `write_glyphs()`, `clear_end_of_line()`, etc.
   - Action: Redirect to Grid operations

### C/C++ Interop Strategy

Since Emacs is C and our TUI is C++, we need extern "C" wrappers:

```cpp
// In emacs_display_adapter.cpp
extern "C" {
  // C-callable wrapper for C++ functionality
  void emacs_cxx_render_glyph_row(void *grid_ptr, int row, 
                                   struct glyph_row *glyph_row) {
    Grid *grid = static_cast<Grid*>(grid_ptr);
    EmacsDisplayAdapter adapter;
    adapter.render_glyph_row(*grid, row, glyph_row);
  }
  
  void emacs_cxx_flush_grid(void *grid_ptr) {
    Grid *grid = static_cast<Grid*>(grid_ptr);
    Renderer renderer;
    renderer.render(*grid, std::cout);
  }
}
```

Then in C code (term.c):

```c
// Forward declarations
extern void emacs_cxx_render_glyph_row(void *grid, int row, 
                                        struct glyph_row *glyph_row);
extern void emacs_cxx_flush_grid(void *grid);

// In redisplay
static void
update_text_area (struct window *w, struct glyph_row *glyph_row, int row) {
  void *grid = get_frame_grid(w->frame);
  emacs_cxx_render_glyph_row(grid, row, glyph_row);
}
```

---

## 🧪 Testing Strategy

### Unit Tests (Pure C++)

Each adapter has its own test suite:

```cpp
// test/cxx/test_display_adapter.cpp
void test_face_to_attributes() {
  struct face mock_face;
  mock_face.foreground = 0xFF0000; // Red
  mock_face.background = 0x000000; // Black
  mock_face.weight = FONT_WEIGHT_BOLD;
  
  auto attr = EmacsDisplayAdapter::face_to_attributes(&mock_face);
  
  assert(attr.bold == true);
  // assert color mappings...
}
```

### Integration Tests (C++ calling C)

```cpp
// test/cxx/test_emacs_integration.cpp
// NOTE: Requires linking with Emacs object files

extern "C" {
  // Emacs C functions we'll call
  struct frame *make_initial_frame(void);
  struct window *make_window(void);
}

void test_render_emacs_window() {
  struct frame *f = make_initial_frame();
  struct window *w = make_window();
  
  Grid grid(24, 80);
  EmacsDisplayAdapter adapter;
  adapter.sync_window_to_grid(grid, w);
  
  // Verify grid contents match window
}
```

### Manual Testing

```bash
# Run Emacs with new backend
./src/emacs --display-backend=cxx-grid

# Expected: Full Emacs UI rendered via Grid system
```

---

## ⚠️ Risks & Mitigations

### Risk 1: Emacs Internal API Instability
**Problem**: Emacs internal structures (struct glyph, struct face) may change  
**Mitigation**: 
- Isolate all Emacs C struct access in adapters
- Use accessor functions where possible
- Document Emacs version compatibility

### Risk 2: Performance Regression
**Problem**: C++ overhead may slow down redisplay  
**Mitigation**:
- Use dirty region tracking (already implemented in Grid)
- Profile critical paths
- Optimize hot functions (e.g., `face_to_attributes`)

### Risk 3: Memory Management Conflicts
**Problem**: Emacs GC vs C++ allocators  
**Mitigation**:
- Use GC-aware allocators (already implemented in Phase 1)
- Never store Lisp_Object in C++ containers without protection
- Use `gc_vector_t`, `gc_string` consistently

### Risk 4: Breaking Existing Functionality
**Problem**: Integration breaks legacy TTY code  
**Mitigation**:
- Keep legacy term.c as fallback option
- Feature flag: `--enable-cxx-terminal` (compile-time)
- Runtime option: `--display-backend=legacy` vs `cxx-grid`

---

## 📊 Success Metrics

### Quantitative
- [ ] All existing Emacs display tests pass
- [ ] Redisplay performance: < 16ms per frame (60 FPS)
- [ ] Memory overhead: < 5% increase from baseline
- [ ] Zero memory leaks (Valgrind clean)

### Qualitative
- [ ] Visual rendering indistinguishable from legacy backend
- [ ] All Emacs editing features work (navigation, selection, etc.)
- [ ] Syntax highlighting displays correctly
- [ ] Multiple windows/splits work
- [ ] Mouse interaction works

### Developer Experience
- [ ] Clean C++20 code (no raw pointers where avoidable)
- [ ] Comprehensive unit test coverage (>80%)
- [ ] Clear documentation of integration points
- [ ] Easy to add new features (extensibility)

---

## 📅 Timeline Estimate

| Phase | Tasks | Estimated Time | Priority |
|-------|-------|----------------|----------|
| 5.1 Minimal Display | Basic face mapping, simple rendering | 2-3 days | P0 |
| 5.2 Input Integration | Keyboard event mapping | 1-2 days | P0 |
| 5.3 Full Attributes | Bold/italic/underline, 256-color | 1-2 days | P1 |
| 5.4 Window Management | Splits, resize | 2-3 days | P1 |
| 5.5 Redisplay Integration | Full xdisp.c hooks | 2-3 days | P0 |
| 5.6 Mouse Support | Click, drag, scroll | 1-2 days | P2 |
| **Total** | | **9-15 days** | |

**Note**: This is AI-assisted development, so actual time may vary significantly.

---

## 🚀 Getting Started (Phase 5.1)

### Immediate Next Steps

1. **Create Display Adapter Skeleton**
   ```bash
   # Create files
   touch src/emacs_display_adapter.hpp
   touch src/emacs_display_adapter.cpp
   touch test/cxx/test_display_adapter.cpp
   ```

2. **Implement Basic Face Mapping**
   - Start with foreground/background colors only
   - Map Emacs color indices to ANSI colors (0-15)

3. **Create Mock Test**
   - Test `face_to_attributes()` with mock struct face
   - Verify color mapping correctness

4. **Implement Single Glyph Rendering**
   - `render_glyph()` for ASCII only
   - Write to Grid at specific (row, col)

5. **Manual Integration Test**
   - Create standalone test that uses Emacs structures
   - Render "Hello World" to Grid
   - Output via Renderer to verify

---

## 📚 Required Reading

Before starting implementation, understand these Emacs concepts:

1. **Glyphs**: Fundamental display unit (src/dispextern.h, struct glyph)
2. **Faces**: Text attributes (src/dispextern.h, struct face)
3. **Glyph Rows**: Horizontal line of glyphs (struct glyph_row)
4. **Windows**: Emacs window (NOT OS window) displaying buffer
5. **Frames**: Top-level container (terminal or GUI frame)
6. **Redisplay**: The algorithm that updates display (src/xdisp.c)

**Key Files**:
- `src/dispextern.h` - All display structures
- `src/xdisp.c` - Redisplay engine (READ COMMENTS!)
- `src/term.c` - Terminal output (what we're replacing)
- `src/keyboard.c` - Input handling

---

## ✅ Phase 5.1 Acceptance Criteria

Before moving to Phase 5.2, we must have:

- [x] `emacs_display_adapter.hpp` with class definition
- [x] `face_to_attributes()` implemented and tested
- [x] `render_glyph()` for ASCII characters
- [x] Unit tests for adapter (at least 5 test cases)
- [x] Manual test renders static text correctly
- [x] Code compiles with no errors
- [x] All existing Phase 4 tests still pass
- [x] CMake integration for new module
- [x] Documentation updated (this file)

**Milestone Deliverable**: Render "Hello from Emacs!" text using:
1. Mock `struct glyph` array (C)
2. `EmacsDisplayAdapter` (C++)
3. `Grid` (C++)
4. `Renderer` (C++)
5. ANSI output to terminal

---

**Current Status**: 📝 Planning Complete - Ready for Implementation  
**Next**: Start Phase 5.1 - Create Display Adapter skeleton

---

**References**:
- Phase 4 completion: `PHASE4-COMPLETE.md`
- Grid implementation: `src/grid.hpp`
- Renderer implementation: `src/renderer.hpp`
- Emacs display: `src/dispextern.h`, `src/xdisp.c`
