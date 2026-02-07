// test/cxx/test_keymap.cpp
// Unit tests for keymap system

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_keymap.hpp"

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

static KeySequence
make_sequence (const KeyStroke &first, const KeyStroke &second)
{
  KeySequence seq;
  seq.push_back (first);
  seq.push_back (second);
  return seq;
}

static void
test_make_keystroke ()
{
  KeyStroke ks = make_keystroke (KeyCode::Tab, KeyModifier::Alt);
  assert (ks.key == KeyCode::Tab);
  assert (ks.modifiers == KeyModifier::Alt);
  assert (ks.unicode == 0);

  KeyStroke ch = make_char_keystroke ('a');
  assert (ch.key == KeyCode::Unknown);
  assert (ch.modifiers == KeyModifier::None);
  assert (ch.unicode == static_cast<uint32_t> ('a'));

  KeyStroke ctrl = make_ctrl_keystroke ('x');
  assert (ctrl.key == KeyCode::Unknown);
  assert (ctrl.modifiers == KeyModifier::Ctrl);
  assert (ctrl.unicode == static_cast<uint32_t> ('x'));

  std::printf ("test_make_keystroke passed\n");
}

static void
test_keystroke_equality ()
{
  KeyStroke a = make_keystroke (KeyCode::Enter, KeyModifier::Shift);
  KeyStroke b = make_keystroke (KeyCode::Enter, KeyModifier::Shift);
  KeyStroke c = make_keystroke (KeyCode::Enter, KeyModifier::Alt);

  assert (a == b);
  assert (!(a == c));

  std::printf ("test_keystroke_equality passed\n");
}

static void
test_keymap_create ()
{
  Keymap km ("test");
  assert (km.name () == "test");

  std::printf ("test_keymap_create passed\n");
}

static void
test_keymap_bind_lookup ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ks = make_char_keystroke ('a');

  km.bind (ks, "self-insert");
  KeyLookupResult result = km.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "self-insert");

  std::printf ("test_keymap_bind_lookup passed\n");
}

static void
test_keymap_unbound ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ks = make_char_keystroke ('a');

  KeyLookupResult result = km.lookup (ks);
  assert (result.type == KeyLookupType::Unbound);

  std::printf ("test_keymap_unbound passed\n");
}

static void
test_keymap_unbind ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ks = make_char_keystroke ('b');

  km.bind (ks, "self-insert");
  km.unbind (ks);
  KeyLookupResult result = km.lookup (ks);
  assert (result.type == KeyLookupType::Unbound);

  std::printf ("test_keymap_unbind passed\n");
}

static void
test_keymap_bind_overwrite ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ks = make_char_keystroke ('c');

  km.bind (ks, "first");
  km.bind (ks, "second");
  KeyLookupResult result = km.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "second");

  std::printf ("test_keymap_bind_overwrite passed\n");
}

static void
test_keymap_prefix_key ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ctrl_x = make_ctrl_keystroke ('x');
  KeyStroke ctrl_f = make_ctrl_keystroke ('f');
  KeySequence seq = make_sequence (ctrl_x, ctrl_f);

  km.bind_sequence (seq, "find-file");
  KeyLookupResult result = km.lookup (ctrl_x);
  assert (result.type == KeyLookupType::PrefixKey);

  std::printf ("test_keymap_prefix_key passed\n");
}

static void
test_keymap_sequence_lookup ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ctrl_x = make_ctrl_keystroke ('x');
  KeyStroke ctrl_f = make_ctrl_keystroke ('f');
  KeySequence seq = make_sequence (ctrl_x, ctrl_f);

  km.bind_sequence (seq, "find-file");
  KeyLookupResult result = km.lookup_sequence (seq);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "find-file");

  std::printf ("test_keymap_sequence_lookup passed\n");
}

static void
test_keymap_parent_inheritance ()
{
  KeymapManager::instance ().clear ();
  Keymap parent ("parent");
  Keymap child ("child");
  KeyStroke ks = make_char_keystroke ('d');

  parent.bind (ks, "parent-cmd");
  child.set_parent (&parent);

  KeyLookupResult result = child.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "parent-cmd");

  std::printf ("test_keymap_parent_inheritance passed\n");
}

static void
test_keymap_parent_override ()
{
  KeymapManager::instance ().clear ();
  Keymap parent ("parent");
  Keymap child ("child");
  KeyStroke ks = make_char_keystroke ('e');

  parent.bind (ks, "parent-cmd");
  child.bind (ks, "child-cmd");
  child.set_parent (&parent);

  KeyLookupResult result = child.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "child-cmd");

  std::printf ("test_keymap_parent_override passed\n");
}

static void
test_keymap_is_prefix ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ctrl_x = make_ctrl_keystroke ('x');
  KeyStroke ctrl_f = make_ctrl_keystroke ('f');
  KeySequence seq = make_sequence (ctrl_x, ctrl_f);

  km.bind_sequence (seq, "find-file");
  assert (km.is_prefix (ctrl_x));
  assert (!km.is_prefix (ctrl_f));

  std::printf ("test_keymap_is_prefix passed\n");
}

static void
test_keymap_get_prefix_keymap ()
{
  KeymapManager::instance ().clear ();
  Keymap km ("local");
  KeyStroke ctrl_x = make_ctrl_keystroke ('x');
  KeyStroke ctrl_f = make_ctrl_keystroke ('f');
  KeySequence seq = make_sequence (ctrl_x, ctrl_f);

  km.bind_sequence (seq, "find-file");
  const Keymap *prefix = km.get_prefix_keymap (ctrl_x);
  assert (prefix);
  assert (prefix->name () == "prefix");

  KeySequence rest;
  rest.push_back (ctrl_f);
  KeyLookupResult result = prefix->lookup_sequence (rest);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "find-file");

  std::printf ("test_keymap_get_prefix_keymap passed\n");
}

static void
test_manager_global_keymap ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  assert (manager.global_keymap ().name () == "global");

  std::printf ("test_manager_global_keymap passed\n");
}

static void
test_manager_lookup_global ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  KeyStroke ks = make_char_keystroke ('f');

  manager.global_keymap ().bind (ks, "forward-char");
  KeyLookupResult result = manager.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "forward-char");

  std::printf ("test_manager_lookup_global passed\n");
}

static void
test_manager_major_mode_override ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  Keymap major ("major");
  KeyStroke ks = make_char_keystroke ('g');

  manager.global_keymap ().bind (ks, "global-cmd");
  major.bind (ks, "major-cmd");
  manager.set_major_mode_keymap (&major);

  KeyLookupResult result = manager.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "major-cmd");

  std::printf ("test_manager_major_mode_override passed\n");
}

static void
test_manager_minor_mode_priority ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  Keymap minor1 ("minor1");
  Keymap minor2 ("minor2");
  KeyStroke ks = make_char_keystroke ('h');

  minor1.bind (ks, "minor-one");
  minor2.bind (ks, "minor-two");
  manager.push_minor_mode_keymap (&minor1);
  manager.push_minor_mode_keymap (&minor2);

  KeyLookupResult result = manager.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "minor-two");

  std::printf ("test_manager_minor_mode_priority passed\n");
}

static void
test_manager_local_highest_priority ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  Keymap major ("major");
  Keymap minor ("minor");
  Keymap local ("local");
  KeyStroke ks = make_char_keystroke ('i');

  manager.global_keymap ().bind (ks, "global-cmd");
  major.bind (ks, "major-cmd");
  minor.bind (ks, "minor-cmd");
  local.bind (ks, "local-cmd");
  manager.set_major_mode_keymap (&major);
  manager.push_minor_mode_keymap (&minor);
  manager.set_local_keymap (&local);

  KeyLookupResult result = manager.lookup (ks);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "local-cmd");

  std::printf ("test_manager_local_highest_priority passed\n");
}

static void
test_manager_sequence_lookup ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  KeyStroke ctrl_x = make_ctrl_keystroke ('x');
  KeyStroke ctrl_f = make_ctrl_keystroke ('f');
  KeySequence seq = make_sequence (ctrl_x, ctrl_f);

  manager.global_keymap ().bind_sequence (seq, "find-file");
  KeyLookupResult result = manager.lookup_sequence (seq);
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "find-file");

  std::printf ("test_manager_sequence_lookup passed\n");
}

static void
test_manager_clear ()
{
  KeymapManager &manager = KeymapManager::instance ();
  manager.clear ();
  Keymap major ("major");
  Keymap minor ("minor");
  Keymap local ("local");
  KeyStroke ks = make_char_keystroke ('j');

  manager.global_keymap ().bind (ks, "global-cmd");
  major.bind (ks, "major-cmd");
  minor.bind (ks, "minor-cmd");
  local.bind (ks, "local-cmd");
  manager.set_major_mode_keymap (&major);
  manager.push_minor_mode_keymap (&minor);
  manager.set_local_keymap (&local);

  manager.clear ();
  KeyLookupResult result = manager.lookup (ks);
  assert (result.type == KeyLookupType::Unbound);
  assert (manager.global_keymap ().name () == "global");

  std::printf ("test_manager_clear passed\n");
}

int
main ()
{
  std::printf ("Running keymap tests...\n\n");

  test_make_keystroke ();
  test_keystroke_equality ();
  test_keymap_create ();
  test_keymap_bind_lookup ();
  test_keymap_unbound ();
  test_keymap_unbind ();
  test_keymap_bind_overwrite ();
  test_keymap_prefix_key ();
  test_keymap_sequence_lookup ();
  test_keymap_parent_inheritance ();
  test_keymap_parent_override ();
  test_keymap_is_prefix ();
  test_keymap_get_prefix_keymap ();
  test_manager_global_keymap ();
  test_manager_lookup_global ();
  test_manager_major_mode_override ();
  test_manager_minor_mode_priority ();
  test_manager_local_highest_priority ();
  test_manager_sequence_lookup ();
  test_manager_clear ();

  std::printf ("\n✅ All keymap tests passed!\n");
  return 0;
}
