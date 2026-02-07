// src/gap_buffer.cpp
// Gap buffer implementation for Emacs C++20 migration

#include "gap_buffer.hpp"
#include <cassert>
#include <cstring>

namespace emacs
{
namespace
{

[[nodiscard]] bool
is_continuation_byte (unsigned char byte) noexcept
{
  return (byte & 0xC0) == 0x80;
}

[[nodiscard]] ptrdiff_t
utf8_sequence_length (unsigned char lead) noexcept
{
  if ((lead & 0x80) == 0x00)
    {
      return 1;
    }

  if ((lead & 0xE0) == 0xC0)
    {
      return 2;
    }

  if ((lead & 0xF0) == 0xE0)
    {
      return 3;
    }

  if ((lead & 0xF8) == 0xF0)
    {
      return 4;
    }

  return 1;
}

[[nodiscard]] bool
is_valid_utf8_sequence (const char *data, ptrdiff_t offset,
			ptrdiff_t length, ptrdiff_t end)
{
  if (offset + length > end)
    {
      return false;
    }

  for (ptrdiff_t i = 1; i < length; ++i)
    {
      unsigned char byte
	= static_cast<unsigned char> (data[offset + i]);
      if (!is_continuation_byte (byte))
	{
	  return false;
	}
    }

  return true;
}

[[nodiscard]] ptrdiff_t
utf8_forward_char_len (const char *data, ptrdiff_t offset,
		       ptrdiff_t end)
{
  if (offset >= end)
    {
      return 0;
    }

  unsigned char lead = static_cast<unsigned char> (data[offset]);
  ptrdiff_t length = utf8_sequence_length (lead);

  if (length == 1)
    {
      return 1;
    }

  if (!is_valid_utf8_sequence (data, offset, length, end))
    {
      return 1;
    }

  return length;
}

[[nodiscard]] ptrdiff_t
utf8_backward_char_len (const char *data, ptrdiff_t offset)
{
  if (offset <= 0)
    {
      return 0;
    }

  ptrdiff_t start = offset - 1;
  ptrdiff_t scans = 0;

  while (
    start > 0
    && is_continuation_byte (static_cast<unsigned char> (data[start]))
    && scans < 3)
    {
      --start;
      ++scans;
    }

  unsigned char lead = static_cast<unsigned char> (data[start]);
  ptrdiff_t length = utf8_sequence_length (lead);

  if (length == 1)
    {
      return 1;
    }

  if (start + length != offset)
    {
      return 1;
    }

  if (!is_valid_utf8_sequence (data, start, length, offset))
    {
      return 1;
    }

  return length;
}

} // namespace

GapBuffer::GapBuffer ()
    : buffer_ (static_cast<size_t> (INITIAL_GAP_SIZE)),
      gap_start_ (0), gap_size_ (INITIAL_GAP_SIZE), point_ (1)
{
}

GapBuffer::GapBuffer (std::string_view initial_text)
    : buffer_ (static_cast<size_t> (initial_text.size ()
				    + INITIAL_GAP_SIZE)),
      gap_start_ (static_cast<ptrdiff_t> (initial_text.size ())),
      gap_size_ (INITIAL_GAP_SIZE),
      point_ (static_cast<ptrdiff_t> (initial_text.size () + 1))
{
  if (!initial_text.empty ())
    {
      std::memcpy (buffer_.data (), initial_text.data (),
		   initial_text.size ());
    }
}

ptrdiff_t
GapBuffer::size () const noexcept
{
  return static_cast<ptrdiff_t> (buffer_.size ()) - gap_size_;
}

bool
GapBuffer::empty () const noexcept
{
  return size () == 0;
}

ptrdiff_t
GapBuffer::point () const noexcept
{
  return point_;
}

void
GapBuffer::set_point (ptrdiff_t pos)
{
  assert (pos >= point_min () && pos <= point_max ());
  point_ = pos;
}

ptrdiff_t
GapBuffer::point_min () const noexcept
{
  return 1;
}

ptrdiff_t
GapBuffer::point_max () const noexcept
{
  return size () + 1;
}

void
GapBuffer::insert_char (char c)
{
  move_gap_to (point_ - 1);
  ensure_gap (1);

  buffer_[static_cast<size_t> (gap_start_)] = c;
  ++gap_start_;
  --gap_size_;
  ++point_;
}

void
GapBuffer::insert_string (std::string_view text)
{
  if (text.empty ())
    {
      return;
    }

  move_gap_to (point_ - 1);
  ensure_gap (static_cast<ptrdiff_t> (text.size ()));

  std::memcpy (buffer_.data () + static_cast<size_t> (gap_start_),
	       text.data (), text.size ());
  gap_start_ += static_cast<ptrdiff_t> (text.size ());
  gap_size_ -= static_cast<ptrdiff_t> (text.size ());
  point_ += static_cast<ptrdiff_t> (text.size ());
}

void
GapBuffer::delete_forward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  if (point_ > size ())
    {
      return;
    }

  move_gap_to (point_ - 1);

  ptrdiff_t gap_end = gap_start_ + gap_size_;
  ptrdiff_t end = static_cast<ptrdiff_t> (buffer_.size ());
  const char *data = buffer_.data ();

  ptrdiff_t bytes_deleted = 0;
  ptrdiff_t offset = gap_end;

  for (ptrdiff_t count = 0; count < n && offset < end; ++count)
    {
      ptrdiff_t len = utf8_forward_char_len (data, offset, end);
      if (len <= 0)
	{
	  break;
	}
      offset += len;
      bytes_deleted += len;
    }

  gap_size_ += bytes_deleted;
}

void
GapBuffer::delete_backward (ptrdiff_t n)
{
  if (n <= 0)
    {
      return;
    }

  if (point_ <= 1)
    {
      return;
    }

  move_gap_to (point_ - 1);

  const char *data = buffer_.data ();
  ptrdiff_t bytes_deleted = 0;
  ptrdiff_t offset = gap_start_;

  for (ptrdiff_t count = 0; count < n && offset > 0; ++count)
    {
      ptrdiff_t len = utf8_backward_char_len (data, offset);
      if (len <= 0)
	{
	  break;
	}
      offset -= len;
      bytes_deleted += len;
    }

  gap_start_ -= bytes_deleted;
  gap_size_ += bytes_deleted;
  point_ -= bytes_deleted;
}

char
GapBuffer::char_at (ptrdiff_t pos) const
{
  assert (pos >= point_min () && pos <= size ());
  ptrdiff_t offset = pos_to_offset (pos);
  unsigned char byte = static_cast<unsigned char> (buffer_[offset]);
  assert (!is_continuation_byte (byte));
  return buffer_[offset];
}

std::string_view
GapBuffer::text_before_gap () const noexcept
{
  return std::string_view (buffer_.data (),
			   static_cast<size_t> (gap_start_));
}

std::string_view
GapBuffer::text_after_gap () const noexcept
{
  ptrdiff_t start = gap_start_ + gap_size_;
  ptrdiff_t length = static_cast<ptrdiff_t> (buffer_.size ()) - start;

  return std::string_view (buffer_.data ()
			     + static_cast<size_t> (start),
			   static_cast<size_t> (length));
}

std::string
GapBuffer::content () const
{
  ptrdiff_t text_size = size ();
  std::string result;
  result.resize (static_cast<size_t> (text_size));

  if (text_size == 0)
    {
      return result;
    }

  if (gap_start_ > 0)
    {
      std::memcpy (result.data (), buffer_.data (),
		   static_cast<size_t> (gap_start_));
    }

  ptrdiff_t after_len = static_cast<ptrdiff_t> (buffer_.size ())
			- gap_start_ - gap_size_;
  if (after_len > 0)
    {
      std::memcpy (result.data () + static_cast<size_t> (gap_start_),
		   buffer_.data ()
		     + static_cast<size_t> (gap_start_ + gap_size_),
		   static_cast<size_t> (after_len));
    }

  return result;
}

std::string
GapBuffer::content_range (ptrdiff_t from, ptrdiff_t to) const
{
  assert (from >= point_min ());
  assert (to >= from);
  assert (to <= point_max ());

  ptrdiff_t length = to - from;
  std::string result;
  result.resize (static_cast<size_t> (length));

  if (length == 0)
    {
      return result;
    }

  ptrdiff_t start_offset = pos_to_offset (from);
  ptrdiff_t end_offset = pos_to_offset (to);

  if (start_offset < gap_start_ && end_offset <= gap_start_)
    {
      std::memcpy (result.data (),
		   buffer_.data ()
		     + static_cast<size_t> (start_offset),
		   static_cast<size_t> (length));
      return result;
    }

  ptrdiff_t gap_end = gap_start_ + gap_size_;
  if (start_offset >= gap_end)
    {
      std::memcpy (result.data (),
		   buffer_.data ()
		     + static_cast<size_t> (start_offset),
		   static_cast<size_t> (length));
      return result;
    }

  ptrdiff_t before_len = gap_start_ - start_offset;
  if (before_len > 0)
    {
      std::memcpy (result.data (),
		   buffer_.data ()
		     + static_cast<size_t> (start_offset),
		   static_cast<size_t> (before_len));
    }

  ptrdiff_t after_len = length - before_len;
  if (after_len > 0)
    {
      std::memcpy (result.data () + static_cast<size_t> (before_len),
		   buffer_.data () + static_cast<size_t> (gap_end),
		   static_cast<size_t> (after_len));
    }

  return result;
}

ptrdiff_t
GapBuffer::gap_start () const noexcept
{
  return gap_start_;
}

ptrdiff_t
GapBuffer::gap_size () const noexcept
{
  return gap_size_;
}

ptrdiff_t
GapBuffer::buffer_size () const noexcept
{
  return static_cast<ptrdiff_t> (buffer_.size ());
}

void
GapBuffer::move_gap_to (ptrdiff_t pos)
{
  assert (pos >= 0);
  assert (pos <= size ());

  if (pos == gap_start_)
    {
      return;
    }

  if (pos < gap_start_)
    {
      ptrdiff_t move_bytes = gap_start_ - pos;
      std::memmove (buffer_.data ()
		      + static_cast<size_t> (pos + gap_size_),
		    buffer_.data () + static_cast<size_t> (pos),
		    static_cast<size_t> (move_bytes));
      gap_start_ = pos;
      return;
    }

  ptrdiff_t move_bytes = pos - gap_start_;
  std::memmove (buffer_.data () + static_cast<size_t> (gap_start_),
		buffer_.data ()
		  + static_cast<size_t> (gap_start_ + gap_size_),
		static_cast<size_t> (move_bytes));
  gap_start_ = pos;
}

void
GapBuffer::ensure_gap (ptrdiff_t needed)
{
  if (needed <= gap_size_)
    {
      return;
    }

  ptrdiff_t new_gap = gap_size_;
  if (new_gap < MIN_GAP_GROWTH)
    {
      new_gap = MIN_GAP_GROWTH;
    }
  while (new_gap < gap_size_ + needed)
    {
      new_gap *= 2;
    }

  ptrdiff_t text_size = size ();
  ptrdiff_t new_size = text_size + new_gap;
  gc_vector_t<char> new_buffer;
  new_buffer.resize (static_cast<size_t> (new_size));

  if (gap_start_ > 0)
    {
      std::memcpy (new_buffer.data (), buffer_.data (),
		   static_cast<size_t> (gap_start_));
    }

  ptrdiff_t after_len = text_size - gap_start_;
  if (after_len > 0)
    {
      std::memcpy (new_buffer.data ()
		     + static_cast<size_t> (gap_start_ + new_gap),
		   buffer_.data ()
		     + static_cast<size_t> (gap_start_ + gap_size_),
		   static_cast<size_t> (after_len));
    }

  buffer_ = std::move (new_buffer);
  gap_size_ = new_gap;
}

ptrdiff_t
GapBuffer::pos_to_offset (ptrdiff_t pos) const noexcept
{
  ptrdiff_t offset = pos - 1;
  if (offset >= gap_start_)
    {
      offset += gap_size_;
    }
  return offset;
}

} // namespace emacs
