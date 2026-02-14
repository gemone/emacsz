// src/gnulib/regex_utils.hpp
// C++20 replacement for gnulib regex module
//
// Replaces: regex (gnulib/POSIX regex)
//
// This module provides a C++20 wrapper around <regex> that offers
// compatibility with gnulib's regex interface while leveraging
// modern C++ features.

#pragma once

#include <algorithm>
#include <cstring>
#include <memory>
#include <optional>
#include <regex>
#include <string>
#include <string_view>
#include <vector>

#if __has_include(<span>)
# include <span>
#else
// Fallback span implementation for older compilers
namespace std
{
template <typename T> class span
{
public:
  span (T *ptr, std::size_t size) : ptr_ (ptr), size_ (size) {}
  T *data () const noexcept { return ptr_; }
  std::size_t size () const noexcept { return size_; }
  T *begin () const noexcept { return ptr_; }
  T *end () const noexcept { return ptr_ + size_; }
  T &operator[] (std::size_t i) const noexcept { return ptr_[i]; }

private:
  T *ptr_;
  std::size_t size_;
};
} // namespace std
#endif

namespace emacs::gnulib
{

// POSIX regex compatibility flags (matching gnulib/POSIX definitions)
namespace regex_flags
{
// Compilation flags
constexpr int REG_EXTENDED
  = 1;			     // Use POSIX Extended Regular Expressions
constexpr int REG_ICASE = 2; // Ignore case in match
constexpr int REG_NOSUB = 4; // Report only success/fail in regexec()
constexpr int REG_NEWLINE = 8; // Treat newline as special

// Execution flags
constexpr int REG_NOTBOL = 1; // ^ doesn't match beginning of string
constexpr int REG_NOTEOL = 2; // $ doesn't match end of string
} // namespace regex_flags

// POSIX regex error codes
enum class regex_error : int
{
  REG_NOERROR = 0, // Success
  REG_NOMATCH = 1, // No match
  REG_BADPAT = 2,  // Invalid pattern
  REG_ECOLLATE = 3,
  REG_ECTYPE = 4,
  REG_EESCAPE = 5, // Trailing backslash
  REG_ESUBREG = 6, // Invalid back reference
  REG_EBRACK = 7,  // Unmatched [
  REG_EPAREN = 8,  // Unmatched (
  REG_EBRACE = 9,  // Unmatched {
  REG_BADBR = 10,  // Invalid content of {}
  REG_ERANGE = 11, // Invalid range end
  REG_ESPACE = 12, // Out of memory
  REG_BADRPT = 13, // Invalid preceding regular expression
  REG_EEND = 14,
  REG_ESIZE = 15,
  REG_ERPAREN = 16
};

// Match result structure (POSIX regmatch_t compatible)
struct regex_match_t
{
  std::ptrdiff_t rm_so; // Start offset
  std::ptrdiff_t rm_eo; // End offset

  [[nodiscard]] bool matched () const noexcept { return rm_so >= 0; }

  [[nodiscard]] std::size_t length () const noexcept
  {
    return matched () ? static_cast<std::size_t> (rm_eo - rm_so) : 0;
  }
};

// C++20 regex wrapper class
class Regex
{
public:
  Regex () = default;

  // Compile a regex pattern
  [[nodiscard]] regex_error compile (std::string_view pattern,
				     int flags = 0) noexcept
  {
    try
      {
	std::regex_constants::syntax_option_type syntax_flags
	  = std::regex_constants::ECMAScript;

	// Convert POSIX flags to std::regex flags
	if (flags & regex_flags::REG_EXTENDED)
	  {
	    syntax_flags = std::regex_constants::extended;
	  }
	if (flags & regex_flags::REG_ICASE)
	  {
	    syntax_flags |= std::regex_constants::icase;
	  }
	if (flags & regex_flags::REG_NOSUB)
	  {
	    syntax_flags |= std::regex_constants::nosubs;
	  }

	regex_ = std::regex (pattern.begin (), pattern.end (),
			     syntax_flags);
	pattern_ = std::string (pattern);
	nosub_ = (flags & regex_flags::REG_NOSUB) != 0;
	compiled_ = true;
	return regex_error::REG_NOERROR;
      }
    catch (const std::regex_error &e)
      {
	compiled_ = false;
	return translate_error (e.code ());
      }
  }

  // Execute regex match
  [[nodiscard]] regex_error exec (std::string_view str,
				  std::span<regex_match_t> matches,
				  int flags = 0) const noexcept
  {
    if (!compiled_)
      return regex_error::REG_BADPAT;

    try
      {
	std::regex_constants::match_flag_type match_flags
	  = std::regex_constants::match_default;

	if (flags & regex_flags::REG_NOTBOL)
	  {
	    match_flags |= std::regex_constants::match_not_bol;
	  }
	if (flags & regex_flags::REG_NOTEOL)
	  {
	    match_flags |= std::regex_constants::match_not_eol;
	  }

	std::cmatch results;
	if (!std::regex_search (str.data (),
				str.data () + str.size (), results,
				regex_, match_flags))
	  {
	    // No match - set all to -1
	    for (auto &m : matches)
	      {
		m.rm_so = -1;
		m.rm_eo = -1;
	      }
	    return regex_error::REG_NOMATCH;
	  }

	// Fill in match results
	std::size_t i = 0;
	for (; i < matches.size () && i < results.size (); ++i)
	  {
	    if (results[i].matched)
	      {
		matches[i].rm_so = results[i].first - str.data ();
		matches[i].rm_eo = results[i].second - str.data ();
	      }
	    else
	      {
		matches[i].rm_so = -1;
		matches[i].rm_eo = -1;
	      }
	  }
	// Clear remaining matches
	for (; i < matches.size (); ++i)
	  {
	    matches[i].rm_so = -1;
	    matches[i].rm_eo = -1;
	  }

	return regex_error::REG_NOERROR;
      }
    catch (const std::regex_error &)
      {
	return regex_error::REG_ESPACE;
      }
  }

  // Simple match check (no subexpression capture)
  [[nodiscard]] bool matches (std::string_view str,
			      int flags = 0) const noexcept
  {
    if (!compiled_)
      return false;

    try
      {
	std::regex_constants::match_flag_type match_flags
	  = std::regex_constants::match_default;

	if (flags & regex_flags::REG_NOTBOL)
	  match_flags |= std::regex_constants::match_not_bol;
	if (flags & regex_flags::REG_NOTEOL)
	  match_flags |= std::regex_constants::match_not_eol;

	return std::regex_search (str.begin (), str.end (), regex_,
				  match_flags);
      }
    catch (...)
      {
	return false;
      }
  }

  // Full match (entire string must match)
  [[nodiscard]] bool full_match (std::string_view str) const noexcept
  {
    if (!compiled_)
      return false;

    try
      {
	return std::regex_match (str.begin (), str.end (), regex_);
      }
    catch (...)
      {
	return false;
      }
  }

  // Get all matches in string
  [[nodiscard]] std::vector<std::string>
  find_all (std::string_view str) const
  {
    std::vector<std::string> results;
    if (!compiled_)
      return results;

    auto begin
      = std::cregex_iterator (str.data (), str.data () + str.size (),
			      regex_);
    auto end = std::cregex_iterator ();

    for (auto it = begin; it != end; ++it)
      {
	results.emplace_back ((*it)[0].str ());
      }

    return results;
  }

  // Replace all matches
  [[nodiscard]] std::string
  replace (std::string_view str, std::string_view replacement) const
  {
    if (!compiled_)
      return std::string (str);

    return std::regex_replace (std::string (str), regex_,
			       std::string (replacement));
  }

  // Replace first match only
  [[nodiscard]] std::string
  replace_first (std::string_view str,
		 std::string_view replacement) const
  {
    if (!compiled_)
      return std::string (str);

    return std::
      regex_replace (std::string (str), regex_,
		     std::string (replacement),
		     std::regex_constants::format_first_only);
  }

  // Get pattern string
  [[nodiscard]] const std::string &pattern () const noexcept
  {
    return pattern_;
  }

  // Check if compiled successfully
  [[nodiscard]] bool is_valid () const noexcept { return compiled_; }

  // Get error message for error code
  [[nodiscard]] static std::string_view
  error_message (regex_error err) noexcept
  {
    switch (err)
      {
      case regex_error::REG_NOERROR:
	return "Success";
      case regex_error::REG_NOMATCH:
	return "No match";
      case regex_error::REG_BADPAT:
	return "Invalid pattern";
      case regex_error::REG_ECOLLATE:
	return "Invalid collating element";
      case regex_error::REG_ECTYPE:
	return "Invalid character class";
      case regex_error::REG_EESCAPE:
	return "Trailing backslash";
      case regex_error::REG_ESUBREG:
	return "Invalid back reference";
      case regex_error::REG_EBRACK:
	return "Unmatched [";
      case regex_error::REG_EPAREN:
	return "Unmatched (";
      case regex_error::REG_EBRACE:
	return "Unmatched {";
      case regex_error::REG_BADBR:
	return "Invalid content of {}";
      case regex_error::REG_ERANGE:
	return "Invalid range end";
      case regex_error::REG_ESPACE:
	return "Out of memory";
      case regex_error::REG_BADRPT:
	return "Invalid preceding regular expression";
      default:
	return "Unknown error";
      }
  }

private:
  std::regex regex_;
  std::string pattern_;
  bool compiled_ = false;
  bool nosub_ = false;

  [[nodiscard]] static regex_error
  translate_error (std::regex_constants::error_type err) noexcept
  {
    switch (err)
      {
      case std::regex_constants::error_collate:
	return regex_error::REG_ECOLLATE;
      case std::regex_constants::error_ctype:
	return regex_error::REG_ECTYPE;
      case std::regex_constants::error_escape:
	return regex_error::REG_EESCAPE;
      case std::regex_constants::error_backref:
	return regex_error::REG_ESUBREG;
      case std::regex_constants::error_brack:
	return regex_error::REG_EBRACK;
      case std::regex_constants::error_paren:
	return regex_error::REG_EPAREN;
      case std::regex_constants::error_brace:
	return regex_error::REG_EBRACE;
      case std::regex_constants::error_badbrace:
	return regex_error::REG_BADBR;
      case std::regex_constants::error_range:
	return regex_error::REG_ERANGE;
      case std::regex_constants::error_space:
	return regex_error::REG_ESPACE;
      case std::regex_constants::error_badrepeat:
	return regex_error::REG_BADRPT;
      default:
	return regex_error::REG_BADPAT;
      }
  }
};

// ============================================================================
// POSIX-compatible C-style interface
// ============================================================================

// Opaque regex type for C compatibility
struct regex_t
{
  std::unique_ptr<Regex> impl;
  std::size_t re_nsub = 0; // Number of subexpressions
};

// Compile regex (POSIX regcomp compatible)
inline int
regcomp (regex_t *preg, const char *pattern, int cflags) noexcept
{
  if (!preg || !pattern)
    return static_cast<int> (regex_error::REG_BADPAT);

  preg->impl = std::make_unique<Regex> ();
  auto result = preg->impl->compile (pattern, cflags);

  if (result == regex_error::REG_NOERROR)
    {
      // Count subexpressions (simplified - count unescaped open
      // parens)
      preg->re_nsub = 0;
      bool escaped = false;
      for (const char *p = pattern; *p; ++p)
	{
	  if (escaped)
	    {
	      escaped = false;
	    }
	  else if (*p == '\\')
	    {
	      escaped = true;
	    }
	  else if (*p == '(')
	    {
	      ++preg->re_nsub;
	    }
	}
    }

  return static_cast<int> (result);
}

// Execute regex (POSIX regexec compatible)
inline int
regexec (const regex_t *preg, const char *string, std::size_t nmatch,
	 regex_match_t *pmatch, int eflags) noexcept
{
  if (!preg || !preg->impl || !string)
    return static_cast<int> (regex_error::REG_BADPAT);

  if (nmatch == 0 || !pmatch)
    {
      // Just check for match
      return preg->impl->matches (string, eflags)
	       ? static_cast<int> (regex_error::REG_NOERROR)
	       : static_cast<int> (regex_error::REG_NOMATCH);
    }

  return static_cast<int> (
    preg->impl->exec (string,
		      std::span<regex_match_t> (pmatch, nmatch),
		      eflags));
}

// Free regex (POSIX regfree compatible)
inline void
regfree (regex_t *preg) noexcept
{
  if (preg)
    {
      preg->impl.reset ();
      preg->re_nsub = 0;
    }
}

// Get error message (POSIX regerror compatible)
inline std::size_t
regerror (int errcode, const regex_t * /*preg*/, char *errbuf,
	  std::size_t errbuf_size) noexcept
{
  auto msg
    = Regex::error_message (static_cast<regex_error> (errcode));
  std::size_t needed = msg.size () + 1;

  if (errbuf && errbuf_size > 0)
    {
      std::size_t to_copy = std::min (errbuf_size - 1, msg.size ());
      std::memcpy (errbuf, msg.data (), to_copy);
      errbuf[to_copy] = '\0';
    }

  return needed;
}

// ============================================================================
// Modern C++ convenience functions
// ============================================================================

// Quick match check
[[nodiscard]] inline bool
regex_matches (std::string_view pattern, std::string_view str,
	       int flags = 0) noexcept
{
  Regex re;
  if (re.compile (pattern, flags) != regex_error::REG_NOERROR)
    return false;
  return re.matches (str);
}

// Quick full match check
[[nodiscard]] inline bool
regex_full_matches (std::string_view pattern, std::string_view str,
		    int flags = 0) noexcept
{
  Regex re;
  if (re.compile (pattern, flags) != regex_error::REG_NOERROR)
    return false;
  return re.full_match (str);
}

// Quick find all
[[nodiscard]] inline std::vector<std::string>
regex_find_all (std::string_view pattern, std::string_view str,
		int flags = 0)
{
  Regex re;
  if (re.compile (pattern, flags) != regex_error::REG_NOERROR)
    return {};
  return re.find_all (str);
}

// Quick replace all
[[nodiscard]] inline std::string
regex_replace_all (std::string_view pattern, std::string_view str,
		   std::string_view replacement, int flags = 0)
{
  Regex re;
  if (re.compile (pattern, flags) != regex_error::REG_NOERROR)
    return std::string (str);
  return re.replace (str, replacement);
}

// Quick replace first
[[nodiscard]] inline std::string
regex_replace_first (std::string_view pattern, std::string_view str,
		     std::string_view replacement, int flags = 0)
{
  Regex re;
  if (re.compile (pattern, flags) != regex_error::REG_NOERROR)
    return std::string (str);
  return re.replace_first (str, replacement);
}

} // namespace emacs::gnulib
