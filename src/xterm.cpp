// src/xterm.cpp
#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <format>
#include <iostream>
#include <vector>

#ifdef EMACS_USE_POSIX_TTY
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#endif

#include "xterm.hpp"

namespace emacs
{

#ifdef EMACS_USE_POSIX_TTY

PosixTtyBackend::PosixTtyBackend () noexcept
{
}

PosixTtyBackend::~PosixTtyBackend ()
{
  cleanup ();
}

bool
PosixTtyBackend::init () noexcept
{
  if (initialized_)
    {
      return true;
    }

  if (!enable_raw_mode ())
    {
      return false;
    }

  // Enter alternate screen, enable mouse reporting (SGR), hide cursor
  append_output ("\033[?1049h" // Alternate screen
		 "\033[?1000h" // Mouse click
		 "\033[?1002h" // Mouse drag
		 "\033[?1006h" // Mouse SGR
		 "\033[?25l"); // Hide cursor initially

  flush ();
  initialized_ = true;
  return true;
}

void
PosixTtyBackend::cleanup () noexcept
{
  if (!initialized_)
    {
      return;
    }

  // Exit alternate screen, disable mouse, show cursor
  append_output ("\033[?25h"   // Show cursor
		 "\033[?1006l" // Disable SGR
		 "\033[?1002l" // Disable drag
		 "\033[?1000l" // Disable click
		 "\033[?1049l"); // Exit alternate screen
  flush ();

  disable_raw_mode ();
  initialized_ = false;
}

bool
PosixTtyBackend::enable_raw_mode () noexcept
{
  if (tcgetattr (STDIN_FILENO, &original_termios_) == -1)
    {
      return false;
    }

  struct termios raw = original_termios_;
  raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  raw.c_oflag &= ~(OPOST);
  raw.c_cflag |= (CS8);
  raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  raw.c_cc[VMIN] = 0;
  raw.c_cc[VTIME] = 1;

  if (tcsetattr (STDIN_FILENO, TCSAFLUSH, &raw) == -1)
    {
      return false;
    }

  int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
  if (flags != -1)
    {
      original_nonblock_ = (flags & O_NONBLOCK);
      fcntl (STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }

  raw_mode_enabled_ = true;
  return true;
}

void
PosixTtyBackend::disable_raw_mode () noexcept
{
  if (raw_mode_enabled_)
    {
      tcsetattr (STDIN_FILENO, TCSAFLUSH, &original_termios_);

      int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
      if (flags != -1)
        {
          if (original_nonblock_)
            flags |= O_NONBLOCK;
          else
            flags &= ~O_NONBLOCK;
          fcntl (STDIN_FILENO, F_SETFL, flags);
        }

      raw_mode_enabled_ = false;
    }
}

void
PosixTtyBackend::append_output (std::string_view data) noexcept
{
  output_buffer_.append (data);
}

void
PosixTtyBackend::append_output (char c) noexcept
{
  output_buffer_.push_back (c);
}

void
PosixTtyBackend::flush () noexcept
{
  if (output_buffer_.empty ())
    {
      return;
    }

  // Use write to avoid C++ iostream syncing issues
  ::write (STDOUT_FILENO, output_buffer_.data (), output_buffer_.size ());
  output_buffer_.clear ();
}

void
PosixTtyBackend::emit_sgr_color (bool foreground,
				 const TerminalColor &color) noexcept
{
  // Truecolor: ESC [ 38;2;r;g;b m (fg) or 48;2;r;g;b m (bg)
  std::string buf = std::format ("\033[{};2;{};{};{}m", foreground ? 38 : 48,
				 color.red, color.green, color.blue);
  append_output (buf);
}

void
PosixTtyBackend::emit_sgr (const TerminalGlyph &glyph) noexcept
{
  append_output ("\033[0"); // Reset first
  if (glyph.bold)
    append_output (";1");
  if (glyph.italic)
    append_output (";3");
  if (glyph.underline)
    append_output (";4");
  if (glyph.blink)
    append_output (";5");
  if (glyph.inverse)
    append_output (";7");

  append_output ("m");

  emit_sgr_color (true, glyph.foreground);
  emit_sgr_color (false, glyph.background);
}

void
PosixTtyBackend::write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
{
  for (const auto &glyph : glyphs)
    {
      emit_sgr (glyph);

      // Basic UTF-8 encoding
      if (glyph.codepoint < 0x80)
	{
	  append_output (static_cast<char> (glyph.codepoint));
	}
      else if (glyph.codepoint < 0x800)
	{
	  append_output (static_cast<char> (0xC0 | (glyph.codepoint >> 6)));
	  append_output (static_cast<char> (0x80 | (glyph.codepoint & 0x3F)));
	}
      else if (glyph.codepoint < 0x10000)
	{
	  append_output (static_cast<char> (0xE0 | (glyph.codepoint >> 12)));
	  append_output (
	    static_cast<char> (0x80 | ((glyph.codepoint >> 6) & 0x3F)));
	  append_output (static_cast<char> (0x80 | (glyph.codepoint & 0x3F)));
	}
      else
	{
	  append_output (static_cast<char> (0xF0 | (glyph.codepoint >> 18)));
	  append_output (
	    static_cast<char> (0x80 | ((glyph.codepoint >> 12) & 0x3F)));
	  append_output (
	    static_cast<char> (0x80 | ((glyph.codepoint >> 6) & 0x3F)));
	  append_output (static_cast<char> (0x80 | (glyph.codepoint & 0x3F)));
	}
    }
}

void
PosixTtyBackend::write_text (std::string_view text) noexcept
{
  // Assume default attributes for raw text
  append_output ("\033[0m");
  append_output (text);
}

void
PosixTtyBackend::clear_to_end (CursorPosition pos) noexcept
{
  set_cursor_position (pos);
  append_output ("\033[J");
}

void
PosixTtyBackend::clear_frame () noexcept
{
  append_output ("\033[2J");
}

void
PosixTtyBackend::clear_end_of_line (CursorPosition pos) noexcept
{
  set_cursor_position (pos);
  append_output ("\033[K");
}

void
PosixTtyBackend::set_cursor_position (CursorPosition pos) noexcept
{
  cursor_ = pos;
  std::string buf = std::format ("\033[{};{}H", pos.row + 1, pos.col + 1);
  append_output (buf);
}

CursorPosition
PosixTtyBackend::get_cursor_position () const noexcept
{
  return cursor_;
}

void
PosixTtyBackend::insert_glyphs (CursorPosition pos,
				std::span<TerminalGlyph> glyphs) noexcept
{
  set_cursor_position (pos);
  // Insert blanks
  std::string buf = std::format ("\033[{}@", glyphs.size ());
  append_output (buf);
  // Write glyphs
  write_glyphs (glyphs);
}

void
PosixTtyBackend::delete_glyphs (CursorPosition pos, std::size_t n) noexcept
{
  set_cursor_position (pos);
  std::string buf = std::format ("\033[{}P", n);
  append_output (buf);
}

void
PosixTtyBackend::insert_lines (CursorPosition pos, std::size_t n) noexcept
{
  set_cursor_position (pos);
  std::string buf = std::format ("\033[{}L", n);
  append_output (buf);
}

void
PosixTtyBackend::delete_lines (CursorPosition pos, std::size_t n) noexcept
{
  set_cursor_position (pos);
  std::string buf = std::format ("\033[{}M", n);
  append_output (buf);
}

bool
PosixTtyBackend::supports_colors () const noexcept
{
  return true;
}

bool
PosixTtyBackend::supports_truecolor () const noexcept
{
  return true;
}

bool
PosixTtyBackend::supports_blinking_cursor () const noexcept
{
  return true;
}

bool
PosixTtyBackend::supports_bracketed_paste () const noexcept
{
  return true;
}

std::pair<int, int>
PosixTtyBackend::get_terminal_size () const noexcept
{
  struct winsize ws;
  if (ioctl (STDOUT_FILENO, TIOCGWINSZ, &ws) == -1)
    {
      return { 24, 80 };
    }
  return { ws.ws_row, ws.ws_col };
}

void
PosixTtyBackend::set_raw_mode (bool raw) noexcept
{
  if (raw)
    (void)enable_raw_mode ();
  else
    disable_raw_mode ();
}

InputEvent
PosixTtyBackend::read_input () noexcept
{
  char buf[256];
  ssize_t n = ::read (STDIN_FILENO, buf, sizeof (buf));
  if (n > 0)
    {
      input_queue_.insert (input_queue_.end (), buf, buf + n);
    }

  if (input_queue_.empty())
    return { InputEventType::None };

  InputEvent event;
  event.type = InputEventType::None;

  auto& q = input_queue_;
  unsigned char c = static_cast<unsigned char>(q[0]);

  if (c == 0x1b) // ESC
    {
      if (q.size() < 2)
        {
          if (n == 0) // No new data, assuming bare ESC
            {
               event.type = InputEventType::Key;
               event.key = 27; // ESC
               q.erase(q.begin());
               return event;
            }
          return { InputEventType::None };
        }

      if (q[1] == '[' || q[1] == 'O') // CSI or SS3
        {
           // Check for Mouse SGR: <ESC>[<Button>;<Px>;<Py>M
           if (q.size() > 5 && q[2] == '<')
             {
               size_t end = 0;
               for(size_t i=3; i<q.size(); ++i) {
                 if (q[i] == 'm' || q[i] == 'M') { end = i; break; }
               }

               if (end > 0)
                 {
                    // Parse SGR (simplified, just consume for now to not block)
                    // TODO: Actual SGR parsing
                    q.erase(q.begin(), q.begin() + end + 1);
                    return { InputEventType::Mouse };
                 }
             }

           // Check for arrow keys
           char code = q.size() > 2 ? q[2] : 0;
           if (q[1] == '[')
             {
               if (code == 'A') { event.type = InputEventType::Key; event.key = 1000; /* Up */ }
               else if (code == 'B') { event.type = InputEventType::Key; event.key = 1001; /* Down */ }
               else if (code == 'C') { event.type = InputEventType::Key; event.key = 1002; /* Right */ }
               else if (code == 'D') { event.type = InputEventType::Key; event.key = 1003; /* Left */ }

               if (event.type != InputEventType::None)
                 {
                   q.erase(q.begin(), q.begin() + 3);
                   return event;
                 }
             }
        }

       // Fallback
       event.type = InputEventType::Key;
       event.key = 27;
       q.erase(q.begin());
    }
  else
    {
       event.type = InputEventType::Key;
       event.ch = c;
       event.key = c;
       q.erase(q.begin());
    }

  return event;
}

#endif // EMACS_USE_POSIX_TTY

} // namespace emacs
