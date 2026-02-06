#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C"
{
  void *lisp_malloc (size_t s) { return std::malloc (s); }
  void lisp_free (void *p) { std::free (p); }
}

#include "../../src/emacs_event_loop_adapter.hpp"
#include "../../src/emacs_mouse_adapter.hpp"

using namespace emacs::tui;

struct face
{
  unsigned long foreground;
  unsigned long background;
};

static void
fill_glyphs (struct glyph *glyphs, int count, const char *text)
{
  if (!glyphs || !text)
    {
      return;
    }

  int length = static_cast<int> (std::strlen (text));
  for (int i = 0; i < count; ++i)
    {
      char ch = (i < length) ? text[i] : ' ';
      glyphs[i].ch = static_cast<int> (ch);
      glyphs[i].face_id = 0;
    }
}

static window
make_window (int left, int top, int cols, int lines, ptrdiff_t start,
	     ptrdiff_t point, glyph_matrix *matrix)
{
  window w{};
  w.left_col = left;
  w.top_line = top;
  w.total_cols = cols;
  w.total_lines = lines;
  w.start = reinterpret_cast<Lisp_Object> (start);
  w.pointm = reinterpret_cast<Lisp_Object> (point);
  w.current_matrix = matrix;
  return w;
}

static ptrdiff_t
event_pos (const struct input_event &event)
{
  return reinterpret_cast<ptrdiff_t> (event.x);
}

static struct input_event
make_ascii_event (unsigned code)
{
  struct input_event event{};
  event.kind = ASCII_KEYSTROKE_EVENT;
  event.code = code;
  event.modifiers = 0;
  return event;
}

static void
init_row (struct glyph_row *row, struct glyph *data, int cols,
	  const char *text)
{
  row->glyphs[TEXT_AREA] = data;
  row->used[TEXT_AREA] = cols;
  row->enabled_p = true;

  int length = text ? static_cast<int> (std::strlen (text)) : 0;
  for (int col = 0; col < cols; ++col)
    {
      char ch = (col < length) ? text[col] : ' ';
      data[col].ch = static_cast<int> (ch);
      data[col].face_id = 0;
    }
}

static void
test_full_pipeline ()
{
  printf ("Testing full pipeline...\n");

  EmacsRedisplayAdapter adapter;
  assert (adapter.init (24, 80));

  face f{ 7, 0 };
  struct glyph glyphs[5]{};
  fill_glyphs (glyphs, 5, "Hello");
  adapter.write_glyphs (glyphs, &f, 5, 0, 0);

  auto back_cell = adapter.grid ().get_back_cell (0, 0);
  assert (back_cell.has_value ());
  assert (back_cell->ch == "H");

  adapter.flush ();

  auto front_cell = adapter.grid ().get_cell (0, 0);
  assert (front_cell.has_value ());
  assert (front_cell->ch == "H");

  printf ("✓ full pipeline test passed\n");
}

static void
test_keyboard_event_round_trip ()
{
  printf ("Testing keyboard event round-trip...\n");

  EmacsInputAdapter input_adapter;
  KeyEvent key (KeyCode::Unknown, KeyModifier::None, 'a');
  InputEvent input = InputEvent::make_key (key);
  struct input_event emacs_event
    = input_adapter.to_emacs_event (input);

  assert (emacs_event.kind == ASCII_KEYSTROKE_EVENT);
  assert (emacs_event.code == 'a');

  EmacsEventLoopAdapter loop;
  loop.inject_event (emacs_event);
  assert (loop.pending_count () == 1);

  auto next = loop.next_event ();
  assert (next.has_value ());
  assert (next->code == 'a');

  printf ("✓ keyboard round-trip test passed\n");
}

static void
test_mouse_click_to_window ()
{
  printf ("Testing mouse click to window...\n");

  struct glyph_row rows[1]{};
  struct glyph glyphs[1][20]{};
  struct glyph_matrix matrix{};
  init_row (&rows[0], glyphs[0], 20, "xxxxxxxxxxxxxxxxxxxx");
  matrix.rows = rows;
  matrix.nrows = 1;

  window root = make_window (0, 0, 80, 24, 1, 1, &matrix);
  window selected = make_window (10, 5, 20, 5, 100, 120, &matrix);

  frame f{};
  f.root_window = &root;
  f.selected_window = &selected;

  EmacsMouseAdapter mouse_adapter;
  MouseEvent mouse (MouseButton::Left, MouseEventType::Press, 6, 12);
  struct input_event event
    = mouse_adapter.translate_mouse_event (mouse, &f);

  assert (event.kind == MOUSE_CLICK_EVENT);
  assert (event.code == 0);
  assert ((event.modifiers & down_modifier) != 0);
  assert (event.frame_or_window == &selected);
  assert (event_pos (event) == 100 + (1 * 20 + 2));

  window *found = mouse_adapter.find_window_at (&f, 6, 12);
  assert (found == &selected);

  printf ("✓ mouse click to window test passed\n");
}

static void
test_mouse_drag_selection ()
{
  printf ("Testing mouse drag selection...\n");

  struct glyph_row rows[1]{};
  struct glyph glyphs[1][30]{};
  struct glyph_matrix matrix{};
  init_row (&rows[0], glyphs[0], 30, "drag-test-row");
  matrix.rows = rows;
  matrix.nrows = 1;

  window w = make_window (0, 0, 30, 10, 10, 10, &matrix);
  frame f{};
  f.root_window = &w;
  f.selected_window = &w;

  EmacsMouseAdapter adapter;
  MouseEvent press (MouseButton::Left, MouseEventType::Press, 5, 10);
  MouseEvent drag (MouseButton::Left, MouseEventType::Drag, 5, 20);
  MouseEvent release (MouseButton::Left, MouseEventType::Release, 5,
		      20);

  adapter.translate_mouse_event (press, &f);
  adapter.translate_mouse_event (drag, &f);
  adapter.translate_mouse_event (release, &f);

  auto range = adapter.get_drag_range ();
  assert (range.window == &w);
  assert (range.start_pos == 10 + (5 * 30 + 10));
  assert (range.end_pos == 10 + (5 * 30 + 20));

  printf ("✓ mouse drag selection test passed\n");
}

static void
test_scroll_wheel_event ()
{
  printf ("Testing scroll wheel event...\n");

  struct glyph_row rows[1]{};
  struct glyph glyphs[1][10]{};
  struct glyph_matrix matrix{};
  init_row (&rows[0], glyphs[0], 10, "row");
  matrix.rows = rows;
  matrix.nrows = 1;

  window w = make_window (0, 0, 10, 5, 5, 5, &matrix);
  frame f{};
  f.root_window = &w;
  f.selected_window = &w;

  EmacsMouseAdapter adapter;
  MouseEvent wheel (MouseButton::WheelUp, MouseEventType::Scroll, 2,
		    3);
  struct input_event event
    = adapter.translate_mouse_event (wheel, &f);

  assert (event.kind == WHEEL_EVENT);
  assert (event.code == 0);
  assert (event.frame_or_window == &w);
  assert (event_pos (event) == 5 + (2 * 10 + 3));

  printf ("✓ scroll wheel event test passed\n");
}

static void
test_window_sync_to_grid ()
{
  printf ("Testing window sync to grid...\n");

  Grid grid (4, 6);
  EmacsWindowAdapter adapter;

  struct glyph_row rows[2]{};
  struct glyph glyphs[2][6]{};
  struct glyph_matrix matrix{};
  init_row (&rows[0], glyphs[0], 6, "ABCDEF");
  init_row (&rows[1], glyphs[1], 6, "ghijkl");
  matrix.rows = rows;
  matrix.nrows = 2;

  window w = make_window (0, 0, 6, 2, 0, 0, &matrix);

  adapter.sync_window_to_grid (&w, grid);

  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "A");

  cell = grid.get_back_cell (1, 3);
  assert (cell.has_value ());
  assert (cell->ch == "j");

  printf ("✓ window sync to grid test passed\n");
}

static void
test_redisplay_with_cursor ()
{
  printf ("Testing redisplay with cursor...\n");

  EmacsRedisplayAdapter adapter;
  assert (adapter.init (5, 10));
  adapter.set_cursor (3, 4);

  frame f{};
  adapter.redisplay_frame (&f);

  assert (f.cursor_y == 3);
  assert (f.cursor_x == 4);

  printf ("✓ redisplay with cursor test passed\n");
}

static void
test_resize_pipeline ()
{
  printf ("Testing resize pipeline...\n");

  EmacsRedisplayAdapter adapter;
  assert (adapter.init (10, 10));
  adapter.resize (15, 20);
  assert (adapter.frame_rows () == 15);
  assert (adapter.frame_cols () == 20);

  printf ("✓ resize pipeline test passed\n");
}

static void
test_mode_line_rendering ()
{
  printf ("Testing mode line rendering...\n");

  EmacsRedisplayAdapter adapter;
  assert (adapter.init (3, 10));

  window w = make_window (0, 0, 10, 3, 0, 0, nullptr);
  adapter.render_mode_line (&w, "MODE", 2);

  auto cell = adapter.grid ().get_back_cell (2, 0);
  assert (cell.has_value ());
  assert (cell->ch == "M");
  assert ((cell->attrs.flags & CellAttributes::REVERSE) != 0);

  cell = adapter.grid ().get_back_cell (2, 7);
  assert (cell.has_value ());
  assert ((cell->attrs.flags & CellAttributes::REVERSE) != 0);

  printf ("✓ mode line rendering test passed\n");
}

static void
test_multiple_windows ()
{
  printf ("Testing multiple windows...\n");

  window root = make_window (0, 0, 80, 24, 0, 0, nullptr);
  window selected = make_window (10, 5, 20, 6, 0, 0, nullptr);

  frame f{};
  f.root_window = &root;
  f.selected_window = &selected;

  EmacsMouseAdapter adapter;
  window *picked = adapter.find_window_at (&f, 6, 12);
  assert (picked == &selected);

  picked = adapter.find_window_at (&f, 1, 1);
  assert (picked == &root);

  printf ("✓ multiple windows test passed\n");
}

static void
test_event_loop_buffer_ordering ()
{
  printf ("Testing event loop buffer ordering...\n");

  EmacsEventLoopAdapter adapter;
  adapter.inject_event (make_ascii_event ('a'));
  adapter.inject_event (make_ascii_event ('b'));
  adapter.inject_event (make_ascii_event ('c'));

  auto first = adapter.next_event ();
  auto second = adapter.next_event ();
  auto third = adapter.next_event ();

  assert (first.has_value ());
  assert (second.has_value ());
  assert (third.has_value ());
  assert (first->code == 'a');
  assert (second->code == 'b');
  assert (third->code == 'c');

  printf ("✓ event loop ordering test passed\n");
}

static void
test_c_api_integration ()
{
  printf ("Testing C API integration...\n");

  void *input_adapter = emacs_cxx_create_input_adapter ();
  assert (input_adapter != nullptr);

  InputEvent cpp_event = InputEvent::make_key (
    KeyEvent (KeyCode::Unknown, KeyModifier::None, 'z'));
  struct input_event emacs_event{};
  emacs_cxx_convert_input_event (input_adapter, &cpp_event,
				 &emacs_event);
  assert (emacs_event.kind == ASCII_KEYSTROKE_EVENT);
  assert (emacs_event.code == 'z');

  void *loop_adapter = emacs_cxx_create_event_loop_adapter ();
  assert (loop_adapter != nullptr);

  emacs_cxx_inject_event (loop_adapter, &emacs_event);
  assert (emacs_cxx_pending_count (loop_adapter) == 1);

  struct input_event out_event{};
  int ok = emacs_cxx_next_event (loop_adapter, &out_event);
  assert (ok == 1);
  assert (out_event.code == 'z');

  emacs_cxx_destroy_input_adapter (input_adapter);
  emacs_cxx_destroy_event_loop_adapter (loop_adapter);

  printf ("✓ C API integration test passed\n");
}

int
main ()
{
  printf ("Running Phase 5 integration tests...\n\n");

  test_full_pipeline ();
  test_keyboard_event_round_trip ();
  test_mouse_click_to_window ();
  test_mouse_drag_selection ();
  test_scroll_wheel_event ();
  test_window_sync_to_grid ();
  test_redisplay_with_cursor ();
  test_resize_pipeline ();
  test_mode_line_rendering ();
  test_multiple_windows ();
  test_event_loop_buffer_ordering ();
  test_c_api_integration ();

  printf ("\n✅ All Phase 5 integration tests passed!\n");
  return 0;
}
