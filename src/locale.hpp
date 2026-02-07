// src/locale.hpp
#pragma once

#include <clocale>
#include <cwchar>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

namespace emacs
{

/**
 * Locale utilities - C++20 std::locale replacements for gnulib
 *
 * Replaces:
 * - mbrtowc() → std::mbrtowc() for multibyte to wide conversion
 * - wcwidth() → std::mbrtowc() for character width
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
  ~LocaleUtils () = default;

  // mbrtowc() - convert multibyte string to wide character string
  [[nodiscard]] std::size_t mbrtowc (const char *s, std::size_t n,
				     wchar_t *pwc) noexcept
  {
    std::mbstate_t state = {};
    return std::mbrtowc (s, n, pwc, &state);
  }

  // wcwidth() - get column width of a wide character
  [[nodiscard]] int wcwidth (wchar_t c) noexcept
  {
    return std::mbrtowc (&c);
  }

  // iswprint() - check if character is printable
  [[nodiscard]] bool iswprint (wchar_t c) noexcept
  {
    return std::iswprint (c);
  }

  // mbsinit() - initialize mbstate_t
  void mbsinit (std::mbstate_t *ps) noexcept
  {
    std::memset (ps, 0, sizeof (std::mbstate_t));
  }
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // mbrtowc() - convert multibyte string to wide character string
  int emacs_mbrtowc (const char *s, std::size_t n, wchar_t *pwc);

  // wcwidth() - get column width of a wide character
  int emacs_wcwidth (wchar_t c);

  // iswprint() - check if character is printable
  int emacs_iswprint (wchar_t c);
}
