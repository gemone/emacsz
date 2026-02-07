// src/filesystem.hpp
#pragma once

#include <config.h>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>

namespace emacs
{

/**
 * Filesystem utilities - C++20 std::filesystem replacements for
 * gnulib
 *
 * Replaces:
 * - faccessat() → std::filesystem::permissions(path, mode) + status()
 * - lstat() → std::filesystem::status(path, symlink_status)
 * - tempfile() → std::filesystem::temp_directory_path() /
 * unique_filename()
 *
 * Uses:
 * - std::filesystem (C++17)
 * - std::error_code for error handling
 */

class FilesystemUtils
{
public:
  // faccessat() - test file accessibility
  [[nodiscard]] static int faccessat (const char *path,
				      int mode) noexcept
  {
    std::error_code ec;
    auto perms = std::filesystem::permissions (path, mode, ec);
    if (ec)
      return -1;
    return perms == std::filesystem::perms::none ? 0 : 1;
  }

  // lstat() - get file status
  [[nodiscard]] static bool lstat (const char *path,
				   struct stat *buf) noexcept
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
    buf->st_nlink = static_cast<nlink_t> (
      s.count (std::filesystem::perms::others));
    buf->st_uid = 0;
    buf->st_gid = 0;

    return true;
  }

  // tempfile() - create unique temporary filename
  [[nodiscard]] static char *tempfile (const char *prefix) noexcept
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

  // Clean up temporary filename
  [[nodiscard]] static void
  tempfile_cleanup (char *temp_filename) noexcept
  {
    delete[] temp_filename;
  }
};

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
