// test/cxx/test_input_parser_debug.cpp
// Debug version with output

#include <cassert>
#include <iostream>
#include "../../src/input_parser.hpp"

using namespace emacs::tui;

void
test_escape_key ()
{
  InputParser parser;

  std::cout << "Feeding ESC...\ n";
  parser.feed ("\x1b");
  std::cout << "Has events: " << parser.has_events () << "\n";

  std::cout << "Feeding 'a'...\n";
  parser.feed ("a");
  std::cout << "Has events: " << parser.has_events () << "\n";

  auto esc = parser.next_event ();
  std::cout << "First event - has_value: " << esc.has_value ()
	    << "\n";
  if (esc.has_value ())
    {
      std::cout << "  type: " << (int) esc->type << "\n";
      std::cout << "  key: " << (int) esc->key.key << "\n";
    }

  auto a = parser.next_event ();
  std::cout << "Second event - has_value: " << a.has_value () << "\n";
  if (a.has_value ())
    {
      std::cout << "  type: " << (int) a->type << "\n";
      std::cout << "  unicode: " << (int) a->key.unicode
		<< " (expected " << (int) 'a' << ")\n";
    }
}

int
main ()
{
  test_escape_key ();
  return 0;
}
