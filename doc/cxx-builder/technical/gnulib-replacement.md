# gnulib C++20 Replacement Library

This document describes the C++20 replacement library for gnulib modules used by GNU Emacs.

## Overview

The `emacs_gnulib_replacement` library provides header-only C++20 implementations that replace gnulib portable functions. All implementations use the `emacs::gnulib` namespace.

## Module Structure

| Module | Header | gnulib Modules Replaced |
|--------|--------|------------------------|
| Memory | `memory_utils.hpp` | alloca, malloc-gnu, realloc-posix, free-posix, mempcpy, memrchr, memmem, memset_explicit |
| Strings | `string_utils.hpp` | strdup, strndup, stpcpy, stpncpy, strnlen, c-ctype, c-strcase, getline |
| Time | `time_utils.hpp` | timespec, gettime, gettimeofday, mktime, timegm, nanosleep, time_rz, timer-time |
| Filesystem | `filesystem.hpp` | faccessat, fstatat, readlink, readlinkat, symlink, canonicalize-lgpl, tempname |
| Crypto | `crypto.hpp` | crypto/md5, crypto/sha1-buffer, crypto/sha256-buffer, crypto/sha512-buffer |
| Math | `math_utils.hpp` | intprops, minmax, stdckdint, stdc_bit_width, stdc_count_ones, stdc_trailing_zeros, byteswap |
| Regex | `regex_utils.hpp` | regex |
| System | `system_utils.hpp` | getopt-gnu, environ, getloadavg, nproc, pthread_sigmask, sig2str, pipe2, pselect, getrandom, execinfo |

## Usage

Include the master header to access all modules:

```cpp
#include <gnulib_replacement.hpp>

using namespace emacs::gnulib;
```

Or include individual modules:

```cpp
#include <gnulib/crypto.hpp>
#include <gnulib/filesystem.hpp>
```

## CMake Integration

```cmake
target_link_libraries(your_target PUBLIC emacs_gnulib_replacement)
```

## Module Details

### memory_utils.hpp

| Function | Description |
|----------|-------------|
| `secure_alloc<T>(n)` | Allocate n elements with automatic cleanup |
| `mempcpy(dest, src, n)` | Copy and return end pointer |
| `memrchr(s, c, n)` | Reverse memchr |
| `memmem(h, hl, n, nl)` | Search for needle in haystack |
| `memset_explicit(s, c, n)` | Non-optimizable memset |

### string_utils.hpp

| Function | Description |
|----------|-------------|
| `strnlen(s, maxlen)` | Length-limited strlen |
| `stpcpy(dest, src)` | Copy and return end pointer |
| `stpncpy(dest, src, n)` | Length-limited stpcpy |
| `duplicate(sv)` | C++20 string duplication |
| `getline_safe(stream)` | Safe line reading |
| `is_alnum(c)`, `is_alpha(c)`, etc. | Locale-independent ctype |
| `to_lower(c)`, `to_upper(c)` | Case conversion |
| `strcasecmp(a, b)` | Case-insensitive compare |

### time_utils.hpp

| Type/Function | Description |
|---------------|-------------|
| `TimeSpec` | C++20 wrapper for timespec |
| `current_time()` | Get current time |
| `timegm_safe(tm)` | Portable timegm |
| `nanosleep_safe(duration)` | Sleep for duration |
| `mktime_utc(tm)` | UTC mktime |

### filesystem.hpp

| Function | Description |
|----------|-------------|
| `faccessat_safe(path, mode)` | Check file access |
| `readlink_safe(path)` | Read symbolic link |
| `symlink_safe(target, link)` | Create symbolic link |
| `canonicalize(path)` | Canonical path |
| `make_temp_file(template)` | Create temporary file |

### crypto.hpp

| Type | Description |
|------|-------------|
| `MD5` | MD5 hash class |
| `SHA1` | SHA1 hash class |
| `md5_buffer(data)` | One-shot MD5 |
| `sha1_buffer(data)` | One-shot SHA1 |

### math_utils.hpp

| Function | Description |
|----------|-------------|
| `add_overflow(a, b, &r)` | Checked addition |
| `sub_overflow(a, b, &r)` | Checked subtraction |
| `mul_overflow(a, b, &r)` | Checked multiplication |
| `bit_width(x)` | Number of bits needed |
| `popcount(x)` | Count set bits |
| `countr_zero(x)` | Trailing zero count |
| `byteswap16/32/64(x)` | Byte order swap |
| `min(a, b)`, `max(a, b)` | Constexpr min/max |

### regex_utils.hpp

| Type/Function | Description |
|---------------|-------------|
| `Regex` | C++20 regex wrapper class |
| `regcomp(preg, pattern, flags)` | POSIX-compatible compile |
| `regexec(preg, string, nmatch, pmatch, flags)` | POSIX-compatible execute |
| `regex_matches(pattern, str)` | Quick match check |
| `regex_replace_all(pattern, str, replacement)` | Replace all matches |

### system_utils.hpp

| Type/Function | Description |
|---------------|-------------|
| `Getopt` | Command-line argument parser |
| `get_environ()` | Get environment variables |
| `getenv_safe(name)` | Safe getenv |
| `setenv_safe(name, value)` | Safe setenv |
| `nproc()` | Get CPU count |
| `getloadavg(loadavg, n)` | Get load average |
| `sigabbrev_np(sig)` | Signal abbreviation |
| `sigdescr_np(sig)` | Signal description |
| `pipe2_safe(flags)` | Create pipe with flags |
| `getrandom_safe(buf, len)` | Get random bytes |
| `get_backtrace()` | Stack backtrace |

## Platform Support

All modules support:
- Linux (glibc 2.17+)
- macOS (10.15+)
- Windows (MSVC 2019+, MinGW)
- FreeBSD, OpenBSD

## Migration Strategy

1. Include `gnulib_replacement.hpp` in new C++ code
2. Use `emacs::gnulib::` namespace for portable functions
3. Gradually migrate existing C code
4. Remove gnulib dependency once migration complete

## Feature Detection

```cpp
using namespace emacs::gnulib;

if constexpr (HAS_STD_FORMAT) {
    // Use std::format
}

if constexpr (HAS_STD_FILESYSTEM) {
    // Use std::filesystem
}

if constexpr (HAS_STD_CHRONO_CALENDAR) {
    // Use C++20 chrono calendar
}
```
