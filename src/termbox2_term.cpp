// src/termbox2_term.cpp
#include "termbox2.h"

#include <cerrno>
#include <cstring>
#include <iostream>
#include <vector>

#include "termbox2_term.hpp"

namespace emacs
{

Termbox2Backend::Termbox2Backend () noexcept
    : initialized_ (false), width_ (0), height_ (0), cursor_{ 0, 0 },
      raw_mode_enabled_ (false), bracketed_paste_enabled_ (false)
{
}

Termbox2Backend::~Termbox2Backend () { cleanup (); }

[[nodiscard]] bool
Termbox2Backend::init () noexcept
{
  int ret = tb_init ();
  if (ret != TB_OK)
    {
      std::cerr << "Termbox2 init failed with error code: " << ret
		<< "\n";
      return false;
    }

  tb_set_input_mode (TB_INPUT_ESC | TB_INPUT_MOUSE);
  tb_set_output_mode (TB_OUTPUT_TRUECOLOR);

  width_ = tb_width ();
  height_ = tb_height ();

  tb_clear ();
  tb_present ();

  initialized_ = true;
  raw_mode_enabled_ = false;
  bracketed_paste_enabled_ = false;

  return true;
}

void
Termbox2Backend::cleanup () noexcept
{
  if (initialized_)
    {
      tb_shutdown ();
      initialized_ = false;
    }
}

struct tb_cell
Termbox2Backend::glyph_to_cell (
  const TerminalGlyph &glyph) const noexcept
{
  struct tb_cell cell;
  cell.ch = glyph.codepoint;
  cell.fg = color_to_termbox (glyph.foreground);
  cell.bg = color_to_termbox (glyph.background);

  uint32_t attr = attributes_to_termbox (glyph.bold, glyph.italic,
					 glyph.underline,
					 glyph.inverse, glyph.blink);
  cell.fg |= attr;

  return cell;
}

[[nodiscard]] uint32_t
Termbox2Backend::color_to_termbox (
  const TerminalColor &color) const noexcept
{
  return (static_cast<uint32_t> (color.red) << 16)
	 | (static_cast<uint32_t> (color.green) << 8)
	 | static_cast<uint32_t> (color.blue);
}

[[nodiscard]] uint32_t
Termbox2Backend::attributes_to_termbox (bool bold, bool italic,
					bool underline, bool inverse,
					bool blink) const noexcept
{
  uint32_t attr = 0;

  if (bold)
    attr |= TB_BOLD;
  if (italic)
    attr |= TB_ITALIC;
  if (underline)
    attr |= TB_UNDERLINE;
  if (inverse)
    attr |= TB_REVERSE;
  if (blink)
    attr |= TB_BLINK;

  return attr;
}

void
Termbox2Backend::write_glyphs (
  std::span<TerminalGlyph> glyphs) noexcept
{
  if (!initialized_)
    return;

  for (const auto &glyph : glyphs)
    {
      struct tb_cell cell = glyph_to_cell (glyph);
      int row = cursor_.row;
      int col = cursor_.col;

      if (row >= height_)
	break;
      if (col >= width_)
	break;

      tb_set_cell (col, row, cell.ch, cell.fg, cell.bg);

      cursor_.col++;
      if (cursor_.col >= width_)
	{
	  cursor_.col = 0;
	  cursor_.row++;
	}
    }
}

void
Termbox2Backend::write_text (std::string_view text) noexcept
{
  if (!initialized_)
    return;

  const char *ptr = text.data ();
  const char *end = ptr + text.size ();

  while (ptr < end)
    {
      if (cursor_.row >= height_)
	break;
      if (cursor_.col >= width_)
	break;

      // Decode UTF-8 sequence to Unicode codepoint
      uint32_t codepoint = 0;
      int len = tb_utf8_char_to_unicode (&codepoint, ptr);

      if (len <= 0)
	{
	  // Invalid UTF-8, skip byte
	  ++ptr;
	  continue;
	}

      tb_set_cell (cursor_.col, cursor_.row, codepoint, TB_DEFAULT,
		   TB_DEFAULT);

      cursor_.col++;
      if (cursor_.col >= width_)
	{
	  cursor_.col = 0;
	  cursor_.row++;
	}

      ptr += len;
    }
}

void
Termbox2Backend::clear_to_end (CursorPosition pos) noexcept
{
  if (!initialized_)
    return;

  for (int row = pos.row; row < height_; ++row)
    {
      for (int col = 0; col < width_; ++col)
	{
	  tb_set_cell (col, row, 0, TB_DEFAULT, TB_DEFAULT);
	}
    }

  tb_set_cursor (pos.col, pos.row);
}

void
Termbox2Backend::clear_frame () noexcept
{
  if (!initialized_)
    return;

  tb_clear ();
}

void
Termbox2Backend::clear_end_of_line (CursorPosition pos) noexcept
{
  if (!initialized_)
    return;

  for (int col = pos.col; col < width_; ++col)
    {
      tb_set_cell (col, pos.row, 0, TB_DEFAULT, TB_DEFAULT);
    }
}

void
Termbox2Backend::set_cursor_position (CursorPosition pos) noexcept
{
  if (!initialized_)
    return;

  cursor_ = pos;
  tb_set_cursor (pos.col, pos.row);
}

[[nodiscard]] CursorPosition
Termbox2Backend::get_cursor_position () const noexcept
{
  return cursor_;
}

void
Termbox2Backend::insert_glyphs (
  CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept
{
  if (!initialized_)
    return;

  std::vector<struct tb_cell> buffer;
  buffer.reserve (glyphs.size ());

  for (const auto &glyph : glyphs)
    {
      buffer.push_back (glyph_to_cell (glyph));
    }

  for (size_t i = 0; i < buffer.size (); ++i)
    {
      int col = pos.col + static_cast<int> (i);
      int row = pos.row;

      if (row >= height_)
	continue;

      tb_set_cell (col, row, buffer[i].ch, buffer[i].fg,
		   buffer[i].bg);
    }
}

void
Termbox2Backend::delete_glyphs (CursorPosition pos,
				std::size_t n) noexcept
{
  if (!initialized_)
    return;

  for (size_t i = 0; i < n; ++i)
    {
      int col = pos.col + static_cast<int> (i);
      int row = pos.row;

      if (row >= height_)
	continue;

      tb_set_cell (col, row, ' ', TB_DEFAULT, TB_DEFAULT);
    }
}

void
Termbox2Backend::insert_lines (CursorPosition pos,
			       std::size_t n) noexcept
{
  if (!initialized_ || n == 0)
    return;

  int start_row = pos.row;
  int lines_to_move = height_ - start_row - static_cast<int> (n);

  if (lines_to_move > 0)
    {
      struct tb_cell *back_buffer = tb_cell_buffer ();

      for (int row = height_ - 1;
	   row >= start_row + static_cast<int> (n); --row)
	{
	  int src_row = row - static_cast<int> (n);
	  for (int col = 0; col < width_; ++col)
	    {
	      struct tb_cell &src
		= back_buffer[src_row * width_ + col];
	      tb_set_cell (col, row, src.ch, src.fg, src.bg);
	    }
	}
    }

  for (size_t i = 0;
       i < n && start_row + static_cast<int> (i) < height_; ++i)
    {
      int row = start_row + static_cast<int> (i);
      for (int col = 0; col < width_; ++col)
	{
	  tb_set_cell (col, row, ' ', TB_DEFAULT, TB_DEFAULT);
	}
    }
}

void
Termbox2Backend::delete_lines (CursorPosition pos,
			       std::size_t n) noexcept
{
  if (!initialized_ || n == 0)
    return;

  int start_row = pos.row;
  int lines_to_move = height_ - start_row - static_cast<int> (n);

  if (lines_to_move > 0)
    {
      struct tb_cell *back_buffer = tb_cell_buffer ();

      for (int row = start_row; row < height_ - static_cast<int> (n);
	   ++row)
	{
	  int src_row = row + static_cast<int> (n);
	  for (int col = 0; col < width_; ++col)
	    {
	      struct tb_cell &src
		= back_buffer[src_row * width_ + col];
	      tb_set_cell (col, row, src.ch, src.fg, src.bg);
	    }
	}
    }

  for (int row = height_ - static_cast<int> (n); row < height_; ++row)
    {
      if (row < 0)
	continue;
      for (int col = 0; col < width_; ++col)
	{
	  tb_set_cell (col, row, ' ', TB_DEFAULT, TB_DEFAULT);
	}
    }
}

[[nodiscard]] bool
Termbox2Backend::supports_colors () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
Termbox2Backend::supports_truecolor () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
Termbox2Backend::supports_blinking_cursor () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
Termbox2Backend::supports_bracketed_paste () const noexcept
{
  return initialized_;
}

[[nodiscard]] std::pair<int, int>
Termbox2Backend::get_terminal_size () const noexcept
{
  return { height_, width_ };
}

[[nodiscard]] InputEvent
Termbox2Backend::read_input () noexcept
{
  InputEvent result;

  if (!initialized_)
    {
      result.type = InputEventType::Error;
      return result;
    }

  struct tb_event ev;
  int ret;

retry:
  ret = tb_poll_event (&ev);

  if (ret == TB_ERR_POLL)
    {
      if (tb_last_errno () == EINTR)
	goto retry;

      result.type = InputEventType::Error;
      return result;
    }

  if (ret != TB_OK)
    {
      result.type = InputEventType::Error;
      return result;
    }

  switch (ev.type)
    {
    case TB_EVENT_KEY:
      result.type = InputEventType::Key;
      result.mod = ev.mod;
      if (ev.ch != 0)
	{
	  result.ch = ev.ch;
	  result.key = 0;
	}
      else
	{
	  result.ch = 0;
	  result.key = ev.key;
	}
      break;

    case TB_EVENT_RESIZE:
      result.type = InputEventType::Resize;
      result.w = ev.w;
      result.h = ev.h;
      width_ = ev.w;
      height_ = ev.h;
      break;

    case TB_EVENT_MOUSE:
      result.type = InputEventType::Mouse;
      result.x = ev.x;
      result.y = ev.y;
      result.mod = ev.mod;

      switch (ev.key)
	{
	case TB_KEY_MOUSE_LEFT:
	  result.button = MouseButton::Left;
	  break;
	case TB_KEY_MOUSE_RIGHT:
	  result.button = MouseButton::Right;
	  break;
	case TB_KEY_MOUSE_MIDDLE:
	  result.button = MouseButton::Middle;
	  break;
	case TB_KEY_MOUSE_WHEEL_UP:
	  result.button = MouseButton::WheelUp;
	  break;
	case TB_KEY_MOUSE_WHEEL_DOWN:
	  result.button = MouseButton::WheelDown;
	  break;
	case TB_KEY_MOUSE_RELEASE:
	  result.button = MouseButton::Release;
	  break;
	default:
	  result.button = MouseButton::None;
	  break;
	}
      break;

    default:
      result.type = InputEventType::None;
      break;
    }

  return result;
}

void
Termbox2Backend::set_raw_mode (bool raw) noexcept
{
  if (!initialized_)
    return;

  raw_mode_enabled_ = raw;
}

void
Termbox2Backend::enable_bracketed_paste (bool enable) noexcept
{
  if (!initialized_)
    return;

  bracketed_paste_enabled_ = enable;

  if (enable)
    {
      tb_send ("\033[?2004h", 8);
    }
  else
    {
      tb_send ("\033[?2004l", 8);
    }
}

void
Termbox2Backend::set_color (uint8_t fg, uint8_t bg) noexcept
{
  if (!initialized_)
    return;

  tb_set_cell (cursor_.col, cursor_.row, 0,
	       static_cast<uint32_t> (fg),
	       static_cast<uint32_t> (bg));
}

void
Termbox2Backend::set_truecolor (uint8_t r, uint8_t g,
				uint8_t b) noexcept
{
  if (!initialized_)
    return;

  uint32_t color = (static_cast<uint32_t> (r) << 16)
		   | (static_cast<uint32_t> (g) << 8)
		   | static_cast<uint32_t> (b);

  tb_set_cell (cursor_.col, cursor_.row, 0, color, TB_DEFAULT);
}

void
Termbox2Backend::set_attribute (bool bold, bool italic,
				bool underline, bool inverse) noexcept
{
  if (!initialized_)
    return;

  uint32_t attr
    = attributes_to_termbox (bold, italic, underline, inverse, false);
  tb_set_cell (cursor_.col, cursor_.row, 0, TB_DEFAULT | attr,
	       TB_DEFAULT);
}

void
Termbox2Backend::flush () noexcept
{
  if (!initialized_)
    return;

  tb_present ();
}

} // namespace emacs
