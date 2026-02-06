// emacs_redisplay_adapter.cpp - Redisplay pipeline integration

#include "emacs_redisplay_adapter.hpp"

#include <algorithm>

#ifndef EMACS_WINDOW_STRUCTS_DEFINED
struct window;
struct buffer;
struct glyph_matrix;
struct glyph_row;
# define EMACS_WINDOW_STRUCTS_DEFINED
# define EMACS_WINDOW_STRUCTS_DEFINED_LOCAL
#endif

#include "emacs_window_adapter.hpp"

#ifdef EMACS_WINDOW_STRUCTS_DEFINED_LOCAL
# undef EMACS_WINDOW_STRUCTS_DEFINED
# undef EMACS_WINDOW_STRUCTS_DEFINED_LOCAL
#endif

#ifndef EMACS_STRUCTS_DEFINED
struct face
{
  unsigned long foreground;
  unsigned long background;
};
#endif

namespace emacs
{
namespace tui
{

EmacsRedisplayAdapter::EmacsRedisplayAdapter ()
    : grid_ (0, 0), renderer_ (), display_adapter_ (),
      window_adapter_ (nullptr), window_adapter_alloc_ (),
      cursor_row_ (0), cursor_col_ (0), cursor_visible_ (true),
      initialized_ (false), redisplay_count_ (0), cells_updated_ (0)
{
}

EmacsRedisplayAdapter::~EmacsRedisplayAdapter () { shutdown (); }

[[nodiscard]] bool
EmacsRedisplayAdapter::init (int rows, int cols) noexcept
{
  if (rows <= 0 || cols <= 0)
    {
      return false;
    }

  grid_.resize (rows, cols);
  initialized_ = true;

  if (!window_adapter_)
    {
      window_adapter_ = window_adapter_alloc_.allocate (1);
      if (window_adapter_)
	{
	  new (window_adapter_) EmacsWindowAdapter ();
	}
    }

  return window_adapter_ != nullptr;
}

void
EmacsRedisplayAdapter::shutdown () noexcept
{
  if (window_adapter_)
    {
      window_adapter_->~EmacsWindowAdapter ();
      window_adapter_alloc_.deallocate (window_adapter_, 1);
      window_adapter_ = nullptr;
    }

  initialized_ = false;
}

void
EmacsRedisplayAdapter::redisplay_frame (struct frame *f)
{
  if (!initialized_ || !f)
    {
      return;
    }

  if (f->redisplay_needed)
    {
      grid_.mark_all_dirty ();
    }

  sync_all_windows (f);

  if (window_adapter_)
    {
      const char *text = "";
      if (f->root_window)
	{
	  auto dims
	    = window_adapter_->get_window_dimensions (f->root_window);
	  if (dims.height > 0)
	    {
	      int row = dims.top + dims.height - 1;
	      render_mode_line (f->root_window, text, row);
	    }
	}

      if (f->selected_window && f->selected_window != f->root_window)
	{
	  auto dims = window_adapter_->get_window_dimensions (
	    f->selected_window);
	  if (dims.height > 0)
	    {
	      int row = dims.top + dims.height - 1;
	      render_mode_line (f->selected_window, text, row);
	    }
	}
    }

  update_cursor_position (f);
  flush ();
  ++redisplay_count_;
}

void
EmacsRedisplayAdapter::update_window (struct frame *f,
				      struct window *w)
{
  if (!initialized_ || !f || !w || !window_adapter_)
    {
      return;
    }

  window_adapter_->sync_window_to_grid (w, grid_);

  auto dims = window_adapter_->get_window_dimensions (w);
  if (dims.width > 0 && dims.height > 0)
    {
      cells_updated_
	+= static_cast<size_t> (dims.width * dims.height);
    }
}

void
EmacsRedisplayAdapter::mark_frame_dirty (struct frame *f) noexcept
{
  if (!f)
    {
      return;
    }

  f->redisplay_needed = true;
  grid_.mark_all_dirty ();
}

void
EmacsRedisplayAdapter::write_glyphs (const struct glyph *glyphs,
				     const struct face *face, int len,
				     int row, int col)
{
  if (!initialized_ || !glyphs || len <= 0)
    {
      return;
    }

  int write_col = col;
  for (int i = 0; i < len; ++i)
    {
      if (write_col >= grid_.cols ())
	{
	  break;
	}

      display_adapter_.render_glyph (grid_, row, write_col,
				     &glyphs[i], face);
      ++write_col;
      ++cells_updated_;
    }
}

void
EmacsRedisplayAdapter::clear_end_of_line (int row, int col)
{
  if (!initialized_)
    {
      return;
    }

  const Cell &cell = grid_.default_cell ();
  for (int c = col; c < grid_.cols (); ++c)
    {
      (void) grid_.set_cell (row, c, cell);
      ++cells_updated_;
    }
}

void
EmacsRedisplayAdapter::clear_frame ()
{
  if (!initialized_)
    {
      return;
    }

  grid_.clear ();
  grid_.mark_all_dirty ();
}

void
EmacsRedisplayAdapter::set_cursor (int row, int col)
{
  cursor_row_ = row;
  cursor_col_ = col;
}

void
EmacsRedisplayAdapter::set_cursor_visible (bool visible)
{
  cursor_visible_ = visible;
}

void
EmacsRedisplayAdapter::render_mode_line (struct window *w,
					 const char *text, int row)
{
  if (!initialized_ || !text)
    {
      return;
    }

  int start_col = 0;
  int max_cols = grid_.cols ();

  if (window_adapter_ && w)
    {
      auto dims = window_adapter_->get_window_dimensions (w);
      start_col = dims.left;
      if (dims.width > 0)
	{
	  max_cols = std::min (grid_.cols (), dims.left + dims.width);
	}
    }

  CellAttributes attrs;
  attrs.flags = CellAttributes::REVERSE;

  int col = start_col;
  for (const char *p = text; *p && col < max_cols; ++p, ++col)
    {
      char utf8[2] = { *p, '\0' };
      Cell cell (std::string (utf8), attrs, 1);
      (void) grid_.set_cell (row, col, cell);
      ++cells_updated_;
    }

  for (; col < max_cols; ++col)
    {
      Cell cell (" ", attrs, 1);
      (void) grid_.set_cell (row, col, cell);
      ++cells_updated_;
    }
}

void
EmacsRedisplayAdapter::render_header_line (struct window *w,
					   const char *text, int row)
{
  render_mode_line (w, text, row);
}

void
EmacsRedisplayAdapter::resize (int rows, int cols)
{
  grid_.resize (rows, cols);
}

void
EmacsRedisplayAdapter::flush ()
{
  if (!initialized_)
    {
      return;
    }

  renderer_.render (grid_);
  grid_.swap_buffers ();

  if (cursor_visible_)
    {
      renderer_.move_cursor (cursor_row_, cursor_col_);
    }

  renderer_.flush ();
}

[[nodiscard]] bool
EmacsRedisplayAdapter::is_initialized () const noexcept
{
  return initialized_;
}

[[nodiscard]] int
EmacsRedisplayAdapter::frame_rows () const noexcept
{
  return grid_.rows ();
}

[[nodiscard]] int
EmacsRedisplayAdapter::frame_cols () const noexcept
{
  return grid_.cols ();
}

[[nodiscard]] size_t
EmacsRedisplayAdapter::redisplay_count () const noexcept
{
  return redisplay_count_;
}

[[nodiscard]] size_t
EmacsRedisplayAdapter::cells_updated () const noexcept
{
  return cells_updated_;
}

void
EmacsRedisplayAdapter::sync_all_windows (struct frame *f)
{
  if (!f)
    {
      return;
    }

  if (f->root_window)
    {
      update_window (f, f->root_window);
    }

  if (f->selected_window && f->selected_window != f->root_window)
    {
      update_window (f, f->selected_window);
    }
}

void
EmacsRedisplayAdapter::render_window_borders (struct frame *f)
{
  (void) f;
}

void
EmacsRedisplayAdapter::update_cursor_position (struct frame *f)
{
  if (!f)
    {
      return;
    }

  f->cursor_y = cursor_row_;
  f->cursor_x = cursor_col_;
}

} // namespace tui
} // namespace emacs

extern "C"
{
  [[nodiscard]] void *emacs_cxx_create_redisplay_adapter (void)
  {
    return new emacs::tui::EmacsRedisplayAdapter ();
  }

  void emacs_cxx_destroy_redisplay_adapter (void *adapter_ptr)
  {
    delete static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
  }

  [[nodiscard]] int emacs_cxx_init_redisplay (void *adapter_ptr,
					      int rows, int cols)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (!adapter)
      {
	return 0;
      }
    return adapter->init (rows, cols) ? 1 : 0;
  }

  void emacs_cxx_shutdown_redisplay (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->shutdown ();
      }
  }

  void emacs_cxx_redisplay_frame (void *adapter_ptr, void *frame_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    auto *frame = static_cast<struct frame *> (frame_ptr);
    if (adapter)
      {
	adapter->redisplay_frame (frame);
      }
  }

  void emacs_cxx_update_window (void *adapter_ptr, void *frame_ptr,
				void *window_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    auto *frame = static_cast<struct frame *> (frame_ptr);
    auto *window = static_cast<struct window *> (window_ptr);
    if (adapter)
      {
	adapter->update_window (frame, window);
      }
  }

  void emacs_cxx_write_glyphs (void *adapter_ptr, void *glyphs,
			       void *face, int len, int row, int col)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    auto *glyph_ptr = static_cast<struct glyph *> (glyphs);
    auto *face_ptr = static_cast<struct face *> (face);
    if (adapter)
      {
	adapter->write_glyphs (glyph_ptr, face_ptr, len, row, col);
      }
  }

  void emacs_cxx_clear_end_of_line (void *adapter_ptr, int row,
				    int col)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->clear_end_of_line (row, col);
      }
  }

  void emacs_cxx_clear_frame (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->clear_frame ();
      }
  }

  void emacs_cxx_set_cursor (void *adapter_ptr, int row, int col)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->set_cursor (row, col);
      }
  }

  void emacs_cxx_flush (void *adapter_ptr)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->flush ();
      }
  }

  void emacs_cxx_resize_frame (void *adapter_ptr, int rows, int cols)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    if (adapter)
      {
	adapter->resize (rows, cols);
      }
  }

  void emacs_cxx_render_mode_line (void *adapter_ptr,
				   void *window_ptr, const char *text,
				   int row)
  {
    auto *adapter = static_cast<emacs::tui::EmacsRedisplayAdapter *> (
      adapter_ptr);
    auto *window = static_cast<struct window *> (window_ptr);
    if (adapter)
      {
	adapter->render_mode_line (window, text, row);
      }
  }
}
