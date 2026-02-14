// src/gnulib/system_info.hpp - C++20 replacement for system
// information Replaces: boot-time, fsusage, d-type

#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>

#ifdef _WIN32
# include <windows.h>
#else
# include <dirent.h>
# include <sys/stat.h>
# include <sys/types.h>
# if __has_include(<sys/statvfs.h>)
#  include <sys/statvfs.h>
#  define HAVE_STATVFS 1
# endif
# if __has_include(<sys/mount.h>)
#  include <sys/mount.h>
# endif
# if __has_include( \
   <sys/sysctl.h>) && (defined(__APPLE__) || defined(__FreeBSD__))
#  include <sys/sysctl.h>
#  define HAVE_SYSCTL 1
# endif
# if __has_include(<sys/sysinfo.h>)
#  include <sys/sysinfo.h>
#  define HAVE_SYSINFO 1
# endif
#endif

namespace emacs::gnulib
{

struct FsUsage
{
  std::uint64_t total_blocks = 0;
  std::uint64_t free_blocks = 0;
  std::uint64_t available_blocks = 0;
  std::uint64_t total_inodes = 0;
  std::uint64_t free_inodes = 0;
  std::uint64_t block_size = 0;

  [[nodiscard]] std::uint64_t total_bytes () const noexcept
  {
    return total_blocks * block_size;
  }

  [[nodiscard]] std::uint64_t free_bytes () const noexcept
  {
    return free_blocks * block_size;
  }

  [[nodiscard]] std::uint64_t available_bytes () const noexcept
  {
    return available_blocks * block_size;
  }

  [[nodiscard]] double usage_percent () const noexcept
  {
    if (total_blocks == 0)
      return 0.0;
    return 100.0
	   * static_cast<double> (total_blocks - available_blocks)
	   / static_cast<double> (total_blocks);
  }
};

[[nodiscard]] inline std::optional<FsUsage>
get_fs_usage (const char *path)
{
  FsUsage usage;

#ifdef _WIN32
  ULARGE_INTEGER free_bytes_available;
  ULARGE_INTEGER total_bytes;
  ULARGE_INTEGER total_free_bytes;

  if (!GetDiskFreeSpaceExA (path, &free_bytes_available, &total_bytes,
			    &total_free_bytes))
    return std::nullopt;

  usage.block_size = 1;
  usage.total_blocks = total_bytes.QuadPart;
  usage.free_blocks = total_free_bytes.QuadPart;
  usage.available_blocks = free_bytes_available.QuadPart;
  usage.total_inodes = 0;
  usage.free_inodes = 0;

#elif defined(HAVE_STATVFS)
  struct statvfs buf;
  if (statvfs (path, &buf) != 0)
    return std::nullopt;

  usage.block_size = buf.f_frsize ? buf.f_frsize : buf.f_bsize;
  usage.total_blocks = buf.f_blocks;
  usage.free_blocks = buf.f_bfree;
  usage.available_blocks = buf.f_bavail;
  usage.total_inodes = buf.f_files;
  usage.free_inodes = buf.f_ffree;

#else
  (void) path;
  return std::nullopt;
#endif

  return usage;
}

[[nodiscard]] inline std::optional<FsUsage>
get_fs_usage (const std::string &path)
{
  return get_fs_usage (path.c_str ());
}

struct BootTime
{
  std::chrono::system_clock::time_point time;
  bool valid = false;

  [[nodiscard]] std::chrono::seconds uptime () const noexcept
  {
    if (!valid)
      return std::chrono::seconds{ 0 };
    auto now = std::chrono::system_clock::now ();
    return std::chrono::duration_cast<std::chrono::seconds> (now
							     - time);
  }
};

[[nodiscard]] inline BootTime
get_boot_time ()
{
  BootTime result;

#if defined(_WIN32)
  ULONGLONG tick_count = GetTickCount64 ();
  auto now = std::chrono::system_clock::now ();
  result.time = now - std::chrono::milliseconds (tick_count);
  result.valid = true;

#elif defined(HAVE_SYSCTL) \
  && (defined(__APPLE__) || defined(__FreeBSD__))
  struct timeval boottime;
  size_t len = sizeof (boottime);
  int mib[2] = { CTL_KERN, KERN_BOOTTIME };

  if (sysctl (mib, 2, &boottime, &len, nullptr, 0) == 0)
    {
      result.time
	= std::chrono::system_clock::from_time_t (boottime.tv_sec)
	  + std::chrono::microseconds (boottime.tv_usec);
      result.valid = true;
    }

#elif defined(HAVE_SYSINFO)
  struct sysinfo info;
  if (sysinfo (&info) == 0)
    {
      auto now = std::chrono::system_clock::now ();
      result.time = now - std::chrono::seconds (info.uptime);
      result.valid = true;
    }
#endif

  return result;
}

[[nodiscard]] inline std::chrono::seconds
get_uptime ()
{
  return get_boot_time ().uptime ();
}

enum class FileType : unsigned char
{
  unknown = 0,
  fifo = 1,
  character_device = 2,
  directory = 4,
  block_device = 6,
  regular = 8,
  symlink = 10,
  socket = 12,
  whiteout = 14
};

#ifndef _WIN32

[[nodiscard]] inline FileType
dirent_type (const struct dirent *entry) noexcept
{
# ifdef _DIRENT_HAVE_D_TYPE
  switch (entry->d_type)
    {
    case DT_FIFO:
      return FileType::fifo;
    case DT_CHR:
      return FileType::character_device;
    case DT_DIR:
      return FileType::directory;
    case DT_BLK:
      return FileType::block_device;
    case DT_REG:
      return FileType::regular;
    case DT_LNK:
      return FileType::symlink;
    case DT_SOCK:
      return FileType::socket;
#  ifdef DT_WHT
    case DT_WHT:
      return FileType::whiteout;
#  endif
    default:
      return FileType::unknown;
    }
# else
  (void) entry;
  return FileType::unknown;
# endif
}

[[nodiscard]] inline bool
dirent_type_known (const struct dirent *entry) noexcept
{
# ifdef _DIRENT_HAVE_D_TYPE
  return entry->d_type != DT_UNKNOWN;
# else
  (void) entry;
  return false;
# endif
}

#endif

[[nodiscard]] inline FileType
stat_file_type (mode_t mode) noexcept
{
#ifndef _WIN32
  if (S_ISREG (mode))
    return FileType::regular;
  if (S_ISDIR (mode))
    return FileType::directory;
  if (S_ISLNK (mode))
    return FileType::symlink;
  if (S_ISCHR (mode))
    return FileType::character_device;
  if (S_ISBLK (mode))
    return FileType::block_device;
  if (S_ISFIFO (mode))
    return FileType::fifo;
  if (S_ISSOCK (mode))
    return FileType::socket;
#else
  if (mode & _S_IFREG)
    return FileType::regular;
  if (mode & _S_IFDIR)
    return FileType::directory;
  if (mode & _S_IFCHR)
    return FileType::character_device;
#endif
  return FileType::unknown;
}

[[nodiscard]] inline const char *
file_type_name (FileType type) noexcept
{
  switch (type)
    {
    case FileType::fifo:
      return "fifo";
    case FileType::character_device:
      return "character device";
    case FileType::directory:
      return "directory";
    case FileType::block_device:
      return "block device";
    case FileType::regular:
      return "regular file";
    case FileType::symlink:
      return "symbolic link";
    case FileType::socket:
      return "socket";
    case FileType::whiteout:
      return "whiteout";
    default:
      return "unknown";
    }
}

}
