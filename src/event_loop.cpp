// src/event_loop.cpp
// Event loop for processing terminal input events

#include "event_loop.hpp"
#include <cstring>  // strerror()
#include <errno.h>  // errno
#include <fcntl.h>  // fcntl()
#include <unistd.h> // read()

namespace emacs
{
namespace tui
{

EventLoop::EventLoop ()
    : status_ (EventLoopStatus::Stopped), event_callback_ (nullptr),
      parser_ (), stop_requested_ (false)
{
}

EventLoop::~EventLoop () { stop (); }

bool
EventLoop::start ()
{
  if (status_ == EventLoopStatus::Running)
    {
      return true;
    }

  // Set stdin to non-blocking mode
  int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
  if (flags == -1)
    {
      status_ = EventLoopStatus::Error;
      return false;
    }

  if (fcntl (STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) == -1)
    {
      status_ = EventLoopStatus::Error;
      return false;
    }

  status_ = EventLoopStatus::Running;
  stop_requested_ = false;
  return true;
}

void
EventLoop::stop ()
{
  if (status_ == EventLoopStatus::Stopped)
    {
      return;
    }

  stop_requested_ = true;
  status_ = EventLoopStatus::Stopped;

  // Restore stdin to blocking mode
  int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
  if (flags != -1)
    {
      fcntl (STDIN_FILENO, F_SETFL, flags & ~O_NONBLOCK);
    }
}

void
EventLoop::run_once ()
{
  if (status_ != EventLoopStatus::Running)
    {
      return;
    }

  if (stop_requested_)
    {
      stop ();
      return;
    }

  process_stdin ();

  while (parser_.has_events ())
    {
      auto event = parser_.next_event ();
      if (event.has_value () && event_callback_)
	{
	  event_callback_ (event.value ());
	}
    }
}

void
EventLoop::set_event_callback (EventCallback callback)
{
  event_callback_ = callback;
}

void
EventLoop::set_timer (int timeout_ms, TimerCallback callback)
{
  // Timer support is stubbed for now
  // Full implementation would use libuv or timerfd
  // For Phase 4, we're focusing on input events
  (void) timeout_ms;
  (void) callback;
}

void
EventLoop::process_stdin ()
{
  char buffer[4096];
  ssize_t bytes_read;

  while ((bytes_read = read (STDIN_FILENO, buffer, sizeof (buffer)))
	 > 0)
    {
      handle_input (buffer, static_cast<size_t> (bytes_read));
    }

  // Check for errors (EAGAIN/EWOULDBLOCK is expected for non-blocking
  // I/O)
  if (bytes_read == -1 && errno != EAGAIN && errno != EWOULDBLOCK)
    {
      status_ = EventLoopStatus::Error;
    }

  // Check for errors (EAGAIN/EWOULDBLOCK is expected for non-blocking
  // I/O)
  if (bytes_read == -1 && errno != EAGAIN && errno != EWOULDBLOCK)
    {
      // Real error occurred
      status_ = EventLoopStatus::Error;
    }
}

void
EventLoop::handle_input (const char *data, size_t len)
{
  parser_.feed (std::string_view (data, len));
}

}
}
