#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string_view>

#include "containers.hpp"

namespace emacs
{

class EmacsBuffer;

using CompletionFn
  = std::function<gc_vector_t<gc_string> (std::string_view input)>;

using MinibufferCallback
  = std::function<void (std::string_view input)>;

enum class MinibufferState : uint8_t
{
  Inactive,
  Reading,
  Complete,
  Cancelled,
};

class Minibuffer
{
public:
  static Minibuffer &instance () noexcept;

  void read (std::string_view prompt,
	     MinibufferCallback callback = nullptr,
	     CompletionFn completion_fn = nullptr);

  void insert_char (char c);
  void delete_backward ();
  void delete_forward ();

  void move_forward ();
  void move_backward ();
  void move_beginning ();
  void move_end ();

  void commit ();
  void cancel ();
  void complete ();

  [[nodiscard]] MinibufferState state () const noexcept;
  [[nodiscard]] const gc_string &prompt () const noexcept;
  [[nodiscard]] gc_string input () const;
  [[nodiscard]] gc_string display_text () const;
  [[nodiscard]] size_t cursor_position () const noexcept;
  [[nodiscard]] const gc_string &result () const noexcept;
  [[nodiscard]] const gc_vector_t<gc_string> &
  completions () const noexcept;
  [[nodiscard]] int completion_index () const noexcept;

  void next_completion ();
  void prev_completion ();

  [[nodiscard]] const gc_string &echo_message () const noexcept;
  void set_echo_message (std::string_view msg);
  void clear_echo_message () noexcept;

  void reset () noexcept;
  [[nodiscard]] bool is_active () const noexcept;

private:
  Minibuffer ();

  void clear_completions () noexcept;

  gc_string prompt_;
  gc_string input_buffer_;
  size_t cursor_pos_ = 0;
  MinibufferState state_ = MinibufferState::Inactive;
  gc_string result_;
  MinibufferCallback callback_;
  CompletionFn completion_fn_;
  gc_vector_t<gc_string> completions_;
  int completion_index_ = -1;
  gc_string echo_message_;
};

void minibuffer_execute_command ();

} // namespace emacs

extern "C"
{
  int emacs_cxx_minibuffer_read (const char *prompt);
  int emacs_cxx_minibuffer_insert (char c);
  int emacs_cxx_minibuffer_commit ();
  int emacs_cxx_minibuffer_cancel ();
  int emacs_cxx_minibuffer_is_active ();
}
