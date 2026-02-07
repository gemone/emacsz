// src/emacs_buffer_bridge.hpp
// Phase 6.5: Buffer ↔ Window Bridge
//
// This adapter connects EmacsBuffer (gap buffer + markers) to the
// Phase 5 display pipeline. It provides:
// - Buffer → Grid rendering (direct, no glyphs)
// - Buffer → glyph_matrix population (compatibility path)
// - Visible line extraction with wrapping
// - Point → grid cursor mapping
//
// Note: All buffer positions are 1-based (Emacs style).

#pragma once

#include <cstddef>

#include "containers.hpp"
#include "emacs_buffer.hpp"
#include "grid.hpp"

// glyph/glyph_row/glyph_matrix are defined in the window adapter
// mock structs. When building inside Emacs, these come from C
// headers and EMACS_WINDOW_STRUCTS_DEFINED is set externally.
#ifndef EMACS_WINDOW_STRUCTS_DEFINED
# include "emacs_window_adapter.hpp"
#endif

namespace emacs
{
namespace tui
{

/**
 * BufferBridge
 *
 * Connects EmacsBuffer content to the Phase 5 display pipeline.
 * This class can render directly into a Grid or populate a
 * glyph_matrix compatible with EmacsWindowAdapter.
 *
 * Rendering rules:
 * - window_start is 1-based and specifies the first visible byte.
 * - Newlines (\n) terminate a visual line and are not rendered.
 * - Long lines wrap at window_cols (visual wrap).
 * - Tabs expand to spaces at 8-column tab stops.
 *
 * Display model:
 * - The bridge walks buffer bytes from window_start forward.
 * - Each visual line is at most window_cols columns wide.
 * - A newline starts a new visual line immediately.
 * - Wrapping occurs before placing a character that would exceed
 *   the available columns.
 *
 * Example (window_cols = 10):
 *   Buffer: "A\tB"
 *   Visual: "A       B"
 *   (Tab expands to 7 spaces to reach column 8.)
 *
 * Direct vs glyph paths:
 * - Direct rendering writes Cell objects into Grid back buffer.
 * - Glyph rendering fills glyph_matrix rows for EmacsWindowAdapter.
 *
 * Statistics:
 * - lines_rendered_ counts visual lines produced per call.
 * - cells_written_ counts the number of Grid cells or glyphs set.
 *
 * Limitations (Phase 6):
 * - Multi-byte UTF-8 is treated as bytes for now.
 * - Character width and combining marks are not yet handled.
 */
class BufferBridge
{
public:
  BufferBridge ();
  ~BufferBridge ();

  // No copy, no move (manages internal glyph arrays)
  BufferBridge (const BufferBridge &) = delete;
  BufferBridge &operator= (const BufferBridge &) = delete;
  BufferBridge (BufferBridge &&) = delete;
  BufferBridge &operator= (BufferBridge &&) = delete;

  // === Direct Buffer → Grid rendering ===

  /**
   * Render buffer content directly to Grid.
   *
   * Extracts visible text from buffer starting at window_start,
   * wraps lines at window_cols, and writes to Grid cells.
   *
   * @param buffer Source buffer
   * @param grid Target grid
   * @param window_start Buffer position of first visible char
   * @param window_rows Number of visible rows
   * @param window_cols Number of visible columns
   * @param row_offset Grid row offset (for multi-window frames)
   * @param col_offset Grid column offset
   */
  void render_buffer_to_grid (const emacs::EmacsBuffer &buffer,
			      Grid &grid, ptrdiff_t window_start,
			      int window_rows, int window_cols,
			      int row_offset = 0, int col_offset = 0);

  /**
   * Render buffer with explicit attributes.
   *
   * Convenience overload using custom CellAttributes.
   */
  void render_buffer_to_grid (const emacs::EmacsBuffer &buffer,
			      Grid &grid, ptrdiff_t window_start,
			      int window_rows, int window_cols,
			      const CellAttributes &attrs,
			      int row_offset = 0, int col_offset = 0);

  // === Cursor position mapping ===

  /**
   * Cursor position inside Grid coordinates.
   *
   * The position is 0-based within the Grid. If the point is not
   * visible inside the current window, (row, col) will be (-1, -1).
   */
  struct CursorPos
  {
    int row = -1;
    int col = -1;

    [[nodiscard]] bool is_visible () const noexcept
    {
      return row >= 0 && col >= 0;
    }
  };

  /**
   * Map buffer point to grid coordinates.
   *
   * Converts the 1-based buffer point to 0-based grid coordinates,
   * accounting for window_start, line wrapping, and offsets.
   *
   * @param buffer Source buffer
   * @param window_start First visible buffer position
   * @param window_rows Visible rows in the window
   * @param window_cols Columns for line wrapping
   * @param row_offset Grid row offset
   * @param col_offset Grid column offset
   * @return CursorPos with coordinates or (-1, -1) if not visible
   */
  [[nodiscard]] CursorPos
  map_point_to_grid (const emacs::EmacsBuffer &buffer,
		     ptrdiff_t window_start, int window_rows,
		     int window_cols, int row_offset = 0,
		     int col_offset = 0) const;

  // === Line extraction ===

  /**
   * Extract visible lines from buffer.
   *
   * Returns the text displayed in a window of the given dimensions,
   * starting at window_start. Lines wrap at window_cols. Newlines
   * ('\n') start new visual lines and are not included in output.
   *
   * @param buffer Source buffer
   * @param window_start First visible position (1-based)
   * @param window_rows Max lines to extract
   * @param window_cols Max columns per line
   * @return Vector of lines (each line is a gc_string)
   */
  [[nodiscard]] gc_vector_t<gc_string>
  extract_visible_lines (const emacs::EmacsBuffer &buffer,
			 ptrdiff_t window_start, int window_rows,
			 int window_cols) const;

  // === Glyph matrix population ===

  /**
   * Populate a glyph matrix from buffer content.
   *
   * Creates/fills glyph rows that EmacsWindowAdapter can sync.
   * glyph.ch is filled with character codes, glyph.face_id is 0,
   * and glyph_row.enabled_p is set to true.
   *
   * @param buffer Source buffer
   * @param matrix Target glyph matrix (must be pre-allocated)
   * @param window_start First visible position
   * @param window_rows Matrix rows
   * @param window_cols Matrix columns
   */
  void populate_glyph_matrix (const emacs::EmacsBuffer &buffer,
			      struct glyph_matrix *matrix,
			      ptrdiff_t window_start, int window_rows,
			      int window_cols);

  // === Statistics ===
  [[nodiscard]] size_t lines_rendered () const noexcept;
  [[nodiscard]] size_t cells_written () const noexcept;
  void reset_stats () noexcept;

private:
  size_t lines_rendered_;
  size_t cells_written_;
};

} // namespace tui
} // namespace emacs
