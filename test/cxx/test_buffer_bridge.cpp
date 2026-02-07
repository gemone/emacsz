// test/cxx/test_buffer_bridge.cpp
// Phase 6.5: BufferBridge tests

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "../../src/emacs_buffer_bridge.hpp"

using namespace emacs;
using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

namespace
{

struct GlyphMatrixOwner
{
  glyph_matrix matrix;
  gc_vector_t<glyph_row> rows;
  gc_vector_t<glyph> glyphs;

  GlyphMatrixOwner (int nrows, int ncols)
      : matrix{}, rows (static_cast<size_t> (nrows)),
	glyphs (static_cast<size_t> (nrows * ncols))
  {
    matrix.rows = rows.data ();
    matrix.nrows = nrows;

    for (int r = 0; r < nrows; ++r)
      {
	rows[static_cast<size_t> (r)].glyphs[TEXT_AREA]
	  = glyphs.data () + r * ncols;
	rows[static_cast<size_t> (r)].used[TEXT_AREA] = 0;
	rows[static_cast<size_t> (r)].enabled_p = false;
      }
  }
};

void
assert_cell_char (const Grid &grid, int row, int col, const char *ch)
{
  auto cell = grid.get_back_cell (row, col);
  assert (cell.has_value ());
  assert (cell->ch == ch);
}

void
assert_cell_attrs (const Grid &grid, int row, int col,
		   const CellAttributes &attrs)
{
  auto cell = grid.get_back_cell (row, col);
  assert (cell.has_value ());
  assert (cell->attrs == attrs);
}

} // namespace

void
test_render_empty_buffer ()
{
  printf ("Testing render empty buffer...\n");

  EmacsBuffer buffer ("empty");
  Grid grid (2, 4);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 1, 2, 4);

  for (int row = 0; row < 2; ++row)
    {
      for (int col = 0; col < 4; ++col)
	{
	  assert_cell_char (grid, row, col, " ");
	}
    }

  printf ("✓ Empty buffer render passed\n");
}

void
test_render_single_line ()
{
  printf ("Testing render single line...\n");

  EmacsBuffer buffer ("buf", "Hello");
  Grid grid (2, 8);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 1, 2, 8);

  assert_cell_char (grid, 0, 0, "H");
  assert_cell_char (grid, 0, 1, "e");
  assert_cell_char (grid, 0, 2, "l");
  assert_cell_char (grid, 0, 3, "l");
  assert_cell_char (grid, 0, 4, "o");
  assert_cell_char (grid, 0, 5, " ");

  printf ("✓ Single line render passed\n");
}

void
test_render_multiple_lines ()
{
  printf ("Testing render multiple lines...\n");

  EmacsBuffer buffer ("buf", "Hello\nWorld");
  Grid grid (3, 6);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 1, 3, 6);

  assert_cell_char (grid, 0, 0, "H");
  assert_cell_char (grid, 0, 4, "o");
  assert_cell_char (grid, 1, 0, "W");
  assert_cell_char (grid, 1, 4, "d");
  assert_cell_char (grid, 2, 0, " ");

  printf ("✓ Multiple lines render passed\n");
}

void
test_render_with_line_wrap ()
{
  printf ("Testing render line wrap...\n");

  EmacsBuffer buffer ("buf", "ABCDEFGHIJK");
  Grid grid (3, 4);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 1, 3, 4);

  assert_cell_char (grid, 0, 0, "A");
  assert_cell_char (grid, 0, 3, "D");
  assert_cell_char (grid, 1, 0, "E");
  assert_cell_char (grid, 1, 3, "H");
  assert_cell_char (grid, 2, 0, "I");
  assert_cell_char (grid, 2, 2, "K");

  printf ("✓ Line wrap render passed\n");
}

void
test_render_with_offset ()
{
  printf ("Testing render with offset...\n");

  EmacsBuffer buffer ("buf", "Hi");
  Grid grid (4, 6);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 1, 2, 4, 1, 2);

  assert_cell_char (grid, 1, 2, "H");
  assert_cell_char (grid, 1, 3, "i");
  assert_cell_char (grid, 0, 0, " ");

  printf ("✓ Offset render passed\n");
}

void
test_render_with_window_start ()
{
  printf ("Testing render with window start...\n");

  EmacsBuffer buffer ("buf", "ABCDEFG");
  Grid grid (2, 4);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buffer, grid, 3, 2, 4);

  assert_cell_char (grid, 0, 0, "C");
  assert_cell_char (grid, 0, 3, "F");

  printf ("✓ Window start render passed\n");
}

void
test_render_with_attributes ()
{
  printf ("Testing render with attributes...\n");

  EmacsBuffer buffer ("buf", "XY");
  Grid grid (1, 4);
  BufferBridge bridge;

  CellAttributes attrs;
  attrs.fg = 4;
  attrs.bg = 2;
  attrs.flags = CellAttributes::BOLD;

  bridge.render_buffer_to_grid (buffer, grid, 1, 1, 4, attrs);

  assert_cell_char (grid, 0, 0, "X");
  assert_cell_attrs (grid, 0, 0, attrs);
  assert_cell_attrs (grid, 0, 1, attrs);

  printf ("✓ Attributes render passed\n");
}

void
test_cursor_pos_beginning ()
{
  printf ("Testing cursor position at beginning...\n");

  EmacsBuffer buffer ("buf", "Hello");
  buffer.set_point (1);
  BufferBridge bridge;

  auto pos = bridge.map_point_to_grid (buffer, 1, 2, 4);
  assert (pos.row == 0);
  assert (pos.col == 0);

  printf ("✓ Cursor beginning passed\n");
}

void
test_cursor_pos_middle ()
{
  printf ("Testing cursor position in middle...\n");

  EmacsBuffer buffer ("buf", "Hello");
  buffer.set_point (4);
  BufferBridge bridge;

  auto pos = bridge.map_point_to_grid (buffer, 1, 2, 10);
  assert (pos.row == 0);
  assert (pos.col == 3);

  printf ("✓ Cursor middle passed\n");
}

void
test_cursor_pos_after_newline ()
{
  printf ("Testing cursor position after newline...\n");

  EmacsBuffer buffer ("buf", "Hi\nThere");
  buffer.set_point (4);
  BufferBridge bridge;

  auto pos = bridge.map_point_to_grid (buffer, 1, 4, 10);
  assert (pos.row == 1);
  assert (pos.col == 0);

  printf ("✓ Cursor after newline passed\n");
}

void
test_cursor_pos_wrapped_line ()
{
  printf ("Testing cursor position with wrap...\n");

  EmacsBuffer buffer ("buf", "ABCDE");
  buffer.set_point (5);
  BufferBridge bridge;

  auto pos = bridge.map_point_to_grid (buffer, 1, 3, 3);
  assert (pos.row == 1);
  assert (pos.col == 1);

  printf ("✓ Cursor wrap passed\n");
}

void
test_cursor_pos_not_visible ()
{
  printf ("Testing cursor not visible...\n");

  EmacsBuffer buffer ("buf", "Hello");
  buffer.set_point (2);
  BufferBridge bridge;

  auto pos = bridge.map_point_to_grid (buffer, 3, 1, 4);
  assert (!pos.is_visible ());

  printf ("✓ Cursor not visible passed\n");
}

void
test_extract_visible_lines ()
{
  printf ("Testing extract visible lines...\n");

  EmacsBuffer buffer ("buf", "One\nTwo\nThree");
  BufferBridge bridge;

  auto lines = bridge.extract_visible_lines (buffer, 1, 3, 10);
  assert (lines.size () == 3);
  assert (lines[0] == "One");
  assert (lines[1] == "Two");
  assert (lines[2] == "Three");

  printf ("✓ Extract lines passed\n");
}

void
test_extract_lines_with_wrap ()
{
  printf ("Testing extract lines with wrap...\n");

  EmacsBuffer buffer ("buf", "ABCDE");
  BufferBridge bridge;

  auto lines = bridge.extract_visible_lines (buffer, 1, 3, 2);
  assert (lines.size () == 3);
  assert (lines[0] == "AB");
  assert (lines[1] == "CD");
  assert (lines[2] == "E");

  printf ("✓ Extract lines wrap passed\n");
}

void
test_populate_glyph_matrix ()
{
  printf ("Testing populate glyph matrix...\n");

  EmacsBuffer buffer ("buf", "ABC\nDE");
  BufferBridge bridge;
  GlyphMatrixOwner owner (3, 4);

  bridge.populate_glyph_matrix (buffer, &owner.matrix, 1, 3, 4);

  assert (owner.rows[0].enabled_p);
  assert (owner.rows[0].used[TEXT_AREA] == 4);
  assert (owner.rows[0].glyphs[TEXT_AREA][0].ch == 'A');
  assert (owner.rows[1].glyphs[TEXT_AREA][0].ch == 'D');
  assert (owner.rows[2].glyphs[TEXT_AREA][0].ch == ' ');

  printf ("✓ Populate glyph matrix passed\n");
}

void
test_tab_rendering ()
{
  printf ("Testing tab rendering...\n");

  EmacsBuffer buffer ("buf", "A\tB");
  BufferBridge bridge;
  Grid grid (1, 10);

  bridge.render_buffer_to_grid (buffer, grid, 1, 1, 10);

  assert_cell_char (grid, 0, 0, "A");
  assert_cell_char (grid, 0, 1, " ");
  assert_cell_char (grid, 0, 7, " ");
  assert_cell_char (grid, 0, 8, "B");

  printf ("✓ Tab rendering passed\n");
}

void
test_stats ()
{
  printf ("Testing stats...\n");

  EmacsBuffer buffer ("buf", "Hello\nWorld");
  BufferBridge bridge;
  Grid grid (2, 6);

  bridge.reset_stats ();
  bridge.render_buffer_to_grid (buffer, grid, 1, 2, 6);

  assert (bridge.lines_rendered () == 2);
  assert (bridge.cells_written () == 12);

  bridge.reset_stats ();
  assert (bridge.lines_rendered () == 0);
  assert (bridge.cells_written () == 0);

  printf ("✓ Stats passed\n");
}

int
main ()
{
  printf ("Running BufferBridge tests...\n\n");

  test_render_empty_buffer ();
  test_render_single_line ();
  test_render_multiple_lines ();
  test_render_with_line_wrap ();
  test_render_with_offset ();
  test_render_with_window_start ();
  test_render_with_attributes ();
  test_cursor_pos_beginning ();
  test_cursor_pos_middle ();
  test_cursor_pos_after_newline ();
  test_cursor_pos_wrapped_line ();
  test_cursor_pos_not_visible ();
  test_extract_visible_lines ();
  test_extract_lines_with_wrap ();
  test_populate_glyph_matrix ();
  test_tab_rendering ();
  test_stats ();

  printf ("\n✅ All BufferBridge tests passed!\n");
  return 0;
}
