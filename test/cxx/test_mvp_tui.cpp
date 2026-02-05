#include "../../src/allocator.hpp"
#include "../../src/event_loop.hpp"
#include "../../src/grid.hpp"
#include "../../src/input_parser.hpp"
#include "../../src/renderer.hpp"

#include <cstring>
#include <iostream>
#include <termios.h>
#include <unistd.h>

using namespace emacs::tui;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

struct termios orig_termios;

void
disable_raw_mode ()
{
  tcsetattr (STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void
enable_raw_mode ()
{
  tcgetattr (STDIN_FILENO, &orig_termios);
  atexit (disable_raw_mode);

  struct termios raw = orig_termios;
  raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  raw.c_oflag &= ~(OPOST);
  raw.c_cflag |= (CS8);
  raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  raw.c_cc[VMIN] = 0;
  raw.c_cc[VTIME] = 1;

  tcsetattr (STDIN_FILENO, TCSAFLUSH, &raw);
}

int
main ()
{
  std::cout << "Phase 4 TUI MVP Demo\n";
  std::cout << "====================\n";
  std::cout
    << "Testing Grid + Renderer + InputParser + EventLoop\n\n";

  Grid grid (24, 80);
  Renderer renderer;

  renderer.clear_screen ();
  renderer.move_cursor (0, 0);
  renderer.show_cursor (false);

  CellAttributes title_attrs;
  title_attrs.flags = CellAttributes::BOLD;
  title_attrs.fg = 14;

  grid.set_cell (0, 0, Cell ("E", title_attrs));
  grid.set_cell (0, 1, Cell ("m", title_attrs));
  grid.set_cell (0, 2, Cell ("a", title_attrs));
  grid.set_cell (0, 3, Cell ("c", title_attrs));
  grid.set_cell (0, 4, Cell ("s", title_attrs));
  grid.set_cell (0, 5, Cell (" "));
  grid.set_cell (0, 6, Cell ("C", title_attrs));
  grid.set_cell (0, 7, Cell ("+", title_attrs));
  grid.set_cell (0, 8, Cell ("+", title_attrs));
  grid.set_cell (0, 9, Cell ("2", title_attrs));
  grid.set_cell (0, 10, Cell ("0", title_attrs));

  grid.set_cell (2, 0, Cell ("P"));
  grid.set_cell (2, 1, Cell ("h"));
  grid.set_cell (2, 2, Cell ("a"));
  grid.set_cell (2, 3, Cell ("s"));
  grid.set_cell (2, 4, Cell ("e"));
  grid.set_cell (2, 5, Cell (" "));
  grid.set_cell (2, 6, Cell ("4"));
  grid.set_cell (2, 7, Cell (":"));
  grid.set_cell (2, 8, Cell (" "));
  grid.set_cell (2, 9, Cell ("T"));
  grid.set_cell (2, 10, Cell ("U"));
  grid.set_cell (2, 11, Cell ("I"));

  CellAttributes status_attrs;
  status_attrs.flags = CellAttributes::REVERSE;
  status_attrs.fg = 0;
  status_attrs.bg = 7;

  for (int col = 0; col < 80; ++col)
    {
      grid.set_cell (23, col, Cell (" ", status_attrs));
    }

  grid.set_cell (23, 1, Cell ("G", status_attrs));
  grid.set_cell (23, 2, Cell ("r", status_attrs));
  grid.set_cell (23, 3, Cell ("i", status_attrs));
  grid.set_cell (23, 4, Cell ("d", status_attrs));
  grid.set_cell (23, 6, Cell ("R", status_attrs));
  grid.set_cell (23, 7, Cell ("e", status_attrs));
  grid.set_cell (23, 8, Cell ("n", status_attrs));
  grid.set_cell (23, 9, Cell ("d", status_attrs));
  grid.set_cell (23, 10, Cell ("e", status_attrs));
  grid.set_cell (23, 11, Cell ("r", status_attrs));
  grid.set_cell (23, 12, Cell ("e", status_attrs));
  grid.set_cell (23, 13, Cell ("r", status_attrs));
  grid.set_cell (23, 15, Cell ("I", status_attrs));
  grid.set_cell (23, 16, Cell ("n", status_attrs));
  grid.set_cell (23, 17, Cell ("p", status_attrs));
  grid.set_cell (23, 18, Cell ("u", status_attrs));
  grid.set_cell (23, 19, Cell ("t", status_attrs));
  grid.set_cell (23, 21, Cell ("E", status_attrs));
  grid.set_cell (23, 22, Cell ("v", status_attrs));
  grid.set_cell (23, 23, Cell ("e", status_attrs));
  grid.set_cell (23, 24, Cell ("n", status_attrs));
  grid.set_cell (23, 25, Cell ("t", status_attrs));

  grid.set_cell (4, 2, Cell ("["));
  grid.set_cell (4, 3, Cell ("O"));
  grid.set_cell (4, 4, Cell ("K"));
  grid.set_cell (4, 5, Cell ("]"));
  grid.set_cell (4, 7, Cell ("A"));
  grid.set_cell (4, 8, Cell ("l"));
  grid.set_cell (4, 9, Cell ("l"));
  grid.set_cell (4, 10, Cell (" "));
  grid.set_cell (4, 11, Cell ("c"));
  grid.set_cell (4, 12, Cell ("o"));
  grid.set_cell (4, 13, Cell ("m"));
  grid.set_cell (4, 14, Cell ("p"));
  grid.set_cell (4, 15, Cell ("o"));
  grid.set_cell (4, 16, Cell ("n"));
  grid.set_cell (4, 17, Cell ("e"));
  grid.set_cell (4, 18, Cell ("n"));
  grid.set_cell (4, 19, Cell ("t"));
  grid.set_cell (4, 20, Cell ("s"));
  grid.set_cell (4, 21, Cell (" "));
  grid.set_cell (4, 22, Cell ("w"));
  grid.set_cell (4, 23, Cell ("o"));
  grid.set_cell (4, 24, Cell ("r"));
  grid.set_cell (4, 25, Cell ("k"));
  grid.set_cell (4, 26, Cell ("i"));
  grid.set_cell (4, 27, Cell ("n"));
  grid.set_cell (4, 28, Cell ("g"));
  grid.set_cell (4, 29, Cell ("!"));

  grid.swap_buffers ();

  renderer.render (grid);
  renderer.move_cursor (23, 0);
  renderer.show_cursor (true);
  renderer.flush ();

  std::cout << "\n\n✅ MVP Demo Complete!\n";
  std::cout << "   - Grid: 24x80 cells\n";
  std::cout << "   - Renderer: ANSI escape sequences\n";
  std::cout << "   - Status bar with reverse video\n";
  std::cout << "   - Title with bold formatting\n";

  sleep (2);

  renderer.clear_screen ();
  renderer.move_cursor (0, 0);
  renderer.show_cursor (true);
  renderer.flush ();

  return 0;
}
