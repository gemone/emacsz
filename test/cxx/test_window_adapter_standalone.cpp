// test/cxx/test_window_adapter_standalone.cpp
// Standalone tests for EmacsWindowAdapter (Phase 5.3)

#include <cassert>
#include <cstdio>
#include <cstring>
#include "../../src/emacs_window_adapter.hpp"
#include "../../src/grid.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

struct MockWindow
{
  window base;
  buffer buf;
  glyph_matrix matrix;
  glyph_row rows[10];
  glyph glyphs_data[10][80];
};

MockWindow *
create_mock_window (int width, int height)
{
  MockWindow *mw = new MockWindow ();

  mw->base.total_cols = width;
  mw->base.total_lines = height;
  mw->base.pixel_width = width * 8;
  mw->base.pixel_height = height * 16;
  mw->base.left_col = 0;
  mw->base.top_line = 0;
  mw->base.contents = reinterpret_cast<Lisp_Object> (&mw->buf);
  mw->base.start = reinterpret_cast<Lisp_Object> (0);
  mw->base.pointm = reinterpret_cast<Lisp_Object> (0);

  mw->matrix.rows = mw->rows;
  mw->matrix.nrows = height;
  mw->base.current_matrix = &mw->matrix;

  for (int i = 0; i < height && i < 10; ++i)
    {
      mw->rows[i].glyphs[TEXT_AREA] = mw->glyphs_data[i];
      mw->rows[i].used[TEXT_AREA] = width;
      mw->rows[i].enabled_p = true;

      for (int j = 0; j < width && j < 80; ++j)
	{
	  mw->glyphs_data[i][j].ch = 'A' + (i * width + j) % 26;
	  mw->glyphs_data[i][j].face_id = 0;
	}
    }

  mw->buf.text_data = nullptr;
  mw->buf.text_length = 0;
  mw->buf.pt = 0;

  return mw;
}

void
test_get_window_dimensions ()
{
  printf ("Testing get_window_dimensions...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  auto dims = adapter.get_window_dimensions (&mw->base);

  assert (dims.width == 80);
  assert (dims.height == 24);
  assert (dims.left == 0);
  assert (dims.top == 0);

  delete mw;
  printf ("✓ Window dimensions test passed\n");
}

void
test_get_window_dimensions_null ()
{
  printf ("Testing get_window_dimensions with null...\n");

  EmacsWindowAdapter adapter;
  auto dims = adapter.get_window_dimensions (nullptr);

  assert (dims.width == 0);
  assert (dims.height == 0);

  printf ("✓ Null window dimensions test passed\n");
}

void
test_get_cursor_position ()
{
  printf ("Testing get_cursor_position...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  mw->base.start = reinterpret_cast<Lisp_Object> (0);
  mw->base.pointm = reinterpret_cast<Lisp_Object> (160);

  auto pos = adapter.get_cursor_position (&mw->base);

  assert (pos.row == 2);
  assert (pos.col == 0);

  delete mw;
  printf ("✓ Cursor position test passed\n");
}

void
test_get_cursor_position_mid_line ()
{
  printf ("Testing get_cursor_position mid-line...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  mw->base.start = reinterpret_cast<Lisp_Object> (0);
  mw->base.pointm = reinterpret_cast<Lisp_Object> (85);

  auto pos = adapter.get_cursor_position (&mw->base);

  assert (pos.row == 1);
  assert (pos.col == 5);

  delete mw;
  printf ("✓ Mid-line cursor position test passed\n");
}

void
test_get_window_start ()
{
  printf ("Testing get_window_start...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  mw->base.start = reinterpret_cast<Lisp_Object> (1000);

  ptrdiff_t start = adapter.get_window_start (&mw->base);
  assert (start == 1000);

  delete mw;
  printf ("✓ Window start test passed\n");
}

void
test_get_window_point ()
{
  printf ("Testing get_window_point...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  mw->base.pointm = reinterpret_cast<Lisp_Object> (500);

  ptrdiff_t point = adapter.get_window_point (&mw->base);
  assert (point == 500);

  delete mw;
  printf ("✓ Window point test passed\n");
}

void
test_sync_window_to_grid ()
{
  printf ("Testing sync_window_to_grid...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (10, 5);
  Grid grid (5, 10);

  adapter.sync_window_to_grid (&mw->base, grid);

  auto cell_opt = grid.get_back_cell (0, 0);
  assert (cell_opt.has_value ());
  assert (cell_opt->ch == "A");

  cell_opt = grid.get_back_cell (0, 1);
  assert (cell_opt.has_value ());
  assert (cell_opt->ch == "B");

  delete mw;
  printf ("✓ Window to grid sync test passed\n");
}

void
test_sync_window_to_grid_null ()
{
  printf ("Testing sync_window_to_grid with null...\n");

  EmacsWindowAdapter adapter;
  Grid grid (5, 10);

  adapter.sync_window_to_grid (nullptr, grid);

  printf ("✓ Null window sync test passed\n");
}

void
test_is_window_valid ()
{
  printf ("Testing is_window_valid...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  assert (adapter.is_window_valid (&mw->base) == true);
  assert (adapter.is_window_valid (nullptr) == false);

  mw->base.total_cols = 0;
  assert (adapter.is_window_valid (&mw->base) == false);

  delete mw;
  printf ("✓ Window validity test passed\n");
}

void
test_get_window_buffer ()
{
  printf ("Testing get_window_buffer...\n");

  EmacsWindowAdapter adapter;
  MockWindow *mw = create_mock_window (80, 24);

  buffer *buf = adapter.get_window_buffer (&mw->base);
  assert (buf == &mw->buf);

  buf = adapter.get_window_buffer (nullptr);
  assert (buf == nullptr);

  delete mw;
  printf ("✓ Get window buffer test passed\n");
}

void
test_c_api ()
{
  printf ("Testing C API...\n");

  void *adapter = emacs_cxx_create_window_adapter ();
  assert (adapter != nullptr);

  MockWindow *mw = create_mock_window (80, 24);
  Grid grid (24, 80);

  int width = 0, height = 0;
  emacs_cxx_get_window_dimensions (adapter, &mw->base, &width,
				   &height);
  assert (width == 80);
  assert (height == 24);

  mw->base.start = reinterpret_cast<Lisp_Object> (0);
  mw->base.pointm = reinterpret_cast<Lisp_Object> (85);

  int row = 0, col = 0;
  emacs_cxx_get_cursor_position (adapter, &mw->base, &row, &col);
  assert (row == 1);
  assert (col == 5);

  emacs_cxx_sync_window_to_grid (adapter, &mw->base, &grid);

  auto cell_opt = grid.get_back_cell (0, 0);
  assert (cell_opt.has_value ());
  assert (cell_opt->ch == "A");

  emacs_cxx_destroy_window_adapter (adapter);
  delete mw;

  printf ("✓ C API test passed\n");
}

int
main ()
{
  printf ("Running EmacsWindowAdapter tests...\n\n");

  test_get_window_dimensions ();
  test_get_window_dimensions_null ();
  test_get_cursor_position ();
  test_get_cursor_position_mid_line ();
  test_get_window_start ();
  test_get_window_point ();
  test_sync_window_to_grid ();
  test_sync_window_to_grid_null ();
  test_is_window_valid ();
  test_get_window_buffer ();
  test_c_api ();

  printf ("\n✅ All EmacsWindowAdapter tests passed!\n");
  return 0;
}
