// src/chrono.hpp
#pragma once

#include <chrono>
#include <cstdint>
#include <sys/time.h>
#include <sys/types.h>
#include <thread>

namespace emacs
{

/**
 * Time utilities - C++20 std::chrono replacements for gnulib
 *
 * Replaces:
 * - gettimeofday() → std::chrono::system_clock::now() for current
 * time
 * - nanosleep() → std::this_thread::sleep_for() for high-resolution
 * sleep
 *
 * Uses:
 * - std::chrono exclusively (no <sys/time.h> or <time.h> functions)
 * - std::this_thread for threading
 */

class TimeUtils
{
public:
  TimeUtils () noexcept = default;
  ~TimeUtils () noexcept = default;

  // gettimeofday() - get current time with microsecond precision
  static void gettimeofday (struct timeval *tv) noexcept;

  // nanosleep() - high-resolution sleep
  static void nanosleep (const struct timespec *req) noexcept;
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // gettimeofday() - get current time with microsecond precision
  void emacs_gettimeofday (struct timeval *tv);

  // nanosleep() - high-resolution sleep
  void emacs_nanosleep (const struct timespec *req);
}
