#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string_view>

#include "../../src/emacs_mode.hpp"

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

static int passed = 0;
static int failed = 0;

#define RUN_TEST(fn)           \
  do                           \
    {                          \
      printf ("  %-50s", #fn); \
      fflush (stdout);         \
      fn ();                   \
      ++passed;                \
      printf ("✓\n");          \
    }                          \
  while (0)

static void
test_define_major_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text mode");
  assert (manager.has_mode ("text-mode"));

  std::printf ("test_define_major_mode passed\n");
}

static void
test_define_minor_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("visual-line-mode", "Visual line mode");
  assert (manager.has_mode ("visual-line-mode"));

  std::printf ("test_define_minor_mode passed\n");
}

static void
test_activate_major_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text mode");
  manager.activate_major_mode ("text-mode", nullptr);
  assert (manager.current_major_mode () == "text-mode");

  std::printf ("test_activate_major_mode passed\n");
}

static void
test_fundamental_mode_default ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  assert (manager.current_major_mode () == "fundamental-mode");
  assert (manager.has_mode ("fundamental-mode"));

  std::printf ("test_fundamental_mode_default passed\n");
}

static void
test_activate_switches_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text mode");
  manager.define_major_mode ("prog-mode", "Prog mode");
  manager.activate_major_mode ("text-mode", nullptr);
  manager.activate_major_mode ("prog-mode", nullptr);
  assert (manager.current_major_mode () == "prog-mode");

  std::printf ("test_activate_switches_mode passed\n");
}

static void
test_enable_minor_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("auto-fill-mode", "Auto fill");
  manager.enable_minor_mode ("auto-fill-mode", nullptr);
  assert (manager.minor_mode_enabled ("auto-fill-mode"));

  std::printf ("test_enable_minor_mode passed\n");
}

static void
test_disable_minor_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("auto-fill-mode", "Auto fill");
  manager.enable_minor_mode ("auto-fill-mode", nullptr);
  manager.disable_minor_mode ("auto-fill-mode", nullptr);
  assert (!manager.minor_mode_enabled ("auto-fill-mode"));

  std::printf ("test_disable_minor_mode passed\n");
}

static void
test_minor_mode_enabled_check ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("hl-line-mode", "HL line");
  assert (!manager.minor_mode_enabled ("hl-line-mode"));
  manager.enable_minor_mode ("hl-line-mode", nullptr);
  assert (manager.minor_mode_enabled ("hl-line-mode"));

  std::printf ("test_minor_mode_enabled_check passed\n");
}

static void
test_active_minor_modes_list ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("mode-a", "A");
  manager.define_minor_mode ("mode-b", "B");
  manager.enable_minor_mode ("mode-a", nullptr);
  manager.enable_minor_mode ("mode-b", nullptr);

  gc_vector_t<gc_string> modes = manager.active_minor_modes ();
  assert (modes.size () == 2);
  assert (modes[0] == "mode-a");
  assert (modes[1] == "mode-b");

  std::printf ("test_active_minor_modes_list passed\n");
}

static void
test_mode_keymap_binding_lookup ()
{
  ModeManager &manager = ModeManager::instance ();
  KeymapManager &keys = KeymapManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("mode-km", "Mode keymap");
  Keymap &km = manager.mode_keymap ("mode-km");
  KeyStroke ks = make_char_keystroke ('a');
  km.bind (ks, "cmd-a");
  manager.enable_minor_mode ("mode-km", nullptr);

  KeyLookupResult result = keys.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "cmd-a");

  std::printf ("test_mode_keymap_binding_lookup passed\n");
}

static void
test_major_mode_keymap_on_activate ()
{
  ModeManager &manager = ModeManager::instance ();
  KeymapManager &keys = KeymapManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text mode");
  Keymap &km = manager.mode_keymap ("text-mode");
  KeyStroke ks = make_char_keystroke ('b');
  km.bind (ks, "text-cmd");
  manager.activate_major_mode ("text-mode", nullptr);

  KeyLookupResult result = keys.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "text-cmd");

  std::printf ("test_major_mode_keymap_on_activate passed\n");
}

static void
test_minor_mode_keymap_on_enable ()
{
  ModeManager &manager = ModeManager::instance ();
  KeymapManager &keys = KeymapManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("minor-x", "Minor x");
  Keymap &km = manager.mode_keymap ("minor-x");
  KeyStroke ks = make_char_keystroke ('c');
  km.bind (ks, "minor-cmd");
  manager.enable_minor_mode ("minor-x", nullptr);

  KeyLookupResult result = keys.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "minor-cmd");

  std::printf ("test_minor_mode_keymap_on_enable passed\n");
}

static void
test_disable_hooks_run ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text");
  manager.define_major_mode ("prog-mode", "Prog");

  int disabled = 0;
  manager.add_mode_hook (
    "text-mode", [&disabled] () { ++disabled; }, false);
  manager.activate_major_mode ("text-mode", nullptr);
  manager.activate_major_mode ("prog-mode", nullptr);
  assert (disabled == 1);

  std::printf ("test_disable_hooks_run passed\n");
}

static void
test_enable_hooks_run ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text");

  int enabled = 0;
  manager
    .add_mode_hook ("text-mode", [&enabled] () { ++enabled; }, true);
  manager.activate_major_mode ("text-mode", nullptr);
  assert (enabled == 1);

  std::printf ("test_enable_hooks_run passed\n");
}

static void
test_major_mode_inheritance ()
{
  ModeManager &manager = ModeManager::instance ();
  KeymapManager &keys = KeymapManager::instance ();
  manager.reset ();
  manager.define_major_mode ("fundamental-mode", "Fundamental");
  manager.define_major_mode ("text-mode", "Text", "fundamental-mode");

  Keymap &parent = manager.mode_keymap ("fundamental-mode");
  Keymap &child = manager.mode_keymap ("text-mode");
  KeyStroke ks = make_char_keystroke ('d');
  parent.bind (ks, "parent-cmd");
  manager.activate_major_mode ("text-mode", nullptr);

  KeyLookupResult result = keys.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "parent-cmd");

  std::printf ("test_major_mode_inheritance passed\n");
}

static void
test_has_mode_check ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("mode-check", "Check");
  assert (manager.has_mode ("mode-check"));
  assert (!manager.has_mode ("missing-mode"));

  std::printf ("test_has_mode_check passed\n");
}

static void
test_reactivate_same_major_mode ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text");

  int enabled = 0;
  manager
    .add_mode_hook ("text-mode", [&enabled] () { ++enabled; }, true);
  manager.activate_major_mode ("text-mode", nullptr);
  manager.activate_major_mode ("text-mode", nullptr);
  assert (enabled == 1);

  std::printf ("test_reactivate_same_major_mode passed\n");
}

static void
test_extern_c_bridge_functions ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text");
  manager.define_minor_mode ("minor-bridge", "Minor");

  assert (emacs_cxx_activate_major_mode ("text-mode") == 0);
  assert (std::string_view (emacs_cxx_current_major_mode ())
	  == "text-mode");
  assert (emacs_cxx_enable_minor_mode ("minor-bridge") == 0);
  assert (manager.minor_mode_enabled ("minor-bridge"));
  assert (emacs_cxx_disable_minor_mode ("minor-bridge") == 0);
  assert (!manager.minor_mode_enabled ("minor-bridge"));

  std::printf ("test_extern_c_bridge_functions passed\n");
}

static void
test_reset_clears_state ()
{
  ModeManager &manager = ModeManager::instance ();
  manager.reset ();
  manager.define_major_mode ("text-mode", "Text");
  manager.define_minor_mode ("minor-one", "Minor");
  manager.activate_major_mode ("text-mode", nullptr);
  manager.enable_minor_mode ("minor-one", nullptr);

  manager.reset ();
  assert (manager.current_major_mode () == "fundamental-mode");
  assert (!manager.minor_mode_enabled ("minor-one"));

  std::printf ("test_reset_clears_state passed\n");
}

static void
test_multiple_minor_modes_stack ()
{
  ModeManager &manager = ModeManager::instance ();
  KeymapManager &keys = KeymapManager::instance ();
  manager.reset ();
  manager.define_minor_mode ("minor-a", "A");
  manager.define_minor_mode ("minor-b", "B");
  KeyStroke ks = make_char_keystroke ('z');

  manager.mode_keymap ("minor-a").bind (ks, "cmd-a");
  manager.mode_keymap ("minor-b").bind (ks, "cmd-b");
  manager.enable_minor_mode ("minor-a", nullptr);
  manager.enable_minor_mode ("minor-b", nullptr);

  KeyLookupResult result = keys.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "cmd-b");

  std::printf ("test_multiple_minor_modes_stack passed\n");
}

int
main ()
{
  std::printf ("Running mode tests...\n\n");

  RUN_TEST (test_define_major_mode);
  RUN_TEST (test_define_minor_mode);
  RUN_TEST (test_activate_major_mode);
  RUN_TEST (test_fundamental_mode_default);
  RUN_TEST (test_activate_switches_mode);
  RUN_TEST (test_enable_minor_mode);
  RUN_TEST (test_disable_minor_mode);
  RUN_TEST (test_minor_mode_enabled_check);
  RUN_TEST (test_active_minor_modes_list);
  RUN_TEST (test_mode_keymap_binding_lookup);
  RUN_TEST (test_major_mode_keymap_on_activate);
  RUN_TEST (test_minor_mode_keymap_on_enable);
  RUN_TEST (test_disable_hooks_run);
  RUN_TEST (test_enable_hooks_run);
  RUN_TEST (test_major_mode_inheritance);
  RUN_TEST (test_has_mode_check);
  RUN_TEST (test_reactivate_same_major_mode);
  RUN_TEST (test_extern_c_bridge_functions);
  RUN_TEST (test_reset_clears_state);
  RUN_TEST (test_multiple_minor_modes_stack);

  std::printf ("\n✅ Passed: %d, Failed: %d\n", passed, failed);
  return failed == 0 ? 0 : 1;
}
