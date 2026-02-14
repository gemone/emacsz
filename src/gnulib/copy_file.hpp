// src/gnulib/copy_file.hpp - C++20 replacements for gnulib file
// copying Replaces: copy-file, copy-acl

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

#if __cpp_lib_filesystem >= 201703L
# include <filesystem>
namespace fs = std::filesystem;
#endif

#ifdef _WIN32
# include <aclapi.h>
# include <direct.h>
# include <io.h>
# include <windows.h>
#else
# include <fcntl.h>
# include <sys/stat.h>
# include <sys/types.h>
# include <unistd.h>
# if __has_include(<sys/acl.h>)
#  include <sys/acl.h>
#  define HAVE_POSIX_ACL 1
# endif
# if __has_include(<sys/xattr.h>)
#  include <sys/xattr.h>
#  define HAVE_XATTR 1
# elif __has_include(<attr/xattr.h>)
#  include <attr/xattr.h>
#  define HAVE_XATTR 1
# endif
#endif

namespace emacs::gnulib
{

enum class copy_options : uint16_t
{
  none = 0,
  preserve_permissions = 1 << 0,
  preserve_timestamps = 1 << 1,
  preserve_ownership = 1 << 2,
  preserve_acl = 1 << 3,
  preserve_xattr = 1 << 4,
  preserve_all
  = (preserve_permissions | preserve_timestamps | preserve_ownership
     | preserve_acl | preserve_xattr),
  follow_symlinks = 1 << 5,
  overwrite_existing = 1 << 6,
};

[[nodiscard]] constexpr inline copy_options
operator| (copy_options lhs, copy_options rhs) noexcept
{
  return static_cast<copy_options> (static_cast<uint16_t> (lhs)
				    | static_cast<uint16_t> (rhs));
}

[[nodiscard]] constexpr inline copy_options
operator& (copy_options lhs, copy_options rhs) noexcept
{
  return static_cast<copy_options> (static_cast<uint16_t> (lhs)
				    & static_cast<uint16_t> (rhs));
}

[[nodiscard]] constexpr inline bool
has_option (copy_options opts, copy_options flag) noexcept
{
  return (opts & flag) == flag;
}

struct CopyError
{
  enum class ErrorCode
  {
    success = 0,
    source_not_found = 1,
    destination_exists = 2,
    permission_denied = 3,
    io_error = 4,
    acl_copy_failed = 5,
    xattr_copy_failed = 6,
    symlink_target_not_found = 7,
    invalid_path = 8,
    unknown = 9,
  };

  ErrorCode code = ErrorCode::success;
  std::string message;
  bool is_fatal = false;

  [[nodiscard]] bool is_success () const noexcept
  {
    return code == ErrorCode::success;
  }

  [[nodiscard]] bool has_partial_failure () const noexcept
  {
    return !is_success () && !is_fatal;
  }
};

[[nodiscard]] inline CopyError
copy_acl_with_error (const std::string &src_path,
		     const std::string &dst_path) noexcept
{
  CopyError err;

#ifdef _WIN32
  PACL dacl = nullptr;
  PACL sacl = nullptr;
  PSID owner = nullptr;
  PSID group = nullptr;
  PSECURITY_DESCRIPTOR sd = nullptr;

  DWORD result
    = GetNamedSecurityInfoA (src_path.c_str (), SE_FILE_OBJECT,
			     DACL_SECURITY_INFORMATION
			       | SACL_SECURITY_INFORMATION
			       | OWNER_SECURITY_INFORMATION
			       | GROUP_SECURITY_INFORMATION,
			     &owner, &group, &dacl, &sacl, &sd);

  if (result != ERROR_SUCCESS)
    {
      err.code = CopyError::ErrorCode::acl_copy_failed;
      err.message = "Failed to read source ACL";
      err.is_fatal = false;
      LocalFree (sd);
      return err;
    }

  result
    = SetNamedSecurityInfoA (const_cast<char *> (dst_path.c_str ()),
			     SE_FILE_OBJECT,
			     DACL_SECURITY_INFORMATION
			       | OWNER_SECURITY_INFORMATION
			       | GROUP_SECURITY_INFORMATION,
			     owner, group, dacl, nullptr);

  LocalFree (sd);

  if (result != ERROR_SUCCESS)
    {
      err.code = CopyError::ErrorCode::acl_copy_failed;
      err.message = "Failed to write destination ACL";
      err.is_fatal = false;
      return err;
    }

#elif defined(HAVE_POSIX_ACL)
  acl_t acl = acl_get_file (src_path.c_str (), ACL_TYPE_ACCESS);
  if (acl == nullptr)
    {
      if (errno == ENOTSUP || errno == ENOSYS)
	{
	  err.code = CopyError::ErrorCode::success;
	  return err;
	}
      err.code = CopyError::ErrorCode::acl_copy_failed;
      err.message = "Failed to read source ACL";
      err.is_fatal = false;
      return err;
    }

  int result = acl_set_file (dst_path.c_str (), ACL_TYPE_ACCESS, acl);
  acl_free (acl);

  if (result < 0)
    {
      if (errno != ENOTSUP && errno != ENOSYS)
	{
	  err.code = CopyError::ErrorCode::acl_copy_failed;
	  err.message = "Failed to write destination ACL";
	  err.is_fatal = false;
	  return err;
	}
    }

  acl = acl_get_file (src_path.c_str (), ACL_TYPE_DEFAULT);
  if (acl != nullptr)
    {
      result
	= acl_set_file (dst_path.c_str (), ACL_TYPE_DEFAULT, acl);
      acl_free (acl);
      if (result < 0 && errno != ENOTSUP && errno != ENOSYS
	  && errno != ENOTDIR)
	{
	  err.code = CopyError::ErrorCode::acl_copy_failed;
	  err.message = "Failed to write destination DEFAULT ACL";
	  err.is_fatal = false;
	  return err;
	}
    }

#else
  (void) src_path;
  (void) dst_path;
#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline CopyError
copy_xattr (const std::string &src_path,
	    const std::string &dst_path) noexcept
{
  CopyError err;

#ifdef HAVE_XATTR

# ifdef __APPLE__
  constexpr int XATTR_FOLLOW = 0;
# else
  constexpr int XATTR_FOLLOW = 0;
# endif

  ssize_t attrs_size
    = listxattr (src_path.c_str (), nullptr, 0, XATTR_FOLLOW);
  if (attrs_size == -1)
    {
      if (errno == ENOTSUP || errno == ENOSYS || errno == ENODATA)
	{
	  err.code = CopyError::ErrorCode::success;
	  return err;
	}
      err.code = CopyError::ErrorCode::xattr_copy_failed;
      err.message = "Failed to list source extended attributes";
      err.is_fatal = false;
      return err;
    }

  if (attrs_size == 0)
    {
      err.code = CopyError::ErrorCode::success;
      return err;
    }

  std::string attrs_buffer (attrs_size, '\0');
  ssize_t result = listxattr (src_path.c_str (), &attrs_buffer[0],
			      attrs_size, XATTR_FOLLOW);
  if (result == -1)
    {
      err.code = CopyError::ErrorCode::xattr_copy_failed;
      err.message = "Failed to read extended attribute names";
      err.is_fatal = false;
      return err;
    }

  for (size_t i = 0; i < static_cast<size_t> (result);)
    {
      const char *attr_name = &attrs_buffer[i];
      size_t attr_name_len = std::strlen (attr_name);

      ssize_t attr_size = getxattr (src_path.c_str (), attr_name,
				    nullptr, 0, 0, XATTR_FOLLOW);
      if (attr_size == -1)
	{
	  i += attr_name_len + 1;
	  continue;
	}

      std::string attr_value (attr_size, '\0');
      ssize_t read_size
	= getxattr (src_path.c_str (), attr_name, &attr_value[0],
		    attr_size, 0, XATTR_FOLLOW);
      if (read_size == -1)
	{
	  i += attr_name_len + 1;
	  continue;
	}

      ssize_t write_result
	= setxattr (dst_path.c_str (), attr_name, &attr_value[0],
		    read_size, 0, XATTR_FOLLOW);
      if (write_result == -1 && errno != ENOTSUP && errno != ENOSYS)
	{
	  err.code = CopyError::ErrorCode::xattr_copy_failed;
	  err.message
	    = std::string ("Failed to write extended attribute: ")
	      + attr_name;
	  err.is_fatal = false;
	}

      i += attr_name_len + 1;
    }

#else
  (void) src_path;
  (void) dst_path;
#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline CopyError
copy_file_content (const std::string &src_path,
		   const std::string &dst_path,
		   copy_options opts) noexcept
{
  CopyError err;

#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;

  fs::copy_options fs_opts = fs::copy_options::skip_existing;

  if (has_option (opts, copy_options::overwrite_existing))
    {
      fs_opts = fs::copy_options::overwrite_existing;
    }

  if (has_option (opts, copy_options::follow_symlinks))
    {
      fs_opts |= fs::copy_options::copy_symlinks;
    }

  bool success = fs::copy_file (src_path, dst_path, fs_opts, ec);

  if (ec)
    {
      if (ec.value () == EEXIST)
	{
	  err.code = CopyError::ErrorCode::destination_exists;
	  err.message = "Destination file already exists";
	  err.is_fatal = true;
	}
      else if (ec.value () == ENOENT)
	{
	  err.code = CopyError::ErrorCode::source_not_found;
	  err.message = "Source file not found";
	  err.is_fatal = true;
	}
      else if (ec.value () == EACCES)
	{
	  err.code = CopyError::ErrorCode::permission_denied;
	  err.message = "Permission denied";
	  err.is_fatal = true;
	}
      else
	{
	  err.code = CopyError::ErrorCode::io_error;
	  err.message = ec.message ();
	  err.is_fatal = true;
	}
      return err;
    }

#else
  (void) opts;

  std::FILE *src = std::fopen (src_path.c_str (), "rb");
  if (!src)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = std::strerror (errno);
      err.is_fatal = true;
      return err;
    }

  std::FILE *dst = std::fopen (dst_path.c_str (), "wb");
  if (!dst)
    {
      err.code = CopyError::ErrorCode::io_error;
      err.message = std::strerror (errno);
      err.is_fatal = true;
      std::fclose (src);
      return err;
    }

  constexpr size_t BUFFER_SIZE = 65536;
  char buffer[BUFFER_SIZE];
  size_t bytes_read;

  while ((bytes_read = std::fread (buffer, 1, BUFFER_SIZE, src)) > 0)
    {
      if (std::fwrite (buffer, 1, bytes_read, dst) != bytes_read)
	{
	  err.code = CopyError::ErrorCode::io_error;
	  err.message = "Write error during file copy";
	  err.is_fatal = true;
	  std::fclose (src);
	  std::fclose (dst);
	  return err;
	}
    }

  if (std::ferror (src))
    {
      err.code = CopyError::ErrorCode::io_error;
      err.message = "Read error during file copy";
      err.is_fatal = true;
      std::fclose (src);
      std::fclose (dst);
      return err;
    }

  std::fclose (src);
  std::fclose (dst);

#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline CopyError
copy_file_permissions (const std::string &src_path,
		       const std::string &dst_path) noexcept
{
  CopyError err;

#ifndef _WIN32
  struct stat st;
  if (stat (src_path.c_str (), &st) != 0)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = std::strerror (errno);
      err.is_fatal = false;
      return err;
    }

  if (chmod (dst_path.c_str (), st.st_mode & 07777) != 0)
    {
      err.code = CopyError::ErrorCode::permission_denied;
      err.message = std::strerror (errno);
      err.is_fatal = false;
      return err;
    }

#else
  (void) src_path;
  (void) dst_path;
#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline CopyError
copy_file_timestamps (const std::string &src_path,
		      const std::string &dst_path) noexcept
{
  CopyError err;

#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  auto src_time = fs::last_write_time (src_path, ec);
  if (ec)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = "Failed to read source timestamps";
      err.is_fatal = false;
      return err;
    }

  fs::last_write_time (dst_path, src_time, ec);
  if (ec)
    {
      err.code = CopyError::ErrorCode::io_error;
      err.message = "Failed to write destination timestamps";
      err.is_fatal = false;
      return err;
    }

#else
# ifndef _WIN32
  struct stat st;
  if (stat (src_path.c_str (), &st) != 0)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = std::strerror (errno);
      err.is_fatal = false;
      return err;
    }

  struct timespec times[2];
  times[0].tv_sec = st.st_atime;
  times[0].tv_nsec = 0;
  times[1].tv_sec = st.st_mtime;
  times[1].tv_nsec = 0;

  if (utimensat (AT_FDCWD, dst_path.c_str (), times, 0) != 0)
    {
      err.code = CopyError::ErrorCode::io_error;
      err.message = std::strerror (errno);
      err.is_fatal = false;
      return err;
    }
# else
  (void) src_path;
  (void) dst_path;
# endif
#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline CopyError
copy_file_ownership (const std::string &src_path,
		     const std::string &dst_path) noexcept
{
  CopyError err;

#ifndef _WIN32
  struct stat st;
  if (stat (src_path.c_str (), &st) != 0)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = std::strerror (errno);
      err.is_fatal = false;
      return err;
    }

  if (chown (dst_path.c_str (), st.st_uid, st.st_gid) != 0)
    {
      if (errno != EPERM && errno != EACCES)
	{
	  err.code = CopyError::ErrorCode::io_error;
	  err.message = std::strerror (errno);
	  err.is_fatal = false;
	}
      err.code = CopyError::ErrorCode::success;
      return err;
    }

#else
  (void) src_path;
  (void) dst_path;
#endif

  err.code = CopyError::ErrorCode::success;
  return err;
}

[[nodiscard]] inline std::pair<bool, CopyError>
copy_file_preserving (const std::string &src_path,
		      const std::string &dst_path,
		      copy_options opts
		      = copy_options::preserve_all) noexcept
{
  CopyError err;

#if __cpp_lib_filesystem >= 201703L
  std::error_code ec;
  if (!fs::exists (src_path, ec))
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = "Source file does not exist";
      err.is_fatal = true;
      return { false, err };
    }
#else
# ifndef _WIN32
  struct stat st;
  if (stat (src_path.c_str (), &st) != 0)
    {
      err.code = CopyError::ErrorCode::source_not_found;
      err.message = std::strerror (errno);
      err.is_fatal = true;
      return { false, err };
    }
# endif
#endif

  auto copy_result = copy_file_content (src_path, dst_path, opts);
  if (copy_result.is_fatal)
    {
      return { false, copy_result };
    }

  bool has_partial_failures = false;

  if (has_option (opts, copy_options::preserve_permissions))
    {
      auto perm_err = copy_file_permissions (src_path, dst_path);
      if (!perm_err.is_success ())
	{
	  has_partial_failures = true;
	}
    }

  if (has_option (opts, copy_options::preserve_timestamps))
    {
      auto time_err = copy_file_timestamps (src_path, dst_path);
      if (!time_err.is_success ())
	{
	  has_partial_failures = true;
	}
    }

  if (has_option (opts, copy_options::preserve_ownership))
    {
      auto own_err = copy_file_ownership (src_path, dst_path);
      if (!own_err.is_success ())
	{
	  has_partial_failures = true;
	}
    }

  if (has_option (opts, copy_options::preserve_acl))
    {
      auto acl_err = copy_acl_with_error (src_path, dst_path);
      if (!acl_err.is_success ())
	{
	  has_partial_failures = true;
	}
    }

  if (has_option (opts, copy_options::preserve_xattr))
    {
      auto xattr_err = copy_xattr (src_path, dst_path);
      if (!xattr_err.is_success ())
	{
	  has_partial_failures = true;
	}
    }

  err.code = CopyError::ErrorCode::success;
  err.message = has_partial_failures
		  ? "File copied with some metadata errors"
		  : "File copied successfully";
  return { true, err };
}

[[nodiscard]] inline std::pair<bool, CopyError>
copy_file_preserving (const char *src_path, const char *dst_path,
		      copy_options opts
		      = copy_options::preserve_all) noexcept
{
  return copy_file_preserving (std::string (src_path),
			       std::string (dst_path), opts);
}

[[nodiscard]] inline bool
copy_acl_simple (const char *src_path, const char *dst_path) noexcept
{
  auto err = copy_acl_with_error (std::string (src_path),
				  std::string (dst_path));
  return err.is_success ();
}

[[nodiscard]] inline bool
copy_xattr (const char *src_path, const char *dst_path) noexcept
{
  auto err
    = copy_xattr (std::string (src_path), std::string (dst_path));
  return err.is_success ();
}

}
