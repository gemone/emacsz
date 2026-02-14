#include <iostream>
#include "../../src/allocator.hpp"

int
main ()
{
  std::cout << "Program started\n";
  std::cout << "Creating allocator...\n";
  emacs::emacs_allocator<int> alloc;
  std::cout << "Allocator created\n";
  std::cout << "Program ended\n";
  return 0;
}
