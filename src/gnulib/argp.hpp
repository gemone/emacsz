// src/gnulib/argp.hpp - C++20 replacements for gnulib argument
// parsing Replaces: argp, argp-help

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace emacs::gnulib
{

enum class ArgpFlag : unsigned int
{
  OPTION_ARG_OPTIONAL = 1,
  OPTION_HIDDEN = 2,
  OPTION_ALIAS = 4,
  OPTION_DOC = 8,
};

enum class ArgpKey : int
{
  INIT = 0,
  KEY_ARG = -1,
  KEY_END = 1,
  KEY_SUCCESS = 2,
  KEY_ERROR = 3,
};

struct argp_option
{
  const char *name;
  int key;
  const char *arg;
  unsigned int flags;
  const char *doc;
};

constexpr argp_option argp_options_end
  = { nullptr, 0, nullptr, 0, nullptr };

class ArgumentParser
{
public:
  using handler_fn = std::function<int (int key, const char *arg)>;

  ArgumentParser (std::string_view doc,
		  std::string_view args_doc = "")
      : doc_ (doc), args_doc_ (args_doc)
  {
    options_.reserve (16);
  }

  void add_option (const argp_option &opt)
  {
    if (opt.name || opt.key)
      options_.push_back (opt);
  }

  void add_options (const argp_option *opts, size_t count)
  {
    for (size_t i = 0; i < count; ++i)
      {
	if (opts[i].name || opts[i].key)
	  add_option (opts[i]);
      }
  }

  int parse (int argc, char *const *argv, handler_fn handler)
  {
    if (argc < 1 || !argv)
      return EINVAL;

    program_name_ = std::string (argv[0]);

    int result = handler (static_cast<int> (ArgpKey::INIT), nullptr);
    if (result != 0)
      return result;

    int i = 1;
    while (i < argc)
      {
	const char *arg = argv[i];

	if (std::strcmp (arg, "--") == 0)
	  {
	    ++i;
	    break;
	  }

	if (arg[0] == '-' && arg[1] == '-')
	  {
	    result
	      = process_long_option (arg, argc, argv, i, handler);
	    if (result != 0)
	      return result;
	    ++i;
	  }
	else if (arg[0] == '-' && arg[1] != '\0')
	  {
	    result
	      = process_short_options (arg, argc, argv, i, handler);
	    if (result != 0)
	      return result;
	    ++i;
	  }
	else
	  {
	    result
	      = handler (static_cast<int> (ArgpKey::KEY_ARG), arg);
	    if (result != 0)
	      return result;
	    ++i;
	  }
      }

    while (i < argc)
      {
	int result
	  = handler (static_cast<int> (ArgpKey::KEY_ARG), argv[i]);
	if (result != 0)
	  return result;
	++i;
      }

    result = handler (static_cast<int> (ArgpKey::KEY_END), nullptr);
    return result;
  }

  void print_usage (FILE *stream = stderr) const
  {
    if (!program_name_.empty ())
      {
	std::fprintf (stream, "Usage: %s", program_name_.c_str ());
	if (!args_doc_.empty ())
	  std::fprintf (stream, " %s", args_doc_.data ());
	std::fprintf (stream, "\n");
      }
  }

  void print_help (FILE *stream = stdout) const
  {
    print_usage (stream);

    if (!doc_.empty ())
      std::fprintf (stream, "\n%s\n", doc_.data ());

    if (!options_.empty ())
      {
	std::fprintf (stream, "\nOptions:\n");
	print_options (stream);
      }
  }

  [[nodiscard]] std::string_view program_name () const noexcept
  {
    return program_name_;
  }

  [[nodiscard]] std::string_view documentation () const noexcept
  {
    return doc_;
  }

  [[nodiscard]] std::string_view args_documentation () const noexcept
  {
    return args_doc_;
  }

private:
  std::string doc_;
  std::string_view args_doc_;
  std::string program_name_;
  std::vector<argp_option> options_;

  int process_long_option (const char *arg, int argc,
			   char *const *argv, int &i,
			   handler_fn &handler)
  {
    const char *opt = arg + 2;
    const char *eq = std::strchr (opt, '=');
    std::string opt_name;
    std::string_view opt_value;
    bool has_value = false;

    if (eq)
      {
	opt_name = std::string (opt, eq - opt);
	opt_value = std::string_view (eq + 1);
	has_value = true;
      }
    else
      opt_name = std::string (opt);

    if (opt_name == "help" || opt_name == "h")
      {
	print_help (stdout);
	std::exit (0);
      }

    if (opt_name == "version")
      {
	print_usage (stdout);
	std::exit (0);
      }

    for (const auto &option : options_)
      {
	if (option.name && opt_name == option.name)
	  {
	    if (option.arg)
	      {
		if (has_value)
		  return handler (option.key, opt_value.data ());
		else if (i + 1 < argc)
		  {
		    ++i;
		    return handler (option.key, argv[i]);
		  }
		else if ((option.flags
			  & static_cast<unsigned int> (
			    ArgpFlag::OPTION_ARG_OPTIONAL))
			 == 0)
		  {
		    std::fprintf (stderr,
				  "%s: option '--%s' requires an "
				  "argument\n",
				  program_name_.c_str (),
				  option.name);
		    return EINVAL;
		  }
		else
		  return handler (option.key, nullptr);
	      }
	    else
	      {
		if (has_value)
		  {
		    std::fprintf (stderr,
				  "%s: option '--%s' takes no "
				  "argument\n",
				  program_name_.c_str (),
				  option.name);
		    return EINVAL;
		  }
		return handler (option.key, nullptr);
	      }
	  }
      }

    std::fprintf (stderr, "%s: unrecognized option '--%s'\n",
		  program_name_.c_str (), opt_name.c_str ());
    return EINVAL;
  }

  int process_short_options (const char *arg, int argc,
			     char *const *argv, int &i,
			     handler_fn &handler)
  {
    for (const char *p = arg + 1; *p; ++p)
      {
	char opt_char = *p;

	if (opt_char == 'h')
	  {
	    print_help (stdout);
	    std::exit (0);
	  }

	bool found = false;
	for (const auto &option : options_)
	  {
	    if (option.key == opt_char)
	      {
		found = true;
		if (option.arg)
		  {
		    std::string_view opt_value;
		    if (*(p + 1) != '\0')
		      {
			opt_value = std::string_view (p + 1);
			int result
			  = handler (option.key, opt_value.data ());
			if (result != 0)
			  return result;
			return 0;
		      }
		    else if (i + 1 < argc)
		      {
			++i;
			int result = handler (option.key, argv[i]);
			if (result != 0)
			  return result;
			return 0;
		      }
		    else if ((option.flags
			      & static_cast<unsigned int> (
				ArgpFlag::OPTION_ARG_OPTIONAL))
			     == 0)
		      {
			std::fprintf (stderr,
				      "%s: option requires an "
				      "argument -- %c\n",
				      program_name_.c_str (),
				      opt_char);
			return EINVAL;
		      }
		    else
		      return handler (option.key, nullptr);
		  }
		else
		  {
		    int result = handler (option.key, nullptr);
		    if (result != 0)
		      return result;
		  }
		break;
	      }
	  }

	if (!found)
	  {
	    std::fprintf (stderr, "%s: invalid option -- %c\n",
			  program_name_.c_str (), opt_char);
	    return EINVAL;
	  }
      }

    return 0;
  }

  void print_options (FILE *stream) const
  {
    for (const auto &option : options_)
      {
	if ((option.flags
	     & static_cast<unsigned int> (ArgpFlag::OPTION_HIDDEN))
	    != 0)
	  continue;

	if ((option.flags
	     & static_cast<unsigned int> (ArgpFlag::OPTION_DOC))
	    != 0)
	  {
	    if (option.doc)
	      std::fprintf (stream, "\n  %s\n", option.doc);
	    continue;
	  }

	if (!option.name)
	  continue;

	std::fprintf (stream, "  ");

	if (option.key >= 32 && option.key < 127)
	  std::fprintf (stream, "-%c, ", option.key);

	std::fprintf (stream, "--%s", option.name);

	if (option.arg)
	  std::fprintf (stream, "=%s", option.arg);

	if (option.doc)
	  std::fprintf (stream, "\n        %s", option.doc);

	std::fprintf (stream, "\n");
      }

    std::fprintf (stream,
		  "  -h, --help\n        Give this help list\n");
    std::
      fprintf (stream,
	       "      --version\n        Show version information\n");
  }
};

[[nodiscard]] inline ArgumentParser
make_argument_parser (std::string_view doc,
		      std::string_view args_doc = "")
{
  return ArgumentParser (doc, args_doc);
}

}
