// src/haikuterm.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

#ifdef EMACS_USE_HAIKU
# include <interface/AppKit.h>
# include <interface/InterfaceKit.h>
# include <interface/StorageKit.h>
#endif

namespace emacs
{

class HaikuBackend
{
private:
#ifdef EMACS_USE_HAIKU
  BWindow *window_;
  BView *view_;
  BView *content_view_;
  bool initialized_;
  CursorPosition cursor_;
#else
  bool initialized_;
#endif

public:
  HaikuBackend () noexcept;
  ~HaikuBackend ();

  HaikuBackend (const HaikuBackend &) = delete;
  HaikuBackend &operator= (const HaikuBackend &) = delete;

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

static_assert (TerminalBackend<HaikuBackend>);

} // namespace emacs
