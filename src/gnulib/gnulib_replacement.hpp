// src/gnulib/gnulib_replacement.hpp
// Master header for gnulib C++20 replacements
//
// This file provides the main include point for all gnulib
// replacement modules. Include this single header to access all C++20
// replacements.
//
// Migration Strategy:
// 1. Include this header in new C++20 code
// 2. Use emacs::gnulib namespace for all replacement functions
// 3. Gradually migrate C code to use these replacements
// 4. Eventually remove original gnulib dependency

#pragma once

// C++20 Standard Requirements
#if __cplusplus < 202002L
# error "C++20 or later is required for gnulib replacements"
#endif

#include "acl_utils.hpp"
#include "argp.hpp"
#include "ciphers.hpp"
#include "compat_macros.hpp"
#include "copy_file.hpp"
#include "crypto.hpp"
#include "diff_utils.hpp"
#include "error_handling.hpp"
#include "filesystem.hpp"
#include "format_output.hpp"
#include "gettext_iconv.hpp"
#include "hash.hpp"
#include "hmac.hpp"
#include "io_utils.hpp"
#include "localename.hpp"
#include "math_utils.hpp"
#include "memory_utils.hpp"
#include "multibyte.hpp"
#include "obstack.hpp"
#include "path_utils.hpp"
#include "regex_utils.hpp"
#include "safe_io.hpp"
#include "sha3.hpp"
#include "spawn.hpp"
#include "string_utils.hpp"
#include "system_info.hpp"
#include "system_utils.hpp"
#include "time_utils.hpp"
#include "unicode.hpp"
#include "wchar_utils.hpp"
#include "xalloc.hpp"

namespace emacs::gnulib
{

// Version information
constexpr const char *VERSION = "1.0.0";
constexpr const char *DESCRIPTION
  = "C++20 gnulib replacement library for GNU Emacs";

// Feature detection
constexpr bool HAS_STD_FORMAT =
#if __cpp_lib_format >= 201907L
  true
#else
  false
#endif
  ;

constexpr bool HAS_STD_FILESYSTEM =
#if __cpp_lib_filesystem >= 201703L
  true
#else
  false
#endif
  ;

constexpr bool HAS_STD_CHRONO_CALENDAR =
#if __cpp_lib_chrono >= 201907L
  true
#else
  false
#endif
  ;

// Configuration macros for compatibility
#ifndef GNULIB_REPLACEMENT_INLINE
# define GNULIB_REPLACEMENT_INLINE inline
#endif

} // namespace emacs::gnulib
