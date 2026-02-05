// src/grid.hpp
// Double-buffered grid system for terminal rendering
//
// This module provides a character-based grid with double buffering
// for efficient terminal updates. Only changed cells are redrawn.
//
// Phase 4: Terminal/TUI - Grid System
// Created: 2026-02-05

#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "allocator.hpp"
#include "containers.hpp"

namespace emacs
{
namespace tui
{

/**
 * Cell attributes for terminal display
 *
 * Represents foreground/background colors and text attributes
 * (bold, italic, underline, etc.) for a single grid cell.
 */
struct CellAttributes
{
  // Foreground color (0-255 for 256-color terminals, RGB for true
  // color)
  uint32_t fg = 7; // Default: white

  // Background color
  uint32_t bg = 0; // Default: black

  // Text attributes (bitfield)
  enum Flags : uint16_t
  {
    NONE = 0,
    BOLD = 1 << 0,
    ITALIC = 1 << 1,
    UNDERLINE = 1 << 2,
    REVERSE = 1 << 3,
    BLINK = 1 << 4,
    DIM = 1 << 5
  };
  uint16_t flags = NONE;

  [[nodiscard]] bool
  operator== (const CellAttributes &other) const noexcept
  {
    return fg == other.fg && bg == other.bg && flags == other.flags;
  }

  [[nodiscard]] bool
  operator!= (const CellAttributes &other) const noexcept
  {
    return !(*this == other);
  }
};

/**
 * Grid cell containing a character and its attributes
 */
struct Cell
{
  // Character data (UTF-8 string, typically 1-4 bytes)
  // Using gc_string for GC-aware allocation
  gc_string ch;

  // Cell attributes
  CellAttributes attrs;

  // Width in columns (1 for ASCII, 2 for CJK)
  uint8_t width = 1;

  // Default constructor
  Cell () noexcept : ch (" "), width (1) {}

  // Constructor with character
  explicit Cell (const std::string &c, uint8_t w = 1)
      : ch (c), width (w)
  {
  }

  // Constructor with character and attributes
  Cell (const std::string &c, const CellAttributes &a, uint8_t w = 1)
      : ch (c), attrs (a), width (w)
  {
  }

  [[nodiscard]] bool operator== (const Cell &other) const noexcept
  {
    return ch == other.ch && attrs == other.attrs
	   && width == other.width;
  }

  [[nodiscard]] bool operator!= (const Cell &other) const noexcept
  {
    return !(*this == other);
  }
};

/**
 * Rectangle region for dirty tracking
 */
struct Rect
{
  int row = 0;
  int col = 0;
  int rows = 0;
  int cols = 0;

  [[nodiscard]] bool is_empty () const noexcept
  {
    return rows <= 0 || cols <= 0;
  }

  [[nodiscard]] bool contains (int r, int c) const noexcept
  {
    return r >= row && r < row + rows && c >= col && c < col + cols;
  }
};

/**
 * Double-buffered grid for terminal rendering
 *
 * Features:
 * - Double buffering (front + back buffer)
 * - Dirty region tracking for minimal redraws
 * - UTF-8 and CJK character support (wcwidth)
 * - GC-aware memory allocation
 * - Efficient copy-on-write semantics
 */
class Grid
{
private:
  // Grid dimensions
  int rows_;
  int cols_;

  // Front buffer (currently displayed)
  gc_vector_t<Cell> front_buffer_;

  // Back buffer (being rendered to)
  gc_vector_t<Cell> back_buffer_;

  // Dirty region (cells that changed between buffers)
  std::optional<Rect> dirty_region_;

  // Default cell (for clearing)
  Cell default_cell_;

  // Helper: Get linear index from (row, col)
  [[nodiscard]] size_t index (int row, int col) const noexcept
  {
    return static_cast<size_t> (row * cols_ + col);
  }

  // Helper: Expand dirty region to include cell
  void expand_dirty (int row, int col) noexcept;

public:
  /**
   * Construct grid with specified dimensions
   *
   * @param rows Number of rows
   * @param cols Number of columns
   */
  Grid (int rows, int cols);

  // Delete copy constructor (expensive operation)
  Grid (const Grid &) = delete;
  Grid &operator= (const Grid &) = delete;

  // Allow move semantics
  Grid (Grid &&) noexcept = default;
  Grid &operator= (Grid &&) noexcept = default;

  /**
   * Get grid dimensions
   */
  [[nodiscard]] int rows () const noexcept { return rows_; }

  [[nodiscard]] int cols () const noexcept { return cols_; }

  /**
   * Resize grid (clears all content)
   *
   * @param rows New number of rows
   * @param cols New number of columns
   */
  void resize (int rows, int cols);

  /**
   * Set cell in back buffer
   *
   * @param row Row index (0-based)
   * @param col Column index (0-based)
   * @param cell Cell to set
   * @return true if cell was set, false if out of bounds
   */
  [[nodiscard]] bool set_cell (int row, int col, const Cell &cell);

  /**
   * Get cell from front buffer (currently displayed)
   *
   * @param row Row index
   * @param col Column index
   * @return Cell at position, or nullopt if out of bounds
   */
  [[nodiscard]] std::optional<Cell> get_cell (int row, int col) const;

  /**
   * Get cell from back buffer (being rendered)
   *
   * @param row Row index
   * @param col Column index
   * @return Cell at position, or nullopt if out of bounds
   */
  [[nodiscard]] std::optional<Cell> get_back_cell (int row,
						   int col) const;

  /**
   * Clear entire back buffer with default cell
   */
  void clear ();

  /**
   * Clear region of back buffer
   *
   * @param row Starting row
   * @param col Starting column
   * @param rows Number of rows to clear
   * @param cols Number of columns to clear
   */
  void clear_region (int row, int col, int rows, int cols);

  /**
   * Swap front and back buffers (present rendered frame)
   *
   * This makes the back buffer visible and prepares for next frame.
   * Updates dirty region tracking.
   */
  void swap_buffers ();

  /**
   * Get dirty region (cells that changed since last swap)
   *
   * @return Dirty region, or nullopt if nothing changed
   */
  [[nodiscard]] std::optional<Rect> dirty_region () const noexcept
  {
    return dirty_region_;
  }

  /**
   * Check if grid has any dirty cells
   */
  [[nodiscard]] bool is_dirty () const noexcept
  {
    return dirty_region_.has_value ();
  }

  /**
   * Mark entire grid as dirty
   */
  void mark_all_dirty ();

  /**
   * Set default cell (used for clearing)
   */
  void set_default_cell (const Cell &cell) { default_cell_ = cell; }

  /**
   * Get default cell
   */
  [[nodiscard]] const Cell &default_cell () const noexcept
  {
    return default_cell_;
  }
};

} // namespace tui
} // namespace emacs
