// src/input_parser.hpp
// Terminal input parser for escape sequences and keyboard events

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include "allocator.hpp"
#include "containers.hpp"

namespace emacs
{
namespace tui
{

enum class KeyModifier : uint8_t
{
  None = 0,
  Shift = 1 << 0,
  Alt = 1 << 1,
  Ctrl = 1 << 2,
  Meta = 1 << 3,
};

inline KeyModifier
operator| (KeyModifier a, KeyModifier b)
{
  return static_cast<KeyModifier> (static_cast<uint8_t> (a)
				   | static_cast<uint8_t> (b));
}

inline KeyModifier
operator& (KeyModifier a, KeyModifier b)
{
  return static_cast<KeyModifier> (static_cast<uint8_t> (a)
				   & static_cast<uint8_t> (b));
}

inline bool
has_modifier (KeyModifier mods, KeyModifier test)
{
  return (mods & test) == test;
}

enum class KeyCode : uint16_t
{
  Unknown = 0,

  Tab = 9,
  Enter = 13,
  Escape = 27,
  Backspace = 127,

  ArrowUp = 256,
  ArrowDown,
  ArrowLeft,
  ArrowRight,

  Home,
  End,
  PageUp,
  PageDown,
  Insert,
  Delete,

  F1,
  F2,
  F3,
  F4,
  F5,
  F6,
  F7,
  F8,
  F9,
  F10,
  F11,
  F12,
};

enum class MouseButton : uint8_t
{
  None = 0,
  Left = 1,
  Middle = 2,
  Right = 3,
  WheelUp = 4,
  WheelDown = 5,
};

enum class MouseEventType : uint8_t
{
  Press,
  Release,
  Move,
  Drag,
  Scroll,
};

struct KeyEvent
{
  KeyCode key;
  KeyModifier modifiers;
  uint32_t unicode;

  KeyEvent ()
      : key (KeyCode::Unknown), modifiers (KeyModifier::None),
	unicode (0)
  {
  }
  KeyEvent (KeyCode k, KeyModifier m = KeyModifier::None,
	    uint32_t u = 0)
      : key (k), modifiers (m), unicode (u)
  {
  }
};

struct MouseEvent
{
  MouseButton button;
  MouseEventType type;
  int row;
  int col;
  KeyModifier modifiers;

  MouseEvent ()
      : button (MouseButton::None), type (MouseEventType::Press),
	row (0), col (0), modifiers (KeyModifier::None)
  {
  }
  MouseEvent (MouseButton btn, MouseEventType t, int r, int c,
	      KeyModifier m = KeyModifier::None)
      : button (btn), type (t), row (r), col (c), modifiers (m)
  {
  }
};

enum class InputEventType : uint8_t
{
  None,
  Key,
  Mouse,
  Resize,
};

struct InputEvent
{
  InputEventType type;
  union
  {
    KeyEvent key;
    MouseEvent mouse;
    struct
    {
      int rows;
      int cols;
    } resize;
  };

  InputEvent () : type (InputEventType::None), resize{ 0, 0 } {}

  InputEvent (const InputEvent &other)
      : type (other.type), resize{ 0, 0 }
  {
    switch (type)
      {
      case InputEventType::Key:
	key = other.key;
	break;
      case InputEventType::Mouse:
	mouse = other.mouse;
	break;
      case InputEventType::Resize:
	resize = other.resize;
	break;
      default:
	break;
      }
  }

  InputEvent &operator= (const InputEvent &other)
  {
    if (this != &other)
      {
	type = other.type;
	switch (type)
	  {
	  case InputEventType::Key:
	    key = other.key;
	    break;
	  case InputEventType::Mouse:
	    mouse = other.mouse;
	    break;
	  case InputEventType::Resize:
	    resize = other.resize;
	    break;
	  default:
	    resize = { 0, 0 };
	    break;
	  }
      }
    return *this;
  }

  InputEvent (InputEvent &&) = default;
  InputEvent &operator= (InputEvent &&) = default;

  static InputEvent make_key (const KeyEvent &k)
  {
    InputEvent e;
    e.type = InputEventType::Key;
    e.key = k;
    return e;
  }

  static InputEvent make_mouse (const MouseEvent &m)
  {
    InputEvent e;
    e.type = InputEventType::Mouse;
    e.mouse = m;
    return e;
  }

  static InputEvent make_resize (int rows, int cols)
  {
    InputEvent e;
    e.type = InputEventType::Resize;
    e.resize.rows = rows;
    e.resize.cols = cols;
    return e;
  }
};

class InputParser
{
public:
  InputParser () = default;
  ~InputParser () = default;

  InputParser (const InputParser &) = delete;
  InputParser &operator= (const InputParser &) = delete;

  InputParser (InputParser &&) = default;
  InputParser &operator= (InputParser &&) = default;

  void feed (std::string_view data);

  std::optional<InputEvent> next_event ();

  bool has_events () const noexcept { return !events_.empty (); }

  void clear () noexcept
  {
    buffer_.clear ();
    events_.clear ();
  }

private:
  void parse_buffer ();
  bool try_parse_escape_sequence ();
  bool try_parse_csi_sequence ();
  bool try_parse_mouse_sgr (std::string_view params);
  bool try_parse_utf8 ();

  void add_event (const InputEvent &event)
  {
    events_.push_back (event);
  }

  gc_string buffer_;
  gc_vector_t<InputEvent> events_;
};

}
}
