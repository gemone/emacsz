// src/gnulib/acl_utils.hpp - C++20 replacement for ACL utilities
// Replaces: file-has-acl, qcopy-acl, fchmodat

#pragma once

#include <cerrno>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#ifdef _WIN32
# include <aclapi.h>
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
# if __has_include(<acl/libacl.h>)
#  include <acl/libacl.h>
#  define HAVE_LIBACL 1
# endif
#endif

namespace emacs::gnulib
{

enum class AclSupport
{
  none,
  posix,
  windows,
  nfs4
};

[[nodiscard]] inline AclSupport
get_acl_support () noexcept
{
#ifdef _WIN32
  return AclSupport::windows;
#elif defined(HAVE_POSIX_ACL)
  return AclSupport::posix;
#else
  return AclSupport::none;
#endif
}

[[nodiscard]] inline int
file_has_acl (const char *path) noexcept
{
#ifdef _WIN32
  PACL dacl = nullptr;
  PSECURITY_DESCRIPTOR sd = nullptr;

  DWORD result
    = GetNamedSecurityInfoA (path, SE_FILE_OBJECT,
			     DACL_SECURITY_INFORMATION, nullptr,
			     nullptr, &dacl, nullptr, &sd);

  if (result != ERROR_SUCCESS)
    {
      errno = ENOENT;
      return -1;
    }

  int has_acl = 0;
  if (dacl != nullptr)
    {
      ACL_SIZE_INFORMATION acl_info;
      if (GetAclInformation (dacl, &acl_info, sizeof (acl_info),
			     AclSizeInformation))
	{
	  has_acl = (acl_info.AceCount > 0) ? 1 : 0;
	}
    }

  LocalFree (sd);
  return has_acl;

#elif defined(HAVE_POSIX_ACL)
  acl_t acl = acl_get_file (path, ACL_TYPE_ACCESS);
  if (acl == nullptr)
    {
      if (errno == ENOTSUP || errno == ENOSYS)
	return 0;
      return -1;
    }

  int has_acl = 0;

# ifdef HAVE_LIBACL
  has_acl = acl_extended_file (path);
  if (has_acl < 0)
    has_acl = 0;
# else
  acl_entry_t entry;
  int entry_id = ACL_FIRST_ENTRY;
  int count = 0;

  while (acl_get_entry (acl, entry_id, &entry) == 1)
    {
      entry_id = ACL_NEXT_ENTRY;
      ++count;
    }

  has_acl = (count > 3) ? 1 : 0;
# endif

  acl_free (acl);
  return has_acl;

#else
  (void) path;
  return 0;
#endif
}

[[nodiscard]] inline int
file_has_acl (const std::string &path) noexcept
{
  return file_has_acl (path.c_str ());
}

inline int
copy_acl (const char *src_path, const char *dst_path) noexcept
{
#ifdef _WIN32
  PACL dacl = nullptr;
  PACL sacl = nullptr;
  PSID owner = nullptr;
  PSID group = nullptr;
  PSECURITY_DESCRIPTOR sd = nullptr;

  DWORD result
    = GetNamedSecurityInfoA (src_path, SE_FILE_OBJECT,
			     DACL_SECURITY_INFORMATION
			       | SACL_SECURITY_INFORMATION
			       | OWNER_SECURITY_INFORMATION
			       | GROUP_SECURITY_INFORMATION,
			     &owner, &group, &dacl, &sacl, &sd);

  if (result != ERROR_SUCCESS)
    {
      errno = ENOENT;
      return -1;
    }

  result = SetNamedSecurityInfoA (const_cast<char *> (dst_path),
				  SE_FILE_OBJECT,
				  DACL_SECURITY_INFORMATION
				    | OWNER_SECURITY_INFORMATION
				    | GROUP_SECURITY_INFORMATION,
				  owner, group, dacl, nullptr);

  LocalFree (sd);

  if (result != ERROR_SUCCESS)
    {
      errno = EPERM;
      return -1;
    }

  return 0;

#elif defined(HAVE_POSIX_ACL)
  acl_t acl = acl_get_file (src_path, ACL_TYPE_ACCESS);
  if (acl == nullptr)
    {
      if (errno == ENOTSUP || errno == ENOSYS)
	return 0;
      return -1;
    }

  int result = acl_set_file (dst_path, ACL_TYPE_ACCESS, acl);
  acl_free (acl);

  if (result < 0)
    {
      if (errno == ENOTSUP || errno == ENOSYS)
	return 0;
      return -1;
    }

  acl = acl_get_file (src_path, ACL_TYPE_DEFAULT);
  if (acl != nullptr)
    {
      result = acl_set_file (dst_path, ACL_TYPE_DEFAULT, acl);
      acl_free (acl);
      if (result < 0 && errno != ENOTSUP && errno != ENOSYS
	  && errno != ENOTDIR)
	return -1;
    }

  return 0;

#else
  (void) src_path;
  (void) dst_path;
  return 0;
#endif
}

inline int
copy_acl (const std::string &src_path,
	  const std::string &dst_path) noexcept
{
  return copy_acl (src_path.c_str (), dst_path.c_str ());
}

#ifndef _WIN32

inline int
fchmodat_safe (int dirfd, const char *pathname, mode_t mode,
	       int flags) noexcept
{
# if defined(__linux__) || defined(__FreeBSD__) \
   || defined(__OpenBSD__)
  return ::fchmodat (dirfd, pathname, mode, flags);
# elif defined(__APPLE__)
  if (flags & AT_SYMLINK_NOFOLLOW)
    {
      errno = ENOTSUP;
      return -1;
    }
  return ::fchmodat (dirfd, pathname, mode, flags);
# else
  if (dirfd == AT_FDCWD && flags == 0)
    return ::chmod (pathname, mode);

  errno = ENOSYS;
  return -1;
# endif
}

inline int
chmod_safe (const char *path, mode_t mode) noexcept
{
  return ::chmod (path, mode);
}

inline int
fchmod_safe (int fd, mode_t mode) noexcept
{
  return ::fchmod (fd, mode);
}

inline int
lchmod_safe (const char *path, mode_t mode) noexcept
{
# if defined(__APPLE__) || defined(__FreeBSD__)
  return ::lchmod (path, mode);
# else
  struct stat st;
  if (lstat (path, &st) < 0)
    return -1;

  if (S_ISLNK (st.st_mode))
    {
      errno = ENOTSUP;
      return -1;
    }

  return ::chmod (path, mode);
# endif
}

#endif

struct FilePermissions
{
  bool owner_read = false;
  bool owner_write = false;
  bool owner_execute = false;
  bool group_read = false;
  bool group_write = false;
  bool group_execute = false;
  bool others_read = false;
  bool others_write = false;
  bool others_execute = false;
  bool setuid = false;
  bool setgid = false;
  bool sticky = false;

#ifndef _WIN32
  [[nodiscard]] mode_t to_mode () const noexcept
  {
    mode_t m = 0;
    if (owner_read)
      m |= S_IRUSR;
    if (owner_write)
      m |= S_IWUSR;
    if (owner_execute)
      m |= S_IXUSR;
    if (group_read)
      m |= S_IRGRP;
    if (group_write)
      m |= S_IWGRP;
    if (group_execute)
      m |= S_IXGRP;
    if (others_read)
      m |= S_IROTH;
    if (others_write)
      m |= S_IWOTH;
    if (others_execute)
      m |= S_IXOTH;
    if (setuid)
      m |= S_ISUID;
    if (setgid)
      m |= S_ISGID;
    if (sticky)
      m |= S_ISVTX;
    return m;
  }

  static FilePermissions from_mode (mode_t m) noexcept
  {
    FilePermissions p;
    p.owner_read = (m & S_IRUSR) != 0;
    p.owner_write = (m & S_IWUSR) != 0;
    p.owner_execute = (m & S_IXUSR) != 0;
    p.group_read = (m & S_IRGRP) != 0;
    p.group_write = (m & S_IWGRP) != 0;
    p.group_execute = (m & S_IXGRP) != 0;
    p.others_read = (m & S_IROTH) != 0;
    p.others_write = (m & S_IWOTH) != 0;
    p.others_execute = (m & S_IXOTH) != 0;
    p.setuid = (m & S_ISUID) != 0;
    p.setgid = (m & S_ISGID) != 0;
    p.sticky = (m & S_ISVTX) != 0;
    return p;
  }
#endif
};

}
