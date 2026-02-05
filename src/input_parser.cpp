// src/input_parser.cpp
// Terminal input parser implementation

#include "input_parser.hpp"
#include <algorithm>
#include <cctype>

namespace emacs
{
namespace tui
{

void
InputParser::feed (std::string_view data)
{
  buffer_.append (data);
  parse_buffer ();
}

std::optional<InputEvent>
InputParser::next_event ()
{
  if (events_.empty ())
    {
      return std::nullopt;
    }

  InputEvent event = events_.front ();
  events_.erase (events_.begin ());
  return event;
}

void
InputParser::parse_buffer ()
{
  while (!buffer_.empty ())
    {
      if (buffer_[0] == '\x1b')
	{
	  if (!try_parse_escape_sequence ())
	    {
	      break;
	    }
	}
      else if (try_parse_utf8 ())
	{
	  continue;
	}
      else
	{
	  break;
	}
    }
}

bool
InputParser::try_parse_escape_sequence ()
{
  if (buffer_.size () < 2)
    {
      return false;
    }

  if (buffer_[1] == '[')
    {
      return try_parse_csi_sequence ();
    }

  if (buffer_[1] == 'O')
    {
      if (buffer_.size () < 3)
	{
	  return false;
	}

      char c = buffer_[2];
      KeyCode key = KeyCode::Unknown;

      switch (c)
	{
	case 'P':
	  key = KeyCode::F1;
	  break;
	case 'Q':
	  key = KeyCode::F2;
	  break;
	case 'R':
	  key = KeyCode::F3;
	  break;
	case 'S':
	  key = KeyCode::F4;
	  break;
	default:
	  return false;
	}

      add_event (InputEvent::make_key (KeyEvent (key)));
      buffer_.erase (0, 3);
      return true;
    }

  add_event (InputEvent::make_key (
    KeyEvent (KeyCode::Escape, KeyModifier::None)));
  buffer_.erase (0, 1);
  return true;
}

bool
InputParser::try_parse_csi_sequence ()
{
  size_t end = buffer_.find_first_not_of ("0123456789;", 2);

  if (end == gc_string::npos)
    {
      return false;
    }

  char final = buffer_[end];
  std::string_view params (buffer_.data () + 2, end - 2);

  if (final == 'M' || final == 'm')
    {
      return try_parse_mouse_sgr (params);
    }

  KeyCode key = KeyCode::Unknown;
  switch (final)
    {
    case 'A':
      key = KeyCode::ArrowUp;
      break;
    case 'B':
      key = KeyCode::ArrowDown;
      break;
    case 'C':
      key = KeyCode::ArrowRight;
      break;
    case 'D':
      key = KeyCode::ArrowLeft;
      break;
    case 'H':
      key = KeyCode::Home;
      break;
    case 'F':
      key = KeyCode::End;
      break;
    case '~':
      {
	if (params == "2")
	  {
	    key = KeyCode::Insert;
	  }
	else if (params == "3")
	  {
	    key = KeyCode::Delete;
	  }
	else if (params == "5")
	  {
	    key = KeyCode::PageUp;
	  }
	else if (params == "6")
	  {
	    key = KeyCode::PageDown;
	  }
	else if (params == "15")
	  {
	    key = KeyCode::F5;
	  }
	else if (params == "17")
	  {
	    key = KeyCode::F6;
	  }
	else if (params == "18")
	  {
	    key = KeyCode::F7;
	  }
	else if (params == "19")
	  {
	    key = KeyCode::F8;
	  }
	else if (params == "20")
	  {
	    key = KeyCode::F9;
	  }
	else if (params == "21")
	  {
	    key = KeyCode::F10;
	  }
	else if (params == "23")
	  {
	    key = KeyCode::F11;
	  }
	else if (params == "24")
	  {
	    key = KeyCode::F12;
	  }
	break;
      }
    default:
      return false;
    }

  if (key != KeyCode::Unknown)
    {
      add_event (InputEvent::make_key (KeyEvent (key)));
      buffer_.erase (0, end + 1);
      return true;
    }

  return false;
}

bool
InputParser::try_parse_mouse_sgr (std::string_view params)
{
  size_t semi1 = params.find (';');
  if (semi1 == std::string_view::npos)
    {
      return false;
    }

  size_t semi2 = params.find (';', semi1 + 1);
  if (semi2 == std::string_view::npos)
    {
      return false;
    }

  int button_code = 0;
  int col = 0;
  int row = 0;

  try
    {
      button_code
	= std::stoi (std::string (params.substr (0, semi1)));
      col = std::stoi (
	std::string (params.substr (semi1 + 1, semi2 - semi1 - 1)));
      row = std::stoi (std::string (params.substr (semi2 + 1)));
    }
  catch (...)
    {
      return false;
    }

  MouseButton btn = MouseButton::Left;
  if ((button_code & 3) == 0)
    {
      btn = MouseButton::Left;
    }
  else if ((button_code & 3) == 1)
    {
      btn = MouseButton::Middle;
    }
  else if ((button_code & 3) == 2)
    {
      btn = MouseButton::Right;
    }

  MouseEventType type = MouseEventType::Press;
  if (button_code & 32)
    {
      type = MouseEventType::Move;
    }
  else if (button_code & 64)
    {
      type = MouseEventType::Scroll;
      btn = (button_code & 1) ? MouseButton::WheelDown
			      : MouseButton::WheelUp;
    }

  add_event (InputEvent::make_mouse (
    MouseEvent (btn, type, row - 1, col - 1)));

  size_t end = buffer_.find_first_of ("Mm", 2);
  if (end != gc_string::npos)
    {
      buffer_.erase (0, end + 1);
      return true;
    }

  return false;
}

bool
InputParser::try_parse_utf8 ()
{
  if (buffer_.empty ())
    {
      return false;
    }

  unsigned char c = static_cast<unsigned char> (buffer_[0]);

  if (c < 0x80)
    {
      if (c == '\t')
	{
	  add_event (InputEvent::make_key (
	    KeyEvent (KeyCode::Tab, KeyModifier::None, '\t')));
	}
      else if (c == '\r' || c == '\n')
	{
	  add_event (InputEvent::make_key (
	    KeyEvent (KeyCode::Enter, KeyModifier::None, '\n')));
	}
      else if (c == 127)
	{
	  add_event (InputEvent::make_key (
	    KeyEvent (KeyCode::Backspace, KeyModifier::None, 127)));
	}
      else if (c >= 32)
	{
	  add_event (InputEvent::make_key (
	    KeyEvent (KeyCode::Unknown, KeyModifier::None, c)));
	}
      else if (c >= 1 && c <= 26)
	{
	  uint32_t unicode = c + 'a' - 1;
	  add_event (InputEvent::make_key (
	    KeyEvent (KeyCode::Unknown, KeyModifier::Ctrl, unicode)));
	}

      buffer_.erase (0, 1);
      return true;
    }

  int bytes = 0;
  uint32_t unicode = 0;

  if ((c & 0xE0) == 0xC0)
    {
      bytes = 2;
      unicode = c & 0x1F;
    }
  else if ((c & 0xF0) == 0xE0)
    {
      bytes = 3;
      unicode = c & 0x0F;
    }
  else if ((c & 0xF8) == 0xF0)
    {
      bytes = 4;
      unicode = c & 0x07;
    }
  else
    {
      buffer_.erase (0, 1);
      return true;
    }

  if (buffer_.size () < static_cast<size_t> (bytes))
    {
      return false;
    }

  for (int i = 1; i < bytes; ++i)
    {
      unsigned char byte = static_cast<unsigned char> (buffer_[i]);
      if ((byte & 0xC0) != 0x80)
	{
	  buffer_.erase (0, 1);
	  return true;
	}
      unicode = (unicode << 6) | (byte & 0x3F);
    }

  add_event (InputEvent::make_key (
    KeyEvent (KeyCode::Unknown, KeyModifier::None, unicode)));
  buffer_.erase (0, bytes);
  return true;
}

}
}
