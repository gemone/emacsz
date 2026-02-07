#pragma once

#include <cstdint>
#include <functional>
#include <string_view>

#include "emacs_command_registry.hpp"
#include "emacs_keymap.hpp"
#include "input_parser.hpp"

namespace emacs
{

class EmacsBuffer;

using PreCommandHook
  = std::function<void (std::string_view command_name)>;
using PostCommandHook
  = std::function<void (std::string_view command_name)>;

enum class DispatchResult : uint8_t
{
  Executed,
  Unbound,
  PrefixKey,
  Error,
  SelfInsert,
};

class CommandDispatcher
{
public:
  static CommandDispatcher &instance () noexcept;

  [[nodiscard]] DispatchResult dispatch (const tui::InputEvent &event,
					 EmacsBuffer *buffer);

  void set_current_buffer (EmacsBuffer *buffer) noexcept;
  [[nodiscard]] EmacsBuffer *current_buffer () const noexcept;

  void set_prefix_argument (int arg) noexcept;
  [[nodiscard]] int prefix_argument () const noexcept;
  [[nodiscard]] bool has_prefix_argument () const noexcept;
  void clear_prefix_argument () noexcept;

  [[nodiscard]] const KeySequence &pending_keys () const noexcept;
  void reset_key_sequence () noexcept;

  void set_pre_command_hook (PreCommandHook hook);
  void set_post_command_hook (PostCommandHook hook);

  [[nodiscard]] const gc_string &message () const noexcept;
  void clear_message () noexcept;

  [[nodiscard]] uint32_t last_inserted_char () const noexcept;

  void reset () noexcept;

private:
  CommandDispatcher () = default;

  [[nodiscard]] KeyStroke
  key_event_to_keystroke (const tui::KeyEvent &ke) const noexcept;

  [[nodiscard]] bool try_self_insert (const tui::KeyEvent &ke,
				      EmacsBuffer *buffer);

  [[nodiscard]] bool execute_command (std::string_view name,
				      EmacsBuffer *buffer);

  void update_message ();

  KeySequence pending_keys_;
  EmacsBuffer *current_buffer_ = nullptr;
  int prefix_argument_ = 1;
  bool has_prefix_ = false;
  bool raw_prefix_ = false;
  PreCommandHook pre_command_hook_;
  PostCommandHook post_command_hook_;
  gc_string message_;
  uint32_t last_char_ = 0;
};

} // namespace emacs

extern "C"
{
  int emacs_cxx_dispatch_key (int key_code, int modifiers,
			      unsigned int unicode, void *buffer_ptr);
  void emacs_cxx_dispatch_reset ();
}
