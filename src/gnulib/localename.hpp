// src/gnulib/localename.hpp
// C++20 replacements for gnulib locale name utilities
// Replaces: localename, setlocale-null

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cassert>
#include <clocale>
#include <cstddef>
#include <cstring>
#include <mutex>
#include <optional>
#include <string>

#ifdef _WIN32
# include <windows.h>
# if __has_include(<winnls.h>)
#  include <winnls.h>
# endif
#else
# include <locale.h>
# if __has_include(<xlocale.h>)
#  include <xlocale.h>
# endif
#endif

namespace emacs::gnulib
{

// Thread-local cache for locale names (performance optimization)
namespace detail
{
#ifdef _WIN32
// Windows locale code to POSIX locale name mapping
[[nodiscard]] inline std::optional<std::string>
windows_lcid_to_locale (LCID lcid)
{
  // Common Windows LCID to POSIX locale mappings
  const auto lcid_base = PRIMARYLANGID (lcid);
  const auto lcid_sublang = SUBLANGID (lcid);

  // This is a simplified mapping - a real implementation would be
  // more comprehensive
  switch (lcid_base)
    {
    case LANG_ENGLISH:
      if (lcid_sublang == SUBLANG_ENGLISH_US)
	return "en_US";
      if (lcid_sublang == SUBLANG_ENGLISH_UK)
	return "en_GB";
      return "en";
    case LANG_FRENCH:
      return "fr_FR";
    case LANG_GERMAN:
      return "de_DE";
    case LANG_SPANISH:
      return "es_ES";
    case LANG_ITALIAN:
      return "it_IT";
    case LANG_PORTUGUESE:
      return "pt_PT";
    case LANG_JAPANESE:
      return "ja_JP";
    case LANG_CHINESE:
      if (lcid_sublang == SUBLANG_CHINESE_SIMPLIFIED)
	return "zh_CN";
      if (lcid_sublang == SUBLANG_CHINESE_TRADITIONAL)
	return "zh_TW";
      return "zh";
    default:
      return std::nullopt;
    }
}
#endif

// Get the current thread-specific locale
[[nodiscard]] inline const char *
get_thread_locale_name_impl (int category)
{
#ifdef _WIN32
  // On Windows, use GetThreadLocale for thread-specific locale
  LCID lcid = GetThreadLocale ();
  char buffer[LOCALE_NAME_MAX_LENGTH];
  int count
    = GetLocaleInfoA (lcid, LOCALE_SNAME, buffer, sizeof (buffer));
  if (count > 0)
    {
      static thread_local std::string cached_locale;
      cached_locale = buffer;
      return cached_locale.c_str ();
    }
  return "C";
#else
// On POSIX, uselocale returns the current thread locale or
// LC_GLOBAL_LOCALE
# if defined(LC_GLOBAL_LOCALE)
  locale_t current = uselocale ((locale_t) 0);
  if (current == LC_GLOBAL_LOCALE)
    return nullptr; // No thread-specific locale set
  if (current != (locale_t) 0)
    {
      // Thread-specific locale is set
      const char *name = querylocale (LC_ALL, current);
      if (name)
	return name;
    }
# endif
  return nullptr;
#endif
}

} // namespace detail

// Get the POSIX locale name for a category
[[nodiscard]] inline const char *
gl_locale_name_posix (int category,
		      [[maybe_unused]] const char *categoryname)
{
  // On POSIX systems, use the environment variables or query locale
  const char *locale_name = nullptr;

  // Try environment variables first
  switch (category)
    {
    case LC_ALL:
      locale_name = std::getenv ("LC_ALL");
      if (!locale_name)
	locale_name = std::getenv ("LANG");
      break;
    case LC_COLLATE:
      locale_name = std::getenv ("LC_COLLATE");
      break;
    case LC_CTYPE:
      locale_name = std::getenv ("LC_CTYPE");
      break;
    case LC_MONETARY:
      locale_name = std::getenv ("LC_MONETARY");
      break;
    case LC_NUMERIC:
      locale_name = std::getenv ("LC_NUMERIC");
      break;
    case LC_TIME:
      locale_name = std::getenv ("LC_TIME");
      break;
    case LC_MESSAGES:
      locale_name = std::getenv ("LC_MESSAGES");
      break;
    default:
      break;
    }

  if (locale_name && locale_name[0] != '\0')
    return locale_name;

  // Fall back to LANG
  locale_name = std::getenv ("LANG");
  if (locale_name && locale_name[0] != '\0')
    return locale_name;

  // Default to "C"
  return "C";
}

// Get the thread-specific locale name for a category
[[nodiscard]] inline const char *
gl_locale_name_thread (int category, const char *categoryname)
{
  const char *result = nullptr;

#ifdef _WIN32
  // Windows: use thread-local locale
  (void) categoryname;
  result = detail::get_thread_locale_name_impl (category);
#else
  // POSIX: check for thread-local locale first
  result = detail::get_thread_locale_name_impl (category);
  if (!result)
    {
      // Fall back to POSIX method
      result = gl_locale_name_posix (category, categoryname);
    }
#endif

  return result ? result : "C";
}

// Get the current locale name for a category (primary implementation)
// This queries the actual current locale setting
[[nodiscard]] inline const char *
gl_locale_name (int category, const char *categoryname)
{
  // First, try to get thread-specific locale if available
  const char *result = gl_locale_name_thread (category, categoryname);

  // If we got a result and it's not "C", return it
  if (result && result[0] != '\0' && std::strcmp (result, "C") != 0)
    return result;

  // Fall back to querying the current locale
  result = std::setlocale (category, nullptr);
  if (result && result[0] != '\0')
    return result;

  // Default fallback
  return "C";
}

// Thread-safe setlocale query (returns current locale without
// changing it) This is the core safe function for querying locale
// without side effects
[[nodiscard]] inline const char *
setlocale_null (int category)
{
  // In most implementations, setlocale(category, NULL) is thread-safe
  // and only returns the current locale without changing it
  const char *result = std::setlocale (category, nullptr);
  return result ? result : "C";
}

// Thread-safe setlocale query with buffer (safe buffer version)
// Stores result in provided buffer, returns the count of bytes
// written or -1 on error
[[nodiscard]] inline int
setlocale_null_r (int category, char *buf, size_t bufsize)
{
  if (!buf || bufsize == 0)
    return -1;

  const char *locale = std::setlocale (category, nullptr);
  if (!locale)
    {
      buf[0] = '\0';
      return -1;
    }

  size_t len = std::strlen (locale);
  if (len >= bufsize)
    {
      // Buffer too small
      if (bufsize > 0)
	buf[0] = '\0';
      return -1;
    }

  std::strcpy (buf, locale);
  return static_cast<int> (len);
}

// C++ wrapper: Get current locale name as std::string
[[nodiscard]] inline std::string
get_locale_name (int category = LC_ALL)
{
  const char *name = gl_locale_name (category, nullptr);
  return std::string (name ? name : "C");
}

// C++ wrapper: Get thread-specific locale name as optional<string>
[[nodiscard]] inline std::optional<std::string>
get_thread_locale_name (int category = LC_ALL)
{
  const char *name = detail::get_thread_locale_name_impl (category);
  if (name && name[0] != '\0')
    return std::string (name);
  return std::nullopt;
}

// C++ wrapper: Safe locale query with automatic buffer management
// Returns the current locale name as std::string
[[nodiscard]] inline std::string
query_current_locale (int category = LC_ALL)
{
  return std::string (setlocale_null (category));
}

// Locale category name utilities
[[nodiscard]] inline const char *
locale_category_name (int category) noexcept
{
  switch (category)
    {
    case LC_ALL:
      return "LC_ALL";
    case LC_COLLATE:
      return "LC_COLLATE";
    case LC_CTYPE:
      return "LC_CTYPE";
    case LC_MONETARY:
      return "LC_MONETARY";
    case LC_NUMERIC:
      return "LC_NUMERIC";
    case LC_TIME:
      return "LC_TIME";
#ifdef LC_MESSAGES
    case LC_MESSAGES:
      return "LC_MESSAGES";
#endif
    default:
      return "LC_UNKNOWN";
    }
}

// Locale category ID from name (reverse lookup)
[[nodiscard]] inline int
locale_category_from_name (const char *name) noexcept
{
  if (!name)
    return LC_ALL;

  if (std::strcmp (name, "LC_ALL") == 0)
    return LC_ALL;
  if (std::strcmp (name, "LC_COLLATE") == 0)
    return LC_COLLATE;
  if (std::strcmp (name, "LC_CTYPE") == 0)
    return LC_CTYPE;
  if (std::strcmp (name, "LC_MONETARY") == 0)
    return LC_MONETARY;
  if (std::strcmp (name, "LC_NUMERIC") == 0)
    return LC_NUMERIC;
  if (std::strcmp (name, "LC_TIME") == 0)
    return LC_TIME;
#ifdef LC_MESSAGES
  if (std::strcmp (name, "LC_MESSAGES") == 0)
    return LC_MESSAGES;
#endif

  return -1; // Invalid category
}

// Check if a locale string is valid
[[nodiscard]] inline bool
is_valid_locale_name (const char *locale_name) noexcept
{
  if (!locale_name || locale_name[0] == '\0')
    return false;

  // "C" and "POSIX" are always valid
  if (std::strcmp (locale_name, "C") == 0
      || std::strcmp (locale_name, "POSIX") == 0)
    return true;

  // POSIX locale names typically follow the pattern:
  // language[_territory][.codeset][@modifier]
  // Example: en_US.UTF-8 or ja_JP@utf8
  // For simplicity, we just check that it contains valid characters
  for (const char *p = locale_name; *p; ++p)
    {
      char c = *p;
      if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
	    || (c >= '0' && c <= '9') || c == '_' || c == '.'
	    || c == '@' || c == '-'))
	return false;
    }

  return true;
}

} // namespace emacs::gnulib
