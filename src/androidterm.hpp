// src/androidterm.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

#ifdef EMACS_USE_ANDROID
# include <android/input.h>
# include <android/log.h>
# include <android/native_window.h>
#endif

namespace emacs
{

class AndroidBackend
{
private:
#ifdef EMACS_USE_ANDROID
  ANativeWindow *window_;
  AInputQueue *input_queue_;
  bool initialized_;
  CursorPosition cursor_;
#else
  bool initialized_;
#endif

public:
  AndroidBackend () noexcept;
  ~AndroidBackend ();

  AndroidBackend (const AndroidBackend &) = delete;
  AndroidBackend &operator= (const AndroidBackend &) = delete;

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
};

static_assert (TerminalBackend<AndroidBackend>);

} // namespace emacs
