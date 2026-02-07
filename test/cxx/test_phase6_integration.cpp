// test/cxx/test_phase6_integration.cpp
// Phase 6 End-to-End Integration Tests
//
// Tests the full pipeline:
//   EmacsBuffer → BufferBridge → Grid → Renderer output
//   UndoManager ↔ EmacsBuffer round-trip
//   Markers tracking through edits → cursor mapping
//   Buffer → glyph_matrix → WindowAdapter → Grid
//
// 15 integration tests.

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C"
{
  void *lisp_malloc (size_t s) { return std::malloc (s); }
  void lisp_free (void *p) { std::free (p); }
  void *lisp_realloc (void *p, size_t s)
  {
    return std::realloc (p, s);
  }
}

#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_buffer_bridge.hpp"
#include "../../src/emacs_event_loop_adapter.hpp"
#include "../../src/emacs_mouse_adapter.hpp"
#include "../../src/emacs_redisplay_adapter.hpp"
#include "../../src/emacs_undo.hpp"

using namespace emacs;
using namespace emacs::tui;

// ============================================================
// Test 1: Buffer create → render to Grid → verify cells
// ============================================================
static void
test_buffer_to_grid ()
{
  printf ("Testing buffer → grid rendering...\n");

  EmacsBuffer buf ("*test*", "Hello\nWorld");
  Grid grid (5, 20);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buf, grid, 1, 5, 20);

  // Row 0: "Hello"
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "H");

  cell = grid.get_back_cell (0, 4);
  assert (cell.has_value ());
  assert (cell->ch == "o");

  // Row 1: "World"
  cell = grid.get_back_cell (1, 0);
  assert (cell.has_value ());
  assert (cell->ch == "W");

  cell = grid.get_back_cell (1, 4);
  assert (cell.has_value ());
  assert (cell->ch == "d");

  // Row 2 should be blank (space)
  cell = grid.get_back_cell (2, 0);
  assert (cell.has_value ());
  assert (cell->ch == " ");

  printf ("✓ buffer → grid rendering passed\n");
}

// ============================================================
// Test 2: Edit buffer → re-render → verify updated cells
// ============================================================
static void
test_edit_and_rerender ()
{
  printf ("Testing edit → re-render...\n");

  EmacsBuffer buf ("*edit*", "ABC");
  Grid grid (3, 10);
  BufferBridge bridge;

  // Initial render
  bridge.render_buffer_to_grid (buf, grid, 1, 3, 10);
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "A");

  // Edit: insert "X" at beginning (point=1)
  buf.set_point (1);
  buf.insert_char ('X');
  assert (buf.content () == "XABC");

  // Re-render
  bridge.render_buffer_to_grid (buf, grid, 1, 3, 10);
  cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "X");

  cell = grid.get_back_cell (0, 1);
  assert (cell.has_value ());
  assert (cell->ch == "A");

  printf ("✓ edit → re-render passed\n");
}

// ============================================================
// Test 3: Undo/redo round-trip with buffer
// ============================================================
static void
test_undo_redo_with_buffer ()
{
  printf ("Testing undo/redo with buffer...\n");

  EmacsBuffer buf ("*undo*", "Hello");
  UndoManager undo;

  // Record inserting " World" at end
  buf.set_point (buf.point_max ());
  ptrdiff_t old_point = buf.point ();

  undo.begin_group ();
  undo.record_insert (old_point, " World", old_point);
  buf.insert_string (" World");
  undo.end_group ();

  assert (buf.content () == "Hello World");

  // Undo: remove " World"
  const auto &group = undo.prepare_undo ();
  assert (!group.empty ());
  for (int i = static_cast<int> (group.records.size ()) - 1; i >= 0;
       --i)
    {
      const auto &rec = group.records[static_cast<size_t> (i)];
      if (rec.type == UndoRecordType::INSERT)
	{
	  // Undo an insert = delete from pos, length = text.size()
	  buf.set_point (rec.position);
	  for (size_t j = 0; j < rec.text.size (); ++j)
	    buf.delete_forward (1);
	}
    }
  undo.commit_undo ();
  assert (buf.content () == "Hello");

  // Redo: re-insert " World"
  const auto &redo_group = undo.prepare_redo ();
  assert (!redo_group.empty ());
  for (size_t i = 0; i < redo_group.records.size (); ++i)
    {
      const auto &rec = redo_group.records[i];
      if (rec.type == UndoRecordType::INSERT)
	{
	  buf.set_point (rec.position);
	  buf.insert_string (
	    std::string_view (rec.text.data (), rec.text.size ()));
	}
    }
  undo.commit_redo ();
  assert (buf.content () == "Hello World");

  printf ("✓ undo/redo with buffer passed\n");
}

// ============================================================
// Test 4: Marker tracks through insert
// ============================================================
static void
test_marker_tracks_insert ()
{
  printf ("Testing marker tracking through insert...\n");

  EmacsBuffer buf ("*marker*", "ABCD");
  // Place marker at position 3 (between B and C)
  Marker mark (&buf, 3, MarkerInsertionType::AFTER_INSERTION);
  assert (mark.position () == 3);

  // Insert "XY" at position 2 (between A and B)
  buf.set_point (2);
  buf.insert_string ("XY");
  // Buffer: "AXYBC D" → actually "AXYBCD"
  assert (buf.content () == "AXYBCD");

  // Marker was at 3, insert of 2 chars before it → now at 5
  assert (mark.position () == 5);

  // Render and check cursor mapping
  Grid grid (3, 20);
  BufferBridge bridge;
  bridge.render_buffer_to_grid (buf, grid, 1, 3, 20);

  // Verify buffer content in grid
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "A");

  cell = grid.get_back_cell (0, 1);
  assert (cell.has_value ());
  assert (cell->ch == "X");

  printf ("✓ marker tracking through insert passed\n");
}

// ============================================================
// Test 5: Marker tracks through delete
// ============================================================
static void
test_marker_tracks_delete ()
{
  printf ("Testing marker tracking through delete...\n");

  EmacsBuffer buf ("*markdel*", "ABCDEFGH");
  // Marker at position 6 (before F)
  Marker mark (&buf, 6, MarkerInsertionType::BEFORE_INSERTION);
  assert (mark.position () == 6);

  // Delete 2 chars at position 3 (removes C and D)
  buf.set_point (3);
  buf.delete_forward (1);
  buf.delete_forward (1);
  assert (buf.content () == "ABEFGH");

  // Marker was at 6, deletion of 2 chars before it → now at 4
  assert (mark.position () == 4);

  printf ("✓ marker tracking through delete passed\n");
}

// ============================================================
// Test 6: Cursor position mapping through bridge
// ============================================================
static void
test_cursor_mapping ()
{
  printf ("Testing cursor position mapping...\n");

  EmacsBuffer buf ("*cursor*", "Hello\nWorld\nFoo");
  Grid grid (5, 20);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buf, grid, 1, 5, 20);

  // Point at position 1 (beginning) → row=0, col=0
  buf.set_point (1);
  auto cursor = bridge.map_point_to_grid (buf, 1, 5, 20);
  assert (cursor.is_visible ());
  assert (cursor.row == 0);
  assert (cursor.col == 0);

  // Point at position 3 → row=0, col=2 ("l" in "Hello")
  buf.set_point (3);
  cursor = bridge.map_point_to_grid (buf, 1, 5, 20);
  assert (cursor.is_visible ());
  assert (cursor.row == 0);
  assert (cursor.col == 2);

  // Point at position 7 → row=1, col=0 ("W" in "World")
  // "Hello\n" = 6 bytes, so pos 7 = start of "World"
  buf.set_point (7);
  cursor = bridge.map_point_to_grid (buf, 1, 5, 20);
  assert (cursor.is_visible ());
  assert (cursor.row == 1);
  assert (cursor.col == 0);

  printf ("✓ cursor position mapping passed\n");
}

// ============================================================
// Test 7: Line wrapping renders correctly
// ============================================================
static void
test_line_wrapping ()
{
  printf ("Testing line wrapping...\n");

  EmacsBuffer buf ("*wrap*", "ABCDEFGHIJ");
  Grid grid (5, 5);
  BufferBridge bridge;

  // 10 chars with 5-col window → wraps to 2 lines
  bridge.render_buffer_to_grid (buf, grid, 1, 5, 5);

  // Row 0: "ABCDE"
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "A");
  cell = grid.get_back_cell (0, 4);
  assert (cell.has_value ());
  assert (cell->ch == "E");

  // Row 1: "FGHIJ"
  cell = grid.get_back_cell (1, 0);
  assert (cell.has_value ());
  assert (cell->ch == "F");
  cell = grid.get_back_cell (1, 4);
  assert (cell.has_value ());
  assert (cell->ch == "J");

  printf ("✓ line wrapping passed\n");
}

// ============================================================
// Test 8: Tab expansion in grid rendering
// ============================================================
static void
test_tab_expansion ()
{
  printf ("Testing tab expansion...\n");

  EmacsBuffer buf ("*tab*", "A\tB");
  Grid grid (3, 20);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buf, grid, 1, 3, 20);

  // 'A' at col 0
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "A");

  // Tab expands to spaces cols 1-7, then 'B' at col 8
  cell = grid.get_back_cell (0, 8);
  assert (cell.has_value ());
  assert (cell->ch == "B");

  // Cols 1-7 should be spaces
  for (int c = 1; c <= 7; ++c)
    {
      cell = grid.get_back_cell (0, c);
      assert (cell.has_value ());
      assert (cell->ch == " ");
    }

  printf ("✓ tab expansion passed\n");
}

// ============================================================
// Test 9: Glyph matrix population → WindowAdapter sync
// ============================================================
static void
test_glyph_matrix_to_window_adapter ()
{
  printf ("Testing glyph matrix → window adapter...\n");

  EmacsBuffer buf ("*glyph*", "Hi\nThere");
  BufferBridge bridge;

  // Allocate glyph matrix
  const int rows = 3;
  const int cols = 10;

  struct glyph_row glyph_rows[3]{};
  struct glyph glyph_data[3][10]{};
  struct glyph_matrix matrix{};

  for (int r = 0; r < rows; ++r)
    {
      glyph_rows[r].glyphs[TEXT_AREA] = glyph_data[r];
      glyph_rows[r].used[TEXT_AREA] = cols;
      glyph_rows[r].enabled_p = false;
    }
  matrix.rows = glyph_rows;
  matrix.nrows = rows;

  bridge.populate_glyph_matrix (buf, &matrix, 1, rows, cols);

  // Row 0: "Hi" + spaces
  assert (glyph_rows[0].enabled_p);
  assert (glyph_data[0][0].ch == 'H');
  assert (glyph_data[0][1].ch == 'i');
  assert (glyph_data[0][2].ch == ' ');

  // Row 1: "There" + spaces
  assert (glyph_rows[1].enabled_p);
  assert (glyph_data[1][0].ch == 'T');
  assert (glyph_data[1][4].ch == 'e');

  // Now sync through WindowAdapter
  Grid grid (5, cols);
  EmacsWindowAdapter win_adapter;

  struct window w{};
  w.left_col = 0;
  w.top_line = 0;
  w.total_cols = cols;
  w.total_lines = rows;
  w.start = reinterpret_cast<Lisp_Object> (1);
  w.pointm = reinterpret_cast<Lisp_Object> (1);
  w.current_matrix = &matrix;

  win_adapter.sync_window_to_grid (&w, grid);

  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "H");

  cell = grid.get_back_cell (1, 0);
  assert (cell.has_value ());
  assert (cell->ch == "T");

  printf ("✓ glyph matrix → window adapter passed\n");
}

// ============================================================
// Test 10: Full pipeline: buffer → bridge → grid → renderer
// ============================================================
static void
test_full_edit_display_render ()
{
  printf ("Testing full edit → display → render pipeline...\n");

  EmacsBuffer buf ("*full*", "Line 1\nLine 2");
  Grid grid (5, 20);
  BufferBridge bridge;
  Renderer renderer;

  // Render buffer to grid
  bridge.render_buffer_to_grid (buf, grid, 1, 5, 20);

  // Swap buffers (flush back → front)
  grid.swap_buffers ();

  // Verify front buffer has content
  auto cell = grid.get_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "L");

  cell = grid.get_cell (1, 0);
  assert (cell.has_value ());
  assert (cell->ch == "L");

  renderer.render (grid);
  assert (renderer.output ().size () > 0);

  // Edit the buffer
  buf.set_point (8); // after "Line 1\n" (pos 8 = start of "Line 2")
  buf.insert_string ("NEW ");
  assert (buf.content () == "Line 1\nNEW Line 2");

  // Re-render
  bridge.render_buffer_to_grid (buf, grid, 1, 5, 20);
  grid.swap_buffers ();

  cell = grid.get_cell (1, 0);
  assert (cell.has_value ());
  assert (cell->ch == "N");

  cell = grid.get_cell (1, 4);
  assert (cell.has_value ());
  assert (cell->ch == "L");

  printf ("✓ full edit → display → render pipeline passed\n");
}

// ============================================================
// Test 11: Keyboard event → buffer insert → render
// ============================================================
static void
test_keyboard_to_buffer_to_display ()
{
  printf ("Testing keyboard → buffer → display pipeline...\n");

  // Simulate: user types 'H', 'i'
  EmacsInputAdapter input_adapter;
  EmacsEventLoopAdapter loop;

  // Create key events
  KeyEvent key_h (KeyCode::Unknown, KeyModifier::None, 'H');
  KeyEvent key_i (KeyCode::Unknown, KeyModifier::None, 'i');
  InputEvent ev_h = InputEvent::make_key (key_h);
  InputEvent ev_i = InputEvent::make_key (key_i);

  // Convert and inject
  struct input_event emacs_h = input_adapter.to_emacs_event (ev_h);
  struct input_event emacs_i = input_adapter.to_emacs_event (ev_i);
  loop.inject_event (emacs_h);
  loop.inject_event (emacs_i);

  // Consume events and insert into buffer
  EmacsBuffer buf ("*keys*");
  buf.set_point (1);

  while (loop.pending_count () > 0)
    {
      auto event = loop.next_event ();
      if (event.has_value () && event->kind == ASCII_KEYSTROKE_EVENT)
	{
	  buf.insert_char (static_cast<char> (event->code));
	}
    }

  assert (buf.content () == "Hi");

  // Render to grid
  Grid grid (3, 10);
  BufferBridge bridge;
  bridge.render_buffer_to_grid (buf, grid, 1, 3, 10);

  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "H");

  cell = grid.get_back_cell (0, 1);
  assert (cell.has_value ());
  assert (cell->ch == "i");

  printf ("✓ keyboard → buffer → display pipeline passed\n");
}

// ============================================================
// Test 12: Multiple markers + undo consistency
// ============================================================
static void
test_markers_undo_consistency ()
{
  printf ("Testing markers + undo consistency...\n");

  EmacsBuffer buf ("*multi*", "ABCDEF");
  UndoManager undo;

  // Markers at positions 2, 4, 6
  Marker m1 (&buf, 2, MarkerInsertionType::AFTER_INSERTION);
  Marker m2 (&buf, 4, MarkerInsertionType::BEFORE_INSERTION);
  Marker m3 (&buf, 6, MarkerInsertionType::AFTER_INSERTION);

  assert (m1.position () == 2);
  assert (m2.position () == 4);
  assert (m3.position () == 6);

  // Insert "XX" at position 3 (between B and C)
  buf.set_point (3);
  ptrdiff_t old_pt = buf.point ();
  undo.begin_group ();
  undo.record_insert (old_pt, "XX", old_pt);
  buf.insert_string ("XX");
  undo.end_group ();

  assert (buf.content () == "ABXXCDEF");
  // m1 at 2 (before insert) → stays 2
  assert (m1.position () == 2);
  // m2 at 4 (after insert at 3, +2) → 6
  assert (m2.position () == 6);
  // m3 at 6 (after insert at 3, +2) → 8
  assert (m3.position () == 8);

  printf ("✓ markers + undo consistency passed\n");
}

// ============================================================
// Test 13: Window start scrolling
// ============================================================
static void
test_window_start_scrolling ()
{
  printf ("Testing window start scrolling...\n");

  EmacsBuffer buf ("*scroll*", "Line1\nLine2\nLine3\nLine4\nLine5");
  Grid grid (3, 20);
  BufferBridge bridge;

  // Render starting from position 1 (beginning)
  bridge.render_buffer_to_grid (buf, grid, 1, 3, 20);
  auto cell = grid.get_back_cell (0, 0);
  assert (cell.has_value ());
  assert (cell->ch == "L");
  cell = grid.get_back_cell (0, 4);
  assert (cell.has_value ());
  assert (cell->ch == "1");

  // Scroll: render starting from "Line3"
  // "Line1\nLine2\n" = 12 bytes, so position 13 = start of
  // "Line3"
  bridge.render_buffer_to_grid (buf, grid, 13, 3, 20);
  cell = grid.get_back_cell (0, 4);
  assert (cell.has_value ());
  assert (cell->ch == "3");

  cell = grid.get_back_cell (1, 4);
  assert (cell.has_value ());
  assert (cell->ch == "4");

  cell = grid.get_back_cell (2, 4);
  assert (cell.has_value ());
  assert (cell->ch == "5");

  printf ("✓ window start scrolling passed\n");
}

// ============================================================
// Test 14: Buffer stats after rendering
// ============================================================
static void
test_bridge_stats ()
{
  printf ("Testing bridge rendering stats...\n");

  EmacsBuffer buf ("*stats*", "AB\nCD\nEF");
  Grid grid (5, 10);
  BufferBridge bridge;

  bridge.render_buffer_to_grid (buf, grid, 1, 5, 10);

  assert (bridge.lines_rendered () == 3);
  assert (bridge.cells_written () > 0);

  bridge.reset_stats ();
  assert (bridge.lines_rendered () == 0);
  assert (bridge.cells_written () == 0);

  printf ("✓ bridge rendering stats passed\n");
}

// ============================================================
// Test 15: C API buffer round-trip
// ============================================================
static void
test_c_api_buffer ()
{
  printf ("Testing C API buffer round-trip...\n");

  void *buf = emacs_cxx_create_buffer_with_text ("*capi*", "Test");
  assert (buf != nullptr);
  assert (emacs_cxx_buffer_size (buf) == 4);
  assert (emacs_cxx_buffer_point (buf) == 5);

  emacs_cxx_buffer_set_point (buf, 1);
  emacs_cxx_buffer_insert_char (buf, 'X');
  assert (emacs_cxx_buffer_size (buf) == 5);
  assert (emacs_cxx_buffer_is_modified (buf) == 1);

  emacs_cxx_buffer_set_point (buf, 6);
  emacs_cxx_buffer_insert_string (buf, "!");
  assert (emacs_cxx_buffer_size (buf) == 6);

  // Verify content through C++ cast
  auto *cpp_buf = static_cast<EmacsBuffer *> (buf);
  assert (cpp_buf->content () == "XTest!");

  emacs_cxx_destroy_buffer (buf);

  printf ("✓ C API buffer round-trip passed\n");
}

// ============================================================
// Main
// ============================================================
int
main ()
{
  printf ("Running Phase 6 integration tests...\n\n");

  test_buffer_to_grid ();
  test_edit_and_rerender ();
  test_undo_redo_with_buffer ();
  test_marker_tracks_insert ();
  test_marker_tracks_delete ();
  test_cursor_mapping ();
  test_line_wrapping ();
  test_tab_expansion ();
  test_glyph_matrix_to_window_adapter ();
  test_full_edit_display_render ();
  test_keyboard_to_buffer_to_display ();
  test_markers_undo_consistency ();
  test_window_start_scrolling ();
  test_bridge_stats ();
  test_c_api_buffer ();

  printf ("\n✅ All 15 Phase 6 integration tests "
	  "passed!\n");
  return 0;
}
