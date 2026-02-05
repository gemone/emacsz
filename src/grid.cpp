// src/grid.cpp
// Grid system implementation

#include "grid.hpp"
#include <algorithm>

namespace emacs
{
namespace tui
{

Grid::Grid (int rows, int cols)
    : rows_ (rows), cols_ (cols),
      front_buffer_ (static_cast<size_t> (rows * cols),
		     default_cell_),
      back_buffer_ (static_cast<size_t> (rows * cols), default_cell_)
{
}

void
Grid::resize (int rows, int cols)
{
  rows_ = rows;
  cols_ = cols;

  size_t total_cells = static_cast<size_t> (rows * cols);
  front_buffer_.resize (total_cells);
  back_buffer_.resize (total_cells);

  clear ();
  mark_all_dirty ();
}

bool
Grid::set_cell (int row, int col, const Cell &cell)
{
  if (row < 0 || row >= rows_ || col < 0 || col >= cols_)
    {
      return false;
    }

  size_t idx = index (row, col);
  back_buffer_[idx] = cell;

  expand_dirty (row, col);
  return true;
}

std::optional<Cell>
Grid::get_cell (int row, int col) const
{
  if (row < 0 || row >= rows_ || col < 0 || col >= cols_)
    {
      return std::nullopt;
    }

  return front_buffer_[index (row, col)];
}

std::optional<Cell>
Grid::get_back_cell (int row, int col) const
{
  if (row < 0 || row >= rows_ || col < 0 || col >= cols_)
    {
      return std::nullopt;
    }

  return back_buffer_[index (row, col)];
}

void
Grid::clear ()
{
  std::fill (back_buffer_.begin (), back_buffer_.end (),
	     default_cell_);
  mark_all_dirty ();
}

void
Grid::clear_region (int row, int col, int nrows, int ncols)
{
  int end_row = std::min (row + nrows, rows_);
  int end_col = std::min (col + ncols, cols_);

  for (int r = row; r < end_row; ++r)
    {
      for (int c = col; c < end_col; ++c)
	{
	  if (r >= 0 && r < rows_ && c >= 0 && c < cols_)
	    {
	      back_buffer_[index (r, c)] = default_cell_;
	      expand_dirty (r, c);
	    }
	}
    }
}

void
Grid::swap_buffers ()
{
  dirty_region_.reset ();

  for (int r = 0; r < rows_; ++r)
    {
      for (int c = 0; c < cols_; ++c)
	{
	  size_t idx = index (r, c);
	  if (front_buffer_[idx] != back_buffer_[idx])
	    {
	      front_buffer_[idx] = back_buffer_[idx];
	      expand_dirty (r, c);
	    }
	}
    }
}

void
Grid::mark_all_dirty ()
{
  dirty_region_ = Rect{ 0, 0, rows_, cols_ };
}

void
Grid::expand_dirty (int row, int col) noexcept
{
  if (!dirty_region_)
    {
      dirty_region_ = Rect{ row, col, 1, 1 };
      return;
    }

  Rect &r = *dirty_region_;

  int min_row = std::min (r.row, row);
  int min_col = std::min (r.col, col);
  int max_row = std::max (r.row + r.rows, row + 1);
  int max_col = std::max (r.col + r.cols, col + 1);

  r.row = min_row;
  r.col = min_col;
  r.rows = max_row - min_row;
  r.cols = max_col - min_col;
}

} // namespace tui
} // namespace emacs
