#include "terminal_database.hpp"

#include <cstdlib>

namespace emacs
{

void
TerminalDatabase::detect_terminal ()
{
  load_from_env ();

  if (is_vt100 ())
    {
      load_vt100_default ();
    }
  else if (is_xterm ())
    {
      load_xterm_default ();
    }
  else
    {
      load_vt100_default ();
    }
}

void
TerminalDatabase::set_terminal_type (std::string_view term)
{
  term_type_ = term;
  detect_terminal ();
}

bool
TerminalDatabase::has_terminfo (std::string_view term) const
{
  return builtin_caps_.find (std::string (term))
	 != builtin_caps_.end ();
}

void
TerminalDatabase::load_vt100_default ()
{
  caps_ = { .colors = 8,
	    .supports_bold = true,
	    .supports_italic = false,
	    .supports_underline = true,
	    .supports_blink = false,
	    .supports_reverse = true,
	    .supports_true_color = false,
	    .max_colors = 8,
	    .pairs = 64,
	    .max_width = 132,
	    .max_height = 43,
	    .has_status_line = false,
	    .has_cursor_address = true,
	    .has_color_mode = false,
	    .has_auto_right_margin = true,
	    .has_eat_newline_glitch = false };

  esc_ = { .cursor_home = "\033[H",
	   .cursor_to_ll = "\033[H",
	   .cursor_up = "\033[A",
	   .cursor_down = "\033[B",
	   .cursor_left = "\033[D",
	   .cursor_right = "\033[C",
	   .parm_up_cursor = "\033[%p1%dA",
	   .parm_down_cursor = "\033[%p1%dB",
	   .parm_left_cursor = "\033[%p1%dD",
	   .parm_right_cursor = "\033[%p1%dC",
	   .clear_screen = "\033[H\033[J",
	   .clr_eol = "\033[K",
	   .clr_eos = "\033[J",
	   .clr_bol = "\033[1K",
	   .clear_margins = "\033[1;24r",
	   .set_a_foreground = "\033[3%?%p1%dm",
	   .set_a_background = "\033[4%?%p1%dm",
	   .set_foreground = "\033[3%?%p1%dm",
	   .set_background = "\033[4%?%p1%dm",
	   .pound_lock = "",
	   .exit_attribute_mode = "\033[0m",
	   .enter_bold_mode = "\033[1m",
	   .exit_bold_mode = "\033[22m",
	   .enter_dim_mode = "\033[2m",
	   .exit_dim_mode = "\033[22m",
	   .enter_blink_mode = "\033[5m",
	   .exit_blink_mode = "\033[25m",
	   .enter_reverse_mode = "\033[7m",
	   .exit_reverse_mode = "\033[27m",
	   .enter_standout_mode = "\033[7m",
	   .exit_standout_mode = "\033[27m",
	   .enter_underline_mode = "\033[4m",
	   .exit_underline_mode = "\033[24m",
	   .enter_secure_mode = "",
	   .exit_secure_mode = "",
	   .enter_italics_mode = "",
	   .exit_italics_mode = "",
	   .set_color_pair = "" };
}

void
TerminalDatabase::load_xterm_default ()
{
  load_vt100_default ();

  caps_.supports_true_color = true;
  caps_.colors = 256;
  caps_.max_colors = 16777216;
  caps_.supports_italic = true;
  caps_.max_width = 9999;
  caps_.max_height = 9999;

  esc_.set_a_foreground
    = "\033[%?%p1%{8}%{15}%lf%{25}%{45}%:%?%p1%{6}%{15}%lf%{25}%{45}%"
      ":%?%p1%{1}%{8}%e%{34}%{44}%;%p1%{3}%{4}%dm";
  esc_.set_a_background
    = "\033[%?%p1%{8}%{15}%lf%{25}%{45}%:%?%p1%{6}%{15}%lf%{25}%{45}%"
      ":%?%p1%{1}%{8}%e%{34}%{44}%;%p1%{4}%dm";
  esc_.enter_italics_mode = "\033[3m";
  esc_.exit_italics_mode = "\033[23m";
}

void
TerminalDatabase::load_from_env ()
{
  const char *term_env = std::getenv ("TERM");
  if (term_env)
    {
      term_type_ = term_env;
    }
  else
    {
      term_type_ = "vt100";
    }

  const char *colorterm_env = std::getenv ("COLORTERM");
  if (colorterm_env
      && (std::strcmp (colorterm_env, "truecolor") == 0
	  || std::strcmp (colorterm_env, "24bit") == 0))
    {
      caps_.supports_true_color = true;
      caps_.colors = 256;
      caps_.max_colors = 16777216;
    }
}

const std::unordered_map<std::string, TerminalCapabilities>
  TerminalDatabase::builtin_caps_{};

}
