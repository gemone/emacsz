#pragma once

#include <cstddef>
#include <functional>
#include <string_view>

#include "containers.hpp"

namespace emacs
{

class EmacsBuffer;

struct CommandContext
{
  EmacsBuffer *buffer;
  int prefix_argument;
  bool has_prefix;
  bool raw_prefix;
};

using CommandFn = std::function<void (CommandContext &)>;

struct InteractiveSpec
{
  gc_string code;
  [[nodiscard]] bool is_interactive () const noexcept;
};

struct CommandDef
{
  gc_string name;
  CommandFn fn;
  gc_string docstring;
  InteractiveSpec interactive;
  int min_args;
  int max_args;
};

class CommandRegistry
{
public:
  static CommandRegistry &instance () noexcept;

  void register_command (std::string_view name, CommandFn fn,
			 std::string_view docstring = "",
			 std::string_view interactive_spec = "",
			 int min_args = 0, int max_args = 0);

  [[nodiscard]] const CommandDef *
  lookup (std::string_view name) const noexcept;

  [[nodiscard]] bool execute (std::string_view name,
			      CommandContext &ctx) const;

  [[nodiscard]] gc_vector_t<const CommandDef *>
  list_commands () const;

  [[nodiscard]] gc_vector_t<const CommandDef *>
  list_interactive_commands () const;

  [[nodiscard]] size_t count () const noexcept;

  [[nodiscard]] bool
  has_command (std::string_view name) const noexcept;

  [[nodiscard]] gc_vector_t<const CommandDef *>
  complete_prefix (std::string_view prefix) const;

  void clear () noexcept;

private:
  CommandRegistry () = default;
  gc_unordered_map<gc_string, CommandDef> commands_;
};

} // namespace emacs

extern "C"
{
  int emacs_cxx_register_command (const char *name,
				  void (*fn) (void *),
				  const char *docstring);
  int emacs_cxx_execute_command (const char *name, void *buffer_ptr);
  int emacs_cxx_has_command (const char *name);
}
