// test/cxx/test_input_adapter_standalone.cpp
// Unit tests for EmacsInputAdapter

#include <cassert>
#include <iostream>
#include "../../src/emacs_input_adapter.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

void
test_modifier_conversion ()
{
  EmacsInputAdapter adapter;

  KeyModifier none = KeyModifier::None;
  assert (EmacsInputAdapter::modifiers_to_emacs (none) == 0);

  KeyModifier shift = KeyModifier::Shift;
  assert (
    (EmacsInputAdapter::modifiers_to_emacs (shift) & shift_modifier)
    != 0);

  KeyModifier ctrl = KeyModifier::Ctrl;
  assert (
    (EmacsInputAdapter::modifiers_to_emacs (ctrl) & ctrl_modifier)
    != 0);

  KeyModifier alt = KeyModifier::Alt;
  assert ((EmacsInputAdapter::modifiers_to_emacs (alt) & alt_modifier)
	  != 0);

  KeyModifier meta = KeyModifier::Meta;
  assert (
    (EmacsInputAdapter::modifiers_to_emacs (meta) & meta_modifier)
    != 0);

  KeyModifier combo = KeyModifier::Ctrl | KeyModifier::Alt;
  unsigned emacs_combo
    = EmacsInputAdapter::modifiers_to_emacs (combo);
  assert ((emacs_combo & ctrl_modifier) != 0);
  assert ((emacs_combo & alt_modifier) != 0);

  std::cout << "✓ Modifier conversion test passed\n";
}

void
test_keycode_to_keysym ()
{
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::ArrowUp)
	  == 0xFF52);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::ArrowDown)
	  == 0xFF54);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::ArrowLeft)
	  == 0xFF51);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::ArrowRight)
	  == 0xFF53);

  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::Home)
	  == 0xFF50);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::End)
	  == 0xFF57);

  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::F1)
	  == 0xFFBE);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::F12)
	  == 0xFFC9);

  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::Tab) == 9);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::Enter)
	  == 13);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::Escape)
	  == 27);
  assert (EmacsInputAdapter::keycode_to_keysym (KeyCode::Backspace)
	  == 127);

  std::cout << "✓ Keycode to keysym conversion test passed\n";
}

void
test_mouse_button_conversion ()
{
  assert (EmacsInputAdapter::mouse_button_to_code (MouseButton::Left)
	  == 0);
  assert (
    EmacsInputAdapter::mouse_button_to_code (MouseButton::Middle)
    == 1);
  assert (EmacsInputAdapter::mouse_button_to_code (MouseButton::Right)
	  == 2);

  assert (EmacsInputAdapter::is_wheel_event (MouseButton::WheelUp));
  assert (EmacsInputAdapter::is_wheel_event (MouseButton::WheelDown));
  assert (!EmacsInputAdapter::is_wheel_event (MouseButton::Left));

  std::cout << "✓ Mouse button conversion test passed\n";
}

void
test_ascii_key_event ()
{
  EmacsInputAdapter adapter;

  KeyEvent key_a (KeyCode::Unknown, KeyModifier::None, 'a');
  InputEvent input_a = InputEvent::make_key (key_a);
  struct input_event emacs_a = adapter.to_emacs_event (input_a);

  assert (emacs_a.kind == ASCII_KEYSTROKE_EVENT);
  assert (emacs_a.code == 'a');
  assert (emacs_a.modifiers == 0);

  std::cout << "✓ ASCII key event test passed\n";
}

void
test_key_with_modifiers ()
{
  EmacsInputAdapter adapter;

  KeyEvent ctrl_c (KeyCode::Unknown, KeyModifier::Ctrl, 'c');
  InputEvent input_ctrl_c = InputEvent::make_key (ctrl_c);
  struct input_event emacs_ctrl_c
    = adapter.to_emacs_event (input_ctrl_c);

  assert (emacs_ctrl_c.kind == ASCII_KEYSTROKE_EVENT);
  assert (emacs_ctrl_c.code == 'c');
  assert ((emacs_ctrl_c.modifiers & ctrl_modifier) != 0);

  std::cout << "✓ Key with modifiers test passed\n";
}

void
test_special_key ()
{
  EmacsInputAdapter adapter;

  KeyEvent arrow_up (KeyCode::ArrowUp, KeyModifier::None, 0);
  InputEvent input_arrow = InputEvent::make_key (arrow_up);
  struct input_event emacs_arrow
    = adapter.to_emacs_event (input_arrow);

  assert (emacs_arrow.kind == NON_ASCII_KEYSTROKE_EVENT);
  assert (emacs_arrow.code == 0xFF52);

  std::cout << "✓ Special key event test passed\n";
}

void
test_mouse_click ()
{
  EmacsInputAdapter adapter;

  MouseEvent left_click (MouseButton::Left, MouseEventType::Press, 10,
			 20);
  InputEvent input_click = InputEvent::make_mouse (left_click);
  struct input_event emacs_click
    = adapter.to_emacs_event (input_click);

  assert (emacs_click.kind == MOUSE_CLICK_EVENT);
  assert (emacs_click.code == 0);
  assert ((emacs_click.modifiers & down_modifier) != 0);

  std::cout << "✓ Mouse click event test passed\n";
}

void
test_wheel_event ()
{
  EmacsInputAdapter adapter;

  MouseEvent wheel_up (MouseButton::WheelUp, MouseEventType::Scroll,
		       0, 0);
  InputEvent input_wheel = InputEvent::make_mouse (wheel_up);
  struct input_event emacs_wheel
    = adapter.to_emacs_event (input_wheel);

  assert (emacs_wheel.kind == WHEEL_EVENT);
  assert (emacs_wheel.code == 0);

  std::cout << "✓ Wheel event test passed\n";
}

void
test_multibyte_char ()
{
  EmacsInputAdapter adapter;

  KeyEvent unicode_char (KeyCode::Unknown, KeyModifier::None, 0x4E2D);
  InputEvent input_unicode = InputEvent::make_key (unicode_char);
  struct input_event emacs_unicode
    = adapter.to_emacs_event (input_unicode);

  assert (emacs_unicode.kind == MULTIBYTE_CHAR_KEYSTROKE_EVENT);
  assert (emacs_unicode.code == 0x4E2D);

  std::cout << "✓ Multibyte character event test passed\n";
}

void
test_c_api ()
{
  void *adapter = emacs_cxx_create_input_adapter ();
  assert (adapter != nullptr);

  KeyEvent key_x (KeyCode::Unknown, KeyModifier::None, 'x');
  InputEvent input_x = InputEvent::make_key (key_x);
  struct input_event emacs_x;

  emacs_cxx_convert_input_event (adapter, &input_x, &emacs_x);

  assert (emacs_x.kind == ASCII_KEYSTROKE_EVENT);
  assert (emacs_x.code == 'x');

  emacs_cxx_destroy_input_adapter (adapter);

  std::cout << "✓ C API test passed\n";
}

int
main ()
{
  std::cout << "Running EmacsInputAdapter tests...\n";

  test_modifier_conversion ();
  test_keycode_to_keysym ();
  test_mouse_button_conversion ();
  test_ascii_key_event ();
  test_key_with_modifiers ();
  test_special_key ();
  test_mouse_click ();
  test_wheel_event ();
  test_multibyte_char ();
  test_c_api ();

  std::cout << "\n✅ All EmacsInputAdapter tests passed!\n";
  return 0;
}
