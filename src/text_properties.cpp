// src/text_properties.cpp
// Text properties implementation

#include "text_properties.hpp"

#include <algorithm>

namespace emacs
{

void
TextProperties::put (ptrdiff_t start, ptrdiff_t end,
		     std::string_view key,
		     const TextPropertyValue &value)
{
  if (start >= end || start < 1)
    {
      return;
    }

  gc_string key_str (key.begin (), key.end ());

  remove (start, end, key);

  PropertyInterval interval;
  interval.start = start;
  interval.end = end;
  interval.key = key_str;
  interval.value = value;

  auto it
    = std::lower_bound (intervals_.begin (), intervals_.end (), start,
			[] (const PropertyInterval &iv, ptrdiff_t pos)
			  { return iv.start < pos; });

  intervals_.insert (it, interval);
  merge_adjacent_intervals ();
}

void
TextProperties::put_face (ptrdiff_t start, ptrdiff_t end,
			  const tui::CellAttributes &attrs)
{
  put (start, end, "face", TextPropertyValue (attrs));
}

std::optional<TextPropertyValue>
TextProperties::get (ptrdiff_t pos, std::string_view key) const
{
  for (const auto &iv : intervals_)
    {
      if (iv.key.size () == key.size ()
	  && std::equal (iv.key.begin (), iv.key.end (), key.begin ())
	  && iv.contains (pos))
	{
	  return iv.value;
	}
    }
  return std::nullopt;
}

std::optional<tui::CellAttributes>
TextProperties::get_face (ptrdiff_t pos) const
{
  auto val = get (pos, "face");
  if (!val)
    {
      return std::nullopt;
    }
  if (auto *attrs = std::get_if<tui::CellAttributes> (&*val))
    {
      return *attrs;
    }
  return std::nullopt;
}

void
TextProperties::remove (ptrdiff_t start, ptrdiff_t end,
			std::string_view key)
{
  if (start >= end)
    {
      return;
    }

  gc_vector_t<PropertyInterval> new_intervals;

  for (auto &iv : intervals_)
    {
      bool key_match = iv.key.size () == key.size ()
		       && std::equal (iv.key.begin (), iv.key.end (),
				      key.begin ());

      if (!key_match)
	{
	  new_intervals.push_back (std::move (iv));
	  continue;
	}

      if (iv.end <= start || iv.start >= end)
	{
	  new_intervals.push_back (std::move (iv));
	  continue;
	}

      if (iv.start < start)
	{
	  PropertyInterval left = iv;
	  left.end = start;
	  new_intervals.push_back (std::move (left));
	}

      if (iv.end > end)
	{
	  PropertyInterval right = iv;
	  right.start = end;
	  new_intervals.push_back (std::move (right));
	}
    }

  intervals_ = std::move (new_intervals);
}

void
TextProperties::remove_all (ptrdiff_t start, ptrdiff_t end)
{
  if (start >= end)
    {
      return;
    }

  gc_vector_t<PropertyInterval> new_intervals;

  for (auto &iv : intervals_)
    {
      if (iv.end <= start || iv.start >= end)
	{
	  new_intervals.push_back (std::move (iv));
	  continue;
	}

      if (iv.start < start)
	{
	  PropertyInterval left = iv;
	  left.end = start;
	  new_intervals.push_back (std::move (left));
	}

      if (iv.end > end)
	{
	  PropertyInterval right = iv;
	  right.start = end;
	  new_intervals.push_back (std::move (right));
	}
    }

  intervals_ = std::move (new_intervals);
}

ptrdiff_t
TextProperties::next_property_change (ptrdiff_t pos,
				      std::string_view key) const
{
  ptrdiff_t best = 0;

  for (const auto &iv : intervals_)
    {
      bool key_match = iv.key.size () == key.size ()
		       && std::equal (iv.key.begin (), iv.key.end (),
				      key.begin ());
      if (!key_match)
	{
	  continue;
	}

      if (iv.start > pos)
	{
	  if (best == 0 || iv.start < best)
	    {
	      best = iv.start;
	    }
	  break;
	}

      if (iv.contains (pos) && iv.end > pos)
	{
	  if (best == 0 || iv.end < best)
	    {
	      best = iv.end;
	    }
	}
    }

  return best;
}

void
TextProperties::for_each_in_range (
  ptrdiff_t start, ptrdiff_t end, std::string_view key,
  const std::function<void (const PropertyInterval &)> &callback)
  const
{
  for (const auto &iv : intervals_)
    {
      bool key_match = iv.key.size () == key.size ()
		       && std::equal (iv.key.begin (), iv.key.end (),
				      key.begin ());
      if (!key_match)
	{
	  continue;
	}
      if (iv.start >= end)
	{
	  break;
	}
      if (iv.end > start)
	{
	  callback (iv);
	}
    }
}

void
TextProperties::for_each_in_range (
  ptrdiff_t start, ptrdiff_t end,
  const std::function<void (const PropertyInterval &)> &callback)
  const
{
  for (const auto &iv : intervals_)
    {
      if (iv.start >= end)
	{
	  continue;
	}
      if (iv.end > start)
	{
	  callback (iv);
	}
    }
}

void
TextProperties::adjust_for_insert (ptrdiff_t pos, ptrdiff_t length)
{
  if (length <= 0)
    {
      return;
    }

  for (auto &iv : intervals_)
    {
      if (iv.start > pos)
	{
	  iv.start += length;
	  iv.end += length;
	}
      else if (iv.start == pos)
	{
	  if (iv.front_sticky)
	    {
	      iv.end += length;
	    }
	  else
	    {
	      iv.start += length;
	      iv.end += length;
	    }
	}
      else if (pos < iv.end)
	{
	  iv.end += length;
	}
      else if (pos == iv.end && iv.rear_sticky)
	{
	  iv.end += length;
	}
    }
}

void
TextProperties::adjust_for_delete (ptrdiff_t pos, ptrdiff_t length)
{
  if (length <= 0)
    {
      return;
    }

  ptrdiff_t del_end = pos + length;

  for (auto &iv : intervals_)
    {
      if (iv.start >= del_end)
	{
	  iv.start -= length;
	  iv.end -= length;
	}
      else if (iv.end <= pos)
	{
	  // Entirely before deletion — no change.
	}
      else if (iv.start >= pos && iv.end <= del_end)
	{
	  iv.start = pos;
	  iv.end = pos;
	}
      else if (iv.start < pos && iv.end > del_end)
	{
	  iv.end -= length;
	}
      else if (iv.start < pos)
	{
	  iv.end = pos;
	}
      else
	{
	  iv.start = pos;
	  iv.end -= length;
	  if (iv.end < iv.start)
	    {
	      iv.end = iv.start;
	    }
	}
    }

  remove_empty_intervals ();
}

size_t
TextProperties::interval_count () const noexcept
{
  return intervals_.size ();
}

bool
TextProperties::empty () const noexcept
{
  return intervals_.empty ();
}

void
TextProperties::clear () noexcept
{
  intervals_.clear ();
}

void
TextProperties::remove_empty_intervals ()
{
  auto it = std::remove_if (intervals_.begin (), intervals_.end (),
			    [] (const PropertyInterval &iv)
			      { return iv.empty (); });
  intervals_.erase (it, intervals_.end ());
}

void
TextProperties::merge_adjacent_intervals ()
{
  if (intervals_.size () < 2)
    {
      return;
    }

  gc_vector_t<PropertyInterval> merged;
  merged.push_back (intervals_[0]);

  for (size_t i = 1; i < intervals_.size (); ++i)
    {
      auto &prev = merged.back ();
      auto &curr = intervals_[i];

      bool same_key
	= prev.key.size () == curr.key.size ()
	  && std::equal (prev.key.begin (), prev.key.end (),
			 curr.key.begin ());

      bool same_value = same_key && prev.value == curr.value;

      if (same_value && prev.end >= curr.start)
	{
	  prev.end = std::max (prev.end, curr.end);
	}
      else
	{
	  merged.push_back (curr);
	}
    }

  intervals_ = std::move (merged);
}

} // namespace emacs
