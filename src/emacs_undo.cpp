// src/emacs_undo.cpp
// Undo/redo manager for EmacsBuffer edits

#include "emacs_undo.hpp"

#include <cassert>

namespace emacs
{

UndoRecord::UndoRecord (UndoRecordType t, ptrdiff_t pos,
			std::string_view txt, ptrdiff_t pt)
    : type (t), position (pos), text (txt.begin (), txt.end ()),
      old_point (pt)
{
}

bool
UndoGroup::empty () const noexcept
{
  return records.empty ();
}

UndoManager::UndoManager ()
    : undo_stack_ (), redo_stack_ (), current_group_ (),
      recording_ (false), enabled_ (true), max_undo_ (0),
      prepared_undo_ (), prepared_redo_ ()
{
}

void
UndoManager::begin_group ()
{
  if (!enabled_)
    {
      return;
    }

  if (recording_)
    {
      return;
    }

  recording_ = true;
  current_group_.records.clear ();
}

void
UndoManager::end_group ()
{
  if (!enabled_)
    {
      recording_ = false;
      current_group_.records.clear ();
      return;
    }

  if (!recording_)
    {
      return;
    }

  recording_ = false;

  if (current_group_.empty ())
    {
      return;
    }

  push_undo_group (std::move (current_group_));
  current_group_.records.clear ();
}

void
UndoManager::record_insert (ptrdiff_t pos, std::string_view text,
			    ptrdiff_t old_point)
{
  if (!enabled_ || text.empty ())
    {
      return;
    }

  if (!recording_)
    {
      begin_group ();
      current_group_.records.emplace_back (UndoRecordType::INSERT,
					   pos, text, old_point);
      end_group ();
      return;
    }

  current_group_.records.emplace_back (UndoRecordType::INSERT, pos,
				       text, old_point);
  redo_stack_.clear ();
}

void
UndoManager::record_delete (ptrdiff_t pos, std::string_view text,
			    ptrdiff_t old_point)
{
  if (!enabled_ || text.empty ())
    {
      return;
    }

  if (!recording_)
    {
      begin_group ();
      current_group_.records.emplace_back (UndoRecordType::DELETE,
					   pos, text, old_point);
      end_group ();
      return;
    }

  current_group_.records.emplace_back (UndoRecordType::DELETE, pos,
				       text, old_point);
  redo_stack_.clear ();
}

bool
UndoManager::can_undo () const noexcept
{
  return !undo_stack_.empty ();
}

bool
UndoManager::can_redo () const noexcept
{
  return !redo_stack_.empty ();
}

size_t
UndoManager::undo_count () const noexcept
{
  return undo_stack_.size ();
}

size_t
UndoManager::redo_count () const noexcept
{
  return redo_stack_.size ();
}

const UndoGroup &
UndoManager::prepare_undo ()
{
  assert (!undo_stack_.empty ());
  prepared_undo_ = undo_stack_.back ();
  if (prepared_undo_.records.size () > 1)
    {
      size_t left = 0;
      size_t right = prepared_undo_.records.size () - 1;
      while (left < right)
	{
	  UndoRecord temp = std::move (prepared_undo_.records[left]);
	  prepared_undo_.records[left]
	    = std::move (prepared_undo_.records[right]);
	  prepared_undo_.records[right] = std::move (temp);
	  ++left;
	  --right;
	}
    }
  return prepared_undo_;
}

void
UndoManager::commit_undo ()
{
  if (undo_stack_.empty ())
    {
      return;
    }

  redo_stack_.push_back (std::move (undo_stack_.back ()));
  undo_stack_.pop_back ();
}

const UndoGroup &
UndoManager::prepare_redo ()
{
  assert (!redo_stack_.empty ());
  prepared_redo_ = redo_stack_.back ();
  return prepared_redo_;
}

void
UndoManager::commit_redo ()
{
  if (redo_stack_.empty ())
    {
      return;
    }

  undo_stack_.push_back (std::move (redo_stack_.back ()));
  redo_stack_.pop_back ();
}

void
UndoManager::clear () noexcept
{
  undo_stack_.clear ();
  redo_stack_.clear ();
  current_group_.records.clear ();
  recording_ = false;
}

size_t
UndoManager::max_undo_count () const noexcept
{
  return max_undo_;
}

void
UndoManager::set_max_undo_count (size_t max) noexcept
{
  max_undo_ = max;
  trim_undo_stack ();
}

bool
UndoManager::is_recording () const noexcept
{
  return recording_;
}

bool
UndoManager::is_enabled () const noexcept
{
  return enabled_;
}

void
UndoManager::set_enabled (bool enabled) noexcept
{
  enabled_ = enabled;
}

void
UndoManager::push_undo_group (UndoGroup &&group)
{
  if (group.empty ())
    {
      return;
    }

  undo_stack_.push_back (std::move (group));
  redo_stack_.clear ();
  trim_undo_stack ();
}

void
UndoManager::trim_undo_stack ()
{
  if (max_undo_ == 0)
    {
      return;
    }

  while (undo_stack_.size () > max_undo_)
    {
      undo_stack_.erase (undo_stack_.begin ());
    }
}

} // namespace emacs
