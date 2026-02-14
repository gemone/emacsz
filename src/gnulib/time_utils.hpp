// src/gnulib/time_utils.hpp
// C++20 replacements for gnulib time functions
// Replaces: timespec, gettime, gettimeofday, mktime, timegm, time_rz,
// nanosleep, etc.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <chrono>
#include <ctime>
#include <ratio>
#include <thread>

#ifdef _WIN32
# include <windows.h>
#else
# include <sys/time.h>
# include <time.h>
#endif

namespace emacs::gnulib
{

constexpr long TIMESPEC_HZ = 1000000000L;
constexpr int LOG10_TIMESPEC_HZ = 9;

struct timespec_t
{
  time_t tv_sec;
  long tv_nsec;

  [[nodiscard]] constexpr bool
  operator== (const timespec_t &other) const noexcept
  {
    return tv_sec == other.tv_sec && tv_nsec == other.tv_nsec;
  }

  [[nodiscard]] constexpr bool
  operator< (const timespec_t &other) const noexcept
  {
    if (tv_sec != other.tv_sec)
      return tv_sec < other.tv_sec;
    return tv_nsec < other.tv_nsec;
  }

  [[nodiscard]] constexpr bool
  operator<= (const timespec_t &other) const noexcept
  {
    return !(other < *this);
  }

  [[nodiscard]] constexpr bool
  operator> (const timespec_t &other) const noexcept
  {
    return other < *this;
  }

  [[nodiscard]] constexpr bool
  operator>= (const timespec_t &other) const noexcept
  {
    return !(*this < other);
  }
};

[[nodiscard]] constexpr timespec_t
make_timespec (time_t sec, long nsec) noexcept
{
  return { sec, nsec };
}

[[nodiscard]] constexpr int
timespec_cmp (timespec_t a, timespec_t b) noexcept
{
  if (a.tv_sec < b.tv_sec)
    return -1;
  if (a.tv_sec > b.tv_sec)
    return 1;
  if (a.tv_nsec < b.tv_nsec)
    return -1;
  if (a.tv_nsec > b.tv_nsec)
    return 1;
  return 0;
}

[[nodiscard]] constexpr int
timespec_sign (timespec_t a) noexcept
{
  if (a.tv_sec > 0 || (a.tv_sec == 0 && a.tv_nsec > 0))
    return 1;
  if (a.tv_sec < 0 || a.tv_nsec < 0)
    return -1;
  return 0;
}

[[nodiscard]] inline timespec_t
timespec_add (timespec_t a, timespec_t b) noexcept
{
  timespec_t result;
  result.tv_sec = a.tv_sec + b.tv_sec;
  result.tv_nsec = a.tv_nsec + b.tv_nsec;
  if (result.tv_nsec >= TIMESPEC_HZ)
    {
      result.tv_sec++;
      result.tv_nsec -= TIMESPEC_HZ;
    }
  return result;
}

[[nodiscard]] inline timespec_t
timespec_sub (timespec_t a, timespec_t b) noexcept
{
  timespec_t result;
  result.tv_sec = a.tv_sec - b.tv_sec;
  result.tv_nsec = a.tv_nsec - b.tv_nsec;
  if (result.tv_nsec < 0)
    {
      result.tv_sec--;
      result.tv_nsec += TIMESPEC_HZ;
    }
  return result;
}

[[nodiscard]] constexpr double
timespec_to_double (timespec_t ts) noexcept
{
  return static_cast<double> (ts.tv_sec)
	 + static_cast<double> (ts.tv_nsec) / TIMESPEC_HZ;
}

[[nodiscard]] constexpr timespec_t
double_to_timespec (double d) noexcept
{
  time_t sec = static_cast<time_t> (d);
  long nsec = static_cast<long> ((d - sec) * TIMESPEC_HZ);
  if (nsec < 0)
    {
      sec--;
      nsec += TIMESPEC_HZ;
    }
  return { sec, nsec };
}

[[nodiscard]] inline timespec_t
current_timespec () noexcept
{
#if __cpp_lib_chrono >= 201907L
  auto now = std::chrono::system_clock::now ();
  auto duration = now.time_since_epoch ();
  auto sec
    = std::chrono::duration_cast<std::chrono::seconds> (duration);
  auto nsec
    = std::chrono::duration_cast<std::chrono::nanoseconds> (duration)
      - std::chrono::duration_cast<std::chrono::nanoseconds> (sec);
  return { sec.count (), nsec.count () };
#else
  struct timespec ts;
# ifdef _WIN32
  FILETIME ft;
  GetSystemTimeAsFileTime (&ft);
  ULARGE_INTEGER ull;
  ull.LowPart = ft.dwLowDateTime;
  ull.HighPart = ft.dwHighDateTime;
  ts.tv_sec = (ull.QuadPart / 10000000ULL) - 11644473600ULL;
  ts.tv_nsec = (ull.QuadPart % 10000000ULL) * 100;
# else
  clock_gettime (CLOCK_REALTIME, &ts);
# endif
  return { ts.tv_sec, ts.tv_nsec };
#endif
}

inline void
gettime (timespec_t *ts) noexcept
{
  *ts = current_timespec ();
}

[[nodiscard]] inline long
gettime_res () noexcept
{
#ifdef _WIN32
  return 100;
#else
  struct timespec res;
  if (clock_getres (CLOCK_REALTIME, &res) == 0)
    return res.tv_nsec;
  return 1;
#endif
}

inline int
gettimeofday_compat (struct timeval *tv,
		     [[maybe_unused]] void *tz) noexcept
{
  if (!tv)
    return -1;
  timespec_t ts = current_timespec ();
  tv->tv_sec = ts.tv_sec;
  tv->tv_usec = ts.tv_nsec / 1000;
  return 0;
}

inline int
nanosleep_compat (const timespec_t *req, timespec_t *rem) noexcept
{
  if (!req || req->tv_sec < 0 || req->tv_nsec < 0
      || req->tv_nsec >= TIMESPEC_HZ)
    return -1;

  auto duration = std::chrono::seconds (req->tv_sec)
		  + std::chrono::nanoseconds (req->tv_nsec);
  std::this_thread::sleep_for (duration);

  if (rem)
    *rem = { 0, 0 };
  return 0;
}

[[nodiscard]] inline time_t
timegm_compat (struct tm *tm) noexcept
{
#ifdef _WIN32
  return _mkgmtime (tm);
#elif defined(__GLIBC__) || defined(__FreeBSD__) || defined(__APPLE__)
  return timegm (tm);
#else
  time_t t;
  struct tm tmp = *tm;
  tmp.tm_isdst = 0;
  char *tz = getenv ("TZ");
  setenv ("TZ", "UTC", 1);
  tzset ();
  t = mktime (&tmp);
  if (tz)
    setenv ("TZ", tz, 1);
  else
    unsetenv ("TZ");
  tzset ();
  return t;
#endif
}

template <typename Clock = std::chrono::system_clock> class timer
{
public:
  using clock_type = Clock;
  using time_point = typename Clock::time_point;
  using duration = typename Clock::duration;

  timer () : start_ (Clock::now ()) {}

  void reset () noexcept { start_ = Clock::now (); }

  [[nodiscard]] duration elapsed () const noexcept
  {
    return Clock::now () - start_;
  }

  [[nodiscard]] double elapsed_seconds () const noexcept
  {
    return std::chrono::duration<double> (elapsed ()).count ();
  }

  [[nodiscard]] long long elapsed_milliseconds () const noexcept
  {
    return std::chrono::duration_cast<std::chrono::milliseconds> (
	     elapsed ())
      .count ();
  }

  [[nodiscard]] long long elapsed_nanoseconds () const noexcept
  {
    return std::chrono::duration_cast<std::chrono::nanoseconds> (
	     elapsed ())
      .count ();
  }

private:
  time_point start_;
};

using system_timer = timer<std::chrono::system_clock>;
using steady_timer = timer<std::chrono::steady_clock>;
using high_res_timer = timer<std::chrono::high_resolution_clock>;

template <typename Duration>
inline void
sleep_for (Duration duration) noexcept
{
  std::this_thread::sleep_for (duration);
}

inline void
sleep_ns (long long nanoseconds) noexcept
{
  std::this_thread::sleep_for (
    std::chrono::nanoseconds (nanoseconds));
}

inline void
sleep_us (long long microseconds) noexcept
{
  std::this_thread::sleep_for (
    std::chrono::microseconds (microseconds));
}

inline void
sleep_ms (long long milliseconds) noexcept
{
  std::this_thread::sleep_for (
    std::chrono::milliseconds (milliseconds));
}

inline void
sleep_s (long long seconds) noexcept
{
  std::this_thread::sleep_for (std::chrono::seconds (seconds));
}

} // namespace emacs::gnulib
