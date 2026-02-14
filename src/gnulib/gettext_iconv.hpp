// src/gnulib/gettext_iconv.hpp
// C++20 replacements for gnulib internationalization
// Replaces: gettext-h, iconv, iconv-h, textdomain, bindtextdomain

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cerrno>
#include <cstddef>
#include <cstring>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

// Platform-specific includes for gettext and iconv
#if defined(__linux__) || defined(__FreeBSD__)   \
  || defined(__NetBSD__) || defined(__OpenBSD__) \
  || defined(__DragonFly__)
# include <iconv.h>
# ifdef HAVE_LIBINTL_H
#  include <libintl.h>
#  define EMACS_HAVE_GETTEXT 1
# else
#  define EMACS_HAVE_GETTEXT 0
# endif
#elif defined(__APPLE__)
# include <iconv.h>
// macOS has gettext via Homebrew or MacPorts, but not by default
# ifdef HAVE_LIBINTL_H
#  include <libintl.h>
#  define EMACS_HAVE_GETTEXT 1
# else
#  define EMACS_HAVE_GETTEXT 0
# endif
#elif defined(_WIN32)
# include <windows.h>
// Windows uses different APIs for character conversion
// gettext support requires GNU gettext for Windows
# ifdef HAVE_LIBINTL_H
#  include <libintl.h>
#  define EMACS_HAVE_GETTEXT 1
# else
#  define EMACS_HAVE_GETTEXT 0
# endif
// For iconv on Windows, we may have libiconv or use Windows APIs
# ifdef HAVE_ICONV_H
#  include <iconv.h>
#  define EMACS_HAVE_ICONV 1
# else
#  define EMACS_HAVE_ICONV 0
# endif
#else
// Unknown platform - try standard headers
# ifdef HAVE_ICONV_H
#  include <iconv.h>
# endif
# ifdef HAVE_LIBINTL_H
#  include <libintl.h>
#  define EMACS_HAVE_GETTEXT 1
# else
#  define EMACS_HAVE_GETTEXT 0
# endif
#endif

// Default EMACS_HAVE_ICONV for non-Windows platforms
#ifndef EMACS_HAVE_ICONV
# if defined(__linux__) || defined(__APPLE__)     \
   || defined(__FreeBSD__) || defined(__NetBSD__) \
   || defined(__OpenBSD__) || defined(__DragonFly__)
#  define EMACS_HAVE_ICONV 1
# else
#  define EMACS_HAVE_ICONV 0
# endif
#endif

namespace emacs::gnulib
{

// ============================================================================
// Gettext Functions
// ============================================================================

/// Error thrown when gettext operations fail
class GettextError : public std::runtime_error
{
public:
  using std::runtime_error::runtime_error;
};

/// Set or query the current message domain
/// @param domainname The domain name to set, or nullptr to query
/// @return The current domain name
[[nodiscard]] inline const char *
textdomain_safe (const char *domainname) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::textdomain (domainname);
#else
  static thread_local std::string current_domain = "messages";
  if (domainname)
    current_domain = domainname;
  return current_domain.c_str ();
#endif
}

/// Bind a message domain to a directory
/// @param domainname The domain name
/// @param dirname The directory containing message catalogs
/// @return The bound directory path
[[nodiscard]] inline const char *
bindtextdomain_safe (const char *domainname,
		     const char *dirname) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::bindtextdomain (domainname, dirname);
#else
  (void) domainname;
  (void) dirname;
  return dirname;
#endif
}

/// Set the encoding for a message domain
/// @param domainname The domain name
/// @param codeset The character encoding (e.g., "UTF-8")
/// @return The bound codeset
[[nodiscard]] inline const char *
bind_textdomain_codeset_safe (const char *domainname,
			      const char *codeset) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::bind_textdomain_codeset (domainname, codeset);
#else
  (void) domainname;
  (void) codeset;
  return codeset;
#endif
}

/// Translate a message using the current domain
/// @param msgid The message to translate
/// @return The translated message, or msgid if no translation found
[[nodiscard]] inline const char *
gettext_safe (const char *msgid) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::gettext (msgid);
#else
  return msgid;
#endif
}

/// Translate a message from a specific domain
/// @param domainname The domain to use
/// @param msgid The message to translate
/// @return The translated message
[[nodiscard]] inline const char *
dgettext_safe (const char *domainname, const char *msgid) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::dgettext (domainname, msgid);
#else
  (void) domainname;
  return msgid;
#endif
}

/// Translate a message from a specific domain and category
/// @param domainname The domain to use
/// @param msgid The message to translate
/// @param category The locale category (e.g., LC_MESSAGES)
/// @return The translated message
[[nodiscard]] inline const char *
dcgettext_safe (const char *domainname, const char *msgid,
		int category) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::dcgettext (domainname, msgid, category);
#else
  (void) domainname;
  (void) category;
  return msgid;
#endif
}

/// Translate a plural message
/// @param msgid1 Singular form
/// @param msgid2 Plural form
/// @param n The count to determine singular/plural
/// @return The appropriate translated message
[[nodiscard]] inline const char *
ngettext_safe (const char *msgid1, const char *msgid2,
	       unsigned long n) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::ngettext (msgid1, msgid2, n);
#else
  return (n == 1) ? msgid1 : msgid2;
#endif
}

/// Translate a plural message from a specific domain
/// @param domainname The domain to use
/// @param msgid1 Singular form
/// @param msgid2 Plural form
/// @param n The count
/// @return The appropriate translated message
[[nodiscard]] inline const char *
dngettext_safe (const char *domainname, const char *msgid1,
		const char *msgid2, unsigned long n) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::dngettext (domainname, msgid1, msgid2, n);
#else
  (void) domainname;
  return (n == 1) ? msgid1 : msgid2;
#endif
}

/// Translate a plural message from a specific domain and category
[[nodiscard]] inline const char *
dcngettext_safe (const char *domainname, const char *msgid1,
		 const char *msgid2, unsigned long n,
		 int category) noexcept
{
#if EMACS_HAVE_GETTEXT
  return ::dcngettext (domainname, msgid1, msgid2, n, category);
#else
  (void) domainname;
  (void) category;
  return (n == 1) ? msgid1 : msgid2;
#endif
}

// C++ string versions for convenience
[[nodiscard]] inline std::string
gettext_str (std::string_view msgid)
{
  return gettext_safe (std::string (msgid).c_str ());
}

[[nodiscard]] inline std::string
ngettext_str (std::string_view msgid1, std::string_view msgid2,
	      unsigned long n)
{
  return ngettext_safe (std::string (msgid1).c_str (),
			std::string (msgid2).c_str (), n);
}

// Macros for marking translatable strings (typically used with
// xgettext) These are no-ops but allow string extraction tools to
// find them
#ifndef _
# define _(String) emacs::gnulib::gettext_safe (String)
#endif

#ifndef N_
# define N_(String) (String)
#endif

// ============================================================================
// Iconv Functions and Classes
// ============================================================================

/// Error thrown when iconv operations fail
class IconvError : public std::runtime_error
{
public:
  explicit IconvError (const std::string &msg)
      : std::runtime_error (msg), error_code_ (errno)
  {
  }

  IconvError (const std::string &msg, int err)
      : std::runtime_error (msg), error_code_ (err)
  {
  }

  [[nodiscard]] int error_code () const noexcept
  {
    return error_code_;
  }

private:
  int error_code_;
};

#if EMACS_HAVE_ICONV

/// Safe wrapper for iconv_open
/// @param tocode Destination encoding
/// @param fromcode Source encoding
/// @return iconv descriptor, or (iconv_t)-1 on error
[[nodiscard]] inline iconv_t
iconv_open_safe (const char *tocode, const char *fromcode) noexcept
{
  return ::iconv_open (tocode, fromcode);
}

/// Safe wrapper for iconv_close
/// @param cd The iconv descriptor to close
/// @return 0 on success, -1 on error
inline int
iconv_close_safe (iconv_t cd) noexcept
{
  if (cd != reinterpret_cast<iconv_t> (-1))
    return ::iconv_close (cd);
  return 0;
}

/// Safe wrapper for iconv
/// @param cd The iconv descriptor
/// @param inbuf Pointer to input buffer pointer
/// @param inbytesleft Pointer to input bytes remaining
/// @param outbuf Pointer to output buffer pointer
/// @param outbytesleft Pointer to output buffer space remaining
/// @return Number of non-reversible conversions, or (size_t)-1 on
/// error
[[nodiscard]] inline size_t
iconv_safe (iconv_t cd, char **inbuf, size_t *inbytesleft,
	    char **outbuf, size_t *outbytesleft) noexcept
{
  return ::iconv (cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

/// Check if an iconv descriptor is valid
[[nodiscard]] inline bool
iconv_is_valid (iconv_t cd) noexcept
{
  return cd != reinterpret_cast<iconv_t> (-1);
}

/// RAII wrapper for iconv_t descriptor
class IconvDescriptor
{
public:
  IconvDescriptor () noexcept : cd_ (reinterpret_cast<iconv_t> (-1))
  {
  }

  IconvDescriptor (const char *tocode, const char *fromcode)
      : cd_ (::iconv_open (tocode, fromcode))
  {
    if (!is_valid ())
      throw IconvError (std::string ("Failed to open iconv from '")
			+ fromcode + "' to '" + tocode + "'");
  }

  ~IconvDescriptor () noexcept { close (); }

  // Non-copyable
  IconvDescriptor (const IconvDescriptor &) = delete;
  IconvDescriptor &operator= (const IconvDescriptor &) = delete;

  // Movable
  IconvDescriptor (IconvDescriptor &&other) noexcept : cd_ (other.cd_)
  {
    other.cd_ = reinterpret_cast<iconv_t> (-1);
  }

  IconvDescriptor &operator= (IconvDescriptor &&other) noexcept
  {
    if (this != &other)
      {
	close ();
	cd_ = other.cd_;
	other.cd_ = reinterpret_cast<iconv_t> (-1);
      }
    return *this;
  }

  [[nodiscard]] bool is_valid () const noexcept
  {
    return cd_ != reinterpret_cast<iconv_t> (-1);
  }

  [[nodiscard]] iconv_t get () const noexcept { return cd_; }

  void close () noexcept
  {
    if (is_valid ())
      {
	::iconv_close (cd_);
	cd_ = reinterpret_cast<iconv_t> (-1);
      }
  }

  /// Reset the conversion state
  void reset () noexcept
  {
    if (is_valid ())
      ::iconv (cd_, nullptr, nullptr, nullptr, nullptr);
  }

  explicit operator bool () const noexcept { return is_valid (); }

private:
  iconv_t cd_;
};

/// High-level RAII character encoding converter
class IconvConverter
{
public:
  /// Construct a converter between encodings
  /// @param from_encoding Source encoding (e.g., "UTF-8",
  /// "ISO-8859-1")
  /// @param to_encoding Destination encoding
  /// @throws IconvError if the conversion is not supported
  IconvConverter (std::string_view from_encoding,
		  std::string_view to_encoding)
      : from_encoding_ (from_encoding), to_encoding_ (to_encoding),
	descriptor_ (std::string (to_encoding).c_str (),
		     std::string (from_encoding).c_str ())
  {
  }

  /// Convert a string from source to destination encoding
  /// @param input The input string in source encoding
  /// @return The converted string in destination encoding
  /// @throws IconvError on conversion failure
  [[nodiscard]] std::string convert (std::string_view input) const
  {
    if (input.empty ())
      return {};

    std::string output;
    output.resize (input.size () * 4);

    const char *inbuf = input.data ();
    size_t inbytesleft = input.size ();
    char *outbuf = output.data ();
    size_t outbytesleft = output.size ();

    ::iconv (descriptor_.get (), nullptr, nullptr, nullptr, nullptr);

    while (inbytesleft > 0)
      {
	char *inbuf_ptr = const_cast<char *> (inbuf);
	size_t result
	  = ::iconv (descriptor_.get (), &inbuf_ptr, &inbytesleft,
		     &outbuf, &outbytesleft);

	inbuf = inbuf_ptr;

	if (result == static_cast<size_t> (-1))
	  {
	    if (errno == E2BIG)
	      {
		size_t used = output.size () - outbytesleft;
		output.resize (output.size () * 2);
		outbuf = output.data () + used;
		outbytesleft = output.size () - used;
	      }
	    else if (errno == EILSEQ)
	      {
		throw IconvError (
		  "Invalid multibyte sequence in input");
	      }
	    else if (errno == EINVAL)
	      {
		break;
	      }
	    else
	      {
		throw IconvError ("iconv conversion failed");
	      }
	  }
      }

    output.resize (output.size () - outbytesleft);
    return output;
  }

  /// Convert with optional replacement for invalid sequences
  /// @param input The input string
  /// @param replacement Character to use for invalid sequences
  /// @return The converted string
  [[nodiscard]] std::string
  convert_lossy (std::string_view input, char replacement = '?') const
  {
    if (input.empty ())
      return {};

    std::string output;
    output.reserve (input.size () * 2);

    const char *inbuf = input.data ();
    size_t inbytesleft = input.size ();

    std::string buffer (256, '\0');

    ::iconv (descriptor_.get (), nullptr, nullptr, nullptr, nullptr);

    while (inbytesleft > 0)
      {
	char *outbuf = buffer.data ();
	size_t outbytesleft = buffer.size ();
	char *inbuf_ptr = const_cast<char *> (inbuf);

	size_t result
	  = ::iconv (descriptor_.get (), &inbuf_ptr, &inbytesleft,
		     &outbuf, &outbytesleft);

	output.append (buffer.data (), buffer.size () - outbytesleft);
	inbuf = inbuf_ptr;

	if (result == static_cast<size_t> (-1))
	  {
	    if (errno == EILSEQ && inbytesleft > 0)
	      {
		output.push_back (replacement);
		++inbuf;
		--inbytesleft;
		::iconv (descriptor_.get (), nullptr, nullptr,
			 nullptr, nullptr);
	      }
	    else if (errno == EINVAL)
	      {
		break;
	      }
	    else if (errno != E2BIG)
	      {
		break;
	      }
	  }
      }

    return output;
  }

  /// Get the source encoding name
  [[nodiscard]] std::string_view from_encoding () const noexcept
  {
    return from_encoding_;
  }

  /// Get the destination encoding name
  [[nodiscard]] std::string_view to_encoding () const noexcept
  {
    return to_encoding_;
  }

  /// Check if the converter is valid
  [[nodiscard]] bool is_valid () const noexcept
  {
    return descriptor_.is_valid ();
  }

  explicit operator bool () const noexcept { return is_valid (); }

private:
  std::string from_encoding_;
  std::string to_encoding_;
  mutable IconvDescriptor descriptor_;
};

/// Create an optional converter (returns nullopt on failure instead
/// of throwing)
[[nodiscard]] inline std::optional<IconvConverter>
make_iconv_converter (std::string_view from_encoding,
		      std::string_view to_encoding) noexcept
{
  try
    {
      return IconvConverter (from_encoding, to_encoding);
    }
  catch (const IconvError &)
    {
      return std::nullopt;
    }
}

#else // !EMACS_HAVE_ICONV

// Windows-specific implementation using
// MultiByteToWideChar/WideCharToMultiByte

# ifdef _WIN32

/// Get Windows code page from encoding name
[[nodiscard]] inline unsigned int
encoding_to_codepage (std::string_view encoding) noexcept
{
  if (encoding == "UTF-8" || encoding == "utf-8")
    return CP_UTF8;
  if (encoding == "UTF-16" || encoding == "utf-16"
      || encoding == "UTF-16LE" || encoding == "utf-16le")
    return 1200;
  if (encoding == "UTF-16BE" || encoding == "utf-16be")
    return 1201;
  if (encoding == "ISO-8859-1" || encoding == "iso-8859-1"
      || encoding == "latin1")
    return 28591;
  if (encoding == "Windows-1252" || encoding == "CP1252")
    return 1252;
  if (encoding == "ASCII" || encoding == "US-ASCII")
    return 20127;
  return CP_UTF8;
}

/// Windows implementation of IconvConverter
class IconvConverter
{
public:
  IconvConverter (std::string_view from_encoding,
		  std::string_view to_encoding)
      : from_encoding_ (from_encoding), to_encoding_ (to_encoding),
	from_cp_ (encoding_to_codepage (from_encoding)),
	to_cp_ (encoding_to_codepage (to_encoding))
  {
  }

  [[nodiscard]] std::string convert (std::string_view input) const
  {
    if (input.empty ())
      return {};

    int wlen = MultiByteToWideChar (from_cp_, MB_ERR_INVALID_CHARS,
				    input.data (),
				    static_cast<int> (input.size ()),
				    nullptr, 0);
    if (wlen == 0)
      throw IconvError ("Failed to convert from source encoding",
			static_cast<int> (GetLastError ()));

    std::wstring wstr (static_cast<size_t> (wlen), L'\0');
    MultiByteToWideChar (from_cp_, MB_ERR_INVALID_CHARS,
			 input.data (),
			 static_cast<int> (input.size ()),
			 wstr.data (), wlen);

    int outlen = WideCharToMultiByte (to_cp_, 0, wstr.data (), wlen,
				      nullptr, 0, nullptr, nullptr);
    if (outlen == 0)
      throw IconvError ("Failed to convert to target encoding",
			static_cast<int> (GetLastError ()));

    std::string output (static_cast<size_t> (outlen), '\0');
    WideCharToMultiByte (to_cp_, 0, wstr.data (), wlen,
			 output.data (), outlen, nullptr, nullptr);

    return output;
  }

  [[nodiscard]] std::string
  convert_lossy (std::string_view input,
		 [[maybe_unused]] char replacement = '?') const
  {
    if (input.empty ())
      return {};

    int wlen = MultiByteToWideChar (from_cp_, 0, input.data (),
				    static_cast<int> (input.size ()),
				    nullptr, 0);
    if (wlen == 0)
      return {};

    std::wstring wstr (static_cast<size_t> (wlen), L'\0');
    MultiByteToWideChar (from_cp_, 0, input.data (),
			 static_cast<int> (input.size ()),
			 wstr.data (), wlen);

    int outlen = WideCharToMultiByte (to_cp_, 0, wstr.data (), wlen,
				      nullptr, 0, nullptr, nullptr);
    if (outlen == 0)
      return {};

    std::string output (static_cast<size_t> (outlen), '\0');
    WideCharToMultiByte (to_cp_, 0, wstr.data (), wlen,
			 output.data (), outlen, nullptr, nullptr);

    return output;
  }

  [[nodiscard]] std::string_view from_encoding () const noexcept
  {
    return from_encoding_;
  }

  [[nodiscard]] std::string_view to_encoding () const noexcept
  {
    return to_encoding_;
  }

  [[nodiscard]] bool is_valid () const noexcept { return true; }

  explicit operator bool () const noexcept { return true; }

private:
  std::string from_encoding_;
  std::string to_encoding_;
  unsigned int from_cp_;
  unsigned int to_cp_;
};

[[nodiscard]] inline std::optional<IconvConverter>
make_iconv_converter (std::string_view from_encoding,
		      std::string_view to_encoding) noexcept
{
  try
    {
      return IconvConverter (from_encoding, to_encoding);
    }
  catch (const IconvError &)
    {
      return std::nullopt;
    }
}

# else

class IconvConverter
{
public:
  IconvConverter (std::string_view from_encoding,
		  std::string_view to_encoding)
      : from_encoding_ (from_encoding), to_encoding_ (to_encoding)
  {
    if (from_encoding != to_encoding && from_encoding != "UTF-8"
	&& to_encoding != "UTF-8")
      {
	throw IconvError ("iconv not available on this platform");
      }
  }

  [[nodiscard]] std::string convert (std::string_view input) const
  {
    return std::string (input);
  }

  [[nodiscard]] std::string
  convert_lossy (std::string_view input,
		 [[maybe_unused]] char replacement = '?') const
  {
    return std::string (input);
  }

  [[nodiscard]] std::string_view from_encoding () const noexcept
  {
    return from_encoding_;
  }

  [[nodiscard]] std::string_view to_encoding () const noexcept
  {
    return to_encoding_;
  }

  [[nodiscard]] bool is_valid () const noexcept
  {
    return from_encoding_ == to_encoding_;
  }

  explicit operator bool () const noexcept { return is_valid (); }

private:
  std::string from_encoding_;
  std::string to_encoding_;
};

[[nodiscard]] inline std::optional<IconvConverter>
make_iconv_converter (std::string_view from_encoding,
		      std::string_view to_encoding) noexcept
{
  try
    {
      return IconvConverter (from_encoding, to_encoding);
    }
  catch (const IconvError &)
    {
      return std::nullopt;
    }
}

# endif // _WIN32

#endif // EMACS_HAVE_ICONV

// ============================================================================
// Convenience Functions
// ============================================================================

/// Convert string from one encoding to another
/// @param input The input string
/// @param from_encoding Source encoding
/// @param to_encoding Destination encoding
/// @return Converted string, or nullopt on failure
[[nodiscard]] inline std::optional<std::string>
convert_encoding (std::string_view input,
		  std::string_view from_encoding,
		  std::string_view to_encoding) noexcept
{
  try
    {
      IconvConverter converter (from_encoding, to_encoding);
      return converter.convert (input);
    }
  catch (const IconvError &)
    {
      return std::nullopt;
    }
}

/// Convert string to UTF-8 from any encoding
[[nodiscard]] inline std::optional<std::string>
to_utf8 (std::string_view input,
	 std::string_view from_encoding) noexcept
{
  return convert_encoding (input, from_encoding, "UTF-8");
}

/// Convert UTF-8 string to another encoding
[[nodiscard]] inline std::optional<std::string>
from_utf8 (std::string_view input,
	   std::string_view to_encoding) noexcept
{
  return convert_encoding (input, "UTF-8", to_encoding);
}

/// Check if an encoding conversion is supported
[[nodiscard]] inline bool
is_conversion_supported (std::string_view from_encoding,
			 std::string_view to_encoding) noexcept
{
  return make_iconv_converter (from_encoding, to_encoding)
    .has_value ();
}

} // namespace emacs::gnulib
