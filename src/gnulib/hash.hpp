// src/gnulib/hash.hpp
// C++20 replacements for gnulib hash utilities
// Replaces: hash-pjw, hash-pjw-bare, hash (hash table)

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string_view>
#include <unordered_map>

namespace emacs::gnulib
{

// Constants for Peter J. Weinberger's hash algorithm
namespace detail
{
// Hash table size constants
static constexpr size_t HASH_ONE = 0x01000193;
static constexpr size_t HASH_MULTIPLIER = 16777619;
static constexpr uint32_t PRIME = 0x9e3779b1;
}

// Peter J. Weinberger's hash function (hash-pjw)
// Returns a hash value in the range [0, tablesize)
[[nodiscard]] constexpr inline size_t
hash_pjw (const char *str, size_t tablesize) noexcept
{
  if (!str || tablesize == 0)
    return 0;

  size_t h = 0;
  for (const char *p = str; *p; ++p)
    {
      size_t g = h << 4;
      h = h << 4;
      h += static_cast<unsigned char> (*p);

      g = (h & 0xf0000000UL);
      if (g)
	h = h ^ (g >> 24);
      h = h & ~g;
    }

  return h % tablesize;
}

// Peter J. Weinberger's hash function (hash-pjw)
// String view overload
[[nodiscard]] constexpr inline size_t
hash_pjw (std::string_view str, size_t tablesize) noexcept
{
  if (str.empty () || tablesize == 0)
    return 0;

  size_t h = 0;
  for (unsigned char c : str)
    {
      size_t g = h << 4;
      h = h << 4;
      h += c;

      g = (h & 0xf0000000UL);
      if (g)
	h = h ^ (g >> 24);
      h = h & ~g;
    }

  return h % tablesize;
}

// Peter J. Weinberger's hash function without modulo (hash-pjw-bare)
// Returns the raw hash value without limiting to a table size
[[nodiscard]] constexpr inline size_t
hash_pjw_bare (const char *str) noexcept
{
  if (!str)
    return 0;

  size_t h = 0;
  for (const char *p = str; *p; ++p)
    {
      size_t g = h << 4;
      h = h << 4;
      h += static_cast<unsigned char> (*p);

      g = (h & 0xf0000000UL);
      if (g)
	h = h ^ (g >> 24);
      h = h & ~g;
    }

  return h;
}

// Peter J. Weinberger's hash function without modulo (hash-pjw-bare)
// String view overload
[[nodiscard]] constexpr inline size_t
hash_pjw_bare (std::string_view str) noexcept
{
  if (str.empty ())
    return 0;

  size_t h = 0;
  for (unsigned char c : str)
    {
      size_t g = h << 4;
      h = h << 4;
      h += c;

      g = (h & 0xf0000000UL);
      if (g)
	h = h ^ (g >> 24);
      h = h & ~g;
    }

  return h;
}

// Simple hash table wrapper around std::unordered_map
// Provides a convenient interface for basic hash table operations
template <typename Key, typename Value> class hash_table
{
public:
  using key_type = Key;
  using value_type = Value;
  using map_type = std::unordered_map<Key, Value>;
  using iterator = typename map_type::iterator;
  using const_iterator = typename map_type::const_iterator;

  hash_table () = default;
  explicit hash_table (size_t initial_size) : data_ (initial_size) {}

  // Insert or update a key-value pair
  std::pair<iterator, bool>
  insert (const Key &key, const Value &value) noexcept (
    std::is_nothrow_copy_assignable_v<Value>)
  {
    return data_.insert ({ key, value });
  }

  // Insert or update with move semantics
  std::pair<iterator, bool> insert (
    const Key &key,
    Value &&value) noexcept (std::is_nothrow_move_assignable_v<Value>)
  {
    return data_.insert ({ key, std::move (value) });
  }

  // Find a value by key
  [[nodiscard]] iterator find (const Key &key) noexcept
  {
    return data_.find (key);
  }

  [[nodiscard]] const_iterator find (const Key &key) const noexcept
  {
    return data_.find (key);
  }

  // Check if key exists
  [[nodiscard]] bool contains (const Key &key) const noexcept
  {
    return data_.find (key) != data_.end ();
  }

  // Remove a key
  bool erase (const Key &key) noexcept
  {
    return data_.erase (key) > 0;
  }

  // Get value by key (with default)
  [[nodiscard]] Value get (const Key &key,
			   const Value &default_value) const
    noexcept (std::is_nothrow_copy_assignable_v<Value>)
  {
    auto it = data_.find (key);
    return it != data_.end () ? it->second : default_value;
  }

  // Get or create with default value
  Value &get_or_insert (
    const Key &key,
    const Value
      &default_value) noexcept (std::
				  is_nothrow_copy_assignable_v<Value>)
  {
    return data_[key]
	   = data_.count (key) ? data_[key] : default_value;
  }

  // Clear all entries
  void clear () noexcept { data_.clear (); }

  // Get number of entries
  [[nodiscard]] size_t size () const noexcept
  {
    return data_.size ();
  }

  // Check if empty
  [[nodiscard]] bool empty () const noexcept
  {
    return data_.empty ();
  }

  // Access underlying map
  [[nodiscard]] map_type &underlying_map () noexcept { return data_; }

  [[nodiscard]] const map_type &underlying_map () const noexcept
  {
    return data_;
  }

  // Iterator support
  iterator begin () noexcept { return data_.begin (); }
  iterator end () noexcept { return data_.end (); }
  const_iterator begin () const noexcept { return data_.begin (); }
  const_iterator end () const noexcept { return data_.end (); }
  const_iterator cbegin () const noexcept { return data_.cbegin (); }
  const_iterator cend () const noexcept { return data_.cend (); }

private:
  map_type data_;
};

} // namespace emacs::gnulib
