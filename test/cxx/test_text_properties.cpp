// test/cxx/test_text_properties.cpp
// Unit tests for text properties system (Phase 9.1)

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <optional>

#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_buffer_bridge.hpp"
#include "../../src/text_properties.hpp"

using namespace emacs;
using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void *lisp_malloc_unsafe (size_t size)
  {
    return std::malloc (size);
  }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_malloc_uncleared (size_t size)
  {
    return std::malloc (size);
  }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

// === Test 1: Empty TextProperties ===
static void
test_empty ()
{
  TextProperties tp;

  assert (tp.empty ());
  assert (tp.interval_count () == 0);
  assert (!tp.get (1, "face").has_value ());
  assert (!tp.get_face (1).has_value ());

  std::printf ("test_empty passed\n");
}

// === Test 2: Basic put/get ===
static void
test_put_get ()
{
  TextProperties tp;

  gc_string val ("bold");
  tp.put (1, 5, "face-name", TextPropertyValue (val));

  assert (tp.interval_count () == 1);
  assert (!tp.empty ());

  auto result = tp.get (1, "face-name");
  assert (result.has_value ());
  assert (std::get<gc_string> (*result) == "bold");

  result = tp.get (4, "face-name");
  assert (result.has_value ());

  result = tp.get (5, "face-name");
  assert (!result.has_value ());

  result = tp.get (1, "other-key");
  assert (!result.has_value ());

  std::printf ("test_put_get passed\n");
}

// === Test 3: put_face / get_face ===
static void
test_put_get_face ()
{
  TextProperties tp;

  CellAttributes attrs;
  attrs.fg = 0xFF0000;
  attrs.bg = 0x000000;
  attrs.flags = 1;

  tp.put_face (3, 8, attrs);

  assert (tp.interval_count () == 1);

  auto face = tp.get_face (3);
  assert (face.has_value ());
  assert (face->fg == 0xFF0000);
  assert (face->bg == 0x000000);
  assert (face->flags == 1);

  face = tp.get_face (7);
  assert (face.has_value ());

  face = tp.get_face (8);
  assert (!face.has_value ());

  face = tp.get_face (2);
  assert (!face.has_value ());

  std::printf ("test_put_get_face passed\n");
}

// === Test 4: Remove by key ===
static void
test_remove ()
{
  TextProperties tp;

  gc_string val ("v1");
  tp.put (1, 10, "key1", TextPropertyValue (val));
  tp.put (1, 10, "key2", TextPropertyValue (val));

  assert (tp.interval_count () == 2);

  tp.remove (1, 10, "key1");
  assert (tp.interval_count () == 1);
  assert (!tp.get (5, "key1").has_value ());
  assert (tp.get (5, "key2").has_value ());

  std::printf ("test_remove passed\n");
}

// === Test 5: Remove partial range (split) ===
static void
test_remove_partial ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 20, "k", TextPropertyValue (val));

  tp.remove (5, 10, "k");

  assert (tp.get (3, "k").has_value ());
  assert (!tp.get (7, "k").has_value ());
  assert (tp.get (12, "k").has_value ());

  assert (tp.interval_count () == 2);

  std::printf ("test_remove_partial passed\n");
}

// === Test 6: Remove all ===
static void
test_remove_all ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 10, "k1", TextPropertyValue (val));

  CellAttributes attrs;
  attrs.fg = 0xAA;
  tp.put_face (3, 8, attrs);

  assert (tp.interval_count () == 2);

  tp.remove_all (1, 20);
  assert (tp.empty ());

  std::printf ("test_remove_all passed\n");
}

// === Test 7: next_property_change ===
static void
test_next_property_change ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  assert (tp.next_property_change (1, "k") == 5);
  assert (tp.next_property_change (5, "k") == 10);
  assert (tp.next_property_change (7, "k") == 10);
  assert (tp.next_property_change (10, "k") == 0);

  std::printf ("test_next_property_change passed\n");
}

// === Test 8: for_each_in_range by key ===
static void
test_for_each_in_range_key ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 5, "k", TextPropertyValue (val));
  tp.put (8, 12, "k", TextPropertyValue (val));
  tp.put (20, 25, "k", TextPropertyValue (val));

  int count = 0;
  tp.for_each_in_range (3, 15, "k", [&] (const PropertyInterval &iv)
			  { ++count; });

  assert (count == 2);

  std::printf ("test_for_each_in_range_key passed\n");
}

// === Test 9: for_each_in_range all keys ===
static void
test_for_each_in_range_all ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 5, "k1", TextPropertyValue (val));
  tp.put (3, 8, "k2", TextPropertyValue (val));

  int count = 0;
  tp.for_each_in_range (1, 10, [&] (const PropertyInterval &iv)
			  { ++count; });

  assert (count == 2);

  std::printf ("test_for_each_in_range_all passed\n");
}

// === Test 10: adjust_for_insert — after ===
static void
test_adjust_insert_after ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  tp.adjust_for_insert (2, 3);

  assert (tp.get (8, "k").has_value ());
  assert (tp.get (12, "k").has_value ());
  assert (!tp.get (13, "k").has_value ());
  assert (!tp.get (5, "k").has_value ());

  std::printf ("test_adjust_insert_after passed\n");
}

// === Test 11: adjust_for_insert — inside span ===
static void
test_adjust_insert_inside ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  tp.adjust_for_insert (7, 3);

  assert (tp.get (5, "k").has_value ());
  assert (tp.get (9, "k").has_value ());
  assert (tp.get (12, "k").has_value ());
  assert (!tp.get (13, "k").has_value ());

  std::printf ("test_adjust_insert_inside passed\n");
}

// === Test 12: adjust_for_insert at start (not front-sticky) ===
static void
test_adjust_insert_start_not_sticky ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  tp.adjust_for_insert (5, 2);

  assert (!tp.get (5, "k").has_value ());
  assert (tp.get (7, "k").has_value ());
  assert (tp.get (11, "k").has_value ());
  assert (!tp.get (12, "k").has_value ());

  std::printf ("test_adjust_insert_start_not_sticky passed\n");
}

// === Test 13: adjust_for_insert at end (rear-sticky) ===
static void
test_adjust_insert_end_rear_sticky ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  tp.adjust_for_insert (10, 3);

  assert (tp.get (5, "k").has_value ());
  assert (tp.get (12, "k").has_value ());
  assert (!tp.get (13, "k").has_value ());

  std::printf ("test_adjust_insert_end_rear_sticky passed\n");
}

// === Test 14: adjust_for_delete — entirely after ===
static void
test_adjust_delete_after ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (10, 15, "k", TextPropertyValue (val));

  tp.adjust_for_delete (3, 2);

  assert (tp.get (8, "k").has_value ());
  assert (tp.get (12, "k").has_value ());
  assert (!tp.get (13, "k").has_value ());
  assert (!tp.get (7, "k").has_value ());

  std::printf ("test_adjust_delete_after passed\n");
}

// === Test 15: adjust_for_delete — entirely before ===
static void
test_adjust_delete_before ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 5, "k", TextPropertyValue (val));

  tp.adjust_for_delete (8, 3);

  assert (tp.get (1, "k").has_value ());
  assert (tp.get (4, "k").has_value ());
  assert (!tp.get (5, "k").has_value ());

  std::printf ("test_adjust_delete_before passed\n");
}

// === Test 16: adjust_for_delete — fully contained ===
static void
test_adjust_delete_contained ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 10, "k", TextPropertyValue (val));

  tp.adjust_for_delete (5, 5);

  assert (tp.empty ());

  std::printf ("test_adjust_delete_contained passed\n");
}

// === Test 17: adjust_for_delete — spanning ===
static void
test_adjust_delete_spanning ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 15, "k", TextPropertyValue (val));

  tp.adjust_for_delete (8, 3);

  assert (tp.get (5, "k").has_value ());
  assert (tp.get (11, "k").has_value ());
  assert (!tp.get (12, "k").has_value ());

  std::printf ("test_adjust_delete_spanning passed\n");
}

// === Test 18: adjust_for_delete — left overlap ===
static void
test_adjust_delete_left_overlap ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 15, "k", TextPropertyValue (val));

  tp.adjust_for_delete (3, 5);

  assert (tp.get (3, "k").has_value ());
  assert (tp.get (9, "k").has_value ());
  assert (!tp.get (10, "k").has_value ());
  assert (!tp.get (2, "k").has_value ());

  std::printf ("test_adjust_delete_left_overlap passed\n");
}

// === Test 19: adjust_for_delete — right overlap ===
static void
test_adjust_delete_right_overlap ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 15, "k", TextPropertyValue (val));

  tp.adjust_for_delete (12, 5);

  assert (tp.get (5, "k").has_value ());
  assert (tp.get (11, "k").has_value ());
  assert (!tp.get (12, "k").has_value ());

  std::printf ("test_adjust_delete_right_overlap passed\n");
}

// === Test 20: clear ===
static void
test_clear ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (1, 10, "k", TextPropertyValue (val));

  CellAttributes attrs;
  tp.put_face (5, 8, attrs);

  assert (tp.interval_count () == 2);

  tp.clear ();
  assert (tp.empty ());
  assert (tp.interval_count () == 0);

  std::printf ("test_clear passed\n");
}

// === Test 21: EmacsBuffer integration — insert adjusts props ===
static void
test_buffer_insert_adjusts ()
{
  EmacsBuffer buf ("test", "ABCDEFGH");

  CellAttributes attrs;
  attrs.fg = 0xFF;
  buf.text_properties ().put_face (3, 6, attrs);

  buf.set_point (3);
  buf.insert_string ("XX");

  auto face = buf.text_properties ().get_face (3);
  assert (!face.has_value ());

  face = buf.text_properties ().get_face (5);
  assert (face.has_value ());
  assert (face->fg == 0xFF);

  face = buf.text_properties ().get_face (7);
  assert (face.has_value ());

  face = buf.text_properties ().get_face (8);
  assert (!face.has_value ());

  std::printf ("test_buffer_insert_adjusts passed\n");
}

// === Test 22: EmacsBuffer integration — delete adjusts props ===
static void
test_buffer_delete_adjusts ()
{
  EmacsBuffer buf ("test", "ABCDEFGH");

  CellAttributes attrs;
  attrs.fg = 0xAA;
  buf.text_properties ().put_face (5, 8, attrs);

  buf.set_point (2);
  buf.delete_forward (2);

  auto face = buf.text_properties ().get_face (3);
  assert (face.has_value ());
  assert (face->fg == 0xAA);

  face = buf.text_properties ().get_face (5);
  assert (face.has_value ());

  face = buf.text_properties ().get_face (6);
  assert (!face.has_value ());

  std::printf ("test_buffer_delete_adjusts passed\n");
}

// === Test 23: EmacsBuffer — delete_backward adjusts ===
static void
test_buffer_delete_backward_adjusts ()
{
  EmacsBuffer buf ("test", "ABCDEFGH");

  CellAttributes attrs;
  attrs.fg = 0xBB;
  buf.text_properties ().put_face (5, 8, attrs);

  buf.set_point (4);
  buf.delete_backward (2);

  auto face = buf.text_properties ().get_face (3);
  assert (face.has_value ());
  assert (face->fg == 0xBB);

  face = buf.text_properties ().get_face (5);
  assert (face.has_value ());

  face = buf.text_properties ().get_face (6);
  assert (!face.has_value ());

  std::printf ("test_buffer_delete_backward_adjusts passed\n");
}

// === Test 24: Overwrite existing property ===
static void
test_overwrite_property ()
{
  TextProperties tp;

  CellAttributes red;
  red.fg = 0xFF0000;
  tp.put_face (1, 10, red);

  CellAttributes blue;
  blue.fg = 0x0000FF;
  tp.put_face (3, 7, blue);

  auto face = tp.get_face (2);
  assert (face.has_value ());
  assert (face->fg == 0xFF0000);

  face = tp.get_face (5);
  assert (face.has_value ());
  assert (face->fg == 0x0000FF);

  face = tp.get_face (8);
  assert (face.has_value ());
  assert (face->fg == 0xFF0000);

  std::printf ("test_overwrite_property passed\n");
}

// === Test 25: Multiple keys on same range ===
static void
test_multiple_keys ()
{
  TextProperties tp;

  gc_string v1 ("bold");
  gc_string v2 ("italic");
  tp.put (1, 10, "weight", TextPropertyValue (v1));
  tp.put (1, 10, "style", TextPropertyValue (v2));

  auto r1 = tp.get (5, "weight");
  assert (r1.has_value ());
  assert (std::get<gc_string> (*r1) == "bold");

  auto r2 = tp.get (5, "style");
  assert (r2.has_value ());
  assert (std::get<gc_string> (*r2) == "italic");

  std::printf ("test_multiple_keys passed\n");
}

// === Test 26: BufferBridge renders face properties ===
static void
test_bridge_renders_faces ()
{
  EmacsBuffer buf ("test", "ABCDE");

  CellAttributes red;
  red.fg = 0xFF0000;
  red.bg = 0;
  red.flags = 0;
  buf.text_properties ().put_face (2, 4, red);

  Grid grid (1, 10);
  BufferBridge bridge;

  CellAttributes base;
  base.fg = 0xFFFFFF;
  base.bg = 0;
  base.flags = 0;
  bridge.render_buffer_to_grid (buf, grid, 1, 1, 10, base);

  auto cellA = grid.get_back_cell (0, 0);
  assert (cellA.has_value ());
  assert (cellA->attrs.fg == 0xFFFFFF);

  auto cellB = grid.get_back_cell (0, 1);
  assert (cellB.has_value ());
  assert (cellB->attrs.fg == 0xFF0000);

  auto cellC = grid.get_back_cell (0, 2);
  assert (cellC.has_value ());
  assert (cellC->attrs.fg == 0xFF0000);

  auto cellD = grid.get_back_cell (0, 3);
  assert (cellD.has_value ());
  assert (cellD->attrs.fg == 0xFFFFFF);

  std::printf ("test_bridge_renders_faces passed\n");
}

// === Test 27: Merge adjacent intervals ===
static void
test_merge_adjacent ()
{
  TextProperties tp;

  CellAttributes attrs;
  attrs.fg = 0xAA;
  tp.put_face (1, 5, attrs);
  tp.put_face (5, 10, attrs);

  assert (tp.interval_count () == 1);

  auto face = tp.get_face (1);
  assert (face.has_value ());
  face = tp.get_face (9);
  assert (face.has_value ());

  std::printf ("test_merge_adjacent passed\n");
}

// === Test 28: extern C bridge — put/has ===
static void
test_extern_c_bridge ()
{
  void *buf = emacs_cxx_create_buffer_with_text ("test", "ABCDE");

  emacs_cxx_buffer_put_text_property (buf, 2, 4, "syntax", "keyword");

  assert (emacs_cxx_buffer_has_text_property (buf, 2, "syntax") == 1);
  assert (emacs_cxx_buffer_has_text_property (buf, 4, "syntax") == 0);
  assert (emacs_cxx_buffer_has_text_property (buf, 1, "syntax") == 0);

  emacs_cxx_buffer_remove_text_property (buf, 2, 4, "syntax");
  assert (emacs_cxx_buffer_has_text_property (buf, 2, "syntax") == 0);

  emacs_cxx_destroy_buffer (buf);

  std::printf ("test_extern_c_bridge passed\n");
}

// === Test 29: extern C bridge — put_face ===
static void
test_extern_c_put_face ()
{
  void *buf = emacs_cxx_create_buffer_with_text ("test", "ABCDE");

  emacs_cxx_buffer_put_face (buf, 1, 3, 0xFF0000, 0x000000, 1);

  auto *buffer = static_cast<EmacsBuffer *> (buf);
  auto face = buffer->text_properties ().get_face (1);
  assert (face.has_value ());
  assert (face->fg == 0xFF0000);
  assert (face->bg == 0x000000);
  assert (face->flags == 1);

  face = buffer->text_properties ().get_face (3);
  assert (!face.has_value ());

  emacs_cxx_destroy_buffer (buf);

  std::printf ("test_extern_c_put_face passed\n");
}

// === Test 30: Invalid ranges are no-ops ===
static void
test_invalid_ranges ()
{
  TextProperties tp;

  gc_string val ("v");
  tp.put (5, 3, "k", TextPropertyValue (val));
  assert (tp.empty ());

  tp.put (0, 5, "k", TextPropertyValue (val));
  assert (tp.empty ());

  tp.put (-1, 5, "k", TextPropertyValue (val));
  assert (tp.empty ());

  std::printf ("test_invalid_ranges passed\n");
}

int
main ()
{
  std::printf ("=== Text Properties Tests (Phase 9.1) ===\n");

  test_empty ();
  test_put_get ();
  test_put_get_face ();
  test_remove ();
  test_remove_partial ();
  test_remove_all ();
  test_next_property_change ();
  test_for_each_in_range_key ();
  test_for_each_in_range_all ();
  test_adjust_insert_after ();
  test_adjust_insert_inside ();
  test_adjust_insert_start_not_sticky ();
  test_adjust_insert_end_rear_sticky ();
  test_adjust_delete_after ();
  test_adjust_delete_before ();
  test_adjust_delete_contained ();
  test_adjust_delete_spanning ();
  test_adjust_delete_left_overlap ();
  test_adjust_delete_right_overlap ();
  test_clear ();
  test_buffer_insert_adjusts ();
  test_buffer_delete_adjusts ();
  test_buffer_delete_backward_adjusts ();
  test_overwrite_property ();
  test_multiple_keys ();
  test_bridge_renders_faces ();
  test_merge_adjacent ();
  test_extern_c_bridge ();
  test_extern_c_put_face ();
  test_invalid_ranges ();

  std::printf ("\nAll 30 text properties tests passed!\n");
  return 0;
}
