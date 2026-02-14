#include <iostream>
#include "../../src/containers.hpp"

using namespace emacs;

int
main ()
{
  std::cout << "Creating gc_string...\n";
  gc_string s;

  std::cout << "Appending 'hello'...\n";
  s.append ("hello");

  std::cout << "String: " << s << "\n";
  std::cout << "Size: " << s.size () << "\n";

  std::cout << "Done\n";
  return 0;
}
