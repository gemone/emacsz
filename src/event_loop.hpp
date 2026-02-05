#pragma once

#include <functional>
#include <optional>
#include "allocator.hpp"
#include "containers.hpp"
#include "input_parser.hpp"

namespace emacs
{
namespace tui
{

enum class EventLoopStatus
{
  Running,
  Stopped,
  Error,
};

using EventCallback = std::function<void (const InputEvent &)>;
using TimerCallback = std::function<void ()>;

class EventLoop
{
public:
  EventLoop ();
  ~EventLoop ();

  EventLoop (const EventLoop &) = delete;
  EventLoop &operator= (const EventLoop &) = delete;

  EventLoop (EventLoop &&) = delete;
  EventLoop &operator= (EventLoop &&) = delete;

  bool start ();
  void stop ();
  void run_once ();

  void set_event_callback (EventCallback callback);
  void set_timer (int timeout_ms, TimerCallback callback);

  EventLoopStatus status () const noexcept { return status_; }
  bool is_running () const noexcept
  {
    return status_ == EventLoopStatus::Running;
  }

private:
  void process_stdin ();
  void handle_input (const char *data, size_t len);

  EventLoopStatus status_;
  EventCallback event_callback_;
  InputParser parser_;
  bool stop_requested_;
};

}
}
