// test/cxx/test_mouse_adapter_standalone.cpp
// Standalone tests for EmacsMouseAdapter (Phase 5.6)

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

#include "../../src/emacs_mouse_adapter.hpp"

using namespace emacs::tui;

static frame
make_frame_with_windows (window *root, window *selected)
{
  frame f{};
  f.root_window = root;
  f.selected_window = selected;
  return f;
}

static window
make_window (int left, int top, int cols, int lines, ptrdiff_t start)
{
  window w{};
  w.left_col = left;
  w.top_line = top;
  w.total_cols = cols;
  w.total_lines = lines;
  w.start = reinterpret_cast<Lisp_Object> (start);
  return w;
}

static ptrdiff_t
event_pos (const struct input_event &event)
{
  return reinterpret_cast<ptrdiff_t> (event.x);
}

void
test_create_destroy ()
{
  printf ("Testing create/destroy...\n");

  EmacsMouseAdapter *adapter = new EmacsMouseAdapter ();
  assert (adapter != nullptr);
  delete adapter;

  printf ("✓ Create/destroy test passed\n");
}

void
test_find_window_root ()
{
  printf ("Testing find_window_at (root)...\n");

  EmacsMouseAdapter adapter;
  window root = make_window (0, 0, 80, 24, 1);
  frame f = make_frame_with_windows (&root, nullptr);

  window *found = adapter.find_window_at (&f, 3, 4);
  assert (found == &root);

  printf ("✓ find_window_at root test passed\n");
}

void
test_find_window_selected ()
{
  printf ("Testing find_window_at (selected)...\n");

  EmacsMouseAdapter adapter;
  window root = make_window (0, 0, 80, 24, 1);
  window selected = make_window (10, 5, 20, 5, 10);
  frame f = make_frame_with_windows (&root, &selected);

  window *found = adapter.find_window_at (&f, 6, 11);
  assert (found == &selected);

  printf ("✓ find_window_at selected test passed\n");
}

void
test_find_window_out_of_bounds ()
{
  printf ("Testing find_window_at out-of-bounds...\n");

  EmacsMouseAdapter adapter;
  window root = make_window (0, 0, 10, 10, 1);
  frame f = make_frame_with_windows (&root, nullptr);

  window *found = adapter.find_window_at (&f, 20, 20);
  assert (found == nullptr);

  printf ("✓ find_window_at out-of-bounds test passed\n");
}

void
test_terminal_to_window_coords ()
{
  printf ("Testing terminal_to_window_coords...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (5, 7, 10, 10, 1);

  auto coords = adapter.terminal_to_window_coords (&w, 9, 8);
  assert (coords.row == 2);
  assert (coords.col == 3);

  printf ("✓ terminal_to_window_coords test passed\n");
}

void
test_terminal_to_buffer_pos ()
{
  printf ("Testing terminal_to_buffer_pos...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (2, 3, 10, 10, 100);

  ptrdiff_t pos = adapter.terminal_to_buffer_pos (&w, 5, 6);
  assert (pos == 100 + (2 * 10 + 4));

  printf ("✓ terminal_to_buffer_pos test passed\n");
}

void
test_translate_mouse_click ()
{
  printf ("Testing translate_mouse_event click...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (0, 0, 10, 10, 1);
  frame f = make_frame_with_windows (&w, &w);

  MouseEvent mouse (MouseButton::Left, MouseEventType::Press, 2, 3);
  struct input_event event
    = adapter.translate_mouse_event (mouse, &f);

  assert (event.kind == MOUSE_CLICK_EVENT);
  assert (event.code == 0);
  assert (event.frame_or_window == &w);
  assert (event_pos (event) == 1 + (2 * 10 + 3));
  assert ((event.modifiers & down_modifier) != 0);

  printf ("✓ translate_mouse_event click test passed\n");
}

void
test_translate_mouse_wheel ()
{
  printf ("Testing translate_mouse_event wheel...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (0, 0, 10, 10, 1);
  frame f = make_frame_with_windows (&w, &w);

  MouseEvent mouse (MouseButton::WheelDown, MouseEventType::Scroll, 1,
		    1);
  struct input_event event
    = adapter.translate_mouse_event (mouse, &f);

  assert (event.kind == WHEEL_EVENT);
  assert (event.code == 1);

  printf ("✓ translate_mouse_event wheel test passed\n");
}

void
test_drag_tracking_state ()
{
  printf ("Testing drag tracking state...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (0, 0, 10, 10, 1);

  adapter.begin_drag (1, 2, &w);
  assert (adapter.is_dragging ());

  adapter.update_drag (2, 3);
  adapter.end_drag (2, 3);
  assert (!adapter.is_dragging ());

  printf ("✓ Drag tracking state test passed\n");
}

void
test_drag_range ()
{
  printf ("Testing get_drag_range...\n");

  EmacsMouseAdapter adapter;
  window w = make_window (1, 1, 10, 10, 50);

  adapter.begin_drag (2, 2, &w);
  adapter.update_drag (3, 4);

  auto range = adapter.get_drag_range ();
  assert (range.window == &w);
  assert (range.start_pos == 50 + (1 * 10 + 1));
  assert (range.end_pos == 50 + (2 * 10 + 3));

  printf ("✓ get_drag_range test passed\n");
}

void
test_scroll_lines_default_setter ()
{
  printf ("Testing scroll_lines default/setter...\n");

  EmacsMouseAdapter adapter;
  assert (adapter.scroll_lines () == 3);
  adapter.set_scroll_lines (5);
  assert (adapter.scroll_lines () == 5);

  printf ("✓ scroll_lines default/setter test passed\n");
}

void
test_c_api ()
{
  printf ("Testing C API...\n");

  void *adapter = emacs_cxx_create_mouse_adapter ();
  assert (adapter != nullptr);

  window w = make_window (0, 0, 10, 10, 1);
  frame f = make_frame_with_windows (&w, &w);

  struct input_event out_event{};
  emacs_cxx_translate_mouse (adapter,
			     static_cast<int> (MouseButton::Left),
			     static_cast<int> (
			       MouseEventType::Release),
			     1, 2, &f, &out_event);

  assert (out_event.kind == MOUSE_CLICK_EVENT);
  assert ((out_event.modifiers & click_modifier) != 0);
  assert (event_pos (out_event) == 1 + (1 * 10 + 2));

  void *found = emacs_cxx_find_window_at (adapter, &f, 1, 2);
  assert (found == &w);

  emacs_cxx_destroy_mouse_adapter (adapter);

  printf ("✓ C API test passed\n");
}

int
main ()
{
  printf ("Running EmacsMouseAdapter tests...\n\n");

  test_create_destroy ();
  test_find_window_root ();
  test_find_window_selected ();
  test_find_window_out_of_bounds ();
  test_terminal_to_window_coords ();
  test_terminal_to_buffer_pos ();
  test_translate_mouse_click ();
  test_translate_mouse_wheel ();
  test_drag_tracking_state ();
  test_drag_range ();
  test_scroll_lines_default_setter ();
  test_c_api ();

  printf ("\n✅ All EmacsMouseAdapter tests passed!\n");
  return 0;
}
