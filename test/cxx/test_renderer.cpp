#include <cassert>
#include <iostream>
#include <string>
#include "../../src/allocator.hpp"
#include "../../src/grid.hpp"
#include "../../src/renderer.hpp"

using namespace emacs::tui;

void
test_construction ()
{
  Renderer renderer;
  assert (renderer.output ().empty ());
  std::cout << "test_construction passed\n";
}

void
test_clear_screen ()
{
  Renderer renderer;
  renderer.clear_screen ();

  const auto &output = renderer.output ();
  assert (!output.empty ());
  assert (output.find ("\033[2J") != std::string::npos);

  std::cout << "test_clear_screen passed\n";
}

void
test_cursor_visibility ()
{
  Renderer renderer;

  renderer.show_cursor (false);
  assert (renderer.output ().find ("\033[?25l") != std::string::npos);

  renderer.reset_output ();

  renderer.show_cursor (true);
  assert (renderer.output ().find ("\033[?25h") != std::string::npos);

  std::cout << "test_cursor_visibility passed\n";
}

void
test_cursor_movement ()
{
  Renderer renderer;

  renderer.move_cursor (5, 10);

  const auto &output = renderer.output ();
  assert (output.find ("\033[6;11H") != std::string::npos);

  std::cout << "test_cursor_movement passed\n";
}

void
test_render_empty_grid ()
{
  Grid grid (10, 20);
  Renderer renderer;

  grid.swap_buffers ();

  renderer.render (grid);

  assert (renderer.output ().empty ());

  std::cout << "test_render_empty_grid passed\n";
}

void
test_render_single_cell ()
{
  Grid grid (10, 20);
  Renderer renderer;

  Cell cell ("X");
  grid.set_cell (5, 10, cell);
  grid.swap_buffers ();

  renderer.render (grid);

  const auto &output = renderer.output ();
  assert (!output.empty ());
  assert (output.find ("\033[") != std::string::npos);
  assert (output.find ("X") != std::string::npos);

  std::cout << "test_render_single_cell passed\n";
}

void
test_render_with_attributes ()
{
  Grid grid (10, 20);
  Renderer renderer;

  CellAttributes attrs;
  attrs.flags = CellAttributes::BOLD | CellAttributes::UNDERLINE;

  Cell cell ("B", attrs);
  grid.set_cell (2, 3, cell);
  grid.swap_buffers ();

  renderer.render (grid);

  const auto &output = renderer.output ();
  assert (!output.empty ());
  assert (output.find ("\033[0") != std::string::npos);
  assert (output.find (";1") != std::string::npos);
  assert (output.find (";4") != std::string::npos);

  std::cout << "test_render_with_attributes passed\n";
}

void
test_render_dirty_region ()
{
  Grid grid (10, 20);
  Renderer renderer;

  grid.set_cell (0, 0, Cell ("A"));
  grid.set_cell (0, 1, Cell ("B"));
  grid.set_cell (1, 0, Cell ("C"));
  grid.swap_buffers ();

  renderer.render (grid);

  const auto &output = renderer.output ();
  assert (!output.empty ());
  assert (output.find ("A") != std::string::npos);
  assert (output.find ("B") != std::string::npos);
  assert (output.find ("C") != std::string::npos);

  std::cout << "test_render_dirty_region passed\n";
}

void
test_output_reset ()
{
  Renderer renderer;
  renderer.clear_screen ();

  assert (!renderer.output ().empty ());

  renderer.reset_output ();
  assert (renderer.output ().empty ());

  std::cout << "test_output_reset passed\n";
}

int
main ()
{
  std::cout << "Running Renderer tests...\n\n";

  test_construction ();
  test_clear_screen ();
  test_cursor_visibility ();
  test_cursor_movement ();
  test_render_empty_grid ();
  test_render_single_cell ();
  test_render_with_attributes ();
  test_render_dirty_region ();
  test_output_reset ();

  std::cout << "\nAll Renderer tests passed!\n";
  return 0;
}
