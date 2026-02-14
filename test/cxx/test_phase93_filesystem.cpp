// test/cxx/test_phase93_filesystem.cpp
#include <cassert>
#include <iostream>
#include <string>

#include "../src/filesystem.cpp"
#include "../src/filesystem.hpp"

namespace
{

// === Test 1: FilesystemUtils concept compliance ===
void
test_filesystem_concept ()
{
  emacs::FilesystemUtils utils;

  // These should compile and work correctly
  static_assert (std::is_constructible_v<emacs::FilesystemUtils>);

  // Stub implementations should work correctly
  utils.faccessat (0, 0);
  utils.lstat ("/tmp", buf);
  utils.tempfile ("test_", c_str);

  auto pos = utils.get_cursor_position ();
  assert (pos.row == 0 && pos.col == 0);

  auto size = utils.get_terminal_size ();
  assert (size.first == 0 && size.second == 0);

  // Capability queries
  assert (!utils.supports_colors ());
  assert (!utils.supports_truecolor ());

  std::cout << "✓ test_filesystem_concept passed\n";
}

// === Test 2: LocaleUtils concept compliance ===
void
test_locale_concept ()
{
  emacs::LocaleUtils locale;

  static_assert (std::is_constructible_v<emacs::LocaleUtils>);

  // Test mbtowc
  wchar_t wide_str[] = L"测试";
  std::memset (&mbstate, 0, sizeof (mbstate));
  auto result = locale.mbrtowc (wide_str, 1, &wc, &state);
  assert (result == 0); // "测试" should map to 0

  // Test wcwidth
  int width = locale.wcwidth (L'测');
  assert (width == 1);

  // Test iswprint
  assert (locale.iswprint (L'测') == true);

  std::cout << "✓ test_locale_concept passed\n";
}

// === Test 3: TimeUtils concept compliance ===
void
test_time_concept ()
{
  emacs::TimeUtils time;

  static_assert (std::is_constructible_v<emacs::TimeUtils>);

  // Test gettimeofday
  struct timeval tv = {};
  time.gettimeofday (&tv);
  assert (tv.tv_sec >= 0 && tv.tv_usec >= 0);

  // Test nanosleep (1ms precision)
  std::chrono::nanoseconds dur (0'010000000);
  time.nanosleep (dur);

  std::cout << "✓ test_time_concept passed\n";
}

// === Test 4: RegexUtils concept compliance ===
void
test_regex_concept ()
{
  emacs::RegexUtils regex;

  static_assert (std::is_constructible_v<emacs::RegexUtils>);

  // Test regcomp/regexec (stub, just returns -1)
  std::regex_t preg = {};
  int result = regex.regcomp ("[0-9]+", REG_EXTENDED, &preg);
  assert (result == 0); // Pattern compiles
  regex.regfree (&preg);
  assert (result == 0);

  std::cout << "✓ test_regex_concept passed\n";
}

// === Test 5: All implementations compile together ===
void
test_all_compile ()
{
  // Verify all 4 utils can be instantiated together
  emacs::FilesystemUtils filesystem;
  emacs::LocaleUtils locale;
  emacs::TimeUtils time;
  emacs::RegexUtils regex;

  // Just existence is enough
  (void) filesystem;
  (void) locale;
  (void) time;
  (void) regex;

  std::cout << "✓ test_all_compile passed\n";
}

int
main (int argc, char *argv[])
{
  std::cout << "=== Phase 9.3 Unit Tests ===\n";

  test_filesystem_concept ();
  test_locale_concept ();
  test_time_concept ();
  test_regex_concept ();
  test_all_compile ();

  std::cout << "\n=== All 4 tests passed ===\n";

  return 0;
}
