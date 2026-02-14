#include <iostream>
#include "../../src/input_parser.hpp"

using namespace emacs::tui;

int
main ()
{
  std::cout << "Step 1: Creating InputParser\n";
  InputParser parser;

  std::cout << "Step 2: Feeding 'abc'\n";
  parser.feed ("abc");

  std::cout << "Step 3: Checking has_events\n";
  std::cout << "Has events: " << parser.has_events () << "\n";

  std::cout << "Step 4: Getting events\n";
  int count = 0;
  while (parser.has_events () && count < 10)
    {
      std::cout << "  Getting event #" << (count + 1) << "\n";
      auto e = parser.next_event ();
      if (e.has_value () && e->type == InputEventType::Key)
	{
	  std::cout << "  Got char: " << (char) e->key.unicode
		    << "\n";
	}
      count++;
    }

  std::cout << "Step 5: Done\n";
  return 0;
}
