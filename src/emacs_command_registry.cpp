#include "emacs_command_registry.hpp"

#include <algorithm>

namespace emacs
{

[[nodiscard]] bool
InteractiveSpec::is_interactive () const noexcept
{
  return !code.empty ();
}

CommandRegistry &
CommandRegistry::instance () noexcept
{
  static CommandRegistry registry;
  return registry;
}

void
CommandRegistry::register_command (std::string_view name,
				   CommandFn fn,
				   std::string_view docstring,
				   std::string_view interactive_spec,
				   int min_args, int max_args)
{
  CommandDef def;
  def.name = gc_string (name.data (), name.size ());
  def.fn = std::move (fn);
  def.docstring = gc_string (docstring.data (), docstring.size ());
  def.interactive.code
    = gc_string (interactive_spec.data (), interactive_spec.size ());
  def.min_args = min_args;
  def.max_args = max_args;

  commands_[def.name] = std::move (def);
}

[[nodiscard]] const CommandDef *
CommandRegistry::lookup (std::string_view name) const noexcept
{
  gc_string key (name.data (), name.size ());
  auto it = commands_.find (key);
  if (it == commands_.end ())
    return nullptr;
  return &it->second;
}

[[nodiscard]] bool
CommandRegistry::execute (std::string_view name,
			  CommandContext &ctx) const
{
  const CommandDef *def = lookup (name);
  if (!def)
    return false;
  def->fn (ctx);
  return true;
}

[[nodiscard]] gc_vector_t<const CommandDef *>
CommandRegistry::list_commands () const
{
  gc_vector_t<const CommandDef *> entries;
  entries.reserve (commands_.size ());
  for (const auto &entry : commands_)
    entries.push_back (&entry.second);

  std::sort (entries.begin (), entries.end (),
	     [] (const CommandDef *left, const CommandDef *right)
	       { return left->name < right->name; });

  return entries;
}

[[nodiscard]] gc_vector_t<const CommandDef *>
CommandRegistry::list_interactive_commands () const
{
  gc_vector_t<const CommandDef *> entries;
  entries.reserve (commands_.size ());
  for (const auto &entry : commands_)
    {
      if (!entry.second.interactive.is_interactive ())
	continue;
      entries.push_back (&entry.second);
    }

  std::sort (entries.begin (), entries.end (),
	     [] (const CommandDef *left, const CommandDef *right)
	       { return left->name < right->name; });

  return entries;
}

[[nodiscard]] size_t
CommandRegistry::count () const noexcept
{
  return commands_.size ();
}

[[nodiscard]] bool
CommandRegistry::has_command (std::string_view name) const noexcept
{
  return lookup (name) != nullptr;
}

[[nodiscard]] gc_vector_t<const CommandDef *>
CommandRegistry::complete_prefix (std::string_view prefix) const
{
  gc_vector_t<const CommandDef *> entries;
  entries.reserve (commands_.size ());
  for (const auto &entry : commands_)
    {
      if (entry.second.name.compare (0, prefix.size (), prefix) != 0)
	continue;
      entries.push_back (&entry.second);
    }

  std::sort (entries.begin (), entries.end (),
	     [] (const CommandDef *left, const CommandDef *right)
	       { return left->name < right->name; });

  return entries;
}

void
CommandRegistry::clear () noexcept
{
  commands_.clear ();
}

} // namespace emacs

extern "C"
{
  int emacs_cxx_register_command (const char *name,
				  void (*fn) (void *),
				  const char *docstring)
  {
    if (!name || !fn)
      return -1;
    try
      {
	emacs::CommandRegistry::instance ().register_command (
	  name, [fn] (emacs::CommandContext &ctx)
	    { fn (static_cast<void *> (ctx.buffer)); },
	  docstring ? docstring : "", "", 0, 0);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_execute_command (const char *name, void *buffer_ptr)
  {
    if (!name)
      return -1;
    try
      {
	emacs::CommandContext ctx;
	ctx.buffer = static_cast<emacs::EmacsBuffer *> (buffer_ptr);
	ctx.prefix_argument = 0;
	ctx.has_prefix = false;
	ctx.raw_prefix = false;

	bool ok
	  = emacs::CommandRegistry::instance ().execute (name, ctx);
	return ok ? 0 : -1;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_has_command (const char *name)
  {
    if (!name)
      return 0;
    try
      {
	return emacs::CommandRegistry::instance ().has_command (name)
		 ? 1
		 : 0;
      }
    catch (...)
      {
	return 0;
      }
  }
}
