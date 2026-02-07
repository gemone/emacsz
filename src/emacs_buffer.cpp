// src/emacs_buffer.cpp
// Emacs buffer object and marker system implementation

#include "emacs_buffer.hpp"
#include <algorithm>
#include <cassert>

namespace emacs
{

Marker::Marker (EmacsBuffer *buffer, ptrdiff_t pos,
		MarkerInsertionType type)
    : buffer_ (buffer), position_ (pos), insertion_type_ (type)
{
  if (buffer_)
    {
      buffer_->register_marker (this);
    }
}

Marker::~Marker ()
{
  if (buffer_)
    {
      buffer_->unregister_marker (this);
    }
  buffer_ = nullptr;
}

ptrdiff_t
Marker::position () const noexcept
{
  return position_;
}

void
Marker::set_position (ptrdiff_t pos)
{
  position_ = pos;
}

EmacsBuffer *
Marker::buffer () const noexcept
{
  return buffer_;
}

MarkerInsertionType
Marker::insertion_type () const noexcept
{
  return insertion_type_;
}

void
Marker::set_insertion_type (MarkerInsertionType type) noexcept
{
  insertion_type_ = type;
}

EmacsBuffer::EmacsBuffer (std::string_view name)
    : name_ (name.begin (), name.end ()), text_ (), modified_ (false),
      markers_ (), mark_ (0), mark_active_ (false), narrow_beg_ (0),
      narrow_end_ (0), undo_manager_ (),
      inhibit_undo_recording_ (false), self_insert_count_ (0),
      self_insert_pos_ (0), self_insert_text_ ()
{
}

EmacsBuffer::EmacsBuffer (std::string_view name,
			  std::string_view initial_text)
    : name_ (name.begin (), name.end ()), text_ (initial_text),
      modified_ (false), markers_ (), mark_ (0), mark_active_ (false),
      narrow_beg_ (0), narrow_end_ (0), undo_manager_ (),
      inhibit_undo_recording_ (false), self_insert_count_ (0),
      self_insert_pos_ (0), self_insert_text_ ()
{
}

EmacsBuffer::~EmacsBuffer ()
{
  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = nullptr;
	}
    }
  markers_.clear ();
}

EmacsBuffer::EmacsBuffer (EmacsBuffer &&other) noexcept
    : name_ (std::move (other.name_)),
      text_ (std::move (other.text_)), modified_ (other.modified_),
      markers_ (std::move (other.markers_)), mark_ (other.mark_),
      mark_active_ (other.mark_active_),
      narrow_beg_ (other.narrow_beg_),
      narrow_end_ (other.narrow_end_),
      undo_manager_ (std::move (other.undo_manager_)),
      inhibit_undo_recording_ (other.inhibit_undo_recording_),
      self_insert_count_ (other.self_insert_count_),
      self_insert_pos_ (other.self_insert_pos_),
      self_insert_text_ (std::move (other.self_insert_text_))
{
  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = this;
	}
    }
  other.markers_.clear ();
  other.mark_ = 0;
  other.mark_active_ = false;
  other.narrow_beg_ = 0;
  other.narrow_end_ = 0;
  other.inhibit_undo_recording_ = false;
  other.self_insert_count_ = 0;
  other.self_insert_pos_ = 0;
  other.self_insert_text_.clear ();
}

EmacsBuffer &
EmacsBuffer::operator= (EmacsBuffer &&other) noexcept
{
  if (this == &other)
    {
      return *this;
    }

  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = nullptr;
	}
    }
  markers_.clear ();

  name_ = std::move (other.name_);
  text_ = std::move (other.text_);
  modified_ = other.modified_;
  markers_ = std::move (other.markers_);
  mark_ = other.mark_;
  mark_active_ = other.mark_active_;
  narrow_beg_ = other.narrow_beg_;
  narrow_end_ = other.narrow_end_;
  undo_manager_ = std::move (other.undo_manager_);
  inhibit_undo_recording_ = other.inhibit_undo_recording_;
  self_insert_count_ = other.self_insert_count_;
  self_insert_pos_ = other.self_insert_pos_;
  self_insert_text_ = std::move (other.self_insert_text_);

  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = this;
	}
    }
  other.markers_.clear ();
  other.mark_ = 0;
  other.mark_active_ = false;
  other.narrow_beg_ = 0;
  other.narrow_end_ = 0;
  other.inhibit_undo_recording_ = false;
  other.self_insert_count_ = 0;
  other.self_insert_pos_ = 0;
  other.self_insert_text_.clear ();

  return *this;
}

const gc_string &
EmacsBuffer::name () const noexcept
{
  return name_;
}

void
EmacsBuffer::set_name (std::string_view name)
{
  name_.assign (name.begin (), name.end ());
}

ptrdiff_t
EmacsBuffer::size () const noexcept
{
  return text_.size ();
}

bool
EmacsBuffer::empty () const noexcept
{
  return text_.empty ();
}

ptrdiff_t
EmacsBuffer::point () const noexcept
{
  return text_.point ();
}

void
EmacsBuffer::set_point (ptrdiff_t pos)
{
  ptrdiff_t min = point_min ();
  ptrdiff_t max = point_max ();
  if (pos < min)
    {
      pos = min;
    }
  else if (pos > max)
    {
      pos = max;
    }
  text_.set_point (pos);
}

ptrdiff_t
EmacsBuffer::point_min () const noexcept
{
  if (narrow_beg_ != 0)
    {
      return narrow_beg_;
    }
  return text_.point_min ();
}

ptrdiff_t
EmacsBuffer::point_max () const noexcept
{
  if (narrow_end_ != 0)
    {
      return narrow_end_;
    }
  return text_.point_max ();
}

bool
EmacsBuffer::has_mark () const noexcept
{
  return mark_ != 0;
}

ptrdiff_t
EmacsBuffer::mark () const noexcept
{
  return mark_;
}

void
EmacsBuffer::set_mark (ptrdiff_t pos)
{
  if (pos < 1)
    {
      pos = 1;
    }
  if (pos > text_.point_max ())
    {
      pos = text_.point_max ();
    }
  mark_ = pos;
  mark_active_ = true;
}

void
EmacsBuffer::deactivate_mark () noexcept
{
  mark_active_ = false;
}

bool
EmacsBuffer::mark_active () const noexcept
{
  return mark_active_;
}

void
EmacsBuffer::exchange_point_and_mark ()
{
  if (mark_ == 0)
    {
      return;
    }
  ptrdiff_t current_point = point ();
  set_point (mark_);
  mark_ = current_point;
}

ptrdiff_t
EmacsBuffer::region_beginning () const noexcept
{
  if (mark_ == 0)
    {
      return point ();
    }
  return std::min (point (), mark_);
}

ptrdiff_t
EmacsBuffer::region_end () const noexcept
{
  if (mark_ == 0)
    {
      return point ();
    }
  return std::max (point (), mark_);
}

char
EmacsBuffer::char_at (ptrdiff_t pos) const
{
  return text_.char_at (pos);
}

std::string
EmacsBuffer::content () const
{
  return text_.content ();
}

std::string
EmacsBuffer::content_range (ptrdiff_t from, ptrdiff_t to) const
{
  return text_.content_range (from, to);
}

void
EmacsBuffer::insert_char (char c)
{
  ptrdiff_t insert_pos = text_.point ();
  if (is_narrowed ())
    {
      ptrdiff_t min = point_min ();
      ptrdiff_t max = point_max ();
      if (insert_pos < min)
	{
	  insert_pos = min;
	  text_.set_point (insert_pos);
	}
      else if (insert_pos > max)
	{
	  insert_pos = max;
	  text_.set_point (insert_pos);
	}
    }
  text_.insert_char (c);
  adjust_markers_for_insert (insert_pos, 1);
  if (narrow_end_ != 0)
    {
      narrow_end_ += 1;
    }
  if (!inhibit_undo_recording_)
    {
      bool continue_group
	= self_insert_count_ > 0 && self_insert_count_ < 20
	  && insert_pos
	       == self_insert_pos_
		    + static_cast<ptrdiff_t> (self_insert_count_);
      if (!continue_group)
	{
	  flush_self_insert_group ();
	  self_insert_pos_ = insert_pos;
	  self_insert_count_ = 0;
	  self_insert_text_.clear ();
	  undo_manager_.begin_group ();
	}
      self_insert_text_.push_back (c);
      ++self_insert_count_;
      undo_manager_.record_insert (insert_pos,
				   std::string_view (&c, 1),
				   insert_pos);
      if (self_insert_count_ >= 20)
	{
	  flush_self_insert_group ();
	}
    }
  else
    {
      flush_self_insert_group ();
    }
  modified_ = true;
}

void
EmacsBuffer::insert_string (std::string_view text)
{
  if (text.empty ())
    {
      return;
    }

  if (!inhibit_undo_recording_)
    {
      flush_self_insert_group ();
    }

  ptrdiff_t insert_pos = text_.point ();
  if (is_narrowed ())
    {
      ptrdiff_t min = point_min ();
      ptrdiff_t max = point_max ();
      if (insert_pos < min)
	{
	  insert_pos = min;
	  text_.set_point (insert_pos);
	}
      else if (insert_pos > max)
	{
	  insert_pos = max;
	  text_.set_point (insert_pos);
	}
    }
  text_.insert_string (text);
  adjust_markers_for_insert (insert_pos,
			     static_cast<ptrdiff_t> (text.size ()));
  if (narrow_end_ != 0)
    {
      narrow_end_ += static_cast<ptrdiff_t> (text.size ());
    }
  if (!inhibit_undo_recording_)
    {
      undo_manager_.record_insert (insert_pos, text, insert_pos);
    }
  modified_ = true;
}

void
EmacsBuffer::delete_forward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  if (!inhibit_undo_recording_)
    {
      flush_self_insert_group ();
    }

  ptrdiff_t before_size = text_.size ();
  ptrdiff_t delete_pos = text_.point ();
  if (is_narrowed ())
    {
      if (delete_pos < point_min ())
	{
	  delete_pos = point_min ();
	  text_.set_point (delete_pos);
	}
      ptrdiff_t max_delete = point_max () - delete_pos;
      if (max_delete <= 0)
	{
	  return;
	}
      if (n > max_delete)
	{
	  n = max_delete;
	}
    }
  std::string deleted_text;
  if (!inhibit_undo_recording_)
    {
      deleted_text = content_range (delete_pos, delete_pos + n);
    }
  text_.delete_forward (n);
  ptrdiff_t after_size = text_.size ();

  if (after_size == before_size)
    {
      return;
    }

  ptrdiff_t deleted = before_size - after_size;
  adjust_markers_for_delete (delete_pos, deleted);
  if (narrow_end_ != 0)
    {
      narrow_end_ -= deleted;
      if (narrow_end_ < narrow_beg_)
	{
	  narrow_end_ = narrow_beg_;
	}
    }
  if (!inhibit_undo_recording_)
    {
      undo_manager_.record_delete (delete_pos, deleted_text,
				   delete_pos);
    }
  modified_ = true;
}

void
EmacsBuffer::delete_backward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  if (!inhibit_undo_recording_)
    {
      flush_self_insert_group ();
    }

  ptrdiff_t before_size = text_.size ();
  ptrdiff_t before_point = text_.point ();
  if (is_narrowed ())
    {
      if (before_point > point_max ())
	{
	  before_point = point_max ();
	  text_.set_point (before_point);
	}
      ptrdiff_t min_delete = point_min ();
      ptrdiff_t available = before_point - min_delete;
      if (available <= 0)
	{
	  return;
	}
      if (n > available)
	{
	  n = available;
	}
    }
  ptrdiff_t delete_pos = before_point - n;
  std::string deleted_text;
  if (!inhibit_undo_recording_)
    {
      deleted_text = content_range (delete_pos, delete_pos + n);
    }
  text_.delete_backward (n);
  ptrdiff_t after_size = text_.size ();

  if (after_size == before_size)
    {
      return;
    }

  ptrdiff_t deleted = before_size - after_size;
  delete_pos = before_point - deleted;
  adjust_markers_for_delete (delete_pos, deleted);
  if (narrow_end_ != 0)
    {
      narrow_end_ -= deleted;
      if (narrow_end_ < narrow_beg_)
	{
	  narrow_end_ = narrow_beg_;
	}
    }
  if (!inhibit_undo_recording_)
    {
      undo_manager_.record_delete (delete_pos, deleted_text,
				   delete_pos);
    }
  modified_ = true;
}

void
EmacsBuffer::undo ()
{
  if (undo_manager_.is_recording ())
    {
      flush_self_insert_group ();
    }
  if (!undo_manager_.can_undo ())
    {
      return;
    }

  const UndoGroup &group = undo_manager_.prepare_undo ();
  inhibit_undo_recording_ = true;
  flush_self_insert_group ();
  for (const UndoRecord &record : group.records)
    {
      if (record.type == UndoRecordType::INSERT)
	{
	  text_.set_point (record.position);
	  delete_forward (
	    static_cast<ptrdiff_t> (record.text.size ()));
	}
      else
	{
	  text_.set_point (record.position);
	  insert_string (record.text);
	}
    }
  inhibit_undo_recording_ = false;
  if (!group.records.empty ())
    {
      text_.set_point (group.records.back ().old_point);
    }
  undo_manager_.commit_undo ();
}

void
EmacsBuffer::redo ()
{
  if (undo_manager_.is_recording ())
    {
      flush_self_insert_group ();
    }
  if (!undo_manager_.can_redo ())
    {
      return;
    }

  const UndoGroup &group = undo_manager_.prepare_redo ();
  inhibit_undo_recording_ = true;
  flush_self_insert_group ();
  for (const UndoRecord &record : group.records)
    {
      if (record.type == UndoRecordType::INSERT)
	{
	  text_.set_point (record.position);
	  insert_string (record.text);
	}
      else
	{
	  text_.set_point (record.position);
	  delete_forward (
	    static_cast<ptrdiff_t> (record.text.size ()));
	}
    }
  inhibit_undo_recording_ = false;
  if (!group.records.empty ())
    {
      text_.set_point (group.records.back ().old_point);
    }
  undo_manager_.commit_redo ();
}

bool
EmacsBuffer::is_modified () const noexcept
{
  return modified_;
}

void
EmacsBuffer::set_modified (bool modified) noexcept
{
  modified_ = modified;
}

void
EmacsBuffer::narrow_to_region (ptrdiff_t beg, ptrdiff_t end)
{
  if (beg < 1)
    {
      beg = 1;
    }
  ptrdiff_t max = text_.point_max ();
  if (end > max)
    {
      end = max;
    }
  if (end < beg)
    {
      end = beg;
    }
  narrow_beg_ = beg;
  narrow_end_ = end;
  set_point (text_.point ());
}

void
EmacsBuffer::widen () noexcept
{
  narrow_beg_ = 0;
  narrow_end_ = 0;
}

bool
EmacsBuffer::is_narrowed () const noexcept
{
  return narrow_beg_ != 0 || narrow_end_ != 0;
}

void
EmacsBuffer::register_marker (Marker *marker)
{
  if (!marker)
    {
      return;
    }

  auto it = std::find (markers_.begin (), markers_.end (), marker);
  if (it != markers_.end ())
    {
      return;
    }

  marker->buffer_ = this;
  markers_.push_back (marker);
}

void
EmacsBuffer::unregister_marker (Marker *marker)
{
  if (!marker)
    {
      return;
    }

  auto it = std::find (markers_.begin (), markers_.end (), marker);
  if (it == markers_.end ())
    {
      return;
    }

  markers_.erase (it);
  marker->buffer_ = nullptr;
}

size_t
EmacsBuffer::marker_count () const noexcept
{
  return markers_.size ();
}

const GapBuffer &
EmacsBuffer::gap_buffer () const noexcept
{
  return text_;
}

GapBuffer &
EmacsBuffer::gap_buffer () noexcept
{
  return text_;
}

UndoManager &
EmacsBuffer::undo_manager () noexcept
{
  return undo_manager_;
}

const UndoManager &
EmacsBuffer::undo_manager () const noexcept
{
  return undo_manager_;
}

void
EmacsBuffer::adjust_markers_for_insert (ptrdiff_t pos,
					ptrdiff_t length)
{
  if (length <= 0)
    {
      return;
    }

  for (Marker *marker : markers_)
    {
      if (!marker)
	{
	  continue;
	}

      if (marker->position_ > pos)
	{
	  marker->position_ += length;
	  continue;
	}

      if (marker->position_ == pos
	  && marker->insertion_type_
	       == MarkerInsertionType::AFTER_INSERTION)
	{
	  marker->position_ += length;
	}
    }

  if (mark_ > pos)
    {
      mark_ += length;
    }
}

void
EmacsBuffer::adjust_markers_for_delete (ptrdiff_t pos,
					ptrdiff_t length)
{
  if (length <= 0)
    {
      return;
    }

  ptrdiff_t end = pos + length;

  for (Marker *marker : markers_)
    {
      if (!marker)
	{
	  continue;
	}

      if (marker->position_ >= end)
	{
	  marker->position_ -= length;
	  continue;
	}

      if (marker->position_ > pos && marker->position_ < end)
	{
	  marker->position_ = pos;
	}
    }

  if (mark_ >= end)
    {
      mark_ -= length;
    }
  else if (mark_ > pos && mark_ < end)
    {
      mark_ = pos;
    }
}

void
EmacsBuffer::flush_self_insert_group ()
{
  if (self_insert_count_ == 0)
    {
      return;
    }
  if (undo_manager_.is_recording ())
    {
      undo_manager_.end_group ();
    }
  self_insert_count_ = 0;
  self_insert_pos_ = 0;
  self_insert_text_.clear ();
}

} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_buffer (const char *name)
  {
    const char *safe_name = name ? name : "";
    return new emacs::EmacsBuffer (safe_name);
  }

  void *emacs_cxx_create_buffer_with_text (const char *name,
					   const char *text)
  {
    const char *safe_name = name ? name : "";
    const char *safe_text = text ? text : "";
    return new emacs::EmacsBuffer (safe_name, safe_text);
  }

  void emacs_cxx_destroy_buffer (void *buf)
  {
    delete static_cast<emacs::EmacsBuffer *> (buf);
  }

  ptrdiff_t emacs_cxx_buffer_size (void *buf)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    return buffer ? buffer->size () : 0;
  }

  ptrdiff_t emacs_cxx_buffer_point (void *buf)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    return buffer ? buffer->point () : 1;
  }

  void emacs_cxx_buffer_set_point (void *buf, ptrdiff_t pos)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    if (!buffer)
      {
	return;
      }
    buffer->set_point (pos);
  }

  void emacs_cxx_buffer_insert_char (void *buf, char c)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    if (!buffer)
      {
	return;
      }
    buffer->insert_char (c);
  }

  void emacs_cxx_buffer_insert_string (void *buf, const char *text)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    if (!buffer)
      {
	return;
      }
    const char *safe_text = text ? text : "";
    buffer->insert_string (safe_text);
  }

  void emacs_cxx_buffer_delete_forward (void *buf, ptrdiff_t n)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    if (!buffer)
      {
	return;
      }
    buffer->delete_forward (n);
  }

  void emacs_cxx_buffer_delete_backward (void *buf, ptrdiff_t n)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    if (!buffer)
      {
	return;
      }
    buffer->delete_backward (n);
  }

  int emacs_cxx_buffer_is_modified (void *buf)
  {
    auto *buffer = static_cast<emacs::EmacsBuffer *> (buf);
    return buffer && buffer->is_modified () ? 1 : 0;
  }
}
