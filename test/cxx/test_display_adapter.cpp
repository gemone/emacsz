#include <cassert>
#include <iostream>
#include "../../src/grid.hpp"
#include "../../src/renderer.hpp"

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

#include "../../src/emacs_display_adapter.hpp"

using namespace emacs;
using namespace tui;

struct glyph
{
  union
  {
    int ch;
  } u;
};

void
test_color_mapping ()
{
  for (unsigned long color = 0; color < 16; ++color)
    {
      uint8_t ansi = EmacsDisplayAdapter::color_index_to_ansi (color);
      assert (ansi == color);
    }

  uint8_t fallback = EmacsDisplayAdapter::color_index_to_ansi (999);
  assert (fallback == 7);

  std::cout << "test_color_mapping passed\n";
}

void
test_face_to_attributes_null ()
{
  auto attr = EmacsDisplayAdapter::face_to_attributes (nullptr);

  assert (attr.fg == 7);
  assert (attr.bg == 0);

  std::cout << "test_face_to_attributes_null passed\n";
}

void
test_face_to_attributes_colors ()
{
  struct face test_face;
  test_face.foreground = 12;
  test_face.background = 4;

  auto attr = EmacsDisplayAdapter::face_to_attributes (&test_face);

  assert (attr.fg == 12);
  assert (attr.bg == 4);

  std::cout << "test_face_to_attributes_colors passed\n";
}

void
test_glyph_to_codepoint_null ()
{
  char32_t cp = EmacsDisplayAdapter::glyph_to_codepoint (nullptr);
  assert (cp == U' ');

  std::cout << "test_glyph_to_codepoint_null passed\n";
}

void
test_glyph_to_codepoint_ascii ()
{
  struct glyph g;
  g.u.ch = 'A';

  char32_t cp = EmacsDisplayAdapter::glyph_to_codepoint (&g);
  assert (cp == U'A');

  std::cout << "test_glyph_to_codepoint_ascii passed\n";
}

void
test_render_simple_text ()
{
  Grid grid (5, 20);
  EmacsDisplayAdapter adapter;

  adapter.render_text_simple (grid, 0, 0, "Hello");

  grid.swap_buffers ();

  auto cell_h = grid.get_cell (0, 0);
  auto cell_e = grid.get_cell (0, 1);
  auto cell_l1 = grid.get_cell (0, 2);
  auto cell_l2 = grid.get_cell (0, 3);
  auto cell_o = grid.get_cell (0, 4);

  assert (cell_h.has_value () && cell_h->ch == "H");
  assert (cell_e.has_value () && cell_e->ch == "e");
  assert (cell_l1.has_value () && cell_l1->ch == "l");
  assert (cell_l2.has_value () && cell_l2->ch == "l");
  assert (cell_o.has_value () && cell_o->ch == "o");

  std::cout << "test_render_simple_text passed\n";
}

void
test_render_glyph ()
{
  Grid grid (5, 20);
  EmacsDisplayAdapter adapter;

  struct glyph g;
  g.u.ch = 'X';

  struct face f;
  f.foreground = 10;
  f.background = 1;

  adapter.render_glyph (grid, 2, 5, &g, &f);

  grid.swap_buffers ();

  auto cell = grid.get_cell (2, 5);
  assert (cell.has_value ());
  assert (cell->ch == "X");
  assert (cell->attrs.fg == 10);
  assert (cell->attrs.bg == 1);

  std::cout << "test_render_glyph passed\n";
}

void
test_render_glyph_control_char ()
{
  Grid grid (5, 20);
  EmacsDisplayAdapter adapter;

  struct glyph g;
  g.u.ch = '\n';

  adapter.render_glyph (grid, 0, 0, &g, nullptr);

  grid.swap_buffers ();

  auto cell = grid.get_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == " ");

  std::cout << "test_render_glyph_control_char passed\n";
}

void
test_c_wrappers ()
{
  void *grid_ptr = emacs_cxx_create_grid (10, 40);
  assert (grid_ptr != nullptr);

  emacs_cxx_destroy_grid (grid_ptr);

  std::cout << "test_c_wrappers passed\n";
}

int
main ()
{
  std::cout << "Running EmacsDisplayAdapter tests...\n\n";

  test_color_mapping ();
  test_face_to_attributes_null ();
  test_face_to_attributes_colors ();
  test_glyph_to_codepoint_null ();
  test_glyph_to_codepoint_ascii ();
  test_render_simple_text ();
  test_render_glyph ();
  test_render_glyph_control_char ();
  test_c_wrappers ();

  std::cout << "\n✅ All EmacsDisplayAdapter tests passed!\n";
  return 0;
}
