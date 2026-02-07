// src/gap_buffer.hpp
// C++20 gap buffer for Emacs text storage
//
// Phase 6.1: Lisp Interpreter Core
// This file defines the core gap buffer data structure used by
// the C++20 migration branch.
//
// The buffer uses 1-based positions to match Emacs (BEG = 1).
// All public positions are in bytes, not characters.

#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include "containers.hpp"

namespace emacs
{

/**
 * GapBuffer
 *
 * A gap buffer stores text in a contiguous array with a movable
 * gap at point. Insertions at point are O(1) and other operations
 * move the gap as needed.
 *
 * Invariants:
 * - buffer_ holds both text and the gap.
 * - gap_start_ is a 0-based byte offset in buffer_.
 * - gap_size_ is the number of unused bytes in the gap.
 * - point_ is a 1-based position in the text (BEG = 1).
 *
 * UTF-8:
 * - delete_forward/backward remove full UTF-8 sequences.
 * - char_at asserts that pos is on a UTF-8 boundary.
 */
class GapBuffer
{
public:
  /**
   * Construct an empty buffer with an initial gap.
   */
  GapBuffer ();

  /**
   * Construct a buffer pre-loaded with text.
   *
   * The point is placed after the inserted text.
   */
  explicit GapBuffer (std::string_view initial_text);

  ~GapBuffer () = default;

  // Delete copy (expensive), allow move
  GapBuffer (const GapBuffer &) = delete;
  GapBuffer &operator= (const GapBuffer &) = delete;
  GapBuffer (GapBuffer &&) noexcept = default;
  GapBuffer &operator= (GapBuffer &&) noexcept = default;

  /**
   * Total number of bytes in the buffer (gap excluded).
   */
  [[nodiscard]] ptrdiff_t size () const noexcept;

  /**
   * Returns true if the buffer is empty.
   */
  [[nodiscard]] bool empty () const noexcept;

  /**
   * Current cursor position (1-based).
   */
  [[nodiscard]] ptrdiff_t point () const noexcept;

  /**
   * Move cursor to the given position.
   *
   * @param pos 1-based position in range [BEG..Z+1].
   */
  void set_point (ptrdiff_t pos);

  /**
   * Minimum point position (always 1).
   */
  [[nodiscard]] ptrdiff_t point_min () const noexcept;

  /**
   * Maximum point position (size + 1).
   */
  [[nodiscard]] ptrdiff_t point_max () const noexcept;

  /**
   * Insert a single byte at point.
   *
   * Point advances by one byte.
   */
  void insert_char (char c);

  /**
   * Insert a string at point.
   *
   * Point advances by text.size() bytes.
   */
  void insert_string (std::string_view text);

  /**
   * Delete N UTF-8 characters after point.
   *
   * If fewer than N characters remain, deletes to end.
   */
  void delete_forward (ptrdiff_t n = 1);

  /**
   * Delete N UTF-8 characters before point.
   *
   * If fewer than N characters exist, deletes to beginning.
   */
  void delete_backward (ptrdiff_t n = 1);

  /**
   * Get byte at a 1-based position.
   *
   * Asserts that pos is on a UTF-8 boundary.
   */
  [[nodiscard]] char char_at (ptrdiff_t pos) const;

  /**
   * String view of the text before the gap.
   */
  [[nodiscard]] std::string_view text_before_gap () const noexcept;

  /**
   * String view of the text after the gap.
   */
  [[nodiscard]] std::string_view text_after_gap () const noexcept;

  /**
   * Full buffer content (gap excluded).
   */
  [[nodiscard]] std::string content () const;

  /**
   * Extract a substring in the range [from, to).
   *
   * Positions are 1-based; to may be point_max().
   */
  [[nodiscard]] std::string content_range (ptrdiff_t from,
					   ptrdiff_t to) const;

  /**
   * Gap start offset in the backing buffer (0-based).
   */
  [[nodiscard]] ptrdiff_t gap_start () const noexcept;

  /**
   * Current size of the gap in bytes.
   */
  [[nodiscard]] ptrdiff_t gap_size () const noexcept;

  /**
   * Total buffer size including the gap.
   */
  [[nodiscard]] ptrdiff_t buffer_size () const noexcept;

private:
  // Backing storage (text + gap)
  gc_vector_t<char> buffer_;

  // Start of the gap (0-based byte offset in buffer_)
  ptrdiff_t gap_start_;

  // Size of the gap in bytes
  ptrdiff_t gap_size_;

  // Cursor position (1-based, Emacs style)
  ptrdiff_t point_;

  static constexpr ptrdiff_t INITIAL_GAP_SIZE = 256;
  static constexpr ptrdiff_t MIN_GAP_GROWTH = 256;

  /**
   * Move the gap to a 0-based position in text.
   */
  void move_gap_to (ptrdiff_t pos);

  /**
   * Ensure the gap has at least needed bytes.
   */
  void ensure_gap (ptrdiff_t needed);

  /**
   * Convert 1-based text position to buffer offset.
   */
  [[nodiscard]] ptrdiff_t
  pos_to_offset (ptrdiff_t pos) const noexcept;
};

} // namespace emacs
