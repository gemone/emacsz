// src/chrono.cpp
#include <chrono>

#include "chrono.hpp"

namespace emacs
{

TimeUtils::TimeUtils () {}

TimeUtils::~TimeUtils () {}

void
TimeUtils::gettimeofday (struct timeval *tv) noexcept
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
}

void
TimeUtils::nanosleep (const struct timespec *req) noexcept
{
  std::chrono::nanoseconds dur (req->tv_sec, req->tv_nsec);
  std::this_thread::sleep_for (dur);
}

} // namespace emacs
