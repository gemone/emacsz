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
      markers_ ()
{
}

EmacsBuffer::EmacsBuffer (std::string_view name,
			  std::string_view initial_text)
    : name_ (name.begin (), name.end ()), text_ (initial_text),
      modified_ (false), markers_ ()
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
      markers_ (std::move (other.markers_))
{
  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = this;
	}
    }
  other.markers_.clear ();
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

  for (Marker *marker : markers_)
    {
      if (marker)
	{
	  marker->buffer_ = this;
	}
    }
  other.markers_.clear ();

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
  text_.set_point (pos);
}

ptrdiff_t
EmacsBuffer::point_min () const noexcept
{
  return text_.point_min ();
}

ptrdiff_t
EmacsBuffer::point_max () const noexcept
{
  return text_.point_max ();
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
  text_.insert_char (c);
  adjust_markers_for_insert (insert_pos, 1);
  modified_ = true;
}

void
EmacsBuffer::insert_string (std::string_view text)
{
  if (text.empty ())
    {
      return;
    }

  ptrdiff_t insert_pos = text_.point ();
  text_.insert_string (text);
  adjust_markers_for_insert (insert_pos,
			     static_cast<ptrdiff_t> (text.size ()));
  modified_ = true;
}

void
EmacsBuffer::delete_forward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  ptrdiff_t before_size = text_.size ();
  ptrdiff_t delete_pos = text_.point ();
  text_.delete_forward (n);
  ptrdiff_t after_size = text_.size ();

  if (after_size == before_size)
    {
      return;
    }

  ptrdiff_t deleted = before_size - after_size;
  adjust_markers_for_delete (delete_pos, deleted);
  modified_ = true;
}

void
EmacsBuffer::delete_backward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  ptrdiff_t before_size = text_.size ();
  ptrdiff_t before_point = text_.point ();
  text_.delete_backward (n);
  ptrdiff_t after_size = text_.size ();

  if (after_size == before_size)
    {
      return;
    }

  ptrdiff_t deleted = before_size - after_size;
  ptrdiff_t delete_pos = before_point - deleted;
  adjust_markers_for_delete (delete_pos, deleted);
  modified_ = true;
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
