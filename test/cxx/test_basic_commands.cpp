// test/cxx/test_basic_commands.cpp
// Unit tests for Emacs basic commands

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_basic_commands.hpp"
#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_command_dispatcher.hpp"
#include "../../src/emacs_command_registry.hpp"
#include "../../src/emacs_keymap.hpp"
#include "../../src/emacs_undo.hpp"
#include "../../src/input_parser.hpp"

using namespace emacs;
using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

static void
reset_singletons ()
{
  CommandRegistry::instance ().clear ();
  CommandDispatcher::instance ().reset ();
  KeymapManager::instance ().clear ();
}

static InputEvent
make_char_event (char c)
{
  return InputEvent::make_key (
    KeyEvent (KeyCode::Unknown, KeyModifier::None,
	      static_cast<unsigned char> (c)));
}

static CommandContext
make_context (EmacsBuffer *buffer)
{
  CommandContext ctx;
  ctx.buffer = buffer;
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;
  return ctx;
}

static void
assert_buffer_equals (EmacsBuffer &buffer, const gc_string &expected)
{
  assert (buffer.size ()
	  == static_cast<ptrdiff_t> (expected.size ()));
  for (size_t i = 0; i < expected.size (); ++i)
    {
      assert (buffer.char_at (static_cast<ptrdiff_t> (i + 1))
	      == expected[i]);
    }
}

static void
test_register_basic_commands ()
{
  reset_singletons ();

  register_basic_commands ();

  CommandRegistry &reg = CommandRegistry::instance ();
  assert (reg.count () == 15);
  assert (reg.has_command ("self-insert-command"));
  assert (reg.has_command ("forward-char"));
  assert (reg.has_command ("backward-char"));
  assert (reg.has_command ("beginning-of-line"));
  assert (reg.has_command ("end-of-line"));
  assert (reg.has_command ("delete-char"));
  assert (reg.has_command ("backward-delete-char"));
  assert (reg.has_command ("newline"));
  assert (reg.has_command ("kill-line"));
  assert (reg.has_command ("undo"));
  assert (reg.has_command ("redo"));
  assert (reg.has_command ("beginning-of-buffer"));
  assert (reg.has_command ("end-of-buffer"));
  assert (reg.has_command ("next-line"));
  assert (reg.has_command ("previous-line"));

  std::printf ("✓ test_register_basic_commands passed\n");
}

static void
test_self_insert ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [] (CommandContext &) {});

  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'x'),
						  nullptr);

  EmacsBuffer buffer ("self-insert");
  CommandContext ctx = make_context (&buffer);
  cmd_self_insert (ctx);

  assert_buffer_equals (buffer, "x");

  std::printf ("✓ test_self_insert passed\n");
}

static void
test_self_insert_prefix ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [] (CommandContext &) {});

  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'x'),
						  nullptr);

  EmacsBuffer buffer ("self-insert-prefix");
  CommandContext ctx = make_context (&buffer);
  ctx.has_prefix = true;
  ctx.prefix_argument = 3;
  cmd_self_insert (ctx);

  assert_buffer_equals (buffer, "xxx");

  std::printf ("✓ test_self_insert_prefix passed\n");
}

static void
test_forward_char ()
{
  reset_singletons ();

  EmacsBuffer buffer ("forward", "abc");
  buffer.set_point (1);
  CommandContext ctx = make_context (&buffer);
  cmd_forward_char (ctx);

  assert (buffer.point () == 2);

  std::printf ("✓ test_forward_char passed\n");
}

static void
test_backward_char ()
{
  reset_singletons ();

  EmacsBuffer buffer ("backward", "abc");
  buffer.set_point (3);
  CommandContext ctx = make_context (&buffer);
  cmd_backward_char (ctx);

  assert (buffer.point () == 2);

  std::printf ("✓ test_backward_char passed\n");
}

static void
test_forward_char_prefix ()
{
  reset_singletons ();

  EmacsBuffer buffer ("forward-prefix", "abcdef");
  buffer.set_point (1);
  CommandContext ctx = make_context (&buffer);
  ctx.has_prefix = true;
  ctx.prefix_argument = 3;
  cmd_forward_char (ctx);

  assert (buffer.point () == 4);

  std::printf ("✓ test_forward_char_prefix passed\n");
}

static void
test_beginning_of_line ()
{
  reset_singletons ();

  EmacsBuffer buffer ("bol", "hello\nworld");
  buffer.set_point (7);
  CommandContext ctx = make_context (&buffer);
  cmd_beginning_of_line (ctx);

  assert (buffer.point () == 7);

  std::printf ("✓ test_beginning_of_line passed\n");
}

static void
test_end_of_line ()
{
  reset_singletons ();

  EmacsBuffer buffer ("eol", "hello\nworld");
  buffer.set_point (2);
  CommandContext ctx = make_context (&buffer);
  cmd_end_of_line (ctx);

  assert (buffer.point () == 6);

  std::printf ("✓ test_end_of_line passed\n");
}

static void
test_delete_char ()
{
  reset_singletons ();

  EmacsBuffer buffer ("delete-char", "abc");
  buffer.set_point (2);
  CommandContext ctx = make_context (&buffer);
  cmd_delete_char (ctx);

  assert_buffer_equals (buffer, "ac");

  std::printf ("✓ test_delete_char passed\n");
}

static void
test_backward_delete_char ()
{
  reset_singletons ();

  EmacsBuffer buffer ("backward-delete", "abc");
  buffer.set_point (3);
  CommandContext ctx = make_context (&buffer);
  cmd_backward_delete_char (ctx);

  assert_buffer_equals (buffer, "ac");

  std::printf ("✓ test_backward_delete_char passed\n");
}

static void
test_newline ()
{
  reset_singletons ();

  EmacsBuffer buffer ("newline", "ab");
  buffer.set_point (2);
  CommandContext ctx = make_context (&buffer);
  cmd_newline (ctx);

  assert_buffer_equals (buffer, "a\nb");

  std::printf ("✓ test_newline passed\n");
}

static void
test_kill_line ()
{
  reset_singletons ();

  EmacsBuffer buffer ("kill-line", "hello\nworld");
  buffer.set_point (2);
  CommandContext ctx = make_context (&buffer);
  cmd_kill_line (ctx);

  assert_buffer_equals (buffer, "h\nworld");

  std::printf ("✓ test_kill_line passed\n");
}

static void
test_kill_line_at_newline ()
{
  reset_singletons ();

  EmacsBuffer buffer ("kill-line-newline", "hello\nworld");
  buffer.set_point (6);
  CommandContext ctx = make_context (&buffer);
  cmd_kill_line (ctx);

  assert_buffer_equals (buffer, "helloworld");

  std::printf ("✓ test_kill_line_at_newline passed\n");
}

static void
test_undo ()
{
  reset_singletons ();

  UndoManager manager;
  (void) manager;

  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [] (CommandContext &) {});

  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'x'),
						  nullptr);

  EmacsBuffer buffer ("undo");
  CommandContext ctx = make_context (&buffer);
  cmd_self_insert (ctx);

  CommandContext undo_ctx = make_context (&buffer);
  cmd_undo (undo_ctx);

  assert (buffer.empty ());

  std::printf ("✓ test_undo passed\n");
}

static void
test_redo ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [] (CommandContext &) {});

  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'x'),
						  nullptr);

  EmacsBuffer buffer ("redo");
  CommandContext ctx = make_context (&buffer);
  cmd_self_insert (ctx);

  CommandContext undo_ctx = make_context (&buffer);
  cmd_undo (undo_ctx);

  CommandContext redo_ctx = make_context (&buffer);
  cmd_redo (redo_ctx);

  assert_buffer_equals (buffer, "x");

  std::printf ("✓ test_redo passed\n");
}

static void
test_beginning_of_buffer ()
{
  reset_singletons ();

  EmacsBuffer buffer ("bob", "abc");
  buffer.set_point (3);
  CommandContext ctx = make_context (&buffer);
  cmd_beginning_of_buffer (ctx);

  assert (buffer.point () == 1);

  std::printf ("✓ test_beginning_of_buffer passed\n");
}

static void
test_end_of_buffer ()
{
  reset_singletons ();

  EmacsBuffer buffer ("eob", "abc");
  buffer.set_point (1);
  CommandContext ctx = make_context (&buffer);
  cmd_end_of_buffer (ctx);

  assert (buffer.point () == buffer.point_max ());

  std::printf ("✓ test_end_of_buffer passed\n");
}

static void
test_next_line ()
{
  reset_singletons ();

  EmacsBuffer buffer ("next-line", "one\ntwo\nthree");
  buffer.set_point (2);
  CommandContext ctx = make_context (&buffer);
  cmd_next_line (ctx);

  assert (buffer.point () == 6);

  std::printf ("✓ test_next_line passed\n");
}

static void
test_previous_line ()
{
  reset_singletons ();

  EmacsBuffer buffer ("prev-line", "one\ntwo\nthree");
  buffer.set_point (9);
  CommandContext ctx = make_context (&buffer);
  cmd_previous_line (ctx);

  assert (buffer.point () == 9);

  std::printf ("✓ test_previous_line passed\n");
}

static void
test_next_line_preserves_column ()
{
  reset_singletons ();

  EmacsBuffer buffer ("next-line-column", "hello\nworld");
  buffer.set_point (3);
  CommandContext ctx = make_context (&buffer);
  cmd_next_line (ctx);

  assert (buffer.point () == 9);

  std::printf ("✓ test_next_line_preserves_column passed\n");
}

static void
test_null_buffer_safety ()
{
  reset_singletons ();

  CommandContext ctx = make_context (nullptr);

  cmd_self_insert (ctx);
  cmd_forward_char (ctx);
  cmd_backward_char (ctx);
  cmd_beginning_of_line (ctx);
  cmd_end_of_line (ctx);
  cmd_delete_char (ctx);
  cmd_backward_delete_char (ctx);
  cmd_newline (ctx);
  cmd_kill_line (ctx);
  cmd_undo (ctx);
  cmd_redo (ctx);
  cmd_beginning_of_buffer (ctx);
  cmd_end_of_buffer (ctx);
  cmd_next_line (ctx);
  cmd_previous_line (ctx);

  assert (true);

  std::printf ("✓ test_null_buffer_safety passed\n");
}

int
main ()
{
  std::printf ("Running basic commands tests...\n\n");

  test_register_basic_commands ();
  test_self_insert ();
  test_self_insert_prefix ();
  test_forward_char ();
  test_backward_char ();
  test_forward_char_prefix ();
  test_beginning_of_line ();
  test_end_of_line ();
  test_delete_char ();
  test_backward_delete_char ();
  test_newline ();
  test_kill_line ();
  test_kill_line_at_newline ();
  test_undo ();
  test_redo ();
  test_beginning_of_buffer ();
  test_end_of_buffer ();
  test_next_line ();
  test_previous_line ();
  test_next_line_preserves_column ();
  test_null_buffer_safety ();

  std::printf ("\n✅ All basic commands tests passed!\n");
  return 0;
}
