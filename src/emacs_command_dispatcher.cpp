#include <cstdio>
#include <utility>

#include "emacs_buffer.hpp"
#include "emacs_command_dispatcher.hpp"

namespace emacs
{

static gc_string
format_key_name (const KeyStroke &ks)
{
  if (ks.unicode >= 32 && ks.unicode < 127)
    return gc_string (1, static_cast<char> (ks.unicode));

  switch (ks.key)
    {
    case tui::KeyCode::Tab:
      return "TAB";
    case tui::KeyCode::Enter:
      return "RET";
    case tui::KeyCode::Escape:
      return "ESC";
    case tui::KeyCode::Backspace:
      return "DEL";
    case tui::KeyCode::ArrowUp:
      return "UP";
    case tui::KeyCode::ArrowDown:
      return "DOWN";
    case tui::KeyCode::ArrowLeft:
      return "LEFT";
    case tui::KeyCode::ArrowRight:
      return "RIGHT";
    case tui::KeyCode::Home:
      return "HOME";
    case tui::KeyCode::End:
      return "END";
    case tui::KeyCode::PageUp:
      return "PGUP";
    case tui::KeyCode::PageDown:
      return "PGDN";
    case tui::KeyCode::Insert:
      return "INS";
    case tui::KeyCode::Delete:
      return "DELETE";
    case tui::KeyCode::F1:
      return "F1";
    case tui::KeyCode::F2:
      return "F2";
    case tui::KeyCode::F3:
      return "F3";
    case tui::KeyCode::F4:
      return "F4";
    case tui::KeyCode::F5:
      return "F5";
    case tui::KeyCode::F6:
      return "F6";
    case tui::KeyCode::F7:
      return "F7";
    case tui::KeyCode::F8:
      return "F8";
    case tui::KeyCode::F9:
      return "F9";
    case tui::KeyCode::F10:
      return "F10";
    case tui::KeyCode::F11:
      return "F11";
    case tui::KeyCode::F12:
      return "F12";
    case tui::KeyCode::Unknown:
    default:
      break;
    }

  char buf[16];
  std::snprintf (buf, sizeof (buf), "U+%04X",
		 static_cast<unsigned int> (ks.unicode));
  return gc_string (buf);
}

static void
append_keystroke (gc_string &out, const KeyStroke &ks)
{
  if (tui::has_modifier (ks.modifiers, tui::KeyModifier::Ctrl))
    out.append ("C-");
  if (tui::has_modifier (ks.modifiers, tui::KeyModifier::Meta))
    out.append ("M-");
  if (tui::has_modifier (ks.modifiers, tui::KeyModifier::Alt))
    out.append ("A-");
  if (tui::has_modifier (ks.modifiers, tui::KeyModifier::Shift))
    out.append ("S-");

  out.append (format_key_name (ks));
}

CommandDispatcher &
CommandDispatcher::instance () noexcept
{
  static CommandDispatcher dispatcher;
  return dispatcher;
}

[[nodiscard]] DispatchResult
CommandDispatcher::dispatch (const tui::InputEvent &event,
			     EmacsBuffer *buffer)
{
  if (buffer)
    current_buffer_ = buffer;

  if (event.type != tui::InputEventType::Key)
    return DispatchResult::Unbound;

  const tui::KeyEvent &ke = event.key;
  KeyStroke ks = key_event_to_keystroke (ke);

  if (tui::has_modifier (ke.modifiers, tui::KeyModifier::Ctrl)
      && (ke.unicode == 'u' || ke.unicode == 'U'))
    {
      if (has_prefix_)
	prefix_argument_ *= 4;
      else
	prefix_argument_ = 4;
      has_prefix_ = true;
      raw_prefix_ = true;
      return DispatchResult::Executed;
    }

  pending_keys_.push_back (ks);
  KeyLookupResult result
    = KeymapManager::instance ().lookup_sequence (pending_keys_);

  switch (result.type)
    {
    case KeyLookupType::PrefixKey:
      update_message ();
      return DispatchResult::PrefixKey;
    case KeyLookupType::Command:
      {
	bool ok = execute_command (result.command_name, buffer);
	reset_key_sequence ();
	clear_message ();
	return ok ? DispatchResult::Executed : DispatchResult::Error;
      }
    case KeyLookupType::Unbound:
    default:
      break;
    }

  bool only_shift = (ke.modifiers == tui::KeyModifier::None
		     || ke.modifiers == tui::KeyModifier::Shift);
  if (pending_keys_.size () == 1 && ke.unicode >= 32 && only_shift)
    {
      bool ok = try_self_insert (ke, buffer);
      reset_key_sequence ();
      clear_message ();
      if (ok)
	return DispatchResult::SelfInsert;
    }

  reset_key_sequence ();
  clear_message ();
  return DispatchResult::Unbound;
}

void
CommandDispatcher::set_current_buffer (EmacsBuffer *buffer) noexcept
{
  current_buffer_ = buffer;
}

[[nodiscard]] EmacsBuffer *
CommandDispatcher::current_buffer () const noexcept
{
  return current_buffer_;
}

void
CommandDispatcher::set_prefix_argument (int arg) noexcept
{
  prefix_argument_ = arg;
  has_prefix_ = true;
  raw_prefix_ = false;
}

[[nodiscard]] int
CommandDispatcher::prefix_argument () const noexcept
{
  return prefix_argument_;
}

[[nodiscard]] bool
CommandDispatcher::has_prefix_argument () const noexcept
{
  return has_prefix_;
}

void
CommandDispatcher::clear_prefix_argument () noexcept
{
  prefix_argument_ = 1;
  has_prefix_ = false;
  raw_prefix_ = false;
}

[[nodiscard]] const KeySequence &
CommandDispatcher::pending_keys () const noexcept
{
  return pending_keys_;
}

void
CommandDispatcher::reset_key_sequence () noexcept
{
  pending_keys_.clear ();
}

void
CommandDispatcher::set_pre_command_hook (PreCommandHook hook)
{
  pre_command_hook_ = std::move (hook);
}

void
CommandDispatcher::set_post_command_hook (PostCommandHook hook)
{
  post_command_hook_ = std::move (hook);
}

[[nodiscard]] const gc_string &
CommandDispatcher::message () const noexcept
{
  return message_;
}

void
CommandDispatcher::clear_message () noexcept
{
  message_.clear ();
}

[[nodiscard]] uint32_t
CommandDispatcher::last_inserted_char () const noexcept
{
  return last_char_;
}

void
CommandDispatcher::reset () noexcept
{
  reset_key_sequence ();
  clear_message ();
  clear_prefix_argument ();
  last_char_ = 0;
  current_buffer_ = nullptr;
}

[[nodiscard]] KeyStroke
CommandDispatcher::key_event_to_keystroke (
  const tui::KeyEvent &ke) const noexcept
{
  KeyStroke ks;
  ks.key = ke.key;
  ks.modifiers = ke.modifiers;
  ks.unicode = ke.unicode;
  return ks;
}

[[nodiscard]] bool
CommandDispatcher::try_self_insert (const tui::KeyEvent &ke,
				    EmacsBuffer *buffer)
{
  if (ke.unicode == 0)
    return false;

  last_char_ = ke.unicode;

  if (CommandRegistry::instance ().has_command (
	"self-insert-command"))
    return execute_command ("self-insert-command", buffer);

  if (!buffer)
    return false;
  if (ke.unicode > 0x7f)
    return false;

  buffer->insert_char (static_cast<char> (ke.unicode));
  clear_prefix_argument ();
  return true;
}

[[nodiscard]] bool
CommandDispatcher::execute_command (std::string_view name,
				    EmacsBuffer *buffer)
{
  if (pre_command_hook_)
    pre_command_hook_ (name);

  CommandContext ctx;
  ctx.buffer = buffer;
  ctx.prefix_argument = prefix_argument_;
  ctx.has_prefix = has_prefix_;
  ctx.raw_prefix = raw_prefix_;

  bool ok = CommandRegistry::instance ().execute (name, ctx);

  if (post_command_hook_)
    post_command_hook_ (name);

  clear_prefix_argument ();
  return ok;
}

void
CommandDispatcher::update_message ()
{
  message_.clear ();
  for (const auto &ks : pending_keys_)
    {
      append_keystroke (message_, ks);
      message_.push_back (' ');
    }
}

} // namespace emacs

extern "C"
{
  int emacs_cxx_dispatch_key (int key_code, int modifiers,
			      unsigned int unicode, void *buffer_ptr)
  {
    try
      {
	const auto key = static_cast<emacs::tui::KeyCode> (key_code);
	const auto mods
	  = static_cast<emacs::tui::KeyModifier> (modifiers);
	emacs::tui::KeyEvent ke (key, mods, unicode);
	emacs::tui::InputEvent ev
	  = emacs::tui::InputEvent::make_key (ke);

	emacs::EmacsBuffer *buffer
	  = static_cast<emacs::EmacsBuffer *> (buffer_ptr);
	emacs::DispatchResult result
	  = emacs::CommandDispatcher::instance ().dispatch (ev,
							    buffer);
	return static_cast<int> (result);
      }
    catch (...)
      {
	return -1;
      }
  }

  void emacs_cxx_dispatch_reset ()
  {
    try
      {
	emacs::CommandDispatcher::instance ().reset ();
      }
    catch (...)
      {
      }
  }
}
