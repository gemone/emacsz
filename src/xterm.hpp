// src/xterm.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#ifdef EMACS_USE_POSIX_TTY
#include <termios.h>
#endif

#include "terminal_concept.hpp"

namespace emacs
{

#ifdef EMACS_USE_POSIX_TTY

class PosixTtyBackend
{
private:
  bool initialized_ = false;
  CursorPosition cursor_ = { 0, 0 };
  bool raw_mode_enabled_ = false;

  // Output buffering
  std::string output_buffer_;

  // Terminal state preservation
  struct termios original_termios_;
  bool original_nonblock_ = false;

  // Input parsing state
  std::vector<char> input_queue_;

  // Mouse tracking state
  int mouse_last_x_ = -1;
  int mouse_last_y_ = -1;

  [[nodiscard]] bool enable_raw_mode () noexcept;
  void disable_raw_mode () noexcept;

  void append_output (std::string_view data) noexcept;
  void append_output (char c) noexcept;

  // Internal helpers for escape sequences
  void emit_sgr (const TerminalGlyph &glyph) noexcept;
  void emit_sgr_color (bool foreground,
		       const TerminalColor &color) noexcept;
  void reset_sgr () noexcept;

public:
  PosixTtyBackend () noexcept;
  ~PosixTtyBackend ();

  PosixTtyBackend (const PosixTtyBackend &) = delete;
  PosixTtyBackend &operator= (const PosixTtyBackend &) = delete;

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

  [[nodiscard]] std::pair<int, int> get_terminal_size () const noexcept;
  [[nodiscard]] InputEvent read_input () noexcept;
  void set_raw_mode (bool raw) noexcept;
  void flush () noexcept;
};

#else

// Stub implementation for non-POSIX platforms
class PosixTtyBackend
{
public:
  PosixTtyBackend () noexcept {}
  ~PosixTtyBackend () {}

  [[nodiscard]] bool
  init () noexcept
  {
    return false;
  }
  void
  cleanup () noexcept
  {
  }

  void
  write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
  {
    (void)glyphs;
  }
  void
  write_text (std::string_view text) noexcept
  {
    (void)text;
  }
  void
  clear_to_end (CursorPosition pos) noexcept
  {
    (void)pos;
  }
  void
  clear_frame () noexcept
  {
  }
  void
  clear_end_of_line (CursorPosition pos) noexcept
  {
    (void)pos;
  }

  void
  set_cursor_position (CursorPosition pos) noexcept
  {
    (void)pos;
  }
  [[nodiscard]] CursorPosition
  get_cursor_position () const noexcept
  {
    return { 0, 0 };
  }

  void
  insert_glyphs (CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept
  {
    (void)pos;
    (void)glyphs;
  }
  void
  delete_glyphs (CursorPosition pos, std::size_t n) noexcept
  {
    (void)pos;
    (void)n;
  }
  void
  insert_lines (CursorPosition pos, std::size_t n) noexcept
  {
    (void)pos;
    (void)n;
  }
  void
  delete_lines (CursorPosition pos, std::size_t n) noexcept
  {
    (void)pos;
    (void)n;
  }

  [[nodiscard]] bool
  supports_colors () const noexcept
  {
    return false;
  }
  [[nodiscard]] bool
  supports_truecolor () const noexcept
  {
    return false;
  }
  [[nodiscard]] bool
  supports_blinking_cursor () const noexcept
  {
    return false;
  }
  [[nodiscard]] bool
  supports_bracketed_paste () const noexcept
  {
    return false;
  }

  [[nodiscard]] std::pair<int, int>
  get_terminal_size () const noexcept
  {
    return { 0, 0 };
  }
  [[nodiscard]] InputEvent
  read_input () noexcept
  {
    return {};
  }
  void
  set_raw_mode (bool raw) noexcept
  {
    (void)raw;
  }
  void
  flush () noexcept
  {
  }
};

#endif

static_assert (TerminalBackend<PosixTtyBackend>);

} // namespace emacs
