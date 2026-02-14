// src/gnulib/safe_io.hpp
// C++20 replacements for gnulib safe I/O
// Replaces: safe-read, safe-write, full-read, full-write

#pragma once

#include <cerrno>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <sys/types.h>

#ifdef _WIN32
# include <fcntl.h>
# include <io.h>
# define WIN32_LEAN_AND_MEAN
# include <windows.h>
// Windows uses different names for POSIX I/O functions
# ifndef STDIN_FILENO
#  define STDIN_FILENO 0
# endif
# ifndef STDOUT_FILENO
#  define STDOUT_FILENO 1
# endif
# ifndef STDERR_FILENO
#  define STDERR_FILENO 2
# endif
// ssize_t is not defined on Windows
# ifdef _WIN64
typedef __int64 ssize_t;
# else
typedef int ssize_t;
# endif
#else
# include <fcntl.h>
# include <sys/stat.h>
# include <unistd.h>
#endif

namespace emacs::gnulib
{

// Default buffer size for file operations
constexpr size_t SAFE_IO_BUFFER_SIZE = 8192;

// Maximum size for read_file operations (16 MB by default)
constexpr size_t MAX_FILE_SIZE = 16 * 1024 * 1024;

//============================================================================
// Safe Read/Write - retry on EINTR
//============================================================================

/// Read with EINTR retry - returns bytes read or -1 on error.
/// A return value of 0 indicates EOF.
[[nodiscard]] inline ssize_t
safe_read (int fd, void *buf, size_t count) noexcept
{
  ssize_t result;
  do
    {
#ifdef _WIN32
      // Windows read can only handle int-sized counts
      unsigned int to_read = count > INT_MAX
			       ? static_cast<unsigned int> (INT_MAX)
			       : static_cast<unsigned int> (count);
      result = _read (fd, buf, to_read);
#else
      result = ::read (fd, buf, count);
#endif
    }
  while (result < 0 && errno == EINTR);
  return result;
}

/// Write with EINTR retry - returns bytes written or -1 on error.
[[nodiscard]] inline ssize_t
safe_write (int fd, const void *buf, size_t count) noexcept
{
  ssize_t result;
  do
    {
#ifdef _WIN32
      // Windows write can only handle int-sized counts
      unsigned int to_write = count > INT_MAX
				? static_cast<unsigned int> (INT_MAX)
				: static_cast<unsigned int> (count);
      result = _write (fd, buf, to_write);
#else
      result = ::write (fd, buf, count);
#endif
    }
  while (result < 0 && errno == EINTR);
  return result;
}

//============================================================================
// Full Read/Write - read/write entire buffer
//============================================================================

/// Read exactly count bytes (or until EOF/error).
/// Returns total bytes read, may be less than count on EOF.
/// Errno is set on error; check if return value < count && errno !=
/// 0.
[[nodiscard]] inline size_t
full_read (int fd, void *buf, size_t count) noexcept
{
  size_t total = 0;
  char *ptr = static_cast<char *> (buf);

  while (total < count)
    {
      ssize_t n = safe_read (fd, ptr + total, count - total);
      if (n < 0)
	return total;
      if (n == 0)
	break;
      total += static_cast<size_t> (n);
    }
  return total;
}

/// Write exactly count bytes (or until error).
/// Returns total bytes written, may be less than count on error.
/// Errno is set on error; check if return value < count.
[[nodiscard]] inline size_t
full_write (int fd, const void *buf, size_t count) noexcept
{
  size_t total = 0;
  const char *ptr = static_cast<const char *> (buf);

  while (total < count)
    {
      ssize_t n = safe_write (fd, ptr + total, count - total);
      if (n <= 0)
	return total;
      total += static_cast<size_t> (n);
    }
  return total;
}

//============================================================================
// C++ Stream Wrappers
//============================================================================

/// Read up to max_size bytes into a string.
/// Returns std::nullopt on error.
[[nodiscard]] inline std::optional<std::string>
safe_read_string (int fd, size_t max_size)
{
  std::string result;
  result.resize (max_size);

  size_t bytes_read = full_read (fd, result.data (), max_size);
  if (bytes_read == 0 && errno != 0)
    return std::nullopt;

  result.resize (bytes_read);
  return result;
}

/// Write string to file descriptor.
/// Returns bytes written or -1 on error.
[[nodiscard]] inline ssize_t
safe_write_string (int fd, std::string_view str) noexcept
{
  size_t written = full_write (fd, str.data (), str.size ());
  if (written < str.size ())
    return -1;
  return static_cast<ssize_t> (written);
}

//============================================================================
// File Operations - helper functions for opening files
//============================================================================

namespace detail
{

/// Open file for reading (binary mode on Windows)
[[nodiscard]] inline int
open_for_read (const char *path) noexcept
{
#ifdef _WIN32
  return _open (path, _O_RDONLY | _O_BINARY);
#else
  return ::open (path, O_RDONLY);
#endif
}

/// Open file for writing (create/truncate, binary mode on Windows)
[[nodiscard]] inline int
open_for_write (const char *path) noexcept
{
#ifdef _WIN32
  return _open (path, _O_WRONLY | _O_CREAT | _O_TRUNC | _O_BINARY,
		_S_IREAD | _S_IWRITE);
#else
  return ::open (path, O_WRONLY | O_CREAT | O_TRUNC,
		 S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
#endif
}

/// Close file descriptor
inline int
close_fd (int fd) noexcept
{
#ifdef _WIN32
  return _close (fd);
#else
  return ::close (fd);
#endif
}

/// Get file size from file descriptor
[[nodiscard]] inline ssize_t
get_file_size (int fd) noexcept
{
#ifdef _WIN32
  __int64 size = _filelengthi64 (fd);
  return size < 0 ? -1 : static_cast<ssize_t> (size);
#else
  struct stat st;
  if (::fstat (fd, &st) < 0)
    return -1;
  return static_cast<ssize_t> (st.st_size);
#endif
}

} // namespace detail

//============================================================================
// File Operations - read entire file
//============================================================================

/// Read entire file into string (from file descriptor).
/// The caller is responsible for closing the file descriptor.
/// Returns std::nullopt on error.
[[nodiscard]] inline std::optional<std::string>
read_file (int fd)
{
  ssize_t size = detail::get_file_size (fd);
  if (size < 0)
    return std::nullopt;

  if (static_cast<size_t> (size) > MAX_FILE_SIZE)
    {
      errno = EFBIG;
      return std::nullopt;
    }

  std::string result;
  result.resize (static_cast<size_t> (size));

  size_t bytes_read
    = full_read (fd, result.data (), static_cast<size_t> (size));
  if (bytes_read < static_cast<size_t> (size) && errno != 0)
    return std::nullopt;

  result.resize (bytes_read);
  return result;
}

/// Read entire file into string (from path).
/// Returns std::nullopt on error.
[[nodiscard]] inline std::optional<std::string>
read_file (const char *path)
{
  int fd = detail::open_for_read (path);
  if (fd < 0)
    return std::nullopt;

  auto result = read_file (fd);
  detail::close_fd (fd);
  return result;
}

/// Read entire file into string (from std::string path).
[[nodiscard]] inline std::optional<std::string>
read_file (const std::string &path)
{
  return read_file (path.c_str ());
}

/// Read entire file into string (from std::string_view path).
[[nodiscard]] inline std::optional<std::string>
read_file (std::string_view path)
{
  return read_file (std::string (path));
}

//============================================================================
// File Operations - write string to file
//============================================================================

/// Write string to file (from file descriptor).
/// The caller is responsible for closing the file descriptor.
/// Returns true on success, false on error.
[[nodiscard]] inline bool
write_file (int fd, std::string_view content)
{
  size_t written = full_write (fd, content.data (), content.size ());
  return written == content.size ();
}

/// Write string to file (from path).
/// Creates the file if it doesn't exist, truncates if it does.
/// Returns true on success, false on error.
[[nodiscard]] inline bool
write_file (const char *path, std::string_view content)
{
  int fd = detail::open_for_write (path);
  if (fd < 0)
    return false;

  bool success = write_file (fd, content);
  int saved_errno = errno;

#ifdef _WIN32
  _commit (fd);
#else
  ::fsync (fd);
#endif

  detail::close_fd (fd);
  errno = saved_errno;
  return success;
}

/// Write string to file (from std::string path).
[[nodiscard]] inline bool
write_file (const std::string &path, std::string_view content)
{
  return write_file (path.c_str (), content);
}

//============================================================================
// Convenience functions for reading with limited size
//============================================================================

/// Read up to max_bytes from file descriptor into string.
/// Unlike read_file(fd), this doesn't check file size first.
/// Useful for reading from pipes, sockets, or special files.
[[nodiscard]] inline std::optional<std::string>
read_up_to (int fd, size_t max_bytes)
{
  std::string result;
  result.reserve (std::min (max_bytes, SAFE_IO_BUFFER_SIZE));

  char buffer[SAFE_IO_BUFFER_SIZE];
  size_t total_read = 0;

  while (total_read < max_bytes)
    {
      size_t to_read
	= std::min (sizeof (buffer), max_bytes - total_read);
      ssize_t n = safe_read (fd, buffer, to_read);

      if (n < 0)
	{
	  if (total_read == 0)
	    return std::nullopt;
	  break;
	}
      if (n == 0)
	break;

      result.append (buffer, static_cast<size_t> (n));
      total_read += static_cast<size_t> (n);
    }

  return result;
}

/// Read all available data from file descriptor (up to
/// MAX_FILE_SIZE). Useful for reading from pipes, sockets, or special
/// files.
[[nodiscard]] inline std::optional<std::string>
read_all (int fd)
{
  return read_up_to (fd, MAX_FILE_SIZE);
}

//============================================================================
// Atomic file write (write to temp, then rename)
//============================================================================

/// Write string to file atomically using rename.
/// Creates a temporary file, writes content, then renames to target.
/// Returns true on success, false on error.
[[nodiscard]] inline bool
write_file_atomic (const char *path, std::string_view content)
{
  std::string temp_path = std::string (path) + ".tmp.XXXXXX";

#ifdef _WIN32
  if (_mktemp_s (temp_path.data (), temp_path.size () + 1) != 0)
    return false;
  int fd = _open (temp_path.c_str (),
		  _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
		  _S_IREAD | _S_IWRITE);
#else
  int fd = ::mkstemp (temp_path.data ());
#endif

  if (fd < 0)
    return false;

  bool write_success = write_file (fd, content);

#ifdef _WIN32
  _commit (fd);
#else
  ::fsync (fd);
#endif

  detail::close_fd (fd);

  if (!write_success)
    {
#ifdef _WIN32
      _unlink (temp_path.c_str ());
#else
      ::unlink (temp_path.c_str ());
#endif
      return false;
    }

#ifdef _WIN32
  _unlink (path);
  if (::rename (temp_path.c_str (), path) != 0)
    {
      _unlink (temp_path.c_str ());
      return false;
    }
#else
  if (::rename (temp_path.c_str (), path) != 0)
    {
      ::unlink (temp_path.c_str ());
      return false;
    }
#endif

  return true;
}

/// Write string to file atomically (std::string path version).
[[nodiscard]] inline bool
write_file_atomic (const std::string &path, std::string_view content)
{
  return write_file_atomic (path.c_str (), content);
}

} // namespace emacs::gnulib
