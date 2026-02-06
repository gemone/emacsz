// test/cxx/demo_event_loop.cpp
// Demonstration of EmacsEventLoopAdapter manual event injection

#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_event_loop_adapter.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

static const char *
event_kind_name (int kind)
{
  switch (kind)
    {
    case ASCII_KEYSTROKE_EVENT:
      return "ASCII_KEYSTROKE";
    case MULTIBYTE_CHAR_KEYSTROKE_EVENT:
      return "MULTIBYTE_CHAR";
    case NON_ASCII_KEYSTROKE_EVENT:
      return "NON_ASCII_KEY";
    case MOUSE_CLICK_EVENT:
      return "MOUSE_CLICK";
    case WHEEL_EVENT:
      return "WHEEL";
    default:
      return "UNKNOWN";
    }
}

int
main ()
{
  printf ("═══════════════════════════════════════════════════\n");
  printf ("   Emacs Event Loop Adapter - Manual Injection Demo\n");
  printf ("═══════════════════════════════════════════════════\n\n");

  EmacsEventLoopAdapter adapter;

  void *frame = reinterpret_cast<void *> (0xDEADBEEF);
  adapter.set_current_frame (frame);

  const char *text = "Hello";
  printf ("Injecting events: %s\n\n", text);

  for (const char *p = text; *p; ++p)
    {
      KeyEvent key (KeyCode::Unknown, KeyModifier::None,
		    static_cast<uint32_t> (*p));
      InputEvent event = InputEvent::make_key (key);
      adapter.inject_input_event (event);
    }

  printf ("Draining %zu events...\n\n", adapter.pending_count ());

  while (adapter.pending_count () > 0)
    {
      auto event = adapter.next_event ();
      if (!event.has_value ())
	{
	  break;
	}

      printf ("  kind=%s code=0x%X frame=%p\n",
	      event_kind_name (event->kind), event->code,
	      event->frame_or_window);
    }

  printf ("\nTotal processed: %zu\n",
	  adapter.total_events_processed ());
  printf ("Frame stamped: %s\n",
	  adapter.current_frame () == frame ? "yes" : "no");

  printf ("\n═══════════════════════════════════════════════════\n");
  printf ("✅ Demo complete!\n");
  printf ("═══════════════════════════════════════════════════\n");

  return 0;
}
