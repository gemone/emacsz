// src/filesystem.cpp
#include "filesystem.hpp"
#include <unistd.h>

namespace emacs
{

// Convert std::filesystem::perms to POSIX mode_t
mode_t
FilesystemUtils::perms_to_posix (std::filesystem::perms p) noexcept
{
  mode_t mode = 0;

  if ((p & std::filesystem::perms::owner_read)
      != std::filesystem::perms::none)
    mode |= S_IRUSR;
  if ((p & std::filesystem::perms::owner_write)
      != std::filesystem::perms::none)
    mode |= S_IWUSR;
  if ((p & std::filesystem::perms::owner_exec)
      != std::filesystem::perms::none)
    mode |= S_IXUSR;

  if ((p & std::filesystem::perms::group_read)
      != std::filesystem::perms::none)
    mode |= S_IRGRP;
  if ((p & std::filesystem::perms::group_write)
      != std::filesystem::perms::none)
    mode |= S_IWGRP;
  if ((p & std::filesystem::perms::group_exec)
      != std::filesystem::perms::none)
    mode |= S_IXGRP;

  if ((p & std::filesystem::perms::others_read)
      != std::filesystem::perms::none)
    mode |= S_IROTH;
  if ((p & std::filesystem::perms::others_write)
      != std::filesystem::perms::none)
    mode |= S_IWOTH;
  if ((p & std::filesystem::perms::others_exec)
      != std::filesystem::perms::none)
    mode |= S_IXOTH;

  return mode;
}

int
FilesystemUtils::faccessat (const char *path, int mode) noexcept
{
  std::error_code ec;
  auto status = std::filesystem::status (path, ec);

  if (ec)
    return -1;

  auto perms = status.permissions ();

  if ((mode & R_OK)
      && (perms & std::filesystem::perms::owner_read)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::group_read)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::others_read)
	   == std::filesystem::perms::none)
    return -1;

  if ((mode & W_OK)
      && (perms & std::filesystem::perms::owner_write)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::group_write)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::others_write)
	   == std::filesystem::perms::none)
    return -1;

  if ((mode & X_OK)
      && (perms & std::filesystem::perms::owner_exec)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::group_exec)
	   == std::filesystem::perms::none
      && (perms & std::filesystem::perms::others_exec)
	   == std::filesystem::perms::none)
    return -1;

  return 0;
}

bool
FilesystemUtils::lstat (const char *path, struct stat *buf) noexcept
{
  std::error_code ec;
  auto status = std::filesystem::symlink_status (path, ec);

  if (ec || !buf)
    {
      if (buf)
	{
	  std::memset (buf, 0, sizeof (*buf));
	}
      return false;
    }

  auto type = status.type ();
  auto perms = status.permissions ();

  mode_t mode = 0;

  if (type == std::filesystem::file_type::regular)
    mode |= S_IFREG;
  else if (type == std::filesystem::file_type::directory)
    mode |= S_IFDIR;
  else if (type == std::filesystem::file_type::symlink)
    mode |= S_IFLNK;
  else if (type == std::filesystem::file_type::block)
    mode |= S_IFBLK;
  else if (type == std::filesystem::file_type::character)
    mode |= S_IFCHR;
  else if (type == std::filesystem::file_type::fifo)
    mode |= S_IFIFO;
  else if (type == std::filesystem::file_type::socket)
    mode |= S_IFSOCK;

  mode |= perms_to_posix (perms);

  buf->st_mode = mode;
  buf->st_nlink = static_cast<nlink_t> (
    std::filesystem::hard_link_count (path, ec));
  buf->st_uid = 0;
  buf->st_gid = 0;
  buf->st_size
    = static_cast<off_t> (std::filesystem::file_size (path, ec));

  return true;
}

char *
FilesystemUtils::tempfile (const char *prefix) noexcept
{
  std::error_code ec;
  auto temp_dir = std::filesystem::temp_directory_path (ec);

  if (ec)
    return nullptr;

  static unsigned long counter = 0;
  counter++;

  std::string filename
    = (prefix ? std::string (prefix) : std::string ("emacs_"))
      + std::to_string (counter) + "XXXXXX";

  auto temp_path = temp_dir / filename;

  char *c_str = new char[temp_path.string ().size () + 1];
  std::strcpy (c_str, temp_path.c_str ());

  return c_str;
}

void
FilesystemUtils::tempfile_cleanup (char *temp_filename) noexcept
{
  if (temp_filename)
    {
      delete[] temp_filename;
    }
}

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  int emacs_faccessat (const char *path, int mode)
  {
    return emacs::FilesystemUtils::faccessat (path, mode);
  }

  int emacs_lstat (const char *path, struct stat *buf)
  {
    return emacs::FilesystemUtils::lstat (path, buf) ? 1 : 0;
  }

  char *emacs_tempfile (const char *prefix)
  {
    return emacs::FilesystemUtils::tempfile (prefix);
  }

  void emacs_tempfile_cleanup (char *temp_filename)
  {
    emacs::FilesystemUtils::tempfile_cleanup (temp_filename);
  }
}
