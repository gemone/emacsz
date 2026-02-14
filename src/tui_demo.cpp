// src/tui_demo.cpp
#include <chrono>
#include <iostream>
#include <thread>

#include "termbox2_term.hpp"

int
main ()
{
  emacs::Termbox2Backend terminal;

  if (!terminal.init ())
    {
      std::cerr << "Failed to initialize termbox2 backend\n";
      return 1;
    }

  terminal.clear_frame ();
  terminal.set_cursor_position ({ 0, 0 });
  terminal.write_text ("Emacs TUI Demo - Press 'q' to quit");

  terminal.set_cursor_position ({ 2, 0 });
  terminal.write_text ("Terminal size: ");

  auto [height, width] = terminal.get_terminal_size ();
  std::string size_str
    = std::to_string (width) + "x" + std::to_string (height);
  terminal.write_text (size_str);

  terminal.set_cursor_position ({ 4, 0 });
  terminal.write_text ("Features:");
  terminal.set_cursor_position ({ 5, 2 });
  terminal.write_text ("- Colors: ");
  terminal.write_text (terminal.supports_colors () ? "Yes" : "No");
  terminal.set_cursor_position ({ 6, 2 });
  terminal.write_text ("- Truecolor: ");
  terminal.write_text (terminal.supports_truecolor () ? "Yes" : "No");
  terminal.set_cursor_position ({ 7, 2 });
  terminal.write_text ("- Bracketed paste: ");
  terminal.write_text (terminal.supports_bracketed_paste () ? "Yes"
							    : "No");

  terminal.set_cursor_position ({ 9, 0 });
  terminal.write_text ("Type keys to see their codes (q = quit):");
  terminal.flush ();

  int row = 10;
  while (true)
    {
      emacs::InputEvent event = terminal.read_input ();

      if (event.type == emacs::InputEventType::Key)
	{
	  uint32_t key = (event.ch != 0) ? event.ch : event.key;

	  if (key == 'q' || key == 'Q')
	    break;

	  terminal.set_cursor_position ({ row, 2 });
	  std::string key_str = "Key: " + std::to_string (key);
	  if (key >= 32 && key < 127)
	    {
	      key_str += " ('"
			 + std::string (1, static_cast<char> (key))
			 + "')";
	    }
	  if (event.mod != 0)
	    {
	      key_str += " mod=" + std::to_string (event.mod);
	    }
	  terminal.write_text (key_str);
	  terminal.clear_end_of_line (
	    { row, static_cast<int> (key_str.size () + 2) });
	  terminal.flush ();

	  row++;
	  if (row >= height - 1)
	    {
	      row = 10;
	      for (int r = 10; r < height - 1; ++r)
		{
		  terminal.set_cursor_position ({ r, 0 });
		  terminal.clear_end_of_line ({ r, 0 });
		}
	      terminal.flush ();
	    }
	}
      else if (event.type == emacs::InputEventType::Resize)
	{
	  height = event.h;
	  width = event.w;
	  terminal.set_cursor_position ({ 2, 15 });
	  std::string new_size = std::to_string (width) + "x"
				 + std::to_string (height) + "  ";
	  terminal.write_text (new_size);
	  terminal.flush ();
	}
      else if (event.type == emacs::InputEventType::Mouse)
	{
	  terminal.set_cursor_position ({ row, 2 });
	  std::string mouse_str
	    = "Mouse: x=" + std::to_string (event.x)
	      + " y=" + std::to_string (event.y);
	  terminal.write_text (mouse_str);
	  terminal.clear_end_of_line (
	    { row, static_cast<int> (mouse_str.size () + 2) });
	  terminal.flush ();

	  row++;
	  if (row >= height - 1)
	    row = 10;
	}
    }

  terminal.cleanup ();
  return 0;
}
