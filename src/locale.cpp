// src/locale.cpp
#include <clocale>
#include <cstring>
#include <cwchar>

#include "locale.hpp"

namespace emacs
{

LocaleUtils::LocaleUtils () {}

LocaleUtils::~LocaleUtils () {}

std::size_t
LocaleUtils::mbrtowc (const char *s, std::size_t n,
		      wchar_t *pwc) noexcept
{
  std::mbstate_t state = {};
  return std::mbrtowc (s, n, pwc, &state);
}

int
LocaleUtils::wcwidth (wchar_t c) noexcept
{
  return std::mbrtowc (&c);
}

bool
LocaleUtils::iswprint (wchar_t c) noexcept
{
  return std::iswprint (c);
}

void
LocaleUtils::mbsinit (std::mbstate_t *ps) noexcept
{
  std::memset (ps, 0, sizeof (std::mbstate_t));
}

} // namespace emacs
