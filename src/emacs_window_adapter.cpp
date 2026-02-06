// src/emacs_window_adapter.cpp
// Phase 5.3: Window Integration - Implementation

#include "emacs_window_adapter.hpp"
#include <algorithm>
#include <cstring>
#include "emacs_display_adapter.hpp"

namespace emacs
{
namespace tui
{

EmacsWindowAdapter::WindowDimensions
EmacsWindowAdapter::get_window_dimensions (
  const struct window *w) const
{
  WindowDimensions dims = { 0, 0, 0, 0 };

  if (!w)
    {
      return dims;
    }

  dims.width = w->total_cols;
  dims.height = w->total_lines;
  dims.left = w->left_col;
  dims.top = w->top_line;

  return dims;
}

EmacsWindowAdapter::CursorPosition
EmacsWindowAdapter::get_cursor_position (const struct window *w) const
{
  CursorPosition pos = { 0, 0 };

  if (!w || !w->current_matrix)
    {
      return pos;
    }

  ptrdiff_t point = get_window_point (w);
  ptrdiff_t start = get_window_start (w);

  if (point < start)
    {
      return pos;
    }

  return buffer_pos_to_window_coords (w, point);
}

ptrdiff_t
EmacsWindowAdapter::get_window_start (const struct window *w) const
{
  if (!w)
    {
      return 0;
    }

  return lisp_to_int (w->start);
}

ptrdiff_t
EmacsWindowAdapter::get_window_point (const struct window *w) const
{
  if (!w)
    {
      return 0;
    }

  return lisp_to_int (w->pointm);
}

void
EmacsWindowAdapter::sync_window_to_grid (const struct window *w,
					 Grid &grid)
{
  if (!is_window_valid (w))
    {
      return;
    }

  struct glyph_matrix *matrix = w->current_matrix;
  if (!matrix || !matrix->rows)
    {
      return;
    }

  WindowDimensions dims = get_window_dimensions (w);
  int max_rows = std::min (dims.height, matrix->nrows);
  int max_cols = dims.width;

  for (int row = 0; row < max_rows; ++row)
    {
      if (!matrix->rows[row].enabled_p)
	{
	  continue;
	}
      sync_glyph_row_to_grid (&matrix->rows[row], row, grid,
			      max_cols);
    }
}

void
EmacsWindowAdapter::sync_cursor_to_grid (const struct window *w,
					 Grid &grid)
{
  if (!is_window_valid (w))
    {
      return;
    }

  CursorPosition pos = get_cursor_position (w);

  (void) grid;
  (void) pos;
}

void
EmacsWindowAdapter::sync_glyph_row_to_grid (
  const struct glyph_row *row, int grid_row, Grid &grid, int max_cols)
{
  if (!row || !row->glyphs[TEXT_AREA])
    {
      return;
    }

  int num_glyphs = std::min (row->used[TEXT_AREA], max_cols);

  for (int col = 0; col < num_glyphs; ++col)
    {
      const struct glyph *g = &row->glyphs[TEXT_AREA][col];

      Cell cell;
      char ch_str[2] = { static_cast<char> (g->ch & 0x7F), '\0' };
      cell.ch = gc_string (ch_str);

      cell.attrs.fg = 7;
      cell.attrs.bg = 0;
      cell.attrs.flags = CellAttributes::NONE;

      grid.set_cell (grid_row, col, cell);
    }
}

bool
EmacsWindowAdapter::is_window_valid (const struct window *w) const
{
  if (!w)
    {
      return false;
    }

  if (w->total_cols <= 0 || w->total_lines <= 0)
    {
      return false;
    }

  return true;
}

struct buffer *
EmacsWindowAdapter::get_window_buffer (const struct window *w) const
{
  if (!w)
    {
      return nullptr;
    }

  return lisp_to_buffer (w->contents);
}

EmacsWindowAdapter::CursorPosition
EmacsWindowAdapter::buffer_pos_to_window_coords (
  const struct window *w, ptrdiff_t pos) const
{
  CursorPosition coords = { 0, 0 };

  if (!w || !w->current_matrix)
    {
      return coords;
    }

  ptrdiff_t start = get_window_start (w);
  if (pos < start)
    {
      return coords;
    }

  ptrdiff_t relative_pos = pos - start;

  WindowDimensions dims = get_window_dimensions (w);
  if (dims.width <= 0)
    {
      return coords;
    }

  coords.row = static_cast<int> (relative_pos / dims.width);
  coords.col = static_cast<int> (relative_pos % dims.width);

  if (coords.row >= dims.height)
    {
      coords.row = dims.height - 1;
      coords.col = dims.width - 1;
    }

  return coords;
}

ptrdiff_t
EmacsWindowAdapter::lisp_to_int (Lisp_Object obj) const
{
#ifdef EMACS_WINDOW_STRUCTS_DEFINED
  return XFIXNUM (obj);
#else
  return reinterpret_cast<ptrdiff_t> (obj);
#endif
}

struct buffer *
EmacsWindowAdapter::lisp_to_buffer (Lisp_Object obj) const
{
#ifdef EMACS_WINDOW_STRUCTS_DEFINED
  if (BUFFERP (obj))
    {
      return XBUFFER (obj);
    }
  return nullptr;
#else
  return reinterpret_cast<struct buffer *> (obj);
#endif
}

} // namespace tui
} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_window_adapter (void)
  {
    return new emacs::tui::EmacsWindowAdapter ();
  }

  void emacs_cxx_destroy_window_adapter (void *adapter_ptr)
  {
    delete static_cast<emacs::tui::EmacsWindowAdapter *> (
      adapter_ptr);
  }

  void emacs_cxx_sync_window_to_grid (void *adapter_ptr,
				      void *window_ptr,
				      void *grid_ptr)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsWindowAdapter *> (adapter_ptr);
    auto *window = static_cast<struct window *> (window_ptr);
    auto *grid = static_cast<emacs::tui::Grid *> (grid_ptr);

    if (adapter && window && grid)
      {
	adapter->sync_window_to_grid (window, *grid);
      }
  }

  void emacs_cxx_get_window_dimensions (void *adapter_ptr,
					void *window_ptr,
					int *out_width,
					int *out_height)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsWindowAdapter *> (adapter_ptr);
    auto *window = static_cast<struct window *> (window_ptr);

    if (adapter && window && out_width && out_height)
      {
	auto dims = adapter->get_window_dimensions (window);
	*out_width = dims.width;
	*out_height = dims.height;
      }
  }

  void emacs_cxx_get_cursor_position (void *adapter_ptr,
				      void *window_ptr, int *out_row,
				      int *out_col)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsWindowAdapter *> (adapter_ptr);
    auto *window = static_cast<struct window *> (window_ptr);

    if (adapter && window && out_row && out_col)
      {
	auto pos = adapter->get_cursor_position (window);
	*out_row = pos.row;
	*out_col = pos.col;
      }
  }

} // extern "C"
