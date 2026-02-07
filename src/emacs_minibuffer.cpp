#include "emacs_minibuffer.hpp"

#include <algorithm>

#include "emacs_command_registry.hpp"

namespace emacs
{

namespace
{

[[nodiscard]] gc_string
common_prefix (const gc_vector_t<gc_string> &items)
{
  if (items.empty ())
    return gc_string ();

  size_t prefix_len = items.front ().size ();
  for (const auto &item : items)
    {
      size_t limit = std::min (prefix_len, item.size ());
      size_t i = 0;
      for (; i < limit; ++i)
	{
	  if (item[i] != items.front ()[i])
	    break;
	}
      prefix_len = i;
      if (prefix_len == 0)
	break;
    }

  return items.front ().substr (0, prefix_len);
}

}

Minibuffer &
Minibuffer::instance () noexcept
{
  static Minibuffer minibuffer;
  return minibuffer;
}

Minibuffer::Minibuffer ()
    : prompt_ (), input_buffer_ (), cursor_pos_ (0),
      state_ (MinibufferState::Inactive), result_ (),
      callback_ (nullptr), completion_fn_ (nullptr), completions_ (),
      completion_index_ (-1), echo_message_ ()
{
}

void
Minibuffer::read (std::string_view prompt,
		  MinibufferCallback callback,
		  CompletionFn completion_fn)
{
  prompt_ = gc_string (prompt.data (), prompt.size ());
  input_buffer_.clear ();
  cursor_pos_ = 0;
  result_.clear ();
  callback_ = std::move (callback);
  completion_fn_ = std::move (completion_fn);
  clear_completions ();
  state_ = MinibufferState::Reading;
}

void
Minibuffer::insert_char (char c)
{
  if (state_ != MinibufferState::Reading)
    return;
  input_buffer_.insert (cursor_pos_, 1, c);
  ++cursor_pos_;
  clear_completions ();
}

void
Minibuffer::delete_backward ()
{
  if (state_ != MinibufferState::Reading)
    return;
  if (cursor_pos_ == 0)
    return;
  input_buffer_.erase (cursor_pos_ - 1, 1);
  --cursor_pos_;
  clear_completions ();
}

void
Minibuffer::delete_forward ()
{
  if (state_ != MinibufferState::Reading)
    return;
  if (cursor_pos_ >= input_buffer_.size ())
    return;
  input_buffer_.erase (cursor_pos_, 1);
  clear_completions ();
}

void
Minibuffer::move_forward ()
{
  if (state_ != MinibufferState::Reading)
    return;
  if (cursor_pos_ < input_buffer_.size ())
    ++cursor_pos_;
}

void
Minibuffer::move_backward ()
{
  if (state_ != MinibufferState::Reading)
    return;
  if (cursor_pos_ > 0)
    --cursor_pos_;
}

void
Minibuffer::move_beginning ()
{
  if (state_ != MinibufferState::Reading)
    return;
  cursor_pos_ = 0;
}

void
Minibuffer::move_end ()
{
  if (state_ != MinibufferState::Reading)
    return;
  cursor_pos_ = input_buffer_.size ();
}

void
Minibuffer::commit ()
{
  if (state_ != MinibufferState::Reading)
    return;
  state_ = MinibufferState::Complete;
  result_ = input_buffer_;
  if (callback_)
    callback_ (std::string_view (result_.data (), result_.size ()));
  state_ = MinibufferState::Inactive;
  callback_ = nullptr;
  completion_fn_ = nullptr;
  clear_completions ();
}

void
Minibuffer::cancel ()
{
  if (state_ == MinibufferState::Inactive)
    return;
  state_ = MinibufferState::Cancelled;
  reset ();
  state_ = MinibufferState::Inactive;
}

void
Minibuffer::complete ()
{
  if (state_ != MinibufferState::Reading)
    return;
  if (!completion_fn_)
    return;

  completions_ = completion_fn_ (
    std::string_view (input_buffer_.data (), input_buffer_.size ()));
  completion_index_ = completions_.empty () ? -1 : 0;

  if (completions_.empty ())
    return;

  if (completions_.size () == 1)
    {
      input_buffer_ = completions_.front ();
      cursor_pos_ = input_buffer_.size ();
      return;
    }

  gc_string prefix = common_prefix (completions_);
  if (!prefix.empty () && prefix.size () > input_buffer_.size ())
    {
      input_buffer_ = prefix;
      cursor_pos_ = input_buffer_.size ();
    }
}

[[nodiscard]] MinibufferState
Minibuffer::state () const noexcept
{
  return state_;
}

[[nodiscard]] const gc_string &
Minibuffer::prompt () const noexcept
{
  return prompt_;
}

[[nodiscard]] gc_string
Minibuffer::input () const
{
  return input_buffer_;
}

[[nodiscard]] gc_string
Minibuffer::display_text () const
{
  gc_string display = prompt_;
  display += input_buffer_;
  return display;
}

[[nodiscard]] size_t
Minibuffer::cursor_position () const noexcept
{
  return prompt_.size () + cursor_pos_;
}

[[nodiscard]] const gc_string &
Minibuffer::result () const noexcept
{
  return result_;
}

[[nodiscard]] const gc_vector_t<gc_string> &
Minibuffer::completions () const noexcept
{
  return completions_;
}

[[nodiscard]] int
Minibuffer::completion_index () const noexcept
{
  return completion_index_;
}

void
Minibuffer::next_completion ()
{
  if (completions_.empty ())
    return;
  completion_index_ = (completion_index_ + 1) % completions_.size ();
  input_buffer_ = completions_[completion_index_];
  cursor_pos_ = input_buffer_.size ();
}

void
Minibuffer::prev_completion ()
{
  if (completions_.empty ())
    return;
  completion_index_ = completion_index_ - 1;
  if (completion_index_ < 0)
    completion_index_ = static_cast<int> (completions_.size ()) - 1;
  input_buffer_ = completions_[completion_index_];
  cursor_pos_ = input_buffer_.size ();
}

[[nodiscard]] const gc_string &
Minibuffer::echo_message () const noexcept
{
  return echo_message_;
}

void
Minibuffer::set_echo_message (std::string_view msg)
{
  echo_message_ = gc_string (msg.data (), msg.size ());
}

void
Minibuffer::clear_echo_message () noexcept
{
  echo_message_.clear ();
}

void
Minibuffer::reset () noexcept
{
  prompt_.clear ();
  input_buffer_.clear ();
  cursor_pos_ = 0;
  result_.clear ();
  callback_ = nullptr;
  completion_fn_ = nullptr;
  clear_completions ();
}

[[nodiscard]] bool
Minibuffer::is_active () const noexcept
{
  return state_ == MinibufferState::Reading;
}

void
Minibuffer::clear_completions () noexcept
{
  completions_.clear ();
  completion_index_ = -1;
}

void
minibuffer_execute_command ()
{
  auto completion_fn = [] (std::string_view input)
    {
      gc_vector_t<gc_string> matches;
      auto entries
	= CommandRegistry::instance ().complete_prefix (input);
      matches.reserve (entries.size ());
      for (const auto *entry : entries)
	matches.push_back (entry->name);
      return matches;
    };

  auto callback = [] (std::string_view input)
    {
      CommandContext ctx;
      ctx.buffer = nullptr;
      ctx.prefix_argument = 0;
      ctx.has_prefix = false;
      ctx.raw_prefix = false;
      (void) CommandRegistry::instance ().execute (input, ctx);
    };

  Minibuffer::instance ().read ("M-x ", std::move (callback),
				std::move (completion_fn));
}

} // namespace emacs

extern "C"
{
  int emacs_cxx_minibuffer_read (const char *prompt)
  {
    if (!prompt)
      return -1;
    try
      {
	emacs::Minibuffer::instance ().read (prompt);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_minibuffer_insert (char c)
  {
    try
      {
	emacs::Minibuffer::instance ().insert_char (c);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_minibuffer_commit ()
  {
    try
      {
	emacs::Minibuffer::instance ().commit ();
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_minibuffer_cancel ()
  {
    try
      {
	emacs::Minibuffer::instance ().cancel ();
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_minibuffer_is_active ()
  {
    try
      {
	return emacs::Minibuffer::instance ().is_active () ? 1 : 0;
      }
    catch (...)
      {
	return 0;
      }
  }
}
