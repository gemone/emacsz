#include <iostream>
#include "../../src/input_parser.hpp"

using namespace emacs::tui;

int
main ()
{
  InputParser parser;

  std::cout << "Feeding 'abc'...\n";
  parser.feed ("abc");

  std::cout << "Has events: " << parser.has_events () << "\n";

  while (parser.has_events ())
    {
      auto e = parser.next_event ();
      if (e.has_value () && e->type == InputEventType::Key)
	{
	  std::cout << "Got char: " << (char) e->key.unicode << "\n";
	}
    }

  std::cout << "Done\n";
  return 0;
}
