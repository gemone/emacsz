#include "emacs_keymap.hpp"

#include <algorithm>
#include <cstring>

namespace emacs
{

bool
KeyStroke::operator== (const KeyStroke &other) const noexcept
{
  return key == other.key && modifiers == other.modifiers
	 && unicode == other.unicode;
}

size_t
KeyStrokeHash::operator() (const KeyStroke &ks) const noexcept
{
  size_t key_part = static_cast<size_t> (ks.key);
  size_t mod_part = static_cast<size_t> (ks.modifiers);
  size_t uni_part = static_cast<size_t> (ks.unicode);
  return (key_part << 16) ^ (mod_part << 8) ^ uni_part;
}

[[nodiscard]] KeyStroke
make_keystroke (tui::KeyCode key, tui::KeyModifier mods) noexcept
{
  KeyStroke ks;
  ks.key = key;
  ks.modifiers = mods;
  ks.unicode = 0;
  return ks;
}

[[nodiscard]] KeyStroke
make_char_keystroke (char c) noexcept
{
  KeyStroke ks;
  ks.key = tui::KeyCode::Unknown;
  ks.modifiers = tui::KeyModifier::None;
  ks.unicode = static_cast<uint32_t> (static_cast<unsigned char> (c));
  return ks;
}

[[nodiscard]] KeyStroke
make_ctrl_keystroke (char c) noexcept
{
  KeyStroke ks;
  ks.key = tui::KeyCode::Unknown;
  ks.modifiers = tui::KeyModifier::Ctrl;
  ks.unicode = static_cast<uint32_t> (static_cast<unsigned char> (c));
  return ks;
}

Keymap::Keymap (std::string_view name)
    : name_ (name.data (), name.size ())
{
}

void
Keymap::bind (const KeyStroke &ks, std::string_view command)
{
  Binding binding;
  binding.is_prefix = false;
  binding.command = gc_string (command.data (), command.size ());
  bindings_[ks] = std::move (binding);
}

void
Keymap::bind_sequence (const KeySequence &seq,
		       std::string_view command)
{
  if (seq.empty ())
    return;
  if (seq.size () == 1)
    {
      bind (seq.front (), command);
      return;
    }

  Keymap *prefix = get_or_create_prefix_keymap (seq.front ());
  if (!prefix)
    return;

  KeySequence rest (seq.begin () + 1, seq.end ());
  prefix->bind_sequence (rest, command);
}

[[nodiscard]] KeyLookupResult
Keymap::lookup (const KeyStroke &ks) const noexcept
{
  auto it = bindings_.find (ks);
  if (it == bindings_.end ())
    {
      if (parent_)
	return parent_->lookup (ks);
      return { KeyLookupType::Unbound, gc_string () };
    }

  if (it->second.is_prefix)
    return { KeyLookupType::PrefixKey, gc_string () };

  return { KeyLookupType::Command, it->second.command };
}

[[nodiscard]] KeyLookupResult
Keymap::lookup_sequence (const KeySequence &seq) const noexcept
{
  if (seq.empty ())
    return { KeyLookupType::Unbound, gc_string () };

  const Keymap *current = this;
  for (size_t i = 0; i < seq.size (); ++i)
    {
      const KeyStroke &ks = seq[i];
      auto it = current->bindings_.find (ks);
      if (it == current->bindings_.end ())
	{
	  if (current->parent_)
	    return current->parent_->lookup_sequence (
	      KeySequence (seq.begin () + i, seq.end ()));
	  return { KeyLookupType::Unbound, gc_string () };
	}

      if (i + 1 == seq.size ())
	{
	  if (it->second.is_prefix)
	    return { KeyLookupType::PrefixKey, gc_string () };
	  return { KeyLookupType::Command, it->second.command };
	}

      if (!it->second.is_prefix || !it->second.sub_keymap)
	return { KeyLookupType::Unbound, gc_string () };

      current = it->second.sub_keymap.get ();
    }

  return { KeyLookupType::Unbound, gc_string () };
}

[[nodiscard]] bool
Keymap::is_prefix (const KeyStroke &ks) const noexcept
{
  auto it = bindings_.find (ks);
  if (it == bindings_.end ())
    return false;
  return it->second.is_prefix;
}

[[nodiscard]] const Keymap *
Keymap::get_prefix_keymap (const KeyStroke &ks) const noexcept
{
  auto it = bindings_.find (ks);
  if (it == bindings_.end ())
    return nullptr;
  if (!it->second.is_prefix)
    return nullptr;
  return it->second.sub_keymap.get ();
}

[[nodiscard]] Keymap *
Keymap::get_or_create_prefix_keymap (const KeyStroke &ks)
{
  auto it = bindings_.find (ks);
  if (it != bindings_.end ())
    {
      if (!it->second.is_prefix)
	{
	  it->second.is_prefix = true;
	  it->second.command.clear ();
	  it->second.sub_keymap = std::make_unique<Keymap> ("prefix");
	}
      return it->second.sub_keymap.get ();
    }

  Binding binding;
  binding.is_prefix = true;
  binding.sub_keymap = std::make_unique<Keymap> ("prefix");
  bindings_[ks] = std::move (binding);
  return bindings_[ks].sub_keymap.get ();
}

void
Keymap::unbind (const KeyStroke &ks)
{
  bindings_.erase (ks);
}

[[nodiscard]] const gc_string &
Keymap::name () const noexcept
{
  return name_;
}

void
Keymap::set_parent (const Keymap *parent) noexcept
{
  parent_ = parent;
}

[[nodiscard]] const Keymap *
Keymap::parent () const noexcept
{
  return parent_;
}

KeymapManager &
KeymapManager::instance () noexcept
{
  static KeymapManager manager;
  return manager;
}

Keymap &
KeymapManager::global_keymap () noexcept
{
  return global_keymap_;
}

void
KeymapManager::set_major_mode_keymap (const Keymap *km) noexcept
{
  major_mode_keymap_ = km;
}

void
KeymapManager::push_minor_mode_keymap (const Keymap *km)
{
  if (!km)
    return;
  minor_mode_keymaps_.push_back (km);
}

void
KeymapManager::remove_minor_mode_keymap (const Keymap *km)
{
  if (!km)
    return;
  auto it = std::remove (minor_mode_keymaps_.begin (),
			 minor_mode_keymaps_.end (), km);
  minor_mode_keymaps_.erase (it, minor_mode_keymaps_.end ());
}

void
KeymapManager::set_local_keymap (const Keymap *km) noexcept
{
  local_keymap_ = km;
}

[[nodiscard]] KeyLookupResult
KeymapManager::lookup (const KeyStroke &ks) const noexcept
{
  if (local_keymap_)
    {
      KeyLookupResult result = local_keymap_->lookup (ks);
      if (result.type != KeyLookupType::Unbound)
	return result;
    }

  for (auto it = minor_mode_keymaps_.rbegin ();
       it != minor_mode_keymaps_.rend (); ++it)
    {
      if (!*it)
	continue;
      KeyLookupResult result = (*it)->lookup (ks);
      if (result.type != KeyLookupType::Unbound)
	return result;
    }

  if (major_mode_keymap_)
    {
      KeyLookupResult result = major_mode_keymap_->lookup (ks);
      if (result.type != KeyLookupType::Unbound)
	return result;
    }

  return global_keymap_.lookup (ks);
}

[[nodiscard]] KeyLookupResult
KeymapManager::lookup_sequence (const KeySequence &seq) const noexcept
{
  if (seq.empty ())
    return { KeyLookupType::Unbound, gc_string () };

  KeyLookupResult first = lookup (seq.front ());
  if (first.type != KeyLookupType::PrefixKey)
    {
      if (seq.size () == 1)
	return first;
      return { KeyLookupType::Unbound, gc_string () };
    }

  const Keymap *prefix_keymap = nullptr;
  if (local_keymap_ && local_keymap_->is_prefix (seq.front ()))
    prefix_keymap = local_keymap_->get_prefix_keymap (seq.front ());

  if (!prefix_keymap)
    {
      for (auto it = minor_mode_keymaps_.rbegin ();
	   it != minor_mode_keymaps_.rend (); ++it)
	{
	  if (!*it)
	    continue;
	  if ((*it)->is_prefix (seq.front ()))
	    {
	      prefix_keymap = (*it)->get_prefix_keymap (seq.front ());
	      if (prefix_keymap)
		break;
	    }
	}
    }

  if (!prefix_keymap && major_mode_keymap_
      && major_mode_keymap_->is_prefix (seq.front ()))
    prefix_keymap
      = major_mode_keymap_->get_prefix_keymap (seq.front ());

  if (!prefix_keymap && global_keymap_.is_prefix (seq.front ()))
    prefix_keymap = global_keymap_.get_prefix_keymap (seq.front ());

  if (!prefix_keymap)
    return { KeyLookupType::Unbound, gc_string () };

  KeySequence rest (seq.begin () + 1, seq.end ());
  return prefix_keymap->lookup_sequence (rest);
}

void
KeymapManager::clear () noexcept
{
  major_mode_keymap_ = nullptr;
  minor_mode_keymaps_.clear ();
  local_keymap_ = nullptr;
  global_keymap_ = Keymap ("global");
}

KeymapManager::KeymapManager () : global_keymap_ ("global") {}

} // namespace emacs

extern "C"
{
  int emacs_cxx_keymap_bind (const char *keymap_name, int key_code,
			     int modifiers, const char *command)
  {
    if (!keymap_name || !command)
      return -1;
    try
      {
	emacs::KeymapManager &manager
	  = emacs::KeymapManager::instance ();
	if (std::string_view (keymap_name) == "global")
	  {
	    emacs::KeyStroke ks = emacs::
	      make_keystroke (static_cast<emacs::tui::KeyCode> (
				key_code),
			      static_cast<emacs::tui::KeyModifier> (
				modifiers));
	    manager.global_keymap ().bind (ks, command);
	    return 0;
	  }
	return -1;
      }
    catch (...)
      {
	return -1;
      }
  }

  int emacs_cxx_keymap_lookup (int key_code, int modifiers,
			       char *out_command, int out_len)
  {
    if (!out_command || out_len <= 0)
      return -1;
    try
      {
	emacs::KeyStroke ks
	  = emacs::make_keystroke (static_cast<emacs::tui::KeyCode> (
				     key_code),
				   static_cast<
				     emacs::tui::KeyModifier> (
				     modifiers));
	emacs::KeyLookupResult result
	  = emacs::KeymapManager::instance ().lookup (ks);
	if (result.type != emacs::KeyLookupType::Command)
	  return 0;

	int copy_len = static_cast<int> (result.command_name.size ());
	if (copy_len >= out_len)
	  copy_len = out_len - 1;
	std::memcpy (out_command, result.command_name.data (),
		     static_cast<size_t> (copy_len));
	out_command[copy_len] = '\0';
	return 1;
      }
    catch (...)
      {
	return -1;
      }
  }
}
