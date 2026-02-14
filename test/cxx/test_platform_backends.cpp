// test/cxx/test_platform_backends.cpp
#include <cassert>
#include <iostream>
#include <string>

#include "../src/androidterm.hpp"
#include "../src/haikuterm.hpp"
#include "../src/nsterm.hpp"
#include "../src/terminal_concept.hpp"
#include "../src/w32term.hpp"
#include "../src/xterm.hpp"

namespace
{

// === Test 1: PosixTtyBackend concept compliance ===
void
test_posix_concept ()
{
  emacs::PosixTtyBackend backend;

  // These should compile and satisfy concept
  static_assert (emacs::TerminalBackend<emacs::PosixTtyBackend>);

  // Stub implementations should work correctly
  backend.init ();
  backend.cleanup ();

  // Default cursor position
  auto pos = backend.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  // Terminal size stub returns {0,0}
  auto size = backend.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  // Capability queries
  assert (!backend.supports_colors ());
  assert (!backend.supports_truecolor ());
  assert (!backend.supports_blinking_cursor ());
  assert (!backend.supports_bracketed_paste ());

  // read_input returns None
  auto event = backend.read_input ();
  assert (event.type == emacs::InputEventType::None);

  std::cout << "✓ test_posix_concept passed\n";
}

// === Test 2: WindowsConsoleBackend concept compliance ===
void
test_windows_concept ()
{
  emacs::WindowsConsoleBackend backend;

  static_assert (
    emacs::TerminalBackend<emacs::WindowsConsoleBackend>);

  backend.init ();
  backend.cleanup ();

  auto pos = backend.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  auto size = backend.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  assert (!backend.supports_colors ());
  assert (!backend.supports_truecolor ());
  assert (!backend.supports_blinking_cursor ());
  assert (!backend.supports_bracketed_paste ());

  auto event = backend.read_input ();
  assert (event.type == emacs::InputEventType::None);

  std::cout << "✓ test_windows_concept passed\n";
}

// === Test 3: MacOSNativeBackend concept compliance ===
void
test_macos_concept ()
{
  emacs::MacOSNativeBackend backend;

  static_assert (emacs::TerminalBackend<emacs::MacOSNativeBackend>);

  backend.init ();
  backend.cleanup ();

  auto pos = backend.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  auto size = backend.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  assert (!backend.supports_colors ());
  assert (!backend.supports_truecolor ());
  assert (!backend.supports_blinking_cursor ());
  assert (!backend.supports_bracketed_paste ());

  auto event = backend.read_input ();
  assert (event.type == emacs::InputEventType::None);

  std::cout << "✓ test_macos_concept passed\n";
}

// === Test 4: HaikuBackend concept compliance ===
void
test_haiku_concept ()
{
  emacs::HaikuBackend backend;

  static_assert (emacs::TerminalBackend<emacs::HaikuBackend>);

  backend.init ();
  backend.cleanup ();

  auto pos = backend.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  auto size = backend.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  assert (!backend.supports_colors ());
  assert (!backend.supports_truecolor ());
  assert (!backend.supports_blinking_cursor ());
  assert (!backend.supports_bracketed_paste ());

  auto event = backend.read_input ();
  assert (event.type == emacs::InputEventType::None);

  std::cout << "✓ test_haiku_concept passed\n";
}

// === Test 5: AndroidBackend concept compliance ===
void
test_android_concept ()
{
  emacs::AndroidBackend backend;

  static_assert (emacs::TerminalBackend<emacs::AndroidBackend>);

  backend ();
  backend.cleanup ();

  auto pos = backend.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  auto size = backend.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  assert (!backend.supports_colors ());
  assert (!backend.supports_truecolor ());
  assert (!backend.supports_blinking_cursor ());
  assert (!backend.supports_bracketed_paste ());

  auto event = backend.read_input ();
  assert (event.type == emacs::InputEventType::None);

  std::cout << "✓ test_android_concept passed\n";
}

// === Test 6: All backends compile together ===
void
test_all_backends_compile ()
{
  // Verify all backends can be instantiated together
  emacs::PosixTtyBackend posix;
  emacs::WindowsConsoleBackend windows;
  emacs::MacOSNativeBackend macos;
  emacs::HaikuBackend haiku;
  emacs::AndroidBackend android;

  // Just existence is enough
  (void) posix;
  (void) windows;
  (void) macos;
  (void) haiku;
  (void) android;

  std::cout << "✓ test_all_backends_compile passed\n";
}

int
main (int argc, char *argv[])
{
  std::cout << "=== Platform Backend Tests ===\n\n";

  test_posix_concept ();
  test_windows_concept ();
  test_macos_concept ();
  test_haiku_concept ();
  test_android_concept ();
  test_all_backends_compile ();

  std::cout << "\n=== All 6 tests passed ===\n";
  return 0;
}
