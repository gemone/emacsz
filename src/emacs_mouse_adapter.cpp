// src/emacs_mouse_adapter.cpp
// Phase 5.6: Mouse Integration

#include "emacs_mouse_adapter.hpp"
#include <cstring>

namespace emacs
{
namespace tui
{

EmacsMouseAdapter::EmacsMouseAdapter ()
    : dragging_ (false), drag_start_row_ (0), drag_start_col_ (0),
      drag_current_row_ (0), drag_current_col_ (0),
      drag_window_ (nullptr), scroll_lines_ (3)
{
}

EmacsMouseAdapter::~EmacsMouseAdapter () = default;

struct window *
EmacsMouseAdapter::find_window_at (struct frame *f, int row,
				   int col) const
{
  if (!f)
    {
      return nullptr;
    }

  struct window *windows[2] = { f->selected_window, f->root_window };

  for (struct window *w : windows)
    {
      if (!w)
	{
	  continue;
	}

      auto dims = window_adapter_.get_window_dimensions (w);
      int left = dims.left;
      int top = dims.top;
      int right = left + dims.width;
      int bottom = top + dims.height;

      if (row >= top && row < bottom && col >= left && col < right)
	{
	  return w;
	}
    }

  return nullptr;
}

EmacsMouseAdapter::WindowCoords
EmacsMouseAdapter::terminal_to_window_coords (const struct window *w,
					      int term_row,
					      int term_col) const
{
  WindowCoords coords = { 0, 0 };

  if (!w)
    {
      return coords;
    }

  auto dims = window_adapter_.get_window_dimensions (w);
  coords.row = term_row - dims.top;
  coords.col = term_col - dims.left;

  return coords;
}

ptrdiff_t
EmacsMouseAdapter::terminal_to_buffer_pos (const struct window *w,
					   int term_row,
					   int term_col) const
{
  if (!w)
    {
      return 0;
    }

  auto dims = window_adapter_.get_window_dimensions (w);
  if (dims.width <= 0)
    {
      return 0;
    }

  WindowCoords coords
    = terminal_to_window_coords (w, term_row, term_col);
  ptrdiff_t window_start = window_adapter_.get_window_start (w);
  ptrdiff_t offset
    = static_cast<ptrdiff_t> (coords.row) * dims.width + coords.col;

  return window_start + offset;
}

struct input_event
EmacsMouseAdapter::translate_mouse_event (const MouseEvent &mouse,
					  struct frame *f)
{
  struct input_event emacs_event;
  std::memset (&emacs_event, 0, sizeof (struct input_event));
  emacs_event.kind = NO_EVENT;

  struct window *w = find_window_at (f, mouse.row, mouse.col);
  if (!w)
    {
      return emacs_event;
    }

  ptrdiff_t pos = terminal_to_buffer_pos (w, mouse.row, mouse.col);

  if (EmacsInputAdapter::is_wheel_event (mouse.button))
    {
      emacs_event.kind = WHEEL_EVENT;
      emacs_event.code
	= (mouse.button == MouseButton::WheelUp) ? 0 : 1;
    }
  else
    {
      emacs_event.kind = MOUSE_CLICK_EVENT;
      emacs_event.code
	= EmacsInputAdapter::mouse_button_to_code (mouse.button);

      if (mouse.type == MouseEventType::Press)
	{
	  emacs_event.modifiers |= down_modifier;
	}
      else if (mouse.type == MouseEventType::Release)
	{
	  emacs_event.modifiers |= click_modifier;
	}
      else if (mouse.type == MouseEventType::Drag
	       || mouse.type == MouseEventType::Move)
	{
	  emacs_event.modifiers |= drag_modifier;
	}
    }

  emacs_event.modifiers
    |= EmacsInputAdapter::modifiers_to_emacs (mouse.modifiers);

  emacs_event.x
    = reinterpret_cast<void *> (static_cast<intptr_t> (pos));
  emacs_event.y
    = reinterpret_cast<void *> (static_cast<intptr_t> (pos));
  emacs_event.frame_or_window = w;

  if (mouse.type == MouseEventType::Press)
    {
      begin_drag (mouse.row, mouse.col, w);
    }
  else if (mouse.type == MouseEventType::Drag
	   || mouse.type == MouseEventType::Move)
    {
      update_drag (mouse.row, mouse.col);
    }
  else if (mouse.type == MouseEventType::Release)
    {
      end_drag (mouse.row, mouse.col);
    }

  return emacs_event;
}

void
EmacsMouseAdapter::begin_drag (int row, int col, struct window *w)
{
  dragging_ = true;
  drag_start_row_ = row;
  drag_start_col_ = col;
  drag_current_row_ = row;
  drag_current_col_ = col;
  drag_window_ = w;
}

void
EmacsMouseAdapter::update_drag (int row, int col)
{
  if (!dragging_)
    {
      return;
    }

  drag_current_row_ = row;
  drag_current_col_ = col;
}

void
EmacsMouseAdapter::end_drag (int row, int col)
{
  if (!dragging_)
    {
      return;
    }

  drag_current_row_ = row;
  drag_current_col_ = col;
  dragging_ = false;
}

bool
EmacsMouseAdapter::is_dragging () const noexcept
{
  return dragging_;
}

EmacsMouseAdapter::DragRange
EmacsMouseAdapter::get_drag_range () const noexcept
{
  DragRange range = { 0, 0, nullptr };

  if (!drag_window_)
    {
      return range;
    }

  range.window = drag_window_;
  range.start_pos
    = terminal_to_buffer_pos (drag_window_, drag_start_row_,
			      drag_start_col_);
  range.end_pos
    = terminal_to_buffer_pos (drag_window_, drag_current_row_,
			      drag_current_col_);

  return range;
}

int
EmacsMouseAdapter::scroll_lines () const noexcept
{
  return scroll_lines_;
}

void
EmacsMouseAdapter::set_scroll_lines (int lines) noexcept
{
  if (lines > 0)
    {
      scroll_lines_ = lines;
    }
}

} // namespace tui
} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_mouse_adapter (void)
  {
    return new emacs::tui::EmacsMouseAdapter ();
  }

  void emacs_cxx_destroy_mouse_adapter (void *adapter_ptr)
  {
    delete static_cast<emacs::tui::EmacsMouseAdapter *> (adapter_ptr);
  }

  void emacs_cxx_translate_mouse (void *adapter_ptr, int button,
				  int type, int row, int col,
				  void *frame_ptr,
				  struct input_event *out_event)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsMouseAdapter *> (adapter_ptr);
    auto *frame = static_cast<struct frame *> (frame_ptr);

    if (!adapter || !out_event)
      {
	return;
      }

    emacs::tui::MouseEvent mouse;
    mouse.button = static_cast<emacs::tui::MouseButton> (button);
    mouse.type = static_cast<emacs::tui::MouseEventType> (type);
    mouse.row = row;
    mouse.col = col;
    mouse.modifiers = emacs::tui::KeyModifier::None;

    *out_event = adapter->translate_mouse_event (mouse, frame);
  }

  void *emacs_cxx_find_window_at (void *adapter_ptr, void *frame_ptr,
				  int row, int col)
  {
    auto *adapter
      = static_cast<emacs::tui::EmacsMouseAdapter *> (adapter_ptr);
    auto *frame = static_cast<struct frame *> (frame_ptr);

    if (!adapter)
      {
	return nullptr;
      }

    return adapter->find_window_at (frame, row, col);
  }
}
