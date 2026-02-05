// src/emacs_input_adapter.cpp
// Phase 5.2: Input Integration

#include "emacs_input_adapter.hpp"
#include <cstring>

namespace emacs
{
namespace tui
{

void
EmacsInputAdapter::init_event (struct input_event &event)
{
  std::memset (&event, 0, sizeof (struct input_event));
  event.kind = NO_EVENT;
}

struct input_event
EmacsInputAdapter::to_emacs_event (const InputEvent &event)
{
  switch (event.type)
    {
    case InputEventType::Key:
      return key_event_to_emacs (event.key);

    case InputEventType::Mouse:
      return mouse_event_to_emacs (event.mouse);

    case InputEventType::Resize:
      {
	struct input_event emacs_event;
	init_event (emacs_event);
	return emacs_event;
      }

    default:
      {
	struct input_event emacs_event;
	init_event (emacs_event);
	return emacs_event;
      }
    }
}

struct input_event
EmacsInputAdapter::key_event_to_emacs (const KeyEvent &key)
{
  struct input_event emacs_event;
  init_event (emacs_event);

  emacs_event.modifiers = modifiers_to_emacs (key.modifiers);

  if (key.unicode > 0 && key.unicode < 128)
    {
      emacs_event.kind = ASCII_KEYSTROKE_EVENT;
      emacs_event.code = key.unicode;
    }
  else if (key.unicode >= 128)
    {
      emacs_event.kind = MULTIBYTE_CHAR_KEYSTROKE_EVENT;
      emacs_event.code = key.unicode;
    }
  else
    {
      emacs_event.kind = NON_ASCII_KEYSTROKE_EVENT;
      emacs_event.code = keycode_to_keysym (key.key);
    }

  return emacs_event;
}

struct input_event
EmacsInputAdapter::mouse_event_to_emacs (const MouseEvent &mouse)
{
  struct input_event emacs_event;
  init_event (emacs_event);

  if (is_wheel_event (mouse.button))
    {
      emacs_event.kind = WHEEL_EVENT;
      emacs_event.code
	= (mouse.button == MouseButton::WheelUp) ? 0 : 1;
    }
  else
    {
      emacs_event.kind = MOUSE_CLICK_EVENT;
      emacs_event.code = mouse_button_to_code (mouse.button);

      if (mouse.type == MouseEventType::Press)
	{
	  emacs_event.modifiers |= down_modifier;
	}
      else if (mouse.type == MouseEventType::Release)
	{
	  emacs_event.modifiers |= click_modifier;
	}
      else if (mouse.type == MouseEventType::Drag)
	{
	  emacs_event.modifiers |= drag_modifier;
	}
    }

  emacs_event.modifiers |= modifiers_to_emacs (mouse.modifiers);

  return emacs_event;
}

unsigned
EmacsInputAdapter::modifiers_to_emacs (KeyModifier mods)
{
  unsigned emacs_mods = 0;

  if (has_modifier (mods, KeyModifier::Shift))
    emacs_mods |= shift_modifier;

  if (has_modifier (mods, KeyModifier::Ctrl))
    emacs_mods |= ctrl_modifier;

  if (has_modifier (mods, KeyModifier::Alt))
    emacs_mods |= alt_modifier;

  if (has_modifier (mods, KeyModifier::Meta))
    emacs_mods |= meta_modifier;

  return emacs_mods;
}

unsigned
EmacsInputAdapter::keycode_to_keysym (KeyCode key)
{
  switch (key)
    {
    case KeyCode::ArrowUp:
      return 0xFF52;
    case KeyCode::ArrowDown:
      return 0xFF54;
    case KeyCode::ArrowLeft:
      return 0xFF51;
    case KeyCode::ArrowRight:
      return 0xFF53;

    case KeyCode::Home:
      return 0xFF50;
    case KeyCode::End:
      return 0xFF57;
    case KeyCode::PageUp:
      return 0xFF55;
    case KeyCode::PageDown:
      return 0xFF56;
    case KeyCode::Insert:
      return 0xFF63;
    case KeyCode::Delete:
      return 0xFFFF;

    case KeyCode::F1:
      return 0xFFBE;
    case KeyCode::F2:
      return 0xFFBF;
    case KeyCode::F3:
      return 0xFFC0;
    case KeyCode::F4:
      return 0xFFC1;
    case KeyCode::F5:
      return 0xFFC2;
    case KeyCode::F6:
      return 0xFFC3;
    case KeyCode::F7:
      return 0xFFC4;
    case KeyCode::F8:
      return 0xFFC5;
    case KeyCode::F9:
      return 0xFFC6;
    case KeyCode::F10:
      return 0xFFC7;
    case KeyCode::F11:
      return 0xFFC8;
    case KeyCode::F12:
      return 0xFFC9;

    case KeyCode::Tab:
      return 9;
    case KeyCode::Enter:
      return 13;
    case KeyCode::Escape:
      return 27;
    case KeyCode::Backspace:
      return 127;

    default:
      return 0;
    }
}

unsigned
EmacsInputAdapter::mouse_button_to_code (MouseButton button)
{
  switch (button)
    {
    case MouseButton::Left:
      return 0;
    case MouseButton::Middle:
      return 1;
    case MouseButton::Right:
      return 2;
    default:
      return 0;
    }
}

bool
EmacsInputAdapter::is_wheel_event (MouseButton button)
{
  return button == MouseButton::WheelUp
	 || button == MouseButton::WheelDown;
}

}
}

extern "C"
{
  void *emacs_cxx_create_input_adapter (void)
  {
    return new emacs::tui::EmacsInputAdapter ();
  }

  void emacs_cxx_destroy_input_adapter (void *adapter_ptr)
  {
    delete static_cast<emacs::tui::EmacsInputAdapter *> (adapter_ptr);
  }

  void emacs_cxx_convert_input_event (void *adapter_ptr,
				      void *cpp_event_ptr,
				      struct input_event *emacs_event)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsInputAdapter *> (adapter_ptr);
    auto *cpp_event
      = static_cast<emacs::tui::InputEvent *> (cpp_event_ptr);

    *emacs_event = adapter->to_emacs_event (*cpp_event);
  }
}
