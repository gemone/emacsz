// src/emacs_input_adapter.hpp
// Adapter to convert C++ InputParser events to Emacs C input_event
// structures Phase 5.2: Input Integration

#pragma once

#include <cstdint>
#include "input_parser.hpp"

// Forward declarations for Emacs C structures
// Full definitions will be provided by including termhooks.h when
// building with Emacs
#ifndef EMACS_INPUT_STRUCTS_DEFINED

// Mock definitions for standalone compilation (testing without Emacs)
enum event_kind
{
  NO_EVENT = 0,
  ASCII_KEYSTROKE_EVENT,
  MULTIBYTE_CHAR_KEYSTROKE_EVENT,
  NON_ASCII_KEYSTROKE_EVENT,
  MOUSE_CLICK_EVENT,
  WHEEL_EVENT,
  HORIZ_WHEEL_EVENT,
};

// Simplified input_event structure matching Emacs layout
struct input_event
{
  int kind;	      // event_kind
  unsigned code;      // character, keysym, or mouse button
  unsigned modifiers; // modifier keys
  void *x;	      // Generic pointer (Lisp_Object in real Emacs)
  void *y;	      // Generic pointer (Lisp_Object in real Emacs)
  unsigned timestamp; // Time
  void *frame_or_window;
  void *arg;
  void *device;
};

// Emacs modifier bits
enum
{
  up_modifier = 1,
  down_modifier = 2,
  drag_modifier = 4,
  click_modifier = 8,
  double_modifier = 16,
  triple_modifier = 32,
  alt_modifier = 0x0400000,   // CHAR_ALT
  super_modifier = 0x0800000, // CHAR_SUPER
  hyper_modifier = 0x1000000, // CHAR_HYPER
  shift_modifier = 0x2000000, // CHAR_SHIFT
  ctrl_modifier = 0x4000000,  // CHAR_CTL
  meta_modifier = 0x8000000,  // CHAR_META
};

#endif // EMACS_INPUT_STRUCTS_DEFINED

namespace emacs
{
namespace tui
{

/**
 * @class EmacsInputAdapter
 * @brief Bridge between C++ InputParser and Emacs C keyboard events
 *
 * Converts modern C++ input events (InputEvent from input_parser.hpp)
 * into Emacs C structures (struct input_event from termhooks.h).
 *
 * **Responsibilities**:
 * - Map KeyEvent → ASCII_KEYSTROKE_EVENT or NON_ASCII_KEYSTROKE_EVENT
 * - Map MouseEvent → MOUSE_CLICK_EVENT or WHEEL_EVENT
 * - Convert key modifiers (Ctrl, Alt, Shift, Meta)
 * - Handle special keys (arrows, F-keys, navigation)
 * - Map mouse buttons and scroll events
 *
 * **Usage**:
 * @code
 *   EmacsInputAdapter adapter;
 *   InputEvent cpp_event = parser.next_event().value();
 *   struct input_event emacs_event =
 * adapter.to_emacs_event(cpp_event);
 *   kbd_buffer_store_event(&emacs_event);
 * @endcode
 */
class EmacsInputAdapter
{
public:
  EmacsInputAdapter () = default;
  ~EmacsInputAdapter () = default;

  // Non-copyable, non-movable (stateless utility class)
  EmacsInputAdapter (const EmacsInputAdapter &) = delete;
  EmacsInputAdapter &operator= (const EmacsInputAdapter &) = delete;

  /**
   * @brief Convert C++ InputEvent to Emacs input_event
   * @param event C++ input event from InputParser
   * @return Emacs input_event ready for kbd_buffer_store_event()
   */
  struct input_event to_emacs_event (const InputEvent &event);

  /**
   * @brief Convert C++ KeyModifier to Emacs modifier bits
   * @param mods C++ modifier flags
   * @return Emacs modifier bitfield
   */
  static unsigned modifiers_to_emacs (KeyModifier mods);

  /**
   * @brief Convert C++ KeyCode to Emacs keysym
   * @param key C++ keycode (special keys like arrows, F-keys)
   * @return Emacs keysym code (for NON_ASCII_KEYSTROKE_EVENT)
   */
  static unsigned keycode_to_keysym (KeyCode key);

  /**
   * @brief Convert C++ MouseButton to Emacs button code
   * @param button C++ mouse button
   * @return Emacs mouse button code (0 = left, 1 = middle, 2 = right)
   */
  static unsigned mouse_button_to_code (MouseButton button);

  /**
   * @brief Check if MouseEvent is a scroll wheel event
   * @param button Mouse button (WheelUp or WheelDown)
   * @return true if wheel event
   */
  static bool is_wheel_event (MouseButton button);

private:
  /**
   * @brief Convert KeyEvent to input_event
   */
  struct input_event key_event_to_emacs (const KeyEvent &key);

  /**
   * @brief Convert MouseEvent to input_event
   */
  struct input_event mouse_event_to_emacs (const MouseEvent &mouse);

  /**
   * @brief Initialize input_event to default state
   * @param event Event to initialize
   */
  static void init_event (struct input_event &event);
};

} // namespace tui
} // namespace emacs

// C API for Emacs C code to call C++ adapter
#ifdef __cplusplus
extern "C"
{
#endif

  /**
   * @brief Create EmacsInputAdapter instance
   * @return Opaque pointer to C++ adapter object
   */
  void *emacs_cxx_create_input_adapter (void);

  /**
   * @brief Destroy EmacsInputAdapter instance
   * @param adapter_ptr Pointer from emacs_cxx_create_input_adapter()
   */
  void emacs_cxx_destroy_input_adapter (void *adapter_ptr);

  /**
   * @brief Convert C++ InputEvent to Emacs input_event
   * @param adapter_ptr Adapter instance
   * @param cpp_event C++ InputEvent (from InputParser)
   * @param emacs_event Output: Emacs input_event
   */
  void
  emacs_cxx_convert_input_event (void *adapter_ptr, void *cpp_event,
				 struct input_event *emacs_event);

#ifdef __cplusplus
}
#endif
