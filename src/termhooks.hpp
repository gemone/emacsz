// src/termhooks.hpp
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "terminal_concept.hpp"

struct frame;
struct glyph;
struct input_event;
struct window;

namespace emacs
{

enum class OutputMethod : uint8_t
{
  Initial = 0,
  Termcap,
  XWindow,
  MSDOSRaw,
  Windows,
  NextStep,
  PGTK,
  Haiku,
  Android
};

enum class EventKind : uint8_t
{
  NoEvent = 0,
  ASCIIKeystroke,
  MultibyteCharKeystroke,
  NonASCIIDKeystroke,
  TimerEvent,
  MouseClick,
  MouseMovement,
  MenuBarActivate,
  MenuBarSelect,
  ModeLineClick,
  SwitchFrame,
  DeleteWindow,
  IconifyFrame,
  DeiconifyFrame,
  WindowChange,
  SettingsChanged,
  FocusIn,
  FocusOut,
  SaveSession,
  DragNDrop,
  UserSignal,
  LanguageChange,
  PanelUpdate,
  PanelLayout,
  IconifiedFrame,
  DragNDropFile,
  AppActivated,
  AppDeactivated,
  ScrollBarClick,
  ScrollBarDrag,
  ScrollBarValueChange,
  SelectionNotify,
  SelectionRequest,
  SelectionClearEvent,
  HelpEvent,
  Pollevent,
  ConfigChangedEvent,
  FileSelected,
  FontChange,
  KeyPress,
  KeyRelease
};

struct TerminalHooks
{
  OutputMethod output_method;

  std::function<void (struct frame *)> cursor_to;
  std::function<void (struct frame *, int, int)> raw_cursor_to;
  std::function<void (struct frame *)> clear_to_end;
  std::function<void (struct frame *)> clear_frame;
  std::function<void (struct frame *, int)> clear_end_of_line;

  std::function<void (struct frame *, struct glyph *, int)>
    write_glyphs;
  std::function<void (struct frame *, struct glyph *, int, int)>
    insert_glyphs;
  std::function<void (struct frame *, int)> delete_glyphs;

  std::function<void (struct frame *, int, int)> ins_del_lines;

  bool supports_colors;
  bool supports_blinking_cursor;

  bool defined_color;
  bool query_colors;

  std::function<void (struct frame *)> update_begin;
  std::function<void (struct frame *)> update_end;
  std::function<void (struct frame *, int)> set_terminal_window;

  std::function<int (struct frame *, struct input_event *)>
    read_socket;
  std::function<void (struct frame *)> delete_frame;
  std::function<void (struct frame *)> set_bitmap_icon;
  std::function<void (struct frame *, const char *)>
    implicit_set_name;

  bool has_multiple_sizes;

  std::function<bool ()> ring_bell;
  std::function<void ()> toggle_invisible_pointer;

  std::function<void ()> reset_terminal_modes;
  std::function<void ()> set_terminal_modes;

  int n_cols;
  int n_rows;
  int charset_list;

  struct frame *focus_frame;
};

template <typename T>
concept TerminalHookProvider
  = requires (T hooks, struct frame *f, struct glyph *g, int n) {
      { hooks.cursor_to (f) } -> std::same_as<void>;
      { hooks.write_glyphs (f, g, n) } -> std::same_as<void>;
      { hooks.clear_frame (f) } -> std::same_as<void>;
    };

} // namespace emacs
