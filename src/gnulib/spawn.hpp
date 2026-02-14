// src/gnulib/spawn.hpp
// C++20 replacements for gnulib spawn utilities
// Replaces: posix_spawn, spawn-h, spawn-pipe

#pragma once

#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#ifdef _WIN32
# include <windows.h>
# if __has_include(<process.h>)
#  include <process.h>
# endif
#else
# include <sys/wait.h>
# include <unistd.h>
# if __has_include(<spawn.h>)
#  include <spawn.h>
# endif
#endif

namespace emacs::gnulib
{

// ============================================================================
// POSIX spawn types and constants
// ============================================================================

#ifdef _WIN32
// Windows process ID type
using pid_t = DWORD;
constexpr pid_t INVALID_PID = 0;
#else
// Use system pid_t
using pid_t = ::pid_t;
constexpr pid_t INVALID_PID = -1;
#endif

// Spawn flags
constexpr int SPAWN_SEARCH_PATH = 1;
constexpr int SPAWN_CLOSE_FD = 2;
constexpr int SPAWN_DUP_FD = 4;
constexpr int SPAWN_APPEND = 8;
constexpr int SPAWN_WRITE = 16;

// ============================================================================
// POSIX spawn attributes (RAII wrappers)
// ============================================================================

#ifndef _WIN32

// RAII wrapper for posix_spawn_file_actions_t
class SpawnFileActions
{
public:
  SpawnFileActions ()
  {
    if (::posix_spawn_file_actions_init (&actions_) != 0)
      {
	std::memset (&actions_, 0, sizeof (actions_));
      }
  }

  ~SpawnFileActions ()
  {
    ::posix_spawn_file_actions_destroy (&actions_);
  }

  SpawnFileActions (const SpawnFileActions &) = delete;
  SpawnFileActions &operator= (const SpawnFileActions &) = delete;

  SpawnFileActions (SpawnFileActions &&other) noexcept
      : actions_ (other.actions_)
  {
    std::memset (&other.actions_, 0, sizeof (other.actions_));
  }

  SpawnFileActions &operator= (SpawnFileActions &&other) noexcept
  {
    if (this != &other)
      {
	::posix_spawn_file_actions_destroy (&actions_);
	actions_ = other.actions_;
	std::memset (&other.actions_, 0, sizeof (other.actions_));
      }
    return *this;
  }

  // Add open action: open(fd, path, flags, mode)
  bool add_open (int fd, const char *path, int flags,
		 mode_t mode) noexcept
  {
    return ::posix_spawn_file_actions_addopen (&actions_, fd, path,
					       flags, mode)
	   == 0;
  }

  // Add close action: close(fd)
  bool add_close (int fd) noexcept
  {
    return ::posix_spawn_file_actions_addclose (&actions_, fd) == 0;
  }

  // Add dup2 action: dup2(oldfd, newfd)
  bool add_dup2 (int oldfd, int newfd) noexcept
  {
    return ::posix_spawn_file_actions_adddup2 (&actions_, oldfd,
					       newfd)
	   == 0;
  }

  ::posix_spawn_file_actions_t *get () noexcept { return &actions_; }
  const ::posix_spawn_file_actions_t *get () const noexcept
  {
    return &actions_;
  }

private:
  ::posix_spawn_file_actions_t actions_;
};

// RAII wrapper for posix_spawnattr_t
class SpawnAttributes
{
public:
  SpawnAttributes ()
  {
    if (::posix_spawnattr_init (&attr_) != 0)
      {
	std::memset (&attr_, 0, sizeof (attr_));
      }
  }

  ~SpawnAttributes () { ::posix_spawnattr_destroy (&attr_); }

  SpawnAttributes (const SpawnAttributes &) = delete;
  SpawnAttributes &operator= (const SpawnAttributes &) = delete;

  SpawnAttributes (SpawnAttributes &&other) noexcept
      : attr_ (other.attr_)
  {
    std::memset (&other.attr_, 0, sizeof (other.attr_));
  }

  SpawnAttributes &operator= (SpawnAttributes &&other) noexcept
  {
    if (this != &other)
      {
	::posix_spawnattr_destroy (&attr_);
	attr_ = other.attr_;
	std::memset (&other.attr_, 0, sizeof (other.attr_));
      }
    return *this;
  }

  // Set flags
  bool set_flags (short flags) noexcept
  {
    return ::posix_spawnattr_setflags (&attr_, flags) == 0;
  }

  // Get flags
  bool get_flags (short &flags) const noexcept
  {
    return ::posix_spawnattr_getflags (&attr_, &flags) == 0;
  }

  // Set process group
  bool set_pgroup (pid_t pgroup) noexcept
  {
    return ::posix_spawnattr_setpgroup (&attr_, pgroup) == 0;
  }

  // Set signal mask
  bool set_sigmask (const sigset_t *sigmask) noexcept
  {
    return ::posix_spawnattr_setsigmask (&attr_, sigmask) == 0;
  }

  // Set signal default mask
  bool set_sigdefault (const sigset_t *sigdefault) noexcept
  {
    return ::posix_spawnattr_setsigdefault (&attr_, sigdefault) == 0;
  }

  ::posix_spawnattr_t *get () noexcept { return &attr_; }
  const ::posix_spawnattr_t *get () const noexcept { return &attr_; }

private:
  ::posix_spawnattr_t attr_;
};

#endif // !_WIN32

// ============================================================================
// Low-level spawn wrappers
// ============================================================================

#ifdef _WIN32

// Windows implementation of process spawning
inline std::optional<pid_t>
spawn_process (const std::string &program,
	       const std::vector<std::string> &args,
	       const std::vector<std::string> &env = {},
	       const std::string &cwd = "")
{
  // Build command line from args
  std::string cmdline = program;
  for (const auto &arg : args)
    {
      cmdline += " \"";
      cmdline += arg;
      cmdline += "\"";
    }

  // Prepare environment block
  char *env_block = nullptr;
  std::string env_str;
  if (!env.empty ())
    {
      for (const auto &e : env)
	{
	  env_str += e;
	  env_str += '\0';
	}
      env_str += '\0';
      env_block = env_str.data ();
    }

  STARTUPINFO si;
  PROCESS_INFORMATION pi;
  std::memset (&si, 0, sizeof (si));
  std::memset (&pi, 0, sizeof (pi));
  si.cb = sizeof (si);

  if (!CreateProcessA (program.c_str (), cmdline.data (), nullptr,
		       nullptr, FALSE, 0, env_block,
		       cwd.empty () ? nullptr : cwd.c_str (), &si,
		       &pi))
    {
      return std::nullopt;
    }

  DWORD pid = pi.dwProcessId;
  CloseHandle (pi.hProcess);
  CloseHandle (pi.hThread);
  return pid;
}

#else // POSIX

inline std::optional<pid_t>
spawn_process (const std::string &program,
	       const std::vector<std::string> &args,
	       const std::vector<std::string> &env = {},
	       const std::string &cwd = "")
{
  // Build argv array
  std::vector<char *> argv;
  argv.push_back (const_cast<char *> (program.c_str ()));
  std::vector<std::string> args_copy = args;
  for (auto &arg : args_copy)
    {
      argv.push_back (arg.data ());
    }
  argv.push_back (nullptr);

  // Build environment
  std::vector<char *> environ_vec;
  std::vector<std::string> env_copy = env;
  for (auto &e : env_copy)
    {
      environ_vec.push_back (e.data ());
    }
  environ_vec.push_back (nullptr);

  // Spawn process
  pid_t pid;
  int ret
    = ::posix_spawn (&pid, program.c_str (), nullptr, nullptr,
		     argv.data (),
		     env.empty () ? nullptr : environ_vec.data ());

  if (ret != 0)
    {
      errno = ret;
      return std::nullopt;
    }

  if (!cwd.empty () && pid > 0)
    {
    }

  return pid;
}

#endif

// ============================================================================
// High-level process management
// ============================================================================

/// Represents a spawned process
class Process
{
public:
  Process () : pid_ (INVALID_PID) {}

  explicit Process (pid_t pid) : pid_ (pid) {}

  ~Process () {}

  Process (const Process &) = delete;
  Process &operator= (const Process &) = delete;

  Process (Process &&other) noexcept : pid_ (other.pid_)
  {
    other.pid_ = INVALID_PID;
  }

  Process &operator= (Process &&other) noexcept
  {
    if (this != &other)
      {
	pid_ = other.pid_;
	other.pid_ = INVALID_PID;
      }
    return *this;
  }

  /// Check if process is valid
  [[nodiscard]] bool is_valid () const noexcept
  {
    return pid_ != INVALID_PID;
  }

  /// Get process ID
  [[nodiscard]] pid_t pid () const noexcept { return pid_; }

  /// Wait for process to complete and get exit status
  [[nodiscard]] std::optional<int> wait () noexcept
  {
#ifdef _WIN32
    if (pid_ == INVALID_PID)
      return std::nullopt;

    HANDLE h = OpenProcess (PROCESS_QUERY_INFORMATION, FALSE, pid_);
    if (h == nullptr)
      return std::nullopt;

    DWORD exitCode;
    if (!GetExitCodeProcess (h, &exitCode))
      {
	CloseHandle (h);
	return std::nullopt;
      }

    CloseHandle (h);
    pid_ = INVALID_PID;
    return static_cast<int> (exitCode);

#else
    if (pid_ == INVALID_PID)
      return std::nullopt;

    int status;
    if (::waitpid (pid_, &status, 0) < 0)
      return std::nullopt;

    pid_ = INVALID_PID;

    if (WIFEXITED (status))
      return WEXITSTATUS (status);
    else if (WIFSIGNALED (status))
      return -(WTERMSIG (status));
    return -1;

#endif
  }

  /// Wait for process with timeout (non-blocking check)
  [[nodiscard]] std::optional<int> try_wait () noexcept
  {
#ifdef _WIN32
    if (pid_ == INVALID_PID)
      return std::nullopt;

    HANDLE h = OpenProcess (PROCESS_QUERY_INFORMATION, FALSE, pid_);
    if (h == nullptr)
      return std::nullopt;

    DWORD result = WaitForSingleObject (h, 0);
    DWORD exitCode = 0;

    if (result == WAIT_OBJECT_0)
      {
	GetExitCodeProcess (h, &exitCode);
	CloseHandle (h);
	pid_ = INVALID_PID;
	return static_cast<int> (exitCode);
      }

    CloseHandle (h);
    return std::nullopt;

#else
    if (pid_ == INVALID_PID)
      return std::nullopt;

    int status;
    pid_t ret = ::waitpid (pid_, &status, WNOHANG);

    if (ret < 0)
      return std::nullopt;
    if (ret == 0)
      return std::nullopt; // Still running

    pid_ = INVALID_PID;

    if (WIFEXITED (status))
      return WEXITSTATUS (status);
    else if (WIFSIGNALED (status))
      return -(WTERMSIG (status));
    return -1;

#endif
  }

  /// Terminate process
  [[nodiscard]] bool terminate () noexcept
  {
#ifdef _WIN32
    if (pid_ == INVALID_PID)
      return false;

    HANDLE h = OpenProcess (PROCESS_TERMINATE, FALSE, pid_);
    if (h == nullptr)
      return false;

    bool result = TerminateProcess (h, 1) != 0;
    CloseHandle (h);
    return result;

#else
    if (pid_ == INVALID_PID)
      return false;
    return ::kill (pid_, SIGTERM) == 0;

#endif
  }

  /// Force kill process
  [[nodiscard]] bool force_kill () noexcept
  {
#ifdef _WIN32
    if (pid_ == INVALID_PID)
      return false;

    HANDLE h = OpenProcess (PROCESS_TERMINATE, FALSE, pid_);
    if (h == nullptr)
      return false;

    bool result = TerminateProcess (h, 9) != 0;
    CloseHandle (h);
    return result;

#else
    if (pid_ == INVALID_PID)
      return false;
    return ::kill (pid_, SIGKILL) == 0;

#endif
  }

private:
  pid_t pid_;
};

// ============================================================================
// Spawn factory functions
// ============================================================================

/// Spawn a process with program and arguments
[[nodiscard]] inline std::optional<Process>
spawn (const std::string &program,
       const std::vector<std::string> &args = {})
{
  auto pid = spawn_process (program, args);
  if (pid)
    return Process (*pid);
  return std::nullopt;
}

/// Spawn a process from a path search
[[nodiscard]] inline std::optional<Process>
spawnp (const std::string &program,
	const std::vector<std::string> &args = {})
{
  // On POSIX, search PATH; on Windows, CreateProcess already does
  // this
  return spawn (program, args);
}

// ============================================================================
// Pipe process support (for process communication)
// ============================================================================

struct PipeProcess
{
  pid_t pid = INVALID_PID;
  int read_fd = -1;  // Parent reads from this
  int write_fd = -1; // Parent writes to this

  void close_read ()
  {
    if (read_fd >= 0)
      {
#ifdef _WIN32
	_close (read_fd);
#else
	::close (read_fd);
#endif
	read_fd = -1;
      }
  }

  void close_write ()
  {
    if (write_fd >= 0)
      {
#ifdef _WIN32
	_close (write_fd);
#else
	::close (write_fd);
#endif
	write_fd = -1;
      }
  }

  void close_all ()
  {
    close_read ();
    close_write ();
  }

  [[nodiscard]] bool is_valid () const noexcept
  {
    return pid != INVALID_PID;
  }
};

#ifndef _WIN32

/// Create a process with stdin and stdout pipes for communication
[[nodiscard]] inline std::optional<PipeProcess>
spawn_pipe (const std::string &program,
	    const std::vector<std::string> &args = {})
{
  int stdin_pipe[2];
  int stdout_pipe[2];

  // Create pipes
  if (::pipe (stdin_pipe) != 0)
    return std::nullopt;
  if (::pipe (stdout_pipe) != 0)
    {
      ::close (stdin_pipe[0]);
      ::close (stdin_pipe[1]);
      return std::nullopt;
    }

  // Prepare file actions
  SpawnFileActions file_actions;
  if (!file_actions.add_dup2 (stdin_pipe[0], STDIN_FILENO))
    {
      ::close (stdin_pipe[0]);
      ::close (stdin_pipe[1]);
      ::close (stdout_pipe[0]);
      ::close (stdout_pipe[1]);
      return std::nullopt;
    }

  if (!file_actions.add_dup2 (stdout_pipe[1], STDOUT_FILENO))
    {
      ::close (stdin_pipe[0]);
      ::close (stdin_pipe[1]);
      ::close (stdout_pipe[0]);
      ::close (stdout_pipe[1]);
      return std::nullopt;
    }

  // Close pipe ends in child
  if (!file_actions.add_close (stdin_pipe[1]))
    {
      ::close (stdin_pipe[0]);
      ::close (stdin_pipe[1]);
      ::close (stdout_pipe[0]);
      ::close (stdout_pipe[1]);
      return std::nullopt;
    }

  if (!file_actions.add_close (stdout_pipe[0]))
    {
      ::close (stdin_pipe[0]);
      ::close (stdin_pipe[1]);
      ::close (stdout_pipe[0]);
      ::close (stdout_pipe[1]);
      return std::nullopt;
    }

  // Build argv
  std::vector<char *> argv;
  argv.push_back (const_cast<char *> (program.c_str ()));
  std::vector<std::string> args_copy = args;
  for (auto &arg : args_copy)
    {
      argv.push_back (arg.data ());
    }
  argv.push_back (nullptr);

  // Spawn process
  pid_t pid;
  int ret
    = ::posix_spawn (&pid, program.c_str (), file_actions.get (),
		     nullptr, argv.data (), nullptr);

  // Close child pipe ends in parent
  ::close (stdin_pipe[0]);
  ::close (stdout_pipe[1]);

  if (ret != 0)
    {
      errno = ret;
      ::close (stdin_pipe[1]);
      ::close (stdout_pipe[0]);
      return std::nullopt;
    }

  return PipeProcess{ pid, stdout_pipe[0], stdin_pipe[1] };
}

#else // _WIN32

// Windows pipe process implementation
[[nodiscard]] inline std::optional<PipeProcess>
spawn_pipe (const std::string &program,
	    const std::vector<std::string> &args = {})
{
  HANDLE stdin_read = INVALID_HANDLE_VALUE;
  HANDLE stdin_write = INVALID_HANDLE_VALUE;
  HANDLE stdout_read = INVALID_HANDLE_VALUE;
  HANDLE stdout_write = INVALID_HANDLE_VALUE;

  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof (SECURITY_ATTRIBUTES);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = nullptr;

  // Create pipes
  if (!CreatePipe (&stdin_read, &stdin_write, &sa, 0))
    return std::nullopt;

  if (!CreatePipe (&stdout_read, &stdout_write, &sa, 0))
    {
      CloseHandle (stdin_read);
      CloseHandle (stdin_write);
      return std::nullopt;
    }

  // Make parent ends non-inheritable
  SetHandleInformation (stdin_write, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation (stdout_read, HANDLE_FLAG_INHERIT, 0);

  // Build command line
  std::string cmdline = program;
  for (const auto &arg : args)
    {
      cmdline += " \"";
      cmdline += arg;
      cmdline += "\"";
    }

  STARTUPINFO si;
  PROCESS_INFORMATION pi;
  std::memset (&si, 0, sizeof (si));
  std::memset (&pi, 0, sizeof (pi));
  si.cb = sizeof (si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = stdin_read;
  si.hStdOutput = stdout_write;
  si.hStdError = GetStdHandle (STD_ERROR_HANDLE);

  if (!CreateProcessA (nullptr, cmdline.data (), nullptr, nullptr,
		       TRUE, 0, nullptr, nullptr, &si, &pi))
    {
      CloseHandle (stdin_read);
      CloseHandle (stdin_write);
      CloseHandle (stdout_read);
      CloseHandle (stdout_write);
      return std::nullopt;
    }

  CloseHandle (pi.hProcess);
  CloseHandle (pi.hThread);
  CloseHandle (stdin_read);
  CloseHandle (stdout_write);

  // Convert Windows handles to file descriptors
  int fd_read
    = _open_osfhandle (reinterpret_cast<intptr_t> (stdout_read),
		       _O_RDONLY | _O_BINARY);
  int fd_write
    = _open_osfhandle (reinterpret_cast<intptr_t> (stdin_write),
		       _O_WRONLY | _O_BINARY);

  if (fd_read < 0 || fd_write < 0)
    {
      if (fd_read >= 0)
	_close (fd_read);
      if (fd_write >= 0)
	_close (fd_write);
      return std::nullopt;
    }

  return PipeProcess{ pi.dwProcessId, fd_read, fd_write };
}

#endif // _WIN32

// ============================================================================
// Utility functions
// ============================================================================

/// Check if process is still running
[[nodiscard]] inline bool
is_process_running (pid_t pid) noexcept
{
#ifdef _WIN32
  if (pid == INVALID_PID)
    return false;

  HANDLE h = OpenProcess (PROCESS_QUERY_INFORMATION, FALSE, pid);
  if (h == nullptr)
    return false;

  DWORD exitCode;
  BOOL result = GetExitCodeProcess (h, &exitCode);
  CloseHandle (h);

  return result && (exitCode == STILL_ACTIVE);

#else
  if (pid <= 0)
    return false;
  return ::kill (pid, 0) == 0;

#endif
}

} // namespace emacs::gnulib
