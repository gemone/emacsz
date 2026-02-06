// test/cxx/test_event_loop_adapter_standalone.cpp
// Standalone tests for EmacsEventLoopAdapter (Phase 5.4)

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_event_loop_adapter.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

static struct input_event
make_ascii_event (unsigned code)
{
  struct input_event event{};
  event.kind = ASCII_KEYSTROKE_EVENT;
  event.code = code;
  event.modifiers = 0;
  event.timestamp = 0;
  event.frame_or_window = nullptr;
  return event;
}

void
test_create_destroy ()
{
  printf ("Testing create/destroy...\n");

  EmacsEventLoopAdapter *adapter = new EmacsEventLoopAdapter ();
  assert (adapter != nullptr);
  delete adapter;

  printf ("✓ Create/destroy test passed\n");
}

void
test_init_shutdown ()
{
  printf ("Testing init/shutdown (manual mode)...\n");

  EmacsEventLoopAdapter adapter;
  assert (adapter.is_active () == false);
  assert (adapter.pending_count () == 0);
  assert (adapter.total_events_processed () == 0);

  adapter.shutdown ();
  assert (adapter.is_active () == false);

  printf ("✓ Init/shutdown test passed\n");
}

void
test_inject_event ()
{
  printf ("Testing inject_event...\n");

  EmacsEventLoopAdapter adapter;
  struct input_event event = make_ascii_event ('a');
  adapter.inject_event (event);

  assert (adapter.pending_count () == 1);

  printf ("✓ Inject event test passed\n");
}

void
test_inject_input_event ()
{
  printf ("Testing inject_input_event...\n");

  EmacsEventLoopAdapter adapter;
  KeyEvent key_x (KeyCode::Unknown, KeyModifier::None, 'x');
  InputEvent input_x = InputEvent::make_key (key_x);

  adapter.inject_input_event (input_x);
  assert (adapter.pending_count () == 1);

  auto event = adapter.next_event ();
  assert (event.has_value ());
  assert (event->kind == ASCII_KEYSTROKE_EVENT);
  assert (event->code == 'x');

  printf ("✓ Inject input event test passed\n");
}

void
test_next_event ()
{
  printf ("Testing next_event FIFO...\n");

  EmacsEventLoopAdapter adapter;
  adapter.inject_event (make_ascii_event ('a'));
  adapter.inject_event (make_ascii_event ('b'));

  auto first = adapter.next_event ();
  auto second = adapter.next_event ();

  assert (first.has_value ());
  assert (second.has_value ());
  assert (first->code == 'a');
  assert (second->code == 'b');

  printf ("✓ Next event FIFO test passed\n");
}

void
test_peek_event ()
{
  printf ("Testing peek_event...\n");

  EmacsEventLoopAdapter adapter;
  adapter.inject_event (make_ascii_event ('p'));

  auto peeked = adapter.peek_event ();
  assert (peeked.has_value ());
  assert (peeked->code == 'p');
  assert (adapter.pending_count () == 1);

  auto next = adapter.next_event ();
  assert (next.has_value ());
  assert (next->code == 'p');

  printf ("✓ Peek event test passed\n");
}

void
test_empty_next_event ()
{
  printf ("Testing next_event on empty queue...\n");

  EmacsEventLoopAdapter adapter;
  auto event = adapter.next_event ();
  assert (!event.has_value ());

  printf ("✓ Empty next_event test passed\n");
}

void
test_empty_peek_event ()
{
  printf ("Testing peek_event on empty queue...\n");

  EmacsEventLoopAdapter adapter;
  auto event = adapter.peek_event ();
  assert (!event.has_value ());

  printf ("✓ Empty peek_event test passed\n");
}

void
test_set_current_frame ()
{
  printf ("Testing set_current_frame...\n");

  EmacsEventLoopAdapter adapter;
  void *frame = reinterpret_cast<void *> (0x1234);
  adapter.set_current_frame (frame);
  assert (adapter.current_frame () == frame);

  printf ("✓ Set current frame test passed\n");
}

void
test_frame_stamping ()
{
  printf ("Testing frame stamping...\n");

  EmacsEventLoopAdapter adapter;
  void *frame = reinterpret_cast<void *> (0xBEEF);
  adapter.set_current_frame (frame);

  adapter.inject_event (make_ascii_event ('z'));
  auto event = adapter.next_event ();
  assert (event.has_value ());
  assert (event->frame_or_window == frame);

  printf ("✓ Frame stamping test passed\n");
}

void
test_buffer_overflow ()
{
  printf ("Testing keyboard buffer overflow...\n");

  EmacsEventLoopAdapter adapter;
  const size_t max_size = 4096;

  for (size_t i = 0; i < max_size + 1; ++i)
    {
      adapter.inject_event (
	make_ascii_event (static_cast<unsigned> (i)));
    }

  assert (adapter.pending_count () == max_size);

  auto first = adapter.next_event ();
  assert (first.has_value ());
  assert (first->code == 1);

  printf ("✓ Buffer overflow test passed\n");
}

void
test_c_api ()
{
  printf ("Testing C API...\n");

  void *adapter = emacs_cxx_create_event_loop_adapter ();
  assert (adapter != nullptr);

  void *frame = reinterpret_cast<void *> (0xCAFE);
  emacs_cxx_set_frame (adapter, frame);

  struct input_event event = make_ascii_event ('q');
  emacs_cxx_inject_event (adapter, &event);
  assert (emacs_cxx_pending_count (adapter) == 1);

  struct input_event peeked{};
  int peek_ok = emacs_cxx_peek_event (adapter, &peeked);
  assert (peek_ok == 1);
  assert (peeked.code == 'q');
  assert (emacs_cxx_pending_count (adapter) == 1);

  struct input_event next{};
  int next_ok = emacs_cxx_next_event (adapter, &next);
  assert (next_ok == 1);
  assert (next.code == 'q');
  assert (next.frame_or_window == frame);
  assert (emacs_cxx_pending_count (adapter) == 0);

  emacs_cxx_destroy_event_loop_adapter (adapter);

  printf ("✓ C API test passed\n");
}

int
main ()
{
  printf ("Running EmacsEventLoopAdapter tests...\n\n");

  test_create_destroy ();
  test_init_shutdown ();
  test_inject_event ();
  test_inject_input_event ();
  test_next_event ();
  test_peek_event ();
  test_empty_next_event ();
  test_empty_peek_event ();
  test_set_current_frame ();
  test_frame_stamping ();
  test_buffer_overflow ();
  test_c_api ();

  printf ("\n✅ All EmacsEventLoopAdapter tests passed!\n");
  return 0;
}
