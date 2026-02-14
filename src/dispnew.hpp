#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace emacs
{

struct DisplayCell
{
  char32_t codepoint;
  uint32_t face_id;
  uint8_t background;
  uint8_t foreground;
  bool wide;
  bool padding;
};

struct DisplayLine
{
  int y;
  int x;
  std::vector<DisplayCell> cells;
};

struct DisplayMatrix
{
  int rows;
  int cols;
  std::vector<DisplayLine> lines;
};

class DisplayUpdate
{
public:
  DisplayUpdate () = default;
  ~DisplayUpdate () = default;

  void clear ();
  void resize (int rows, int cols);
  void write_cell (int row, int col, const DisplayCell &cell);
  void clear_to_eol (int row, int col);
  void clear_to_eos (int row, int col);
  void insert_lines (int row, int count);
  void delete_lines (int row, int count);
  void scroll_region (int top, int bottom, int lines);

  [[nodiscard]] const DisplayMatrix &get_matrix () const noexcept
  {
    return matrix_;
  }

  [[nodiscard]] bool needs_update () const noexcept
  {
    return needs_update_;
  }
  void mark_dirty () noexcept { needs_update_ = true; }
  void mark_clean () noexcept { needs_update_ = false; }

private:
  DisplayMatrix matrix_;
  bool needs_update_{ false };
};

class DisplayRenderer
{
public:
  static DisplayRenderer &instance ();

  void set_terminal_backend (class TerminalBackend *backend);

  void init ();
  void shutdown ();

  void update_display (const DisplayMatrix &matrix);
  void flush_updates ();

  [[nodiscard]] int get_rows () const noexcept;
  [[nodiscard]] int get_cols () const noexcept;

private:
  DisplayRenderer () = default;
  ~DisplayRenderer () = default;

  TerminalBackend *backend_{ nullptr };
  DisplayMatrix current_matrix_;
  DisplayMatrix desired_matrix_;
};

extern "C"
{
  int display_init_c ();
  int display_shutdown_c ();
  int display_update_c (int *rows, int *cols);
}

}
