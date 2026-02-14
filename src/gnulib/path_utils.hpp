// src/gnulib/path_utils.hpp
// C++20 replacements for gnulib path utilities
// Replaces: basename, dirname (GNU versions, not POSIX)

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <optional>
#include <string>
#include <string_view>
#include <type_traits>

namespace emacs::gnulib
{

#ifdef _WIN32
inline constexpr char PATH_SEPARATOR = '\\';
inline constexpr char ALT_PATH_SEPARATOR = '/';
inline constexpr char PREFERRED_SEPARATOR = '\\';
#else
inline constexpr char PATH_SEPARATOR = '/';
inline constexpr char ALT_PATH_SEPARATOR = '/';
inline constexpr char PREFERRED_SEPARATOR = '/';
#endif

[[nodiscard]] inline constexpr bool
is_path_separator (char c) noexcept
{
#ifdef _WIN32
  return c == '/' || c == '\\';
#else
  return c == '/';
#endif
}

// GNU basename: Returns pointer to last component of path
// Unlike POSIX basename, this NEVER modifies the input string
// gnu_basename("/usr/lib") -> "lib"
// gnu_basename("/usr/") -> ""
// gnu_basename("usr") -> "usr"
// gnu_basename("/") -> ""
// gnu_basename(".") -> "."
// gnu_basename("..") -> ".."
// gnu_basename("") -> ""
[[nodiscard]] inline std::string_view
gnu_basename (std::string_view path) noexcept
{
  if (path.empty ())
    return "";

  auto pos = path.size ();
  while (pos > 0)
    {
      --pos;
      if (is_path_separator (path[pos]))
	return path.substr (pos + 1);
    }

  return path;
}

[[nodiscard]] inline const char *
gnu_basename (const char *path) noexcept
{
  if (!path || !*path)
    return "";

  const char *last_sep = nullptr;
  for (const char *p = path; *p; ++p)
    {
      if (is_path_separator (*p))
	last_sep = p;
    }

  if (!last_sep)
    return path;
  return last_sep + 1;
}

// GNU dirname: Returns directory component of path
// Unlike POSIX dirname, this returns a new string (never modifies
// input) gnu_dirname("/usr/lib") -> "/usr" gnu_dirname("/usr/") ->
// "/usr" gnu_dirname("usr") -> "." gnu_dirname("/") -> "/"
// gnu_dirname(".") -> "."
// gnu_dirname("..") -> "."
// gnu_dirname("") -> "."
[[nodiscard]] inline std::string
gnu_dirname (std::string_view path)
{
  if (path.empty ())
    return ".";

  size_t end = path.size ();

  if (end == 1)
    {
      if (is_path_separator (path[0]))
	return std::string (1, path[0]);
      return ".";
    }

#ifdef _WIN32
  if (end >= 2 && path[1] == ':')
    {
      if (end == 2)
	return ".";
      if (end == 3 && is_path_separator (path[2]))
	return std::string (path.substr (0, 3));
    }
#endif

  size_t last_sep = end;
  while (last_sep > 0)
    {
      --last_sep;
      if (is_path_separator (path[last_sep]))
	break;
    }

  if (last_sep == 0 && !is_path_separator (path[0]))
    return ".";

  if (last_sep == 0)
    return std::string (1, path[0]);

#ifdef _WIN32
  if (last_sep == 2 && path[1] == ':')
    return std::string (path.substr (0, 3));
#endif

  size_t dir_end = last_sep;
  while (dir_end > 1 && is_path_separator (path[dir_end - 1]))
    --dir_end;

#ifdef _WIN32
  if (dir_end == 2 && path[1] == ':')
    return std::string (path.substr (0, 3));
#endif

  if (dir_end == 0)
    return std::string (1, path[0]);

  return std::string (path.substr (0, dir_end));
}

[[nodiscard]] inline std::string
gnu_dirname (const char *path)
{
  if (!path || !*path)
    return ".";
  return gnu_dirname (std::string_view (path));
}

[[nodiscard]] inline bool
is_absolute_path (std::string_view path) noexcept
{
  if (path.empty ())
    return false;

#ifdef _WIN32
  if (path.size () >= 3 && path[1] == ':'
      && is_path_separator (path[2]))
    return true;
  if (path.size () >= 2 && is_path_separator (path[0])
      && is_path_separator (path[1]))
    return true;
  return false;
#else
  return path[0] == '/';
#endif
}

[[nodiscard]] inline bool
is_absolute_path (const char *path) noexcept
{
  if (!path || !*path)
    return false;

#ifdef _WIN32
  if (path[0] && path[1] == ':' && is_path_separator (path[2]))
    return true;
  if (is_path_separator (path[0]) && is_path_separator (path[1]))
    return true;
  return false;
#else
  return path[0] == '/';
#endif
}

[[nodiscard]] inline bool
is_relative_path (const char *path) noexcept
{
  return !is_absolute_path (path);
}

[[nodiscard]] inline bool
is_relative_path (std::string_view path) noexcept
{
  return !is_absolute_path (path);
}

// file_extension("foo.txt") -> ".txt"
// file_extension("foo.tar.gz") -> ".gz"
// file_extension("foo") -> ""
// file_extension(".bashrc") -> "" (hidden file, no extension)
// file_extension("foo.") -> "."
[[nodiscard]] inline std::string_view
file_extension (std::string_view path) noexcept
{
  auto basename = gnu_basename (path);
  if (basename.empty ())
    return "";

  auto dot_pos = basename.rfind ('.');

  if (dot_pos == std::string_view::npos || dot_pos == 0)
    return "";

  return basename.substr (dot_pos);
}

// file_stem("foo.txt") -> "foo"
// file_stem("foo.tar.gz") -> "foo.tar"
// file_stem("foo") -> "foo"
// file_stem(".bashrc") -> ".bashrc"
// file_stem("/path/to/foo.txt") -> "foo"
[[nodiscard]] inline std::string_view
file_stem (std::string_view path) noexcept
{
  auto basename = gnu_basename (path);
  if (basename.empty ())
    return "";

  auto dot_pos = basename.rfind ('.');

  if (dot_pos == std::string_view::npos || dot_pos == 0)
    return basename;

  return basename.substr (0, dot_pos);
}

// strip_trailing_slashes("/usr/lib/") -> "/usr/lib"
// strip_trailing_slashes("/") -> "/"
// strip_trailing_slashes("///") -> "/"
// strip_trailing_slashes("") -> ""
[[nodiscard]] inline std::string_view
strip_trailing_slashes (std::string_view path) noexcept
{
  if (path.empty ())
    return path;

  size_t len = path.size ();

  while (len > 1 && is_path_separator (path[len - 1]))
    --len;

#ifdef _WIN32
  if (len >= 2 && path[1] == ':' && len == 2 && path.size () > 2
      && is_path_separator (path[2]))
    return path.substr (0, 3);
#endif

  return path.substr (0, len);
}

[[nodiscard]] inline std::string
normalize_separators (std::string_view path)
{
  std::string result;
  result.reserve (path.size ());

  for (char c : path)
    {
      if (c == '\\')
	result.push_back ('/');
      else
	result.push_back (c);
    }

  return result;
}

[[nodiscard]] inline std::string
native_separators (std::string_view path)
{
  std::string result;
  result.reserve (path.size ());

  for (char c : path)
    {
#ifdef _WIN32
      if (c == '/')
	result.push_back ('\\');
      else
	result.push_back (c);
#else
      result.push_back (c);
#endif
    }

  return result;
}

// path_concat("/usr", "lib") -> "/usr/lib"
// path_concat("/usr/", "lib") -> "/usr/lib"
// path_concat("/usr", "/lib") -> "/lib" (absolute second arg)
// path_concat("", "lib") -> "lib"
// path_concat("/usr", "") -> "/usr"
[[nodiscard]] inline std::string
path_concat (std::string_view base, std::string_view name)
{
  if (is_absolute_path (name))
    return std::string (name);

  if (base.empty ())
    return std::string (name);

  if (name.empty ())
    return std::string (base);

  std::string result;
  result.reserve (base.size () + 1 + name.size ());
  result = base;

  if (!is_path_separator (result.back ())
      && !is_path_separator (name.front ()))
    result.push_back (PREFERRED_SEPARATOR);
  else if (is_path_separator (result.back ())
	   && is_path_separator (name.front ()))
    name.remove_prefix (1);

  result.append (name);
  return result;
}

namespace detail
{
inline void
path_join_impl (std::string &)
{
}

template <typename T, typename... Rest>
inline void
path_join_impl (std::string &result, T &&first, Rest &&...rest)
{
  std::string_view sv;
  if constexpr (std::is_same_v<std::decay_t<T>, std::string>)
    sv = first;
  else if constexpr (std::is_same_v<std::decay_t<T>,
				    std::string_view>)
    sv = first;
  else if constexpr (std::is_same_v<std::decay_t<T>, const char *>
		     || std::is_same_v<std::decay_t<T>, char *>)
    sv = first ? first : "";
  else
    sv = std::string_view (first);

  result = path_concat (result, sv);
  path_join_impl (result, std::forward<Rest> (rest)...);
}
}

// path_join("/usr", "local", "bin") -> "/usr/local/bin"
// path_join("a", "b", "c", "d") -> "a/b/c/d"
template <typename... Args>
[[nodiscard]] inline std::string
path_join (Args &&...args)
{
  std::string result;
  detail::path_join_impl (result, std::forward<Args> (args)...);
  return result;
}

[[nodiscard]] inline bool
has_trailing_separator (std::string_view path) noexcept
{
  return !path.empty () && is_path_separator (path.back ());
}

[[nodiscard]] inline std::string
ensure_trailing_separator (std::string_view path)
{
  if (path.empty ())
    return std::string (1, PREFERRED_SEPARATOR);

  if (is_path_separator (path.back ()))
    return std::string (path);

  std::string result;
  result.reserve (path.size () + 1);
  result = path;
  result.push_back (PREFERRED_SEPARATOR);
  return result;
}

[[nodiscard]] inline std::string
parent_path (std::string_view path)
{
  if (path.empty ())
    return "";

  auto dir = gnu_dirname (path);

  if (dir == "." || dir == path)
    return "";

#ifdef _WIN32
  if (dir.size () == 3 && dir[1] == ':' && is_path_separator (dir[2]))
    return dir;
  if (dir.size () == 2 && dir[1] == ':')
    return dir + "\\";
#endif

  return dir;
}

[[nodiscard]] inline bool
is_root_path (std::string_view path) noexcept
{
  if (path.empty ())
    return false;

#ifdef _WIN32
  if (path.size () == 3 && path[1] == ':'
      && is_path_separator (path[2]))
    return true;
  if (path.size () == 1 && is_path_separator (path[0]))
    return true;
  if (path.size () >= 2 && is_path_separator (path[0])
      && is_path_separator (path[1]))
    {
      auto pos = path.find_first_of ("/\\", 2);
      if (pos == std::string_view::npos)
	return true;
    }
  return false;
#else
  return path == "/";
#endif
}

// root_path("/usr/lib") -> "/"
// root_path("C:\\Users") -> "C:\\"
// root_path("relative/path") -> ""
[[nodiscard]] inline std::string
root_path (std::string_view path)
{
  if (path.empty ())
    return "";

#ifdef _WIN32
  if (path.size () >= 2 && path[1] == ':')
    {
      if (path.size () >= 3 && is_path_separator (path[2]))
	return std::string (path.substr (0, 3));
      return std::string (path.substr (0, 2));
    }
  if (path.size () >= 2 && is_path_separator (path[0])
      && is_path_separator (path[1]))
    {
      auto pos = path.find_first_of ("/\\", 2);
      if (pos != std::string_view::npos)
	{
	  auto pos2 = path.find_first_of ("/\\", pos + 1);
	  if (pos2 != std::string_view::npos)
	    return std::string (path.substr (0, pos2));
	  return std::string (path);
	}
      return std::string (path);
    }
  if (is_path_separator (path[0]))
    return std::string (1, path[0]);
  return "";
#else
  if (path[0] == '/')
    return "/";
  return "";
#endif
}

[[nodiscard]] inline size_t
path_component_count (std::string_view path) noexcept
{
  if (path.empty ())
    return 0;

  size_t count = 0;
  bool in_component = false;

  for (char c : path)
    {
      if (is_path_separator (c))
	{
	  if (in_component)
	    in_component = false;
	}
      else
	{
	  if (!in_component)
	    {
	      ++count;
	      in_component = true;
	    }
	}
    }

  return count;
}

[[nodiscard]] inline bool
path_starts_with (std::string_view path,
		  std::string_view prefix) noexcept
{
  if (prefix.empty ())
    return true;
  if (path.size () < prefix.size ())
    return false;

  for (size_t i = 0; i < prefix.size (); ++i)
    {
      if (is_path_separator (path[i])
	  && is_path_separator (prefix[i]))
	continue;
      if (path[i] != prefix[i])
	return false;
    }

  if (path.size () > prefix.size ())
    {
      if (!is_path_separator (prefix.back ())
	  && !is_path_separator (path[prefix.size ()]))
	return false;
    }

  return true;
}

[[nodiscard]] inline std::optional<std::string>
make_relative (std::string_view path, std::string_view base)
{
  auto norm_path = normalize_separators (path);
  auto norm_base = normalize_separators (base);

  while (!norm_base.empty () && norm_base.back () == '/')
    norm_base.pop_back ();

  if (!path_starts_with (norm_path, norm_base))
    return std::nullopt;

  if (norm_path.size () == norm_base.size ())
    return ".";

  size_t skip = norm_base.size ();
  if (skip < norm_path.size () && norm_path[skip] == '/')
    ++skip;

  return norm_path.substr (skip);
}

}
