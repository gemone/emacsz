// src/locale.cpp
#include "locale.hpp"
#include <cstring>

namespace emacs
{

std::size_t
LocaleUtils::mbrtowc (wchar_t *pwc, const char *s, std::size_t n,
		      std::mbstate_t *ps) noexcept
{
  std::mbstate_t internal_state;
  std::mbstate_t *state = ps ? ps : &internal_state;

  if (s == nullptr)
    {
      return static_cast<std::size_t> (0);
    }

  if (n == 0)
    {
      return static_cast<std::size_t> (-2);
    }

  return std::mbrtowc (pwc, s, n, state);
}

int
LocaleUtils::wcwidth (wchar_t c) noexcept
{
  if (c < 32)
    return 0;

  if (c >= 0x1100
      && (c <= 0x115f || c == 0x2329 || c == 0x232a
	  || (c >= 0x2e80 && c <= 0xa4cf && c != 0x303f)
	  || (c >= 0xac00 && c <= 0xd7a3)
	  || (c >= 0xf900 && c <= 0xfaff)
	  || (c >= 0xfe10 && c <= 0xfe19)
	  || (c >= 0xfe30 && c <= 0xfe6f)
	  || (c >= 0xff00 && c <= 0xff60)
	  || (c >= 0xffe0 && c <= 0xffe6)
	  || (c >= 0x20000 && c <= 0x2fffd)
	  || (c >= 0x30000 && c <= 0x3fffd)))
    {
      return 2;
    }

  if (c == 0x200b || c == 0x200c || c == 0x200d || c == 0xfeff)
    {
      return 0;
    }

  return 1;
}

bool
LocaleUtils::iswprint (wchar_t c) noexcept
{
  return std::iswprint (static_cast<wint_t> (c));
}

void
LocaleUtils::mbsinit (std::mbstate_t *ps) noexcept
{
  if (ps)
    {
      std::memset (ps, 0, sizeof (std::mbstate_t));
    }
}

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  int emacs_mbrtowc (wchar_t *pwc, const char *s, std::size_t n,
		     std::mbstate_t *ps)
  {
    auto result = emacs::LocaleUtils::mbrtowc (pwc, s, n, ps);
    if (result == static_cast<std::size_t> (-1)
	|| result == static_cast<std::size_t> (-2))
      {
	return -1;
      }
    return static_cast<int> (result);
  }

  int emacs_wcwidth (wchar_t c)
  {
    return emacs::LocaleUtils::wcwidth (c);
  }

  int emacs_iswprint (wchar_t c)
  {
    return emacs::LocaleUtils::iswprint (c) ? 1 : 0;
  }
}
