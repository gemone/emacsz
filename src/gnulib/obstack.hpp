// src/gnulib/obstack.hpp
// C++20 replacements for gnulib obstack (stack-like allocation)
// Replaces: obstack

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>

namespace emacs::gnulib
{

// Obstack: stack-like memory pool where objects can be allocated and
// freed back to any previous point. Objects grow upward from the
// base.
class Obstack
{
public:
  explicit Obstack (size_t initial_size = 4096)
      : buffer_ (initial_size > 0 ? initial_size : 4096),
	base_offset_ (0), next_offset_ (0)
  {
  }

  ~Obstack () = default;

  Obstack (const Obstack &) = delete;
  Obstack &operator= (const Obstack &) = delete;

  Obstack (Obstack &&other) noexcept
      : buffer_ (std::move (other.buffer_)),
	base_offset_ (other.base_offset_),
	next_offset_ (other.next_offset_),
	marks_ (std::move (other.marks_))
  {
    other.base_offset_ = 0;
    other.next_offset_ = 0;
  }

  Obstack &operator= (Obstack &&other) noexcept
  {
    if (this != &other)
      {
	buffer_ = std::move (other.buffer_);
	base_offset_ = other.base_offset_;
	next_offset_ = other.next_offset_;
	marks_ = std::move (other.marks_);
	other.base_offset_ = 0;
	other.next_offset_ = 0;
      }
    return *this;
  }

  [[nodiscard]] void *alloc (size_t size)
  {
    ensure_space (size);
    void *ptr = buffer_.data () + next_offset_;
    next_offset_ += size;
    marks_.push_back (base_offset_);
    base_offset_ = next_offset_;
    return ptr;
  }

  [[nodiscard]] void *copy (const void *data, size_t size)
  {
    void *ptr = alloc (size);
    if (data && size > 0)
      std::memcpy (ptr, data, size);
    return ptr;
  }

  [[nodiscard]] void *copy0 (const void *data, size_t size)
  {
    void *ptr = alloc (size + 1);
    if (data && size > 0)
      std::memcpy (ptr, data, size);
    static_cast<char *> (ptr)[size] = '\0';
    return ptr;
  }

  [[nodiscard]] char *strcpy (const char *str)
  {
    if (!str)
      return nullptr;
    size_t len = std::strlen (str);
    return static_cast<char *> (copy0 (str, len));
  }

  [[nodiscard]] char *strncpy (const char *str, size_t n)
  {
    if (!str)
      return nullptr;
    size_t len = std::strlen (str);
    size_t copy_len = std::min (len, n);
    return static_cast<char *> (copy0 (str, copy_len));
  }

  void grow (const void *data, size_t size)
  {
    ensure_space (size);
    if (data && size > 0)
      std::memcpy (buffer_.data () + next_offset_, data, size);
    next_offset_ += size;
  }

  void grow0 (const void *data, size_t size)
  {
    ensure_space (size + 1);
    if (data && size > 0)
      std::memcpy (buffer_.data () + next_offset_, data, size);
    next_offset_ += size;
    buffer_[next_offset_++] = '\0';
  }

  void grow_char (char c)
  {
    ensure_space (1);
    buffer_[next_offset_++] = c;
  }

  void blank (size_t size)
  {
    ensure_space (size);
    next_offset_ += size;
  }

  [[nodiscard]] void *finish ()
  {
    void *ptr = buffer_.data () + base_offset_;
    marks_.push_back (base_offset_);
    base_offset_ = next_offset_;
    return ptr;
  }

  void free (void *ptr)
  {
    if (!ptr)
      {
	free_all ();
	return;
      }

    auto *char_ptr = static_cast<char *> (ptr);
    auto *buf_start = buffer_.data ();

    if (char_ptr < buf_start
	|| char_ptr
	     >= buf_start + static_cast<ptrdiff_t> (buffer_.size ()))
      return;

    size_t offset = static_cast<size_t> (char_ptr - buf_start);

    next_offset_ = offset;
    base_offset_ = offset;

    while (!marks_.empty () && marks_.back () >= offset)
      marks_.pop_back ();
  }

  void free_all ()
  {
    next_offset_ = 0;
    base_offset_ = 0;
    marks_.clear ();
  }

  [[nodiscard]] size_t room () const noexcept
  {
    return buffer_.size () > next_offset_
	     ? buffer_.size () - next_offset_
	     : 0;
  }

  [[nodiscard]] size_t object_size () const noexcept
  {
    return next_offset_ - base_offset_;
  }

  [[nodiscard]] void *base () const noexcept
  {
    return const_cast<char *> (buffer_.data () + base_offset_);
  }

  [[nodiscard]] void *next_free () const noexcept
  {
    return const_cast<char *> (buffer_.data () + next_offset_);
  }

  [[nodiscard]] bool empty () const noexcept
  {
    return next_offset_ == 0;
  }

  [[nodiscard]] size_t capacity () const noexcept
  {
    return buffer_.size ();
  }

  [[nodiscard]] size_t allocated () const noexcept
  {
    return next_offset_;
  }

private:
  void ensure_space (size_t size)
  {
    size_t required = next_offset_ + size;
    if (required > buffer_.size ())
      {
	size_t new_size = std::max (buffer_.size () * 2, required);
	buffer_.resize (new_size);
      }
  }

  std::vector<char> buffer_;
  size_t base_offset_;
  size_t next_offset_;
  std::vector<size_t> marks_;
};

// ============================================================================
// C-compatible API wrappers for gnulib compatibility
// ============================================================================

using obstack_t = Obstack *;

inline int
obstack_init (obstack_t *obs)
{
  if (!obs)
    return 0;
  try
    {
      *obs = new Obstack ();
      return 1;
    }
  catch (...)
    {
      *obs = nullptr;
      return 0;
    }
}

inline void
obstack_destroy (obstack_t obs)
{
  delete obs;
}

inline void *
obstack_alloc (obstack_t obs, size_t size)
{
  if (!obs)
    return nullptr;
  try
    {
      return obs->alloc (size);
    }
  catch (...)
    {
      return nullptr;
    }
}

inline void *
obstack_copy (obstack_t obs, const void *data, size_t size)
{
  if (!obs)
    return nullptr;
  try
    {
      return obs->copy (data, size);
    }
  catch (...)
    {
      return nullptr;
    }
}

inline void *
obstack_copy0 (obstack_t obs, const void *data, size_t size)
{
  if (!obs)
    return nullptr;
  try
    {
      return obs->copy0 (data, size);
    }
  catch (...)
    {
      return nullptr;
    }
}

inline void
obstack_free (obstack_t obs, void *ptr)
{
  if (obs)
    obs->free (ptr);
}

inline void
obstack_grow (obstack_t obs, const void *data, size_t size)
{
  if (obs)
    {
      try
	{
	  obs->grow (data, size);
	}
      catch (...)
	{
	}
    }
}

inline void
obstack_grow0 (obstack_t obs, const void *data, size_t size)
{
  if (obs)
    {
      try
	{
	  obs->grow0 (data, size);
	}
      catch (...)
	{
	}
    }
}

inline void
obstack_1grow (obstack_t obs, char c)
{
  if (obs)
    {
      try
	{
	  obs->grow_char (c);
	}
      catch (...)
	{
	}
    }
}

inline void
obstack_blank (obstack_t obs, size_t size)
{
  if (obs)
    {
      try
	{
	  obs->blank (size);
	}
      catch (...)
	{
	}
    }
}

inline void *
obstack_finish (obstack_t obs)
{
  if (!obs)
    return nullptr;
  try
    {
      return obs->finish ();
    }
  catch (...)
    {
      return nullptr;
    }
}

inline size_t
obstack_room (obstack_t obs)
{
  return obs ? obs->room () : 0;
}

inline size_t
obstack_object_size (obstack_t obs)
{
  return obs ? obs->object_size () : 0;
}

inline void *
obstack_base (obstack_t obs)
{
  return obs ? obs->base () : nullptr;
}

inline void *
obstack_next_free (obstack_t obs)
{
  return obs ? obs->next_free () : nullptr;
}

// ============================================================================
// RAII wrapper for automatic obstack management
// ============================================================================

class ObstackHandle
{
public:
  ObstackHandle () : obs_ (nullptr) { obstack_init (&obs_); }

  explicit ObstackHandle (size_t initial_size)
  {
    try
      {
	obs_ = new Obstack (initial_size);
      }
    catch (...)
      {
	obs_ = nullptr;
      }
  }

  ~ObstackHandle () { obstack_destroy (obs_); }

  ObstackHandle (const ObstackHandle &) = delete;
  ObstackHandle &operator= (const ObstackHandle &) = delete;

  ObstackHandle (ObstackHandle &&other) noexcept : obs_ (other.obs_)
  {
    other.obs_ = nullptr;
  }

  ObstackHandle &operator= (ObstackHandle &&other) noexcept
  {
    if (this != &other)
      {
	obstack_destroy (obs_);
	obs_ = other.obs_;
	other.obs_ = nullptr;
      }
    return *this;
  }

  [[nodiscard]] obstack_t get () noexcept { return obs_; }

  [[nodiscard]] const obstack_t get () const noexcept { return obs_; }

  [[nodiscard]] Obstack *operator->() noexcept { return obs_; }

  [[nodiscard]] const Obstack *operator->() const noexcept
  {
    return obs_;
  }

  [[nodiscard]] Obstack &operator* () { return *obs_; }

  [[nodiscard]] const Obstack &operator* () const { return *obs_; }

  explicit operator bool () const noexcept { return obs_ != nullptr; }

private:
  obstack_t obs_;
};

} // namespace emacs::gnulib
