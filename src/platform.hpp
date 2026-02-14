#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cstdint>
#include <string_view>

namespace emacs
{

enum class Platform
{
  UNKNOWN,
  WINDOWS,
  LINUX,
  MACOS,
  BSD,
  HAIKU,
  ANDROID
};

enum class Architecture
{
  UNKNOWN,
  X86_32,
  X86_64,
  ARM32,
  ARM64,
  PPC,
  PPC64,
  RISCV
};

inline Platform
get_platform () noexcept
{
#if defined(_WIN32) || defined(_WIN64)
  return Platform::WINDOWS;
#elif defined(__APPLE__)
# include <TargetConditionals.h>
# if TARGET_OS_MAC
  return Platform::MACOS;
# elif TARGET_OS_IPHONE
  return Platform::UNKNOWN;
# else
  return Platform::UNKNOWN;
# endif
#elif defined(__linux__)
  return Platform::LINUX;
#elif defined(__FreeBSD__) || defined(__NetBSD__) \
  || defined(__OpenBSD__)
  return Platform::BSD;
#elif defined(__HAIKU__)
  return Platform::HAIKU;
#elif defined(__ANDROID__)
  return Platform::ANDROID;
#else
  return Platform::UNKNOWN;
#endif
}

inline Architecture
get_architecture () noexcept
{
#if defined(_M_X64) || defined(__x86_64__)
  return Architecture::X86_64;
#elif defined(_M_IX86) || defined(__i386__)
  return Architecture::X86_32;
#elif defined(_M_ARM64) || defined(__aarch64__)
  return Architecture::ARM64;
#elif defined(_M_ARM) || defined(__arm__)
  return Architecture::ARM32;
#elif defined(__powerpc64__)
  return Architecture::PPC64;
#elif defined(__powerpc__)
  return Architecture::PPC;
#elif defined(__riscv) && (__riscv_xlen == 64)
  return Architecture::RISCV;
#else
  return Architecture::UNKNOWN;
#endif
}

inline constexpr bool
is_windows () noexcept
{
#if defined(_WIN32) || defined(_WIN64)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_unix () noexcept
{
#if defined(__unix__) || defined(__unix) || defined(__APPLE__) \
  || defined(__linux__) || defined(__FreeBSD__)                \
  || defined(__NetBSD__) || defined(__OpenBSD__)               \
  || defined(__HAIKU__)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_linux () noexcept
{
#ifdef __linux__
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_macos () noexcept
{
#if defined(__APPLE__) && defined(__MACH__)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_bsd () noexcept
{
#if defined(__FreeBSD__) || defined(__NetBSD__) \
  || defined(__OpenBSD__)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_haiku () noexcept
{
#ifdef __HAIKU__
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_android () noexcept
{
#ifdef __ANDROID__
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_posix () noexcept
{
#if defined(_POSIX_VERSION) || defined(__unix__) || defined(__unix) \
  || defined(__APPLE__) || defined(__linux__)                       \
  || defined(__FreeBSD__) || defined(__NetBSD__)                    \
  || defined(__OpenBSD__) || defined(__HAIKU__)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_x86 () noexcept
{
#if defined(__i386__) || defined(__x86_64__) || defined(_M_IX86) \
  || defined(_M_X64)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_arm () noexcept
{
#if defined(__arm__) || defined(__aarch64__) || defined(_M_ARM) \
  || defined(_M_ARM64)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_64bit () noexcept
{
#if defined(__x86_64__) || defined(__aarch64__) \
  || defined(__powerpc64__) || defined(_M_X64) || defined(_M_ARM64)
  return true;
#else
  return false;
#endif
}

inline constexpr bool
is_little_endian () noexcept
{
#if defined(__BYTE_ORDER__)
# if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  return true;
# else
  return false;
# endif
#else
  const int n = 1;
  return *(char *) &n == 1;
#endif
}

inline constexpr bool
is_big_endian () noexcept
{
  return !is_little_endian ();
}

struct PlatformFeatures
{
  bool has_posix_threads;
  bool has_pthreads;
  bool has_windows_threads;
  bool has_inotify;
  bool has_kqueue;
  bool has_epoll;
  bool has_select;
  bool has_poll;
  bool has_unix_domain_sockets;
  bool has_named_pipes;
  bool has_shared_memory;
  bool has_semaphores;
  bool has_futex;
  bool has_fork;
  bool has_execve;
  bool has_sigaction;
  bool has_termios;
  bool has_terminfo;
  bool has_ncurses;
};

inline PlatformFeatures
get_platform_features () noexcept
{
  PlatformFeatures features{};
  features.has_posix_threads = is_posix ()
#if defined(_POSIX_THREADS) && _POSIX_THREADS > 0
			       && true
#else
			       && false
#endif
    ;
  features.has_pthreads = is_posix ()
#if defined(PTHREAD_CREATE_JOINABLE)
			  && true
#else
			  && false
#endif
    ;
  features.has_windows_threads = is_windows ();

  features.has_inotify = is_linux ()
#if defined(__linux__)
			 && true
#else
			 && false
#endif
    ;
  features.has_kqueue = is_bsd () || is_macos ();
  features.has_epoll = is_linux ();
  features.has_select = is_posix ()
#if defined(FD_SETSIZE) || defined(__unix__)
			&& true
#else
			&& false
#endif
    ;
  features.has_poll = is_posix ()
#if defined(POLLIN)
		      && true
#else
		      && false
#endif
    ;
  features.has_unix_domain_sockets = is_posix ()
#if defined(AF_UNIX)
				     && true
#else
				     && false
#endif
    ;
  features.has_named_pipes = is_posix ()
#if defined(S_IFIFO)
			     && true
#else
			     && false
#endif
    ;
  features.has_shared_memory = is_posix ()
#if defined(__MAP_SHARED) || defined(SHM_HUGETLB)
			       && true
#else
			       && false
#endif
    ;
  features.has_semaphores = is_posix ()
#if defined(SEM_NAME_LEN) || defined(__USE_POSIX_SEMAPHORES)
			    && true
#else
			    && false
#endif
    ;
  features.has_futex = is_linux ()
#if defined(__NR_futex)
		       && true
#else
		       && false
#endif
    ;
  features.has_fork = is_posix ()
#if defined(FORK)
		      && true
#else
		      && false
#endif
    ;
  features.has_execve = is_posix ()
#if defined(EXECVE)
			&& true
#else
			&& false
#endif
    ;
  features.has_sigaction = is_posix ()
#if defined(SIGACTION)
			   && true
#else
			   && false
#endif
    ;
  features.has_termios = is_posix ()
#if defined(TERM_H)
			 && true
#else
			 && false
#endif
    ;
  features.has_terminfo = is_posix ()
#if defined(TERMINFO)
			  && true
#else
			  && false
#endif
    ;
  features.has_ncurses = is_posix ()
#if defined(NCURSES_VERSION)
			 && true
#else
			 && false
#endif
    ;

  return features;
}

inline std::string_view
get_platform_name () noexcept
{
  switch (get_platform ())
    {
    case Platform::WINDOWS:
      return "Windows";
    case Platform::LINUX:
      return "Linux";
    case Platform::MACOS:
      return "macOS";
    case Platform::BSD:
      return "BSD";
    case Platform::HAIKU:
      return "Haiku";
    case Platform::ANDROID:
      return "Android";
    default:
      return "Unknown";
    }
}

inline std::string_view
get_architecture_name () noexcept
{
  switch (get_architecture ())
    {
    case Architecture::X86_32:
      return "x86_32";
    case Architecture::X86_64:
      return "x86_64";
    case Architecture::ARM32:
      return "ARM32";
    case Architecture::ARM64:
      return "ARM64";
    case Architecture::PPC:
      return "PPC";
    case Architecture::PPC64:
      return "PPC64";
    case Architecture::RISCV:
      return "RISC-V";
    default:
      return "Unknown";
    }
}

inline constexpr int
get_pointer_size () noexcept
{
#if defined(__PTR_WIDTH__)
  return __PTR_WIDTH__ / 8;
#elif defined(__SIZEOF_POINTER__)
  return __SIZEOF_POINTER__;
#else
  return sizeof (void *);
#endif
}

}
