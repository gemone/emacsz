// src/emacs_undo.hpp
// Undo/redo manager for EmacsBuffer edits
//
// Phase 6.4: Undo System
// Records insert/delete operations and groups them for undo/redo.

#pragma once

#include <cstddef>
#include <string_view>
#include "containers.hpp"

namespace emacs
{

/**
 * Type of undo record.
 */
enum class UndoRecordType
{
  INSERT,
  DELETE
};

/**
 * A single undo record capturing one text change.
 */
struct UndoRecord
{
  UndoRecordType type;
  ptrdiff_t position;
  gc_string text;
  ptrdiff_t old_point;

  UndoRecord (UndoRecordType t, ptrdiff_t pos, std::string_view txt,
	      ptrdiff_t pt);
};

/**
 * An undo group is a sequence of records that should be
 * undone/redone together (like between undo boundaries).
 */
struct UndoGroup
{
  gc_vector_t<UndoRecord> records;

  [[nodiscard]] bool empty () const noexcept;
};

/**
 * Manages undo/redo for a buffer.
 */
class UndoManager
{
public:
  UndoManager ();
  ~UndoManager () = default;

  // No copy, allow move
  UndoManager (const UndoManager &) = delete;
  UndoManager &operator= (const UndoManager &) = delete;
  UndoManager (UndoManager &&) noexcept = default;
  UndoManager &operator= (UndoManager &&) noexcept = default;

  // Recording operations
  void begin_group ();
  void end_group ();
  void record_insert (ptrdiff_t pos, std::string_view text,
		      ptrdiff_t old_point);
  void record_delete (ptrdiff_t pos, std::string_view text,
		      ptrdiff_t old_point);

  // Undo/redo queries
  [[nodiscard]] bool can_undo () const noexcept;
  [[nodiscard]] bool can_redo () const noexcept;
  [[nodiscard]] size_t undo_count () const noexcept;
  [[nodiscard]] size_t redo_count () const noexcept;

  // Undo: returns group to replay (records in reverse order)
  [[nodiscard]] const UndoGroup &prepare_undo ();
  void commit_undo ();

  // Redo: returns group to replay (records in forward order)
  [[nodiscard]] const UndoGroup &prepare_redo ();
  void commit_redo ();

  // Clear all history
  void clear () noexcept;

  // Capacity management
  [[nodiscard]] size_t max_undo_count () const noexcept;
  void set_max_undo_count (size_t max) noexcept;

  // Is currently recording a group?
  [[nodiscard]] bool is_recording () const noexcept;

  // Enable/disable recording
  [[nodiscard]] bool is_enabled () const noexcept;
  void set_enabled (bool enabled) noexcept;

private:
  gc_vector_t<UndoGroup> undo_stack_;
  gc_vector_t<UndoGroup> redo_stack_;
  UndoGroup current_group_;
  bool recording_;
  bool enabled_;
  size_t max_undo_;
  UndoGroup prepared_undo_;
  UndoGroup prepared_redo_;

  void push_undo_group (UndoGroup &&group);
  void trim_undo_stack ();
};

} // namespace emacs
