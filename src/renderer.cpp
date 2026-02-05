#include "renderer.hpp"
#include <cstdio>
#include <unistd.h>

namespace emacs
{
namespace tui
{

Renderer::Renderer ()
    : output_ (), current_attrs_ (), current_fg_ (), current_bg_ (),
      use_alternate_screen_ (false), last_cursor_row_ (-1),
      last_cursor_col_ (-1)
{
}

Renderer::~Renderer () {}

void
Renderer::render (const Grid &grid)
{
  const auto &dirty = grid.dirty_region ();
  if (!dirty.has_value ())
    {
      return;
    }

  const Rect &region = dirty.value ();

  for (int row = region.row; row < region.row + region.rows; ++row)
    {
      for (int col = region.col; col < region.col + region.cols;
	   ++col)
	{
	  auto cell_opt = grid.get_cell (row, col);
	  if (!cell_opt.has_value ())
	    {
	      continue;
	    }

	  const Cell &cell = cell_opt.value ();

	  emit_cursor_position (row, col);

	  if (cell.attrs != current_attrs_)
	    {
	      emit_sgr_attributes (cell.attrs);
	      current_attrs_ = cell.attrs;
	    }

	  if (!cell.ch.empty ())
	    {
	      append (cell.ch);
	    }
	  else
	    {
	      append_char (' ');
	    }
	}
    }
}

void
Renderer::clear_screen ()
{
  emit_clear_screen ();
  current_attrs_ = CellAttributes ();
  last_cursor_row_ = -1;
  last_cursor_col_ = -1;
}

void
Renderer::show_cursor (bool show)
{
  emit_show_cursor (show);
}

void
Renderer::move_cursor (int row, int col)
{
  emit_cursor_position (row, col);
}

void
Renderer::flush ()
{
  if (!output_.empty ())
    {
      ssize_t written
	= write (STDOUT_FILENO, output_.c_str (), output_.size ());
      (void) written;
      output_.clear ();
    }
}

void
Renderer::emit_sgr_reset ()
{
  append ("\033[0m");
}

void
Renderer::emit_sgr_attributes (const CellAttributes &attrs)
{
  append ("\033[0");

  if (attrs.flags & CellAttributes::BOLD)
    append (";1");
  if (attrs.flags & CellAttributes::ITALIC)
    append (";3");
  if (attrs.flags & CellAttributes::UNDERLINE)
    append (";4");
  if (attrs.flags & CellAttributes::REVERSE)
    append (";7");

  append ("m");
}

void
Renderer::emit_cursor_position (int row, int col)
{
  if (last_cursor_row_ == row && last_cursor_col_ == col)
    {
      return;
    }

  char buf[32];
  snprintf (buf, sizeof (buf), "\033[%d;%dH", row + 1, col + 1);
  append (buf);

  last_cursor_row_ = row;
  last_cursor_col_ = col;
}

void
Renderer::emit_clear_screen ()
{
  append ("\033[2J");
}

void
Renderer::emit_show_cursor (bool show)
{
  if (show)
    {
      append ("\033[?25h");
    }
  else
    {
      append ("\033[?25l");
    }
}

void
Renderer::append (const char *str)
{
  output_.append (str);
}

void
Renderer::append (std::string_view str)
{
  output_.append (str);
}

void
Renderer::append_char (char ch)
{
  output_.push_back (ch);
}

}
}
