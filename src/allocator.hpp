// src/allocator.hpp
// C++ allocator wrapper compatible with Emacs GC
//
// This header defines a C++20 allocator that integrates with Emacs
// garbage collection while providing modern C++ allocator interface.
//
// It allows:
// - Gradual migration from C to C++20
// - Use of RAII and smart pointers in new code
// - Compatibility with existing C code during transition
//
// The allocator respects:
// - Alignment requirements from src/alloc.c (MALLOC_ALIGNMENT)
// - Emacs GC functions (lisp_malloc, lisp_free, lisp_realloc)
// - C++20 standard library compatibility

#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <memory>

// Alignment requirements from src/alloc.c
// Use std::max from <algorithm> instead of global max()
enum
{
  MALLOC_ALIGNMENT
  = std::max (2 * sizeof (size_t), alignof (long double))
};

namespace emacs
{

// Forward declarations for Emacs GC integration point
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
 * C++20 allocator compatible with Emacs GC
 *
 * This allocator wraps Emacs GC functions while providing
 * standard C++ allocator interface. It allows:
 * - Gradual migration from C to C++20
 * - Use of RAII and smart pointers in new code
 * - Compatibility with existing C code during transition
 *
 * @note This allocator should be used for NEW C++ code. Existing C
 * code continues to use the original lisp_malloc() directly.
 */
template <typename T> class emacs_allocator
{
public:
  using value_type = T;
  using pointer_type = T *;
  using const_pointer = const T *;
  using size_type = size_t;
  using difference_type = ptrdiff_t;

  // Default constructor - no allocation
  emacs_allocator () noexcept = default;

  // Copy constructor (required for allocator concept)
  emacs_allocator (const emacs_allocator &) noexcept = default;

  /**
   * Allocate memory using Emacs GC
   *
   * @param n Number of objects to allocate (NOT bytes)
   * @return Pointer to allocated memory, or nullptr if allocation
   * fails
   *
   * Uses aligned allocation for proper memory alignment
   * (MALLOC_ALIGNMENT) Falls back to standard allocator if GC is not
   * available
   */
  [[nodiscard]] T *allocate (size_type n)
  {
    size_type total_bytes = n * sizeof (T);
    size_type aligned_size = (total_bytes + MALLOC_ALIGNMENT - 1)
			     & ~(MALLOC_ALIGNMENT - 1);

    void *ptr = lisp_malloc (aligned_size);
    if (!ptr)
      {
	ptr = ::operator new (aligned_size);
      }
    return static_cast<T *> (ptr);
  }

  /**
   * Allocate memory using Emacs GC with alignment
   *
   * @param n Number of elements to allocate
   * @return Pointer to allocated memory array
   */
  [[nodiscard]] T *allocate_aligned (size_type n, size_type elem_size)
  {
    // Calculate aligned size
    size_type total_size = n * elem_size;
    size_type aligned_size
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
  [[nodiscard]] void *allocate_bytes (size_type n) noexcept
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
  void deallocate (T *ptr, size_type /*n*/) noexcept
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
   * Note: May return a different pointer if GC decides to move the
   * allocation
   */
  [[nodiscard]] T *reallocate (T *ptr, size_type old_size,
			       size_type new_size)
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

  /**
   * Equality comparison (required for allocator concept)
   */
  [[nodiscard]] bool
  operator== (const emacs_allocator &) const noexcept
  {
    return true; // All allocators to the same backend are equivalent
  }

  /**
   * Inequality comparison (required for allocator concept)
   */
  [[nodiscard]] bool
  operator!= (const emacs_allocator &) const noexcept
  {
    return false;
  }

  /**
   * Get maximum allocation size
   *
   * @return Maximum number of bytes that can be allocated
   */
  [[nodiscard]] size_type max_size () const noexcept
  {
    // This is a simplified implementation
    // In reality, this would query the Emacs GC system
    return SIZE_MAX;
  }
};

/**
 * Global C++ allocator instance compatible with Emacs GC
 *
 * This provides a standard allocator that can be used with C++
 * containers (std::vector, std::string, etc.) while integrating with
 * Emacs garbage collection.
 *
 * @example
 * std::vector<int, emacs_allocator<int>> my_vector;
 * my_vector.push_back(42);  // Uses lisp_malloc() via allocator
 */

// C-compatible allocator type for extern "C" interface
// Wraps the C++20 emacs_allocator for C compatibility
struct emacs_allocator_t
{
  void *(*allocate) (size_t);
  void (*deallocate) (void *, size_t);
  void *(*reallocate) (void *, size_t, size_t);
};

// Get C-compatible allocator instance
extern "C"
{
  /**
   * Get Emacs C++ allocator instance
   *
   * @return C allocator compatible with Emacs GC
   */
  inline const emacs_allocator_t &get_emacs_allocator ()
  {
    static const emacs_allocator_t instance
      = { .allocate = [] (size_t n) -> void *
	    { return lisp_malloc (n); },
	  .deallocate = [] (void *ptr, size_t /*n*/) -> void
	    { lisp_free (ptr); },
	  .reallocate
	  = [] (void *ptr, size_t old_size, size_t new_size) -> void *
	    { return lisp_realloc (ptr, new_size); } };
    return instance;
  }
}

} // namespace emacs