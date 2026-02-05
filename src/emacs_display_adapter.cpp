// emacs_display_adapter.cpp - Implementation of Emacs-to-Grid bridge

#include "emacs_display_adapter.hpp"
#include <cstring>
#include <iostream>
#include "renderer.hpp"

#ifndef EMACS_STRUCTS_DEFINED
struct face
{
  unsigned long foreground;
  unsigned long background;
};

struct glyph
{
  union
  {
    int ch;
  } u;
};
#endif

namespace emacs
{

using namespace tui;

tui::CellAttributes
EmacsDisplayAdapter::face_to_attributes (const struct face *face)
{
  CellAttributes attr;

  if (!face)
    {
      return attr;
    }

  attr.fg = color_index_to_ansi (face->foreground);
  attr.bg = color_index_to_ansi (face->background);

  return attr;
}

uint8_t
EmacsDisplayAdapter::color_index_to_ansi (unsigned long color)
{
  static const uint8_t color_map[16]
    = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };

  if (color < 16)
    {
      return color_map[color];
    }

  return 7;
}

char32_t
EmacsDisplayAdapter::glyph_to_codepoint (const struct glyph *glyph)
{
  if (!glyph)
    {
      return U' ';
    }

  return static_cast<char32_t> (glyph->u.ch);
}

void
EmacsDisplayAdapter::render_glyph (tui::Grid &grid, int row, int col,
				   const struct glyph *glyph,
				   const struct face *face)
{
  if (!glyph)
    {
      return;
    }

  char32_t codepoint = glyph_to_codepoint (glyph);

  if (codepoint < 32 || codepoint > 126)
    {
      codepoint = U' ';
    }

  CellAttributes attr = face_to_attributes (face);

  char utf8[2] = { static_cast<char> (codepoint), '\0' };
  Cell cell (std::string (utf8), attr, 1);
  grid.set_cell (row, col, cell);
}

void
EmacsDisplayAdapter::render_glyph_row (
  tui::Grid &grid, int row, const struct glyph_row *glyph_row)
{
  (void) grid;
  (void) row;
  (void) glyph_row;
}

void
EmacsDisplayAdapter::sync_window_to_grid (tui::Grid &grid,
					  struct window *w)
{
  (void) grid;
  (void) w;
}

void
EmacsDisplayAdapter::redisplay_frame (struct frame *f)
{
  (void) f;
}

void
EmacsDisplayAdapter::render_text_simple (tui::Grid &grid, int row,
					 int col, const char *text)
{
  if (!text)
    {
      return;
    }

  CellAttributes attr;
  int x = col;

  for (const char *p = text; *p; ++p)
    {
      if (x >= grid.cols ())
	{
	  break;
	}

      char utf8[2] = { *p, '\0' };
      Cell cell (std::string (utf8), attr, 1);
      grid.set_cell (row, x, cell);
      ++x;
    }
}

extern "C"
{
  void emacs_cxx_render_glyph_row (void *grid_ptr, int row,
				   struct glyph_row *glyph_row)
  {
    auto *grid = static_cast<Grid *> (grid_ptr);
    EmacsDisplayAdapter adapter;
    adapter.render_glyph_row (*grid, row, glyph_row);
  }

  void emacs_cxx_flush_grid (void *grid_ptr)
  {
    auto *grid = static_cast<Grid *> (grid_ptr);
    Renderer renderer;
    renderer.render (*grid);
  }

  void *emacs_cxx_create_grid (int rows, int cols)
  {
    return new Grid (rows, cols);
  }

  void emacs_cxx_destroy_grid (void *grid_ptr)
  {
    delete static_cast<Grid *> (grid_ptr);
  }
}

}
