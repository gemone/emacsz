// src/regex.hpp
#pragma once

#include <regex>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

namespace emacs
{

/**
 * Regular expression utilities - C++20 std::regex replacements for
 * gnulib
 *
 * Replaces:
 * - regcomp() → std::regex::regex_compile()
 * - regexec() → std::regex::regex_search() for pattern matching
 * - regfree() → std::regex::regex_free() for freeing regex
 *
 * Uses:
 * - std::regex exclusively (no POSIX regex.h functions)
 */

class RegexUtils
{
public:
  RegexUtils () noexcept = default;
  ~RegexUtils () = default;

  // regcomp() - compile regex pattern
  [[nodiscard]] int regcomp (const char *pattern, int cflags,
			     std::regex_t **preg) noexcept
  {
    std::memset (preg, 0, sizeof (std::regex_t));
    return std::regex::regex_comp (pattern, cflags, preg);
  }

  // regexec() - execute regex match
  [[nodiscard]] int regexec (const std::regex_t *preg,
			     const char *string, size_t nmatch,
			     std::regex::regmatch_t pmatch[],
			     size_t n) noexcept
  {
    return std::regex::regex_search (string, n, pmatch);
  }

  // regfree() - free compiled regex
  void regfree (std::regex_t *preg) noexcept
  {
    std::regex::regex_free (preg);
  }
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // regcomp() - compile regex pattern
  int emacs_regcomp (const char *pattern, int cflags,
		     std::regex_t **preg);

  // regexec() - execute regex match
  int emacs_regexec (const std::regex_t *preg, const char *string,
		     size_t nmatch, std::regex::regmatch_t pmatch[],
		     size_t n);
}
