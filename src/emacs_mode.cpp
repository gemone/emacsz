#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <algorithm>
#include <utility>

#include "emacs_mode.hpp"

namespace emacs
{

ModeDefinition::ModeDefinition (std::string_view mode_name,
				ModeType mode_type,
				std::string_view doc,
				std::string_view parent)
    : name (mode_name.data (), mode_name.size ()), type (mode_type),
      docstring (doc.data (), doc.size ()), keymap (mode_name),
      parent_name (parent.data (), parent.size ())
{
}

ModeManager &
ModeManager::instance () noexcept
{
  static ModeManager manager;
  return manager;
}

void
ModeManager::define_major_mode (std::string_view name,
				std::string_view docstring,
				std::string_view parent_name)
{
  auto existing
    = modes_.find (gc_string (name.data (), name.size ()));
  if (existing != modes_.end ())
    return;

  ModeDefinition def (name, ModeType::Major, docstring, parent_name);
  ModeDefinition *parent = nullptr;
  if (!parent_name.empty ())
    parent = find_mode (parent_name);
  if (parent)
    def.keymap.set_parent (&parent->keymap);
  modes_.emplace (def.name, std::move (def));
}

void
ModeManager::define_minor_mode (std::string_view name,
				std::string_view docstring)
{
  auto existing
    = modes_.find (gc_string (name.data (), name.size ()));
  if (existing != modes_.end ())
    return;

  ModeDefinition def (name, ModeType::Minor, docstring, "");
  modes_.emplace (def.name, std::move (def));
}

[[nodiscard]] Keymap &
ModeManager::mode_keymap (std::string_view name)
{
  ModeDefinition *mode = find_mode (name);
  if (!mode)
    {
      define_major_mode (name, "");
      mode = find_mode (name);
    }
  if (mode)
    ensure_parent_keymap (*mode);
  return mode->keymap;
}

void
ModeManager::activate_major_mode (std::string_view name,
				  EmacsBuffer *buffer)
{
  (void) buffer;
  ModeDefinition *target = find_mode (name);
  if (!target || target->type != ModeType::Major)
    return;

  if (current_major_mode_ == target->name)
    return;

  ModeDefinition *current = find_mode (current_major_mode_);
  if (current && current->type == ModeType::Major)
    {
      for (const ModeHook &hook : current->disable_hooks)
	{
	  hook ();
	}
    }

  ensure_parent_keymap (*target);
  current_major_mode_ = target->name;
  KeymapManager::instance ().set_major_mode_keymap (&target->keymap);

  for (const ModeHook &hook : target->enable_hooks)
    {
      hook ();
    }
}

void
ModeManager::enable_minor_mode (std::string_view name,
				EmacsBuffer *buffer)
{
  (void) buffer;
  ModeDefinition *target = find_mode (name);
  if (!target || target->type != ModeType::Minor)
    return;
  if (minor_mode_enabled (name))
    return;

  KeymapManager::instance ().push_minor_mode_keymap (&target->keymap);
  active_minor_modes_.push_back (target->name);

  for (const ModeHook &hook : target->enable_hooks)
    {
      hook ();
    }
}

void
ModeManager::disable_minor_mode (std::string_view name,
				 EmacsBuffer *buffer)
{
  (void) buffer;
  ModeDefinition *target = find_mode (name);
  if (!target || target->type != ModeType::Minor)
    return;
  if (!minor_mode_enabled (name))
    return;

  KeymapManager::instance ().remove_minor_mode_keymap (
    &target->keymap);
  auto it = std::remove (active_minor_modes_.begin (),
			 active_minor_modes_.end (), target->name);
  active_minor_modes_.erase (it, active_minor_modes_.end ());

  for (const ModeHook &hook : target->disable_hooks)
    {
      hook ();
    }
}

[[nodiscard]] const gc_string &
ModeManager::current_major_mode () const noexcept
{
  return current_major_mode_;
}

[[nodiscard]] bool
ModeManager::minor_mode_enabled (std::string_view name) const noexcept
{
  gc_string key (name.data (), name.size ());
  return std::find (active_minor_modes_.begin (),
		    active_minor_modes_.end (), key)
	 != active_minor_modes_.end ();
}

[[nodiscard]] gc_vector_t<gc_string>
ModeManager::active_minor_modes () const
{
  return active_minor_modes_;
}

[[nodiscard]] bool
ModeManager::has_mode (std::string_view name) const noexcept
{
  return find_mode (name) != nullptr;
}

void
ModeManager::add_mode_hook (std::string_view mode_name, ModeHook hook,
			    bool enable)
{
  ModeDefinition *mode = find_mode (mode_name);
  if (!mode)
    return;
  if (enable)
    mode->enable_hooks.push_back (std::move (hook));
  else
    mode->disable_hooks.push_back (std::move (hook));
}

void
ModeManager::reset ()
{
  modes_.clear ();
  current_major_mode_.clear ();
  active_minor_modes_.clear ();
  KeymapManager::instance ().clear ();
  init_fundamental_mode ();
}

ModeManager::ModeManager () { init_fundamental_mode (); }

[[nodiscard]] ModeDefinition *
ModeManager::find_mode (std::string_view name) noexcept
{
  gc_string key (name.data (), name.size ());
  auto it = modes_.find (key);
  if (it == modes_.end ())
    return nullptr;
  return &it->second;
}

[[nodiscard]] const ModeDefinition *
ModeManager::find_mode (std::string_view name) const noexcept
{
  gc_string key (name.data (), name.size ());
  auto it = modes_.find (key);
  if (it == modes_.end ())
    return nullptr;
  return &it->second;
}

void
ModeManager::ensure_parent_keymap (ModeDefinition &mode)
{
  if (mode.type != ModeType::Major)
    return;
  if (mode.parent_name.empty ())
    return;
  ModeDefinition *parent = find_mode (mode.parent_name);
  if (!parent)
    return;
  if (mode.keymap.parent () != &parent->keymap)
    mode.keymap.set_parent (&parent->keymap);
}

void
ModeManager::init_fundamental_mode ()
{
  define_major_mode ("fundamental-mode", "", "");
  current_major_mode_ = "fundamental-mode";
  ModeDefinition *mode = find_mode ("fundamental-mode");
  if (mode)
    KeymapManager::instance ().set_major_mode_keymap (&mode->keymap);
}

} // namespace emacs

extern "C"
{
  int emacs_cxx_activate_major_mode (const char *name)
  {
    if (!name)
      return -1;
    try
      {
	emacs::ModeManager::instance ().activate_major_mode (name,
							     nullptr);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_enable_minor_mode (const char *name)
  {
    if (!name)
      return -1;
    try
      {
	emacs::ModeManager::instance ().enable_minor_mode (name,
							   nullptr);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_disable_minor_mode (const char *name)
  {
    if (!name)
      return -1;
    try
      {
	emacs::ModeManager::instance ().disable_minor_mode (name,
							    nullptr);
	return 0;
      }
    catch (...)
      {
	return -1;
      }
  }

  const char *emacs_cxx_current_major_mode ()
  {
    try
      {
	const emacs::gc_string &name
	  = emacs::ModeManager::instance ().current_major_mode ();
	return name.c_str ();
      }
    catch (...)
      {
	return "";
      }
  }
}
