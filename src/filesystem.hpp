// src/filesystem.hpp
#pragma once

#include <config.h>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <sys/types.h>

namespace emacs
{

/**
 * Filesystem utilities - C++20 std::filesystem replacements for
 * gnulib
 *
 * Replaces:
 * - faccessat() → std::filesystem::status() + permissions check
 * - lstat() → std::filesystem::symlink_status()
 * - tempfile() → std::filesystem::temp_directory_path() + random
 * filename
 *
 * Uses:
 * - std::filesystem (C++17)
 * - std::error_code for error handling
 */

class FilesystemUtils
{
public:
  FilesystemUtils () noexcept = default;
  ~FilesystemUtils () noexcept = default;

  // faccessat() - test file accessibility
  [[nodiscard]] static int faccessat (const char *path,
				      int mode) noexcept;

  // lstat() - get file status
  [[nodiscard]] static bool lstat (const char *path,
				   struct stat *buf) noexcept;

  // tempfile() - create unique temporary filename
  [[nodiscard]] static char *tempfile (const char *prefix) noexcept;

  // Clean up temporary filename
  static void tempfile_cleanup (char *temp_filename) noexcept;

private:
  // Convert std::filesystem::perms to POSIX mode_t
  static mode_t perms_to_posix (std::filesystem::perms p) noexcept;
};

} // namespace emacs

// extern "C" bridge functions for C compatibility
extern "C"
{
  // faccessat() - test file accessibility
  int emacs_faccessat (const char *path, int mode);

  // lstat() - get file status
  int emacs_lstat (const char *path, struct stat *buf);

  // tempfile() - create unique temporary filename
  char *emacs_tempfile (const char *prefix);

  // Clean up temporary filename
  void emacs_tempfile_cleanup (char *temp_filename);
}
