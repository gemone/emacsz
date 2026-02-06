// src/emacs_window_adapter.hpp
// Phase 5.3: Window Integration - Sync Emacs windows with Grid
//
// Copyright (C) 2026 Free Software Foundation, Inc.
//
// This file is part of GNU Emacs.

#pragma once

#include <cstddef>
#include "grid.hpp"

// Forward declarations for Emacs C structures
// These will be properly defined when compiled with Emacs
#ifndef EMACS_WINDOW_STRUCTS_DEFINED
struct window;
struct buffer;
struct glyph_matrix;
struct glyph_row;

// Mock Lisp_Object for standalone compilation
typedef void *Lisp_Object;

// Mock window structure for standalone testing
struct window
{
  int total_cols;	// Total width in characters
  int total_lines;	// Total height in characters
  int pixel_width;	// Width in pixels
  int pixel_height;	// Height in pixels
  int left_col;		// Left edge position
  int top_line;		// Top edge position
  Lisp_Object contents; // Buffer being displayed
  Lisp_Object start;	// Window start position (marker)
  Lisp_Object pointm;	// Point position (marker)
  struct glyph_matrix *current_matrix;
  struct glyph_matrix *desired_matrix;
};

// Mock buffer structure for standalone testing
struct buffer
{
  Lisp_Object name_;
  char *text_data; // Simplified text storage for testing
  ptrdiff_t text_length;
  ptrdiff_t pt; // Point position
};

// Mock glyph structures for standalone testing
struct glyph
{
  int ch;	    // Character code
  unsigned face_id; // Face ID
};

struct glyph_row
{
  struct glyph *glyphs[3]; // TEXT_AREA = 1
  int used[3];		   // Number of glyphs used
  bool enabled_p;
};

struct glyph_matrix
{
  struct glyph_row *rows;
  int nrows;
};

enum
{
  TEXT_AREA = 1
};
#endif

namespace emacs
{
namespace tui
{

/**
 * @brief Adapter for synchronizing Emacs window state with Grid
 *
 * This adapter bridges Emacs window structures (struct window) with
 * our C++20 Grid system, enabling proper text display and cursor
 * positioning.
 *
 * Key responsibilities:
 * - Extract window dimensions (width/height in characters)
 * - Extract visible text from buffer
 * - Map cursor position from buffer coordinates to grid coordinates
 * - Handle scroll offsets (window-start)
 * - Sync glyph matrix to Grid cells
 *
 * Coordinate mapping:
 * - Emacs uses buffer positions (ptrdiff_t, 1-based)
 * - Grid uses (row, col) coordinates (0-based)
 * - Window has (left_col, top_line) offset on frame
 *
 * @see Grid for the target grid system
 * @see struct window in src/window.h
 * @see struct buffer in src/buffer.h
 */
class EmacsWindowAdapter
{
public:
  /**
   * @brief Window dimension information
   */
  struct WindowDimensions
  {
    int width;	///< Width in characters
    int height; ///< Height in characters
    int left;	///< Left edge position
    int top;	///< Top edge position
  };

  /**
   * @brief Cursor position information
   */
  struct CursorPosition
  {
    int row; ///< Row (0-based)
    int col; ///< Column (0-based)
  };

  /**
   * @brief Extract window dimensions
   *
   * Gets the window's display area size in character cells, excluding
   * scroll bars, fringes, and margins.
   *
   * @param w Emacs window structure
   * @return Window dimensions in characters
   */
  WindowDimensions
  get_window_dimensions (const struct window *w) const;

  /**
   * @brief Get cursor position within window
   *
   * Converts Emacs point (buffer position) to grid coordinates
   * relative to the window's top-left corner.
   *
   * @param w Emacs window structure
   * @return Cursor position in grid coordinates
   */
  CursorPosition get_cursor_position (const struct window *w) const;

  /**
   * @brief Get window start position
   *
   * Returns the buffer position of the first visible character in
   * the window (the scroll offset).
   *
   * @param w Emacs window structure
   * @return Buffer position of window start
   */
  ptrdiff_t get_window_start (const struct window *w) const;

  /**
   * @brief Get point (cursor) position in buffer
   *
   * @param w Emacs window structure
   * @return Buffer position of point
   */
  ptrdiff_t get_window_point (const struct window *w) const;

  /**
   * @brief Synchronize window content to Grid
   *
   * Copies the visible text from the window's glyph matrix to the
   * Grid, applying face attributes. This is the main synchronization
   * function.
   *
   * @param w Emacs window structure
   * @param grid Target grid to populate
   */
  void sync_window_to_grid (const struct window *w, Grid &grid);

  /**
   * @brief Synchronize cursor position to Grid
   *
   * Updates the grid's cursor position to match the window's point.
   *
   * @param w Emacs window structure
   * @param grid Target grid to update
   */
  void sync_cursor_to_grid (const struct window *w, Grid &grid);

  /**
   * @brief Extract text from glyph matrix row
   *
   * Converts a single glyph row to Grid cells with attributes.
   *
   * @param row Glyph row from window's matrix
   * @param grid_row Target row in Grid
   * @param max_cols Maximum columns to copy
   */
  void sync_glyph_row_to_grid (const struct glyph_row *row,
			       int grid_row, Grid &grid,
			       int max_cols);

  /**
   * @brief Check if window is valid for synchronization
   *
   * Verifies the window has valid buffer and dimensions.
   *
   * @param w Emacs window structure
   * @return true if window is valid, false otherwise
   */
  bool is_window_valid (const struct window *w) const;

  /**
   * @brief Get buffer from window
   *
   * Extracts the buffer pointer from window's contents field.
   *
   * @param w Emacs window structure
   * @return Buffer pointer or nullptr if none
   */
  struct buffer *get_window_buffer (const struct window *w) const;

private:
  /**
   * @brief Convert buffer position to window-relative coordinates
   *
   * Maps a buffer position to (row, col) within the window's visible
   * area.
   *
   * @param w Emacs window structure
   * @param pos Buffer position
   * @return Grid coordinates relative to window
   */
  CursorPosition buffer_pos_to_window_coords (const struct window *w,
					      ptrdiff_t pos) const;

  /**
   * @brief Extract Lisp_Object as integer (for testing)
   *
   * In real Emacs, this would use XINT/XFIXNUM. For testing, we cast.
   *
   * @param obj Lisp_Object
   * @return Integer value
   */
  ptrdiff_t lisp_to_int (Lisp_Object obj) const;

  /**
   * @brief Extract buffer pointer from Lisp_Object (for testing)
   *
   * In real Emacs, this would use XBUFFER. For testing, we cast.
   *
   * @param obj Lisp_Object
   * @return Buffer pointer
   */
  struct buffer *lisp_to_buffer (Lisp_Object obj) const;
};

} // namespace tui
} // namespace emacs

// C API for Emacs C code integration
// These functions provide a C-compatible interface for calling from
// Emacs

#ifdef __cplusplus
extern "C"
{
#endif

  /**
   * @brief Create a new EmacsWindowAdapter instance
   * @return Opaque pointer to adapter (cast to void* for C
   * compatibility)
   */
  void *emacs_cxx_create_window_adapter (void);

  /**
   * @brief Destroy an EmacsWindowAdapter instance
   * @param adapter_ptr Adapter created by
   * emacs_cxx_create_window_adapter
   */
  void emacs_cxx_destroy_window_adapter (void *adapter_ptr);

  /**
   * @brief Synchronize window to grid (C API)
   * @param adapter_ptr Adapter instance
   * @param window_ptr Emacs window structure
   * @param grid_ptr Grid instance
   */
  void emacs_cxx_sync_window_to_grid (void *adapter_ptr,
				      void *window_ptr,
				      void *grid_ptr);

  /**
   * @brief Get window dimensions (C API)
   * @param adapter_ptr Adapter instance
   * @param window_ptr Emacs window structure
   * @param out_width Output: width in characters
   * @param out_height Output: height in characters
   */
  void emacs_cxx_get_window_dimensions (void *adapter_ptr,
					void *window_ptr,
					int *out_width,
					int *out_height);

  /**
   * @brief Get cursor position (C API)
   * @param adapter_ptr Adapter instance
   * @param window_ptr Emacs window structure
   * @param out_row Output: cursor row
   * @param out_col Output: cursor column
   */
  void emacs_cxx_get_cursor_position (void *adapter_ptr,
				      void *window_ptr, int *out_row,
				      int *out_col);

#ifdef __cplusplus
}
#endif
