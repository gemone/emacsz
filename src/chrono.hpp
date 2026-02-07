// src/chrono.hpp
#pragma once

#include <chrono>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

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
  ~TimeUtils () = default;

  // gettimeofday() - get current time with microsecond precision
  [[nodiscard]] void gettimeofday (struct timeval *tv) noexcept
  {
    auto now = std::chrono::system_clock::now ();
    auto epoch = now.time_since_epoch ();
    std::chrono::duration<std::int64_t> micros = epoch;
    auto seconds = std::chrono::duration_cast<std::int64_t> (micros);

    if (tv)
      {
	tv->tv_sec = static_cast<time_t> (seconds.count ());
	tv->tv_usec
	  = static_cast<__suseconds_t> (micros.count () % 1000000);
      }
  }

  // nanosleep() - high-resolution sleep
  void nanosleep (const struct timespec *req) noexcept
  {
    std::chrono::nanoseconds dur (req->tv_sec, req->tv_nsec);
    std::this_thread::sleep_for (dur);
  }
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
