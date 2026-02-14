// src/gnulib/string_utils.hpp
// C++20 replacements for gnulib string functions
// Replaces: strdup, strndup, stpcpy, strnlen, c-ctype, c-strcase,
// getline, dtoastr, strtoimax, nstrftime, filevercmp, etc.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <array>
#include <cctype>
#include <charconv>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>
#include <type_traits>

#if __cpp_lib_format >= 201907L
# include <format>
#endif

namespace emacs::gnulib
{

[[nodiscard]] inline std::string
string_duplicate (const char *s)
{
  return s ? std::string (s) : std::string{};
}

[[nodiscard]] inline std::string
string_duplicate_n (const char *s, size_t n)
{
  if (!s)
    return {};
  size_t len = 0;
  while (len < n && s[len])
    ++len;
  return std::string (s, len);
}

[[nodiscard]] inline char *
stpcpy (char *dest, const char *src) noexcept
{
  while ((*dest++ = *src++))
    ;
  return dest - 1;
}

[[nodiscard]] inline char *
stpncpy (char *dest, const char *src, size_t n) noexcept
{
  char *end = dest + n;
  while (dest < end && *src)
    *dest++ = *src++;
  char *result = dest;
  while (dest < end)
    *dest++ = '\0';
  return result;
}

[[nodiscard]] inline size_t
strnlen (const char *s, size_t maxlen) noexcept
{
  const char *end
    = static_cast<const char *> (std::memchr (s, '\0', maxlen));
  return end ? static_cast<size_t> (end - s) : maxlen;
}

#if __cpp_lib_format >= 201907L
template <typename... Args>
[[nodiscard]] inline std::string
string_format (std::string_view fmt, Args &&...args)
{
  return std::vformat (fmt, std::make_format_args (args...));
}
#else
template <typename... Args>
[[nodiscard]] inline std::string
string_format (std::string_view fmt, [[maybe_unused]] Args &&...args)
{
  return std::string (fmt);
}
#endif

inline bool
read_line (std::istream &stream, std::string &line)
{
  line.clear ();
  return static_cast<bool> (std::getline (stream, line));
}

inline bool
read_line_c (std::FILE *fp, std::string &line)
{
  line.clear ();
  int ch;
  while ((ch = std::fgetc (fp)) != EOF && ch != '\n')
    line.push_back (static_cast<char> (ch));
  return ch != EOF || !line.empty ();
}

[[nodiscard]] inline ssize_t
getline_c (char **lineptr, size_t *n, std::FILE *stream)
{
  if (!lineptr || !n || !stream)
    return -1;

  std::string line;
  if (!read_line_c (stream, line))
    return -1;

  size_t needed = line.size () + 1;
  if (*lineptr == nullptr || *n < needed)
    {
      char *newptr
	= static_cast<char *> (std::realloc (*lineptr, needed));
      if (!newptr)
	return -1;
      *lineptr = newptr;
      *n = needed;
    }

  std::memcpy (*lineptr, line.c_str (), line.size ());
  (*lineptr)[line.size ()] = '\0';
  return static_cast<ssize_t> (line.size ());
}

[[nodiscard]] inline bool
c_isascii (int c) noexcept
{
  return (c & ~0x7f) == 0;
}

[[nodiscard]] inline bool
c_isalpha (int c) noexcept
{
  return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

[[nodiscard]] inline bool
c_isdigit (int c) noexcept
{
  return c >= '0' && c <= '9';
}

[[nodiscard]] inline bool
c_isalnum (int c) noexcept
{
  return c_isalpha (c) || c_isdigit (c);
}

[[nodiscard]] inline bool
c_isspace (int c) noexcept
{
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
	 || c == '\v';
}

[[nodiscard]] inline bool
c_isupper (int c) noexcept
{
  return c >= 'A' && c <= 'Z';
}

[[nodiscard]] inline bool
c_islower (int c) noexcept
{
  return c >= 'a' && c <= 'z';
}

[[nodiscard]] inline bool
c_isxdigit (int c) noexcept
{
  return c_isdigit (c) || (c >= 'A' && c <= 'F')
	 || (c >= 'a' && c <= 'f');
}

[[nodiscard]] inline bool
c_isprint (int c) noexcept
{
  return c >= 0x20 && c <= 0x7e;
}

[[nodiscard]] inline bool
c_isgraph (int c) noexcept
{
  return c > 0x20 && c <= 0x7e;
}

[[nodiscard]] inline bool
c_ispunct (int c) noexcept
{
  return c_isgraph (c) && !c_isalnum (c);
}

[[nodiscard]] inline bool
c_iscntrl (int c) noexcept
{
  return (c >= 0 && c < 0x20) || c == 0x7f;
}

[[nodiscard]] inline bool
c_isblank (int c) noexcept
{
  return c == ' ' || c == '\t';
}

[[nodiscard]] inline int
c_toupper (int c) noexcept
{
  return c_islower (c) ? c - ('a' - 'A') : c;
}

[[nodiscard]] inline int
c_tolower (int c) noexcept
{
  return c_isupper (c) ? c + ('a' - 'A') : c;
}

[[nodiscard]] inline int
c_strcasecmp (const char *s1, const char *s2) noexcept
{
  while (true)
    {
      unsigned char c1
	= static_cast<unsigned char> (c_tolower (*s1++));
      unsigned char c2
	= static_cast<unsigned char> (c_tolower (*s2++));
      if (c1 == '\0' || c1 != c2)
	return c1 - c2;
    }
}

[[nodiscard]] inline int
c_strncasecmp (const char *s1, const char *s2, size_t n) noexcept
{
  while (n-- > 0)
    {
      unsigned char c1
	= static_cast<unsigned char> (c_tolower (*s1++));
      unsigned char c2
	= static_cast<unsigned char> (c_tolower (*s2++));
      if (c1 == '\0' || c1 != c2)
	return c1 - c2;
    }
  return 0;
}

[[nodiscard]] inline bool
streq (const char *s1, const char *s2) noexcept
{
  return std::strcmp (s1, s2) == 0;
}

[[nodiscard]] inline bool
strneq (const char *s1, const char *s2, size_t n) noexcept
{
  return std::strncmp (s1, s2, n) == 0;
}

class string_builder
{
public:
  string_builder () = default;

  string_builder &append (std::string_view sv)
  {
    buffer_.append (sv);
    return *this;
  }

  string_builder &append (char c)
  {
    buffer_.push_back (c);
    return *this;
  }

  string_builder &append (const char *s)
  {
    if (s)
      buffer_.append (s);
    return *this;
  }

  template <typename T> string_builder &append_num (T value)
  {
    if constexpr (std::is_integral_v<T>)
      buffer_.append (std::to_string (value));
    return *this;
  }

  [[nodiscard]] std::string str () const & { return buffer_; }

  [[nodiscard]] std::string str () && { return std::move (buffer_); }

  [[nodiscard]] const char *c_str () const noexcept
  {
    return buffer_.c_str ();
  }

  [[nodiscard]] size_t size () const noexcept
  {
    return buffer_.size ();
  }

  void clear () { buffer_.clear (); }

  void reserve (size_t capacity) { buffer_.reserve (capacity); }

private:
  std::string buffer_;
};

// dtoastr: Convert double to string with specified precision
[[nodiscard]] inline std::string
double_to_string (double value, int precision = 6)
{
  std::array<char, 64> buf;
  auto [ptr, ec]
    = std::to_chars (buf.data (), buf.data () + buf.size (), value,
		     std::chars_format::general, precision);
  if (ec == std::errc{})
    return std::string (buf.data (), ptr);

  std::snprintf (buf.data (), buf.size (), "%.*g", precision, value);
  return std::string (buf.data ());
}

[[nodiscard]] inline int
dtoastr (char *buf, size_t bufsize, [[maybe_unused]] int flags,
	 int precision, double value)
{
  auto [ptr, ec]
    = std::to_chars (buf, buf + bufsize, value,
		     std::chars_format::general, precision);
  if (ec == std::errc{})
    {
      *ptr = '\0';
      return static_cast<int> (ptr - buf);
    }
  return std::snprintf (buf, bufsize, "%.*g", precision, value);
}

// strtoimax: Parse string to intmax_t
[[nodiscard]] inline intmax_t
strtoimax_compat (const char *nptr, char **endptr, int base) noexcept
{
#if defined(_WIN32) && !defined(__MINGW32__)
  return _strtoi64 (nptr, endptr, base);
#else
  return strtoimax (nptr, endptr, base);
#endif
}

[[nodiscard]] inline uintmax_t
strtoumax_compat (const char *nptr, char **endptr, int base) noexcept
{
#if defined(_WIN32) && !defined(__MINGW32__)
  return _strtoui64 (nptr, endptr, base);
#else
  return strtoumax (nptr, endptr, base);
#endif
}

template <typename T>
[[nodiscard]] inline std::pair<T, std::errc>
parse_integer (std::string_view str, int base = 10) noexcept
{
  T value{};
  auto [ptr, ec]
    = std::from_chars (str.data (), str.data () + str.size (), value,
		       base);
  return { value, ec };
}

// nstrftime: Format time with nanosecond support
[[nodiscard]] inline size_t
nstrftime (char *buf, size_t bufsize, const char *fmt,
	   const std::tm *tm, [[maybe_unused]] int ut,
	   [[maybe_unused]] long ns)
{
  return std::strftime (buf, bufsize, fmt, tm);
}

[[nodiscard]] inline std::string
format_time (const std::tm *tm, std::string_view fmt)
{
  std::array<char, 256> buf;
  size_t len = std::strftime (buf.data (), buf.size (),
			      std::string (fmt).c_str (), tm);
  return std::string (buf.data (), len);
}

[[nodiscard]] inline std::string
format_time_now (std::string_view fmt)
{
  std::time_t t = std::time (nullptr);
  return format_time (std::localtime (&t), fmt);
}

// filevercmp: Compare file version strings (natural sort)
namespace detail
{
[[nodiscard]] inline int
compare_version_segment (const char *&s1, const char *&s2) noexcept
{
  while (*s1 == '0')
    ++s1;
  while (*s2 == '0')
    ++s2;

  const char *start1 = s1;
  const char *start2 = s2;

  while (*s1 >= '0' && *s1 <= '9')
    ++s1;
  while (*s2 >= '0' && *s2 <= '9')
    ++s2;

  size_t len1 = static_cast<size_t> (s1 - start1);
  size_t len2 = static_cast<size_t> (s2 - start2);

  if (len1 != len2)
    return len1 < len2 ? -1 : 1;

  while (start1 < s1)
    {
      if (*start1 != *start2)
	return *start1 < *start2 ? -1 : 1;
      ++start1;
      ++start2;
    }
  return 0;
}
} // namespace detail

[[nodiscard]] inline int
filevercmp (const char *s1, const char *s2) noexcept
{
  if (!s1)
    return s2 ? -1 : 0;
  if (!s2)
    return 1;

  while (*s1 && *s2)
    {
      bool is_digit1 = (*s1 >= '0' && *s1 <= '9');
      bool is_digit2 = (*s2 >= '0' && *s2 <= '9');

      if (is_digit1 && is_digit2)
	{
	  int cmp = detail::compare_version_segment (s1, s2);
	  if (cmp != 0)
	    return cmp;
	}
      else if (is_digit1)
	{
	  return 1;
	}
      else if (is_digit2)
	{
	  return -1;
	}
      else
	{
	  unsigned char c1 = static_cast<unsigned char> (*s1++);
	  unsigned char c2 = static_cast<unsigned char> (*s2++);
	  if (c1 != c2)
	    return c1 < c2 ? -1 : 1;
	}
    }

  if (*s1)
    return 1;
  if (*s2)
    return -1;
  return 0;
}

// Natural sort comparator for use with std::sort
struct natural_less
{
  [[nodiscard]] bool operator() (std::string_view a,
				 std::string_view b) const noexcept
  {
    return filevercmp (std::string (a).c_str (),
		       std::string (b).c_str ())
	   < 0;
  }
};

// xstrtol family: safe string to number conversion with range
// checking
template <typename T>
[[nodiscard]] inline bool
safe_strtol (const char *str, T &out, int base = 10) noexcept
{
  static_assert (std::is_integral_v<T>);

  if (!str || !*str)
    return false;

  char *endptr;
  errno = 0;

  long long val;
  if constexpr (std::is_signed_v<T>)
    {
      val = std::strtoll (str, &endptr, base);
    }
  else
    {
      auto uval = std::strtoull (str, &endptr, base);
      val = static_cast<long long> (uval);
    }

  if (errno == ERANGE)
    return false;
  if (endptr == str)
    return false;
  if (val < std::numeric_limits<T>::min ()
      || val > std::numeric_limits<T>::max ())
    return false;

  out = static_cast<T> (val);
  return true;
}

} // namespace emacs::gnulib
