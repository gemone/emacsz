// src/main.cpp
#include <iostream>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

#include "termbox2_term.hpp"

namespace emacs
{

class StartupResourceManager
{
private:
  bool initialized_;
  int argc_;
  char **argv_;

public:
  StartupResourceManager (int argc, char *argv[])
      : initialized_ (false), argc_ (argc), argv_ (argv)
  {
  }

  ~StartupResourceManager () = default;

  StartupResourceManager (const StartupResourceManager &) = delete;
  StartupResourceManager &operator= (const StartupResourceManager &)
    = delete;

  StartupResourceManager (StartupResourceManager &&other) noexcept
      : initialized_ (other.initialized_), argc_ (other.argc_),
	argv_ (other.argv_)
  {
    other.initialized_ = false;
  }

  StartupResourceManager &
  operator= (StartupResourceManager &&other) noexcept
  {
    if (this != &other)
      {
	initialized_ = other.initialized_;
	argc_ = other.argc_;
	argv_ = other.argv_;
	other.initialized_ = false;
      }
    return *this;
  }

  [[nodiscard]] bool is_initialized () const noexcept
  {
    return initialized_;
  }

  void mark_initialized () { initialized_ = true; }
};

class CommandLineParser
{
private:
  int argc_;
  char **argv_;

public:
  CommandLineParser (int argc, char *argv[])
      : argc_ (argc), argv_ (argv)
  {
  }

  [[nodiscard]] std::span<char *> arguments () const noexcept
  {
    return std::span<char *> (argv_, static_cast<size_t> (argc_));
  }

  [[nodiscard]] std::string_view program_name () const noexcept
  {
    if (argc_ > 0)
      {
	return std::string_view (argv_[0]);
      }
    return {};
  }

  [[nodiscard]] int argument_count () const noexcept { return argc_; }

  [[nodiscard]] bool
  has_argument (std::string_view arg) const noexcept
  {
    for (const auto &a : arguments ())
      {
	if (std::string_view (a) == arg)
	  {
	    return true;
	  }
      }
    return false;
  }

  [[nodiscard]] bool has_flag (std::string_view flag) const noexcept
  {
    return has_argument (flag);
  }
};

} // namespace emacs

int
main (int argc, char *argv[])
{
  emacs::StartupResourceManager resources (argc, argv);

  try
    {
      emacs::CommandLineParser parser (argc, argv);

      bool batch_mode = parser.has_flag ("--batch");
      [[maybe_unused]] bool debug_mode
	= parser.has_flag ("--debug-init");
      [[maybe_unused]] bool no_site_lisp
	= parser.has_flag ("--no-site-file");
      [[maybe_unused]] bool no_init_file
	= parser.has_flag ("--no-init-file");
      [[maybe_unused]] bool no_loadup
	= parser.has_flag ("--no-loadup");
      [[maybe_unused]] bool no_splash
	= parser.has_flag ("--no-splash");
      [[maybe_unused]] bool no_x_resources
	= parser.has_flag ("--no-x-resources");
      bool no_window_system = parser.has_flag ("--no-window-system");

      resources.mark_initialized ();

      bool use_termbox2 = !batch_mode && !no_window_system;

      emacs::Termbox2Backend termbox2_backend;

      if (use_termbox2 && !termbox2_backend.init ())
	{
	  std::cerr
	    << "FAIL: Termbox2 backend initialization failed\n";
	  return EXIT_FAILURE;
	}

      if (parser.has_flag ("--version"))
	{
	  std::cout << "GNU Emacs (C++20 TUI Demo)\n";
	  return EXIT_SUCCESS;
	}

      if (parser.has_flag ("--help"))
	{
	  std::cout << "Usage: emacs [OPTIONS]\n";
	  std::cout << "  --batch           Run in batch mode\n";
	  std::cout << "  --no-window-system  Disable TUI\n";
	  std::cout << "  --version         Show version\n";
	  std::cout << "  --help            Show this help\n";
	  return EXIT_SUCCESS;
	}

      if (use_termbox2)
	{
	  termbox2_backend.clear_frame ();
	  termbox2_backend.set_cursor_position ({ 0, 0 });
	  termbox2_backend.write_text (
	    "Emacs C++20 - Press 'q' to quit");

	  while (true)
	    {
	      int key = termbox2_backend.read_input ();
	      if (key == 'q' || key == 'Q')
		break;
	    }
	}
      else
	{
	  std::cout << "Running in batch/non-TUI mode\n";
	}
    }
  catch (const std::exception &e)
    {
      std::cerr << "Emacs fatal error: " << e.what () << "\n";
      return EXIT_FAILURE;
    }

  return EXIT_SUCCESS;
}
