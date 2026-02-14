// src/gnulib/wchar_utils.hpp
// C++20 replacements for gnulib wide character handling
// Replaces: wchar-h, wcrtomb, wcsrtombs, mbrtowc, mbsrtowcs

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstring>
#include <cwchar>
#include <string>
#include <string_view>

#if __has_include(<cuchar>)
# include <cuchar>
#endif

// macOS includes <cuchar> but marks c16rtomb/mbrtoc16 as unavailable
#if defined(__cpp_lib_char8_t) && __cpp_lib_char8_t >= 201907L
# if !defined(__APPLE__) && !defined(__MACH__)
#  define EMACS_HAVE_C16_FUNCS 1
# endif
#endif

#ifndef EMACS_HAVE_C16_FUNCS
# define EMACS_HAVE_C16_FUNCS 0
#endif

namespace emacs::gnulib
{

#ifdef _WIN32
constexpr bool wchar_is_utf16 = true;
constexpr bool wchar_is_utf32 = false;
constexpr size_t wchar_size = 2;
#else
constexpr bool wchar_is_utf16 = false;
constexpr bool wchar_is_utf32 = true;
constexpr size_t wchar_size = 4;
#endif

constexpr size_t mb_cur_max_safe = MB_LEN_MAX;

[[nodiscard]] inline size_t
mbrtowc_safe (wchar_t *pwc, const char *s, size_t n,
	      std::mbstate_t *ps) noexcept
{
  if (!s)
    {
      std::mbstate_t internal_state{};
      if (!ps)
	ps = &internal_state;
      *ps = std::mbstate_t{};
      return 0;
    }

  if (n == 0)
    return static_cast<size_t> (-2);

  std::mbstate_t internal_state{};
  if (!ps)
    ps = &internal_state;

  return std::mbrtowc (pwc, s, n, ps);
}

[[nodiscard]] inline size_t
mbtowc_safe (wchar_t *pwc, const char *s, size_t n) noexcept
{
  if (!s)
    {
      std::mbtowc (nullptr, nullptr, 0);
      return 0;
    }

  if (n == 0)
    return static_cast<size_t> (-1);

  int result = std::mbtowc (pwc, s, n);
  return result < 0 ? static_cast<size_t> (-1)
		    : static_cast<size_t> (result);
}

[[nodiscard]] inline int
mblen_safe (const char *s, size_t n) noexcept
{
  if (!s)
    {
      std::mblen (nullptr, 0);
      return 0;
    }

  if (n == 0)
    return -1;

  return std::mblen (s, n);
}

[[nodiscard]] inline size_t
wcrtomb_safe (char *s, wchar_t wc, std::mbstate_t *ps) noexcept
{
  std::mbstate_t internal_state{};
  if (!ps)
    ps = &internal_state;

  if (!s)
    {
      char buf[MB_LEN_MAX];
      return std::wcrtomb (buf, L'\0', ps);
    }

  return std::wcrtomb (s, wc, ps);
}

[[nodiscard]] inline int
wctomb_safe (char *s, wchar_t wc) noexcept
{
  if (!s)
    {
      std::wctomb (nullptr, L'\0');
      return 0;
    }

  return std::wctomb (s, wc);
}

[[nodiscard]] inline size_t
mbsrtowcs_safe (wchar_t *dst, const char **src, size_t len,
		std::mbstate_t *ps) noexcept
{
  if (!src || !*src)
    return 0;

  std::mbstate_t internal_state{};
  if (!ps)
    ps = &internal_state;

  return std::mbsrtowcs (dst, src, len, ps);
}

[[nodiscard]] inline size_t
wcsrtombs_safe (char *dst, const wchar_t **src, size_t len,
		std::mbstate_t *ps) noexcept
{
  if (!src || !*src)
    return 0;

  std::mbstate_t internal_state{};
  if (!ps)
    ps = &internal_state;

  return std::wcsrtombs (dst, src, len, ps);
}

[[nodiscard]] inline std::wstring
to_wstring (std::string_view str)
{
  if (str.empty ())
    return {};

  std::wstring result;
  result.reserve (str.size ());

  std::mbstate_t state{};
  const char *src = str.data ();
  const char *end = src + str.size ();

  wchar_t wc;
  while (src < end)
    {
      size_t len
	= std::mbrtowc (&wc, src, static_cast<size_t> (end - src),
			&state);

      if (len == 0)
	break;
      else if (len == static_cast<size_t> (-1))
	{
	  result.push_back (L'\uFFFD');
	  ++src;
	  state = std::mbstate_t{};
	}
      else if (len == static_cast<size_t> (-2))
	{
	  result.push_back (L'\uFFFD');
	  break;
	}
      else
	{
	  result.push_back (wc);
	  src += len;
	}
    }

  return result;
}

[[nodiscard]] inline std::string
to_string (std::wstring_view wstr)
{
  if (wstr.empty ())
    return {};

  std::string result;
  result.reserve (wstr.size () * MB_LEN_MAX);

  std::mbstate_t state{};
  char buf[MB_LEN_MAX];

  for (wchar_t wc : wstr)
    {
      size_t len = std::wcrtomb (buf, wc, &state);

      if (len == static_cast<size_t> (-1))
	{
	  result.push_back ('?');
	  state = std::mbstate_t{};
	}
      else
	{
	  result.append (buf, len);
	}
    }

  return result;
}

namespace detail
{

[[nodiscard]] inline std::pair<char32_t, size_t>
decode_utf8 (const char *s, size_t len) noexcept
{
  if (len == 0)
    return { 0, 0 };

  unsigned char c = static_cast<unsigned char> (s[0]);

  if (c < 0x80)
    return { c, 1 };

  if ((c & 0xE0) == 0xC0 && len >= 2)
    {
      unsigned char c1 = static_cast<unsigned char> (s[1]);
      if ((c1 & 0xC0) != 0x80)
	return { 0xFFFD, 1 };
      char32_t cp = ((c & 0x1F) << 6) | (c1 & 0x3F);
      if (cp < 0x80)
	return { 0xFFFD, 2 };
      return { cp, 2 };
    }

  if ((c & 0xF0) == 0xE0 && len >= 3)
    {
      unsigned char c1 = static_cast<unsigned char> (s[1]);
      unsigned char c2 = static_cast<unsigned char> (s[2]);
      if ((c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80)
	return { 0xFFFD, 1 };
      char32_t cp
	= ((c & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F);
      if (cp < 0x800)
	return { 0xFFFD, 3 };
      if (cp >= 0xD800 && cp <= 0xDFFF)
	return { 0xFFFD, 3 };
      return { cp, 3 };
    }

  if ((c & 0xF8) == 0xF0 && len >= 4)
    {
      unsigned char c1 = static_cast<unsigned char> (s[1]);
      unsigned char c2 = static_cast<unsigned char> (s[2]);
      unsigned char c3 = static_cast<unsigned char> (s[3]);
      if ((c1 & 0xC0) != 0x80 || (c2 & 0xC0) != 0x80
	  || (c3 & 0xC0) != 0x80)
	return { 0xFFFD, 1 };
      char32_t cp = ((c & 0x07) << 18) | ((c1 & 0x3F) << 12)
		    | ((c2 & 0x3F) << 6) | (c3 & 0x3F);
      if (cp < 0x10000 || cp > 0x10FFFF)
	return { 0xFFFD, 4 };
      return { cp, 4 };
    }

  return { 0xFFFD, 1 };
}

inline size_t
encode_utf8 (char32_t cp, char *buf) noexcept
{
  if (cp < 0x80)
    {
      buf[0] = static_cast<char> (cp);
      return 1;
    }

  if (cp < 0x800)
    {
      buf[0] = static_cast<char> (0xC0 | (cp >> 6));
      buf[1] = static_cast<char> (0x80 | (cp & 0x3F));
      return 2;
    }

  if (cp < 0x10000)
    {
      if (cp >= 0xD800 && cp <= 0xDFFF)
	{
	  buf[0] = '\xEF';
	  buf[1] = '\xBF';
	  buf[2] = '\xBD';
	  return 3;
	}
      buf[0] = static_cast<char> (0xE0 | (cp >> 12));
      buf[1] = static_cast<char> (0x80 | ((cp >> 6) & 0x3F));
      buf[2] = static_cast<char> (0x80 | (cp & 0x3F));
      return 3;
    }

  if (cp <= 0x10FFFF)
    {
      buf[0] = static_cast<char> (0xF0 | (cp >> 18));
      buf[1] = static_cast<char> (0x80 | ((cp >> 12) & 0x3F));
      buf[2] = static_cast<char> (0x80 | ((cp >> 6) & 0x3F));
      buf[3] = static_cast<char> (0x80 | (cp & 0x3F));
      return 4;
    }

  buf[0] = '\xEF';
  buf[1] = '\xBF';
  buf[2] = '\xBD';
  return 3;
}

}

[[nodiscard]] inline std::u16string
to_u16string (std::string_view utf8_str)
{
  if (utf8_str.empty ())
    return {};

  std::u16string result;
  result.reserve (utf8_str.size ());

  const char *src = utf8_str.data ();
  const char *end = src + utf8_str.size ();

  while (src < end)
    {
      auto [cp, len]
	= detail::decode_utf8 (src, static_cast<size_t> (end - src));
      if (len == 0)
	break;

      if (cp <= 0xFFFF)
	{
	  result.push_back (static_cast<char16_t> (cp));
	}
      else if (cp <= 0x10FFFF)
	{
	  cp -= 0x10000;
	  result.push_back (
	    static_cast<char16_t> (0xD800 | (cp >> 10)));
	  result.push_back (
	    static_cast<char16_t> (0xDC00 | (cp & 0x3FF)));
	}
      else
	{
	  result.push_back (u'\uFFFD');
	}

      src += len;
    }

  return result;
}

[[nodiscard]] inline std::u32string
to_u32string (std::string_view utf8_str)
{
  if (utf8_str.empty ())
    return {};

  std::u32string result;
  result.reserve (utf8_str.size ());

  const char *src = utf8_str.data ();
  const char *end = src + utf8_str.size ();

  while (src < end)
    {
      auto [cp, len]
	= detail::decode_utf8 (src, static_cast<size_t> (end - src));
      if (len == 0)
	break;

      result.push_back (cp);
      src += len;
    }

  return result;
}

[[nodiscard]] inline std::string
from_u16string (std::u16string_view str)
{
  if (str.empty ())
    return {};

  std::string result;
  result.reserve (str.size () * 3);

  const char16_t *src = str.data ();
  const char16_t *end = src + str.size ();
  char buf[4];

  while (src < end)
    {
      char32_t cp = *src++;

      if (cp >= 0xD800 && cp <= 0xDBFF && src < end)
	{
	  char16_t low = *src;
	  if (low >= 0xDC00 && low <= 0xDFFF)
	    {
	      cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
	      ++src;
	    }
	  else
	    {
	      cp = 0xFFFD;
	    }
	}
      else if (cp >= 0xDC00 && cp <= 0xDFFF)
	{
	  cp = 0xFFFD;
	}

      size_t len = detail::encode_utf8 (cp, buf);
      result.append (buf, len);
    }

  return result;
}

[[nodiscard]] inline std::string
from_u32string (std::u32string_view str)
{
  if (str.empty ())
    return {};

  std::string result;
  result.reserve (str.size () * 4);

  char buf[4];

  for (char32_t cp : str)
    {
      size_t len = detail::encode_utf8 (cp, buf);
      result.append (buf, len);
    }

  return result;
}

[[nodiscard]] inline bool
is_valid_wchar (wchar_t wc) noexcept
{
#ifdef _WIN32
  return true;
#else
  if (static_cast<char32_t> (wc) > 0x10FFFF)
    return false;
  if (static_cast<char32_t> (wc) >= 0xD800
      && static_cast<char32_t> (wc) <= 0xDFFF)
    return false;
  return true;
#endif
}

[[nodiscard]] inline int
wcwidth_safe (wchar_t wc) noexcept
{
  if (wc == 0)
    return 0;

  if (wc < 32 || (wc >= 0x7F && wc < 0xA0))
    return -1;

  if (wc >= 0x0300 && wc <= 0x036F)
    return 0;

#ifdef _WIN32
  if ((wc >= 0x1100 && wc <= 0x115F) || wc == 0x2329 || wc == 0x232A
      || (wc >= 0x2E80 && wc <= 0xA4CF)
      || (wc >= 0xAC00 && wc <= 0xD7A3)
      || (wc >= 0xF900 && wc <= 0xFAFF)
      || (wc >= 0xFE10 && wc <= 0xFE1F)
      || (wc >= 0xFE30 && wc <= 0xFE6F)
      || (wc >= 0xFF00 && wc <= 0xFF60)
      || (wc >= 0xFFE0 && wc <= 0xFFE6))
    return 2;
#else
  char32_t cp = static_cast<char32_t> (wc);
  if ((cp >= 0x1100 && cp <= 0x115F) || cp == 0x2329 || cp == 0x232A
      || (cp >= 0x2E80 && cp <= 0xA4CF && cp != 0x303F)
      || (cp >= 0xAC00 && cp <= 0xD7A3)
      || (cp >= 0xF900 && cp <= 0xFAFF)
      || (cp >= 0xFE10 && cp <= 0xFE1F)
      || (cp >= 0xFE30 && cp <= 0xFE6F)
      || (cp >= 0xFF00 && cp <= 0xFF60)
      || (cp >= 0xFFE0 && cp <= 0xFFE6)
      || (cp >= 0x20000 && cp <= 0x2FFFD)
      || (cp >= 0x30000 && cp <= 0x3FFFD))
    return 2;
#endif

  return 1;
}

[[nodiscard]] inline size_t
wcswidth_safe (const wchar_t *s, size_t n) noexcept
{
  if (!s)
    return 0;

  size_t width = 0;
  for (size_t i = 0; i < n && s[i]; ++i)
    {
      int w = wcwidth_safe (s[i]);
      if (w < 0)
	return static_cast<size_t> (-1);
      width += static_cast<size_t> (w);
    }
  return width;
}

inline void
mbstate_reset (std::mbstate_t &state) noexcept
{
  state = std::mbstate_t{};
}

[[nodiscard]] inline bool
mbstate_is_initial (const std::mbstate_t &state) noexcept
{
  return std::mbsinit (&state) != 0;
}

}
