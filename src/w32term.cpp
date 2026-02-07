// src/w32term.cpp
#include <cstring>
#include <format>

#ifdef EMACS_USE_W32
# include <windows.h>
#endif

#include "w32term.hpp"

namespace emacs
{

#ifdef EMACS_USE_W32

WindowsConsoleBackend::WindowsConsoleBackend ()
    : hConsole_ (INVALID_HANDLE_VALUE), hInput_ (INVALID_HANDLE_VALUE),
      original_mode_ (0), initialized_ (false),
      cursor_ ({ 0, 0 }), raw_mode_ (false)
{
}

WindowsConsoleBackend::~WindowsConsoleBackend ()
{
  cleanup ();
}

bool
WindowsConsoleBackend::enable_vt100 () noexcept
{
  hConsole_ = GetStdHandle (STD_OUTPUT_HANDLE);
  hInput_ = GetStdHandle (STD_INPUT_HANDLE);

  if (hConsole_ == INVALID_HANDLE_VALUE
      || hInput_ == INVALID_HANDLE_VALUE)
    {
      return false;
    }

  DWORD mode = 0;
  if (!GetConsoleMode (hConsole_, &mode))
    {
      return false;
    }

  original_mode_ = mode;
  mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;

  if (!SetConsoleMode (hConsole_, mode))
    {
      return false;
    }

  return true;
}

void
WindowsConsoleBackend::append_output (std::string_view data) noexcept
{
  output_buffer_.append (data);
}

void
WindowsConsoleBackend::flush_output () noexcept
{
  if (!output_buffer_.empty ())
    {
      DWORD written = 0;
      WriteConsoleA (hConsole_, output_buffer_.data (),
		  static_cast<DWORD> (output_buffer_.size ()),
		  &written, nullptr);
      output_buffer_.clear ();
    }
}

bool
WindowsConsoleBackend::init () noexcept
{
  if (!enable_vt100 ())
    {
      return false;
    }

  initialized_ = true;
  return true;
}

void
WindowsConsoleBackend::cleanup () noexcept
{
  if (initialized_ && hConsole_ != INVALID_HANDLE_VALUE)
    {
      SetConsoleMode (hConsole_, original_mode_);
      hConsole_ = INVALID_HANDLE_VALUE;
      hInput_ = INVALID_HANDLE_VALUE;
      initialized_ = false;
    }
}

void
WindowsConsoleBackend::write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
{
  if (!initialized_)
    {
      return;
    }

  for (const auto &glyph : glyphs)
    {
      // Build ANSI SGR sequence
      std::string seq = "\033[";

      if (glyph.bold)
	seq += ";1";
      if (glyph.italic)
	seq += ";3";
      if (glyph.underline)
	seq += ";4";
      if (glyph.inverse)
	seq += ";7";
      if (glyph.blink)
	seq += ";5";

      // Truecolor foreground
      seq += std::format (";38;2;{};{};{}", glyph.foreground.red,
		       glyph.foreground.green,
		       glyph.foreground.blue);

      // Truecolor background
      seq += std::format (";48;2;{};{};{}", glyph.background.red,
		       glyph.background.green,
		       glyph.background.blue);

      seq += "m";

      append_output (seq);
      append_output (std::string (1, static_cast<char> (glyph.codepoint)));
    }

  flush_output ();
}

void
WindowsConsoleBackend::write_text (std::string_view text) noexcept
{
  if (!initialized_)
    {
      return;
    }

  append_output (text);
  flush_output ();
}

void
WindowsConsoleBackend::clear_to_end (CursorPosition pos) noexcept
{
  append_output ("\033[0J");
  flush_output ();
}

void
WindowsConsoleBackend::clear_frame () noexcept
{
  append_output ("\033[2J");
  flush_output ();
}

void
WindowsConsoleBackend::clear_end_of_line (CursorPosition pos) noexcept
{
  append_output ("\033[K");
  flush_output ();
}

void
WindowsConsoleBackend::set_cursor_position (CursorPosition pos) noexcept
{
  append_output (std::format ("\033[{};{}H", pos.row + 1, pos.col + 1));
  flush_output ();
  cursor_ = pos;
}

CursorPosition
WindowsConsoleBackend::get_cursor_position () const noexcept
{
  CONSOLE_SCREEN_BUFFER_INFO csbi = {};
  if (GetConsoleScreenBufferInfo (hConsole_, &csbi))
    {
      return { csbi.dwCursorPosition.Y, csbi.dwCursorPosition.X };
    }
  return cursor_;
}

void
WindowsConsoleBackend::insert_glyphs (CursorPosition pos,
				    std::span<TerminalGlyph> glyphs) noexcept
{
  set_cursor_position (pos);
  write_glyphs (glyphs);
}

void
WindowsConsoleBackend::delete_glyphs (CursorPosition pos,
				     std::size_t n) noexcept
{
  set_cursor_position (pos);
  std::string spaces (n, ' ');
  append_output (spaces);
  flush_output ();
}

void
WindowsConsoleBackend::insert_lines (CursorPosition pos, std::size_t n) noexcept
{
  append_output (std::format ("\033[{}L", n));
  flush_output ();
}

void
WindowsConsoleBackend::delete_lines (CursorPosition pos, std::size_t n) noexcept
{
  append_output (std::format ("\033[{}M", n));
  flush_output ();
}

bool
WindowsConsoleBackend::supports_colors () const noexcept
{
  return true;
}

bool
WindowsConsoleBackend::supports_truecolor () const noexcept
{
  return true;
}

bool
WindowsConsoleBackend::supports_blinking_cursor () const noexcept
{
  return true;
}

bool
WindowsConsoleBackend::supports_bracketed_paste () const noexcept
{
  return true;
}

std::pair<int, int>
WindowsConsoleBackend::get_terminal_size () const noexcept
{
  CONSOLE_SCREEN_BUFFER_INFO csbi = {};
  if (GetConsoleScreenBufferInfo (hConsole_, &csbi))
    {
      return { csbi.dwSize.Y, csbi.dwSize.X };
    }
  return { 0, 0 };
}

InputEvent
WindowsConsoleBackend::read_input () noexcept
{
  InputEvent event = {};
  event.type = InputEventType::None;

  if (hInput_ == INVALID_HANDLE_VALUE)
    {
      return event;
    }

  INPUT_RECORD record;
  DWORD events_read = 0;

  if (!PeekConsoleInput (hInput_, &record, 1, &events_read)
      || events_read == 0)
    {
      return event;
    }

  if (!ReadConsoleInput (hInput_, &record, 1, &events_read)
      || events_read == 0)
    {
      return event;
    }

  if (record.EventType == KEY_EVENT)
    {
      KEY_EVENT_RECORD &key = record.Event.KeyEvent;
      if (key.bKeyDown)
	{
	  WORD modifiers = key.dwControlKeyState;

	  if (modifiers
	      & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED))
	    {
	      event.type = InputEventType::Key;
	      event.key = key.wVirtualKeyCode;

	      if (key.wVirtualKeyCode == 'C')
		event.key = 3; // Ctrl+C
	      else if (key.wVirtualKeyCode == 'L')
		event.key = 12; // Ctrl+L
	      else if (key.wVirtualKeyCode == 'D')
		event.key = 4; // Ctrl+D
	      else if (key.wVirtualKeyCode == 'H')
		event.key = 2; // Ctrl+H
	      else if (key.wVirtualKeyCode == 'K')
		event.key = 11; // Ctrl+K
	    }
	  else if (key.uChar.AsciiChar)
	    {
	      event.type = InputEventType::Key;
	      event.ch = key.uChar.AsciiChar;
	    }
	}
    }
  else if (record.EventType == MOUSE_EVENT)
    {
      MOUSE_EVENT_RECORD &mouse = record.Event.MouseEvent;
      event.type = InputEventType::Mouse;
      event.x = mouse.dwMousePosition.X;
      event.y = mouse.dwMousePosition.Y;
      event.button = MouseButton::None;

      if (mouse.dwButtonState & FROM_LEFT_1ST_BUTTON_PRESSED)
	event.button = MouseButton::Left;
      else if (mouse.dwButtonState & RIGHTMOST_BUTTON_PRESSED)
	event.button = MouseButton::Right;
      else if (mouse.dwButtonState & FROM_LEFT_2ND_BUTTON_PRESSED)
	event.button = MouseButton::Middle;
    }

  return event;
}

void
WindowsConsoleBackend::set_raw_mode (bool raw) noexcept
{
  if (hInput_ == INVALID_HANDLE_VALUE)
    {
      return;
    }

  DWORD mode = 0;
  GetConsoleMode (hInput_, &mode);

  if (raw)
    {
      mode |= ENABLE_WINDOW_INPUT;
      mode &= ~ENABLE_LINE_INPUT;
      mode &= ~ENABLE_ECHO_INPUT;
    }
  else
    {
      mode &= ~ENABLE_WINDOW_INPUT;
      mode |= ENABLE_LINE_INPUT;
      mode |= ENABLE_ECHO_INPUT;
    }

  SetConsoleMode (hInput_, mode);
  raw_mode_ = raw;
}

void
WindowsConsoleBackend::flush () noexcept
{
  flush_output ();
}

void
WindowsConsoleBackend::enable_bracketed_paste (bool enable) noexcept
{
  const char *seq = enable ? "\033[?2004h" : "\033[?2004l";
  append_output (seq);
  flush_output ();
}

void
WindowsConsoleBackend::set_color (uint8_t fg, uint8_t bg) noexcept
{
  append_output (std::format ("\033[3{};4{}m", fg, bg));
  flush_output ();
}

void
WindowsConsoleBackend::set_truecolor (uint8_t r, uint8_t g,
				uint8_t b) noexcept
{
  // Already using truecolor in write_glyphs
}

void
WindowsConsoleBackend::set_attribute (bool bold, bool italic, bool underline,
				       bool inverse) noexcept
{
  std::string seq = "\033[";

  if (bold)
    seq += "1;";
  if (italic)
    seq += "3;";
  if (underline)
    seq += "4;";
  if (inverse)
    seq += "7;";

  seq += "m";
  append_output (seq);
  flush_output ();
}

#else

// Stub implementation when EMACS_USE_W32 is not defined

bool
WindowsConsoleBackend::init () noexcept
{
  return false;
}

void
WindowsConsoleBackend::cleanup () noexcept
{
}

void
WindowsConsoleBackend::write_glyphs (std::span<TerminalGlyph>) noexcept
{
}

void
WindowsConsoleBackend::write_text (std::string_view) noexcept
{
}

void
WindowsConsoleBackend::clear_to_end (CursorPosition) noexcept
{
}

void
WindowsConsoleBackend::clear_frame () noexcept
{
}

void
WindowsConsoleBackend::clear_end_of_line (CursorPosition) noexcept
{
}

void
WindowsConsoleBackend::set_cursor_position (CursorPosition) noexcept
{
}

CursorPosition
WindowsConsoleBackend::get_cursor_position () const noexcept
{
  return { 0, 0 };
}

void
WindowsConsoleBackend::insert_glyphs (CursorPosition,
				    std::span<TerminalGlyph>) noexcept
{
}

void
WindowsConsoleBackend::delete_glyphs (CursorPosition, std::size_t) noexcept
{
}

void
WindowsConsoleBackend::insert_lines (CursorPosition, std::size_t) noexcept
{
}

void
WindowsConsoleBackend::delete_lines (CursorPosition, std::size_t) noexcept
{
}

bool
WindowsConsoleBackend::supports_colors () const noexcept
{
  return false;
}

bool
WindowsConsoleBackend::supports_truecolor () const noexcept
{
  return false;
}

bool
WindowsConsoleBackend::supports_blinking_cursor () const noexcept
{
  return false;
}

bool
WindowsConsoleBackend::supports_bracketed_paste () const noexcept
{
  return false;
}

std::pair<int, int>
WindowsConsoleBackend::get_terminal_size () const noexcept
{
  return { 0, 0 };
}

InputEvent
WindowsConsoleBackend::read_input () noexcept
{
  InputEvent event = {};
  event.type = InputEventType::None;
  return event;
}

void
WindowsConsoleBackend::set_raw_mode (bool) noexcept
{
}

void
WindowsConsoleBackend::flush () noexcept
{
}

void
WindowsConsoleBackend::enable_bracketed_paste (bool) noexcept
{
}

void
WindowsConsoleBackend::set_color (uint8_t, uint8_t) noexcept
{
}

void
WindowsConsoleBackend::set_truecolor (uint8_t, uint8_t,
				 uint8_t) noexcept
{
}

void
WindowsConsoleBackend::set_attribute (bool, bool, bool,
				       bool) noexcept
{
}

#endif

} // namespace emacs
