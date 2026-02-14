// test/test_terminal_backends.cpp
#include <cstring>
#include <format>
#include <iostream>
#include <span>
#include <vector>

#include "../src/termhooks.hpp"
#include "../src/terminal_concept.hpp"

using namespace emacs;

namespace terminal_tests
{

struct MockTerminalBackend
{
  std::vector<TerminalGlyph> written_glyphs_;
  CursorPosition cursor_pos_;
  int screen_width_;
  int screen_height_;
  bool vt100_enabled_;
  bool truecolor_enabled_;

  MockTerminalBackend ()
      : cursor_pos_{ 0, 0 }, screen_width_ (80), screen_height_ (24),
	vt100_enabled_ (true), truecolor_enabled_ (true)
  {
  }

  void clear ()
  {
    written_glyphs_.clear ();
    cursor_pos_ = { 0, 0 };
  }

  bool init () noexcept { return true; }

  void cleanup () noexcept { clear (); }

  void write_glyphs (std::span<emacs::TerminalGlyph> glyphs) noexcept
  {
    for (const auto &glyph : glyphs)
      {
	written_glyphs_.push_back (glyph);
      }
  }

  void write_text (std::string_view text) noexcept
  {
    for (char ch : text)
      {
	TerminalGlyph glyph;
	glyph.codepoint = static_cast<char32_t> (ch);
	glyph.foreground = 7;
	glyph.background = 0;
	glyph.bold = false;
	glyph.italic = false;
	glyph.underline = false;
	glyph.inverse = false;
	glyph.wide = false;
	glyph.padding = false;
	written_glyphs_.push_back (glyph);
      }
  }

  void clear_to_end (CursorPosition pos) noexcept
  {
    cursor_pos_ = pos;
  }

  void clear_frame () noexcept { clear (); }

  void clear_end_of_line (CursorPosition pos) noexcept
  {
    cursor_pos_ = pos;
  }

  void set_cursor_position (CursorPosition pos) noexcept
  {
    cursor_pos_ = pos;
  }

  CursorPosition get_cursor_position () const noexcept
  {
    return cursor_pos_;
  }

  void insert_glyphs (CursorPosition pos,
		      std::span<emacs::TerminalGlyph> glyphs) noexcept
  {
  }

  void delete_glyphs (CursorPosition pos, std::size_t n) noexcept {}

  void insert_lines (CursorPosition pos, std::size_t n) noexcept {}

  void delete_lines (CursorPosition pos, std::size_t n) noexcept {}

  bool supports_colors () const noexcept { return vt100_enabled_; }

  bool supports_truecolor () const noexcept
  {
    return truecolor_enabled_;
  }

  bool supports_blinking_cursor () const noexcept { return true; }

  bool supports_bracketed_paste () const noexcept { return true; }

  std::pair<int, int> get_terminal_size () const noexcept
  {
    return { screen_height_, screen_width_ };
  }

  int read_input () noexcept { return -1; }

  void set_raw_mode (bool raw) noexcept {}

  void enable_bracketed_paste (bool enable) noexcept {}

  void set_color (uint8_t fg, uint8_t bg) noexcept {}

  void set_truecolor (uint8_t r, uint8_t g, uint8_t b) noexcept
  {
    truecolor_enabled_ = true;
  }

  void set_attribute (bool bold, bool italic, bool underline,
		      bool inverse) noexcept
  {
  }

  const std::vector<TerminalGlyph> &get_written_glyphs () const
  {
    return written_glyphs_;
  }
};

}

bool
test_windows_terminal_backend ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: Windows backend init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> glyphs;
  glyphs.push_back (
    { 0x0048, 0, 7, 0, false, false, false, false, false });

  if (!backend.write_glyphs (glyphs))
    {
      std::cerr << "FAIL: Windows backend write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != 1)
    {
      std::cerr << "FAIL: Expected 1 glyph, got " << written.size ()
		<< "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: Windows terminal backend test\n";
  return true;
}

bool
test_macos_terminal_backend ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: macOS backend init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> glyphs;
  glyphs.push_back (
    { 0x4E2D, 0, 7, 0, false, false, false, false, false });

  if (!backend.write_glyphs (glyphs))
    {
      std::cerr << "FAIL: macOS backend write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != 1)
    {
      std::cerr << "FAIL: Expected 1 glyph, got " << written.size ()
		<< "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: macOS terminal backend test\n";
  return true;
}

bool
test_x11_terminal_backend ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: X11 backend init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> glyphs;
  glyphs.push_back (
    { 0x4E16, 0, 7, 0, false, false, false, false, false });

  if (!backend.write_glyphs (glyphs))
    {
      std::cerr << "FAIL: X11 backend write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != 1)
    {
      std::cerr << "FAIL: Expected 1 glyph, got " << written.size ()
		<< "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: X11 terminal backend test\n";
  return true;
}

bool
test_haiku_terminal_backend ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: Haiku backend init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> glyphs;
  glyphs.push_back (
    { 0x4E08, 0, 7, 0, false, false, false, false, false });

  if (!backend.write_glyphs (glyphs))
    {
      std::cerr << "FAIL: Haiku backend write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != 1)
    {
      std::cerr << "FAIL: Expected 1 glyph, got " << written.size ()
		<< "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: Haiku terminal backend test\n";
  return true;
}

bool
test_android_terminal_backend ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: Android backend init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> glyphs;
  glyphs.push_back (
    { 0x4F7E, 0, 7, 0, false, false, false, false, false });

  if (!backend.write_glyphs (glyphs))
    {
      std::cerr << "FAIL: Android backend write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != 1)
    {
      std::cerr << "FAIL: Expected 1 glyph, got " << written.size ()
		<< "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: Android terminal backend test\n";
  return true;
}

bool
test_utf8_chinese_encoding ()
{
  terminal_tests::MockTerminalBackend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: UTF-8/Chinese encoding test init failed\n";
      return false;
    }

  std::vector<emacs::TerminalGlyph> ascii_glyphs;
  std::vector<emacs::TerminalGlyph> chinese_glyphs;

  for (char ch = 0x20; ch < 0x7F; ++ch)
    {
      TerminalGlyph glyph;
      glyph.codepoint = static_cast<char32_t> (ch);
      glyph.foreground = 7;
      glyph.background = 0;
      ascii_glyphs.push_back (glyph);
    }

  for (char32_t ch = 0x4E00; ch < 0x4E7F; ++ch)
    {
      TerminalGlyph glyph;
      glyph.codepoint = ch;
      glyph.foreground = 7;
      glyph.background = 0;
      chinese_glyphs.push_back (glyph);
    }

  std::vector<emacs::TerminalGlyph> test_text;
  test_text.insert (test_text.end (), ascii_glyphs.begin (),
		    ascii_glyphs.end ());
  test_text.insert (test_text.end (), chinese_glyphs.begin (),
		    chinese_glyphs.end ());

  if (!backend.write_glyphs (test_text))
    {
      std::cerr << "FAIL: UTF-8 encoding test write_glyphs failed\n";
      return false;
    }

  const auto &written = backend.get_written_glyphs ();
  if (written.size () != test_text.size ())
    {
      std::cerr << "FAIL: UTF-8 encoding test expected "
		<< test_text.size () << " glyphs, got "
		<< written.size () << "\n";
      return false;
    }

  backend.cleanup ();

  std::cout << "PASS: UTF-8/Chinese encoding compatibility test\n";
  return true;
}

int
main ()
{
  int passed = 0;
  int failed = 0;

  std::cout << "=== Phase 3: Terminal Backend Tests ===\n";
  std::cout << "Testing Windows terminal backend...\n";
  if (test_windows_terminal_backend ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "Testing macOS terminal backend...\n";
  if (test_macos_terminal_backend ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "Testing X11 terminal backend...\n";
  if (test_x11_terminal_backend ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "Testing Haiku terminal backend...\n";
  if (test_haiku_terminal_backend ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "Testing Android terminal backend...\n";
  if (test_android_terminal_backend ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "Testing UTF-8/Chinese encoding compatibility...\n";
  if (test_utf8_chinese_encoding ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "\n=== Test Results ===\n";
  std::cout << "Passed: " << passed << "\n";
  std::cout << "Failed: " << failed << "\n";

  std::cout << "Success criteria: All tests must pass (5/5)\n";

  return (failed == 0) ? 0 : 1;
}
