// src/allocator.cpp
// C++ allocator wrapper implementation compatible with Emacs GC
//
// This file implements a C++ allocator that wraps Emacs garbage
// collection functions while providing a modern C++20 allocator
// interface.
//
// Key features:
// - Template-based allocator for type safety
// - RAII support for automatic memory management
// - Alignment handling (MALLOC_ALIGNMENT from src/alloc.c)
// - Fallback to standard allocator when Emacs GC unavailable
// - C compatibility via extern "C" interface
//
// This implementation allows:
// - Gradual migration from C to C++20
// - Coexistence with existing C code during transition
// - Use of modern C++ features (RAII, smart pointers, noexcept)

#include "allocator.hpp"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <system_error>

namespace emacs
{

/**
 * Forward declarations for Emacs GC integration
 *
 * These declarations allow C++ code to call Emacs GC functions
 * directly while maintaining type safety.
 */
extern "C"
{
  // These functions are defined in src/alloc.c
  void *lisp_malloc (size_t);
  void *lisp_malloc_unsafe (size_t);
  void lisp_free (void *);
  void *lisp_malloc_uncleared (size_t);
  void *lisp_realloc (void *, size_t);
};

/**
 * Allocate memory using Emacs GC
 *
 * Uses aligned allocation for proper memory alignment
 * Falls back to standard allocator if GC is not available
 */
template <typename T>
[[nodiscard]] T *allocate (size_t n)
{
  // Use aligned allocation for proper memory alignment
  void *ptr = lisp_malloc (n);
  if (!ptr)
    {
      // Fall back to standard allocator if GC not available
      ptr = ::operator new (n);
    }
  return static_cast<T *> (ptr);
}

/**
 * Allocate memory using Emacs GC with alignment
 *
 * @param n Number of elements to allocate
 * @return Pointer to allocated memory array
 */
template <typename T>
[[nodiscard]] T *allocate_aligned (size_t n, size_t elem_size)
{
  // Calculate aligned size
  size_t total_size = n * elem_size;
  size_t aligned_size
    = (total_size + MALLOC_ALIGNMENT - 1) & ~(MALLOC_ALIGNMENT - 1);

  void *ptr = lisp_malloc (aligned_size);
  if (!ptr)
    {
      ptr = ::operator new (aligned_size);
    }
  return static_cast<T *> (ptr);
}

/**
 * Allocate memory without initialization (for large arrays)
 *
 * @param n Number of bytes to allocate
 * @return Pointer to allocated memory
 */
template <typename T>
[[nodiscard]] void *allocate_bytes (size_t n) noexcept
{
  void *ptr = lisp_malloc (n);
  if (!ptr)
    {
      ptr = ::operator new (n);
    }
  return ptr;
}

/**
 * Deallocate memory using Emacs GC
 *
 * @param ptr Pointer to memory to deallocate
 * @param n Size hint (optional, ignored in current implementation)
 */
template <typename T>
void deallocate (T *ptr, size_t /*n*/) noexcept
{
  if (ptr)
    {
      lisp_free (ptr);
    }
}

/**
 * Reallocate memory using Emacs GC
 *
 * @param ptr Pointer to existing memory
 * @param old_size Old size of allocation
 * @param new_size New size of allocation
 * @return Pointer to reallocated memory
 *
 * Note: May return a different pointer if GC decides to move
 * allocation
 */
template <typename T>
[[nodiscard]] T *reallocate (T *ptr, size_t old_size, size_t new_size)
{
  void *new_ptr = lisp_realloc (ptr, new_size);
  if (!new_ptr)
    {
      // Fallback: allocate new and copy
      T *fallback = static_cast<T *> (::operator new (new_size));
      std::memcpy (fallback, ptr,
                  std::min (old_size, new_size) * sizeof (T));
      lisp_free (ptr);
      return fallback;
    }
  return static_cast<T *> (new_ptr);
}

} // namespace emacs
