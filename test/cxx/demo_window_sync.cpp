// test/cxx/demo_window_sync.cpp
// Visual demonstration of Emacs window synchronization to Grid

#include <cstdio>
#include <cstring>
#include "../../src/emacs_window_adapter.hpp"
#include "../../src/grid.hpp"
#include "../../src/renderer.hpp"

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
create_sample_window ()
{
  MockWindow *mw = new MockWindow ();

  mw->base.total_cols = 40;
  mw->base.total_lines = 8;
  mw->base.pixel_width = 40 * 8;
  mw->base.pixel_height = 8 * 16;
  mw->base.left_col = 0;
  mw->base.top_line = 0;
  mw->base.contents = reinterpret_cast<Lisp_Object> (&mw->buf);
  mw->base.start = reinterpret_cast<Lisp_Object> (0);
  mw->base.pointm = reinterpret_cast<Lisp_Object> (45);

  mw->matrix.rows = mw->rows;
  mw->matrix.nrows = 8;
  mw->base.current_matrix = &mw->matrix;

  const char *lines[]
    = { "╔══════════════════════════════════════╗",
	"║  Emacs Window Adapter Demo           ║",
	"║                                      ║",
	"║  This demonstrates synchronizing     ║",
	"║  an Emacs window to a Grid.          ║",
	"║                                      ║",
	"║  Cursor position: row=1, col=5       ║",
	"╚══════════════════════════════════════╝" };

  for (int i = 0; i < 8; ++i)
    {
      mw->rows[i].glyphs[TEXT_AREA] = mw->glyphs_data[i];
      mw->rows[i].used[TEXT_AREA] = 40;
      mw->rows[i].enabled_p = true;

      for (int j = 0; j < 40; ++j)
	{
	  if (j < (int) strlen (lines[i]))
	    {
	      mw->glyphs_data[i][j].ch = lines[i][j];
	    }
	  else
	    {
	      mw->glyphs_data[i][j].ch = ' ';
	    }
	  mw->glyphs_data[i][j].face_id = 0;
	}
    }

  mw->buf.text_data = nullptr;
  mw->buf.text_length = 0;
  mw->buf.pt = 45;

  return mw;
}

int
main ()
{
  printf ("═══════════════════════════════════════════════════\n");
  printf ("   Emacs Window Adapter - Synchronization Demo\n");
  printf ("═══════════════════════════════════════════════════\n\n");

  printf ("Creating mock Emacs window (40x8)...\n");
  MockWindow *mw = create_sample_window ();

  printf ("Window properties:\n");
  printf ("  Dimensions: %d cols × %d lines\n", mw->base.total_cols,
	  mw->base.total_lines);
  printf ("  Position: (%d, %d)\n", mw->base.left_col,
	  mw->base.top_line);
  printf ("  Window start: %ld\n",
	  reinterpret_cast<ptrdiff_t> (mw->base.start));
  printf ("  Point (cursor): %ld\n",
	  reinterpret_cast<ptrdiff_t> (mw->base.pointm));

  printf ("\nCreating adapter and grid...\n");
  EmacsWindowAdapter adapter;
  Grid grid (8, 40);

  auto dims = adapter.get_window_dimensions (&mw->base);
  printf ("  Extracted dimensions: %d × %d\n", dims.width,
	  dims.height);

  auto cursor_pos = adapter.get_cursor_position (&mw->base);
  printf ("  Cursor position: row=%d, col=%d\n", cursor_pos.row,
	  cursor_pos.col);

  printf ("\nSynchronizing window to grid...\n");
  adapter.sync_window_to_grid (&mw->base, grid);
  grid.swap_buffers ();

  printf ("\nRendering grid to terminal:\n\n");
  Renderer renderer;
  renderer.render (grid);
  renderer.flush ();

  printf ("\n\n");
  printf ("Grid state:\n");
  printf ("  Dimensions: %d rows × %d cols\n", grid.rows (),
	  grid.cols ());
  printf ("  Has changes: %s\n", grid.is_dirty () ? "yes" : "no");

  printf ("\nSample cells:\n");
  for (int row = 0; row < 3; ++row)
    {
      printf ("  Row %d: ", row);
      for (int col = 0; col < 10; ++col)
	{
	  auto cell_opt = grid.get_cell (row, col);
	  if (cell_opt)
	    {
	      printf ("%s", cell_opt->ch.c_str ());
	    }
	}
      printf ("...\n");
    }

  printf ("\n═══════════════════════════════════════════════════\n");
  printf ("Demo complete! Window successfully synchronized.\n");
  printf ("═══════════════════════════════════════════════════\n");

  delete mw;
  return 0;
}
