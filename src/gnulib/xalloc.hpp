// src/gnulib/xalloc.hpp
// C++20 replacements for gnulib safe allocation
// Replaces: xalloc, xmalloc, xcalloc, xrealloc, xstrdup, xstrndup

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <type_traits>

namespace emacs::gnulib
{

// ============================================================================
// OOM Handler Support
// ============================================================================

// OOM handler type - called before throwing/terminating on allocation
// failure
using xalloc_die_handler_t = void (*) ();

namespace detail
{

// Thread-safe handler storage
inline std::atomic<xalloc_die_handler_t> xalloc_die_handler{
  nullptr
};

// Check for multiplication overflow
[[nodiscard]] constexpr inline bool
multiply_would_overflow (size_t a, size_t b) noexcept
{
  return b != 0 && a > std::numeric_limits<size_t>::max () / b;
}

} // namespace detail

// Set custom OOM handler (called before throwing)
// Thread-safe: uses atomic store
inline void
set_xalloc_die_handler (xalloc_die_handler_t handler) noexcept
{
  detail::xalloc_die_handler.store (handler,
				    std::memory_order_release);
}

// Get current OOM handler
[[nodiscard]] inline xalloc_die_handler_t
get_xalloc_die_handler () noexcept
{
  return detail::xalloc_die_handler.load (std::memory_order_acquire);
}

// Default OOM handler - prints error and terminates
// This is called when allocation fails and no recovery is possible
[[noreturn]] inline void
xalloc_die ()
{
  auto handler
    = detail::xalloc_die_handler.load (std::memory_order_acquire);
  if (handler)
    handler ();

  std::fprintf (stderr, "memory exhausted\n");
  std::terminate ();
}

// ============================================================================
// Core Allocation Functions
// ============================================================================

// Allocate memory, call xalloc_die on failure
// Note: xmalloc(0) returns a valid pointer (allocates 1 byte)
[[nodiscard]] inline void *
xmalloc (size_t size)
{
  // Allocate at least 1 byte to ensure non-null return
  if (size == 0)
    size = 1;

  void *ptr = std::malloc (size);
  if (!ptr)
    xalloc_die ();

  return ptr;
}

// Allocate zeroed memory for array, call xalloc_die on failure
// Checks for multiplication overflow
[[nodiscard]] inline void *
xcalloc (size_t nmemb, size_t size)
{
  // Handle zero-size allocation
  if (nmemb == 0 || size == 0)
    {
      nmemb = 1;
      size = 1;
    }

  // Check for overflow before calling calloc
  if (detail::multiply_would_overflow (nmemb, size))
    xalloc_die ();

  void *ptr = std::calloc (nmemb, size);
  if (!ptr)
    xalloc_die ();

  return ptr;
}

// Reallocate memory, call xalloc_die on failure
// If ptr is null, behaves like xmalloc
// If size is 0, allocates 1 byte (ensures non-null return)
[[nodiscard]] inline void *
xrealloc (void *ptr, size_t size)
{
  // Allocate at least 1 byte
  if (size == 0)
    size = 1;

  void *new_ptr = std::realloc (ptr, size);
  if (!new_ptr)
    xalloc_die ();

  return new_ptr;
}

// ============================================================================
// Nonnull Wrappers (for static analysis compatibility)
// ============================================================================

// Allocate n * s bytes, with overflow checking
[[nodiscard]] inline void *
xnmalloc (size_t n, size_t s)
{
  if (detail::multiply_would_overflow (n, s))
    xalloc_die ();

  return xmalloc (n * s);
}

// Reallocate to n * s bytes, with overflow checking
[[nodiscard]] inline void *
xnrealloc (void *p, size_t n, size_t s)
{
  if (detail::multiply_would_overflow (n, s))
    xalloc_die ();

  return xrealloc (p, n * s);
}

// ============================================================================
// Template Array Allocation Functions (Type-Safe)
// ============================================================================

// Allocate array of count elements of type T
// Memory is uninitialized
template <typename T>
[[nodiscard]] inline T *
xmalloc_array (size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "xmalloc_array requires trivially copyable types");

  if (count == 0)
    count = 1;

  if (detail::multiply_would_overflow (count, sizeof (T)))
    xalloc_die ();

  return static_cast<T *> (xmalloc (count * sizeof (T)));
}

// Allocate zero-initialized array of count elements of type T
template <typename T>
[[nodiscard]] inline T *
xcalloc_array (size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "xcalloc_array requires trivially copyable types");

  if (count == 0)
    count = 1;

  return static_cast<T *> (xcalloc (count, sizeof (T)));
}

// Reallocate array to count elements of type T
template <typename T>
[[nodiscard]] inline T *
xrealloc_array (T *ptr, size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "xrealloc_array requires trivially copyable types");

  if (count == 0)
    count = 1;

  if (detail::multiply_would_overflow (count, sizeof (T)))
    xalloc_die ();

  return static_cast<T *> (xrealloc (ptr, count * sizeof (T)));
}

// ============================================================================
// String Duplication Functions
// ============================================================================

// Duplicate a null-terminated string
// Returns newly allocated copy, call xalloc_die on failure
[[nodiscard]] inline char *
xstrdup (const char *str)
{
  if (!str)
    xalloc_die ();

  size_t len = std::strlen (str) + 1;
  char *copy = static_cast<char *> (xmalloc (len));
  std::memcpy (copy, str, len);
  return copy;
}

// Duplicate at most n characters from a string
// Result is always null-terminated
// Returns newly allocated copy, call xalloc_die on failure
[[nodiscard]] inline char *
xstrndup (const char *str, size_t n)
{
  if (!str)
    xalloc_die ();

  // Find actual length (up to n characters)
  size_t len = 0;
  while (len < n && str[len] != '\0')
    ++len;

  // Allocate with space for null terminator
  char *copy = static_cast<char *> (xmalloc (len + 1));
  std::memcpy (copy, str, len);
  copy[len] = '\0';
  return copy;
}

// C++ style string duplication - returns std::string
// This is the preferred way in C++ code
[[nodiscard]] inline std::string
xstrdup_string (const char *str)
{
  if (!str)
    return std::string{};

  return std::string (str);
}

// C++ style bounded string duplication - returns std::string
[[nodiscard]] inline std::string
xstrndup_string (const char *str, size_t n)
{
  if (!str)
    return std::string{};

  return std::string (str, ::strnlen (str, n));
}

// ============================================================================
// Smart Pointer Helpers
// ============================================================================

// Custom deleter that uses std::free
// For use with memory allocated by xmalloc/xcalloc/xrealloc
template <typename T> struct xfree_deleter
{
  void operator() (T *ptr) const noexcept { std::free (ptr); }
};

// Specialization for arrays
template <typename T> struct xfree_deleter<T[]>
{
  void operator() (T *ptr) const noexcept { std::free (ptr); }
};

// Unique pointer type that uses xfree_deleter
template <typename T>
using xunique_ptr = std::unique_ptr<T, xfree_deleter<T>>;

// Unique pointer type for arrays
template <typename T>
using xunique_array_ptr = std::unique_ptr<T[], xfree_deleter<T[]>>;

// Create unique_ptr with xmalloc for single element
template <typename T>
[[nodiscard]] inline xunique_ptr<T>
make_xunique ()
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "make_xunique requires trivially copyable types");

  return xunique_ptr<T> (static_cast<T *> (xmalloc (sizeof (T))));
}

// Create unique_ptr with xmalloc for array
template <typename T>
[[nodiscard]] inline xunique_array_ptr<T>
make_xunique_array (size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "make_xunique_array requires trivially copyable "
		 "types");

  return xunique_array_ptr<T> (xmalloc_array<T> (count));
}

// Create unique_ptr with xcalloc for array (zero-initialized)
template <typename T>
[[nodiscard]] inline xunique_array_ptr<T>
make_xunique_array_zeroed (size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "make_xunique_array_zeroed requires trivially "
		 "copyable types");

  return xunique_array_ptr<T> (xcalloc_array<T> (count));
}

// Create unique_ptr from xstrdup
[[nodiscard]] inline xunique_ptr<char[]>
make_xunique_string (const char *str)
{
  return xunique_ptr<char[]> (xstrdup (str));
}

// ============================================================================
// Additional Utilities
// ============================================================================

// Allocate and copy memory (like memdup)
[[nodiscard]] inline void *
xmemdup (const void *src, size_t size)
{
  if (!src && size > 0)
    xalloc_die ();

  void *dest = xmalloc (size);
  if (size > 0)
    std::memcpy (dest, src, size);
  return dest;
}

// Template version of memdup
template <typename T>
[[nodiscard]] inline T *
xmemdup_array (const T *src, size_t count)
{
  static_assert (std::is_trivially_copyable_v<T>,
		 "xmemdup_array requires trivially copyable types");

  if (!src && count > 0)
    xalloc_die ();

  if (detail::multiply_would_overflow (count, sizeof (T)))
    xalloc_die ();

  T *dest = xmalloc_array<T> (count);
  if (count > 0)
    std::memcpy (dest, src, count * sizeof (T));
  return dest;
}

// 2-dimensional array allocation
// Allocates n1 * n2 * s bytes with overflow checking
[[nodiscard]] inline void *
x2nrealloc (void *p, size_t *pn, size_t s)
{
  size_t n = *pn;

  if (!p)
    {
      // Initial allocation - start with reasonable size
      n = (s < 256) ? (256 / s) : 1;
    }
  else
    {
      // Grow by factor of 1.5 (approximately)
      if (n > std::numeric_limits<size_t>::max () / 3 * 2)
	xalloc_die ();
      n += n / 2 + 1;
    }

  *pn = n;
  return xnrealloc (p, n, s);
}

// Grow array: reallocate if needed
// Returns pointer to position n in the array
template <typename T>
[[nodiscard]] inline T *
xpalloc (T *pa, size_t *pn, size_t n_incr_min, ptrdiff_t n_max,
	 size_t s)
{
  size_t n0 = *pn;
  size_t n;

  // Calculate new size
  if (n0 == 0)
    n = n_incr_min;
  else
    {
      // Grow by factor of 1.5
      n = n0 + n0 / 2;
      if (n < n0 + n_incr_min)
	n = n0 + n_incr_min;
    }

  // Clamp to max
  if (n_max >= 0 && n > static_cast<size_t> (n_max))
    n = static_cast<size_t> (n_max);

  *pn = n;

  if (detail::multiply_would_overflow (n, s))
    xalloc_die ();

  return static_cast<T *> (xrealloc (pa, n * s));
}

} // namespace emacs::gnulib
