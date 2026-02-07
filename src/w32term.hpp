// src/w32term.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

#ifdef EMACS_USE_W32
# include <windows.h>
#endif

namespace emacs
{

#ifdef EMACS_USE_W32

class WindowsConsoleBackend
{
private:
  HANDLE hConsole_;
  HANDLE hInput_;
  DWORD original_mode_;
  bool initialized_;
  CursorPosition cursor_;
  bool raw_mode_;

  std::string output_buffer_;

  [[nodiscard]] bool enable_vt100 () noexcept;

  void append_output (std::string_view data) noexcept;
  void flush_output () noexcept;

public:
  WindowsConsoleBackend () noexcept;
  ~WindowsConsoleBackend ();

  WindowsConsoleBackend (const WindowsConsoleBackend &) = delete;
  WindowsConsoleBackend &operator= (const WindowsConsoleBackend &) = delete;

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

#else

// Stub implementation when EMACS_USE_W32 is not defined
class WindowsConsoleBackend
{
private:
  bool initialized_;
  bool raw_mode_;
  CursorPosition cursor_;
  std::string output_buffer_;

public:
  WindowsConsoleBackend () noexcept = default;
  ~WindowsConsoleBackend () = default;

  WindowsConsoleBackend (const WindowsConsoleBackend &) = delete;
  WindowsConsoleBackend &operator= (const WindowsConsoleBackend &) = delete;

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

#endif

static_assert (TerminalBackend<WindowsConsoleBackend>);

} // namespace emacs
