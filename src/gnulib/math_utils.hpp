// src/gnulib/math_utils.hpp
// C++20 replacements for gnulib math and integer utilities
// Replaces: intprops, minmax, stdckdint, stdc_bit_width,
// stdc_count_ones, etc.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <bit>
#include <cstdint>
#include <limits>
#include <type_traits>

namespace emacs::gnulib
{

template <typename T>
[[nodiscard]] constexpr T
min_value (T a, T b) noexcept
{
  return a < b ? a : b;
}

template <typename T>
[[nodiscard]] constexpr T
max_value (T a, T b) noexcept
{
  return a > b ? a : b;
}

template <typename T, typename... Args>
[[nodiscard]] constexpr T
min_value (T first, Args... args) noexcept
{
  return min_value (first, min_value (args...));
}

template <typename T, typename... Args>
[[nodiscard]] constexpr T
max_value (T first, Args... args) noexcept
{
  return max_value (first, max_value (args...));
}

template <typename T>
[[nodiscard]] constexpr T
clamp_value (T val, T lo, T hi) noexcept
{
  return val < lo ? lo : (val > hi ? hi : val);
}

template <typename T>
[[nodiscard]] constexpr int
stdc_bit_width (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_int_pow2 >= 202002L
  return std::bit_width (value);
#else
  if (value == 0)
    return 0;
  int width = 0;
  while (value)
    {
      value >>= 1;
      ++width;
    }
  return width;
#endif
}

template <typename T>
[[nodiscard]] constexpr int
stdc_count_ones (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_bitops >= 201907L
  return std::popcount (value);
#else
  int count = 0;
  while (value)
    {
      count += value & 1;
      value >>= 1;
    }
  return count;
#endif
}

template <typename T>
[[nodiscard]] constexpr int
stdc_leading_zeros (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_bitops >= 201907L
  return std::countl_zero (value);
#else
  if (value == 0)
    return std::numeric_limits<T>::digits;
  int count = 0;
  T mask = static_cast<T> (1) << (std::numeric_limits<T>::digits - 1);
  while ((value & mask) == 0)
    {
      ++count;
      mask >>= 1;
    }
  return count;
#endif
}

template <typename T>
[[nodiscard]] constexpr int
stdc_trailing_zeros (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_bitops >= 201907L
  return std::countr_zero (value);
#else
  if (value == 0)
    return std::numeric_limits<T>::digits;
  int count = 0;
  while ((value & 1) == 0)
    {
      ++count;
      value >>= 1;
    }
  return count;
#endif
}

template <typename T>
[[nodiscard]] constexpr bool
stdc_has_single_bit (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_int_pow2 >= 202002L
  return std::has_single_bit (value);
#else
  return value != 0 && (value & (value - 1)) == 0;
#endif
}

template <typename T>
[[nodiscard]] constexpr T
stdc_bit_ceil (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_int_pow2 >= 202002L
  return std::bit_ceil (value);
#else
  if (value <= 1)
    return 1;
  --value;
  value |= value >> 1;
  value |= value >> 2;
  value |= value >> 4;
  if constexpr (sizeof (T) > 1)
    value |= value >> 8;
  if constexpr (sizeof (T) > 2)
    value |= value >> 16;
  if constexpr (sizeof (T) > 4)
    value |= value >> 32;
  return value + 1;
#endif
}

template <typename T>
[[nodiscard]] constexpr T
stdc_bit_floor (T value) noexcept
{
  static_assert (std::is_unsigned_v<T>);
#if __cpp_lib_int_pow2 >= 202002L
  return std::bit_floor (value);
#else
  if (value == 0)
    return 0;
  value |= value >> 1;
  value |= value >> 2;
  value |= value >> 4;
  if constexpr (sizeof (T) > 1)
    value |= value >> 8;
  if constexpr (sizeof (T) > 2)
    value |= value >> 16;
  if constexpr (sizeof (T) > 4)
    value |= value >> 32;
  return value - (value >> 1);
#endif
}

template <typename R, typename T>
[[nodiscard]] constexpr bool
add_overflow (T a, T b, R *result) noexcept
{
  static_assert (std::is_integral_v<T>);
  static_assert (std::is_integral_v<R>);
#if __has_builtin(__builtin_add_overflow)
  return __builtin_add_overflow (a, b, result);
#else
  *result = static_cast<R> (a + b);
  if constexpr (std::is_signed_v<T>)
    {
      if ((b > 0 && a > std::numeric_limits<T>::max () - b)
	  || (b < 0 && a < std::numeric_limits<T>::min () - b))
	return true;
    }
  else
    {
      if (a > std::numeric_limits<T>::max () - b)
	return true;
    }
  return false;
#endif
}

template <typename R, typename T>
[[nodiscard]] constexpr bool
sub_overflow (T a, T b, R *result) noexcept
{
  static_assert (std::is_integral_v<T>);
  static_assert (std::is_integral_v<R>);
#if __has_builtin(__builtin_sub_overflow)
  return __builtin_sub_overflow (a, b, result);
#else
  *result = static_cast<R> (a - b);
  if constexpr (std::is_signed_v<T>)
    {
      if ((b > 0 && a < std::numeric_limits<T>::min () + b)
	  || (b < 0 && a > std::numeric_limits<T>::max () + b))
	return true;
    }
  else
    {
      if (a < b)
	return true;
    }
  return false;
#endif
}

template <typename R, typename T>
[[nodiscard]] constexpr bool
mul_overflow (T a, T b, R *result) noexcept
{
  static_assert (std::is_integral_v<T>);
  static_assert (std::is_integral_v<R>);
#if __has_builtin(__builtin_mul_overflow)
  return __builtin_mul_overflow (a, b, result);
#else
  *result = static_cast<R> (a * b);
  if (a != 0 && *result / a != b)
    return true;
  return false;
#endif
}

template <typename T>
[[nodiscard]] constexpr bool
type_signed () noexcept
{
  return std::is_signed_v<T>;
}

template <typename T>
[[nodiscard]] constexpr T
type_minimum () noexcept
{
  return std::numeric_limits<T>::min ();
}

template <typename T>
[[nodiscard]] constexpr T
type_maximum () noexcept
{
  return std::numeric_limits<T>::max ();
}

template <typename T>
[[nodiscard]] constexpr bool
in_range (T value, T min, T max) noexcept
{
  return value >= min && value <= max;
}

template <typename To, typename From>
[[nodiscard]] constexpr bool
fits_in_type (From value) noexcept
{
  using ToLimits = std::numeric_limits<To>;

  if constexpr (std::is_signed_v<From> == std::is_signed_v<To>)
    return value >= ToLimits::min () && value <= ToLimits::max ();
  else if constexpr (std::is_signed_v<From>)
    return value >= 0
	   && static_cast<std::make_unsigned_t<From>> (value)
		<= ToLimits::max ();
  else
    return value <= static_cast<From> (ToLimits::max ());
}

[[nodiscard]] constexpr uint16_t
byteswap16 (uint16_t x) noexcept
{
#if __cpp_lib_byteswap >= 202110L
  return std::byteswap (x);
#else
  return static_cast<uint16_t> ((x >> 8) | (x << 8));
#endif
}

[[nodiscard]] constexpr uint32_t
byteswap32 (uint32_t x) noexcept
{
#if __cpp_lib_byteswap >= 202110L
  return std::byteswap (x);
#else
  return ((x >> 24) & 0x000000ff) | ((x >> 8) & 0x0000ff00)
	 | ((x << 8) & 0x00ff0000) | ((x << 24) & 0xff000000);
#endif
}

[[nodiscard]] constexpr uint64_t
byteswap64 (uint64_t x) noexcept
{
#if __cpp_lib_byteswap >= 202110L
  return std::byteswap (x);
#else
  return ((x >> 56) & 0x00000000000000ffULL)
	 | ((x >> 40) & 0x000000000000ff00ULL)
	 | ((x >> 24) & 0x0000000000ff0000ULL)
	 | ((x >> 8) & 0x00000000ff000000ULL)
	 | ((x << 8) & 0x000000ff00000000ULL)
	 | ((x << 24) & 0x0000ff0000000000ULL)
	 | ((x << 40) & 0x00ff000000000000ULL)
	 | ((x << 56) & 0xff00000000000000ULL);
#endif
}

} // namespace emacs::gnulib
