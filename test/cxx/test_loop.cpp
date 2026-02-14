#include <iostream>
#include "../../src/input_parser.hpp"

using namespace emacs::tui;

int
main ()
{
  std::cout << "Step 1\n";
  InputParser parser;

  std::cout << "Step 2\n";
  parser.feed ("abc");

  std::cout << "Step 3\n";
  std::cout << "Has events: " << parser.has_events () << "\n";

  std::cout << "Step 4\n";
  int count = 0;
  while (parser.has_events () && count < 10)
    {
      std::cout << "Loop iteration " << count << "\n";
      auto e = parser.next_event ();
      std::cout << "Got event\n";
      if (e.has_value () && e->type == InputEventType::Key)
	{
	  std::cout << "Got char: " << (char) e->key.unicode << "\n";
	}
      count++;
    }

  std::cout << "Done\n";
  return 0;
}
