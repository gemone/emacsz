// src/regex.cpp
#include <stdexcept>
#include <system_error>
#include "regex.hpp"

namespace emacs
{

EmacsRegex::EmacsRegex (const std::string &p, int flags)
{
  std::regex::flag_type regex_flags = std::regex::ECMAScript;

  if (flags & 1)
    regex_flags |= std::regex::icase;

  try
    {
      pattern = std::regex (p, regex_flags);
    }
  catch (const std::regex_error &e)
    {
      error_msg = e.what ();
    }
}

int
RegexUtils::regcomp (EmacsRegex *preg, const char *pattern,
		     int cflags) noexcept
{
  if (!preg || !pattern)
    {
      return -1;
    }

  try
    {
      new (preg) EmacsRegex (std::string (pattern), cflags);
    }
  catch (...)
    {
      return -1;
    }

  return 0;
}

int
RegexUtils::regexec (const EmacsRegex *preg, const char *string,
		     size_t nmatch, RegexMatch pmatch[],
		     int eflags) noexcept
{
  if (!preg || !string)
    {
      return -1;
    }

  if (!preg->error_msg.empty ())
    {
      return -2;
    }

  std::cmatch matches;

  bool found = std::regex_search (string, matches, preg->pattern);

  if (!found)
    {
      return 1;
    }

  if (nmatch == 0 || !pmatch)
    {
      return 0;
    }

  size_t copy_count = std::min (nmatch, matches.size ());

  for (size_t i = 0; i < copy_count; ++i)
    {
      if (matches[i].matched)
	{
	  pmatch[i].rm_so
	    = static_cast<size_t> (matches[i].first - string);
	  pmatch[i].rm_eo
	    = static_cast<size_t> (matches[i].second - string);
	}
      else
	{
	  pmatch[i].rm_so = static_cast<size_t> (-1);
	  pmatch[i].rm_eo = static_cast<size_t> (-1);
	}
    }

  return 0;
}

void
RegexUtils::regfree (EmacsRegex *preg) noexcept
{
  if (preg)
    {
      preg->~EmacsRegex ();
    }
}

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  int emacs_regcomp (emacs::EmacsRegex *preg, const char *pattern,
		     int cflags)
  {
    return emacs::RegexUtils::regcomp (preg, pattern, cflags);
  }

  int emacs_regexec (const emacs::EmacsRegex *preg,
		     const char *string, size_t nmatch,
		     emacs::RegexMatch pmatch[], int eflags)
  {
    return emacs::RegexUtils::regexec (preg, string, nmatch, pmatch,
				       eflags);
  }

  void emacs_regfree (emacs::EmacsRegex *preg)
  {
    emacs::RegexUtils::regfree (preg);
  }
}
