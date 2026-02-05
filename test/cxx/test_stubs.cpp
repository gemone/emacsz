// test/cxx/test_stubs.cpp
// Stub implementations for Emacs C functions (for unit testing)

#include <cstdlib>

extern "C"
{
  void *lisp_malloc (size_t size) { return malloc (size); }

  void *lisp_malloc_unsafe (size_t size) { return malloc (size); }

  void lisp_free (void *ptr) { free (ptr); }

  void *lisp_malloc_uncleared (size_t size) { return malloc (size); }

  void *lisp_realloc (void *ptr, size_t size)
  {
    return realloc (ptr, size);
  }
}
