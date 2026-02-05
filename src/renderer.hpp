#pragma once

#include <cstdint>
#include <string>
#include "allocator.hpp"
#include "containers.hpp"
#include "grid.hpp"

namespace emacs
{
namespace tui
{

struct Color
{
  uint8_t r;
  uint8_t g;
  uint8_t b;

  Color () : r (0), g (0), b (0) {}
  Color (uint8_t red, uint8_t green, uint8_t blue)
      : r (red), g (green), b (blue)
  {
  }

  bool operator== (const Color &other) const noexcept
  {
    return r == other.r && g == other.g && b == other.b;
  }

  bool operator!= (const Color &other) const noexcept
  {
    return !(*this == other);
  }
};

class Renderer
{
public:
  Renderer ();
  ~Renderer ();

  Renderer (const Renderer &) = delete;
  Renderer &operator= (const Renderer &) = delete;

  Renderer (Renderer &&) = default;
  Renderer &operator= (Renderer &&) = default;

  void render (const Grid &grid);

  void set_use_alternate_screen (bool enable) noexcept
  {
    use_alternate_screen_ = enable;
  }

  void clear_screen ();

  void show_cursor (bool show);
  void move_cursor (int row, int col);

  void flush ();

  const gc_string &output () const noexcept { return output_; }

  void reset_output () { output_.clear (); }

private:
  void emit_sgr_reset ();
  void emit_sgr_attributes (const CellAttributes &attrs);
  void emit_cursor_position (int row, int col);
  void emit_clear_screen ();
  void emit_show_cursor (bool show);

  void append (const char *str);
  void append (std::string_view str);
  void append_char (char ch);

  gc_string output_;
  CellAttributes current_attrs_;
  Color current_fg_;
  Color current_bg_;
  bool use_alternate_screen_;
  int last_cursor_row_;
  int last_cursor_col_;
};

}
}
