// src/gnulib/multibyte.hpp
// C++20 replacements for gnulib multibyte character handling
// Replaces: mbchar, mbiter, mbslen

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <climits>
#include <cstddef>
#include <cstring>
#include <cwchar>
#include <iterator>
#include <string_view>

// Use <cuchar> for C++20 char8_t support where available
#if __cpp_char8_t >= 201811L
# include <cuchar>
#endif

namespace emacs::gnulib
{

// ============================================================================
// Utility functions
// ============================================================================

/// @brief Determine the expected length of a UTF-8 character from its
/// first byte
/// @param first_byte The first byte of a UTF-8 sequence
/// @return The expected length (1-4) or 0 if invalid
[[nodiscard]] inline size_t
utf8_char_length (unsigned char first_byte) noexcept
{
  if ((first_byte & 0x80) == 0x00)
    return 1; // ASCII: 0xxxxxxx
  if ((first_byte & 0xE0) == 0xC0)
    return 2; // 2-byte: 110xxxxx
  if ((first_byte & 0xF0) == 0xE0)
    return 3; // 3-byte: 1110xxxx
  if ((first_byte & 0xF8) == 0xF0)
    return 4; // 4-byte: 11110xxx
  return 0;   // Invalid leading byte
}

/// @brief Check if a byte is a UTF-8 continuation byte
/// @param byte The byte to check
/// @return true if it's a continuation byte (10xxxxxx)
[[nodiscard]] inline bool
is_utf8_continuation (unsigned char byte) noexcept
{
  return (byte & 0xC0) == 0x80;
}

/// @brief Validate a complete UTF-8 string
/// @param str The string to validate
/// @return true if the string is valid UTF-8
[[nodiscard]] inline bool
is_valid_utf8 (std::string_view str) noexcept
{
  const auto *ptr
    = reinterpret_cast<const unsigned char *> (str.data ());
  const auto *end = ptr + str.size ();

  while (ptr < end)
    {
      size_t len = utf8_char_length (*ptr);
      if (len == 0)
	return false; // Invalid leading byte

      if (ptr + len > end)
	return false; // Truncated sequence

      // Check continuation bytes
      for (size_t i = 1; i < len; ++i)
	{
	  if (!is_utf8_continuation (ptr[i]))
	    return false;
	}

      // Additional validation for overlong encodings and invalid
      // ranges
      if (len == 2)
	{
	  // Must encode >= U+0080
	  if ((*ptr & 0x1E) == 0)
	    return false;
	}
      else if (len == 3)
	{
	  // Must encode >= U+0800, and not U+D800-U+DFFF (surrogates)
	  unsigned int codepoint = ((*ptr & 0x0F) << 12)
				   | ((ptr[1] & 0x3F) << 6)
				   | (ptr[2] & 0x3F);
	  if (codepoint < 0x0800
	      || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
	    return false;
	}
      else if (len == 4)
	{
	  // Must encode >= U+10000 and <= U+10FFFF
	  unsigned int codepoint
	    = ((*ptr & 0x07) << 18) | ((ptr[1] & 0x3F) << 12)
	      | ((ptr[2] & 0x3F) << 6) | (ptr[3] & 0x3F);
	  if (codepoint < 0x10000 || codepoint > 0x10FFFF)
	    return false;
	}

      ptr += len;
    }

  return true;
}

// ============================================================================
// mbchar - Multibyte character representation
// ============================================================================

/// @brief Represents a single multibyte character
struct mbchar
{
  char bytes[MB_LEN_MAX]; ///< Raw bytes of the character
  size_t len;		  ///< Number of bytes in the character
  wchar_t wc;		  ///< Wide character equivalent
  bool valid;		  ///< Whether the character is valid

  /// @brief Default constructor - creates an invalid empty character
  mbchar () noexcept : bytes{}, len (0), wc (L'\0'), valid (false) {}

  /// @brief Check if the character is valid
  [[nodiscard]] bool is_valid () const noexcept { return valid; }

  /// @brief Get the byte length of the character
  [[nodiscard]] size_t size () const noexcept { return len; }

  /// @brief Get the wide character value
  [[nodiscard]] wchar_t wide_char () const noexcept { return wc; }

  /// @brief Get a view of the raw bytes
  [[nodiscard]] std::string_view as_string_view () const noexcept
  {
    return std::string_view (bytes, len);
  }

  /// @brief Check if this is an ASCII character
  [[nodiscard]] bool is_ascii () const noexcept
  {
    return valid && len == 1
	   && (static_cast<unsigned char> (bytes[0]) < 128);
  }

  /// @brief Equality comparison
  [[nodiscard]] bool operator== (const mbchar &other) const noexcept
  {
    if (len != other.len)
      return false;
    return std::memcmp (bytes, other.bytes, len) == 0;
  }

  /// @brief Inequality comparison
  [[nodiscard]] bool operator!= (const mbchar &other) const noexcept
  {
    return !(*this == other);
  }
};

// ============================================================================
// mbslen - Count multibyte characters
// ============================================================================

/// @brief Count the number of multibyte characters in a string (not
/// bytes)
/// @param str Null-terminated string to count
/// @return Number of characters, or static_cast<size_t>(-1) on error
[[nodiscard]] inline size_t
mbslen (const char *str) noexcept
{
  if (!str)
    return 0;

  size_t count = 0;
  std::mbstate_t state{};
  const char *ptr = str;

  while (*ptr)
    {
      wchar_t wc;
      size_t len = std::mbrtowc (&wc, ptr, MB_LEN_MAX, &state);

      if (len == 0)
	{
	  // Null character encountered
	  break;
	}
      else if (len == static_cast<size_t> (-1))
	{
	  // Invalid multibyte sequence - treat as single byte
	  ++ptr;
	  ++count;
	  state = std::mbstate_t{};
	}
      else if (len == static_cast<size_t> (-2))
	{
	  // Incomplete multibyte sequence at end - count remaining
	  // bytes
	  while (*ptr)
	    {
	      ++ptr;
	      ++count;
	    }
	  break;
	}
      else
	{
	  ptr += len;
	  ++count;
	}
    }

  return count;
}

/// @brief Count the number of multibyte characters in a string_view
/// @param str String view to count
/// @return Number of characters, or static_cast<size_t>(-1) on error
[[nodiscard]] inline size_t
mbslen (std::string_view str) noexcept
{
  if (str.empty ())
    return 0;

  size_t count = 0;
  std::mbstate_t state{};
  const char *ptr = str.data ();
  const char *end = ptr + str.size ();

  while (ptr < end)
    {
      wchar_t wc;
      size_t remaining = static_cast<size_t> (end - ptr);
      size_t len = std::mbrtowc (&wc, ptr, remaining, &state);

      if (len == 0)
	{
	  // Null character - skip it and continue
	  ++ptr;
	  ++count;
	}
      else if (len == static_cast<size_t> (-1))
	{
	  // Invalid multibyte sequence - treat as single byte
	  ++ptr;
	  ++count;
	  state = std::mbstate_t{};
	}
      else if (len == static_cast<size_t> (-2))
	{
	  // Incomplete sequence - count remaining as individual bytes
	  count += static_cast<size_t> (end - ptr);
	  break;
	}
      else
	{
	  ptr += len;
	  ++count;
	}
    }

  return count;
}

/// @brief Count UTF-8 characters specifically (faster than
/// locale-aware mbslen)
/// @param str String to count
/// @return Number of UTF-8 characters
[[nodiscard]] inline size_t
utf8_strlen (std::string_view str) noexcept
{
  size_t count = 0;
  const auto *ptr
    = reinterpret_cast<const unsigned char *> (str.data ());
  const auto *end = ptr + str.size ();

  while (ptr < end)
    {
      // Count non-continuation bytes
      if ((*ptr & 0xC0) != 0x80)
	++count;
      ++ptr;
    }

  return count;
}

// ============================================================================
// mbiter - Locale-aware iterator over multibyte string
// ============================================================================

// NOTE: mbiter uses std::mbrtowc which depends on the current locale.
// For UTF-8 strings regardless of locale, use utf8_iter instead.
class mbiter
{
public:
  explicit mbiter (const char *str) noexcept
      : start_ (str), current_ (str),
	end_ (str ? str + std::strlen (str) : str), state_{}
  {
  }

  explicit mbiter (std::string_view str) noexcept
      : start_ (str.data ()), current_ (str.data ()),
	end_ (str.data () + str.size ()), state_{}
  {
  }

  [[nodiscard]] bool has_next () const noexcept
  {
    return current_ && current_ < end_;
  }

  [[nodiscard]] mbchar next () noexcept
  {
    mbchar result;

    if (!has_next ())
      return result;

    size_t remaining = static_cast<size_t> (end_ - current_);
    size_t len
      = std::mbrtowc (&result.wc, current_, remaining, &state_);

    if (len == 0)
      {
	result.bytes[0] = '\0';
	result.len = 1;
	result.valid = true;
	++current_;
      }
    else if (len == static_cast<size_t> (-1))
      {
	result.bytes[0] = *current_;
	result.len = 1;
	result.wc = static_cast<wchar_t> (
	  static_cast<unsigned char> (*current_));
	result.valid = false;
	++current_;
	state_ = std::mbstate_t{};
      }
    else if (len == static_cast<size_t> (-2))
      {
	result.len = remaining;
	std::memcpy (result.bytes, current_, remaining);
	result.valid = false;
	current_ = end_;
      }
    else
      {
	result.len = len;
	std::memcpy (result.bytes, current_, len);
	result.valid = true;
	current_ += len;
      }

    return result;
  }

  void reset () noexcept
  {
    current_ = start_;
    state_ = std::mbstate_t{};
  }

  [[nodiscard]] size_t byte_position () const noexcept
  {
    return static_cast<size_t> (current_ - start_);
  }

  [[nodiscard]] size_t remaining_bytes () const noexcept
  {
    return static_cast<size_t> (end_ - current_);
  }

  class iterator
  {
  public:
    using iterator_category = std::input_iterator_tag;
    using value_type = mbchar;
    using difference_type = std::ptrdiff_t;
    using pointer = const mbchar *;
    using reference = const mbchar &;

    iterator () noexcept : iter_ (nullptr), current_{}, at_end_ (true)
    {
    }

    explicit iterator (mbiter *iter, bool at_end = false) noexcept
	: iter_ (iter), current_{},
	  at_end_ (at_end || !iter->has_next ())
    {
      if (!at_end_)
	advance ();
    }

    [[nodiscard]] reference operator* () const noexcept
    {
      return current_;
    }

    [[nodiscard]] pointer operator->() const noexcept
    {
      return &current_;
    }

    iterator &operator++ () noexcept
    {
      advance ();
      return *this;
    }

    iterator operator++ (int) noexcept
    {
      iterator tmp = *this;
      advance ();
      return tmp;
    }

    [[nodiscard]] bool
    operator== (const iterator &other) const noexcept
    {
      if (at_end_ && other.at_end_)
	return true;
      if (at_end_ != other.at_end_)
	return false;
      return iter_ == other.iter_
	     && iter_->byte_position ()
		  == other.iter_->byte_position ();
    }

    [[nodiscard]] bool
    operator!= (const iterator &other) const noexcept
    {
      return !(*this == other);
    }

  private:
    void advance () noexcept
    {
      if (iter_ && iter_->has_next ())
	current_ = iter_->next ();
      else
	at_end_ = true;
    }

    mbiter *iter_;
    mbchar current_;
    bool at_end_;
  };

  [[nodiscard]] iterator begin () noexcept
  {
    reset ();
    return iterator (this);
  }

  [[nodiscard]] iterator end () noexcept
  {
    return iterator (this, true);
  }

private:
  const char *start_;
  const char *current_;
  const char *end_;
  std::mbstate_t state_;
};

// ============================================================================
// utf8_iter - UTF-8 specific iterator (locale-independent)
// ============================================================================

class utf8_iter
{
public:
  explicit utf8_iter (const char *str) noexcept
      : start_ (str), current_ (str),
	end_ (str ? str + std::strlen (str) : str)
  {
  }

  explicit utf8_iter (std::string_view str) noexcept
      : start_ (str.data ()), current_ (str.data ()),
	end_ (str.data () + str.size ())
  {
  }

  [[nodiscard]] bool has_next () const noexcept
  {
    return current_ && current_ < end_;
  }

  [[nodiscard]] mbchar next () noexcept
  {
    mbchar result;

    if (!has_next ())
      return result;

    const auto *ptr
      = reinterpret_cast<const unsigned char *> (current_);
    size_t remaining = static_cast<size_t> (end_ - current_);
    size_t char_len = utf8_char_length (*ptr);

    if (char_len == 0 || char_len > remaining)
      {
	result.bytes[0] = *current_;
	result.len = 1;
	result.wc = static_cast<wchar_t> (*ptr);
	result.valid = false;
	++current_;
	return result;
      }

    for (size_t i = 1; i < char_len; ++i)
      {
	if (!is_utf8_continuation (ptr[i]))
	  {
	    result.bytes[0] = *current_;
	    result.len = 1;
	    result.wc = static_cast<wchar_t> (*ptr);
	    result.valid = false;
	    ++current_;
	    return result;
	  }
      }

    std::memcpy (result.bytes, current_, char_len);
    result.len = char_len;
    result.valid = true;

    switch (char_len)
      {
      case 1:
	result.wc = static_cast<wchar_t> (ptr[0]);
	break;
      case 2:
	result.wc = static_cast<wchar_t> (((ptr[0] & 0x1F) << 6)
					  | (ptr[1] & 0x3F));
	break;
      case 3:
	result.wc = static_cast<wchar_t> (((ptr[0] & 0x0F) << 12)
					  | ((ptr[1] & 0x3F) << 6)
					  | (ptr[2] & 0x3F));
	break;
      case 4:
	{
	  char32_t cp = ((ptr[0] & 0x07) << 18)
			| ((ptr[1] & 0x3F) << 12)
			| ((ptr[2] & 0x3F) << 6) | (ptr[3] & 0x3F);
	  // wchar_t may be 16-bit (Windows) - store as much as
	  // possible
	  result.wc = static_cast<wchar_t> (cp);
	}
	break;
      }

    current_ += char_len;
    return result;
  }

  void reset () noexcept { current_ = start_; }

  [[nodiscard]] size_t byte_position () const noexcept
  {
    return static_cast<size_t> (current_ - start_);
  }

  [[nodiscard]] size_t remaining_bytes () const noexcept
  {
    return static_cast<size_t> (end_ - current_);
  }

  class iterator
  {
  public:
    using iterator_category = std::input_iterator_tag;
    using value_type = mbchar;
    using difference_type = std::ptrdiff_t;
    using pointer = const mbchar *;
    using reference = const mbchar &;

    iterator () noexcept : iter_ (nullptr), current_{}, at_end_ (true)
    {
    }

    explicit iterator (utf8_iter *iter, bool at_end = false) noexcept
	: iter_ (iter), current_{},
	  at_end_ (at_end || !iter->has_next ())
    {
      if (!at_end_)
	advance ();
    }

    [[nodiscard]] reference operator* () const noexcept
    {
      return current_;
    }

    [[nodiscard]] pointer operator->() const noexcept
    {
      return &current_;
    }

    iterator &operator++ () noexcept
    {
      advance ();
      return *this;
    }

    iterator operator++ (int) noexcept
    {
      iterator tmp = *this;
      advance ();
      return tmp;
    }

    [[nodiscard]] bool
    operator== (const iterator &other) const noexcept
    {
      if (at_end_ && other.at_end_)
	return true;
      if (at_end_ != other.at_end_)
	return false;
      return iter_ == other.iter_
	     && iter_->byte_position ()
		  == other.iter_->byte_position ();
    }

    [[nodiscard]] bool
    operator!= (const iterator &other) const noexcept
    {
      return !(*this == other);
    }

  private:
    void advance () noexcept
    {
      if (iter_ && iter_->has_next ())
	current_ = iter_->next ();
      else
	at_end_ = true;
    }

    utf8_iter *iter_;
    mbchar current_;
    bool at_end_;
  };

  [[nodiscard]] iterator begin () noexcept
  {
    reset ();
    return iterator (this);
  }

  [[nodiscard]] iterator end () noexcept
  {
    return iterator (this, true);
  }

private:
  const char *start_;
  const char *current_;
  const char *end_;
};

// ============================================================================
// Additional utility functions
// ============================================================================

/// @brief Convert a UTF-8 code point to its Unicode value
/// @param str Pointer to the start of a UTF-8 sequence
/// @param len Output parameter for the byte length consumed
/// @return The Unicode code point, or 0xFFFD on error
[[nodiscard]] inline char32_t
utf8_decode (const char *str, size_t *len) noexcept
{
  if (!str)
    {
      if (len)
	*len = 0;
      return 0xFFFD;
    }

  const auto *ptr = reinterpret_cast<const unsigned char *> (str);
  size_t char_len = utf8_char_length (*ptr);

  if (char_len == 0)
    {
      if (len)
	*len = 1;
      return 0xFFFD; // Replacement character
    }

  if (len)
    *len = char_len;

  switch (char_len)
    {
    case 1:
      return static_cast<char32_t> (ptr[0]);
    case 2:
      return ((ptr[0] & 0x1F) << 6) | (ptr[1] & 0x3F);
    case 3:
      return ((ptr[0] & 0x0F) << 12) | ((ptr[1] & 0x3F) << 6)
	     | (ptr[2] & 0x3F);
    case 4:
      return ((ptr[0] & 0x07) << 18) | ((ptr[1] & 0x3F) << 12)
	     | ((ptr[2] & 0x3F) << 6) | (ptr[3] & 0x3F);
    default:
      return 0xFFFD;
    }
}

/// @brief Encode a Unicode code point as UTF-8
/// @param codepoint The Unicode code point to encode
/// @param out Output buffer (must have at least 4 bytes)
/// @return Number of bytes written
[[nodiscard]] inline size_t
utf8_encode (char32_t codepoint, char *out) noexcept
{
  if (!out)
    return 0;

  auto *ptr = reinterpret_cast<unsigned char *> (out);

  if (codepoint < 0x80)
    {
      ptr[0] = static_cast<unsigned char> (codepoint);
      return 1;
    }
  else if (codepoint < 0x800)
    {
      ptr[0] = static_cast<unsigned char> (0xC0 | (codepoint >> 6));
      ptr[1] = static_cast<unsigned char> (0x80 | (codepoint & 0x3F));
      return 2;
    }
  else if (codepoint < 0x10000)
    {
      ptr[0] = static_cast<unsigned char> (0xE0 | (codepoint >> 12));
      ptr[1] = static_cast<unsigned char> (
	0x80 | ((codepoint >> 6) & 0x3F));
      ptr[2] = static_cast<unsigned char> (0x80 | (codepoint & 0x3F));
      return 3;
    }
  else if (codepoint <= 0x10FFFF)
    {
      ptr[0] = static_cast<unsigned char> (0xF0 | (codepoint >> 18));
      ptr[1] = static_cast<unsigned char> (
	0x80 | ((codepoint >> 12) & 0x3F));
      ptr[2] = static_cast<unsigned char> (
	0x80 | ((codepoint >> 6) & 0x3F));
      ptr[3] = static_cast<unsigned char> (0x80 | (codepoint & 0x3F));
      return 4;
    }
  else
    {
      // Invalid codepoint - encode replacement character
      ptr[0] = 0xEF;
      ptr[1] = 0xBF;
      ptr[2] = 0xBD;
      return 3;
    }
}

/// @brief Check if a character is a valid Unicode code point
[[nodiscard]] inline bool
is_valid_codepoint (char32_t codepoint) noexcept
{
  // Surrogates (0xD800-0xDFFF) and values > 0x10FFFF are invalid
  return codepoint <= 0x10FFFF
	 && (codepoint < 0xD800 || codepoint > 0xDFFF);
}

#if __cpp_char8_t >= 201811L
/// @brief Overload for char8_t strings (C++20)
[[nodiscard]] inline size_t
mbslen (const char8_t *str) noexcept
{
  return mbslen (reinterpret_cast<const char *> (str));
}

/// @brief Overload for u8string_view (C++20)
[[nodiscard]] inline size_t
mbslen (std::u8string_view str) noexcept
{
  return mbslen (
    std::string_view (reinterpret_cast<const char *> (str.data ()),
		      str.size ()));
}
#endif

} // namespace emacs::gnulib
