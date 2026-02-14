// src/gnulib/system_utils.hpp - C++20 replacement for gnulib system
// utilities Replaces: getopt-gnu, environ, getloadavg, nproc,
// pthread_sigmask, sig2str,
//           pipe2, pselect, getrandom, execinfo

#pragma once

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <random>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#ifdef _WIN32
# include <windows.h>
# if __has_include(<bcrypt.h>)
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt.lib")
#  define HAVE_BCRYPT 1
# endif
#else
# include <fcntl.h>
# include <pthread.h>
# include <sys/select.h>
# include <unistd.h>
extern char **environ;
# if __has_include(<sys/random.h>)
#  include <sys/random.h>
# endif
# if __has_include(<sys/sysctl.h>) && !defined(__linux__)
#  include <sys/sysctl.h>
# endif
# if __has_include(<sys/sysinfo.h>)
#  include <sys/sysinfo.h>
# endif
# if __has_include(<execinfo.h>)
#  include <execinfo.h>
#  define HAVE_EXECINFO 1
# endif
#endif

namespace emacs::gnulib
{

struct GetoptResult
{
  int opt;
  std::optional<std::string_view> optarg;
  int optind;
};

class Getopt
{
public:
  Getopt (int argc, char *const *argv, std::string_view optstring)
      : argc_ (argc), argv_ (argv), optstring_ (optstring)
  {
  }

  [[nodiscard]] std::optional<GetoptResult> next ()
  {
    if (optind_ >= argc_)
      return std::nullopt;

    const char *arg = argv_[optind_];

    if (arg[0] != '-' || arg[1] == '\0')
      return std::nullopt;

    if (arg[1] == '-' && arg[2] == '\0')
      {
	++optind_;
	return std::nullopt;
      }

    if (current_pos_ == 0)
      current_pos_ = 1;

    char c = arg[current_pos_];
    auto pos = optstring_.find (c);

    if (pos == std::string_view::npos)
      {
	GetoptResult result{ '?', std::nullopt, optind_ };
	advance ();
	return result;
      }

    GetoptResult result{ c, std::nullopt, optind_ };

    if (pos + 1 < optstring_.size () && optstring_[pos + 1] == ':')
      {
	if (arg[current_pos_ + 1] != '\0')
	  {
	    result.optarg = &arg[current_pos_ + 1];
	    ++optind_;
	    current_pos_ = 0;
	  }
	else if (optind_ + 1 < argc_)
	  {
	    ++optind_;
	    result.optarg = argv_[optind_];
	    ++optind_;
	    current_pos_ = 0;
	  }
	else
	  {
	    result.opt = ':';
	    advance ();
	  }
      }
    else
      {
	advance ();
      }

    result.optind = optind_;
    return result;
  }

  [[nodiscard]] int index () const noexcept { return optind_; }

  void reset ()
  {
    optind_ = 1;
    current_pos_ = 0;
  }

private:
  int argc_;
  char *const *argv_;
  std::string_view optstring_;
  int optind_ = 1;
  std::size_t current_pos_ = 0;

  void advance ()
  {
    ++current_pos_;
    if (argv_[optind_][current_pos_] == '\0')
      {
	++optind_;
	current_pos_ = 0;
      }
  }
};

struct LongOption
{
  std::string_view name;
  int has_arg;
  int *flag;
  int val;

  static constexpr int no_argument = 0;
  static constexpr int required_argument = 1;
  static constexpr int optional_argument = 2;
};

[[nodiscard]] inline std::vector<std::string>
get_environ ()
{
#ifdef _WIN32
  std::vector<std::string> result;
  LPCH env = GetEnvironmentStrings ();
  if (env)
    {
      for (LPCH p = env; *p; p += strlen (p) + 1)
	{
	  result.emplace_back (p);
	}
      FreeEnvironmentStrings (env);
    }
  return result;
#else
  std::vector<std::string> result;
  for (char **e = environ; *e; ++e)
    {
      result.emplace_back (*e);
    }
  return result;
#endif
}

[[nodiscard]] inline std::optional<std::string>
getenv_safe (std::string_view name)
{
  std::string name_str (name);
#ifdef _WIN32
  char buffer[32768];
  DWORD len = GetEnvironmentVariableA (name_str.c_str (), buffer,
				       sizeof (buffer));
  if (len > 0 && len < sizeof (buffer))
    return std::string (buffer, len);
  return std::nullopt;
#else
  const char *val = std::getenv (name_str.c_str ());
  if (val)
    return std::string (val);
  return std::nullopt;
#endif
}

inline bool
setenv_safe (std::string_view name, std::string_view value,
	     bool overwrite = true)
{
  std::string name_str (name);
  std::string value_str (value);
#ifdef _WIN32
  if (!overwrite
      && GetEnvironmentVariableA (name_str.c_str (), nullptr, 0) > 0)
    return true;
  return SetEnvironmentVariableA (name_str.c_str (),
				  value_str.c_str ())
	 != 0;
#else
  return ::setenv (name_str.c_str (), value_str.c_str (),
		   overwrite ? 1 : 0)
	 == 0;
#endif
}

inline bool
unsetenv_safe (std::string_view name)
{
  std::string name_str (name);
#ifdef _WIN32
  return SetEnvironmentVariableA (name_str.c_str (), nullptr) != 0;
#else
  return ::unsetenv (name_str.c_str ()) == 0;
#endif
}

[[nodiscard]] inline unsigned int
nproc ()
{
  unsigned int n = std::thread::hardware_concurrency ();
  return n > 0 ? n : 1;
}

[[nodiscard]] inline unsigned int
nproc_available ()
{
#ifdef _WIN32
  SYSTEM_INFO sysinfo;
  GetSystemInfo (&sysinfo);
  return sysinfo.dwNumberOfProcessors;
#elif defined(__linux__)
  cpu_set_t cpuset;
  if (sched_getaffinity (0, sizeof (cpuset), &cpuset) == 0)
    return static_cast<unsigned int> (CPU_COUNT (&cpuset));
  return nproc ();
#else
  return nproc ();
#endif
}

[[nodiscard]] inline int
getloadavg (double loadavg[], int nelem)
{
  if (nelem <= 0)
    return -1;

#ifdef _WIN32
  return -1;
#elif defined(__linux__)
  std::ifstream loadfile ("/proc/loadavg");
  if (!loadfile)
    return -1;

  int count = 0;
  for (int i = 0; i < nelem && i < 3; ++i)
    {
      if (!(loadfile >> loadavg[i]))
	break;
      ++count;
    }
  return count;
#elif defined(__APPLE__) || defined(__FreeBSD__) \
  || defined(__OpenBSD__)
  return ::getloadavg (loadavg, nelem);
#else
  return -1;
#endif
}

#ifndef _WIN32

inline int
sigaddset_safe (sigset_t *set, int signum)
{
  return sigaddset (set, signum);
}

inline int
sigdelset_safe (sigset_t *set, int signum)
{
  return sigdelset (set, signum);
}

inline int
sigemptyset_safe (sigset_t *set)
{
  return sigemptyset (set);
}

inline int
sigfillset_safe (sigset_t *set)
{
  return sigfillset (set);
}

inline int
sigismember_safe (const sigset_t *set, int signum)
{
  return sigismember (set, signum);
}

inline int
pthread_sigmask_safe (int how, const sigset_t *set, sigset_t *oldset)
{
  return pthread_sigmask (how, set, oldset);
}

#endif

[[nodiscard]] inline std::string_view
sigabbrev_np (int signum)
{
  switch (signum)
    {
#define SIG_CASE(name) \
  case SIG##name:      \
    return #name
#ifdef SIGABRT
      SIG_CASE (ABRT);
#endif
#ifdef SIGALRM
      SIG_CASE (ALRM);
#endif
#ifdef SIGBUS
      SIG_CASE (BUS);
#endif
#ifdef SIGCHLD
      SIG_CASE (CHLD);
#endif
#ifdef SIGCONT
      SIG_CASE (CONT);
#endif
#ifdef SIGFPE
      SIG_CASE (FPE);
#endif
#ifdef SIGHUP
      SIG_CASE (HUP);
#endif
#ifdef SIGILL
      SIG_CASE (ILL);
#endif
#ifdef SIGINT
      SIG_CASE (INT);
#endif
#ifdef SIGKILL
      SIG_CASE (KILL);
#endif
#ifdef SIGPIPE
      SIG_CASE (PIPE);
#endif
#ifdef SIGQUIT
      SIG_CASE (QUIT);
#endif
#ifdef SIGSEGV
      SIG_CASE (SEGV);
#endif
#ifdef SIGSTOP
      SIG_CASE (STOP);
#endif
#ifdef SIGTERM
      SIG_CASE (TERM);
#endif
#ifdef SIGTSTP
      SIG_CASE (TSTP);
#endif
#ifdef SIGTTIN
      SIG_CASE (TTIN);
#endif
#ifdef SIGTTOU
      SIG_CASE (TTOU);
#endif
#ifdef SIGUSR1
      SIG_CASE (USR1);
#endif
#ifdef SIGUSR2
      SIG_CASE (USR2);
#endif
#ifdef SIGPOLL
      SIG_CASE (POLL);
#endif
#ifdef SIGPROF
      SIG_CASE (PROF);
#endif
#ifdef SIGSYS
      SIG_CASE (SYS);
#endif
#ifdef SIGTRAP
      SIG_CASE (TRAP);
#endif
#ifdef SIGURG
      SIG_CASE (URG);
#endif
#ifdef SIGVTALRM
      SIG_CASE (VTALRM);
#endif
#ifdef SIGXCPU
      SIG_CASE (XCPU);
#endif
#ifdef SIGXFSZ
      SIG_CASE (XFSZ);
#endif
#undef SIG_CASE
    default:
      return "";
    }
}

[[nodiscard]] inline std::string_view
sigdescr_np (int signum)
{
  switch (signum)
    {
#ifdef SIGABRT
    case SIGABRT:
      return "Aborted";
#endif
#ifdef SIGALRM
    case SIGALRM:
      return "Alarm clock";
#endif
#ifdef SIGBUS
    case SIGBUS:
      return "Bus error";
#endif
#ifdef SIGCHLD
    case SIGCHLD:
      return "Child exited";
#endif
#ifdef SIGCONT
    case SIGCONT:
      return "Continued";
#endif
#ifdef SIGFPE
    case SIGFPE:
      return "Floating point exception";
#endif
#ifdef SIGHUP
    case SIGHUP:
      return "Hangup";
#endif
#ifdef SIGILL
    case SIGILL:
      return "Illegal instruction";
#endif
#ifdef SIGINT
    case SIGINT:
      return "Interrupt";
#endif
#ifdef SIGKILL
    case SIGKILL:
      return "Killed";
#endif
#ifdef SIGPIPE
    case SIGPIPE:
      return "Broken pipe";
#endif
#ifdef SIGQUIT
    case SIGQUIT:
      return "Quit";
#endif
#ifdef SIGSEGV
    case SIGSEGV:
      return "Segmentation fault";
#endif
#ifdef SIGSTOP
    case SIGSTOP:
      return "Stopped (signal)";
#endif
#ifdef SIGTERM
    case SIGTERM:
      return "Terminated";
#endif
#ifdef SIGTSTP
    case SIGTSTP:
      return "Stopped";
#endif
#ifdef SIGTTIN
    case SIGTTIN:
      return "Stopped (tty input)";
#endif
#ifdef SIGTTOU
    case SIGTTOU:
      return "Stopped (tty output)";
#endif
#ifdef SIGUSR1
    case SIGUSR1:
      return "User defined signal 1";
#endif
#ifdef SIGUSR2
    case SIGUSR2:
      return "User defined signal 2";
#endif
    default:
      return "Unknown signal";
    }
}

inline int
sig2str (int signum, char *str)
{
  auto abbrev = sigabbrev_np (signum);
  if (abbrev.empty ())
    return -1;
  std::memcpy (str, abbrev.data (), abbrev.size ());
  str[abbrev.size ()] = '\0';
  return 0;
}

inline int
str2sig (const char *str, int *signum)
{
  std::string_view s (str);

#define CHECK_SIG(name)    \
  if (s == #name)          \
    {                      \
      *signum = SIG##name; \
      return 0;            \
    }

#ifdef SIGABRT
  CHECK_SIG (ABRT)
#endif
#ifdef SIGALRM
  CHECK_SIG (ALRM)
#endif
#ifdef SIGBUS
  CHECK_SIG (BUS)
#endif
#ifdef SIGCHLD
  CHECK_SIG (CHLD)
#endif
#ifdef SIGCONT
  CHECK_SIG (CONT)
#endif
#ifdef SIGFPE
  CHECK_SIG (FPE)
#endif
#ifdef SIGHUP
  CHECK_SIG (HUP)
#endif
#ifdef SIGILL
  CHECK_SIG (ILL)
#endif
#ifdef SIGINT
  CHECK_SIG (INT)
#endif
#ifdef SIGKILL
  CHECK_SIG (KILL)
#endif
#ifdef SIGPIPE
  CHECK_SIG (PIPE)
#endif
#ifdef SIGQUIT
  CHECK_SIG (QUIT)
#endif
#ifdef SIGSEGV
  CHECK_SIG (SEGV)
#endif
#ifdef SIGSTOP
  CHECK_SIG (STOP)
#endif
#ifdef SIGTERM
  CHECK_SIG (TERM)
#endif
#ifdef SIGTSTP
  CHECK_SIG (TSTP)
#endif
#ifdef SIGTTIN
  CHECK_SIG (TTIN)
#endif
#ifdef SIGTTOU
  CHECK_SIG (TTOU)
#endif
#ifdef SIGUSR1
  CHECK_SIG (USR1)
#endif
#ifdef SIGUSR2
  CHECK_SIG (USR2)
#endif

#undef CHECK_SIG

  return -1;
}

#ifndef _WIN32

struct PipeFds
{
  int read_fd = -1;
  int write_fd = -1;

  void close_read ()
  {
    if (read_fd >= 0)
      {
	::close (read_fd);
	read_fd = -1;
      }
  }

  void close_write ()
  {
    if (write_fd >= 0)
      {
	::close (write_fd);
	write_fd = -1;
      }
  }

  void close_all ()
  {
    close_read ();
    close_write ();
  }
};

[[nodiscard]] inline std::optional<PipeFds>
pipe2_safe (int flags)
{
  int fds[2];
# if defined(__linux__) || defined(__FreeBSD__) \
   || defined(__OpenBSD__)
  if (::pipe2 (fds, flags) != 0)
    return std::nullopt;
# else
  if (::pipe (fds) != 0)
    return std::nullopt;

  if (flags & O_CLOEXEC)
    {
      fcntl (fds[0], F_SETFD, FD_CLOEXEC);
      fcntl (fds[1], F_SETFD, FD_CLOEXEC);
    }
  if (flags & O_NONBLOCK)
    {
      fcntl (fds[0], F_SETFL, O_NONBLOCK);
      fcntl (fds[1], F_SETFL, O_NONBLOCK);
    }
# endif

  return PipeFds{ fds[0], fds[1] };
}

[[nodiscard]] inline int
pselect_safe (int nfds, fd_set *readfds, fd_set *writefds,
	      fd_set *exceptfds, const struct timespec *timeout,
	      const sigset_t *sigmask)
{
  return ::pselect (nfds, readfds, writefds, exceptfds, timeout,
		    sigmask);
}

#endif

[[nodiscard]] inline bool
getrandom_safe (void *buffer, std::size_t length,
		unsigned int flags = 0)
{
#if defined(__linux__) && __has_include(<sys/random.h>)
  auto *buf = static_cast<unsigned char *> (buffer);
  while (length > 0)
    {
      ssize_t result = ::getrandom (buf, length, flags);
      if (result < 0)
	{
	  if (errno == EINTR)
	    continue;
	  return false;
	}
      buf += result;
      length -= static_cast<std::size_t> (result);
    }
  return true;

#elif defined(__APPLE__) || defined(__FreeBSD__) \
  || defined(__OpenBSD__)
  (void) flags;
  arc4random_buf (buffer, length);
  return true;

#elif defined(_WIN32) && defined(HAVE_BCRYPT)
  (void) flags;
  return BCRYPT_SUCCESS (
    BCryptGenRandom (NULL, static_cast<PUCHAR> (buffer),
		     static_cast<ULONG> (length),
		     BCRYPT_USE_SYSTEM_PREFERRED_RNG));

#elif defined(_WIN32)
  (void) flags;
  (void) buffer;
  (void) length;
  return false;

#else
  (void) flags;
  std::random_device rd;
  std::uniform_int_distribution<unsigned int> dist (0, 255);
  for (std::size_t i = 0; i < length; ++i)
    {
      buf[i] = static_cast<unsigned char> (dist (rd));
    }
  return true;
#endif
}

template <typename T>
[[nodiscard]] std::optional<T>
getrandom_value ()
{
  T value;
  if (getrandom_safe (&value, sizeof (value)))
    return value;
  return std::nullopt;
}

[[nodiscard]] inline std::optional<std::uint64_t>
getrandom_u64 ()
{
  return getrandom_value<std::uint64_t> ();
}

[[nodiscard]] inline std::optional<std::uint32_t>
getrandom_u32 ()
{
  return getrandom_value<std::uint32_t> ();
}

#ifdef HAVE_EXECINFO

[[nodiscard]] inline std::vector<std::string>
get_backtrace (int max_frames = 64)
{
  std::vector<void *> buffer (static_cast<std::size_t> (max_frames));
  int nframes = ::backtrace (buffer.data (), max_frames);

  std::vector<std::string> result;
  if (nframes <= 0)
    return result;

  char **symbols = ::backtrace_symbols (buffer.data (), nframes);
  if (!symbols)
    return result;

  result.reserve (static_cast<std::size_t> (nframes));
  for (int i = 0; i < nframes; ++i)
    {
      result.emplace_back (symbols[i]);
    }

  std::free (symbols);
  return result;
}

inline void
print_backtrace (int fd = STDERR_FILENO, int max_frames = 64)
{
  std::vector<void *> buffer (static_cast<std::size_t> (max_frames));
  int nframes = ::backtrace (buffer.data (), max_frames);
  if (nframes > 0)
    {
      ::backtrace_symbols_fd (buffer.data (), nframes, fd);
    }
}

#else

[[nodiscard]] inline std::vector<std::string>
get_backtrace (int = 64)
{
  return {};
}

inline void
print_backtrace (int = 2, int = 64)
{
}

#endif

}
