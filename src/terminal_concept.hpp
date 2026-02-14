// src/terminal_concept.hpp
#pragma once

#include <concepts>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>

namespace emacs
{

struct TerminalColor
{
  uint8_t red;
  uint8_t green;
  uint8_t blue;
};

struct TerminalGlyph
{
  char32_t codepoint;
  uint32_t face_id;
  TerminalColor background;
  TerminalColor foreground;
  bool wide;
  bool padding;
  bool bold;
  bool italic;
  bool underline;
  bool inverse;
  bool blink;
};

struct CursorPosition
{
  int row;
  int col;
};

struct TerminalRect
{
  int top;
  int left;
  int bottom;
  int right;
};

struct TerminalFace
{
  TerminalColor foreground;
  TerminalColor background;
  bool bold;
  bool italic;
  bool underline;
  bool inverse;
  bool blink;
};

enum class InputEventType
{
  None,
  Key,
  Mouse,
  Resize,
  Error
};

enum class MouseButton
{
  None,
  Left,
  Right,
  Middle,
  WheelUp,
  WheelDown,
  Release
};

struct InputEvent
{
  InputEventType type = InputEventType::None;
  uint32_t key = 0;
  uint32_t ch = 0;
  uint8_t mod = 0;
  MouseButton button = MouseButton::None;
  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
};

template <typename T>
concept TerminalBackend
  = requires (T terminal, CursorPosition pos, std::string_view text,
	      std::span<TerminalGlyph> glyphs, std::size_t n,
	      bool flag) {
      { terminal.init () } -> std::same_as<bool>;
      { terminal.cleanup () } -> std::same_as<void>;

      { terminal.write_glyphs (glyphs) } -> std::same_as<void>;
      { terminal.write_text (text) } -> std::same_as<void>;
      { terminal.clear_to_end (pos) } -> std::same_as<void>;
      { terminal.clear_frame () } -> std::same_as<void>;
      { terminal.clear_end_of_line (pos) } -> std::same_as<void>;

      { terminal.set_cursor_position (pos) } -> std::same_as<void>;
      {
	terminal.get_cursor_position ()
      } -> std::same_as<CursorPosition>;

      { terminal.insert_glyphs (pos, glyphs) } -> std::same_as<void>;
      { terminal.delete_glyphs (pos, n) } -> std::same_as<void>;
      { terminal.insert_lines (pos, n) } -> std::same_as<void>;
      { terminal.delete_lines (pos, n) } -> std::same_as<void>;

      { terminal.supports_colors () } -> std::same_as<bool>;
      { terminal.supports_truecolor () } -> std::same_as<bool>;
      { terminal.supports_blinking_cursor () } -> std::same_as<bool>;
      { terminal.supports_bracketed_paste () } -> std::same_as<bool>;
      {
	terminal.get_terminal_size ()
      } -> std::same_as<std::pair<int, int>>;
      { terminal.read_input () } -> std::same_as<InputEvent>;
      { terminal.set_raw_mode (flag) } -> std::same_as<void>;
      { terminal.flush () } -> std::same_as<void>;
    };

} // namespace emacs
