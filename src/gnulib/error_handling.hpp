// src/gnulib/error_handling.hpp
// C++20 replacements for gnulib error reporting
// Replaces: error, error_at_line, verror, verror_at_line

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "format_output.hpp"

#include <atomic>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

#ifdef _WIN32
# include <windows.h>
#else
# include <unistd.h>
# if __has_include(<sys/param.h>)
#  include <sys/param.h>
# endif
# if defined(__GLIBC__)
extern const char *program_invocation_name;
# elif defined(__APPLE__) || defined(__FreeBSD__)
#  include <stdlib.h>
# endif
#endif

namespace emacs::gnulib
{

// ============================================================================
// Error Reporting State
// ============================================================================

// Thread-local error message counter
inline thread_local unsigned int error_message_count = 0;

// Global callback for printing program name
// If set, this function is called instead of printing the program
// name
inline thread_local void (*error_print_progname) () = nullptr;

// Program name for error messages
// Set automatically or can be set manually
inline thread_local std::string error_program_name{};

namespace detail
{

// Get the program name for error reporting
[[nodiscard]] inline std::string
get_program_name () noexcept
{
  // If already set via error_program_name, use that
  if (!error_program_name.empty ())
    return error_program_name;

#ifdef _WIN32
  // Windows: use __argv[0] or fallback
  extern char **__argv;
  if (__argv && __argv[0])
    {
      const char *name = __argv[0];
      const char *last_slash = name;
      const char *p = name;
      while (*p)
	{
	  if (*p == '\\' || *p == '/')
	    last_slash = p + 1;
	  ++p;
	}
      return last_slash;
    }
  return "emacs";
#elif defined(__GLIBC__)
  // GNU/Linux: use program_invocation_name
  if (program_invocation_name)
    {
      const char *name = program_invocation_name;
      const char *last_slash = name;
      const char *p = name;
      while (*p)
	{
	  if (*p == '/')
	    last_slash = p + 1;
	  ++p;
	}
      return last_slash;
    }
  return "emacs";
#elif defined(__APPLE__) || defined(__FreeBSD__)
  // macOS/BSD: use getprogname()
  const char *name = getprogname ();
  if (name && name[0])
    return name;
  return "emacs";
#else
  // Fallback for other systems
  return "emacs";
#endif
}

// Get the error message suffix from errno
[[nodiscard]] inline std::string
get_error_suffix (int errnum) noexcept
{
  if (errnum == 0)
    return {};

  const char *errstr = std::strerror (errnum);
  if (!errstr)
    return {};

  return std::string (": ") + errstr;
}

// Print error header (program name and file:line if provided)
inline void
print_error_header (const char *filename,
		    unsigned int linenum) noexcept
{
  if (error_print_progname)
    {
      error_print_progname ();
    }
  else
    {
      std::string progname = get_program_name ();
      std::fprintf (stderr, "%s", progname.c_str ());
    }

  if (filename)
    {
      std::fprintf (stderr, ":%s:%u", filename, linenum);
    }
  std::fprintf (stderr, ": ");
}

} // namespace detail

// Forward declarations for error functions
void verror (int status, int errnum, const char *format,
	     va_list ap) noexcept;
void verror_at_line (int status, int errnum, const char *filename,
		     unsigned int linenum, const char *format,
		     va_list ap) noexcept;

// ============================================================================
// C-style Error Reporting Functions
// ============================================================================

/// Print an error message to stderr and optionally exit
/// @param status: Exit status. If non-zero, calls exit(status) after
/// printing
/// @param errnum: If non-zero, appends strerror(errnum) to message
/// @param format: printf-style format string
/// @param ...: Variable arguments for format string
/// Output format: "program_name: message: strerror(errnum)"
inline void
error (int status, int errnum, const char *format, ...) noexcept
{
  va_list ap;
  va_start (ap, format);
  emacs::gnulib::verror (status, errnum, format, ap);
  va_end (ap);
}

/// Print an error message with file and line information
/// @param status: Exit status. If non-zero, calls exit(status) after
/// printing
/// @param errnum: If non-zero, appends strerror(errnum) to message
/// @param filename: Source filename for error location
/// @param linenum: Source line number for error location
/// @param format: printf-style format string
/// @param ...: Variable arguments for format string
/// Output format: "program_name:file:line: message: strerror(errnum)"
inline void
error_at_line (int status, int errnum, const char *filename,
	       unsigned int linenum, const char *format, ...) noexcept
{
  va_list ap;
  va_start (ap, format);
  verror_at_line (status, errnum, filename, linenum, format, ap);
  va_end (ap);
}

/// va_list version of error()
/// Print an error message to stderr and optionally exit
/// @param status: Exit status. If non-zero, calls exit(status) after
/// printing
/// @param errnum: If non-zero, appends strerror(errnum) to message
/// @param format: printf-style format string
/// @param ap: Variable argument list
inline void
verror (int status, int errnum, const char *format,
	va_list ap) noexcept
{
  verror_at_line (status, errnum, nullptr, 0, format, ap);
}

/// va_list version of error_at_line()
/// Print an error message with file and line information
/// @param status: Exit status. If non-zero, calls exit(status) after
/// printing
/// @param errnum: If non-zero, appends strerror(errnum) to message
/// @param filename: Source filename for error location (may be
/// nullptr)
/// @param linenum: Source line number for error location
/// @param format: printf-style format string
/// @param ap: Variable argument list
inline void
verror_at_line (int status, int errnum, const char *filename,
		unsigned int linenum, const char *format,
		va_list ap) noexcept
{
  if (!format)
    {
      if (status != 0)
	std::exit (status);
      return;
    }

  // Print error header
  detail::print_error_header (filename, linenum);

  // Format and print the message
  std::string message = vformat_string (format, ap);
  std::fprintf (stderr, "%s", message.c_str ());

  // Append errno message if provided
  if (errnum != 0)
    {
      std::string suffix = detail::get_error_suffix (errnum);
      std::fprintf (stderr, "%s", suffix.c_str ());
    }

  std::fprintf (stderr, "\n");

  // Increment error counter
  ++error_message_count;

  // Exit if requested
  if (status != 0)
    std::exit (status);
}

// ============================================================================
// C++ Exception-Based Error Reporting
// ============================================================================

/// GNU-style error exception
/// Provides C++ exception interface while maintaining GNU error
/// semantics
class gnu_error : public std::runtime_error
{
private:
  int error_code_;

public:
  /// Construct a gnu_error with error code and message
  /// @param errnum: Error code (errno value)
  /// @param msg: Error message
  explicit gnu_error (int errnum, const std::string &msg)
      : std::runtime_error (msg), error_code_ (errnum)
  {
  }

  /// Construct a gnu_error with just a message
  /// @param msg: Error message
  explicit gnu_error (const std::string &msg)
      : std::runtime_error (msg), error_code_ (0)
  {
  }

  /// Get the error code (errno value)
  /// @return Error code associated with this error
  [[nodiscard]] int error_code () const noexcept
  {
    return error_code_;
  }
};

/// Throw a gnu_error exception with formatted message
/// Never returns - calls std::terminate() or throws
/// @param errnum: Error code (errno value)
/// @param format: printf-style format string
/// @param ...: Variable arguments for format string
/// @throws gnu_error Always
[[noreturn]] inline void
throw_error (int errnum, const char *format, ...)
{
  if (!format)
    throw gnu_error (errnum, "");

  va_list ap;
  va_start (ap, format);

  std::string message = vformat_string (format, ap);
  va_end (ap);

  if (errnum != 0)
    {
      std::string suffix = detail::get_error_suffix (errnum);
      message += suffix;
    }

  throw gnu_error (errnum, message);
}

/// Report an error as an exception (non-fatal)
/// @param errnum: Error code (errno value)
/// @param format: printf-style format string
/// @param ...: Variable arguments for format string
/// @throws gnu_error Always
inline void
report_error (int errnum, const char *format, ...)
{
  if (!format)
    throw gnu_error (errnum, "");

  va_list ap;
  va_start (ap, format);

  std::string message = vformat_string (format, ap);
  va_end (ap);

  if (errnum != 0)
    {
      std::string suffix = detail::get_error_suffix (errnum);
      message += suffix;
    }

  throw gnu_error (errnum, message);
}

// ============================================================================
// Error Reporting Configuration
// ============================================================================

/// Set the program name for error messages
/// @param progname: Program name to use in error messages
inline void
set_error_program_name (const std::string &progname) noexcept
{
  error_program_name = progname;
}

/// Set the program name callback function
/// Called instead of printing the default program name
/// @param callback: Function to call for printing program name,
///                  or nullptr to use default
inline void
set_error_print_progname (void (*callback) ()) noexcept
{
  error_print_progname = callback;
}

/// Get the current error message count
/// @return Number of errors reported
[[nodiscard]] inline unsigned int
get_error_message_count () noexcept
{
  return error_message_count;
}

/// Reset the error message count
/// @param count: New count value (default 0)
inline void
reset_error_message_count (unsigned int count = 0) noexcept
{
  error_message_count = count;
}

// ============================================================================
// Utility Functions for Error Reporting
// ============================================================================

/// Get the string representation of an error code
/// @param errnum: Error code (errno value)
/// @return String representation of the error
[[nodiscard]] inline std::string
error_to_string (int errnum) noexcept
{
  const char *errstr = std::strerror (errnum);
  return errstr ? std::string (errstr) : "Unknown error";
}

/// Print a simple error message to stderr (without counter increment)
/// @param progname: Program name
/// @param message: Error message
inline void
print_simple_error (const std::string &progname,
		    const std::string &message) noexcept
{
  std::fprintf (stderr, "%s: %s\n", progname.c_str (),
		message.c_str ());
}

/// Print a formatted error message to stderr
/// @param progname: Program name
/// @param format: printf-style format string
/// @param ...: Variable arguments for format string
inline void
print_formatted_error (const std::string &progname,
		       const char *format, ...) noexcept
{
  if (!format)
    return;

  va_list ap;
  va_start (ap, format);

  std::string message = vformat_string (format, ap);
  va_end (ap);

  print_simple_error (progname, message);
}

} // namespace emacs::gnulib
