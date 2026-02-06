// test/cxx/test_redisplay_adapter_standalone.cpp
// Standalone tests for EmacsRedisplayAdapter (Phase 5.5)

#include <cassert>
#include <cstddef>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_redisplay_adapter.hpp"
#include "../../src/emacs_window_adapter.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

struct face
{
  unsigned long foreground;
  unsigned long background;
};

void
fill_glyphs_from_text (struct glyph *glyphs, size_t count,
		       const char *text)
{
  if (!glyphs || !text)
    {
      return;
    }

  for (size_t i = 0; i < count; ++i)
    {
      glyphs[i].ch = static_cast<int> (text[i]);
      glyphs[i].face_id = 0;
    }
}

void
test_create_destroy ()
{
  printf ("Testing create/destroy...\n");

  EmacsRedisplayAdapter *adapter = new EmacsRedisplayAdapter ();
  assert (adapter != nullptr);
  assert (adapter->is_initialized () == false);
  delete adapter;

  printf ("✓ Create/destroy test passed\n");
}

void
test_init ()
{
  printf ("Testing init...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (24, 80);
  assert (ok == true);
  assert (adapter.is_initialized ());
  assert (adapter.frame_rows () == 24);
  assert (adapter.frame_cols () == 80);

  printf ("✓ Init test passed\n");
}

void
test_shutdown ()
{
  printf ("Testing shutdown...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (10, 10);
  assert (ok == true);
  adapter.shutdown ();
  assert (!adapter.is_initialized ());

  printf ("✓ Shutdown test passed\n");
}

void
test_clear_frame ()
{
  printf ("Testing clear_frame...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (3, 5);
  assert (ok == true);

  face f{ 7, 0 };
  struct glyph glyphs[3]{};
  fill_glyphs_from_text (glyphs, 3, "abc");
  adapter.write_glyphs (glyphs, &f, 3, 0, 0);

  auto cell = adapter.grid ().get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "a");

  adapter.clear_frame ();
  cell = adapter.grid ().get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == " ");

  printf ("✓ Clear frame test passed\n");
}

void
test_write_glyphs ()
{
  printf ("Testing write_glyphs...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (4, 10);
  assert (ok == true);

  face f{ 2, 4 };
  struct glyph glyphs[3]{};
  fill_glyphs_from_text (glyphs, 3, "Hi!");
  adapter.write_glyphs (glyphs, &f, 3, 1, 2);

  auto cell = adapter.grid ().get_back_cell (1, 2);
  assert (cell.has_value ());
  assert (cell->ch == "H");
  assert (cell->attrs.fg == 2);
  assert (cell->attrs.bg == 4);

  cell = adapter.grid ().get_back_cell (1, 3);
  assert (cell.has_value ());
  assert (cell->ch == "i");

  cell = adapter.grid ().get_back_cell (1, 4);
  assert (cell.has_value ());
  assert (cell->ch == "!");

  printf ("✓ Write glyphs test passed\n");
}

void
test_clear_end_of_line ()
{
  printf ("Testing clear_end_of_line...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (2, 6);
  assert (ok == true);

  face f{ 7, 0 };
  struct glyph glyphs[6]{};
  fill_glyphs_from_text (glyphs, 6, "abcdef");
  adapter.write_glyphs (glyphs, &f, 6, 0, 0);

  adapter.clear_end_of_line (0, 3);

  auto cell = adapter.grid ().get_back_cell (0, 2);
  assert (cell.has_value ());
  assert (cell->ch == "c");

  for (int col = 3; col < 6; ++col)
    {
      cell = adapter.grid ().get_back_cell (0, col);
      assert (cell.has_value ());
      assert (cell->ch == " ");
    }

  printf ("✓ Clear end of line test passed\n");
}

void
test_set_cursor ()
{
  printf ("Testing set_cursor...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (5, 12);
  assert (ok == true);
  adapter.set_cursor (5, 10);

  frame f{};
  f.selected_window = nullptr;
  f.root_window = nullptr;

  adapter.redisplay_frame (&f);
  assert (f.cursor_y == 5);
  assert (f.cursor_x == 10);

  printf ("✓ Set cursor test passed\n");
}

void
test_resize ()
{
  printf ("Testing resize...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (24, 80);
  assert (ok == true);
  adapter.resize (30, 100);
  assert (adapter.frame_rows () == 30);
  assert (adapter.frame_cols () == 100);

  printf ("✓ Resize test passed\n");
}

void
test_render_mode_line ()
{
  printf ("Testing render_mode_line...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (3, 10);
  assert (ok == true);

  window w{};
  adapter.render_mode_line (&w, "MODE", 2);

  auto cell = adapter.grid ().get_back_cell (2, 0);
  assert (cell.has_value ());
  assert (cell->ch == "M");
  assert ((cell->attrs.flags & CellAttributes::REVERSE) != 0);

  cell = adapter.grid ().get_back_cell (2, 6);
  assert (cell.has_value ());
  assert (cell->ch == " ");
  assert ((cell->attrs.flags & CellAttributes::REVERSE) != 0);

  printf ("✓ Render mode line test passed\n");
}

void
test_redisplay_count ()
{
  printf ("Testing redisplay_count...\n");

  EmacsRedisplayAdapter adapter;
  bool ok = adapter.init (2, 2);
  assert (ok == true);

  frame f{};
  adapter.redisplay_frame (&f);
  adapter.redisplay_frame (&f);

  assert (adapter.redisplay_count () == 2);

  printf ("✓ Redisplay count test passed\n");
}

void
test_c_api ()
{
  printf ("Testing C API...\n");

  void *adapter = emacs_cxx_create_redisplay_adapter ();
  assert (adapter != nullptr);

  int ok = emacs_cxx_init_redisplay (adapter, 4, 8);
  assert (ok == 1);

  face f{ 3, 0 };
  struct glyph glyphs[4]{};
  fill_glyphs_from_text (glyphs, 4, "TEST");
  emacs_cxx_write_glyphs (adapter, glyphs, &f, 4, 0, 0);
  emacs_cxx_flush (adapter);

  emacs_cxx_shutdown_redisplay (adapter);
  emacs_cxx_destroy_redisplay_adapter (adapter);

  printf ("✓ C API test passed\n");
}

int
main ()
{
  printf ("Running EmacsRedisplayAdapter tests...\n\n");

  test_create_destroy ();
  test_init ();
  test_shutdown ();
  test_clear_frame ();
  test_write_glyphs ();
  test_clear_end_of_line ();
  test_set_cursor ();
  test_resize ();
  test_render_mode_line ();
  test_redisplay_count ();
  test_c_api ();

  printf ("\n✅ All EmacsRedisplayAdapter tests passed!\n");
  return 0;
}
