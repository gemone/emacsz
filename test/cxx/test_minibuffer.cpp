// test/cxx/test_minibuffer.cpp
// Unit tests for Emacs minibuffer

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_command_dispatcher.hpp"
#include "../../src/emacs_command_registry.hpp"
#include "../../src/emacs_keymap.hpp"
#include "../../src/emacs_minibuffer.hpp"

using namespace emacs;

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
  Minibuffer::instance ().reset ();
  Minibuffer::instance ().cancel ();
  CommandRegistry::instance ().clear ();
  CommandDispatcher::instance ().reset ();
  KeymapManager::instance ().clear ();
}

static void
insert_text (const char *text)
{
  for (size_t i = 0; text[i] != '\0'; ++i)
    Minibuffer::instance ().insert_char (text[i]);
}

static void
test_initial_state ()
{
  reset_singletons ();

  const Minibuffer &minibuffer = Minibuffer::instance ();

  assert (minibuffer.state () == MinibufferState::Inactive);
  assert (!minibuffer.is_active ());
  assert (minibuffer.input ().empty ());

  std::printf ("✓ test_initial_state passed\n");
}

static void
test_read_sets_state ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("Prompt: ");

  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Reading);
  assert (Minibuffer::instance ().is_active ());
  assert (Minibuffer::instance ().prompt () == "Prompt: ");

  std::printf ("✓ test_read_sets_state passed\n");
}

static void
test_insert_char ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("");
  insert_text ("abc");

  assert (Minibuffer::instance ().input () == "abc");
  assert (Minibuffer::instance ().cursor_position () == 3);

  std::printf ("✓ test_insert_char passed\n");
}

static void
test_delete_backward ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("");
  insert_text ("abc");
  Minibuffer::instance ().delete_backward ();

  assert (Minibuffer::instance ().input () == "ab");
  assert (Minibuffer::instance ().cursor_position () == 2);

  std::printf ("✓ test_delete_backward passed\n");
}

static void
test_delete_forward ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("");
  insert_text ("abc");
  Minibuffer::instance ().move_backward ();
  Minibuffer::instance ().delete_forward ();

  assert (Minibuffer::instance ().input () == "ab");
  assert (Minibuffer::instance ().cursor_position () == 2);

  std::printf ("✓ test_delete_forward passed\n");
}

static void
test_cursor_movement ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("");
  insert_text ("abc");

  Minibuffer::instance ().move_beginning ();
  assert (Minibuffer::instance ().cursor_position () == 0);
  Minibuffer::instance ().move_forward ();
  Minibuffer::instance ().move_forward ();
  assert (Minibuffer::instance ().cursor_position () == 2);
  Minibuffer::instance ().move_backward ();
  assert (Minibuffer::instance ().cursor_position () == 1);
  Minibuffer::instance ().move_end ();
  assert (Minibuffer::instance ().cursor_position () == 3);

  std::printf ("✓ test_cursor_movement passed\n");
}

static void
test_cursor_bounds ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("");
  insert_text ("a");

  Minibuffer::instance ().move_beginning ();
  Minibuffer::instance ().move_backward ();
  assert (Minibuffer::instance ().cursor_position () == 0);

  Minibuffer::instance ().move_end ();
  Minibuffer::instance ().move_forward ();
  assert (Minibuffer::instance ().cursor_position () == 1);

  std::printf ("✓ test_cursor_bounds passed\n");
}

static void
test_commit ()
{
  reset_singletons ();

  bool called = false;
  gc_string seen;
  Minibuffer::instance ().read ("Prompt: ",
				[&called,
				 &seen] (std::string_view input)
				  {
				    called = true;
				    seen.assign (input.data (),
						 input.size ());
				  });

  insert_text ("abc");
  Minibuffer::instance ().commit ();

  assert (called);
  assert (seen == "abc");
  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Inactive);
  assert (!Minibuffer::instance ().is_active ());
  assert (Minibuffer::instance ().result () == "abc");

  std::printf ("✓ test_commit passed\n");
}

static void
test_cancel ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("Prompt: ");
  insert_text ("abc");
  Minibuffer::instance ().cancel ();

  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Inactive);
  assert (Minibuffer::instance ().input ().empty ());
  assert (Minibuffer::instance ().prompt ().empty ());

  std::printf ("✓ test_cancel passed\n");
}

static void
test_display_text ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("Prompt: ");
  insert_text ("abc");

  assert (Minibuffer::instance ().display_text () == "Prompt: abc");

  std::printf ("✓ test_display_text passed\n");
}

static void
test_cursor_position_includes_prompt ()
{
  reset_singletons ();

  Minibuffer::instance ().read ("Prompt: ");
  insert_text ("abc");

  size_t expected = Minibuffer::instance ().prompt ().size () + 3;
  assert (Minibuffer::instance ().cursor_position () == expected);

  std::printf ("✓ test_cursor_position_includes_prompt passed\n");
}

static void
test_completion_single_match ()
{
  reset_singletons ();

  CompletionFn completion_fn = [] (std::string_view)
    {
      gc_vector_t<gc_string> matches;
      matches.push_back ("forward-char");
      return matches;
    };

  Minibuffer::instance ().read ("Prompt: ", nullptr, completion_fn);
  insert_text ("for");
  Minibuffer::instance ().complete ();

  assert (Minibuffer::instance ().input () == "forward-char");

  std::printf ("✓ test_completion_single_match passed\n");
}

static void
test_completion_common_prefix ()
{
  reset_singletons ();

  CompletionFn completion_fn = [] (std::string_view)
    {
      gc_vector_t<gc_string> matches;
      matches.push_back ("find-file");
      matches.push_back ("find-function");
      matches.push_back ("fin");
      return matches;
    };

  Minibuffer::instance ().read ("Prompt: ", nullptr, completion_fn);
  insert_text ("f");
  Minibuffer::instance ().complete ();

  assert (Minibuffer::instance ().input () == "fin");

  std::printf ("✓ test_completion_common_prefix passed\n");
}

static void
test_completion_no_match ()
{
  reset_singletons ();

  CompletionFn completion_fn = [] (std::string_view)
    {
      gc_vector_t<gc_string> matches;
      return matches;
    };

  Minibuffer::instance ().read ("Prompt: ", nullptr, completion_fn);
  insert_text ("none");
  Minibuffer::instance ().complete ();

  assert (Minibuffer::instance ().input () == "none");
  assert (Minibuffer::instance ().completions ().empty ());
  assert (Minibuffer::instance ().completion_index () == -1);

  std::printf ("✓ test_completion_no_match passed\n");
}

static void
test_completion_cycling ()
{
  reset_singletons ();

  CompletionFn completion_fn = [] (std::string_view)
    {
      gc_vector_t<gc_string> matches;
      matches.push_back ("xenon");
      matches.push_back ("xray");
      matches.push_back ("xylophone");
      return matches;
    };

  Minibuffer::instance ().read ("Prompt: ", nullptr, completion_fn);
  insert_text ("x");
  Minibuffer::instance ().complete ();

  assert (Minibuffer::instance ().completion_index () == 0);
  Minibuffer::instance ().next_completion ();
  assert (Minibuffer::instance ().input () == "xray");
  Minibuffer::instance ().prev_completion ();
  assert (Minibuffer::instance ().input () == "xenon");
  Minibuffer::instance ().prev_completion ();
  assert (Minibuffer::instance ().input () == "xylophone");

  std::printf ("✓ test_completion_cycling passed\n");
}

static void
test_echo_message ()
{
  reset_singletons ();

  Minibuffer::instance ().set_echo_message ("Echo");
  assert (Minibuffer::instance ().echo_message () == "Echo");
  Minibuffer::instance ().clear_echo_message ();
  assert (Minibuffer::instance ().echo_message ().empty ());

  std::printf ("✓ test_echo_message passed\n");
}

static void
test_minibuffer_execute_command ()
{
  reset_singletons ();

  bool called = false;
  CommandRegistry::instance ()
    .register_command ("forward-char", [&called] (CommandContext &)
			 { called = true; });
  CommandRegistry::instance ()
    .register_command ("find-file", [] (CommandContext &) {});

  minibuffer_execute_command ();
  assert (Minibuffer::instance ().prompt () == "M-x ");
  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Reading);

  insert_text ("forw");
  Minibuffer::instance ().complete ();
  assert (Minibuffer::instance ().input () == "forward-char");

  Minibuffer::instance ().commit ();
  assert (called);
  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Inactive);

  std::printf ("✓ test_minibuffer_execute_command passed\n");
}

static void
test_operations_ignored_when_inactive ()
{
  reset_singletons ();

  Minibuffer::instance ().insert_char ('a');
  Minibuffer::instance ().delete_backward ();
  Minibuffer::instance ().delete_forward ();
  Minibuffer::instance ().move_forward ();
  Minibuffer::instance ().move_backward ();
  Minibuffer::instance ().move_beginning ();
  Minibuffer::instance ().move_end ();

  assert (Minibuffer::instance ().state ()
	  == MinibufferState::Inactive);
  assert (Minibuffer::instance ().input ().empty ());
  assert (Minibuffer::instance ().cursor_position () == 0);

  std::printf ("✓ test_operations_ignored_when_inactive passed\n");
}

int
main ()
{
  std::printf ("Running minibuffer tests...\n\n");

  test_initial_state ();
  test_read_sets_state ();
  test_insert_char ();
  test_delete_backward ();
  test_delete_forward ();
  test_cursor_movement ();
  test_cursor_bounds ();
  test_commit ();
  test_cancel ();
  test_display_text ();
  test_cursor_position_includes_prompt ();
  test_completion_single_match ();
  test_completion_common_prefix ();
  test_completion_no_match ();
  test_completion_cycling ();
  test_echo_message ();
  test_minibuffer_execute_command ();
  test_operations_ignored_when_inactive ();

  std::printf ("\n✅ All minibuffer tests passed!\n");
  return 0;
}
