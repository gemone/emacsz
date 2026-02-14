// src/gnulib/compat_macros.hpp - C++20 compatibility macros
// Replaces: alignasof, builtin-expect, flexmember, vla, ignore-value,
//           bool, std-gnu23, largefile, pathmax

#pragma once

#include <climits>
#include <cstddef>

namespace emacs::gnulib
{

#ifndef __has_builtin
# define __has_builtin(x) 0
#endif

#ifndef __has_attribute
# define __has_attribute(x) 0
#endif

#if __has_builtin(__builtin_expect) || defined(__GNUC__)
# define LIKELY(x) __builtin_expect (!!(x), 1)
# define UNLIKELY(x) __builtin_expect (!!(x), 0)
#else
# define LIKELY(x) (x)
# define UNLIKELY(x) (x)
#endif

#if __has_builtin(__builtin_assume)
# define ASSUME(x) __builtin_assume (x)
#elif defined(_MSC_VER)
# define ASSUME(x) __assume (x)
#elif __has_attribute(assume)
# define ASSUME(x) [[assume (x)]]
#else
# define ASSUME(x) ((void) 0)
#endif

#if __has_builtin(__builtin_unreachable) || defined(__GNUC__)
# define UNREACHABLE() __builtin_unreachable ()
#elif defined(_MSC_VER)
# define UNREACHABLE() __assume (0)
#else
# define UNREACHABLE() ((void) 0)
#endif

#if __has_attribute(always_inline) || defined(__GNUC__)
# define ALWAYS_INLINE __attribute__ ((always_inline)) inline
#elif defined(_MSC_VER)
# define ALWAYS_INLINE __forceinline
#else
# define ALWAYS_INLINE inline
#endif

#if __has_attribute(noinline) || defined(__GNUC__)
# define NOINLINE __attribute__ ((noinline))
#elif defined(_MSC_VER)
# define NOINLINE __declspec (noinline)
#else
# define NOINLINE
#endif

#if __has_attribute(cold) || defined(__GNUC__)
# define COLD __attribute__ ((cold))
#else
# define COLD
#endif

#if __has_attribute(hot) || defined(__GNUC__)
# define HOT __attribute__ ((hot))
#else
# define HOT
#endif

#if __has_attribute(pure) || defined(__GNUC__)
# define PURE __attribute__ ((pure))
#else
# define PURE
#endif

#if __has_attribute(const) || defined(__GNUC__)
# define CONST_FUNC __attribute__ ((const))
#else
# define CONST_FUNC
#endif

#if __has_attribute(malloc) || defined(__GNUC__)
# define MALLOC_LIKE __attribute__ ((malloc))
#else
# define MALLOC_LIKE
#endif

#if __has_attribute(returns_nonnull) || defined(__GNUC__)
# define RETURNS_NONNULL __attribute__ ((returns_nonnull))
#else
# define RETURNS_NONNULL
#endif

#if __has_attribute(warn_unused_result) || defined(__GNUC__)
# define WARN_UNUSED_RESULT __attribute__ ((warn_unused_result))
#else
# define WARN_UNUSED_RESULT
#endif

#if __cplusplus >= 201703L
# define FALLTHROUGH [[fallthrough]]
#elif __has_attribute(fallthrough)
# define FALLTHROUGH __attribute__ ((fallthrough))
#else
# define FALLTHROUGH ((void) 0)
#endif

#if __cplusplus >= 201703L
# define MAYBE_UNUSED [[maybe_unused]]
#elif __has_attribute(unused)
# define MAYBE_UNUSED __attribute__ ((unused))
#else
# define MAYBE_UNUSED
#endif

#if __cplusplus >= 202002L
# define NO_UNIQUE_ADDRESS [[no_unique_address]]
#else
# define NO_UNIQUE_ADDRESS
#endif

template <typename T>
inline void
ignore_value (T &&) noexcept
{
}

#define IGNORE_VALUE(x) ::emacs::gnulib::ignore_value (x)

#if defined(__GNUC__) || defined(__clang__)
# define FLEXIBLE_ARRAY_MEMBER
#else
# define FLEXIBLE_ARRAY_MEMBER 1
#endif

#ifdef PATH_MAX
constexpr std::size_t PATH_MAX_VALUE = PATH_MAX;
#elif defined(_MAX_PATH)
constexpr std::size_t PATH_MAX_VALUE = _MAX_PATH;
#elif defined(MAXPATHLEN)
constexpr std::size_t PATH_MAX_VALUE = MAXPATHLEN;
#else
constexpr std::size_t PATH_MAX_VALUE = 4096;
#endif

#ifdef NAME_MAX
constexpr std::size_t NAME_MAX_VALUE = NAME_MAX;
#elif defined(_MAX_FNAME)
constexpr std::size_t NAME_MAX_VALUE = _MAX_FNAME;
#else
constexpr std::size_t NAME_MAX_VALUE = 255;
#endif

#if defined(_FILE_OFFSET_BITS) && _FILE_OFFSET_BITS == 64
# define LARGE_FILE_SUPPORT 1
#elif defined(_LARGEFILE64_SOURCE)
# define LARGE_FILE_SUPPORT 1
#elif defined(__APPLE__) || defined(__FreeBSD__) \
  || defined(__OpenBSD__)
# define LARGE_FILE_SUPPORT 1
#elif defined(_WIN32)
# define LARGE_FILE_SUPPORT 1
#else
# define LARGE_FILE_SUPPORT 0
#endif

#if __cplusplus >= 202002L
# define CXX20_CONSTEXPR constexpr
#else
# define CXX20_CONSTEXPR inline
#endif

#if __cplusplus >= 202302L
# define CXX23_CONSTEXPR constexpr
#else
# define CXX23_CONSTEXPR inline
#endif

#if defined(__cpp_if_consteval) && __cpp_if_consteval >= 202106L
# define IF_CONSTEVAL if consteval
# define IF_NOT_CONSTEVAL if !consteval
#else
# define IF_CONSTEVAL if (std::is_constant_evaluated ())
# define IF_NOT_CONSTEVAL if (!std::is_constant_evaluated ())
#endif

#ifdef _WIN32
# define EMACS_EXPORT __declspec (dllexport)
# define EMACS_IMPORT __declspec (dllimport)
#else
# define EMACS_EXPORT __attribute__ ((visibility ("default")))
# define EMACS_IMPORT
#endif

#ifdef EMACS_BUILD_DLL
# define EMACS_API EMACS_EXPORT
#else
# define EMACS_API EMACS_IMPORT
#endif

}
