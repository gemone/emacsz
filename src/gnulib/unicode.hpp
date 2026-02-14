// src/gnulib/unicode.hpp
// C++20 replacements for gnulib Unicode handling
// Replaces: unicode utilities (encoding conversion only)
// Note: Character properties (is_upper, is_letter, etc.) require ICU
// library

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace emacs::gnulib
{

// =============================================================================
// Types and Constants
// =============================================================================

// Unicode code point type
using codepoint_t = char32_t;

// Maximum bytes per UTF-8 character
constexpr size_t UTF8_MAX_BYTES = 4;

// Unicode replacement character
constexpr codepoint_t REPLACEMENT_CHAR = 0xFFFD;

// BOM markers
constexpr unsigned char UTF8_BOM[] = { 0xEF, 0xBB, 0xBF };
constexpr char16_t UTF16_BOM_LE = 0xFFFE;
constexpr char16_t UTF16_BOM_BE = 0xFEFF;

// Unicode ranges
constexpr codepoint_t MAX_CODEPOINT = 0x10FFFF;
constexpr codepoint_t SURROGATE_MIN = 0xD800;
constexpr codepoint_t SURROGATE_MAX = 0xDFFF;
constexpr codepoint_t HIGH_SURROGATE_MIN = 0xD800;
constexpr codepoint_t HIGH_SURROGATE_MAX = 0xDBFF;
constexpr codepoint_t LOW_SURROGATE_MIN = 0xDC00;
constexpr codepoint_t LOW_SURROGATE_MAX = 0xDFFF;

// UTF-16 surrogate constants (char16_t typed for comparison without
// warnings)
constexpr char16_t HIGH_SURROGATE_MIN_16 = 0xD800;
constexpr char16_t HIGH_SURROGATE_MAX_16 = 0xDBFF;
constexpr char16_t LOW_SURROGATE_MIN_16 = 0xDC00;
constexpr char16_t LOW_SURROGATE_MAX_16 = 0xDFFF;

// =============================================================================
// UTF-8 Utilities
// =============================================================================

// Returns the number of UTF-8 bytes needed to encode a code point
[[nodiscard]] inline size_t
utf8_codepoint_length (char32_t cp) noexcept
{
  if (cp < 0x80)
    return 1;
  if (cp < 0x800)
    return 2;
  if (cp < 0x10000)
    return 3;
  if (cp <= MAX_CODEPOINT)
    return 4;
  return 0; // Invalid code point
}

// Returns the expected sequence length from the first byte of a UTF-8
// sequence
[[nodiscard]] inline size_t
utf8_sequence_length (unsigned char first_byte) noexcept
{
  if ((first_byte & 0x80) == 0)
    return 1; // 0xxxxxxx - ASCII
  if ((first_byte & 0xE0) == 0xC0)
    return 2; // 110xxxxx
  if ((first_byte & 0xF0) == 0xE0)
    return 3; // 1110xxxx
  if ((first_byte & 0xF8) == 0xF0)
    return 4; // 11110xxx
  return 0;   // Invalid lead byte
}

// Returns true if the byte is a UTF-8 continuation byte (10xxxxxx)
[[nodiscard]] inline bool
unicode_is_utf8_continuation (unsigned char byte) noexcept
{
  return (byte & 0xC0) == 0x80;
}

// Returns true if the code point is a valid Unicode code point
[[nodiscard]] inline bool
unicode_is_valid_codepoint (char32_t cp) noexcept
{
  // Valid range: 0 to 0x10FFFF, excluding surrogates
  return cp <= MAX_CODEPOINT
	 && (cp < SURROGATE_MIN || cp > SURROGATE_MAX);
}

// =============================================================================
// Encoding Detection
// =============================================================================

// Returns true if the string starts with a UTF-8 BOM
[[nodiscard]] inline bool
has_utf8_bom (std::string_view str) noexcept
{
  return str.size () >= 3
	 && static_cast<unsigned char> (str[0]) == 0xEF
	 && static_cast<unsigned char> (str[1]) == 0xBB
	 && static_cast<unsigned char> (str[2]) == 0xBF;
}

// Returns the string with UTF-8 BOM stripped if present
[[nodiscard]] inline std::string_view
strip_utf8_bom (std::string_view str) noexcept
{
  if (has_utf8_bom (str))
    return str.substr (3);
  return str;
}

// =============================================================================
// UTF-8 Decoding
// =============================================================================

// Decodes a single UTF-8 character, advancing the pointer
// Returns std::nullopt on invalid sequences
[[nodiscard]] inline std::optional<char32_t>
utf8_decode_char (const char *&ptr, const char *end) noexcept
{
  if (ptr >= end)
    return std::nullopt;

  unsigned char first = static_cast<unsigned char> (*ptr);
  size_t len = utf8_sequence_length (first);

  if (len == 0 || ptr + len > end)
    {
      ++ptr;
      return std::nullopt;
    }

  char32_t cp;

  switch (len)
    {
    case 1:
      cp = first;
      break;

    case 2:
      {
	unsigned char b1 = static_cast<unsigned char> (ptr[1]);
	if (!unicode_is_utf8_continuation (b1))
	  {
	    ++ptr;
	    return std::nullopt;
	  }
	cp = ((first & 0x1F) << 6) | (b1 & 0x3F);
	// Overlong check: 2-byte sequences must encode >= 0x80
	if (cp < 0x80)
	  {
	    ++ptr;
	    return std::nullopt;
	  }
      }
      break;

    case 3:
      {
	unsigned char b1 = static_cast<unsigned char> (ptr[1]);
	unsigned char b2 = static_cast<unsigned char> (ptr[2]);
	if (!unicode_is_utf8_continuation (b1)
	    || !unicode_is_utf8_continuation (b2))
	  {
	    ++ptr;
	    return std::nullopt;
	  }
	cp
	  = ((first & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
	// Overlong check: 3-byte sequences must encode >= 0x800
	if (cp < 0x800)
	  {
	    ++ptr;
	    return std::nullopt;
	  }
	// Reject surrogates
	if (cp >= SURROGATE_MIN && cp <= SURROGATE_MAX)
	  {
	    ++ptr;
	    return std::nullopt;
	  }
      }
      break;

    case 4:
      {
	unsigned char b1 = static_cast<unsigned char> (ptr[1]);
	unsigned char b2 = static_cast<unsigned char> (ptr[2]);
	unsigned char b3 = static_cast<unsigned char> (ptr[3]);
	if (!unicode_is_utf8_continuation (b1)
	    || !unicode_is_utf8_continuation (b2)
	    || !unicode_is_utf8_continuation (b3))
	  {
	    ++ptr;
	    return std::nullopt;
	  }
	cp = ((first & 0x07) << 18) | ((b1 & 0x3F) << 12)
	     | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
	// Overlong check: 4-byte sequences must encode >= 0x10000
	if (cp < 0x10000)
	  {
	    ++ptr;
	    return std::nullopt;
	  }
	// Range check
	if (cp > MAX_CODEPOINT)
	  {
	    ++ptr;
	    return std::nullopt;
	  }
      }
      break;

    default:
      ++ptr;
      return std::nullopt;
    }

  ptr += len;
  return cp;
}

// =============================================================================
// UTF-8 Encoding
// =============================================================================

// Encodes a single code point to UTF-8
// Returns the number of bytes written (0 on invalid code point)
// The output buffer must have at least UTF8_MAX_BYTES capacity
[[nodiscard]] inline size_t
utf32_encode_char (char32_t cp, char *out) noexcept
{
  if (!unicode_is_valid_codepoint (cp))
    {
      // Encode replacement character instead
      out[0] = static_cast<char> (0xEF);
      out[1] = static_cast<char> (0xBF);
      out[2] = static_cast<char> (0xBD);
      return 3;
    }

  if (cp < 0x80)
    {
      out[0] = static_cast<char> (cp);
      return 1;
    }

  if (cp < 0x800)
    {
      out[0] = static_cast<char> (0xC0 | (cp >> 6));
      out[1] = static_cast<char> (0x80 | (cp & 0x3F));
      return 2;
    }

  if (cp < 0x10000)
    {
      out[0] = static_cast<char> (0xE0 | (cp >> 12));
      out[1] = static_cast<char> (0x80 | ((cp >> 6) & 0x3F));
      out[2] = static_cast<char> (0x80 | (cp & 0x3F));
      return 3;
    }

  out[0] = static_cast<char> (0xF0 | (cp >> 18));
  out[1] = static_cast<char> (0x80 | ((cp >> 12) & 0x3F));
  out[2] = static_cast<char> (0x80 | ((cp >> 6) & 0x3F));
  out[3] = static_cast<char> (0x80 | (cp & 0x3F));
  return 4;
}

// =============================================================================
// UTF Conversion Functions
// =============================================================================

// Convert UTF-8 string to UTF-32
// Invalid sequences are replaced with REPLACEMENT_CHAR
[[nodiscard]] inline std::u32string
utf8_to_utf32 (std::string_view utf8)
{
  std::u32string result;
  result.reserve (utf8.size ()); // Over-reserve, but safe

  const char *ptr = utf8.data ();
  const char *end = ptr + utf8.size ();

  while (ptr < end)
    {
      auto cp = utf8_decode_char (ptr, end);
      result.push_back (cp.value_or (REPLACEMENT_CHAR));
    }

  return result;
}

// Convert UTF-32 string to UTF-8
// Invalid code points are replaced with REPLACEMENT_CHAR
[[nodiscard]] inline std::string
utf32_to_utf8 (std::u32string_view utf32)
{
  std::string result;
  result.reserve (utf32.size ()
		  * UTF8_MAX_BYTES); // Max possible size

  char buf[UTF8_MAX_BYTES];
  for (char32_t cp : utf32)
    {
      size_t len = utf32_encode_char (cp, buf);
      result.append (buf, len);
    }

  return result;
}

// Convert UTF-8 string to UTF-16
// Handles surrogate pairs for code points > 0xFFFF
// Invalid sequences are replaced with REPLACEMENT_CHAR
[[nodiscard]] inline std::u16string
utf8_to_utf16 (std::string_view utf8)
{
  std::u16string result;
  result.reserve (utf8.size ()); // Over-reserve

  const char *ptr = utf8.data ();
  const char *end = ptr + utf8.size ();

  while (ptr < end)
    {
      auto maybe_cp = utf8_decode_char (ptr, end);
      char32_t cp = maybe_cp.value_or (REPLACEMENT_CHAR);

      if (cp < 0x10000)
	{
	  result.push_back (static_cast<char16_t> (cp));
	}
      else
	{
	  // Encode as surrogate pair
	  cp -= 0x10000;
	  result.push_back (
	    static_cast<char16_t> (HIGH_SURROGATE_MIN + (cp >> 10)));
	  result.push_back (
	    static_cast<char16_t> (LOW_SURROGATE_MIN + (cp & 0x3FF)));
	}
    }

  return result;
}

// Convert UTF-16 string to UTF-8
// Handles surrogate pairs
// Invalid surrogates are replaced with REPLACEMENT_CHAR
[[nodiscard]] inline std::string
utf16_to_utf8 (std::u16string_view utf16)
{
  std::string result;
  result.reserve (utf16.size () * 3);

  char buf[UTF8_MAX_BYTES];
  size_t i = 0;

  while (i < utf16.size ())
    {
      char16_t cu = utf16[i];
      char32_t cp;

      if (cu >= HIGH_SURROGATE_MIN_16 && cu <= HIGH_SURROGATE_MAX_16)
	{
	  if (i + 1 < utf16.size ())
	    {
	      char16_t cu2 = utf16[i + 1];
	      if (cu2 >= LOW_SURROGATE_MIN_16
		  && cu2 <= LOW_SURROGATE_MAX_16)
		{
		  cp = 0x10000
		       + ((static_cast<char32_t> (
			     cu - HIGH_SURROGATE_MIN_16)
			   << 10)
			  | (cu2 - LOW_SURROGATE_MIN_16));
		  i += 2;
		}
	      else
		{
		  cp = REPLACEMENT_CHAR;
		  ++i;
		}
	    }
	  else
	    {
	      cp = REPLACEMENT_CHAR;
	      ++i;
	    }
	}
      else if (cu >= LOW_SURROGATE_MIN_16
	       && cu <= LOW_SURROGATE_MAX_16)
	{
	  cp = REPLACEMENT_CHAR;
	  ++i;
	}
      else
	{
	  cp = cu;
	  ++i;
	}

      size_t len = utf32_encode_char (cp, buf);
      result.append (buf, len);
    }

  return result;
}

// =============================================================================
// Validation
// =============================================================================

// Returns true if the string is valid UTF-8
[[nodiscard]] inline bool
unicode_is_valid_utf8 (std::string_view str) noexcept
{
  const char *ptr = str.data ();
  const char *end = ptr + str.size ();

  while (ptr < end)
    {
      unsigned char first = static_cast<unsigned char> (*ptr);
      size_t len = utf8_sequence_length (first);

      if (len == 0 || ptr + len > end)
	return false;

      // Validate continuation bytes and check for overlong encodings
      switch (len)
	{
	case 1:
	  ++ptr;
	  continue;

	case 2:
	  {
	    if (!unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[1])))
	      return false;
	    char32_t cp
	      = ((first & 0x1F) << 6)
		| (static_cast<unsigned char> (ptr[1]) & 0x3F);
	    if (cp < 0x80)
	      return false; // Overlong
	  }
	  break;

	case 3:
	  {
	    if (!unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[1]))
		|| !unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[2])))
	      return false;
	    char32_t cp
	      = ((first & 0x0F) << 12)
		| ((static_cast<unsigned char> (ptr[1]) & 0x3F) << 6)
		| (static_cast<unsigned char> (ptr[2]) & 0x3F);
	    if (cp < 0x800)
	      return false; // Overlong
	    if (cp >= SURROGATE_MIN && cp <= SURROGATE_MAX)
	      return false; // Surrogate
	  }
	  break;

	case 4:
	  {
	    if (!unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[1]))
		|| !unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[2]))
		|| !unicode_is_utf8_continuation (
		  static_cast<unsigned char> (ptr[3])))
	      return false;
	    char32_t cp
	      = ((first & 0x07) << 18)
		| ((static_cast<unsigned char> (ptr[1]) & 0x3F) << 12)
		| ((static_cast<unsigned char> (ptr[2]) & 0x3F) << 6)
		| (static_cast<unsigned char> (ptr[3]) & 0x3F);
	    if (cp < 0x10000)
	      return false; // Overlong
	    if (cp > MAX_CODEPOINT)
	      return false; // Out of range
	  }
	  break;

	default:
	  return false;
	}

      ptr += len;
    }

  return true;
}

// Returns true if the string is valid UTF-16
[[nodiscard]] inline bool
is_valid_utf16 (std::u16string_view str) noexcept
{
  size_t i = 0;

  while (i < str.size ())
    {
      char16_t cu = str[i];

      if (cu >= HIGH_SURROGATE_MIN_16 && cu <= HIGH_SURROGATE_MAX_16)
	{
	  if (i + 1 >= str.size ())
	    return false;
	  char16_t cu2 = str[i + 1];
	  if (cu2 < LOW_SURROGATE_MIN_16
	      || cu2 > LOW_SURROGATE_MAX_16)
	    return false;
	  i += 2;
	}
      else if (cu >= LOW_SURROGATE_MIN_16
	       && cu <= LOW_SURROGATE_MAX_16)
	{
	  return false;
	}
      else
	{
	  ++i;
	}
    }

  return true;
}

// =============================================================================
// Additional Utilities
// =============================================================================

// Count the number of code points in a UTF-8 string
[[nodiscard]] inline size_t
utf8_codepoint_count (std::string_view utf8) noexcept
{
  size_t count = 0;
  const char *ptr = utf8.data ();
  const char *end = ptr + utf8.size ();

  while (ptr < end)
    {
      unsigned char byte = static_cast<unsigned char> (*ptr);
      // Count lead bytes (anything that's not a continuation byte)
      if ((byte & 0xC0) != 0x80)
	++count;
      ++ptr;
    }

  return count;
}

// Count the number of code points in a UTF-16 string
[[nodiscard]] inline size_t
utf16_codepoint_count (std::u16string_view utf16) noexcept
{
  size_t count = 0;
  size_t i = 0;

  while (i < utf16.size ())
    {
      char16_t cu = utf16[i];
      ++count;

      if (cu >= HIGH_SURROGATE_MIN_16 && cu <= HIGH_SURROGATE_MAX_16
	  && i + 1 < utf16.size ())
	{
	  char16_t cu2 = utf16[i + 1];
	  if (cu2 >= LOW_SURROGATE_MIN_16
	      && cu2 <= LOW_SURROGATE_MAX_16)
	    ++i;
	}
      ++i;
    }

  return count;
}

// =============================================================================
// Character Property Stubs (Require ICU for Full Unicode Support)
// =============================================================================

// NOTE: Full Unicode character properties require the ICU library.
// These stubs are provided for basic ASCII compatibility only.
// For proper Unicode support, use ICU's u_isalpha(), u_isdigit(),
// etc.
//
// Example ICU usage:
//   #include <unicode/uchar.h>
//   bool is_letter = u_isalpha(codepoint);
//   bool is_upper = u_isupper(codepoint);
//   char32_t lower = u_tolower(codepoint);
//
// The following functions ONLY work correctly for ASCII (0-127).
// They return false/unchanged for non-ASCII code points.

// ASCII-only: returns true if cp is an ASCII letter
[[nodiscard]] inline bool
is_ascii_letter (char32_t cp) noexcept
{
  return (cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z');
}

// ASCII-only: returns true if cp is an ASCII digit
[[nodiscard]] inline bool
is_ascii_digit (char32_t cp) noexcept
{
  return cp >= '0' && cp <= '9';
}

// ASCII-only: returns true if cp is an ASCII uppercase letter
[[nodiscard]] inline bool
is_ascii_upper (char32_t cp) noexcept
{
  return cp >= 'A' && cp <= 'Z';
}

// ASCII-only: returns true if cp is an ASCII lowercase letter
[[nodiscard]] inline bool
is_ascii_lower (char32_t cp) noexcept
{
  return cp >= 'a' && cp <= 'z';
}

// ASCII-only: convert to lowercase (non-ASCII unchanged)
[[nodiscard]] inline char32_t
to_ascii_lower (char32_t cp) noexcept
{
  if (cp >= 'A' && cp <= 'Z')
    return cp + ('a' - 'A');
  return cp;
}

// ASCII-only: convert to uppercase (non-ASCII unchanged)
[[nodiscard]] inline char32_t
to_ascii_upper (char32_t cp) noexcept
{
  if (cp >= 'a' && cp <= 'z')
    return cp - ('a' - 'A');
  return cp;
}

} // namespace emacs::gnulib
