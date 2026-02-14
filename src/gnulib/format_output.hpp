// src/gnulib/format_output.hpp
// C++20 replacements for gnulib formatted output
// Replaces: vasnprintf, asprintf, vasprintf

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <array>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>

#if __cpp_lib_format >= 201907L
# include <format>
#endif

#ifdef _WIN32
# include <windows.h>
#else
# include <unistd.h>
#endif

namespace emacs::gnulib
{

namespace detail
{

#ifdef _WIN32

[[nodiscard]] inline int
vasprintf_impl (char **strp, const char *fmt, va_list ap) noexcept
{
  if (!strp || !fmt)
    {
      if (strp)
	*strp = nullptr;
      return -1;
    }

  int size = _vscprintf (fmt, ap);
  if (size < 0)
    {
      *strp = nullptr;
      return -1;
    }

  char *buffer = static_cast<char *> (std::malloc (size + 1));
  if (!buffer)
    {
      *strp = nullptr;
      return -1;
    }

  int result = vsnprintf (buffer, size + 1, fmt, ap);
  if (result < 0)
    {
      std::free (buffer);
      *strp = nullptr;
      return -1;
    }

  *strp = buffer;
  return result;
}

#else

[[nodiscard]] inline int
vasprintf_impl (char **strp, const char *fmt, va_list ap) noexcept
{
  return ::vasprintf (strp, fmt, ap);
}

#endif

}

[[nodiscard]] inline int
vasprintf_compat (char **strp, const char *fmt, va_list ap) noexcept
{
  return detail::vasprintf_impl (strp, fmt, ap);
}

[[nodiscard]] inline int
asprintf_compat (char **strp, const char *fmt, ...) noexcept
{
  if (!strp || !fmt)
    {
      if (strp)
	*strp = nullptr;
      return -1;
    }

  va_list ap;
  va_start (ap, fmt);
  int result = vasprintf_compat (strp, fmt, ap);
  va_end (ap);

  return result;
}

inline void
free_asprintf (char *str) noexcept
{
  std::free (str);
}

struct AsprintfDeleter
{
  void operator() (char *p) const noexcept { free_asprintf (p); }
};

using AsprintfPtr = std::unique_ptr<char, AsprintfDeleter>;

[[nodiscard]] inline std::string
vformat_string (const char *fmt, va_list ap)
{
  if (!fmt)
    return {};

  char *buffer = nullptr;
  int result = vasprintf_compat (&buffer, fmt, ap);

  if (result < 0 || !buffer)
    return {};

  AsprintfPtr ptr (buffer);
  return std::string (buffer, result);
}

[[nodiscard]] inline std::string
format_string (const char *fmt, ...) noexcept
{
  if (!fmt)
    return {};

  va_list ap;
  va_start (ap, fmt);

  char *buffer = nullptr;
  int result = vasprintf_compat (&buffer, fmt, ap);
  va_end (ap);

  if (result < 0 || !buffer)
    return {};

  AsprintfPtr ptr (buffer);
  return std::string (buffer, result);
}

#if __cpp_lib_format >= 201907L

template <typename... Args>
[[nodiscard]] inline std::string
format (std::string_view fmt, Args &&...args)
{
  try
    {
      return std::vformat (fmt, std::make_format_args (args...));
    }
  catch (const std::format_error &)
    {
      return std::string (fmt);
    }
}

template <typename... Args>
[[nodiscard]] inline std::string
sformat (std::string_view fmt, Args &&...args) noexcept
{
  try
    {
      return std::vformat (fmt, std::make_format_args (args...));
    }
  catch (...)
    {
      return std::string (fmt);
    }
}

#else

template <typename... Args>
[[nodiscard]] inline std::string
format (std::string_view fmt,
	[[maybe_unused]] Args &&...args) noexcept
{
  return std::string (fmt);
}

template <typename... Args>
[[nodiscard]] inline std::string
sformat (std::string_view fmt,
	 [[maybe_unused]] Args &&...args) noexcept
{
  return std::string (fmt);
}

#endif

[[nodiscard]] inline int
safe_snprintf (char *str, size_t size, const char *fmt, ...) noexcept
{
  if (!str || !fmt || size == 0)
    return -1;

  va_list ap;
  va_start (ap, fmt);
  int result = vsnprintf (str, size, fmt, ap);
  va_end (ap);

  if (result < 0)
    {
      str[0] = '\0';
      return -1;
    }

  if (static_cast<size_t> (result) >= size)
    {
      str[size - 1] = '\0';
      return static_cast<int> (size - 1);
    }

  return result;
}

template <size_t InitialSize = 256>
[[nodiscard]] inline std::string
format_to_string (const char *fmt, ...) noexcept
{
  if (!fmt)
    return {};

  std::string result;
  std::array<char, InitialSize> buffer;

  va_list ap;
  va_start (ap, fmt);

  int needed = vsnprintf (buffer.data (), buffer.size (), fmt, ap);
  va_end (ap);

  if (needed < 0)
    return {};

  if (static_cast<size_t> (needed) < buffer.size ())
    {
      return std::string (buffer.data (), needed);
    }

  result.resize (needed + 1);

  va_start (ap, fmt);
  vsnprintf (&result[0], result.size (), fmt, ap);
  va_end (ap);

  result.pop_back ();
  return result;
}

}
