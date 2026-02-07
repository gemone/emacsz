// src/filesystem.cpp
#include <cstring>
#include <filesystem>

#include "filesystem.hpp"

namespace emacs
{

FilesystemUtils::FilesystemUtils () {}

FilesystemUtils::~FilesystemUtils () {}

int
FilesystemUtils::faccessat (const char *path, int mode) noexcept
{
  std::error_code ec;
  auto perms = std::filesystem::permissions (path, mode, ec);
  if (ec)
    return -1;
  return perms == std::filesystem::perms::none ? 0 : 1;
}

bool
FilesystemUtils::lstat (const char *path, struct stat *buf) noexcept
{
  std::error_code ec;
  auto status
    = std::filesystem::status (std::filesystem::path (path), ec);
  if (ec)
    {
      buf->st_mode = 0;
      buf->st_nlink = 0;
      buf->st_uid = 0;
      buf->st_gid = 0;
      return false;
    }

  auto s = status.permissions ();
  std::filesystem::perms rwxr (static_cast<int> (s));

  buf->st_mode = static_cast<mode_t> (rwxr_to_posix (rwxr));
  buf->st_nlink
    = static_cast<nlink_t> (s.count (std::filesystem::perms::others));
  buf->st_uid = 0;
  buf->st_gid = 0;

  return true;
}

char *
FilesystemUtils::tempfile (const char *prefix) noexcept
{
  static std::string filename;
  filename.resize (64);

  std::error_code ec;
  auto temp_dir = std::filesystem::temp_directory_path (ec);
  auto temp_path
    = temp_dir
      / (filename.empty () ? "emacs_XXXXXX" : (prefix + filename));

  auto unique_path = std::filesystem::unique_path (temp_path, ec);
  if (ec)
    {
      return nullptr;
    }

  filename = unique_path.filename ().string ();

  static std::vector<char> result (filename.begin (),
				   filename.end () + 1);
  result.push_back ('\0');

  char *c_str = new (char[result.size ()];
  std::copy (result.begin (), result.end (), c_str);
  c_str[result.size () - 1] = '\0';

  return c_str;
}

void
FilesystemUtils::tempfile_cleanup (char *temp_filename) noexcept
{
  delete[] temp_filename;
}

} // namespace emacs

// extern "C" bridge functions already in filesystem.hpp
