// test/cxx/demo_redisplay.cpp
// Demonstration of EmacsRedisplayAdapter rendering to Grid

#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_redisplay_adapter.hpp"
#include "../../src/emacs_window_adapter.hpp"

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
}

struct face
{
  unsigned long foreground;
  unsigned long background;
};

void
fill_glyphs_from_text (struct glyph *glyphs, size_t count,
		       const char *text)
{
  if (!glyphs || !text)
    {
      return;
    }

  for (size_t i = 0; i < count; ++i)
    {
      glyphs[i].ch = static_cast<int> (text[i]);
      glyphs[i].face_id = 0;
    }
}

int
main ()
{
  printf ("═══════════════════════════════════════════════════\n");
  printf ("   Emacs Redisplay Adapter - Rendering Demo\n");
  printf ("═══════════════════════════════════════════════════\n\n");

  EmacsRedisplayAdapter adapter;
  if (!adapter.init (24, 80))
    {
      printf ("Failed to initialize redisplay adapter\n");
      return 1;
    }

  face f{ 7, 0 };
  const char *message = "Hello, Emacs Redisplay!";
  struct glyph glyphs[23]{};
  fill_glyphs_from_text (glyphs, 23, message);

  adapter.write_glyphs (glyphs, &f, 23, 0, 0);
  adapter.render_mode_line (nullptr, "-- DEMO MODE --", 23);

  adapter.grid ().swap_buffers ();
  adapter.flush ();

  printf ("\nResizing grid to 30x100...\n");
  adapter.resize (30, 100);

  frame fstats{};
  adapter.redisplay_frame (&fstats);

  printf ("\nStats:\n");
  printf ("  redisplay_count: %zu\n", adapter.redisplay_count ());
  printf ("  cells_updated:   %zu\n", adapter.cells_updated ());

  printf ("\n═══════════════════════════════════════════════════\n");
  printf ("✅ Demo complete!\n");
  printf ("═══════════════════════════════════════════════════\n");

  return 0;
}
