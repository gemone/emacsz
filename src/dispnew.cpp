#include "dispnew.hpp"
#include "terminal_concept.hpp"

#include <cstring>

namespace emacs
{

void
DisplayUpdate::clear ()
{
  for (auto &line : matrix_.lines)
    {
      for (auto &cell : line.cells)
	{
	  cell.codepoint = U' ';
	  cell.face_id = 0;
	  cell.background = 0;
	  cell.foreground = 7;
	  cell.wide = false;
	  cell.padding = false;
	}
    }
  needs_update_ = true;
}

void
DisplayUpdate::resize (int rows, int cols)
{
  if (rows != matrix_.rows || cols != matrix_.cols)
    {
      matrix_.rows = rows;
      matrix_.cols = cols;

      matrix_.lines.resize (rows);
      for (auto &line : matrix_.lines)
	{
	  line.y = &line - &matrix_.lines[0];
	  line.x = 0;
	  line.cells.resize (cols);
	  for (auto &cell : line.cells)
	    {
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
      needs_update_ = true;
    }
}

void
DisplayUpdate::write_cell (int row, int col, const DisplayCell &cell)
{
  if (row >= 0 && row < matrix_.rows && col >= 0
      && col < matrix_.cols)
    {
      auto &line = matrix_.lines[row];
      auto &target_cell = line.cells[col];

      if (target_cell.codepoint != cell.codepoint
	  || target_cell.face_id != cell.face_id
	  || target_cell.background != cell.background
	  || target_cell.foreground != cell.foreground)
	{
	  target_cell = cell;
	  needs_update_ = true;
	}
    }
}

void
DisplayUpdate::clear_to_eol (int row, int col)
{
  if (row >= 0 && row < matrix_.rows && col >= 0
      && col < matrix_.cols)
    {
      auto &line = matrix_.lines[row];
      for (int c = col; c < matrix_.cols; ++c)
	{
	  auto &cell = line.cells[c];
	  cell.codepoint = U' ';
	  cell.face_id = 0;
	  cell.background = 0;
	  cell.foreground = 7;
	  cell.wide = false;
	  cell.padding = false;
	}
      needs_update_ = true;
    }
}

void
DisplayUpdate::clear_to_eos (int row, int col)
{
  if (row >= 0 && row < matrix_.rows)
    {
      for (int r = row; r < matrix_.rows; ++r)
	{
	  auto &line = matrix_.lines[r];
	  int start = (r == row) ? col : 0;
	  for (int c = start; c < matrix_.cols; ++c)
	    {
	      auto &cell = line.cells[c];
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
      needs_update_ = true;
    }
}

void
DisplayUpdate::insert_lines (int row, int count)
{
  if (row >= 0 && row < matrix_.rows && count > 0)
    {
      int lines_to_move = matrix_.rows - row - count;
      if (lines_to_move > 0)
	{
	  std::memmove (&matrix_.lines[row + count],
			&matrix_.lines[row],
			lines_to_move * sizeof (DisplayLine));
	}

      for (int i = 0; i < count && (row + i) < matrix_.rows; ++i)
	{
	  auto &line = matrix_.lines[row + i];
	  for (auto &cell : line.cells)
	    {
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
      needs_update_ = true;
    }
}

void
DisplayUpdate::delete_lines (int row, int count)
{
  if (row >= 0 && row < matrix_.rows && count > 0)
    {
      int lines_to_move = matrix_.rows - row - count;
      if (lines_to_move > 0)
	{
	  std::memmove (&matrix_.lines[row],
			&matrix_.lines[row + count],
			lines_to_move * sizeof (DisplayLine));
	}

      for (int i = matrix_.rows - count; i < matrix_.rows; ++i)
	{
	  auto &line = matrix_.lines[i];
	  for (auto &cell : line.cells)
	    {
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
      needs_update_ = true;
    }
}

void
DisplayUpdate::scroll_region (int top, int bottom, int lines)
{
  if (top < 0)
    top = 0;
  if (bottom >= matrix_.rows)
    bottom = matrix_.rows - 1;

  if (top >= bottom)
    return;

  int region_height = bottom - top + 1;
  lines %= region_height;

  if (lines == 0)
    return;

  if (lines > 0)
    {
      int lines_to_move = region_height - lines;
      std::memmove (&matrix_.lines[top], &matrix_.lines[top + lines],
		    lines_to_move * sizeof (DisplayLine));

      for (int i = bottom - lines + 1; i <= bottom; ++i)
	{
	  auto &line = matrix_.lines[i];
	  for (auto &cell : line.cells)
	    {
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
    }
  else
    {
      int lines_to_move = region_height + lines;
      std::memmove (&matrix_.lines[top - lines], &matrix_.lines[top],
		    lines_to_move * sizeof (DisplayLine));

      for (int i = top; i < top - lines; ++i)
	{
	  auto &line = matrix_.lines[i];
	  for (auto &cell : line.cells)
	    {
	      cell.codepoint = U' ';
	      cell.face_id = 0;
	      cell.background = 0;
	      cell.foreground = 7;
	      cell.wide = false;
	      cell.padding = false;
	    }
	}
    }

  needs_update_ = true;
}

DisplayRenderer &
DisplayRenderer::instance ()
{
  static DisplayRenderer instance;
  return instance;
}

void
DisplayRenderer::set_terminal_backend (TerminalBackend *backend)
{
  backend_ = backend;
}

void
DisplayRenderer::init ()
{
  if (!backend_)
    return;

  backend_->init ();
  current_matrix_ = {};
  desired_matrix_ = {};
}

void
DisplayRenderer::shutdown ()
{
  if (backend_)
    {
      backend_->cleanup ();
      backend_ = nullptr;
    }
}

void
DisplayRenderer::update_display (const DisplayMatrix &matrix)
{
  if (!backend_)
    return;

  desired_matrix_ = matrix;
  current_matrix_.rows = matrix.rows;
  current_matrix_.cols = matrix.cols;

  current_matrix_.lines.resize (matrix.rows);
  for (int i = 0; i < matrix.rows; ++i)
    {
      auto &line = current_matrix_.lines[i];
      line.cells.resize (matrix.cols);
      line.y = i;
      line.x = 0;
      std::memcpy (line.cells.data (), matrix.lines[i].cells.data (),
		   matrix.cols * sizeof (DisplayCell));
    }
}

void
DisplayRenderer::flush_updates ()
{
  if (!backend_)
    return;

  for (int row = 0; row < current_matrix_.rows; ++row)
    {
      for (int col = 0; col < current_matrix_.cols; ++col)
	{
	  auto &current = current_matrix_.lines[row].cells[col];
	  auto &desired = desired_matrix_.lines[row].cells[col];

	  if (current.codepoint != desired.codepoint
	      || current.face_id != desired.face_id
	      || current.background != desired.background
	      || current.foreground != desired.foreground)
	    {
	      TerminalGlyph glyph{ .codepoint = desired.codepoint,
				   .face_id = desired.face_id,
				   .background = desired.background,
				   .foreground = desired.foreground,
				   .wide = desired.wide,
				   .padding = desired.padding };
	      std::vector<TerminalGlyph> glyphs;
	      glyphs.push_back (glyph);
	      backend_->write_glyphs (glyphs);
	      current = desired;
	    }
	}
    }
}

int
DisplayRenderer::get_rows () const noexcept
{
  return current_matrix_.rows;
}

int
DisplayRenderer::get_cols () const noexcept
{
  return current_matrix_.cols;
}

}

extern "C"
{
  int display_init_c ()
  {
    emacs::DisplayRenderer::instance ().init ();
    return 0;
  }

  int display_shutdown_c ()
  {
    emacs::DisplayRenderer::instance ().shutdown ();
    return 0;
  }

  int display_update_c (int *rows, int *cols)
  {
    if (rows)
      *rows = emacs::DisplayRenderer::instance ().get_rows ();
    if (cols)
      *cols = emacs::DisplayRenderer::instance ().get_cols ();
    return 0;
  }
}
