#include <cstdlib>
#include <iostream>

extern "C"
{
  void *lisp_malloc (size_t size)
  {
    std::cout << "lisp_malloc called with size=" << size << "\n";
    void *ptr = malloc (size);
    std::cout << "  returned ptr=" << ptr << "\n";
    return ptr;
  }

  void *lisp_malloc_unsafe (size_t size)
  {
    std::cout << "lisp_malloc_unsafe called\n";
    return malloc (size);
  }

  void lisp_free (void *ptr)
  {
    std::cout << "lisp_free called with ptr=" << ptr << "\n";
    free (ptr);
  }

  void *lisp_malloc_uncleared (size_t size)
  {
    std::cout << "lisp_malloc_uncleared called\n";
    return malloc (size);
  }

  void *lisp_realloc (void *ptr, size_t size)
  {
    std::cout << "lisp_realloc called with ptr=" << ptr
	      << ", size=" << size << "\n";
    return realloc (ptr, size);
  }
}
