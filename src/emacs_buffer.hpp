// src/emacs_buffer.hpp
// Emacs buffer object and marker system
//
// Phase 6.2: Buffer Object
// Phase 6.3: Marker System

#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include "containers.hpp"
#include "emacs_undo.hpp"
#include "gap_buffer.hpp"

namespace emacs
{

class EmacsBuffer;

/**
 * MarkerInsertionType
 *
 * Controls how a marker behaves when text is inserted
 * at its position.
 */
enum class MarkerInsertionType
{
  BEFORE_INSERTION,
  AFTER_INSERTION
};

/**
 * Marker
 *
 * Tracks a 1-based position inside a buffer. Markers are
 * registered with the buffer and updated on edits.
 */
class Marker
{
public:
  /**
   * Construct a marker at a position in a buffer.
   */
  Marker (EmacsBuffer *buffer, ptrdiff_t pos,
	  MarkerInsertionType type
	  = MarkerInsertionType::BEFORE_INSERTION);

  /**
   * Unregister marker from its buffer.
   */
  ~Marker ();

  // No copy, no move (markers are registered in buffer)
  Marker (const Marker &) = delete;
  Marker &operator= (const Marker &) = delete;
  Marker (Marker &&) = delete;
  Marker &operator= (Marker &&) = delete;

  /**
   * Current marker position (1-based).
   */
  [[nodiscard]] ptrdiff_t position () const noexcept;

  /**
   * Set marker position (1-based).
   */
  void set_position (ptrdiff_t pos);

  /**
   * Owning buffer, or nullptr if detached.
   */
  [[nodiscard]] EmacsBuffer *buffer () const noexcept;

  /**
   * Marker insertion behavior at its position.
   */
  [[nodiscard]] MarkerInsertionType insertion_type () const noexcept;

  /**
   * Update marker insertion behavior.
   */
  void set_insertion_type (MarkerInsertionType type) noexcept;

private:
  friend class EmacsBuffer;

  EmacsBuffer *buffer_;
  ptrdiff_t position_;
  MarkerInsertionType insertion_type_;
};

/**
 * EmacsBuffer
 *
 * Wraps GapBuffer and provides Emacs buffer semantics:
 * - name
 * - modified flag
 * - registered markers that track edits
 *
 * All public positions are 1-based and measured in bytes.
 */
class EmacsBuffer
{
public:
  /**
   * Construct an empty buffer with a name.
   */
  explicit EmacsBuffer (std::string_view name);

  /**
   * Construct a buffer with initial text.
   *
   * The point is placed after the inserted text.
   */
  EmacsBuffer (std::string_view name, std::string_view initial_text);

  /**
   * Detach all markers from the buffer.
   */
  ~EmacsBuffer ();

  // No copy, allow move
  EmacsBuffer (const EmacsBuffer &) = delete;
  EmacsBuffer &operator= (const EmacsBuffer &) = delete;
  EmacsBuffer (EmacsBuffer &&) noexcept;
  EmacsBuffer &operator= (EmacsBuffer &&) noexcept;

  /**
   * Buffer name.
   */
  [[nodiscard]] const gc_string &name () const noexcept;

  /**
   * Update buffer name.
   */
  void set_name (std::string_view name);

  /**
   * Text size in bytes (gap excluded).
   */
  [[nodiscard]] ptrdiff_t size () const noexcept;

  /**
   * True if buffer is empty.
   */
  [[nodiscard]] bool empty () const noexcept;

  /**
   * Point position (1-based).
   */
  [[nodiscard]] ptrdiff_t point () const noexcept;

  /**
   * Move point to position.
   */
  void set_point (ptrdiff_t pos);

  /**
   * Minimum point (always 1).
   */
  [[nodiscard]] ptrdiff_t point_min () const noexcept;

  /**
   * Maximum point (size + 1).
   */
  [[nodiscard]] ptrdiff_t point_max () const noexcept;

  /**
   * Is a mark set?
   */
  [[nodiscard]] bool has_mark () const noexcept;

  /**
   * Current mark position (1-based), or 0 if unset.
   */
  [[nodiscard]] ptrdiff_t mark () const noexcept;

  /**
   * Set mark position (1-based).
   */
  void set_mark (ptrdiff_t pos);

  /**
   * Deactivate mark without clearing it.
   */
  void deactivate_mark () noexcept;

  /**
   * Is mark active?
   */
  [[nodiscard]] bool mark_active () const noexcept;

  /**
   * Swap point and mark.
   */
  void exchange_point_and_mark ();

  /**
   * Region beginning (min of point and mark).
   */
  [[nodiscard]] ptrdiff_t region_beginning () const noexcept;

  /**
   * Region end (max of point and mark).
   */
  [[nodiscard]] ptrdiff_t region_end () const noexcept;

  /**
   * Character at position.
   */
  [[nodiscard]] char char_at (ptrdiff_t pos) const;

  /**
   * Full buffer content.
   */
  [[nodiscard]] std::string content () const;

  /**
   * Substring in range [from, to).
   */
  [[nodiscard]] std::string content_range (ptrdiff_t from,
					   ptrdiff_t to) const;

  /**
   * Insert a single byte at point.
   */
  void insert_char (char c);

  /**
   * Insert a string at point.
   */
  void insert_string (std::string_view text);

  /**
   * Delete N UTF-8 characters after point.
   */
  void delete_forward (ptrdiff_t n = 1);

  /**
   * Delete N UTF-8 characters before point.
   */
  void delete_backward (ptrdiff_t n = 1);

  /**
   * Undo last change group.
   */
  void undo ();

  /**
   * Redo last undone group.
   */
  void redo ();

  /**
   * Modified flag.
   */
  [[nodiscard]] bool is_modified () const noexcept;

  /**
   * Set modified flag.
   */
  void set_modified (bool modified) noexcept;

  /**
   * Narrow buffer to [beg, end).
   */
  void narrow_to_region (ptrdiff_t beg, ptrdiff_t end);

  /**
   * Clear narrowing.
   */
  void widen () noexcept;

  /**
   * Is buffer narrowed?
   */
  [[nodiscard]] bool is_narrowed () const noexcept;

  /**
   * Marker registration (called by Marker).
   */
  void register_marker (Marker *marker);

  /**
   * Marker unregistration (called by Marker).
   */
  void unregister_marker (Marker *marker);

  /**
   * Number of registered markers.
   */
  [[nodiscard]] size_t marker_count () const noexcept;

  /**
   * Direct access to underlying gap buffer.
   */
  [[nodiscard]] const GapBuffer &gap_buffer () const noexcept;
  [[nodiscard]] GapBuffer &gap_buffer () noexcept;

  /**
   * Access undo manager.
   */
  [[nodiscard]] UndoManager &undo_manager () noexcept;
  [[nodiscard]] const UndoManager &undo_manager () const noexcept;

private:
  gc_string name_;
  GapBuffer text_;
  bool modified_;
  gc_vector_t<Marker *> markers_;
  ptrdiff_t mark_;
  bool mark_active_;
  ptrdiff_t narrow_beg_;
  ptrdiff_t narrow_end_;
  UndoManager undo_manager_;
  bool inhibit_undo_recording_;
  size_t self_insert_count_;
  ptrdiff_t self_insert_pos_;
  gc_string self_insert_text_;

  /**
   * Adjust markers after insertion.
   *
   * Rules:
   * - position > pos: shift forward by length
   * - position == pos:
   *   - AFTER_INSERTION: shift forward by length
   *   - BEFORE_INSERTION: stay put
   * - position < pos: unchanged
   */
  void adjust_markers_for_insert (ptrdiff_t pos, ptrdiff_t length);

  /**
   * Adjust markers after deletion of range [pos, pos + length).
   *
   * Rules:
   * - position >= pos + length: shift backward by length
   * - position > pos && position < pos + length: move to pos
   * - position <= pos: unchanged
   */
  void adjust_markers_for_delete (ptrdiff_t pos, ptrdiff_t length);

  void flush_self_insert_group ();
};

} // namespace emacs

#ifdef __cplusplus
extern "C"
{
#endif

  void *emacs_cxx_create_buffer (const char *name);
  void *emacs_cxx_create_buffer_with_text (const char *name,
					   const char *text);
  void emacs_cxx_destroy_buffer (void *buf);
  ptrdiff_t emacs_cxx_buffer_size (void *buf);
  ptrdiff_t emacs_cxx_buffer_point (void *buf);
  void emacs_cxx_buffer_set_point (void *buf, ptrdiff_t pos);
  void emacs_cxx_buffer_insert_char (void *buf, char c);
  void emacs_cxx_buffer_insert_string (void *buf, const char *text);
  void emacs_cxx_buffer_delete_forward (void *buf, ptrdiff_t n);
  void emacs_cxx_buffer_delete_backward (void *buf, ptrdiff_t n);
  int emacs_cxx_buffer_is_modified (void *buf);

#ifdef __cplusplus
}
#endif
