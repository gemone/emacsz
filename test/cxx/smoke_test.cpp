#include <iostream>
#include "../src/platform.hpp"

int
main ()
{
  std::cout << "=== Phase 3 Smoke Tests ===" << std::endl;
  std::cout << std::endl;

  std::cout << "Platform Detection:" << std::endl;
  std::cout << "  Platform: " << emacs::get_platform_name ()
	    << std::endl;
  std::cout << "  Architecture: " << emacs::get_architecture_name ()
	    << std::endl;
  std::cout << "  Unix: " << (emacs::is_unix () ? "yes" : "no")
	    << std::endl;
  std::cout << "  Windows: " << (emacs::is_windows () ? "yes" : "no")
	    << std::endl;
  std::cout << "  64-bit: " << (emacs::is_64bit () ? "yes" : "no")
	    << std::endl;
  std::cout << "  Little endian: "
	    << (emacs::is_little_endian () ? "yes" : "no")
	    << std::endl;
  std::cout << std::endl;

  auto features = emacs::get_platform_features ();
  std::cout << "Platform Features:" << std::endl;
  std::cout << "  POSIX threads: "
	    << (features.has_posix_threads ? "yes" : "no")
	    << std::endl;
  std::cout << "  Termios: " << (features.has_termios ? "yes" : "no")
	    << std::endl;
  std::cout << "  Select: " << (features.has_select ? "yes" : "no")
	    << std::endl;
  std::cout << "  Poll: " << (features.has_poll ? "yes" : "no")
	    << std::endl;
  std::cout << std::endl;

  std::cout << "=== Smoke Tests Completed ===" << std::endl;
  return 0;
}
