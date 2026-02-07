// Unit tests for EmacsBuffer + Marker (Phase 6.2-6.3)

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../../src/emacs_buffer.hpp"

using namespace emacs;

// Stubs for Emacs GC allocator
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

static int g_tests_run = 0;

static void
assert_content (const EmacsBuffer &buffer, const char *expected)
{
  std::string content = buffer.content ();
  assert (content == expected);
}

static void
test_create_buffer ()
{
  std::printf ("Testing create buffer...\n");
  EmacsBuffer buffer ("scratch");
  assert (buffer.size () == 0);
  assert (buffer.empty ());
  assert (buffer.point () == 1);
  assert (buffer.name () == "scratch");
  std::printf ("\xe2\x9c\x93 create buffer passed\n");
  ++g_tests_run;
}

static void
test_create_with_text ()
{
  std::printf ("Testing create with text...\n");
  EmacsBuffer buffer ("init", "hello");
  assert (buffer.size () == 5);
  assert (!buffer.empty ());
  assert (buffer.point () == 6);
  assert_content (buffer, "hello");
  std::printf ("\xe2\x9c\x93 create with text passed\n");
  ++g_tests_run;
}

static void
test_buffer_name ()
{
  std::printf ("Testing buffer name...\n");
  EmacsBuffer buffer ("scratch");
  assert (buffer.name () == "scratch");
  buffer.set_name ("notes");
  assert (buffer.name () == "notes");
  std::printf ("\xe2\x9c\x93 buffer name passed\n");
  ++g_tests_run;
}

static void
test_insert_char ()
{
  std::printf ("Testing insert char...\n");
  EmacsBuffer buffer ("buf");
  assert (!buffer.is_modified ());
  buffer.insert_char ('A');
  assert_content (buffer, "A");
  assert (buffer.point () == 2);
  assert (buffer.is_modified ());
  std::printf ("\xe2\x9c\x93 insert char passed\n");
  ++g_tests_run;
}

static void
test_insert_string ()
{
  std::printf ("Testing insert string...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_string ("hello");
  assert_content (buffer, "hello");
  assert (buffer.point () == 6);
  std::printf ("\xe2\x9c\x93 insert string passed\n");
  ++g_tests_run;
}

static void
test_delete_forward ()
{
  std::printf ("Testing delete forward...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (2);
  buffer.delete_forward (1);
  assert_content (buffer, "hllo");
  assert (buffer.point () == 2);
  std::printf ("\xe2\x9c\x93 delete forward passed\n");
  ++g_tests_run;
}

static void
test_delete_backward ()
{
  std::printf ("Testing delete backward...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (3);
  buffer.delete_backward (1);
  assert_content (buffer, "hllo");
  assert (buffer.point () == 2);
  std::printf ("\xe2\x9c\x93 delete backward passed\n");
  ++g_tests_run;
}

static void
test_point_movement ()
{
  std::printf ("Testing point movement...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (1);
  assert (buffer.point () == 1);
  buffer.set_point (4);
  assert (buffer.point () == 4);
  buffer.set_point (6);
  assert (buffer.point () == 6);
  std::printf ("\xe2\x9c\x93 point movement passed\n");
  ++g_tests_run;
}

static void
test_content_range ()
{
  std::printf ("Testing content range...\n");
  EmacsBuffer buffer ("buf", "hello world");
  std::string part = buffer.content_range (1, 6);
  assert (part == "hello");
  part = buffer.content_range (7, 12);
  assert (part == "world");
  std::printf ("\xe2\x9c\x93 content range passed\n");
  ++g_tests_run;
}

static void
test_modified_flag ()
{
  std::printf ("Testing modified flag...\n");
  EmacsBuffer buffer ("buf", "hi");
  assert (!buffer.is_modified ());
  buffer.insert_char ('X');
  assert (buffer.is_modified ());
  buffer.set_modified (false);
  assert (!buffer.is_modified ());
  buffer.delete_backward (1);
  assert (buffer.is_modified ());
  std::printf ("\xe2\x9c\x93 modified flag passed\n");
  ++g_tests_run;
}

static void
test_marker_create ()
{
  std::printf ("Testing marker create...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 3);
  assert (marker.position () == 3);
  assert (marker.buffer () == &buffer);
  assert (buffer.marker_count () == 1);
  std::printf ("\xe2\x9c\x93 marker create passed\n");
  ++g_tests_run;
}

static void
test_marker_default_insertion_type ()
{
  std::printf ("Testing marker default insertion type...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 3);
  buffer.set_point (3);
  buffer.insert_string ("XX");
  assert (marker.position () == 3);
  assert_content (buffer, "heXXllo");
  std::printf ("\xe2\x9c\x93 marker default insertion type passed\n");
  ++g_tests_run;
}

static void
test_marker_auto_unregister ()
{
  std::printf ("Testing marker auto unregister...\n");
  EmacsBuffer buffer ("buf", "hello");
  assert (buffer.marker_count () == 0);
  {
    Marker marker (&buffer, 2);
    assert (buffer.marker_count () == 1);
  }
  assert (buffer.marker_count () == 0);
  std::printf ("\xe2\x9c\x93 marker auto unregister passed\n");
  ++g_tests_run;
}

static void
test_marker_adjust_insert_after ()
{
  std::printf ("Testing marker insert adjust (after)...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 4);
  buffer.set_point (2);
  buffer.insert_string ("XX");
  assert (marker.position () == 6);
  assert_content (buffer, "hXXello");
  std::printf ("\xe2\x9c\x93 marker insert adjust (after) passed\n");
  ++g_tests_run;
}

static void
test_marker_adjust_insert_before ()
{
  std::printf ("Testing marker insert adjust (before)...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 3, MarkerInsertionType::BEFORE_INSERTION);
  buffer.set_point (3);
  buffer.insert_string ("XX");
  assert (marker.position () == 3);
  assert_content (buffer, "heXXllo");
  std::printf ("\xe2\x9c\x93 marker insert adjust (before) passed\n");
  ++g_tests_run;
}

static void
test_marker_adjust_insert_at_after_type ()
{
  std::printf ("Testing marker insert adjust (after type)...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 3, MarkerInsertionType::AFTER_INSERTION);
  buffer.set_point (3);
  buffer.insert_string ("XX");
  assert (marker.position () == 5);
  assert_content (buffer, "heXXllo");
  std::printf (
    "\xe2\x9c\x93 marker insert adjust (after type) passed\n");
  ++g_tests_run;
}

static void
test_marker_adjust_delete ()
{
  std::printf ("Testing marker delete adjust...\n");
  EmacsBuffer buffer ("buf", "abcdef");
  Marker marker (&buffer, 5);
  buffer.set_point (2);
  buffer.delete_forward (2);
  assert (marker.position () == 3);
  assert_content (buffer, "adef");
  std::printf ("\xe2\x9c\x93 marker delete adjust passed\n");
  ++g_tests_run;
}

static void
test_marker_adjust_delete_through ()
{
  std::printf ("Testing marker delete through range...\n");
  EmacsBuffer buffer ("buf", "abcdef");
  Marker marker (&buffer, 4);
  buffer.set_point (2);
  buffer.delete_forward (3);
  assert (marker.position () == 2);
  assert_content (buffer, "aef");
  std::printf ("\xe2\x9c\x93 marker delete through range passed\n");
  ++g_tests_run;
}

static void
test_multiple_markers ()
{
  std::printf ("Testing multiple markers...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker first (&buffer, 2);
  Marker second (&buffer, 5, MarkerInsertionType::BEFORE_INSERTION);
  Marker third (&buffer, 6);

  buffer.set_point (3);
  buffer.insert_string ("XX");
  assert (first.position () == 2);
  assert (second.position () == 7);
  assert (third.position () == 8);

  buffer.set_point (2);
  buffer.delete_forward (2);
  assert (first.position () == 2);
  assert (second.position () == 5);
  assert (third.position () == 6);
  std::printf ("\xe2\x9c\x93 multiple markers passed\n");
  ++g_tests_run;
}

static void
test_marker_buffer_ref ()
{
  std::printf ("Testing marker buffer reference...\n");
  EmacsBuffer buffer ("buf", "hello");
  Marker marker (&buffer, 2);
  assert (marker.buffer () == &buffer);
  std::printf ("\xe2\x9c\x93 marker buffer reference passed\n");
  ++g_tests_run;
}

static void
test_mark_set_and_exchange ()
{
  std::printf ("Testing mark set/exchange...\n");
  EmacsBuffer buffer ("buf", "hello");
  assert (!buffer.has_mark ());
  assert (buffer.mark () == 0);
  assert (!buffer.mark_active ());
  buffer.set_mark (2);
  assert (buffer.has_mark ());
  assert (buffer.mark () == 2);
  assert (buffer.mark_active ());
  buffer.deactivate_mark ();
  assert (!buffer.mark_active ());
  buffer.set_point (5);
  buffer.exchange_point_and_mark ();
  assert (buffer.point () == 2);
  assert (buffer.mark () == 5);
  std::printf ("\xe2\x9c\x93 mark set/exchange passed\n");
  ++g_tests_run;
}

static void
test_mark_adjust_on_edits ()
{
  std::printf ("Testing mark adjustment on edits...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_mark (3);
  buffer.set_point (3);
  buffer.insert_string ("XX");
  assert (buffer.mark () == 3);
  buffer.set_point (1);
  buffer.insert_char ('A');
  assert (buffer.mark () == 4);
  buffer.delete_forward (1);
  assert (buffer.mark () == 3);
  buffer.set_point (2);
  buffer.delete_forward (3);
  assert (buffer.mark () == 2);
  std::printf ("\xe2\x9c\x93 mark adjustment on edits passed\n");
  ++g_tests_run;
}

static void
test_region_helpers ()
{
  std::printf ("Testing region helpers...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (4);
  assert (buffer.region_beginning () == 4);
  assert (buffer.region_end () == 4);
  buffer.set_mark (2);
  assert (buffer.region_beginning () == 2);
  assert (buffer.region_end () == 4);
  std::printf ("\xe2\x9c\x93 region helpers passed\n");
  ++g_tests_run;
}

static void
test_narrowing_basic ()
{
  std::printf ("Testing narrowing basics...\n");
  EmacsBuffer buffer ("buf", "hello world");
  buffer.narrow_to_region (3, 8);
  assert (buffer.is_narrowed ());
  assert (buffer.point_min () == 3);
  assert (buffer.point_max () == 8);
  buffer.set_point (1);
  assert (buffer.point () == 3);
  buffer.set_point (20);
  assert (buffer.point () == 8);
  buffer.widen ();
  assert (!buffer.is_narrowed ());
  assert (buffer.point_min () == 1);
  assert (buffer.point_max () == buffer.size () + 1);
  std::printf ("\xe2\x9c\x93 narrowing basics passed\n");
  ++g_tests_run;
}

static void
test_narrowing_insert_delete ()
{
  std::printf ("Testing narrowing insert/delete...\n");
  EmacsBuffer buffer ("buf", "abcdef");
  buffer.narrow_to_region (2, 5);
  buffer.set_point (2);
  buffer.insert_string ("XX");
  assert (buffer.point_max () == 7);
  assert_content (buffer, "aXXbcdef");
  buffer.set_point (3);
  buffer.delete_forward (2);
  assert (buffer.point_max () == 5);
  assert_content (buffer, "aXcdef");
  buffer.set_point (1);
  buffer.insert_char ('Z');
  assert_content (buffer, "aZXcdef");
  std::printf ("\xe2\x9c\x93 narrowing insert/delete passed\n");
  ++g_tests_run;
}

static void
test_undo_insert_and_redo ()
{
  std::printf ("Testing undo/redo insert...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_string ("hello");
  assert (buffer.undo_manager ().can_undo ());
  buffer.undo ();
  assert_content (buffer, "");
  assert (buffer.undo_manager ().can_redo ());
  buffer.redo ();
  assert_content (buffer, "hello");
  std::printf ("\xe2\x9c\x93 undo/redo insert passed\n");
  ++g_tests_run;
}

static void
test_undo_delete_forward ()
{
  std::printf ("Testing undo delete forward...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (2);
  buffer.delete_forward (2);
  assert_content (buffer, "hlo");
  buffer.undo ();
  assert_content (buffer, "hello");
  std::printf ("\xe2\x9c\x93 undo delete forward passed\n");
  ++g_tests_run;
}

static void
test_undo_delete_backward ()
{
  std::printf ("Testing undo delete backward...\n");
  EmacsBuffer buffer ("buf", "hello");
  buffer.set_point (4);
  buffer.delete_backward (2);
  assert_content (buffer, "hlo");
  buffer.undo ();
  assert_content (buffer, "hello");
  std::printf ("\xe2\x9c\x93 undo delete backward passed\n");
  ++g_tests_run;
}

static void
test_undo_recording_inhibited ()
{
  std::printf ("Testing undo recording inhibition...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_string ("abc");
  buffer.undo ();
  assert (!buffer.undo_manager ().can_undo ());
  assert (buffer.undo_manager ().can_redo ());
  buffer.redo ();
  assert (buffer.undo_manager ().can_undo ());
  assert (!buffer.undo_manager ().can_redo ());
  std::printf ("\xe2\x9c\x93 undo recording inhibition passed\n");
  ++g_tests_run;
}

static void
test_self_insert_amalgamation ()
{
  std::printf ("Testing self-insert amalgamation...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_char ('a');
  buffer.insert_char ('b');
  buffer.insert_char ('c');
  buffer.undo ();
  assert_content (buffer, "");
  std::printf ("\xe2\x9c\x93 self-insert amalgamation passed\n");
  ++g_tests_run;
}

static void
test_self_insert_group_split ()
{
  std::printf ("Testing self-insert group split...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_char ('a');
  buffer.insert_char ('b');
  buffer.set_point (1);
  buffer.insert_char ('c');
  buffer.undo ();
  assert_content (buffer, "ab");
  buffer.undo ();
  assert_content (buffer, "");
  std::printf ("\xe2\x9c\x93 self-insert group split passed\n");
  ++g_tests_run;
}

static void
test_self_insert_flush_on_insert_string ()
{
  std::printf ("Testing self-insert flush on insert string...\n");
  EmacsBuffer buffer ("buf");
  buffer.insert_char ('a');
  buffer.insert_char ('b');
  buffer.insert_string ("ZZ");
  buffer.undo ();
  assert_content (buffer, "ab");
  buffer.undo ();
  assert_content (buffer, "");
  std::printf (
    "\xe2\x9c\x93 self-insert flush on insert string passed\n");
  ++g_tests_run;
}

static void
test_extern_c_api ()
{
  std::printf ("Testing extern C API...\n");
  void *buf = emacs_cxx_create_buffer_with_text ("cbuf", "hello");
  assert (emacs_cxx_buffer_size (buf) == 5);
  assert (emacs_cxx_buffer_point (buf) == 6);
  emacs_cxx_buffer_set_point (buf, 1);
  assert (emacs_cxx_buffer_point (buf) == 1);
  emacs_cxx_buffer_insert_char (buf, 'X');
  assert (emacs_cxx_buffer_size (buf) == 6);
  emacs_cxx_buffer_delete_forward (buf, 1);
  emacs_cxx_buffer_insert_string (buf, "YY");
  emacs_cxx_buffer_delete_backward (buf, 1);
  assert (emacs_cxx_buffer_is_modified (buf) == 1);
  emacs_cxx_destroy_buffer (buf);
  std::printf ("\xe2\x9c\x93 extern C API passed\n");
  ++g_tests_run;
}

int
main ()
{
  std::printf ("=== Emacs Buffer Tests (Phase 6.2-6.3) ===\n\n");

  test_create_buffer ();
  test_create_with_text ();
  test_buffer_name ();
  test_insert_char ();
  test_insert_string ();
  test_delete_forward ();
  test_delete_backward ();
  test_point_movement ();
  test_content_range ();
  test_modified_flag ();
  test_marker_create ();
  test_marker_default_insertion_type ();
  test_marker_auto_unregister ();
  test_marker_adjust_insert_after ();
  test_marker_adjust_insert_before ();
  test_marker_adjust_insert_at_after_type ();
  test_marker_adjust_delete ();
  test_marker_adjust_delete_through ();
  test_multiple_markers ();
  test_marker_buffer_ref ();
  test_mark_set_and_exchange ();
  test_mark_adjust_on_edits ();
  test_region_helpers ();
  test_narrowing_basic ();
  test_narrowing_insert_delete ();
  test_undo_insert_and_redo ();
  test_undo_delete_forward ();
  test_undo_delete_backward ();
  test_undo_recording_inhibited ();
  test_self_insert_amalgamation ();
  test_self_insert_group_split ();
  test_self_insert_flush_on_insert_string ();
  test_extern_c_api ();

  std::printf ("\n=== All %d tests passed! ===\n", g_tests_run);
  return 0;
}
