// test/cxx/demo_input_conversion.cpp
// Visual demonstration of InputAdapter converting events

#include <iomanip>
#include <iostream>
#include "../../src/containers.hpp"
#include "../../src/emacs_input_adapter.hpp"

using namespace emacs::tui;
using emacs::gc_string;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

const char *
event_kind_name (int kind)
{
  switch (kind)
    {
    case ASCII_KEYSTROKE_EVENT:
      return "ASCII_KEYSTROKE";
    case MULTIBYTE_CHAR_KEYSTROKE_EVENT:
      return "MULTIBYTE_CHAR";
    case NON_ASCII_KEYSTROKE_EVENT:
      return "NON_ASCII_KEY";
    case MOUSE_CLICK_EVENT:
      return "MOUSE_CLICK";
    case WHEEL_EVENT:
      return "WHEEL";
    default:
      return "UNKNOWN";
    }
}

gc_string
modifiers_to_string (unsigned mods)
{
  gc_string result;
  if (mods & ctrl_modifier)
    result += "Ctrl+";
  if (mods & alt_modifier)
    result += "Alt+";
  if (mods & shift_modifier)
    result += "Shift+";
  if (mods & meta_modifier)
    result += "Meta+";
  if (mods & down_modifier)
    result += "Down ";
  if (mods & click_modifier)
    result += "Click ";
  if (mods & drag_modifier)
    result += "Drag ";

  if (result.empty ())
    return "(none)";
  if (result.back () == '+')
    result.pop_back ();
  return result;
}

void
demo_key_event (const char *description, KeyCode key,
		KeyModifier mods, uint32_t unicode)
{
  std::cout << "\n🔹 " << description << "\n";
  std::cout << "   C++ Input: KeyCode=" << static_cast<int> (key)
	    << " Unicode=" << unicode << " Modifiers="
	    << modifiers_to_string (
		 EmacsInputAdapter::modifiers_to_emacs (mods))
		 .c_str ()
	    << "\n";

  EmacsInputAdapter adapter;
  KeyEvent cpp_key (key, mods, unicode);
  InputEvent cpp_event = InputEvent::make_key (cpp_key);
  struct input_event emacs_event = adapter.to_emacs_event (cpp_event);

  std::cout << "   Emacs Event: kind="
	    << event_kind_name (emacs_event.kind) << " code=0x"
	    << std::hex << emacs_event.code << std::dec
	    << " modifiers="
	    << modifiers_to_string (emacs_event.modifiers).c_str ()
	    << "\n";
}

void
demo_mouse_event (const char *description, MouseButton button,
		  MouseEventType type)
{
  std::cout << "\n🔹 " << description << "\n";

  EmacsInputAdapter adapter;
  MouseEvent cpp_mouse (button, type, 10, 20);
  InputEvent cpp_event = InputEvent::make_mouse (cpp_mouse);
  struct input_event emacs_event = adapter.to_emacs_event (cpp_event);

  std::cout << "   C++ Input: Button=" << static_cast<int> (button)
	    << " Type=" << static_cast<int> (type) << "\n";
  std::cout << "   Emacs Event: kind="
	    << event_kind_name (emacs_event.kind)
	    << " code=" << emacs_event.code << " modifiers="
	    << modifiers_to_string (emacs_event.modifiers).c_str ()
	    << "\n";
}

int
main ()
{
  std::cout
    << "═══════════════════════════════════════════════════\n";
  std::cout << "   Emacs Input Adapter - Event Conversion Demo\n";
  std::cout
    << "═══════════════════════════════════════════════════\n";

  std::cout << "\n📝 KEYBOARD EVENTS:\n";

  demo_key_event ("Press 'a'", KeyCode::Unknown, KeyModifier::None,
		  'a');

  demo_key_event ("Press Ctrl+C", KeyCode::Unknown, KeyModifier::Ctrl,
		  'c');

  demo_key_event ("Press Ctrl+Alt+X", KeyCode::Unknown,
		  KeyModifier::Ctrl | KeyModifier::Alt, 'x');

  demo_key_event ("Press Arrow Up", KeyCode::ArrowUp,
		  KeyModifier::None, 0);

  demo_key_event ("Press F1", KeyCode::F1, KeyModifier::None, 0);

  demo_key_event ("Press Enter", KeyCode::Enter, KeyModifier::None,
		  13);

  demo_key_event ("Press Unicode '中' (0x4E2D)", KeyCode::Unknown,
		  KeyModifier::None, 0x4E2D);

  std::cout << "\n🖱️  MOUSE EVENTS:\n";

  demo_mouse_event ("Left Click", MouseButton::Left,
		    MouseEventType::Press);

  demo_mouse_event ("Left Release", MouseButton::Left,
		    MouseEventType::Release);

  demo_mouse_event ("Mouse Drag", MouseButton::Left,
		    MouseEventType::Drag);

  demo_mouse_event ("Scroll Up", MouseButton::WheelUp,
		    MouseEventType::Scroll);

  demo_mouse_event ("Scroll Down", MouseButton::WheelDown,
		    MouseEventType::Scroll);

  std::cout
    << "\n═══════════════════════════════════════════════════\n";
  std::cout << "✅ Demo complete!\n";
  std::cout
    << "═══════════════════════════════════════════════════\n";

  return 0;
}
