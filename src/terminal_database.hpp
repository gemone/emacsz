#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <unordered_map>

namespace emacs
{

struct TerminalCapabilities
{
  int colors;
  bool supports_bold;
  bool supports_italic;
  bool supports_underline;
  bool supports_blink;
  bool supports_reverse;
  bool supports_true_color;
  int max_colors;
  int pairs;
  int max_width;
  int max_height;
  bool has_status_line;
  bool has_cursor_address;
  bool has_color_mode;
  bool has_auto_right_margin;
  bool has_eat_newline_glitch;
};

struct EscapeSequences
{
  const char *cursor_home;
  const char *cursor_to_ll;
  const char *cursor_up;
  const char *cursor_down;
  const char *cursor_left;
  const char *cursor_right;
  const char *parm_up_cursor;
  const char *parm_down_cursor;
  const char *parm_left_cursor;
  const char *parm_right_cursor;
  const char *clear_screen;
  const char *clr_eol;
  const char *clr_eos;
  const char *clr_bol;
  const char *clear_margins;
  const char *set_a_foreground;
  const char *set_a_background;
  const char *set_foreground;
  const char *set_background;
  const char *pound_lock;
  const char *exit_attribute_mode;
  const char *enter_bold_mode;
  const char *exit_bold_mode;
  const char *enter_dim_mode;
  const char *exit_dim_mode;
  const char *enter_blink_mode;
  const char *exit_blink_mode;
  const char *enter_reverse_mode;
  const char *exit_reverse_mode;
  const char *enter_standout_mode;
  const char *exit_standout_mode;
  const char *enter_underline_mode;
  const char *exit_underline_mode;
  const char *enter_secure_mode;
  const char *exit_secure_mode;
  const char *enter_italics_mode;
  const char *exit_italics_mode;
  const char *set_color_pair;
};

class TerminalDatabase
{
public:
  static TerminalDatabase &instance ();

  [[nodiscard]] bool has_terminfo (std::string_view term) const;
  [[nodiscard]] const TerminalCapabilities &
  get_capabilities () const noexcept;
  [[nodiscard]] const EscapeSequences &
  get_escape_sequences () const noexcept;

  void detect_terminal ();
  void set_terminal_type (std::string_view term);

  [[nodiscard]] std::string_view get_term_type () const noexcept
  {
    return term_type_;
  }

  [[nodiscard]] bool is_vt100 () const noexcept;
  [[nodiscard]] bool is_xterm () const noexcept;
  [[nodiscard]] bool is_ansi () const noexcept;
  [[nodiscard]] bool is_screen () const noexcept;
  [[nodiscard]] bool is_tmux () const noexcept;
  [[nodiscard]] bool is_konsole () const noexcept;
  [[nodiscard]] bool is_gnome_terminal () const noexcept;
  [[nodiscard]] bool is_mintty () const noexcept;

private:
  TerminalDatabase () = default;
  ~TerminalDatabase () = default;

  void load_vt100_default ();
  void load_xterm_default ();
  void load_from_env ();

  std::string term_type_;
  TerminalCapabilities caps_;
  EscapeSequences esc_;

  static const std::unordered_map<std::string, TerminalCapabilities>
    builtin_caps_;
};

inline TerminalDatabase &
TerminalDatabase::instance ()
{
  static TerminalDatabase instance;
  return instance;
}

inline const TerminalCapabilities &
TerminalDatabase::get_capabilities () const noexcept
{
  return caps_;
}

inline const EscapeSequences &
TerminalDatabase::get_escape_sequences () const noexcept
{
  return esc_;
}

inline bool
TerminalDatabase::is_vt100 () const noexcept
{
  return term_type_.find ("vt100") != std::string::npos;
}

inline bool
TerminalDatabase::is_xterm () const noexcept
{
  return term_type_.find ("xterm") != std::string::npos;
}

inline bool
TerminalDatabase::is_ansi () const noexcept
{
  return term_type_.find ("ansi") != std::string::npos;
}

inline bool
TerminalDatabase::is_screen () const noexcept
{
  return term_type_.find ("screen") != std::string::npos;
}

inline bool
TerminalDatabase::is_tmux () const noexcept
{
  return term_type_.find ("tmux") != std::string::npos;
}

inline bool
TerminalDatabase::is_konsole () const noexcept
{
  return term_type_.find ("konsole") != std::string::npos;
}

inline bool
TerminalDatabase::is_gnome_terminal () const noexcept
{
  return term_type_.find ("gnome") != std::string::npos;
}

inline bool
TerminalDatabase::is_mintty () const noexcept
{
  return term_type_.find ("mintty") != std::string::npos;
}

}
