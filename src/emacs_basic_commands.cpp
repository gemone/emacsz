#include <algorithm>
#include <cstddef>

#include "emacs_basic_commands.hpp"

#include "containers.hpp"
#include "emacs_buffer.hpp"
#include "emacs_command_dispatcher.hpp"
#include "emacs_command_registry.hpp"
#include "emacs_undo.hpp"

namespace emacs
{

namespace
{

[[nodiscard]] int
effective_prefix (const CommandContext &ctx) noexcept
{
  if (!ctx.has_prefix)
    {
      return 1;
    }
  return ctx.prefix_argument == 0 ? 1 : ctx.prefix_argument;
}

[[nodiscard]] ptrdiff_t
clamp_point (const EmacsBuffer &buffer, ptrdiff_t pos) noexcept
{
  if (pos < buffer.point_min ())
    {
      return buffer.point_min ();
    }
  if (pos > buffer.point_max ())
    {
      return buffer.point_max ();
    }
  return pos;
}

[[nodiscard]] UndoManager &
undo_manager_for (EmacsBuffer *buffer)
{
  static gc_unordered_map<EmacsBuffer *, UndoManager> managers;
  auto it = managers.find (buffer);
  if (it == managers.end ())
    {
      it = managers.emplace (buffer, UndoManager ()).first;
    }
  return it->second;
}

void
record_insert (EmacsBuffer &buffer, std::string_view text,
	       ptrdiff_t old_point)
{
  if (text.empty ())
    {
      return;
    }
  UndoManager &manager = undo_manager_for (&buffer);
  manager.record_insert (buffer.point (), text, old_point);
}

void
record_delete (EmacsBuffer &buffer, std::string_view text,
	       ptrdiff_t delete_pos, ptrdiff_t old_point)
{
  if (text.empty ())
    {
      return;
    }
  UndoManager &manager = undo_manager_for (&buffer);
  manager.record_delete (delete_pos, text, old_point);
}

[[nodiscard]] ptrdiff_t
find_line_start (const EmacsBuffer &buffer, ptrdiff_t pos)
{
  if (pos <= buffer.point_min ())
    {
      return buffer.point_min ();
    }

  auto raw = buffer.content ();
  gc_string content (raw.begin (), raw.end ());
  if (content.empty ())
    {
      return buffer.point_min ();
    }

  ptrdiff_t index = pos - 2;
  while (index >= 0)
    {
      if (content[static_cast<size_t> (index)] == '\n')
	{
	  return index + 2;
	}
      --index;
    }

  return buffer.point_min ();
}

[[nodiscard]] ptrdiff_t
find_line_end (const EmacsBuffer &buffer, ptrdiff_t pos)
{
  auto raw = buffer.content ();
  gc_string content (raw.begin (), raw.end ());
  if (content.empty ())
    {
      return buffer.point_max ();
    }

  ptrdiff_t size = static_cast<ptrdiff_t> (content.size ());
  ptrdiff_t index = pos - 1;
  while (index < size)
    {
      if (content[static_cast<size_t> (index)] == '\n')
	{
	  return index + 1;
	}
      ++index;
    }

  return buffer.point_max ();
}

[[nodiscard]] ptrdiff_t
line_column (const EmacsBuffer &buffer, ptrdiff_t pos)
{
  ptrdiff_t start = find_line_start (buffer, pos);
  if (pos < start)
    {
      return 0;
    }
  return pos - start;
}

[[nodiscard]] ptrdiff_t
move_to_line (const EmacsBuffer &buffer, ptrdiff_t pos, int lines)
{
  if (lines == 0)
    {
      return clamp_point (buffer, pos);
    }

  auto raw = buffer.content ();
  gc_string content (raw.begin (), raw.end ());
  ptrdiff_t size = static_cast<ptrdiff_t> (content.size ());
  if (size == 0)
    {
      return buffer.point_min ();
    }

  ptrdiff_t target_col = line_column (buffer, pos);
  ptrdiff_t line_start = find_line_start (buffer, pos);
  ptrdiff_t cursor = line_start - 1;
  int remaining = lines;

  if (remaining > 0)
    {
      while (remaining > 0 && cursor < size)
	{
	  size_t idx = static_cast<size_t> (cursor);
	  if (content[idx] == '\n')
	    {
	      --remaining;
	      if (remaining == 0)
		{
		  ++cursor;
		  break;
		}
	    }
	  ++cursor;
	}
    }
  else
    {
      while (remaining < 0 && cursor > 0)
	{
	  --cursor;
	  size_t idx = static_cast<size_t> (cursor);
	  if (content[idx] == '\n')
	    {
	      ++remaining;
	      if (remaining == 0)
		{
		  ++cursor;
		  break;
		}
	    }
	}
    }

  if (remaining != 0)
    {
      return clamp_point (buffer, pos);
    }

  ptrdiff_t target_start = cursor + 1;
  if (target_start < buffer.point_min ())
    {
      target_start = buffer.point_min ();
    }

  ptrdiff_t target_end = find_line_end (buffer, target_start);
  ptrdiff_t target_len = target_end - target_start;
  ptrdiff_t new_pos
    = target_start + std::min (target_col, target_len);
  return clamp_point (buffer, new_pos);
}

} // namespace

void
cmd_self_insert (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  uint32_t last
    = CommandDispatcher::instance ().last_inserted_char ();
  if (last > 0x7f)
    {
      return;
    }
  char c = static_cast<char> (last);

  int count = effective_prefix (ctx);
  if (count < 0)
    {
      count = 0;
    }
  if (count == 0)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  gc_string text (static_cast<size_t> (count), c);
  record_insert (buffer, text, buffer.point ());

  for (int i = 0; i < count; ++i)
    {
      buffer.insert_char (c);
    }
}

void
cmd_forward_char (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  int count = effective_prefix (ctx);
  ptrdiff_t pos = ctx.buffer->point () + count;
  ctx.buffer->set_point (clamp_point (*ctx.buffer, pos));
}

void
cmd_backward_char (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  int count = effective_prefix (ctx);
  ptrdiff_t pos = ctx.buffer->point () - count;
  ctx.buffer->set_point (clamp_point (*ctx.buffer, pos));
}

void
cmd_beginning_of_line (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  ptrdiff_t pos = ctx.buffer->point ();
  ptrdiff_t start = find_line_start (*ctx.buffer, pos);
  ctx.buffer->set_point (start);
}

void
cmd_end_of_line (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  ptrdiff_t pos = ctx.buffer->point ();
  ptrdiff_t end = find_line_end (*ctx.buffer, pos);
  ctx.buffer->set_point (end);
}

void
cmd_delete_char (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  ptrdiff_t count = effective_prefix (ctx);
  if (count <= 0)
    {
      return;
    }
  ptrdiff_t start = buffer.point ();
  ptrdiff_t end = std::min (start + count, buffer.point_max ());
  if (end > start)
    {
      auto raw = buffer.content_range (start, end);
      gc_string text (raw.begin (), raw.end ());
      record_delete (buffer, text, start, buffer.point ());
    }
  buffer.delete_forward (count);
}

void
cmd_backward_delete_char (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  ptrdiff_t count = effective_prefix (ctx);
  if (count <= 0)
    {
      return;
    }
  ptrdiff_t end = buffer.point ();
  ptrdiff_t start = std::max (buffer.point_min (), end - count);
  if (end > start)
    {
      auto raw = buffer.content_range (start, end);
      gc_string text (raw.begin (), raw.end ());
      record_delete (buffer, text, start, buffer.point ());
    }
  buffer.delete_backward (count);
}

void
cmd_newline (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  record_insert (buffer, "\n", buffer.point ());
  buffer.insert_char ('\n');
}

void
cmd_kill_line (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  auto raw = buffer.content ();
  gc_string content (raw.begin (), raw.end ());
  if (content.empty ())
    {
      return;
    }

  ptrdiff_t pos = buffer.point ();
  ptrdiff_t size = static_cast<ptrdiff_t> (content.size ());
  if (pos > size)
    {
      return;
    }

  ptrdiff_t index = pos - 1;
  if (index >= 0 && index < size
      && content[static_cast<size_t> (index)] == '\n')
    {
      record_delete (buffer, "\n", pos, buffer.point ());
      buffer.delete_forward (1);
      return;
    }

  ptrdiff_t end = find_line_end (buffer, pos);
  ptrdiff_t count = end - pos;
  if (count <= 0)
    {
      return;
    }
  auto raw_range = buffer.content_range (pos, end);
  gc_string text (raw_range.begin (), raw_range.end ());
  record_delete (buffer, text, pos, buffer.point ());
  buffer.delete_forward (count);
}

void
cmd_undo (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  UndoManager &manager = undo_manager_for (&buffer);
  if (!manager.can_undo ())
    {
      return;
    }

  const UndoGroup &group = manager.prepare_undo ();
  for (const auto &record : group.records)
    {
      if (record.type == UndoRecordType::INSERT)
	{
	  buffer.set_point (record.position);
	  buffer.delete_forward (
	    static_cast<ptrdiff_t> (record.text.size ()));
	}
      else
	{
	  buffer.set_point (record.position);
	  buffer.insert_string (record.text);
	}
      buffer.set_point (record.old_point);
    }

  manager.commit_undo ();
}

void
cmd_redo (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  EmacsBuffer &buffer = *ctx.buffer;
  UndoManager &manager = undo_manager_for (&buffer);
  if (!manager.can_redo ())
    {
      return;
    }

  const UndoGroup &group = manager.prepare_redo ();
  for (const auto &record : group.records)
    {
      if (record.type == UndoRecordType::INSERT)
	{
	  buffer.set_point (record.position);
	  buffer.insert_string (record.text);
	}
      else
	{
	  buffer.set_point (record.position);
	  buffer.delete_forward (
	    static_cast<ptrdiff_t> (record.text.size ()));
	}
      buffer.set_point (record.old_point);
    }

  manager.commit_redo ();
}

void
cmd_beginning_of_buffer (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }
  ctx.buffer->set_point (ctx.buffer->point_min ());
}

void
cmd_end_of_buffer (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }
  ctx.buffer->set_point (ctx.buffer->point_max ());
}

void
cmd_next_line (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  int count = effective_prefix (ctx);
  ptrdiff_t pos = ctx.buffer->point ();
  ptrdiff_t next = move_to_line (*ctx.buffer, pos, count);
  ctx.buffer->set_point (next);
}

void
cmd_previous_line (CommandContext &ctx)
{
  if (!ctx.buffer)
    {
      return;
    }

  int count = effective_prefix (ctx);
  ptrdiff_t pos = ctx.buffer->point ();
  ptrdiff_t prev = move_to_line (*ctx.buffer, pos, -count);
  ctx.buffer->set_point (prev);
}

void
register_basic_commands ()
{
  auto &reg = CommandRegistry::instance ();
  reg.register_command ("self-insert-command", cmd_self_insert,
			"Insert the character you type.", "p");
  reg.register_command ("forward-char", cmd_forward_char,
			"Move point forward N chars.", "p");
  reg.register_command ("backward-char", cmd_backward_char,
			"Move point backward N chars.", "p");
  reg.register_command ("beginning-of-line", cmd_beginning_of_line,
			"Move to beginning of line.", "");
  reg.register_command ("end-of-line", cmd_end_of_line,
			"Move to end of line.", "");
  reg.register_command ("delete-char", cmd_delete_char,
			"Delete N chars after point.", "p");
  reg.register_command ("backward-delete-char",
			cmd_backward_delete_char,
			"Delete N chars before point.", "p");
  reg.register_command ("newline", cmd_newline, "Insert a newline.",
			"");
  reg.register_command ("kill-line", cmd_kill_line,
			"Kill to end of line.", "");
  reg.register_command ("undo", cmd_undo, "Undo last change.", "");
  reg.register_command ("redo", cmd_redo, "Redo last undo.", "");
  reg.register_command ("beginning-of-buffer",
			cmd_beginning_of_buffer,
			"Move to beginning of buffer.", "");
  reg.register_command ("end-of-buffer", cmd_end_of_buffer,
			"Move to end of buffer.", "");
  reg.register_command ("next-line", cmd_next_line,
			"Move to next line.", "p");
  reg.register_command ("previous-line", cmd_previous_line,
			"Move to previous line.", "p");
}

} // namespace emacs
