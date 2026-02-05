// emacs_display_adapter.hpp - Bridge between Emacs display engine and
// Grid Part of Phase 5: Emacs Core Integration
//
// Copyright (C) 2025 Free Software Foundation, Inc.
//
// This file bridges Emacs' C-based display structures (glyphs, faces)
// to our modern C++20 Grid-based rendering system.

#ifndef EMACS_DISPLAY_ADAPTER_HPP
#define EMACS_DISPLAY_ADAPTER_HPP

#include "grid.hpp"

// Forward declarations for Emacs C structures
// These come from src/dispextern.h
struct face;
struct glyph;
struct glyph_row;
struct window;
struct frame;

namespace emacs
{

/// @brief Adapter class for translating Emacs display structures to
/// Grid
///
/// This class provides the bridge between Emacs' legacy C display
/// engine (based on glyphs and faces) and our modern C++20 Grid
/// system. It handles:
/// - Converting struct face to Grid CellAttributes
/// - Rendering individual glyphs to Grid cells
/// - Synchronizing entire Emacs windows to Grid
/// - Managing color mappings (Emacs color indices → ANSI colors)
///
/// Usage:
/// @code
///   Grid grid(24, 80);
///   EmacsDisplayAdapter adapter;
///   adapter.sync_window_to_grid(grid, emacs_window);
/// @endcode
class EmacsDisplayAdapter
{
public:
  EmacsDisplayAdapter () = default;
  ~EmacsDisplayAdapter () = default;

  // Non-copyable, non-movable (stateless adapter)
  EmacsDisplayAdapter (const EmacsDisplayAdapter &) = delete;
  EmacsDisplayAdapter &operator= (const EmacsDisplayAdapter &)
    = delete;
  EmacsDisplayAdapter (EmacsDisplayAdapter &&) = delete;
  EmacsDisplayAdapter &operator= (EmacsDisplayAdapter &&) = delete;

  //
  // Core Conversion Functions
  //

  /// @brief Convert Emacs face to Grid cell attributes
  ///
  /// Maps an Emacs face (colors, bold, italic, etc.) to Grid
  /// CellAttributes. This is the fundamental translation function for
  /// all visual styling.
  ///
  /// @param face Pointer to Emacs struct face (can be nullptr for
  /// defaults)
  /// @return CellAttributes suitable for Grid::set_cell()
  ///
  /// Mapping:
  /// - face->foreground → CellAttributes::fg_color (via color index
  /// mapping)
  /// - face->background → CellAttributes::bg_color (via color index
  /// mapping)
  /// - face->weight (bold) → CellAttributes::bold
  /// - face->slant (italic) → CellAttributes::italic
  /// - face->underline_p → CellAttributes::underline
  ///
  /// Phase 5.1: Only foreground/background colors implemented
  /// Phase 5.3: Will add bold, italic, underline, 256-color
  static tui::CellAttributes
  face_to_attributes (const struct face *face);

  /// @brief Render a single Emacs glyph to a Grid cell
  ///
  /// Writes one character with attributes to the Grid at (row, col).
  /// This is the atomic operation for all Emacs text display.
  ///
  /// @param grid Target Grid to write to
  /// @param row Row position (0-based)
  /// @param col Column position (0-based)
  /// @param glyph Emacs glyph containing character and face_id
  /// @param face Emacs face for styling (must match glyph->face_id)
  ///
  /// Phase 5.1: Only ASCII characters (32-126)
  /// Phase 5.3: Will add UTF-8, CJK support
  void render_glyph (tui::Grid &grid, int row, int col,
		     const struct glyph *glyph,
		     const struct face *face);

  /// @brief Render an entire Emacs glyph row to a Grid row
  ///
  /// Processes all glyphs in a glyph_row (one line of text) and
  /// renders them to the corresponding Grid row. This is the main
  /// entry point for Emacs redisplay integration.
  ///
  /// @param grid Target Grid
  /// @param row Target row index in Grid
  /// @param glyph_row Emacs glyph_row structure (one line)
  ///
  /// Phase 5.1: Not implemented yet
  /// Phase 5.5: Will integrate with xdisp.c
  void render_glyph_row (tui::Grid &grid, int row,
			 const struct glyph_row *glyph_row);

  /// @brief Synchronize entire Emacs window to Grid
  ///
  /// High-level function that renders all visible content of an Emacs
  /// window to the Grid. Handles:
  /// - Window bounds and positioning
  /// - All glyph rows in window
  /// - Mode line, header line, tab line
  ///
  /// @param grid Target Grid
  /// @param w Emacs window structure
  ///
  /// Phase 5.1: Not implemented yet
  /// Phase 5.4: Will implement with window management
  void sync_window_to_grid (tui::Grid &grid, struct window *w);

  /// @brief Full frame redisplay using Grid
  ///
  /// Top-level function for redisplaying an entire Emacs frame
  /// (terminal). This will be called from Emacs redisplay engine
  /// (xdisp.c).
  ///
  /// @param f Emacs frame structure
  ///
  /// Phase 5.1: Not implemented yet
  /// Phase 5.5: Will integrate with redisplay_internal()
  void redisplay_frame (struct frame *f);

  //
  // Utility Functions
  //

  /// @brief Convert Emacs color index to ANSI color code
  ///
  /// Maps Emacs internal color representation to ANSI terminal
  /// colors. Handles:
  /// - Basic 16 colors (ANSI 0-15)
  /// - 256-color palette (xterm colors)
  /// - True color (24-bit RGB) - future
  ///
  /// @param color Emacs color index (from face->foreground or
  /// background)
  /// @return ANSI color code (0-255, or special values)
  ///
  /// Phase 5.1: Basic 16 colors only (0-15)
  /// Phase 5.3: Will add 256-color support
  static uint8_t color_index_to_ansi (unsigned long color);

  /// @brief Extract character from Emacs glyph
  ///
  /// Emacs glyphs store characters in a complex union. This extracts
  /// the actual codepoint for rendering.
  ///
  /// @param glyph Emacs glyph structure
  /// @return Unicode codepoint (char32_t)
  ///
  /// Phase 5.1: ASCII only (returns char cast to char32_t)
  /// Phase 5.3: Full Unicode support
  static char32_t glyph_to_codepoint (const struct glyph *glyph);

  //
  // Debug/Testing Functions
  //

  /// @brief Render mock text directly (for testing)
  ///
  /// Bypasses Emacs structures entirely - useful for unit tests.
  /// Renders a simple string with default attributes.
  ///
  /// @param grid Target Grid
  /// @param row Row to write to
  /// @param col Starting column
  /// @param text Text to render (ASCII)
  ///
  /// This is NOT used in production - only for testing Phase 5.1
  void render_text_simple (tui::Grid &grid, int row, int col,
			   const char *text);
};

//
// C-callable wrappers for Emacs integration
//
// These functions provide a C interface to the C++
// EmacsDisplayAdapter, allowing legacy Emacs C code (term.c, xdisp.c)
// to call into our C++ Grid system.
//
extern "C"
{
  /// @brief C wrapper: Render a glyph row to Grid
  ///
  /// Called from Emacs C code (term.c or xdisp.c) during redisplay.
  ///
  /// @param grid_ptr Opaque pointer to Grid (created by
  /// emacs_cxx_create_grid)
  /// @param row Row index
  /// @param glyph_row Emacs glyph_row structure
  void emacs_cxx_render_glyph_row (void *grid_ptr, int row,
				   struct glyph_row *glyph_row);

  /// @brief C wrapper: Flush Grid to terminal
  ///
  /// Renders the Grid using Renderer and outputs to stdout.
  ///
  /// @param grid_ptr Opaque pointer to Grid
  void emacs_cxx_flush_grid (void *grid_ptr);

  /// @brief C wrapper: Create a new Grid
  ///
  /// Allocates a Grid using Emacs GC-aware allocator.
  ///
  /// @param rows Number of rows
  /// @param cols Number of columns
  /// @return Opaque pointer to Grid (pass to other functions)
  void *emacs_cxx_create_grid (int rows, int cols);

  /// @brief C wrapper: Destroy a Grid
  ///
  /// Deallocates Grid (using lisp_free).
  ///
  /// @param grid_ptr Opaque pointer to Grid
  void emacs_cxx_destroy_grid (void *grid_ptr);

} // extern "C"

} // namespace emacs

#endif // EMACS_DISPLAY_ADAPTER_HPP
