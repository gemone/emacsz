// src/regex.hpp
#pragma once

#include <cstring>
#include <regex>
#include <string>
#include <string_view>
#include <vector>

namespace emacs
{

/**
 * Regular expression utilities - C++20 std::regex replacements for
 * gnulib
 *
 * Replaces:
 * - regcomp() → std::regex constructor
 * - regexec() → std::regex_search() for pattern matching
 * - regfree() → std::regex destructor (automatic)
 *
 * Uses:
 * - std::regex exclusively (no POSIX regex.h functions)
 */

struct EmacsRegex
{
  std::regex pattern;
  std::string error_msg;

  EmacsRegex () = default;
  explicit EmacsRegex (const std::string &p, int flags = 0);
};

struct RegexMatch
{
  size_t rm_so;
  size_t rm_eo;

  RegexMatch () : rm_so (0), rm_eo (0) {}
};

class RegexUtils
{
public:
  RegexUtils () noexcept = default;
  ~RegexUtils () noexcept = default;

  // regcomp() - compile regex pattern
  [[nodiscard]] static int regcomp (EmacsRegex *preg,
				    const char *pattern,
				    int cflags) noexcept;

  // regexec() - execute regex match
  [[nodiscard]] static int regexec (const EmacsRegex *preg,
				    const char *string, size_t nmatch,
				    RegexMatch pmatch[],
				    int eflags) noexcept;

  // regfree() - free compiled regex (no-op, automatic RAII)
  static void regfree (EmacsRegex *preg) noexcept;
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // regcomp() - compile regex pattern
  int emacs_regcomp (emacs::EmacsRegex *preg, const char *pattern,
		     int cflags);

  // regexec() - execute regex match
  int emacs_regexec (const emacs::EmacsRegex *preg,
		     const char *string, size_t nmatch,
		     emacs::RegexMatch pmatch[], int eflags);

  // regfree() - free compiled regex
  void emacs_regfree (emacs::EmacsRegex *preg);
}
