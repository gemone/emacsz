#pragma once

#include <cstddef>
#include "allocator.hpp"
#include "emacs_display_adapter.hpp"
#include "emacs_window_adapter.hpp"
#include "grid.hpp"
#include "renderer.hpp"

// Mock frame structure for standalone testing
#ifndef EMACS_FRAME_STRUCTS_DEFINED
struct frame
{
  int total_cols;
  int total_lines;
  int pixel_width;
  int pixel_height;
  struct window *root_window;
  struct window *selected_window;
  bool redisplay_needed;
  int cursor_x;
  int cursor_y;
  void *output_data;
};
#endif

namespace emacs
{
namespace tui
{

class EmacsWindowAdapter;

class EmacsRedisplayAdapter
{
public:
  EmacsRedisplayAdapter ();
  ~EmacsRedisplayAdapter ();

  EmacsRedisplayAdapter (const EmacsRedisplayAdapter &) = delete;
  EmacsRedisplayAdapter &operator= (const EmacsRedisplayAdapter &)
    = delete;
  EmacsRedisplayAdapter (EmacsRedisplayAdapter &&) = delete;
  EmacsRedisplayAdapter &operator= (EmacsRedisplayAdapter &&)
    = delete;

  // Initialize for a frame with given dimensions
  [[nodiscard]] bool init (int rows, int cols) noexcept;

  // Shutdown and release resources
  void shutdown () noexcept;

  // === Main Redisplay API ===

  // Full frame redisplay
  void redisplay_frame (struct frame *f);

  // Update a single window within the frame
  void update_window (struct frame *f, struct window *w);

  // Mark frame as needing redisplay
  void mark_frame_dirty (struct frame *f) noexcept;

  // === Terminal Output API (replaces term.c functions) ===

  // Write glyphs to the grid at current cursor position
  void write_glyphs (const struct glyph *glyphs,
		     const struct face *face, int len, int row,
		     int col);

  // Clear from cursor to end of line
  void clear_end_of_line (int row, int col);

  // Clear entire frame
  void clear_frame ();

  // Set cursor position
  void set_cursor (int row, int col);

  // Show/hide cursor
  void set_cursor_visible (bool visible);

  // === Mode Line / Status Bar ===

  // Render mode line for a window
  void render_mode_line (struct window *w, const char *text, int row);

  // Render header line for a window
  void render_header_line (struct window *w, const char *text,
			   int row);

  // === Frame Management ===

  // Resize frame grid
  void resize (int rows, int cols);

  // Flush rendered output to terminal
  void flush ();

  // === Accessors ===

  [[nodiscard]] Grid &grid () noexcept { return grid_; }
  [[nodiscard]] const Grid &grid () const noexcept { return grid_; }
  [[nodiscard]] Renderer &renderer () noexcept { return renderer_; }
  [[nodiscard]] const Renderer &renderer () const noexcept
  {
    return renderer_;
  }
  [[nodiscard]] bool is_initialized () const noexcept;
  [[nodiscard]] int frame_rows () const noexcept;
  [[nodiscard]] int frame_cols () const noexcept;

  // Statistics
  [[nodiscard]] size_t redisplay_count () const noexcept;
  [[nodiscard]] size_t cells_updated () const noexcept;

private:
  // Internal helpers
  void sync_all_windows (struct frame *f);
  void render_window_borders (struct frame *f);
  void update_cursor_position (struct frame *f);

  Grid grid_;
  Renderer renderer_;
  EmacsDisplayAdapter display_adapter_;
  EmacsWindowAdapter *window_adapter_;
  emacs_allocator<EmacsWindowAdapter> window_adapter_alloc_;

  int cursor_row_;
  int cursor_col_;
  bool cursor_visible_;
  bool initialized_;

  // Stats
  size_t redisplay_count_;
  size_t cells_updated_;
};

} // namespace tui
} // namespace emacs

extern "C"
{
  [[nodiscard]] void *emacs_cxx_create_redisplay_adapter (void);
  void emacs_cxx_destroy_redisplay_adapter (void *adapter_ptr);
  [[nodiscard]] int emacs_cxx_init_redisplay (void *adapter_ptr,
					      int rows, int cols);
  void emacs_cxx_shutdown_redisplay (void *adapter_ptr);
  void emacs_cxx_redisplay_frame (void *adapter_ptr, void *frame_ptr);
  void emacs_cxx_update_window (void *adapter_ptr, void *frame_ptr,
				void *window_ptr);
  void emacs_cxx_write_glyphs (void *adapter_ptr, void *glyphs,
			       void *face, int len, int row, int col);
  void emacs_cxx_clear_end_of_line (void *adapter_ptr, int row,
				    int col);
  void emacs_cxx_clear_frame (void *adapter_ptr);
  void emacs_cxx_set_cursor (void *adapter_ptr, int row, int col);
  void emacs_cxx_flush (void *adapter_ptr);
  void emacs_cxx_resize_frame (void *adapter_ptr, int rows, int cols);
  void emacs_cxx_render_mode_line (void *adapter_ptr,
				   void *window_ptr, const char *text,
				   int row);
}
