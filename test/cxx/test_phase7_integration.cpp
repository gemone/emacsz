// test/cxx/test_phase7_integration.cpp
// Phase 7 End-to-End Integration Tests
//
// Tests the full pipeline:
//   InputEvent → CommandDispatcher → CommandRegistry → EmacsBuffer
//   Keymap lookups + basic editing commands
//   Minibuffer command execution and completion
//
// 12 integration tests.

#include <cassert>
#include <cstdio>
#include <cstdlib>

extern "C"
{
  void *lisp_malloc (size_t s) { return std::malloc (s); }
  void lisp_free (void *p) { std::free (p); }
  void *lisp_realloc (void *p, size_t s)
  {
    return std::realloc (p, s);
  }
}

#include "../../src/emacs_basic_commands.hpp"
#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_command_dispatcher.hpp"
#include "../../src/emacs_command_registry.hpp"
#include "../../src/emacs_keymap.hpp"
#include "../../src/emacs_minibuffer.hpp"
#include "../../src/emacs_undo.hpp"
#include "../../src/input_parser.hpp"

using namespace emacs;
using namespace emacs::tui;

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

static InputEvent
make_key_event (KeyCode code, KeyModifier mod = KeyModifier::None)
{
  return InputEvent::make_key (KeyEvent (code, mod, 0));
}

static void
reset_singletons ()
{
  CommandRegistry::instance ().clear ();
  KeymapManager::instance ().clear ();
  CommandDispatcher::instance ().reset ();
  Minibuffer::instance ().reset ();
}

static void
setup_basic_bindings ()
{
  register_basic_commands ();
  auto &global = KeymapManager::instance ().global_keymap ();
  global.bind (make_ctrl_keystroke ('f'), "forward-char");
  global.bind (make_ctrl_keystroke ('b'), "backward-char");
  global.bind (make_ctrl_keystroke ('a'), "beginning-of-line");
  global.bind (make_ctrl_keystroke ('e'), "end-of-line");
  global.bind (make_ctrl_keystroke ('d'), "delete-char");
  global.bind (make_ctrl_keystroke ('k'), "kill-line");
  global.bind (make_keystroke (KeyCode::Backspace),
	       "backward-delete-char");
  global.bind (make_keystroke (KeyCode::Enter), "newline");
}

static void
dispatch_text (const char *text, EmacsBuffer &buffer)
{
  for (const char *p = text; *p; ++p)
    {
      (void) CommandDispatcher::instance ()
	.dispatch (make_char_event (*p), &buffer);
    }
}

static void
dispatch_ctrl (char c, EmacsBuffer &buffer, int count = 1)
{
  for (int i = 0; i < count; ++i)
    {
      (void) CommandDispatcher::instance ()
	.dispatch (make_ctrl_event (c), &buffer);
    }
}

static gc_string
buffer_text (const EmacsBuffer &buffer)
{
  gc_string result;
  ptrdiff_t size = buffer.size ();
  if (size <= 0)
    return result;
  result.reserve (static_cast<size_t> (size));
  for (ptrdiff_t i = 1; i <= size; ++i)
    result.push_back (buffer.char_at (i));
  return result;
}

// ============================================================
// Test 1: Self-insert pipeline
// ============================================================
static void
test_self_insert_pipeline ()
{
  printf ("Testing self-insert pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*self-insert*");
  dispatch_text ("hello", buffer);

  assert (buffer_text (buffer) == gc_string ("hello"));
  printf ("✓ test_self_insert_pipeline passed\n");
}

// ============================================================
// Test 2: Movement pipeline
// ============================================================
static void
test_movement_pipeline ()
{
  printf ("Testing movement pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*movement*");
  dispatch_text ("hello", buffer);
  dispatch_ctrl ('b', buffer, 3);

  assert (buffer.point () == 3);
  printf ("✓ test_movement_pipeline passed\n");
}

// ============================================================
// Test 3: Delete pipeline
// ============================================================
static void
test_delete_pipeline ()
{
  printf ("Testing delete pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*delete*");
  dispatch_text ("abc", buffer);
  dispatch_ctrl ('b', buffer, 2);
  dispatch_ctrl ('d', buffer);

  assert (buffer_text (buffer) == gc_string ("ac"));
  printf ("✓ test_delete_pipeline passed\n");
}

// ============================================================
// Test 4: Backspace pipeline
// ============================================================
static void
test_backspace_pipeline ()
{
  printf ("Testing backspace pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*backspace*");
  dispatch_text ("abc", buffer);
  (void) CommandDispatcher::instance ()
    .dispatch (make_key_event (KeyCode::Backspace), &buffer);

  assert (buffer_text (buffer) == gc_string ("ab"));
  printf ("✓ test_backspace_pipeline passed\n");
}

// ============================================================
// Test 5: Newline pipeline
// ============================================================
static void
test_newline_pipeline ()
{
  printf ("Testing newline pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*newline*");
  dispatch_text ("hello", buffer);
  (void) CommandDispatcher::instance ().dispatch (make_key_event (
						    KeyCode::Enter),
						  &buffer);

  assert (buffer_text (buffer) == gc_string ("hello\n"));
  printf ("✓ test_newline_pipeline passed\n");
}

// ============================================================
// Test 6: Kill-line pipeline
// ============================================================
static void
test_kill_line_pipeline ()
{
  printf ("Testing kill-line pipeline...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*kill-line*");
  dispatch_text ("hello world", buffer);
  dispatch_ctrl ('a', buffer);
  dispatch_ctrl ('f', buffer, 5);
  dispatch_ctrl ('k', buffer);

  assert (buffer_text (buffer) == gc_string ("hello"));
  printf ("✓ test_kill_line_pipeline passed\n");
}

// ============================================================
// Test 7: Beginning/end of line
// ============================================================
static void
test_beginning_end_of_line ()
{
  printf ("Testing beginning/end of line...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*bol-eol*");
  dispatch_text ("hello", buffer);
  (void) CommandDispatcher::instance ().dispatch (make_key_event (
						    KeyCode::Enter),
						  &buffer);
  dispatch_text ("world", buffer);
  dispatch_ctrl ('a', buffer);

  assert (buffer.point () == 7);
  dispatch_ctrl ('e', buffer);
  assert (buffer.point () == buffer.point_max ());
  printf ("✓ test_beginning_end_of_line passed\n");
}

// ============================================================
// Test 8: C-u prefix forward
// ============================================================
static void
test_cu_prefix_forward ()
{
  printf ("Testing C-u prefix forward...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer buffer ("*prefix*");
  dispatch_text ("abcdef", buffer);
  buffer.set_point (1);

  dispatch_ctrl ('u', buffer);
  dispatch_ctrl ('f', buffer);

  assert (buffer.point () == 5);
  printf ("✓ test_cu_prefix_forward passed\n");
}

// ============================================================
// Test 9: Minibuffer M-x setup
// ============================================================
static void
test_minibuffer_mx_setup ()
{
  printf ("Testing minibuffer M-x setup...\n");
  reset_singletons ();
  setup_basic_bindings ();

  minibuffer_execute_command ();
  Minibuffer &mini = Minibuffer::instance ();

  assert (mini.is_active ());
  assert (mini.prompt () == gc_string ("M-x "));

  mini.cancel ();
  printf ("✓ test_minibuffer_mx_setup passed\n");
}

// ============================================================
// Test 10: Minibuffer completion and execute
// ============================================================
static void
test_minibuffer_complete_and_execute ()
{
  printf ("Testing minibuffer completion...\n");
  reset_singletons ();
  setup_basic_bindings ();

  minibuffer_execute_command ();
  Minibuffer &mini = Minibuffer::instance ();

  mini.insert_char ('f');
  mini.insert_char ('o');
  mini.insert_char ('r');
  mini.insert_char ('w');
  mini.insert_char ('a');
  mini.insert_char ('r');
  mini.insert_char ('d');
  mini.complete ();

  const auto &completions = mini.completions ();
  assert (!completions.empty ());
  assert (completions.front () == gc_string ("forward-char"));
  assert (mini.input () == gc_string ("forward-char"));

  mini.cancel ();
  printf ("✓ test_minibuffer_complete_and_execute passed\n");
}

// ============================================================
// Test 11: Full editing session
// ============================================================
static void
test_full_editing_session ()
{
  printf ("Testing full editing session...\n");
  reset_singletons ();
  setup_basic_bindings ();

  UndoManager manager;
  (void) manager;

  KeymapManager::instance ()
    .global_keymap ()
    .bind (make_ctrl_keystroke ('z'), "undo");

  EmacsBuffer buffer ("*session*");
  dispatch_text ("hello world", buffer);
  dispatch_ctrl ('b', buffer, 6);
  dispatch_ctrl ('d', buffer);
  assert (buffer_text (buffer) == gc_string ("helloworld"));

  dispatch_ctrl ('z', buffer);
  assert (buffer_text (buffer) == gc_string ("hello world"));
  printf ("✓ test_full_editing_session passed\n");
}

// ============================================================
// Test 12: Multiple buffers
// ============================================================
static void
test_multiple_buffers ()
{
  printf ("Testing multiple buffers...\n");
  reset_singletons ();
  setup_basic_bindings ();

  EmacsBuffer first ("*first*");
  EmacsBuffer second ("*second*");

  dispatch_text ("one", first);
  dispatch_text ("two", second);

  dispatch_ctrl ('b', first, 2);
  dispatch_ctrl ('d', first);

  assert (buffer_text (first) == gc_string ("oe"));
  assert (buffer_text (second) == gc_string ("two"));
  printf ("✓ test_multiple_buffers passed\n");
}

// ============================================================
// Main
// ============================================================
int
main ()
{
  printf ("Running Phase 7 integration tests...\n\n");

  test_self_insert_pipeline ();
  test_movement_pipeline ();
  test_delete_pipeline ();
  test_backspace_pipeline ();
  test_newline_pipeline ();
  test_kill_line_pipeline ();
  test_beginning_end_of_line ();
  test_cu_prefix_forward ();
  test_minibuffer_mx_setup ();
  test_minibuffer_complete_and_execute ();
  test_full_editing_session ();
  test_multiple_buffers ();

  printf ("\n✅ All Phase 7 integration tests passed!\n");
  return 0;
}
