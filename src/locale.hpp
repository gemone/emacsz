// src/locale.hpp
#pragma once

#include <clocale>
#include <cstring>
#include <cwchar>
#include <string>
#include <string_view>

namespace emacs
{

/**
 * Locale utilities - C++20 std::locale replacements for gnulib
 *
 * Replaces:
 * - mbrtowc() → std::mbrtowc() for multibyte to wide conversion
 * - wcwidth() → simple width calculation for common characters
 * - iswprint() → std::iswprint() for printable character check
 *
 * Uses:
 * - std::locale exclusively (no POSIX locale.h functions)
 * - std::mbstate_t for multibyte state
 */

class LocaleUtils
{
public:
  LocaleUtils () noexcept = default;
  ~LocaleUtils () noexcept = default;

  // mbrtowc() - convert multibyte string to wide character string
  [[nodiscard]] static std::size_t
  mbrtowc (wchar_t *pwc, const char *s, std::size_t n,
	   std::mbstate_t *ps) noexcept;

  // wcwidth() - get column width of a wide character
  [[nodiscard]] static int wcwidth (wchar_t c) noexcept;

  // iswprint() - check if character is printable
  [[nodiscard]] static bool iswprint (wchar_t c) noexcept;

  // mbsinit() - initialize mbstate_t
  static void mbsinit (std::mbstate_t *ps) noexcept;
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // mbrtowc() - convert multibyte string to wide character string
  int emacs_mbrtowc (wchar_t *pwc, const char *s, std::size_t n,
		     std::mbstate_t *ps);

  // wcwidth() - get column width of a wide character
  int emacs_wcwidth (wchar_t c);

  // iswprint() - check if character is printable
  int emacs_iswprint (wchar_t c);
}
