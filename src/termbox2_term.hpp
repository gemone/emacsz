// src/termbox2_term.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

namespace emacs
{

class Termbox2Backend
{
private:
  bool initialized_;
  int width_;
  int height_;
  CursorPosition cursor_;
  bool raw_mode_enabled_;
  bool bracketed_paste_enabled_;

  struct tb_cell
  glyph_to_cell (const TerminalGlyph &glyph) const noexcept;

  [[nodiscard]] uint32_t
  color_to_termbox (const TerminalColor &color) const noexcept;

  [[nodiscard]] uint32_t
  attributes_to_termbox (bool bold, bool italic, bool underline,
			 bool inverse, bool blink) const noexcept;

public:
  Termbox2Backend () noexcept;
  ~Termbox2Backend ();

  Termbox2Backend (const Termbox2Backend &) = delete;
  Termbox2Backend &operator= (const Termbox2Backend &) = delete;

  [[nodiscard]] bool init () noexcept;
  void cleanup () noexcept;

  void write_glyphs (std::span<TerminalGlyph> glyphs) noexcept;
  void write_text (std::string_view text) noexcept;
  void clear_to_end (CursorPosition pos) noexcept;
  void clear_frame () noexcept;
  void clear_end_of_line (CursorPosition pos) noexcept;

  void set_cursor_position (CursorPosition pos) noexcept;
  [[nodiscard]] CursorPosition get_cursor_position () const noexcept;

  void insert_glyphs (CursorPosition pos,
		      std::span<TerminalGlyph> glyphs) noexcept;
  void delete_glyphs (CursorPosition pos, std::size_t n) noexcept;
  void insert_lines (CursorPosition pos, std::size_t n) noexcept;
  void delete_lines (CursorPosition pos, std::size_t n) noexcept;

  [[nodiscard]] bool supports_colors () const noexcept;
  [[nodiscard]] bool supports_truecolor () const noexcept;
  [[nodiscard]] bool supports_blinking_cursor () const noexcept;
  [[nodiscard]] bool supports_bracketed_paste () const noexcept;

  [[nodiscard]] std::pair<int, int>
  get_terminal_size () const noexcept;
  [[nodiscard]] InputEvent read_input () noexcept;
  void set_raw_mode (bool raw) noexcept;
  void flush () noexcept;

  void enable_bracketed_paste (bool enable) noexcept;
  void set_color (uint8_t fg, uint8_t bg = 7) noexcept;
  void set_truecolor (uint8_t r, uint8_t g, uint8_t b) noexcept;
  void set_attribute (bool bold, bool italic, bool underline,
		      bool inverse) noexcept;
};

static_assert (TerminalBackend<Termbox2Backend>);

} // namespace emacs
