// src/nsterm.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>

#include "terminal_concept.hpp"

#ifdef EMACS_USE_NSTERM
# include <sys/ioctl.h>
# include <termios.h>
# include <unistd.h>
#endif

namespace emacs
{

#ifdef EMACS_USE_NSTERM

class MacOSNativeBackend
{
private:
  bool initialized_;
  CursorPosition cursor_;
  bool raw_mode_;

  // Terminal state preservation
  struct termios original_termios_;
  bool original_nonblock_;

  // Output buffering
  std::string output_buffer_;

  // Input parsing state
  std::vector<char> input_queue_;

  // Terminal detection
  bool is_iterm_;
  bool is_apple_terminal_;

  [[nodiscard]] bool enable_raw_mode () noexcept;
  void disable_raw_mode () noexcept;

  void append_output (std::string_view data) noexcept;
  void flush_output () noexcept;

public:
  MacOSNativeBackend () noexcept;
  ~MacOSNativeBackend ();

  MacOSNativeBackend (const MacOSNativeBackend &) = delete;
  MacOSNativeBackend &operator= (const MacOSNativeBackend &) = delete;

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

// Stub implementation when EMACS_USE_NSTERM is not defined
class MacOSNativeBackend
{
private:
  bool initialized_;
  bool raw_mode_;
  CursorPosition cursor_;
  std::string output_buffer_;

public:
  MacOSNativeBackend () noexcept = default;
  ~MacOSNativeBackend () = default;

  MacOSNativeBackend (const MacOSNativeBackend &) = delete;
  MacOSNativeBackend &operator= (const MacOSNativeBackend &) = delete;

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

static_assert (TerminalBackend<MacOSNativeBackend>);

} // namespace emacs
