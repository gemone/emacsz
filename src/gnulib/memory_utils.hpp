// src/gnulib/memory_utils.hpp
// C++20 replacements for gnulib memory-related functions
// Replaces: alloca, malloc-gnu, realloc-posix, free-posix, mempcpy,
// memrchr, etc.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <span>
#include <type_traits>
#include <vector>

namespace emacs::gnulib
{

// MALLOC_ALIGNMENT - alignment requirement for allocations
constexpr size_t MALLOC_ALIGNMENT
  = std::max (2 * sizeof (size_t), alignof (long double));

// alloca replacement using RAII
// gnulib alloca is dangerous - use this safer stack allocator
template <typename T, size_t MaxStackSize = 1024>
class stack_allocator
{
public:
  using value_type = T;

  explicit stack_allocator (size_t count) : size_ (count * sizeof (T))
  {
    if (size_ <= MaxStackSize)
      {
	ptr_ = stack_buffer_.data ();
	on_stack_ = true;
      }
    else
      {
	ptr_ = static_cast<std::byte *> (std::malloc (size_));
	on_stack_ = false;
      }
  }

  ~stack_allocator ()
  {
    if (!on_stack_ && ptr_)
      std::free (ptr_);
  }

  stack_allocator (const stack_allocator &) = delete;
  stack_allocator &operator= (const stack_allocator &) = delete;
  stack_allocator (stack_allocator &&) = delete;
  stack_allocator &operator= (stack_allocator &&) = delete;

  [[nodiscard]] T *get () noexcept
  {
    return reinterpret_cast<T *> (ptr_);
  }

  [[nodiscard]] const T *get () const noexcept
  {
    return reinterpret_cast<const T *> (ptr_);
  }

  [[nodiscard]] size_t size () const noexcept
  {
    return size_ / sizeof (T);
  }

  [[nodiscard]] bool is_on_stack () const noexcept
  {
    return on_stack_;
  }

private:
  std::array<std::byte, MaxStackSize> stack_buffer_{};
  std::byte *ptr_ = nullptr;
  size_t size_ = 0;
  bool on_stack_ = false;
};

// mempcpy replacement - copy memory and return pointer to end
[[nodiscard]] inline void *
mempcpy (void *dest, const void *src, size_t n) noexcept
{
  std::memcpy (dest, src, n);
  return static_cast<char *> (dest) + n;
}

// memrchr replacement - search for character from end
[[nodiscard]] inline void *
memrchr (const void *s, int c, size_t n) noexcept
{
  const auto *ptr = static_cast<const unsigned char *> (s);
  for (size_t i = n; i > 0; --i)
    {
      if (ptr[i - 1] == static_cast<unsigned char> (c))
	return const_cast<unsigned char *> (&ptr[i - 1]);
    }
  return nullptr;
}

// rawmemchr replacement - search for character without bounds
[[nodiscard]] inline void *
rawmemchr (const void *s, int c) noexcept
{
  const auto *ptr = static_cast<const unsigned char *> (s);
  while (*ptr != static_cast<unsigned char> (c))
    ++ptr;
  return const_cast<unsigned char *> (ptr);
}

// Aligned memory allocation (C++17/20)
[[nodiscard]] inline void *
aligned_malloc (size_t alignment, size_t size)
{
#if defined(__cpp_aligned_new)
  return ::operator new (size, std::align_val_t{ alignment });
#elif defined(_WIN32)
  return _aligned_malloc (size, alignment);
#else
  void *ptr = nullptr;
  if (posix_memalign (&ptr, alignment, size) != 0)
    return nullptr;
  return ptr;
#endif
}

inline void
aligned_free (void *ptr, [[maybe_unused]] size_t alignment) noexcept
{
#if defined(__cpp_aligned_new)
  ::operator delete (ptr, std::align_val_t{ alignment });
#elif defined(_WIN32)
  _aligned_free (ptr);
#else
  std::free (ptr);
#endif
}

// Safer realloc that preserves errno
[[nodiscard]] inline void *
safe_realloc (void *ptr, size_t new_size)
{
  if (new_size == 0)
    {
      std::free (ptr);
      return nullptr;
    }

  void *new_ptr = std::realloc (ptr, new_size);
  if (!new_ptr && new_size > 0)
    {
      return nullptr;
    }
  return new_ptr;
}

// memset_explicit replacement - secure memory clearing
inline void
memset_explicit (void *ptr, int value, size_t size) noexcept
{
#if defined(__STDC_LIB_EXT1__)
  memset_s (ptr, size, value, size);
#elif defined(_WIN32)
  SecureZeroMemory (ptr, size);
#else
  volatile unsigned char *p
    = static_cast<volatile unsigned char *> (ptr);
  while (size--)
    *p++ = static_cast<unsigned char> (value);
  std::atomic_thread_fence (std::memory_order_seq_cst);
#endif
}

// Zero memory securely
inline void
secure_zero_memory (void *ptr, size_t size) noexcept
{
  memset_explicit (ptr, 0, size);
}

// memmem replacement - search for needle in haystack
[[nodiscard]] inline void *
memmem (const void *haystack, size_t haystack_len, const void *needle,
	size_t needle_len) noexcept
{
  if (needle_len == 0)
    return const_cast<void *> (haystack);
  if (haystack_len < needle_len)
    return nullptr;

  const auto *h = static_cast<const char *> (haystack);
  const auto *n = static_cast<const char *> (needle);
  const char *end = h + haystack_len - needle_len + 1;

  while (h < end)
    {
      const char *found
	= static_cast<const char *> (std::memchr (h, *n, end - h));
      if (!found)
	return nullptr;
      if (std::memcmp (found, n, needle_len) == 0)
	return const_cast<char *> (found);
      h = found + 1;
    }
  return nullptr;
}

// Allocation with overflow checking
template <typename T>
[[nodiscard]] inline T *
safe_array_alloc (size_t count)
{
  if (count > SIZE_MAX / sizeof (T))
    return nullptr;
  return static_cast<T *> (std::malloc (count * sizeof (T)));
}

// RAII wrapper for C-style allocated memory
template <typename T> class c_ptr
{
public:
  explicit c_ptr (T *ptr = nullptr) noexcept : ptr_ (ptr) {}

  ~c_ptr () { std::free (ptr_); }

  c_ptr (const c_ptr &) = delete;
  c_ptr &operator= (const c_ptr &) = delete;

  c_ptr (c_ptr &&other) noexcept : ptr_ (other.ptr_)
  {
    other.ptr_ = nullptr;
  }

  c_ptr &operator= (c_ptr &&other) noexcept
  {
    if (this != &other)
      {
	std::free (ptr_);
	ptr_ = other.ptr_;
	other.ptr_ = nullptr;
      }
    return *this;
  }

  [[nodiscard]] T *get () noexcept { return ptr_; }

  [[nodiscard]] const T *get () const noexcept { return ptr_; }

  [[nodiscard]] T *release () noexcept
  {
    T *tmp = ptr_;
    ptr_ = nullptr;
    return tmp;
  }

  void reset (T *ptr = nullptr) noexcept
  {
    std::free (ptr_);
    ptr_ = ptr;
  }

  explicit operator bool () const noexcept { return ptr_ != nullptr; }

  T &operator* () { return *ptr_; }
  const T &operator* () const { return *ptr_; }
  T *operator->() noexcept { return ptr_; }
  const T *operator->() const noexcept { return ptr_; }

private:
  T *ptr_;
};

} // namespace emacs::gnulib
