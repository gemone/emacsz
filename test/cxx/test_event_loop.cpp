#include <cassert>
#include <iostream>
#include <vector>
#include "../../src/allocator.hpp"
#include "../../src/event_loop.hpp"

using namespace emacs::tui;

std::vector<InputEvent> captured_events;

void
test_event_callback (const InputEvent &event)
{
  captured_events.push_back (event);
}

void
test_construction ()
{
  EventLoop loop;
  assert (loop.status () == EventLoopStatus::Stopped);
  assert (!loop.is_running ());
  std::cout << "test_construction passed\n";
}

void
test_start_stop ()
{
  EventLoop loop;
  assert (loop.start ());
  assert (loop.is_running ());
  assert (loop.status () == EventLoopStatus::Running);

  loop.stop ();
  assert (!loop.is_running ());
  assert (loop.status () == EventLoopStatus::Stopped);

  std::cout << "test_start_stop passed\n";
}

void
test_callback_registration ()
{
  EventLoop loop;
  captured_events.clear ();

  loop.set_event_callback (test_event_callback);
  assert (captured_events.empty ());

  std::cout << "test_callback_registration passed\n";
}

void
test_run_once_when_stopped ()
{
  EventLoop loop;
  captured_events.clear ();

  loop.set_event_callback (test_event_callback);
  loop.run_once ();

  assert (captured_events.empty ());
  std::cout << "test_run_once_when_stopped passed\n";
}

void
test_stop_request ()
{
  EventLoop loop;
  assert (loop.start ());
  assert (loop.is_running ());

  loop.stop ();
  assert (!loop.is_running ());

  std::cout << "test_stop_request passed\n";
}

void
test_double_start ()
{
  EventLoop loop;
  assert (loop.start ());
  assert (loop.is_running ());

  assert (loop.start ());
  assert (loop.is_running ());

  loop.stop ();
  std::cout << "test_double_start passed\n";
}

void
test_double_stop ()
{
  EventLoop loop;
  assert (loop.start ());

  loop.stop ();
  assert (!loop.is_running ());

  loop.stop ();
  assert (!loop.is_running ());

  std::cout << "test_double_stop passed\n";
}

void
test_timer_stub ()
{
  EventLoop loop;
  bool timer_called = false;

  loop.set_timer (100, [&timer_called] () { timer_called = true; });

  assert (!timer_called);
  std::cout << "test_timer_stub passed\n";
}

int
main ()
{
  std::cout << "Running EventLoop tests...\n\n";

  test_construction ();
  test_start_stop ();
  test_callback_registration ();
  test_run_once_when_stopped ();
  test_stop_request ();
  test_double_start ();
  test_double_stop ();
  test_timer_stub ();

  std::cout << "\nAll EventLoop tests passed!\n";
  return 0;
}
