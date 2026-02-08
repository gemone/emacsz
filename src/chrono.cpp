// src/chrono.cpp
#include "chrono.hpp"
#include <cstdint>

namespace emacs
{

void
TimeUtils::gettimeofday (struct timeval *tv) noexcept
{
  auto now = std::chrono::system_clock::now ();
  auto epoch = now.time_since_epoch ();

  auto micros
    = std::chrono::duration_cast<std::chrono::microseconds> (epoch);

  if (tv)
    {
      tv->tv_sec = static_cast<time_t> (micros.count () / 1000000);
      tv->tv_usec
	= static_cast<suseconds_t> (micros.count () % 1000000);
    }
}

void
TimeUtils::nanosleep (const struct timespec *req) noexcept
{
  if (!req)
    {
      return;
    }

  auto duration = std::chrono::seconds (req->tv_sec)
		  + std::chrono::nanoseconds (req->tv_nsec);

  std::this_thread::sleep_for (duration);
}

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  void emacs_gettimeofday (struct timeval *tv)
  {
    emacs::TimeUtils::gettimeofday (tv);
  }

  void emacs_nanosleep (const struct timespec *req)
  {
    emacs::TimeUtils::nanosleep (req);
  }
}
