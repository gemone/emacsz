// test/cxx/test_command_dispatcher.cpp
// Unit tests for Emacs command dispatcher

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_command_dispatcher.hpp"
#include "../../src/emacs_command_registry.hpp"
#include "../../src/emacs_keymap.hpp"
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
  CommandDispatcher::instance ().reset ();
  CommandDispatcher::instance ().set_pre_command_hook (
    PreCommandHook ());
  CommandDispatcher::instance ().set_post_command_hook (
    PostCommandHook ());
  CommandRegistry::instance ().clear ();
  KeymapManager::instance ().clear ();
}

static InputEvent
make_char_event (char c)
{
  return InputEvent::make_key (
    KeyEvent (KeyCode::Unknown, KeyModifier::None,
	      static_cast<unsigned char> (c)));
}

static InputEvent
make_ctrl_event (char c)
{
  return InputEvent::make_key (
    KeyEvent (KeyCode::Unknown, KeyModifier::Ctrl,
	      static_cast<unsigned char> (c)));
}

static void
test_dispatch_non_key ()
{
  reset_singletons ();

  InputEvent ev = InputEvent::make_resize (24, 80);
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (ev, nullptr);

  assert (result == DispatchResult::Unbound);

  std::printf ("test_dispatch_non_key passed\n");
}

static void
test_dispatch_unbound_key ()
{
  reset_singletons ();

  InputEvent ev = make_ctrl_event ('f');
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (ev, nullptr);

  assert (result == DispatchResult::Unbound);

  std::printf ("test_dispatch_unbound_key passed\n");
}

static void
test_dispatch_bound_command ()
{
  reset_singletons ();

  bool called = false;
  CommandRegistry::instance ()
    .register_command ("forward-char", [&called] (CommandContext &)
			 { called = true; });
  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('f'), "forward-char");

  InputEvent ev = make_ctrl_event ('f');
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (ev, nullptr);

  assert (result == DispatchResult::Executed);
  assert (called);

  std::printf ("test_dispatch_bound_command passed\n");
}

static void
test_dispatch_self_insert ()
{
  reset_singletons ();

  bool called = false;
  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [&called] (CommandContext &)
			 { called = true; });

  InputEvent ev = make_char_event ('a');
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (ev, nullptr);

  assert (result == DispatchResult::SelfInsert);
  assert (called);

  std::printf ("test_dispatch_self_insert passed\n");
}

static void
test_dispatch_self_insert_fallback ()
{
  reset_singletons ();

  EmacsBuffer buffer ("test");
  InputEvent ev = make_char_event ('a');
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (ev, &buffer);

  assert (result == DispatchResult::SelfInsert);
  assert (buffer.size () == 1);
  assert (buffer.char_at (1) == 'a');

  std::printf ("test_dispatch_self_insert_fallback passed\n");
}

static void
test_dispatch_prefix_key ()
{
  reset_singletons ();

  KeySequence seq;
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('f'));
  KeymapManager::instance ().global_keymap ().bind_sequence (seq,
							     "dummy");

  DispatchResult result
    = CommandDispatcher::instance ().dispatch (make_ctrl_event ('x'),
					       nullptr);

  assert (result == DispatchResult::Unbound);
  assert (CommandDispatcher::instance ().pending_keys ().empty ());
  assert (CommandDispatcher::instance ().message ().empty ());

  std::printf ("test_dispatch_prefix_key passed\n");
}

static void
test_dispatch_prefix_sequence ()
{
  reset_singletons ();

  bool called = false;
  CommandRegistry::instance ()
    .register_command ("find-file", [&called] (CommandContext &)
			 { called = true; });

  KeySequence seq;
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('f'));
  KeymapManager::instance ()
    .global_keymap ()
    .bind_sequence (seq, "find-file");

  DispatchResult first
    = CommandDispatcher::instance ().dispatch (make_ctrl_event ('x'),
					       nullptr);
  DispatchResult second
    = CommandDispatcher::instance ().dispatch (make_ctrl_event ('f'),
					       nullptr);

  assert (first == DispatchResult::Unbound);
  assert (second == DispatchResult::Unbound);
  assert (!called);

  std::printf ("test_dispatch_prefix_sequence passed\n");
}

static void
test_dispatch_cu_prefix ()
{
  reset_singletons ();

  DispatchResult result
    = CommandDispatcher::instance ().dispatch (make_ctrl_event ('u'),
					       nullptr);

  assert (result == DispatchResult::Executed);
  assert (CommandDispatcher::instance ().has_prefix_argument ());
  assert (CommandDispatcher::instance ().prefix_argument () == 4);

  std::printf ("test_dispatch_cu_prefix passed\n");
}

static void
test_dispatch_cu_cu_prefix ()
{
  reset_singletons ();

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'u'),
						  nullptr);
  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'u'),
						  nullptr);

  assert (CommandDispatcher::instance ().has_prefix_argument ());
  assert (CommandDispatcher::instance ().prefix_argument () == 16);

  std::printf ("test_dispatch_cu_cu_prefix passed\n");
}

static void
test_dispatch_prefix_cleared_after_command ()
{
  reset_singletons ();

  bool saw_prefix = false;
  CommandRegistry::instance ()
    .register_command ("dummy",
		       [&saw_prefix] (CommandContext &ctx)
			 {
			   saw_prefix = ctx.has_prefix
					&& ctx.prefix_argument == 4;
			 });
  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('f'), "dummy");

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'u'),
						  nullptr);
  DispatchResult result
    = CommandDispatcher::instance ().dispatch (make_ctrl_event ('f'),
					       nullptr);

  assert (result == DispatchResult::Executed);
  assert (saw_prefix);
  assert (!CommandDispatcher::instance ().has_prefix_argument ());
  assert (CommandDispatcher::instance ().prefix_argument () == 1);

  std::printf ("test_dispatch_prefix_cleared_after_command passed\n");
}

static void
test_dispatch_pending_keys ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("find-file", [] (CommandContext &) {});
  KeySequence seq;
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('f'));
  KeymapManager::instance ()
    .global_keymap ()
    .bind_sequence (seq, "find-file");

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'x'),
						  nullptr);
  assert (CommandDispatcher::instance ().pending_keys ().empty ());

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'f'),
						  nullptr);
  assert (CommandDispatcher::instance ().pending_keys ().empty ());

  std::printf ("test_dispatch_pending_keys passed\n");
}

static void
test_dispatch_message ()
{
  reset_singletons ();

  KeySequence seq;
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('x'));
  seq.push_back (make_ctrl_keystroke ('f'));
  KeymapManager::instance ().global_keymap ().bind_sequence (seq,
							     "dummy");

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'x'),
						  nullptr);
  const gc_string &msg = CommandDispatcher::instance ().message ();

  assert (msg.empty ());

  std::printf ("test_dispatch_message passed\n");
}

static void
test_pre_command_hook ()
{
  reset_singletons ();

  bool called = false;
  gc_string seen;
  CommandDispatcher::instance ().set_pre_command_hook (
    [&called, &seen] (std::string_view name)
      {
	called = true;
	seen.assign (name.data (), name.size ());
      });

  CommandRegistry::instance ()
    .register_command ("forward-char", [] (CommandContext &) {});
  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('f'), "forward-char");

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'f'),
						  nullptr);

  assert (called);
  assert (seen == "forward-char");

  std::printf ("test_pre_command_hook passed\n");
}

static void
test_post_command_hook ()
{
  reset_singletons ();

  bool called = false;
  gc_string seen;
  CommandDispatcher::instance ().set_post_command_hook (
    [&called, &seen] (std::string_view name)
      {
	called = true;
	seen.assign (name.data (), name.size ());
      });

  CommandRegistry::instance ()
    .register_command ("forward-char", [] (CommandContext &) {});
  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('f'), "forward-char");

  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'f'),
						  nullptr);

  assert (called);
  assert (seen == "forward-char");

  std::printf ("test_post_command_hook passed\n");
}

static void
test_reset ()
{
  reset_singletons ();

  EmacsBuffer buffer ("reset");
  CommandDispatcher::instance ().set_current_buffer (&buffer);
  CommandDispatcher::instance ().set_prefix_argument (9);
  (void) KeymapManager::instance ()
    .global_keymap ()
    .get_or_create_prefix_keymap (make_ctrl_keystroke ('x'));
  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'x'),
						  &buffer);
  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'z'),
						  &buffer);

  CommandDispatcher::instance ().reset ();

  assert (CommandDispatcher::instance ().pending_keys ().empty ());
  assert (CommandDispatcher::instance ().message ().empty ());
  assert (!CommandDispatcher::instance ().has_prefix_argument ());
  assert (CommandDispatcher::instance ().prefix_argument () == 1);
  assert (CommandDispatcher::instance ().last_inserted_char () == 0);
  assert (CommandDispatcher::instance ().current_buffer ()
	  == nullptr);

  std::printf ("test_reset passed\n");
}

static void
test_last_inserted_char ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("self-insert-command",
		       [] (CommandContext &) {});

  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'x'),
						  nullptr);

  assert (CommandDispatcher::instance ().last_inserted_char ()
	  == 'x');

  std::printf ("test_last_inserted_char passed\n");
}

static void
test_extern_c_dispatch ()
{
  reset_singletons ();

  CommandRegistry::instance ()
    .register_command ("forward-char", [] (CommandContext &) {});
  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('f'), "forward-char");

  int result
    = emacs_cxx_dispatch_key (static_cast<int> (KeyCode::Unknown),
			      static_cast<int> (KeyModifier::Ctrl),
			      static_cast<unsigned int> ('f'),
			      nullptr);

  assert (result == static_cast<int> (DispatchResult::Executed));

  std::printf ("test_extern_c_dispatch passed\n");
}

static void
test_extern_c_reset ()
{
  reset_singletons ();

  (void) KeymapManager::instance ()
    .global_keymap ()
    .get_or_create_prefix_keymap (make_ctrl_keystroke ('x'));
  (void) CommandDispatcher::instance ().dispatch (make_ctrl_event (
						    'x'),
						  nullptr);
  CommandDispatcher::instance ().set_prefix_argument (3);
  (void) CommandDispatcher::instance ().dispatch (make_char_event (
						    'y'),
						  nullptr);

  emacs_cxx_dispatch_reset ();

  assert (CommandDispatcher::instance ().pending_keys ().empty ());
  assert (CommandDispatcher::instance ().message ().empty ());
  assert (!CommandDispatcher::instance ().has_prefix_argument ());
  assert (CommandDispatcher::instance ().prefix_argument () == 1);
  assert (CommandDispatcher::instance ().last_inserted_char () == 0);

  std::printf ("test_extern_c_reset passed\n");
}

int
main ()
{
  std::printf ("Running command dispatcher tests...\n\n");

  test_dispatch_non_key ();
  test_dispatch_unbound_key ();
  test_dispatch_bound_command ();
  test_dispatch_self_insert ();
  test_dispatch_self_insert_fallback ();
  test_dispatch_prefix_key ();
  test_dispatch_prefix_sequence ();
  test_dispatch_cu_prefix ();
  test_dispatch_cu_cu_prefix ();
  test_dispatch_prefix_cleared_after_command ();
  test_dispatch_pending_keys ();
  test_dispatch_message ();
  test_pre_command_hook ();
  test_post_command_hook ();
  test_reset ();
  test_last_inserted_char ();
  test_extern_c_dispatch ();
  test_extern_c_reset ();

  std::printf ("\n✅ All command dispatcher tests passed!\n");
  return 0;
}
