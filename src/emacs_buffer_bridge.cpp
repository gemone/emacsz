// src/emacs_buffer_bridge.cpp
// Phase 6.5: Buffer ↔ Window Bridge implementation

#include "emacs_buffer_bridge.hpp"

#include <algorithm>
#include <cstring>

#include "text_properties.hpp"

namespace emacs
{
namespace tui
{
namespace
{

constexpr int TAB_WIDTH = 8;

[[nodiscard]] int
tab_spaces (int col) noexcept
{
  int offset = col % TAB_WIDTH;
  return TAB_WIDTH - offset;
}

} // namespace

BufferBridge::BufferBridge ()
    : lines_rendered_ (0), cells_written_ (0)
{
}

BufferBridge::~BufferBridge () = default;

void
BufferBridge::render_buffer_to_grid (const emacs::EmacsBuffer &buffer,
				     Grid &grid,
				     ptrdiff_t window_start,
				     int window_rows, int window_cols,
				     int row_offset, int col_offset)
{
  CellAttributes attrs;
  render_buffer_to_grid (buffer, grid, window_start, window_rows,
			 window_cols, attrs, row_offset, col_offset);
}

void
BufferBridge::render_buffer_to_grid (const emacs::EmacsBuffer &buffer,
				     Grid &grid,
				     ptrdiff_t window_start,
				     int window_rows, int window_cols,
				     const CellAttributes &base_attrs,
				     int row_offset, int col_offset)
{
  if (window_rows <= 0 || window_cols <= 0)
    {
      return;
    }

  ptrdiff_t start = window_start;
  if (start < 1)
    {
      start = 1;
    }

  ptrdiff_t buf_size = buffer.size ();
  const auto &props = buffer.text_properties ();

  Cell space_cell (" ", base_attrs, 1);
  Cell cell (" ", base_attrs, 1);

  int row = 0;
  int col = 0;
  ptrdiff_t idx = start;

  auto fill_rest_of_row = [&] ()
    {
      for (; col < window_cols; ++col)
	{
	  if (grid.set_cell (row_offset + row, col_offset + col,
			     space_cell))
	    {
	      ++cells_written_;
	    }
	}
    };

  while (row < window_rows && idx <= buf_size)
    {
      char ch = buffer.char_at (idx);

      if (ch == '\n')
	{
	  fill_rest_of_row ();
	  ++lines_rendered_;
	  ++row;
	  col = 0;
	  ++idx;
	  continue;
	}

      if (ch == '\t')
	{
	  int spaces = tab_spaces (col);
	  auto face = props.get_face (idx);
	  CellAttributes tab_attrs
	    = face.has_value () ? *face : base_attrs;
	  Cell tab_cell (" ", tab_attrs, 1);
	  for (int i = 0; i < spaces; ++i)
	    {
	      if (col >= window_cols)
		{
		  ++lines_rendered_;
		  ++row;
		  col = 0;
		  if (row >= window_rows)
		    {
		      break;
		    }
		}
	      if (grid.set_cell (row_offset + row, col_offset + col,
				 tab_cell))
		{
		  ++cells_written_;
		}
	      ++col;
	    }
	  ++idx;
	  continue;
	}

      if (col >= window_cols)
	{
	  ++lines_rendered_;
	  ++row;
	  col = 0;
	  if (row >= window_rows)
	    {
	      break;
	    }
	}

      auto face = props.get_face (idx);
      CellAttributes char_attrs
	= face.has_value () ? *face : base_attrs;

      char ch_str[2] = { ch, '\0' };
      cell.ch = gc_string (ch_str);
      cell.attrs = char_attrs;
      cell.width = 1;

      if (grid.set_cell (row_offset + row, col_offset + col, cell))
	{
	  ++cells_written_;
	}
      ++col;
      ++idx;
    }

  if (row < window_rows && col > 0)
    {
      fill_rest_of_row ();
      ++lines_rendered_;
      ++row;
      col = 0;
    }

  for (; row < window_rows; ++row)
    {
      col = 0;
      fill_rest_of_row ();
    }
}

BufferBridge::CursorPos
BufferBridge::map_point_to_grid (const emacs::EmacsBuffer &buffer,
				 ptrdiff_t window_start,
				 int window_rows, int window_cols,
				 int row_offset, int col_offset) const
{
  CursorPos pos;

  if (window_rows <= 0 || window_cols <= 0)
    {
      return pos;
    }

  ptrdiff_t start = window_start;
  if (start < 1)
    {
      start = 1;
    }

  ptrdiff_t point = buffer.point ();
  if (point < start)
    {
      return pos;
    }

  ptrdiff_t size = buffer.size ();
  ptrdiff_t stop = point - 1;
  if (stop > size)
    {
      stop = size;
    }

  int row = 0;
  int col = 0;

  for (ptrdiff_t idx = start; idx <= stop; ++idx)
    {
      char ch = buffer.char_at (idx);

      if (ch == '\n')
	{
	  ++row;
	  col = 0;
	  if (row >= window_rows)
	    {
	      return pos;
	    }
	  continue;
	}

      if (ch == '\t')
	{
	  int spaces = tab_spaces (col);
	  for (int i = 0; i < spaces; ++i)
	    {
	      if (col >= window_cols)
		{
		  ++row;
		  col = 0;
		  if (row >= window_rows)
		    {
		      return pos;
		    }
		}
	      ++col;
	    }
	  continue;
	}

      if (col >= window_cols)
	{
	  ++row;
	  col = 0;
	  if (row >= window_rows)
	    {
	      return pos;
	    }
	}

      ++col;
    }

  if (col >= window_cols)
    {
      ++row;
      col = 0;
    }

  if (row >= window_rows)
    {
      return pos;
    }

  pos.row = row_offset + row;
  pos.col = col_offset + col;
  return pos;
}

gc_vector_t<gc_string>
BufferBridge::extract_visible_lines (const emacs::EmacsBuffer &buffer,
				     ptrdiff_t window_start,
				     int window_rows,
				     int window_cols) const
{
  gc_vector_t<gc_string> lines;

  if (window_rows <= 0 || window_cols <= 0)
    {
      return lines;
    }

  ptrdiff_t start = window_start;
  if (start < 1)
    {
      start = 1;
    }

  ptrdiff_t size = buffer.size ();
  if (start > size)
    {
      return lines;
    }

  gc_string line;
  int col = 0;
  bool limit_reached = false;
  bool last_was_newline = false;

  auto append_line = [&] ()
    {
      if (static_cast<int> (lines.size ()) >= window_rows)
	{
	  limit_reached = true;
	  return;
	}
      lines.push_back (line);
      line.clear ();
      col = 0;
    };

  for (ptrdiff_t idx = start; idx <= size; ++idx)
    {
      if (limit_reached)
	{
	  break;
	}

      char ch = buffer.char_at (idx);

      if (ch == '\n')
	{
	  append_line ();
	  last_was_newline = true;
	  continue;
	}

      last_was_newline = false;

      if (ch == '\t')
	{
	  int spaces = tab_spaces (col);
	  for (int i = 0; i < spaces; ++i)
	    {
	      if (col >= window_cols)
		{
		  append_line ();
		  if (limit_reached)
		    {
		      break;
		    }
		}
	      line.push_back (' ');
	      ++col;
	    }
	  continue;
	}

      if (col >= window_cols)
	{
	  append_line ();
	  if (limit_reached)
	    {
	      break;
	    }
	}

      line.push_back (ch);
      ++col;
    }

  if (!limit_reached && static_cast<int> (lines.size ()) < window_rows
      && (!line.empty () || last_was_newline))
    {
      lines.push_back (line);
    }

  return lines;
}

void
BufferBridge::populate_glyph_matrix (const emacs::EmacsBuffer &buffer,
				     struct glyph_matrix *matrix,
				     ptrdiff_t window_start,
				     int window_rows, int window_cols)
{
  if (!matrix || !matrix->rows || window_rows <= 0
      || window_cols <= 0)
    {
      return;
    }

  gc_vector_t<gc_string> lines
    = extract_visible_lines (buffer, window_start, window_rows,
			     window_cols);

  lines_rendered_ += lines.size ();

  int max_rows = std::min (window_rows, matrix->nrows);

  for (int row = 0; row < max_rows; ++row)
    {
      struct glyph_row *glyph_row = &matrix->rows[row];
      if (!glyph_row)
	{
	  continue;
	}

      glyph_row->enabled_p = true;
      glyph_row->used[TEXT_AREA] = window_cols;

      struct glyph *glyphs = glyph_row->glyphs[TEXT_AREA];
      if (!glyphs)
	{
	  continue;
	}

      size_t line_index = static_cast<size_t> (row);
      const gc_string *line_ptr = nullptr;
      if (line_index < lines.size ())
	{
	  line_ptr = &lines[line_index];
	}

      for (int col = 0; col < window_cols; ++col)
	{
	  char ch = ' ';
	  if (line_ptr && col < static_cast<int> (line_ptr->size ()))
	    {
	      ch = (*line_ptr)[static_cast<size_t> (col)];
	    }
	  glyphs[col].ch = static_cast<int> (ch);
	  glyphs[col].face_id = 0;
	  ++cells_written_;
	}
    }
}

[[nodiscard]] size_t
BufferBridge::lines_rendered () const noexcept
{
  return lines_rendered_;
}

[[nodiscard]] size_t
BufferBridge::cells_written () const noexcept
{
  return cells_written_;
}

void
BufferBridge::reset_stats () noexcept
{
  lines_rendered_ = 0;
  cells_written_ = 0;
}

} // namespace tui
} // namespace emacs
