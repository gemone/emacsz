#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <string_view>
#include <unistd.h>

extern "C"
{
  void *lisp_malloc (size_t s) { return std::malloc (s); }
  void lisp_free (void *p) { std::free (p); }
}

#include "../../src/containers.hpp"
#include "../../src/emacs_mouse_adapter.hpp"

using namespace emacs::tui;

struct face
{
  unsigned long foreground;
  unsigned long background;
};

static volatile std::sig_atomic_t g_stop = 0;

static void
handle_sigint (int)
{
  g_stop = 1;
}

static int
set_stdin_nonblocking (bool enable)
{
  int flags = fcntl (STDIN_FILENO, F_GETFL, 0);
  if (flags == -1)
    {
      return -1;
    }

  if (enable)
    {
      return fcntl (STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }

  return fcntl (STDIN_FILENO, F_SETFL, flags & ~O_NONBLOCK);
}

static void
enable_mouse_reporting ()
{
  std::printf ("\033[?1000h\033[?1002h\033[?1006h");
  std::fflush (stdout);
}

static void
disable_mouse_reporting ()
{
  std::printf ("\033[?1000l\033[?1002l\033[?1006l");
  std::fflush (stdout);
}

static void
draw_status (EmacsRedisplayAdapter &redisplay, window *w,
	     const char *text)
{
  int row = redisplay.frame_rows () - 1;
  redisplay.render_mode_line (w, text, row);
}

int
main ()
{
  std::signal (SIGINT, handle_sigint);

  if (set_stdin_nonblocking (true) != 0)
    {
      std::printf ("Failed to set stdin non-blocking\n");
      return 1;
    }

  EmacsRedisplayAdapter redisplay;
  if (!redisplay.init (24, 80))
    {
      std::printf ("Failed to initialize redisplay adapter\n");
      return 1;
    }

  InputParser parser;
  EmacsMouseAdapter mouse_adapter;

  struct glyph_row rows[1]{};
  struct glyph glyphs[1][80]{};
  struct glyph_matrix matrix{};
  rows[0].glyphs[TEXT_AREA] = glyphs[0];
  rows[0].used[TEXT_AREA] = 80;
  rows[0].enabled_p = true;
  matrix.rows = rows;
  matrix.nrows = 1;

  window w = {};
  w.total_cols = 80;
  w.total_lines = 24;
  w.left_col = 0;
  w.top_line = 0;
  w.start = reinterpret_cast<Lisp_Object> (0);
  w.pointm = reinterpret_cast<Lisp_Object> (0);
  w.current_matrix = &matrix;

  frame fr = {};
  fr.root_window = &w;
  fr.selected_window = &w;

  face f{ 7, 0 };
  emacs::gc_string status = "Ready";
  int cursor_row = 0;
  int cursor_col = 0;

  redisplay.clear_frame ();
  redisplay.render_mode_line (&w, "-- Phase 5 Demo --", 23);
  redisplay.flush ();

  enable_mouse_reporting ();

  while (!g_stop)
    {
      char buffer[256];
      size_t size = sizeof (buffer);
      ssize_t bytes = read (STDIN_FILENO, buffer, size);
      if (bytes > 0)
	{
	  parser.feed (
	    std::string_view (buffer, static_cast<size_t> (bytes)));
	}
      else if (bytes < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
	{
	  status = "Read error";
	}

      while (parser.has_events ())
	{
	  auto event = parser.next_event ();
	  if (!event.has_value ())
	    {
	      break;
	    }

	  if (event->type == InputEventType::Key)
	    {
	      uint32_t unicode = event->key.unicode;
	      if (unicode == 'q')
		{
		  g_stop = 1;
		  break;
		}
	      if (unicode == '\n')
		{
		  cursor_row = (cursor_row + 1) % 23;
		  cursor_col = 0;
		}
	      else if (unicode >= 32 && unicode < 127)
		{
		  struct glyph g{};
		  g.ch = static_cast<int> (unicode);
		  g.face_id = 0;
		  redisplay.write_glyphs (&g, &f, 1, cursor_row,
					  cursor_col);
		  cursor_col = (cursor_col + 1) % 80;
		}

	      status = "Key event";
	    }
	  else if (event->type == InputEventType::Mouse)
	    {
	      MouseEvent mouse = event->mouse;
	      struct input_event emacs_event
		= mouse_adapter.translate_mouse_event (mouse, &fr);
	      if (emacs_event.kind == MOUSE_CLICK_EVENT)
		{
		  cursor_row = mouse.row;
		  cursor_col = mouse.col;
		  status = "Mouse click";
		}
	      else if (emacs_event.kind == WHEEL_EVENT)
		{
		  status = "Mouse wheel";
		}
	      else
		{
		  status = "Mouse event";
		}
	    }
	}

      redisplay.set_cursor (cursor_row, cursor_col);
      draw_status (redisplay, &w, status.c_str ());
      redisplay.flush ();
      usleep (1000);
    }

  disable_mouse_reporting ();
  redisplay.shutdown ();
  set_stdin_nonblocking (false);

  return 0;
}
