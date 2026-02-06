// src/emacs_mouse_adapter.hpp
// Phase 5.6: Mouse Integration

#pragma once

#include "emacs_input_adapter.hpp"
#include "emacs_redisplay_adapter.hpp"
#include "emacs_window_adapter.hpp"

namespace emacs
{
namespace tui
{

class EmacsMouseAdapter
{
public:
  EmacsMouseAdapter ();
  ~EmacsMouseAdapter ();

  EmacsMouseAdapter (const EmacsMouseAdapter &) = delete;
  EmacsMouseAdapter &operator= (const EmacsMouseAdapter &) = delete;

  struct input_event translate_mouse_event (const MouseEvent &mouse,
					    struct frame *f);

  struct window *find_window_at (struct frame *f, int row,
				 int col) const;

  ptrdiff_t terminal_to_buffer_pos (const struct window *w,
				    int term_row, int term_col) const;

  struct WindowCoords
  {
    int row;
    int col;
  };

  WindowCoords terminal_to_window_coords (const struct window *w,
					  int term_row,
					  int term_col) const;

  void begin_drag (int row, int col, struct window *w);
  void update_drag (int row, int col);
  void end_drag (int row, int col);
  [[nodiscard]] bool is_dragging () const noexcept;

  struct DragRange
  {
    ptrdiff_t start_pos;
    ptrdiff_t end_pos;
    struct window *window;
  };

  [[nodiscard]] DragRange get_drag_range () const noexcept;

  [[nodiscard]] int scroll_lines () const noexcept;
  void set_scroll_lines (int lines) noexcept;

private:
  EmacsWindowAdapter window_adapter_;

  bool dragging_;
  int drag_start_row_;
  int drag_start_col_;
  int drag_current_row_;
  int drag_current_col_;
  struct window *drag_window_;
  int scroll_lines_;
};

} // namespace tui
} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_mouse_adapter (void);
  void emacs_cxx_destroy_mouse_adapter (void *adapter_ptr);
  void emacs_cxx_translate_mouse (void *adapter_ptr, int button,
				  int type, int row, int col,
				  void *frame_ptr,
				  struct input_event *out_event);
  void *emacs_cxx_find_window_at (void *adapter_ptr, void *frame_ptr,
				  int row, int col);
}
