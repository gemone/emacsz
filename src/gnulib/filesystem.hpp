// src/gnulib/filesystem.hpp
// C++20 replacements for gnulib filesystem functions
// Replaces: faccessat, fstatat, readlink, readlinkat, symlink,
// canonicalize-lgpl, fdopendir, utimensat, futimens, copy-file-range,
// tempname, etc.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

#if __cpp_lib_filesystem >= 201703L
# include <filesystem>
namespace fs = std::filesystem;
#endif

#ifdef _WIN32
# include <direct.h>
# include <io.h>
# include <windows.h>
# define F_OK 0
# define R_OK 4
# define W_OK 2
# define X_OK 1
# define AT_FDCWD -100
# define AT_SYMLINK_NOFOLLOW 0x100
# define AT_EACCESS 0x200
#else
# include <dirent.h>
# include <fcntl.h>
# include <sys/stat.h>
# include <sys/syscall.h>
# include <unistd.h>
# ifndef UTIME_OMIT
#  define UTIME_OMIT ((1L << 30) - 2L)
# endif
#endif

namespace emacs::gnulib
{

[[nodiscard]] inline int
faccessat_compat (int dirfd, const char *pathname, int mode,
		  int flags) noexcept
{
#ifdef _WIN32
  (void) dirfd;
  (void) flags;
  return _access (pathname, mode);
#else
  return faccessat (dirfd, pathname, mode, flags);
#endif
}

[[nodiscard]] inline bool
file_exists (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  return fs::exists (path, ec);
#else
  return faccessat_compat (AT_FDCWD, path, F_OK, 0) == 0;
#endif
}

[[nodiscard]] inline bool
file_readable (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto perms = fs::status (path, ec).permissions ();
  return !ec && (perms & fs::perms::owner_read) != fs::perms::none;
#else
  return faccessat_compat (AT_FDCWD, path, R_OK, 0) == 0;
#endif
}

[[nodiscard]] inline bool
file_writable (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto perms = fs::status (path, ec).permissions ();
  return !ec && (perms & fs::perms::owner_write) != fs::perms::none;
#else
  return faccessat_compat (AT_FDCWD, path, W_OK, 0) == 0;
#endif
}

[[nodiscard]] inline bool
file_executable (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto perms = fs::status (path, ec).permissions ();
  return !ec && (perms & fs::perms::owner_exec) != fs::perms::none;
#else
  return faccessat_compat (AT_FDCWD, path, X_OK, 0) == 0;
#endif
}

[[nodiscard]] inline bool
is_directory (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  return fs::is_directory (path, ec);
#else
  struct stat st;
  return stat (path, &st) == 0 && S_ISDIR (st.st_mode);
#endif
}

[[nodiscard]] inline bool
is_regular_file (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  return fs::is_regular_file (path, ec);
#else
  struct stat st;
  return stat (path, &st) == 0 && S_ISREG (st.st_mode);
#endif
}

[[nodiscard]] inline bool
is_symlink (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  return fs::is_symlink (path, ec);
#else
# ifdef _WIN32
  DWORD attrs = GetFileAttributesA (path);
  return attrs != INVALID_FILE_ATTRIBUTES
	 && (attrs & FILE_ATTRIBUTE_REPARSE_POINT);
# else
  struct stat st;
  return lstat (path, &st) == 0 && S_ISLNK (st.st_mode);
# endif
#endif
}

[[nodiscard]] inline std::optional<std::string>
read_symlink (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto result = fs::read_symlink (path, ec);
  if (ec)
    return std::nullopt;
  return result.string ();
#else
# ifdef _WIN32
  return std::nullopt;
# else
  char buf[PATH_MAX];
  ssize_t len = readlink (path, buf, sizeof (buf) - 1);
  if (len == -1)
    return std::nullopt;
  buf[len] = '\0';
  return std::string (buf);
# endif
#endif
}

[[nodiscard]] inline std::optional<std::string>
canonical_path (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto result = fs::canonical (path, ec);
  if (ec)
    return std::nullopt;
  return result.string ();
#else
# ifdef _WIN32
  char buf[MAX_PATH];
  DWORD len = GetFullPathNameA (path, MAX_PATH, buf, nullptr);
  if (len == 0 || len > MAX_PATH)
    return std::nullopt;
  return std::string (buf);
# else
  char *resolved = realpath (path, nullptr);
  if (!resolved)
    return std::nullopt;
  std::string result (resolved);
  free (resolved);
  return result;
# endif
#endif
}

[[nodiscard]] inline std::optional<uintmax_t>
file_size (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto size = fs::file_size (path, ec);
  if (ec)
    return std::nullopt;
  return size;
#else
  struct stat st;
  if (stat (path, &st) != 0)
    return std::nullopt;
  return static_cast<uintmax_t> (st.st_size);
#endif
}

inline int
create_directory (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  fs::create_directory (path, ec);
  return ec ? -1 : 0;
#else
# ifdef _WIN32
  return _mkdir (path);
# else
  return mkdir (path, 0755);
# endif
#endif
}

inline int
create_directories (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  fs::create_directories (path, ec);
  return ec ? -1 : 0;
#else
  std::string p (path);
  size_t pos = 0;
  while ((pos = p.find_first_of ("/\\", pos + 1))
	 != std::string::npos)
    {
      std::string subpath = p.substr (0, pos);
      if (!subpath.empty () && !is_directory (subpath.c_str ()))
	{
	  if (create_directory (subpath.c_str ()) != 0)
	    return -1;
	}
    }
  if (!is_directory (path))
    return create_directory (path);
  return 0;
#endif
}

inline int
remove_file (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  return fs::remove (path, ec) ? 0 : -1;
#else
  return std::remove (path);
#endif
}

inline int
rename_file (const char *oldpath, const char *newpath) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  fs::rename (oldpath, newpath, ec);
  return ec ? -1 : 0;
#else
  return std::rename (oldpath, newpath);
#endif
}

inline int
symlink_file (const char *target, const char *linkpath) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  fs::create_symlink (target, linkpath, ec);
  return ec ? -1 : 0;
#else
# ifdef _WIN32
  return -1;
# else
  return symlink (target, linkpath);
# endif
#endif
}

[[nodiscard]] inline std::optional<std::string>
temp_directory () noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto path = fs::temp_directory_path (ec);
  if (ec)
    return std::nullopt;
  return path.string ();
#else
# ifdef _WIN32
  char buf[MAX_PATH];
  DWORD len = GetTempPathA (MAX_PATH, buf);
  if (len == 0 || len > MAX_PATH)
    return std::nullopt;
  return std::string (buf);
# else
  const char *tmpdir = getenv ("TMPDIR");
  if (tmpdir)
    return std::string (tmpdir);
  return std::string ("/tmp");
# endif
#endif
}

[[nodiscard]] inline std::optional<std::string>
current_directory () noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto path = fs::current_path (ec);
  if (ec)
    return std::nullopt;
  return path.string ();
#else
# ifdef _WIN32
  char buf[MAX_PATH];
  if (!_getcwd (buf, MAX_PATH))
    return std::nullopt;
  return std::string (buf);
# else
  char buf[PATH_MAX];
  if (!getcwd (buf, PATH_MAX))
    return std::nullopt;
  return std::string (buf);
# endif
#endif
}

inline int
change_directory (const char *path) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  fs::current_path (path, ec);
  return ec ? -1 : 0;
#else
# ifdef _WIN32
  return _chdir (path);
# else
  return chdir (path);
# endif
#endif
}

[[nodiscard]] inline std::string
path_join (std::string_view base, std::string_view component)
{
#if __cpp_lib_filesystem >= 201703L
  return (fs::path (base) / fs::path (component)).string ();
#else
  std::string result (base);
  if (!result.empty () && result.back () != '/'
      && result.back () != '\\')
    result += '/';
  result += component;
  return result;
#endif
}

[[nodiscard]] inline std::string_view
path_basename (std::string_view path) noexcept
{
  auto pos = path.find_last_of ("/\\");
  if (pos == std::string_view::npos)
    return path;
  return path.substr (pos + 1);
}

[[nodiscard]] inline std::string_view
path_dirname (std::string_view path) noexcept
{
  auto pos = path.find_last_of ("/\\");
  if (pos == std::string_view::npos)
    return ".";
  if (pos == 0)
    return path.substr (0, 1);
  return path.substr (0, pos);
}

[[nodiscard]] inline std::string_view
path_extension (std::string_view path) noexcept
{
  auto basename = path_basename (path);
  auto pos = basename.rfind ('.');
  if (pos == std::string_view::npos || pos == 0)
    return "";
  return basename.substr (pos);
}

// fdopendir: Open directory stream from file descriptor
#ifndef _WIN32
[[nodiscard]] inline DIR *
fdopendir_compat (int fd) noexcept
{
  return fdopendir (fd);
}
#endif

// utimensat: Change file timestamps with nanosecond precision
#ifndef _WIN32
inline int
utimensat_compat (int dirfd, const char *pathname,
		  const struct timespec times[2], int flags) noexcept
{
  return utimensat (dirfd, pathname, times, flags);
}
#endif

// futimens: Change file timestamps via file descriptor
#ifndef _WIN32
inline int
futimens_compat (int fd, const struct timespec times[2]) noexcept
{
  return futimens (fd, times);
}
#endif

// Set file modification/access time using std::filesystem or POSIX
inline int
set_file_times (const char *path,
		[[maybe_unused]] std::optional<int64_t> atime_ns,
		std::optional<int64_t> mtime_ns) noexcept
{
#if __cpp_lib_filesystem >= 201703L
  if (mtime_ns)
    {
      std::error_code ec;
      auto tp
	= fs::file_time_type::clock::now ()
	  + std::chrono::nanoseconds (
	    *mtime_ns
	    - std::chrono::duration_cast<std::chrono::nanoseconds> (
		fs::file_time_type::clock::now ().time_since_epoch ())
		.count ());
      fs::last_write_time (path, tp, ec);
      if (ec)
	return -1;
    }
  return 0;
#else
# ifdef _WIN32
  (void) path;
  (void) atime_ns;
  (void) mtime_ns;
  return -1;
# else
  struct timespec times[2];
  if (atime_ns)
    {
      times[0].tv_sec = *atime_ns / 1'000'000'000LL;
      times[0].tv_nsec = *atime_ns % 1'000'000'000LL;
    }
  else
    {
      times[0].tv_nsec = UTIME_OMIT;
    }
  if (mtime_ns)
    {
      times[1].tv_sec = *mtime_ns / 1'000'000'000LL;
      times[1].tv_nsec = *mtime_ns % 1'000'000'000LL;
    }
  else
    {
      times[1].tv_nsec = UTIME_OMIT;
    }
  return utimensat_compat (AT_FDCWD, path, times, 0);
# endif
#endif
}

// copy_file_range: Efficiently copy data between files (Linux 4.5+)
#if defined(__linux__)
# ifndef __NR_copy_file_range
#  if defined(__x86_64__)
#   define __NR_copy_file_range 326
#  elif defined(__i386__)
#   define __NR_copy_file_range 377
#  elif defined(__aarch64__)
#   define __NR_copy_file_range 285
#  endif
# endif
#endif

[[nodiscard]] inline ssize_t
copy_file_range_compat (int fd_in, off_t *off_in, int fd_out,
			off_t *off_out, size_t len,
			unsigned int flags) noexcept
{
#if defined(__linux__) && defined(__NR_copy_file_range)
  return syscall (__NR_copy_file_range, fd_in, off_in, fd_out,
		  off_out, len, flags);
#else
  (void) fd_in;
  (void) off_in;
  (void) fd_out;
  (void) off_out;
  (void) len;
  (void) flags;
# ifndef _WIN32
  errno = ENOSYS;
# endif
  return -1;
#endif
}

// Fallback copy using read/write for portability
inline ssize_t
copy_file_data (int fd_in, int fd_out, size_t len) noexcept
{
#ifndef _WIN32
  constexpr size_t BUFSIZE = 65536;
  char buf[BUFSIZE];
  ssize_t total = 0;

  while (len > 0)
    {
      size_t to_read = std::min (len, BUFSIZE);
      ssize_t nread = read (fd_in, buf, to_read);
      if (nread <= 0)
	return nread == 0 ? total : -1;

      ssize_t nwritten
	= write (fd_out, buf, static_cast<size_t> (nread));
      if (nwritten != nread)
	return -1;

      total += nwritten;
      len -= static_cast<size_t> (nread);
    }
  return total;
#else
  (void) fd_in;
  (void) fd_out;
  (void) len;
  return -1;
#endif
}

// Generate unique temporary filename (tempname replacement)
[[nodiscard]] inline std::optional<std::string>
make_temp_name (std::string_view prefix, std::string_view suffix = "")
{
#if __cpp_lib_filesystem >= 201703L
  auto tmpdir = fs::temp_directory_path ();
  std::string base (prefix);

  static std::atomic<uint32_t> counter{ 0 };
  auto now
    = std::chrono::steady_clock::now ().time_since_epoch ().count ();
  uint32_t unique = counter.fetch_add (1, std::memory_order_relaxed);

  char hex[17];
  std::snprintf (hex, sizeof (hex), "%08x%08x",
		 static_cast<uint32_t> (now & 0xFFFFFFFF), unique);

  std::string name = base + hex + std::string (suffix);
  return (tmpdir / name).string ();
#else
  auto tmpdir_opt = temp_directory ();
  if (!tmpdir_opt)
    return std::nullopt;

  static std::atomic<uint32_t> counter{ 0 };
  uint32_t unique = counter.fetch_add (1, std::memory_order_relaxed);

  char hex[9];
  std::snprintf (hex, sizeof (hex), "%08x", unique);

  std::string name
    = std::string (prefix) + hex + std::string (suffix);
  return path_join (*tmpdir_opt, name);
#endif
}

// fstatat wrapper
#ifndef _WIN32
[[nodiscard]] inline int
fstatat_compat (int dirfd, const char *pathname, struct stat *statbuf,
		int flags) noexcept
{
  return fstatat (dirfd, pathname, statbuf, flags);
}
#endif

// Get file status relative to directory fd
[[nodiscard]] inline std::optional<struct stat>
file_stat_at (int dirfd, const char *pathname,
	      bool follow_symlinks = true)
{
#ifndef _WIN32
  struct stat st;
  int flags = follow_symlinks ? 0 : AT_SYMLINK_NOFOLLOW;
  if (fstatat_compat (dirfd, pathname, &st, flags) == 0)
    return st;
#else
  (void) dirfd;
  (void) follow_symlinks;
  struct stat st;
  if (stat (pathname, &st) == 0)
    return st;
#endif
  return std::nullopt;
}

} // namespace emacs::gnulib
