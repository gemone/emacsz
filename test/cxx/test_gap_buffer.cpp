// Unit tests for GapBuffer (Phase 6.1)

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../../src/gap_buffer.hpp"

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
assert_content (const GapBuffer &buffer, const char *expected)
{
  std::string content = buffer.content ();
  assert (content == expected);
}

static void
test_empty_buffer ()
{
  std::printf ("Testing empty buffer...\n");
  GapBuffer buffer;
  assert (buffer.size () == 0);
  assert (buffer.empty ());
  assert (buffer.point () == 1);
  assert (buffer.point_min () == 1);
  assert (buffer.point_max () == 1);
  assert_content (buffer, "");
  std::printf ("\xe2\x9c\x93 empty buffer passed\n");
  ++g_tests_run;
}

static void
test_construct_with_text ()
{
  std::printf ("Testing construct with text...\n");
  GapBuffer buffer ("hello");
  assert (buffer.size () == 5);
  assert (!buffer.empty ());
  assert (buffer.point () == 6);
  assert_content (buffer, "hello");
  std::printf ("\xe2\x9c\x93 construct with text passed\n");
  ++g_tests_run;
}

static void
test_insert_char_at_beginning ()
{
  std::printf ("Testing insert char at beginning...\n");
  GapBuffer buffer ("hello");
  buffer.set_point (1);
  buffer.insert_char ('X');
  assert_content (buffer, "Xhello");
  assert (buffer.point () == 2);
  std::printf ("\xe2\x9c\x93 insert char at beginning passed\n");
  ++g_tests_run;
}

static void
test_insert_char_at_end ()
{
  std::printf ("Testing insert char at end...\n");
  GapBuffer buffer ("hello");
  buffer.set_point (6);
  buffer.insert_char ('X');
  assert_content (buffer, "helloX");
  assert (buffer.point () == 7);
  std::printf ("\xe2\x9c\x93 insert char at end passed\n");
  ++g_tests_run;
}

static void
test_insert_char_at_middle ()
{
  std::printf ("Testing insert char at middle...\n");
  GapBuffer buffer ("hello");
  buffer.set_point (3);
  buffer.insert_char ('X');
  assert_content (buffer, "heXllo");
  assert (buffer.point () == 4);
  std::printf ("\xe2\x9c\x93 insert char at middle passed\n");
  ++g_tests_run;
}

static void
test_insert_string ()
{
  std::printf ("Testing insert string...\n");
  GapBuffer buffer ("hello");
  buffer.set_point (3);
  buffer.insert_string ("-gap-");
  assert_content (buffer, "he-gap-llo");
  assert (buffer.point () == 8);
  std::printf ("\xe2\x9c\x93 insert string passed\n");
  ++g_tests_run;
}

static void
test_delete_forward ()
{
  std::printf ("Testing delete forward...\n");
  GapBuffer buffer ("hello");
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
  GapBuffer buffer ("hello");
  buffer.set_point (3);
  buffer.delete_backward (1);
  assert_content (buffer, "hllo");
  assert (buffer.point () == 2);
  std::printf ("\xe2\x9c\x93 delete backward passed\n");
  ++g_tests_run;
}

static void
test_delete_multiple ()
{
  std::printf ("Testing delete multiple...\n");
  GapBuffer buffer ("abcdef");
  buffer.set_point (3);
  buffer.delete_forward (3);
  assert_content (buffer, "abf");
  buffer.delete_backward (2);
  assert_content (buffer, "f");
  assert (buffer.point () == 1);
  std::printf ("\xe2\x9c\x93 delete multiple passed\n");
  ++g_tests_run;
}

static void
test_point_movement ()
{
  std::printf ("Testing point movement...\n");
  GapBuffer buffer ("hello");
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
test_char_at ()
{
  std::printf ("Testing char_at...\n");
  GapBuffer buffer ("hello");
  assert (buffer.char_at (1) == 'h');
  assert (buffer.char_at (2) == 'e');
  assert (buffer.char_at (5) == 'o');
  std::printf ("\xe2\x9c\x93 char_at passed\n");
  ++g_tests_run;
}

static void
test_content_range ()
{
  std::printf ("Testing content_range...\n");
  GapBuffer buffer ("hello world");
  std::string part = buffer.content_range (1, 6);
  assert (part == "hello");
  part = buffer.content_range (7, 12);
  assert (part == "world");
  std::printf ("\xe2\x9c\x93 content_range passed\n");
  ++g_tests_run;
}

static void
test_gap_grows ()
{
  std::printf ("Testing gap growth...\n");
  GapBuffer buffer;
  ptrdiff_t initial_gap = buffer.gap_size ();
  std::string big (static_cast<size_t> (initial_gap + 10), 'a');
  buffer.insert_string (big);
  assert (buffer.size () == static_cast<ptrdiff_t> (big.size ()));
  assert (buffer.gap_size () >= 256);
  std::printf ("\xe2\x9c\x93 gap growth passed\n");
  ++g_tests_run;
}

static void
test_large_insert ()
{
  std::printf ("Testing large insert...\n");
  GapBuffer buffer;
  std::string payload (1200, 'x');
  buffer.insert_string (payload);
  assert (buffer.size () == 1200);
  assert_content (buffer, payload.c_str ());
  std::printf ("\xe2\x9c\x93 large insert passed\n");
  ++g_tests_run;
}

static void
test_mixed_operations ()
{
  std::printf ("Testing mixed operations...\n");
  GapBuffer buffer ("hello");
  buffer.set_point (6);
  buffer.insert_string (" world");
  buffer.set_point (6);
  buffer.insert_char ('X');
  buffer.delete_backward (1);
  buffer.set_point (1);
  buffer.insert_string ("Say: ");
  assert_content (buffer, "Say: hello world");
  std::printf ("\xe2\x9c\x93 mixed operations passed\n");
  ++g_tests_run;
}

static void
test_utf8_content ()
{
  std::printf ("Testing UTF-8 content...\n");
  const char *text = "h\xe2\x98\x83\xe4\xb8\x96\xe7\x95\x8c";
  GapBuffer buffer;
  buffer.insert_string (text);
  assert_content (buffer, text);
  buffer.set_point (2);
  buffer.delete_forward (1);
  assert_content (buffer, "h\xe4\xb8\x96\xe7\x95\x8c");
  buffer.delete_backward (1);
  assert_content (buffer, "\xe4\xb8\x96\xe7\x95\x8c");
  std::printf ("\xe2\x9c\x93 UTF-8 content passed\n");
  ++g_tests_run;
}

static void
test_boundary_conditions ()
{
  std::printf ("Testing boundary conditions...\n");
  GapBuffer buffer ("hi");
  buffer.set_point (1);
  buffer.delete_backward (1);
  assert_content (buffer, "hi");
  buffer.set_point (3);
  buffer.delete_forward (1);
  assert_content (buffer, "hi");
  buffer.set_point (1);
  buffer.insert_char ('X');
  buffer.set_point (buffer.point_max ());
  buffer.insert_char ('Y');
  assert_content (buffer, "XhiY");
  std::printf ("\xe2\x9c\x93 boundary conditions passed\n");
  ++g_tests_run;
}

int
main ()
{
  std::printf ("=== Gap Buffer Tests (Phase 6.1) ===\n\n");

  test_empty_buffer ();
  test_construct_with_text ();
  test_insert_char_at_beginning ();
  test_insert_char_at_end ();
  test_insert_char_at_middle ();
  test_insert_string ();
  test_delete_forward ();
  test_delete_backward ();
  test_delete_multiple ();
  test_point_movement ();
  test_char_at ();
  test_content_range ();
  test_gap_grows ();
  test_large_insert ();
  test_mixed_operations ();
  test_utf8_content ();
  test_boundary_conditions ();

  std::printf ("\n=== All %d tests passed! ===\n", g_tests_run);
  return 0;
}
