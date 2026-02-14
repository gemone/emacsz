// src/strings.hpp
// C++20 string utilities replacing gnulib functions
//
// This header provides modern C++20 string utilities to replace
// gnulib dependencies while maintaining compatibility with existing C
// code.
//
// Replacements provided:
// - strdup() -> std::string(char*)
// - strndup() -> std::string(data, n)
// - stpcpy() -> std::strcpy() + manual +1
// - strnlen() -> custom implementation
// - asprintf() -> std::format() (C++20)

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <format>
#include <fstream>
#include <string>
#include <string_view>

namespace emacs::strings
{

/**
 * Duplicate a null-terminated string
 *
 * Replaces: gnulib strdup()
 *
 * @param s String to duplicate
 * @return std::string copy of input
 */
[[nodiscard]] inline std::string
string_duplicate (const char *s)
{
  return std::string (s);
}

/**
 * Duplicate a string with length limit
 *
 * Replaces: gnulib strndup()
 *
 * @param s String to duplicate
 * @param n Maximum length
 * @return std::string copy of first n characters
 */
[[nodiscard]] inline std::string
string_duplicate_n (const char *s, size_t n)
{
  return std::string (s, n);
}

/**
 * Copy string with null terminator
 *
 * Replaces: gnulib stpcpy()
 *
 * @param dest Destination buffer
 * @param src Source string
 * @return Pointer to end of destination (dest + strlen(src))
 *
 * @note Returns pointer to the null terminator in dest
 */
[[nodiscard]] inline char *
string_copy (char *dest, const char *src)
{
  size_t len = std::strlen (src);
  std::memcpy (dest, src, len + 1);
  return dest + len;
}

/**
 * Get string length with maximum limit
 *
 * Replaces: gnulib strnlen()
 *
 * @param s String to measure
 * @param max_len Maximum length to consider (safety)
 * @return Length of string, up to max_len
 */
[[nodiscard]] inline size_t
string_length_n (const char *s, size_t max_len)
{
  const char *end
    = static_cast<const char *> (std::memchr (s, '\0', max_len));
  return end ? static_cast<size_t> (end - s) : max_len;
}

/**
 * Get string length
 *
 * @param s String to measure
 * @return Length of string
 */
[[nodiscard]] inline size_t
string_length (const char *s)
{
  return std::strlen (s);
}

template <typename... Args>
[[nodiscard]] inline std::string
string_format ([[maybe_unused]] std::string_view fmt,
	       [[maybe_unused]] Args &&...args)
{
#if __cpp_lib_format >= 201907L
  return std::format (std::string (fmt),
		      std::forward<Args> (args)...);
#else
  return std::string (fmt);
#endif
}

inline bool
read_line (std::istream &stream, std::string &line)
{
  line.clear ();
  return static_cast<bool> (std::getline (stream, line));
}

/**
 * Read line from FILE* (C-style)
 *
 * @param fp C file pointer
 * @param line String to read into
 * @return true if successful, false on EOF
 */
inline bool
read_line_c (std::FILE *fp, std::string &line)
{
  line.clear ();
  int ch;
  while ((ch = std::fgetc (fp)) != EOF && ch != '\n')
    {
      line.push_back (static_cast<char> (ch));
    }
  return ch != EOF || !line.empty ();
}

} // namespace emacs::strings
