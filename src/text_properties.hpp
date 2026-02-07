// src/text_properties.hpp
// Text properties system for EmacsBuffer
//
// Phase 9.1: Text Properties
//
// Text properties attach metadata (face attributes, syntax info,
// custom key-value pairs) to character ranges in a buffer.
// Intervals shift automatically on insert/delete operations.
//
// Design: Sorted vector of non-overlapping intervals per property
// key. For the common "face" property, CellAttributes are stored
// directly for zero-cost integration with Grid rendering.
//
// Positions are 1-based (Emacs convention).

#pragma once

#include <cstddef>
#include <functional>
#include <optional>
#include <string_view>
#include <variant>

#include "allocator.hpp"
#include "containers.hpp"
#include "grid.hpp"

namespace emacs
{

/**
 * TextPropertyValue
 *
 * A property value is either a face (CellAttributes for rendering)
 * or a generic string value for extensibility.
 */
using TextPropertyValue
  = std::variant<tui::CellAttributes, gc_string, ptrdiff_t>;

/**
 * PropertyInterval
 *
 * A half-open range [start, end) with a property key and value.
 * Positions are 1-based. Intervals are sorted by start position
 * within each property key.
 */
struct PropertyInterval
{
  ptrdiff_t start; // 1-based, inclusive
  ptrdiff_t end;   // 1-based, exclusive

  gc_string key;
  TextPropertyValue value;

  // Sticky behavior: controls what happens when text is inserted
  // at interval boundaries.
  //   front_sticky: insertion at start extends the interval
  //   rear_sticky: insertion at end extends the interval
  bool front_sticky = false;
  bool rear_sticky = true;

  [[nodiscard]] bool contains (ptrdiff_t pos) const noexcept
  {
    return pos >= start && pos < end;
  }

  [[nodiscard]] bool empty () const noexcept { return start >= end; }

  [[nodiscard]] ptrdiff_t length () const noexcept
  {
    return end > start ? end - start : 0;
  }
};

/**
 * TextProperties
 *
 * Manages text property intervals for a buffer. Intervals are
 * stored in a flat sorted vector for cache-friendly access and
 * simple implementation. This is efficient for typical property
 * counts (dozens to low hundreds per buffer).
 *
 * For rendering, the primary use case is the "face" property
 * which stores CellAttributes directly.
 *
 * Thread safety: NOT thread-safe (same as EmacsBuffer).
 */
class TextProperties
{
public:
  TextProperties () = default;
  ~TextProperties () = default;

  TextProperties (const TextProperties &) = default;
  TextProperties &operator= (const TextProperties &) = default;
  TextProperties (TextProperties &&) noexcept = default;
  TextProperties &operator= (TextProperties &&) noexcept = default;

  /**
   * Set a property on range [start, end).
   *
   * If the range overlaps existing intervals with the same key,
   * they are split/merged as needed.
   */
  void put (ptrdiff_t start, ptrdiff_t end, std::string_view key,
	    const TextPropertyValue &value);

  /**
   * Set a face property on range [start, end).
   *
   * Convenience method for the most common use case.
   */
  void put_face (ptrdiff_t start, ptrdiff_t end,
		 const tui::CellAttributes &attrs);

  /**
   * Get a property value at position for the given key.
   *
   * Returns std::nullopt if no property exists at that position.
   */
  [[nodiscard]] std::optional<TextPropertyValue>
  get (ptrdiff_t pos, std::string_view key) const;

  /**
   * Get face attributes at position.
   *
   * Returns std::nullopt if no face property at that position.
   */
  [[nodiscard]] std::optional<tui::CellAttributes>
  get_face (ptrdiff_t pos) const;

  /**
   * Remove all properties with the given key from [start, end).
   */
  void remove (ptrdiff_t start, ptrdiff_t end, std::string_view key);

  /**
   * Remove ALL properties from [start, end).
   */
  void remove_all (ptrdiff_t start, ptrdiff_t end);

  /**
   * Find the next position where a property changes for key.
   *
   * Starting from pos, returns the next position where the
   * property starts or ends. Returns 0 if no change found.
   */
  [[nodiscard]] ptrdiff_t
  next_property_change (ptrdiff_t pos, std::string_view key) const;

  /**
   * Iterate all intervals overlapping [start, end) for key.
   */
  void for_each_in_range (
    ptrdiff_t start, ptrdiff_t end, std::string_view key,
    const std::function<void (const PropertyInterval &)> &callback)
    const;

  /**
   * Iterate ALL intervals overlapping [start, end).
   */
  void for_each_in_range (
    ptrdiff_t start, ptrdiff_t end,
    const std::function<void (const PropertyInterval &)> &callback)
    const;

  // === Position adjustment (called by buffer on edits) ===

  /**
   * Shift intervals after an insertion at pos of length bytes.
   *
   * Intervals after pos shift forward. Intervals spanning pos
   * may extend depending on sticky settings.
   */
  void adjust_for_insert (ptrdiff_t pos, ptrdiff_t length);

  /**
   * Shift intervals after a deletion of [pos, pos+length).
   *
   * Intervals after the deleted range shift backward.
   * Intervals within the deleted range are shrunk or removed.
   */
  void adjust_for_delete (ptrdiff_t pos, ptrdiff_t length);

  // === Queries ===

  /**
   * Total number of property intervals.
   */
  [[nodiscard]] size_t interval_count () const noexcept;

  /**
   * True if no property intervals exist.
   */
  [[nodiscard]] bool empty () const noexcept;

  /**
   * Remove all property intervals.
   */
  void clear () noexcept;

private:
  gc_vector_t<PropertyInterval> intervals_;

  void remove_empty_intervals ();
  void merge_adjacent_intervals ();
};

} // namespace emacs

#ifdef __cplusplus
extern "C"
{
#endif

  void emacs_cxx_put_text_property (void *buf, ptrdiff_t start,
				    ptrdiff_t end, const char *key,
				    const char *value);
  void emacs_cxx_put_face_property (void *buf, ptrdiff_t start,
				    ptrdiff_t end, uint32_t fg,
				    uint32_t bg, uint16_t flags);
  void emacs_cxx_remove_text_property (void *buf, ptrdiff_t start,
				       ptrdiff_t end,
				       const char *key);
  int emacs_cxx_has_text_property (void *buf, ptrdiff_t pos,
				   const char *key);

#ifdef __cplusplus
}
#endif
