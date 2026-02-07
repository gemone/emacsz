// src/nsterm.cpp
#include <cstring>
#include <format>
#include <vector>

#ifdef EMACS_USE_NSTERM
# include <termios.h>
# include <sys/ioctl.h>
# include <unistd.h>
#endif

#include "nsterm.hpp"

namespace emacs
{

#ifdef EMACS_USE_NSTERM

MacOSNativeBackend::MacOSNativeBackend ()
    : initialized_ (false), cursor_ ({ 0, 0 }), raw_mode_ (false),
      output_buffer_ (), input_queue_ (), is_iterm_ (false),
      is_apple_terminal_ (false)
{
}

MacOSNativeBackend::~MacOSNativeBackend ()
{
  cleanup ();
}

bool
MacOSNativeBackend::enable_raw_mode () noexcept
{
  struct termios raw;
  if (tcgetattr (STDIN_FILENO, &raw) != 0)
    {
      return false;
    }

  original_termios_ = raw;
  cfmakeraw (&raw);
  raw.c_lflag &= ~ECHO;
  raw.c_lflag |= ISIG;
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;

  // Set non-blocking mode
  int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
  original_nonblock_ = (flags & O_NONBLOCK) != 0;
  fcntl (STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);

  return tcsetattr (STDIN_FILENO, TCSANOW, &raw) == 0;
}

void
MacOSNativeBackend::disable_raw_mode () noexcept
{
  tcsetattr (STDIN_FILENO, TCSANOW, &original_termios_);

  if (original_nonblock_)
    {
      int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
      fcntl (STDIN_FILENO, F_SETFL, flags & ~O_NONBLOCK);
    }
}

void
MacOSNativeBackend::append_output (std::string_view data) noexcept
{
  output_buffer_.append (data);
}

void
MacOSNativeBackend::flush_output () noexcept
{
  if (!output_buffer_.empty ())
    {
      write (STDOUT_FILENO, output_buffer_.data (),
	     output_buffer_.size ());
      output_buffer_.clear ();
    }
}

bool
MacOSNativeBackend::init () noexcept
{
  // Detect terminal emulator
  const char *term_program = std::getenv ("TERM_PROGRAM");
  if (term_program)
    {
      std::string program (term_program);
      if (program.find ("iTerm") != std::string::npos)
	is_iterm_ = true;
      else if (program.find ("Apple_Terminal") != std::string::npos)
	is_apple_terminal_ = true;
    }

  // Enable raw mode
  if (!enable_raw_mode ())
    {
      return false;
    }

  // Enable alternative screen buffer
  append_output ("\033[?1049h");
  append_output ("\033[?1000h"); // Enable UTF-8
  append_output ("\033[?1002h"); // Enable bracketed paste
  append_output ("\033[?1006h"); // Enable SGR mouse mode
  append_output ("\033[?25l"); // Hide cursor
  flush_output ();

  initialized_ = true;
  return true;
}

void
MacOSNativeBackend::cleanup () noexcept
{
  if (initialized_)
    {
      // Restore normal screen
      append_output ("\033[?1049l");
      append_output ("\033[?1000l"); // Disable UTF-8
      append_output ("\033[?1002l"); // Disable bracketed paste
      append_output ("\033[?1006l"); // Disable SGR mouse mode
      append_output ("\033[?25h"); // Show cursor
      flush_output ();

      disable_raw_mode ();
      initialized_ = false;
    }
}

void
MacOSNativeBackend::write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
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
MacOSNativeBackend::write_text (std::string_view text) noexcept
{
  if (!initialized_)
    {
      return;
    }

  append_output (text);
  flush_output ();
}

void
MacOSNativeBackend::clear_to_end (CursorPosition pos) noexcept
{
  append_output ("\033[0J");
  flush_output ();
}

void
MacOSNativeBackend::clear_frame () noexcept
{
  append_output ("\033[2J");
  flush_output ();
}

void
MacOSNativeBackend::clear_end_of_line (CursorPosition pos) noexcept
{
  append_output ("\033[K");
  flush_output ();
}

void
MacOSNativeBackend::set_cursor_position (CursorPosition pos) noexcept
{
  append_output (std::format ("\033[{};{}H", pos.row + 1, pos.col + 1));
  flush_output ();
  cursor_ = pos;
}

CursorPosition
MacOSNativeBackend::get_cursor_position () const noexcept
{
  return cursor_;
}

void
MacOSNativeBackend::insert_glyphs (CursorPosition pos,
				   std::span<TerminalGlyph> glyphs) noexcept
{
  set_cursor_position (pos);
  write_glyphs (glyphs);
}

void
MacOSNativeBackend::delete_glyphs (CursorPosition pos,
					 std::size_t n) noexcept
{
  set_cursor_position (pos);
  std::string spaces (n, ' ');
  append_output (spaces);
  flush_output ();
}

void
MacOSNativeBackend::insert_lines (CursorPosition pos, std::size_t n) noexcept
{
  append_output (std::format ("\033[{}L", n));
  flush_output ();
}

void
MacOSNativeBackend::delete_lines (CursorPosition pos, std::size_t n) noexcept
{
  append_output (std::format ("\033[{}M", n));
  flush_output ();
}

bool
MacOSNativeBackend::supports_colors () const noexcept
{
  return true;
}

bool
MacOSNativeBackend::supports_truecolor () const noexcept
{
  return is_iterm_ || is_apple_terminal_;
}

bool
MacOSNativeBackend::supports_blinking_cursor () const noexcept
{
  return true;
}

bool
MacOSNativeBackend::supports_bracketed_paste () const noexcept
{
  return true;
}

std::pair<int, int>
MacOSNativeBackend::get_terminal_size () const noexcept
{
  struct winsize ws = {};
  if (ioctl (STDOUT_FILENO, TIOCGWINSZ, &ws) == 0)
    {
      return { ws.ws_row, ws.ws_col };
    }
  return { 0, 0 };
}

InputEvent
MacOSNativeBackend::read_input () noexcept
{
  InputEvent event = {};
  event.type = InputEventType::None;

  char buf[32];
  ssize_t n = read (STDIN_FILENO, buf, sizeof (buf));

  if (n > 0)
    {
      if (buf[0] == '\033') // ESC
	{
	  // Read more bytes for escape sequence
	  char seq[8];
	  for (int i = 1; i < sizeof (seq); ++i)
	    {
	      ssize_t m = read (STDIN_FILENO, seq + i, 1);
	      if (m <= 0)
		break;
	    }

	  // Basic escape sequence parsing (simplified)
	  if (seq[0] == '[' && seq[1] == 'A')
	    {
	      event.type = InputEventType::Key;
	      event.key = 0x100 + 1; // Up arrow
	    }
	  else if (seq[0] == '[' && seq[1] == 'B')
	    {
	      event.type = InputEventType::Key;
	      event.key = 0x100 + 2; // Down arrow
	    }
	  else if (seq[0] == '[' && seq[1] == 'C')
	    {
	      event.type = InputEventType::Key;
	      event.key = 0x100 + 5; // Right arrow
	    }
	  else if (seq[0] == '[' && seq[1] == 'D')
	    {
	      event.type = InputEventType::Key;
	      event.key = 0x100 + 4; // Left arrow
	    }
	}
      else
	{
	  event.type = InputEventType::Key;
	  event.ch = static_cast<uint32_t> (buf[0]);
	}
    }

  return event;
}

void
MacOSNativeBackend::set_raw_mode (bool raw) noexcept
{
  if (raw)
    {
      enable_raw_mode ();
    }
  else
    {
      disable_raw_mode ();
    }
  raw_mode_ = raw;
}

void
MacOSNativeBackend::flush () noexcept
{
  flush_output ();
}

void
MacOSNativeBackend::enable_bracketed_paste (bool enable) noexcept
{
  const char *seq = enable ? "\033[?2004h" : "\033[?2004l";
  append_output (seq);
  flush_output ();
}

void
MacOSNativeBackend::set_color (uint8_t fg, uint8_t bg) noexcept
{
  append_output (std::format ("\033[3{};4{}m", fg, bg));
  flush_output ();
}

void
MacOSNativeBackend::set_truecolor (uint8_t r, uint8_t g, uint8_t b) noexcept
{
  // Already using truecolor in write_glyphs
}

void
MacOSNativeBackend::set_attribute (bool bold, bool italic, bool underline,
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

// Stub implementation when EMACS_USE_NSTERM is not defined

bool
MacOSNativeBackend::init () noexcept
{
  return false;
}

void
MacOSNativeBackend::cleanup () noexcept
{
}

void
MacOSNativeBackend::write_glyphs (std::span<TerminalGlyph>) noexcept
{
}

void
MacOSNativeBackend::write_text (std::string_view) noexcept
{
}

void
MacOSNativeBackend::clear_to_end (CursorPosition) noexcept
{
}

void
MacOSNativeBackend::clear_frame () noexcept
{
}

void
MacOSNativeBackend::clear_end_of_line (CursorPosition) noexcept
{
}

void
MacOSNativeBackend::set_cursor_position (CursorPosition) noexcept
{
}

CursorPosition
MacOSNativeBackend::get_cursor_position () const noexcept
{
  return { 0, 0 };
}

void
MacOSNativeBackend::insert_glyphs (CursorPosition,
				   std::span<TerminalGlyph>) noexcept
{
}

void
MacOSNativeBackend::delete_glyphs (CursorPosition, std::size_t) noexcept
{
}

void
MacOSNativeBackend::insert_lines (CursorPosition, std::size_t) noexcept
{
}

void
MacOSNativeBackend::delete_lines (CursorPosition, std::size_t) noexcept
{
}

bool
MacOSNativeBackend::supports_colors () const noexcept
{
  return false;
}

bool
MacOSNativeBackend::supports_truecolor () const noexcept
{
  return false;
}

bool
MacOSNativeBackend::supports_blinking_cursor () const noexcept
{
  return false;
}

bool
MacOSNativeBackend::supports_bracketed_paste () const noexcept
{
  return false;
}

std::pair<int, int>
MacOSNativeBackend::get_terminal_size () const noexcept
{
  return { 0, 0 };
}

InputEvent
MacOSNativeBackend::read_input () noexcept
{
  InputEvent event = {};
  event.type = InputEventType::None;
  return event;
}

void
MacOSNativeBackend::set_raw_mode (bool) noexcept
{
}

void
MacOSNativeBackend::flush () noexcept
{
}

void
MacOSNativeBackend::enable_bracketed_paste (bool) noexcept
{
}

void
MacOSNativeBackend::set_color (uint8_t, uint8_t) noexcept
{
}

void
MacOSNativeBackend::set_truecolor (uint8_t, uint8_t,
				     uint8_t) noexcept
{
}

void
MacOSNativeBackend::set_attribute (bool, bool, bool,
				       bool) noexcept
{
}

#endif

} // namespace emacs
