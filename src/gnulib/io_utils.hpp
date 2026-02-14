// src/gnulib/io_utils.hpp - C++20 replacement for gnulib I/O
// utilities Replaces: dup2, fsync, binary-io, unlocked-io,
// close-stream, fcntl

#pragma once

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <optional>

#ifdef _WIN32
# include <fcntl.h>
# include <io.h>
# include <windows.h>
#else
# include <fcntl.h>
# include <unistd.h>
#endif

namespace emacs::gnulib
{

#ifdef _WIN32
constexpr int O_BINARY_FLAG = _O_BINARY;
constexpr int O_TEXT_FLAG = _O_TEXT;
#else
constexpr int O_BINARY_FLAG = 0;
constexpr int O_TEXT_FLAG = 0;
#endif

inline int
dup2_safe (int oldfd, int newfd) noexcept
{
#ifdef _WIN32
  return _dup2 (oldfd, newfd);
#else
  return ::dup2 (oldfd, newfd);
#endif
}

inline int
dup_safe (int fd) noexcept
{
#ifdef _WIN32
  return _dup (fd);
#else
  return ::dup (fd);
#endif
}

inline int
close_safe (int fd) noexcept
{
#ifdef _WIN32
  return _close (fd);
#else
  return ::close (fd);
#endif
}

inline int
fsync_safe (int fd) noexcept
{
#ifdef _WIN32
  HANDLE h = reinterpret_cast<HANDLE> (_get_osfhandle (fd));
  if (h == INVALID_HANDLE_VALUE)
    {
      errno = EBADF;
      return -1;
    }
  if (!FlushFileBuffers (h))
    {
      errno = EIO;
      return -1;
    }
  return 0;
#else
  return ::fsync (fd);
#endif
}

inline int
fdatasync_safe (int fd) noexcept
{
#ifdef _WIN32
  return fsync_safe (fd);
#elif defined(__APPLE__)
  return ::fcntl (fd, F_FULLFSYNC);
#else
  return ::fdatasync (fd);
#endif
}

inline int
set_binary_mode (int fd) noexcept
{
#ifdef _WIN32
  return _setmode (fd, _O_BINARY);
#else
  (void) fd;
  return 0;
#endif
}

inline int
set_text_mode (int fd) noexcept
{
#ifdef _WIN32
  return _setmode (fd, _O_TEXT);
#else
  (void) fd;
  return 0;
#endif
}

inline bool
set_binary_mode (FILE *fp) noexcept
{
#ifdef _WIN32
  return _setmode (_fileno (fp), _O_BINARY) != -1;
#else
  (void) fp;
  return true;
#endif
}

inline bool
set_cloexec (int fd) noexcept
{
#ifdef _WIN32
  (void) fd;
  return true;
#else
  int flags = ::fcntl (fd, F_GETFD);
  if (flags < 0)
    return false;
  return ::fcntl (fd, F_SETFD, flags | FD_CLOEXEC) >= 0;
#endif
}

inline bool
set_nonblock (int fd) noexcept
{
#ifdef _WIN32
  unsigned long mode = 1;
  HANDLE h = reinterpret_cast<HANDLE> (_get_osfhandle (fd));
  DWORD type = GetFileType (h);
  if (type == FILE_TYPE_PIPE)
    {
      DWORD state;
      if (GetNamedPipeHandleState (h, &state, nullptr, nullptr,
				   nullptr, nullptr, 0))
	{
	  state |= PIPE_NOWAIT;
	  return SetNamedPipeHandleState (h, &state, nullptr, nullptr)
		 != 0;
	}
    }
  return false;
#else
  int flags = ::fcntl (fd, F_GETFL);
  if (flags < 0)
    return false;
  return ::fcntl (fd, F_SETFL, flags | O_NONBLOCK) >= 0;
#endif
}

inline bool
clear_nonblock (int fd) noexcept
{
#ifdef _WIN32
  HANDLE h = reinterpret_cast<HANDLE> (_get_osfhandle (fd));
  DWORD type = GetFileType (h);
  if (type == FILE_TYPE_PIPE)
    {
      DWORD state;
      if (GetNamedPipeHandleState (h, &state, nullptr, nullptr,
				   nullptr, nullptr, 0))
	{
	  state &= ~PIPE_NOWAIT;
	  return SetNamedPipeHandleState (h, &state, nullptr, nullptr)
		 != 0;
	}
    }
  return false;
#else
  int flags = ::fcntl (fd, F_GETFL);
  if (flags < 0)
    return false;
  return ::fcntl (fd, F_SETFL, flags & ~O_NONBLOCK) >= 0;
#endif
}

enum class CloseResult
{
  success,
  write_error,
  close_error
};

inline CloseResult
close_stream (FILE *fp) noexcept
{
  bool prev_fail = std::ferror (fp) != 0;
  bool fclose_fail = std::fclose (fp) != 0;

  if (prev_fail || (fclose_fail && errno != EBADF))
    {
      if (!fclose_fail)
	errno = 0;
      return prev_fail ? CloseResult::write_error
		       : CloseResult::close_error;
    }

  return CloseResult::success;
}

inline bool
close_stdout () noexcept
{
  if (close_stream (stdout) != CloseResult::success)
    return false;
  if (close_stream (stderr) != CloseResult::success)
    return false;
  return true;
}

#ifndef _WIN32

inline int
fcntl_safe (int fd, int cmd) noexcept
{
  return ::fcntl (fd, cmd);
}

inline int
fcntl_safe (int fd, int cmd, int arg) noexcept
{
  return ::fcntl (fd, cmd, arg);
}

inline int
fcntl_safe (int fd, int cmd, void *arg) noexcept
{
  return ::fcntl (fd, cmd, arg);
}

struct FileLock
{
  int fd = -1;
  struct flock lock{};

  FileLock () = default;
  explicit FileLock (int file_fd) : fd (file_fd) {}

  bool lock_exclusive (off_t start = 0, off_t len = 0) noexcept
  {
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = start;
    lock.l_len = len;
    return ::fcntl (fd, F_SETLKW, &lock) == 0;
  }

  bool lock_shared (off_t start = 0, off_t len = 0) noexcept
  {
    lock.l_type = F_RDLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = start;
    lock.l_len = len;
    return ::fcntl (fd, F_SETLKW, &lock) == 0;
  }

  bool try_lock_exclusive (off_t start = 0, off_t len = 0) noexcept
  {
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = start;
    lock.l_len = len;
    return ::fcntl (fd, F_SETLK, &lock) == 0;
  }

  bool try_lock_shared (off_t start = 0, off_t len = 0) noexcept
  {
    lock.l_type = F_RDLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = start;
    lock.l_len = len;
    return ::fcntl (fd, F_SETLK, &lock) == 0;
  }

  bool unlock () noexcept
  {
    lock.l_type = F_UNLCK;
    return ::fcntl (fd, F_SETLK, &lock) == 0;
  }
};

#endif

class UnlockedFile
{
public:
  explicit UnlockedFile (FILE *fp) : fp_ (fp) {}

  int getc () noexcept
  {
#ifdef _WIN32
    return _getc_nolock (fp_);
#elif defined(__GLIBC__)
    return getc_unlocked (fp_);
#else
    return std::getc (fp_);
#endif
  }

  int putc (int c) noexcept
  {
#ifdef _WIN32
    return _putc_nolock (c, fp_);
#elif defined(__GLIBC__)
    return putc_unlocked (c, fp_);
#else
    return std::putc (c, fp_);
#endif
  }

  size_t fread (void *ptr, size_t size, size_t nmemb) noexcept
  {
#ifdef _WIN32
    return _fread_nolock (ptr, size, nmemb, fp_);
#elif defined(__GLIBC__)
    return fread_unlocked (ptr, size, nmemb, fp_);
#else
    return std::fread (ptr, size, nmemb, fp_);
#endif
  }

  size_t fwrite (const void *ptr, size_t size, size_t nmemb) noexcept
  {
#ifdef _WIN32
    return _fwrite_nolock (ptr, size, nmemb, fp_);
#elif defined(__GLIBC__)
    return fwrite_unlocked (ptr, size, nmemb, fp_);
#else
    return std::fwrite (ptr, size, nmemb, fp_);
#endif
  }

  int fflush () noexcept
  {
#ifdef _WIN32
    return _fflush_nolock (fp_);
#elif defined(__GLIBC__)
    return fflush_unlocked (fp_);
#else
    return std::fflush (fp_);
#endif
  }

  int feof () noexcept
  {
#ifdef _WIN32
    return _feof_nolock (fp_);
#elif defined(__GLIBC__)
    return feof_unlocked (fp_);
#else
    return std::feof (fp_);
#endif
  }

  int ferror () noexcept
  {
#ifdef _WIN32
    return _ferror_nolock (fp_);
#elif defined(__GLIBC__)
    return ferror_unlocked (fp_);
#else
    return std::ferror (fp_);
#endif
  }

  void clearerr () noexcept
  {
#ifdef _WIN32
    _clearerr_nolock (fp_);
#elif defined(__GLIBC__)
    clearerr_unlocked (fp_);
#else
    std::clearerr (fp_);
#endif
  }

  FILE *get () const noexcept { return fp_; }

private:
  FILE *fp_;
};

inline int
fast_getc (FILE *fp) noexcept
{
  return UnlockedFile (fp).getc ();
}

inline int
fast_putc (int c, FILE *fp) noexcept
{
  return UnlockedFile (fp).putc (c);
}

inline size_t
fast_fread (void *ptr, size_t size, size_t nmemb, FILE *fp) noexcept
{
  return UnlockedFile (fp).fread (ptr, size, nmemb);
}

inline size_t
fast_fwrite (const void *ptr, size_t size, size_t nmemb,
	     FILE *fp) noexcept
{
  return UnlockedFile (fp).fwrite (ptr, size, nmemb);
}

}
