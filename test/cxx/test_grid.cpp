// test/cxx/test_grid.cpp
// Unit tests for Grid system

#include <cassert>
#include <cstdlib>
#include <iostream>
#include "../../src/grid.hpp"

using namespace emacs::tui;

// Test stubs for Emacs GC functions
extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }

  void lisp_free (void *ptr) { std::free (ptr); }

  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

void
test_grid_construction ()
{
  Grid g (10, 20);
  assert (g.rows () == 10);
  assert (g.cols () == 20);
  assert (!g.is_dirty ());
  std::cout << "✓ Grid construction test passed\n";
}

void
test_grid_set_get_cell ()
{
  Grid g (5, 5);

  Cell c ("A", CellAttributes{ 15, 0, 0 }, 1);
  bool result = g.set_cell (2, 3, c);
  assert (result);

  auto back_cell = g.get_back_cell (2, 3);
  assert (back_cell.has_value ());
  assert (back_cell->ch == "A");

  g.swap_buffers ();

  auto front_cell = g.get_cell (2, 3);
  assert (front_cell.has_value ());
  assert (front_cell->ch == "A");

  std::cout << "✓ Grid set/get cell test passed\n";
}

void
test_grid_dirty_tracking ()
{
  Grid g (10, 10);

  assert (!g.is_dirty ());

  Cell c ("X");
  bool result = g.set_cell (5, 5, c);
  assert (result);

  assert (g.is_dirty ());

  auto dirty = g.dirty_region ();
  assert (dirty.has_value ());
  assert (dirty->contains (5, 5));

  std::cout << "✓ Grid dirty tracking test passed\n";
}

void
test_grid_clear ()
{
  Grid g (4, 4);

  Cell c ("*");
  g.set_cell (1, 1, c);
  g.set_cell (2, 2, c);

  g.clear ();

  auto cell = g.get_back_cell (1, 1);
  assert (cell.has_value ());
  assert (cell->ch == " ");

  std::cout << "✓ Grid clear test passed\n";
}

void
test_grid_resize ()
{
  Grid g (5, 5);

  Cell c ("R");
  g.set_cell (2, 2, c);

  g.resize (10, 10);

  assert (g.rows () == 10);
  assert (g.cols () == 10);

  std::cout << "✓ Grid resize test passed\n";
}

void
test_grid_bounds_checking ()
{
  Grid g (3, 3);

  Cell c ("B");
  assert (!g.set_cell (-1, 0, c));
  assert (!g.set_cell (0, -1, c));
  assert (!g.set_cell (5, 0, c));
  assert (!g.set_cell (0, 5, c));

  assert (!g.get_cell (-1, 0).has_value ());
  assert (!g.get_cell (0, -1).has_value ());
  assert (!g.get_cell (5, 0).has_value ());
  assert (!g.get_cell (0, 5).has_value ());

  std::cout << "✓ Grid bounds checking test passed\n";
}

int
main ()
{
  std::cout << "Running Grid system tests...\n\n";

  test_grid_construction ();
  test_grid_set_get_cell ();
  test_grid_dirty_tracking ();
  test_grid_clear ();
  test_grid_resize ();
  test_grid_bounds_checking ();

  std::cout << "\n✅ All Grid tests passed!\n";
  return 0;
}
