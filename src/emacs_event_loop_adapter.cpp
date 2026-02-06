// src/emacs_event_loop_adapter.cpp
// Phase 5.4: Event Loop Integration

#include "emacs_event_loop_adapter.hpp"
#include <chrono>
#include <climits>
#include <cstdio>
#include <thread>

namespace emacs
{
namespace tui
{

EmacsEventLoopAdapter::EmacsEventLoopAdapter ()
    : event_loop_ (), input_adapter_ (), kbd_buffer_ (),
      current_frame_ (nullptr), total_events_processed_ (0),
      initialized_ (false)
{
}

EmacsEventLoopAdapter::~EmacsEventLoopAdapter () { shutdown (); }

bool
EmacsEventLoopAdapter::init () noexcept
{
  if (initialized_)
    {
      return true;
    }

  event_loop_.set_event_callback ([this] (const InputEvent &event)
				    { on_event (event); });

  if (!event_loop_.start ())
    {
      return false;
    }

  initialized_ = true;
  return true;
}

void
EmacsEventLoopAdapter::shutdown () noexcept
{
  if (!initialized_)
    {
      return;
    }

  event_loop_.stop ();
  kbd_buffer_.clear ();
  initialized_ = false;
}

int
EmacsEventLoopAdapter::process_events () noexcept
{
  if (!initialized_)
    {
      return 0;
    }

  size_t before = kbd_buffer_.size ();
  event_loop_.run_once ();
  size_t after = kbd_buffer_.size ();

  if (after < before)
    {
      return 0;
    }

  size_t diff = after - before;
  if (diff > static_cast<size_t> (INT_MAX))
    {
      return INT_MAX;
    }
  return static_cast<int> (diff);
}

int
EmacsEventLoopAdapter::wait_for_event (int timeout_ms) noexcept
{
  if (!initialized_)
    {
      return 0;
    }

  if (timeout_ms == 0)
    {
      return process_events ();
    }

  auto start = std::chrono::steady_clock::now ();

  while (true)
    {
      int processed = process_events ();
      if (processed > 0)
	{
	  return processed;
	}

      if (timeout_ms > 0)
	{
	  auto now = std::chrono::steady_clock::now ();
	  auto elapsed
	    = std::chrono::duration_cast<std::chrono::milliseconds> (
	      now - start);
	  if (elapsed.count () >= timeout_ms)
	    {
	      return 0;
	    }
	}

      std::this_thread::sleep_for (std::chrono::milliseconds (1));
    }
}

size_t
EmacsEventLoopAdapter::pending_count () const noexcept
{
  return kbd_buffer_.size ();
}

std::optional<struct input_event>
EmacsEventLoopAdapter::peek_event () const noexcept
{
  if (kbd_buffer_.empty ())
    {
      return std::nullopt;
    }

  return kbd_buffer_.front ();
}

std::optional<struct input_event>
EmacsEventLoopAdapter::next_event () noexcept
{
  if (kbd_buffer_.empty ())
    {
      return std::nullopt;
    }

  struct input_event event = kbd_buffer_.front ();
  kbd_buffer_.pop_front ();
  return event;
}

void
EmacsEventLoopAdapter::inject_event (const struct input_event &event)
{
  push_event (event);
}

void
EmacsEventLoopAdapter::inject_input_event (const InputEvent &event)
{
  struct input_event emacs_event
    = input_adapter_.to_emacs_event (event);
  push_event (emacs_event);
}

bool
EmacsEventLoopAdapter::is_active () const noexcept
{
  return initialized_ && event_loop_.is_running ();
}

void
EmacsEventLoopAdapter::set_current_frame (void *frame) noexcept
{
  current_frame_ = frame;
}

void *
EmacsEventLoopAdapter::current_frame () const noexcept
{
  return current_frame_;
}

size_t
EmacsEventLoopAdapter::total_events_processed () const noexcept
{
  return total_events_processed_;
}

void
EmacsEventLoopAdapter::on_event (const InputEvent &event) noexcept
{
  struct input_event emacs_event
    = input_adapter_.to_emacs_event (event);
  push_event (emacs_event);
}

void
EmacsEventLoopAdapter::push_event (struct input_event event) noexcept
{
  event.frame_or_window = current_frame_;

  if (kbd_buffer_.size () >= MAX_KBD_BUFFER_SIZE)
    {
      kbd_buffer_.pop_front ();
      std::fprintf (stderr,
		    "EmacsEventLoopAdapter: kbd_buffer overflow, "
		    "dropping oldest event\n");
    }

  kbd_buffer_.push_back (event);
  ++total_events_processed_;
}

} // namespace tui
} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_event_loop_adapter (void)
  {
    return new emacs::tui::EmacsEventLoopAdapter ();
  }

  void emacs_cxx_destroy_event_loop_adapter (void *adapter_ptr)
  {
    delete static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
  }

  int emacs_cxx_init_event_loop (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    return adapter->init () ? 1 : 0;
  }

  void emacs_cxx_shutdown_event_loop (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    adapter->shutdown ();
  }

  int emacs_cxx_process_events (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    return adapter->process_events ();
  }

  int emacs_cxx_wait_for_event (void *adapter_ptr, int timeout_ms)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    return adapter->wait_for_event (timeout_ms);
  }

  int emacs_cxx_next_event (void *adapter_ptr,
			    struct input_event *out_event)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    auto event = adapter->next_event ();
    if (!event.has_value ())
      {
	return 0;
      }

    if (out_event)
      {
	*out_event = event.value ();
      }
    return 1;
  }

  int emacs_cxx_peek_event (void *adapter_ptr,
			    struct input_event *out_event)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    auto event = adapter->peek_event ();
    if (!event.has_value ())
      {
	return 0;
      }

    if (out_event)
      {
	*out_event = event.value ();
      }
    return 1;
  }

  int emacs_cxx_pending_count (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    size_t count = adapter->pending_count ();
    if (count > static_cast<size_t> (INT_MAX))
      {
	return INT_MAX;
      }
    return static_cast<int> (count);
  }

  void emacs_cxx_inject_event (void *adapter_ptr,
			       struct input_event *event)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    if (!event)
      {
	return;
      }
    adapter->inject_event (*event);
  }

  void emacs_cxx_set_frame (void *adapter_ptr, void *frame)
  {
    auto *adapter = static_cast<emacs::tui::EmacsEventLoopAdapter *> (
      adapter_ptr);
    adapter->set_current_frame (frame);
  }
}
