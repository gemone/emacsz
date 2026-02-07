// src/regex.cpp
#include <cstring>
#include <regex>

#include "regex.hpp"

namespace emacs
{

RegexUtils::RegexUtils () {}

RegexUtils::~RegexUtils () {}

int
RegexUtils::regcomp (const char *pattern, int cflags,
		     std::regex_t **preg) noexcept
{
  std::memset (preg, 0, sizeof (std::regex_t));
  return std::regex::regex_comp (pattern, cflags, preg);
}

int
RegexUtils::regexec (const std::regex_t *preg, const char *string,
		     size_t nmatch, std::regex::regmatch_t pmatch[],
		     size_t n) noexcept
{
  return std::regex::regex_search (string, n, pmatch);
}

void
RegexUtils::regfree (std::regex_t *preg) noexcept
{
  std::regex::regex_free (preg);
}

} // namespace emacs
