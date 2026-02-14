// test/test_termbox2_term.cpp
#include <iostream>

#include "../src/termbox2_term.hpp"

/**
 * Test Termbox2Backend initialization
 *
 * Verifies that init() returns true and queries work correctly.
 */
bool
test_termbox2_backend_init ()
{
  emacs::Termbox2Backend backend;

  if (!backend.init ())
    {
      std::cerr << "FAIL: Termbox2Backend init failed\n";
      return false;
    }

  auto size = backend.get_terminal_size ();
  if (size.first <= 0 || size.second <= 0)
    {
      std::cerr << "FAIL: Invalid terminal size: " << size.first
		<< "x" << size.second << "\n";
      return false;
    }

  if (!backend.supports_colors ())
    {
      std::cerr << "FAIL: Terminal should support colors\n";
      return false;
    }

  if (!backend.supports_truecolor ())
    {
      std::cerr << "FAIL: Terminal should support truecolor\n";
      return false;
    }

  std::cout << "PASS: Termbox2Backend init test\n";
  return true;
}

/**
 * Main test runner
 *
 * Runs all tests and reports results.
 */
int
main ()
{
  int passed = 0;
  int failed = 0;

  if (test_termbox2_backend_init ())
    ++passed;
  else
    ++failed;

  std::cout << "\n";
  std::cout << "Results: " << passed << " passed, " << failed
	    << " failed\n";
  std::cout << "Status: " << (failed == 0 ? "SUCCESS" : "FAILED")
	    << "\n";

  return (failed == 0) ? 0 : 1;
}
