#include <iostream>
#include "../../src/emacs_display_adapter.hpp"
#include "../../src/grid.hpp"
#include "../../src/renderer.hpp"

using namespace emacs;
using namespace tui;

struct face
{
  unsigned long foreground;
  unsigned long background;
};

struct glyph
{
  union
  {
    int ch;
  } u;
};

int
main ()
{
  std::cout << "\n=== Emacs Display Adapter Demo ===\n";
  std::cout << "Rendering 'Hello from Emacs!' using Grid + "
	       "DisplayAdapter\n\n";

  Grid grid (10, 50);
  EmacsDisplayAdapter adapter;
  Renderer renderer;

  adapter.render_text_simple (grid, 1, 5, "Hello from Emacs!");

  adapter.render_text_simple (grid, 3, 5,
			      "This demonstrates Phase 5.1:");
  adapter.render_text_simple (grid, 4, 5,
			      "- Emacs face -> Grid attributes");
  adapter.render_text_simple (grid, 5, 5,
			      "- Glyph rendering to Grid cells");
  adapter.render_text_simple (grid, 6, 5,
			      "- Text output via Renderer");

  struct face colored_face;
  colored_face.foreground = 10;
  colored_face.background = 0;

  struct glyph glyphs[]
    = { { { (int) 'C' } }, { { (int) 'o' } }, { { (int) 'l' } },
	{ { (int) 'o' } }, { { (int) 'r' } }, { { (int) 'e' } },
	{ { (int) 'd' } }, { { (int) '!' } } };

  for (int i = 0; i < 8; ++i)
    {
      adapter.render_glyph (grid, 8, 5 + i, &glyphs[i],
			    &colored_face);
    }

  grid.swap_buffers ();
  renderer.render (grid);
  renderer.flush ();

  std::cout << "\n\n\n";

  std::cout << "✅ Display adapter successfully rendered text!\n";
  std::cout << "Ready for Phase 5.2: Input Integration\n\n";

  return 0;
}
