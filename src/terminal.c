/* Functions related to terminal devices.
   Copyright (C) 2005-2026 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#include <config.h>

#include "lisp.h"
#include "character.h"
#include "frame.h"
#include "termchar.h"
#include "blockinput.h"
#include "termhooks.h"
#include "keyboard.h"

#if HAVE_STRUCT_UNIPAIR_UNICODE
# include <errno.h>
# include <linux/kd.h>
# include <sys/ioctl.h>
#endif

/* Chain of all terminals currently in use.  */
struct terminal *terminal_list;

/* The first unallocated terminal id.  */
static int next_terminal_id;

/* The initial terminal device, created by initial_term_init.  */
struct terminal *initial_terminal;

static void delete_initial_terminal (struct terminal *);

/* This setter is used only in this file, so it can be private.  */
static void
tset_param_alist (struct terminal *t, Lisp_Object val)
{
  t->param_alist = val;
}



void
ring_bell (struct frame *f)
{
  if (!NILP (Vring_bell_function))
    {
      Lisp_Object function;

      /* Temporarily set the global variable to nil
	 so that if we get an error, it stays nil
	 and we don't call it over and over.

	 We don't specbind it, because that would carefully
	 restore the bad value if there's an error
	 and make the loop of errors happen anyway.  */

      function = Vring_bell_function;
      Vring_bell_function = Qnil;

      call0 (function);

      Vring_bell_function = function;
    }
  else if (FRAME_TERMINAL (f)->ring_bell_hook)
    (*FRAME_TERMINAL (f)->ring_bell_hook) (f);
}

void
update_begin (struct frame *f)
{
  if (FRAME_TERMINAL (f)->update_begin_hook)
    (*FRAME_TERMINAL (f)->update_begin_hook) (f);
}

void
update_end (struct frame *f)
{
  if (FRAME_TERMINAL (f)->update_end_hook)
    (*FRAME_TERMINAL (f)->update_end_hook) (f);
}

/* Specify how many text lines, from the top of the window,
   should be affected by insert-lines and delete-lines operations.
   This, and those operations, are used only within an update
   that is bounded by calls to update_begin and update_end.  */

void
set_terminal_window (struct frame *f, int size)
{
  if (FRAME_TERMINAL (f)->set_terminal_window_hook)
    (*FRAME_TERMINAL (f)->set_terminal_window_hook) (f, size);
}

/* Move cursor to row/column position VPOS/HPOS.  HPOS/VPOS are
   frame-relative coordinates.  */

void
cursor_to (struct frame *f, int vpos, int hpos)
{
  struct terminal *term = FRAME_TERMINAL (f);
  if (term->cursor_to_hook)
    {
      int x, y;
#ifndef HAVE_ANDROID
      root_xy (f, hpos, vpos, &x, &y);
#else /* HAVE_ANDROID */
      x = hpos, y = vpos;
#endif /* !HAVE_ANDROID */
      term->cursor_to_hook (f, y, x);
    }
}

/* Similar but don't take any account of the wasted characters.  */

void
raw_cursor_to (struct frame *f, int row, int col)
{
  struct terminal *term = FRAME_TERMINAL (f);
  if (term->raw_cursor_to_hook)
    {
      int x, y;
#ifndef HAVE_ANDROID
      root_xy (f, col, row, &x, &y);
#else /* HAVE_ANDROID */
      x = col, y = row;
#endif /* !HAVE_ANDROID */
      term->raw_cursor_to_hook (f, y, x);
    }
}

/* Erase operations.  */

/* Clear from cursor to end of frame.  */
void
clear_to_end (struct frame *f)
{
  if (FRAME_TERMINAL (f)->clear_to_end_hook)
    (*FRAME_TERMINAL (f)->clear_to_end_hook) (f);
}

/* Clear entire frame.  */

void
clear_frame (struct frame *f)
{
  if (FRAME_TERMINAL (f)->clear_frame_hook)
    (*FRAME_TERMINAL (f)->clear_frame_hook) (f);
}

/* Clear from cursor to end of line.
   Assume that the line is already clear starting at column first_unused_hpos.

   Note that the cursor may be moved, on terminals lacking a `ce' string.  */

void
clear_end_of_line (struct frame *f, int first_unused_hpos)
{
  if (FRAME_TERMINAL (f)->clear_end_of_line_hook)
    (*FRAME_TERMINAL (f)->clear_end_of_line_hook) (f, first_unused_hpos);
}

/* Output LEN glyphs starting at STRING at the nominal cursor position.
   Advance the nominal cursor over the text.  */

void
write_glyphs (struct frame *f, struct glyph *string, int len)
{
  if (FRAME_TERMINAL (f)->write_glyphs_hook)
    (*FRAME_TERMINAL (f)->write_glyphs_hook) (f, string, len);
}

/* Insert LEN glyphs from START at the nominal cursor position.

   If start is zero, insert blanks instead of a string at start */

void
insert_glyphs (struct frame *f, struct glyph *start, int len)
{
  if (len <= 0)
    return;

  if (FRAME_TERMINAL (f)->insert_glyphs_hook)
    (*FRAME_TERMINAL (f)->insert_glyphs_hook) (f, start, len);
}

/* Delete N glyphs at the nominal cursor position. */

void
delete_glyphs (struct frame *f, int n)
{
  if (FRAME_TERMINAL (f)->delete_glyphs_hook)
    (*FRAME_TERMINAL (f)->delete_glyphs_hook) (f, n);
}

/* Insert N lines at vpos VPOS.  If N is negative, delete -N lines.  */

void
ins_del_lines (struct frame *f, int vpos, int n)
{
  if (FRAME_TERMINAL (f)->ins_del_lines_hook)
    (*FRAME_TERMINAL (f)->ins_del_lines_hook) (f, vpos, n);
}

/* Return the terminal object specified by TERMINAL.  TERMINAL may
   be a terminal object, a frame, or nil for the terminal device of
   the current frame.  If TERMINAL is neither from the above or the
   resulting terminal object is deleted, return NULL.  */

static struct terminal *
decode_terminal (Lisp_Object terminal)
{
  struct terminal *t;

  if (NILP (terminal))
    terminal = selected_frame;
  t = (TERMINALP (terminal)
       ? XTERMINAL (terminal)
       : FRAMEP (terminal) ? FRAME_TERMINAL (XFRAME (terminal)) : NULL);
  return t && t->name ? t : NULL;
}

/* Like above, but throw an error if TERMINAL is not valid or deleted.  */

struct terminal *
decode_live_terminal (Lisp_Object terminal)
{
  struct terminal *t = decode_terminal (terminal);

  if (!t)
    wrong_type_argument (Qterminal_live_p, terminal);
  return t;
}

/* Like decode_live_terminal, but ensure that the resulting terminal
   object refers to a text-based terminal device.  */

struct terminal *
decode_tty_terminal (Lisp_Object terminal)
{
  struct terminal *t = decode_live_terminal (terminal);

  return (t->type == output_termcap || t->type == output_msdos_raw) ? t : NULL;
}

/* Return an active (not suspended) text-based terminal device that uses
   the tty device with the given NAME, or NULL if the named terminal device
   is not opened.  */

struct terminal *
get_named_terminal (const char *name)
{
  struct terminal *t;

  eassert (name);

  for (t = terminal_list; t; t = t->next_terminal)
    {
      if ((t->type == output_termcap || t->type == output_msdos_raw)
          && !strcmp (t->display_info.tty->name, name)
          && TERMINAL_ACTIVE_P (t))
        return t;
    }
  return NULL;
}

/* Allocate basically initialized terminal.  */

static struct terminal *
allocate_terminal (void)
{
  return ALLOCATE_ZEROED_PSEUDOVECTOR (struct terminal, glyph_code_table,
				       PVEC_TERMINAL);
}

/* Create a new terminal object of TYPE and add it to the terminal list.  RIF
   may be NULL if this terminal type doesn't support window-based redisplay.  */

struct terminal *
create_terminal (enum output_method type, struct redisplay_interface *rif)
{
  struct terminal *terminal = allocate_terminal ();
  Lisp_Object terminal_coding, keyboard_coding;

  terminal->next_terminal = terminal_list;
  terminal_list = terminal;
  terminal->type = type;
  terminal->rif = rif;
  terminal->id = next_terminal_id++;

  terminal->keyboard_coding = xmalloc (sizeof (struct coding_system));
  terminal->terminal_coding = xmalloc (sizeof (struct coding_system));

  /* If default coding systems for the terminal and the keyboard are
     already defined, use them in preference to the defaults.  This is
     needed when Emacs runs in daemon mode.  */
  keyboard_coding = find_symbol_value (Qdefault_keyboard_coding_system);
  if (NILP (keyboard_coding)
      || BASE_EQ (keyboard_coding, Qunbound)
      || NILP (Fcoding_system_p (keyboard_coding)))
    keyboard_coding = Qno_conversion;
  terminal_coding = find_symbol_value (Qdefault_terminal_coding_system);
  if (NILP (terminal_coding)
      || BASE_EQ (terminal_coding, Qunbound)
      || NILP (Fcoding_system_p (terminal_coding)))
    terminal_coding = Qundecided;

  setup_coding_system (keyboard_coding, terminal->keyboard_coding);
  setup_coding_system (terminal_coding, terminal->terminal_coding);

  return terminal;
}

/* Low-level function to close all frames on a terminal, remove it
   from the terminal list and free its memory.  */

void
delete_terminal (struct terminal *terminal)
{
  Lisp_Object tail, frame;

  /* Protect against recursive calls.  delete_frame calls the
     delete_terminal_hook when we delete our last frame.  */
  if (!terminal->name)
    return;

  /* Protection while we are in inconsistent state.  */
  block_input ();
  xfree (terminal->name);
  terminal->name = NULL;

  /* Check for live frames that are still on this terminal.  */
  FOR_EACH_FRAME (tail, frame)
    {
      struct frame *f = XFRAME (frame);
      if (FRAME_LIVE_P (f) && f->terminal == terminal)
        {
	  /* Pass Qnoelisp rather than Qt.  */
          delete_frame (frame, Qnoelisp);
        }
    }

  delete_terminal_internal (terminal);
  unblock_input ();
}

void
delete_terminal_internal (struct terminal *terminal)
{
  struct terminal **tp;

  for (tp = &terminal_list; *tp != terminal; tp = &(*tp)->next_terminal)
    if (! *tp)
      emacs_abort ();
  *tp = terminal->next_terminal;

  xfree (terminal->keyboard_coding);
  terminal->keyboard_coding = NULL;
  xfree (terminal->terminal_coding);
  terminal->terminal_coding = NULL;

  if (terminal->kboard && --terminal->kboard->reference_count == 0)
    {
      delete_kboard (terminal->kboard);
      terminal->kboard = NULL;
    }
}

DEFUN ("delete-terminal", Fdelete_terminal, Sdelete_terminal, 0, 2, 0,
       doc: /* Delete TERMINAL by deleting all frames on it and closing the terminal.
TERMINAL may be a terminal object, a frame, or nil (meaning the
selected frame's terminal).

Normally, you may not delete a display if all other displays are suspended,
but if the second argument FORCE is non-nil, you may do so. */)
  (Lisp_Object terminal, Lisp_Object force)
{
  struct terminal *t = decode_terminal (terminal);

  if (!t)
    return Qnil;

  if (NILP (force))
    {
      struct terminal *p = terminal_list;
      while (p && (p == t || !TERMINAL_ACTIVE_P (p)))
	p = p->next_terminal;

      if (!p)
	error ("Attempt to delete the sole active display terminal");
    }

  if (NILP (Vrun_hooks))
    ;
  else if (EQ (force, Qnoelisp))
    pending_funcalls
      = Fcons (list3 (Qrun_hook_with_args,
		      Qdelete_terminal_functions, terminal),
	       pending_funcalls);
  else
    safe_calln (Qrun_hook_with_args, Qdelete_terminal_functions, terminal);

  if (t->delete_terminal_hook)
    (*t->delete_terminal_hook) (t);
  else
    delete_terminal (t);

  return Qnil;
}


DEFUN ("frame-terminal", Fframe_terminal, Sframe_terminal, 0, 1, 0,
       doc: /* Return the terminal that FRAME is displayed on.
If FRAME is nil, use the selected frame.

The terminal device is represented by its integer identifier.  */)
  (Lisp_Object frame)
{
  struct terminal *t = FRAME_TERMINAL (decode_live_frame (frame));

  if (!t)
    return Qnil;
  else
    {
      Lisp_Object terminal;
      XSETTERMINAL (terminal, t);
      return terminal;
    }
}

DEFUN ("terminal-live-p", Fterminal_live_p, Sterminal_live_p, 1, 1, 0,
       doc: /* Return non-nil if OBJECT is a terminal which has not been deleted.
Return nil if OBJECT is not a live display terminal.
OBJECT may be a terminal object, a frame, or nil (meaning the
selected frame's terminal).
If OBJECT is a live display terminal, return what sort of output
terminal it uses.  See the documentation of `framep' for possible
return values.  */)
  (Lisp_Object object)
{
  struct terminal *t = decode_terminal (object);

  if (!t)
    return Qnil;

  switch (t->type)
    {
    case output_initial: /* The initial frame is like a termcap frame. */
    case output_termcap:
      return Qt;
    case output_x_window:
      return Qx;
    case output_w32:
      return Qw32;
    case output_msdos_raw:
      return Qpc;
    case output_ns:
      return Qns;
    case output_pgtk:
      return Qpgtk;
    case output_haiku:
      return Qhaiku;
    case output_android:
      return Qandroid;
#ifdef HAVE_PROTO_UI
    case output_proto:
      return Qproto;
#endif
    default:
      emacs_abort ();
    }
}

DEFUN ("frame-initial-p", Fframe_initial_p, Sframe_initial_p, 0, 1, 0,
       doc: /* Return non-nil if FRAME is the initial frame.
That is, the initial text frame used internally during daemon mode,
batch mode, and the early stages of startup.
If FRAME is a terminal object, return non-nil if it holds
the initial frame.  FRAME defaults to the selected frame.  */)
  (Lisp_Object frame)
{
  if (NILP (frame))
    frame = selected_frame;
  if (FRAMEP (frame))
    {
      struct frame *f = XFRAME (frame);
      return FRAME_LIVE_P (f) && FRAME_INITIAL_P (f) ? Qt : Qnil;
    }
  struct terminal *t = decode_terminal (frame);
  return t && t->type == output_initial ? Qt : Qnil;
}

DEFUN ("terminal-list", Fterminal_list, Sterminal_list, 0, 0, 0,
       doc: /* Return a list of all terminal devices.  */)
  (void)
{
  Lisp_Object terminal, terminals = Qnil;
  struct terminal *t;

  for (t = terminal_list; t; t = t->next_terminal)
    {
      XSETTERMINAL (terminal, t);
      terminals = Fcons (terminal, terminals);
    }

  return terminals;
}

DEFUN ("terminal-name", Fterminal_name, Sterminal_name, 0, 1, 0,
       doc: /* Return the name of the terminal device TERMINAL.
It is not guaranteed that the returned value is unique among opened devices.

TERMINAL may be a terminal object, a frame, or nil (meaning the
selected frame's terminal). */)
  (Lisp_Object terminal)
{
  struct terminal *t = decode_live_terminal (terminal);

  return t->name ? build_string (t->name) : Qnil;
}



/* Set the value of terminal parameter PARAMETER in terminal D to VALUE.
   Return the previous value.  */

static Lisp_Object
store_terminal_param (struct terminal *t, Lisp_Object parameter, Lisp_Object value)
{
  Lisp_Object old_alist_elt = Fassq (parameter, t->param_alist);
  if (NILP (old_alist_elt))
    {
      tset_param_alist (t, Fcons (Fcons (parameter, value), t->param_alist));
      return Qnil;
    }
  else
    {
      Lisp_Object result = Fcdr (old_alist_elt);
      Fsetcdr (old_alist_elt, value);
      return result;
    }
}


DEFUN ("terminal-parameters", Fterminal_parameters, Sterminal_parameters, 0, 1, 0,
       doc: /* Return the parameter-alist of terminal TERMINAL.
The value is a list of elements of the form (PARM . VALUE), where PARM
is a symbol.

TERMINAL can be a terminal object, a frame, or nil (meaning the
selected frame's terminal).  */)
  (Lisp_Object terminal)
{
  return Fcopy_alist (decode_live_terminal (terminal)->param_alist);
}

DEFUN ("terminal-parameter", Fterminal_parameter, Sterminal_parameter, 2, 2, 0,
       doc: /* Return TERMINAL's value for parameter PARAMETER.
TERMINAL can be a terminal object, a frame, or nil (meaning the
selected frame's terminal).  */)
  (Lisp_Object terminal, Lisp_Object parameter)
{
  CHECK_SYMBOL (parameter);
  return Fcdr (Fassq (parameter, decode_live_terminal (terminal)->param_alist));
}

DEFUN ("set-terminal-parameter", Fset_terminal_parameter,
       Sset_terminal_parameter, 3, 3, 0,
       doc: /* Set TERMINAL's value for parameter PARAMETER to VALUE.
Return the previous value of PARAMETER.

TERMINAL can be a terminal object, a frame or nil (meaning the
selected frame's terminal).  */)
  (Lisp_Object terminal, Lisp_Object parameter, Lisp_Object value)
{
  return store_terminal_param (decode_live_terminal (terminal), parameter, value);
}

#if HAVE_STRUCT_UNIPAIR_UNICODE

/* Compute the glyph code table for T.  */

static void
calculate_glyph_code_table (struct terminal *t)
{
  Lisp_Object glyphtab = Qt;
  enum { initial_unipairs = 1000 };
  int entry_ct = initial_unipairs;
  struct unipair unipair_buffer[initial_unipairs];
  struct unipair *entries = unipair_buffer;
  struct unipair *alloced = 0;

  while (true)
    {
      int fd = fileno (t->display_info.tty->output);
      struct unimapdesc unimapdesc = { entry_ct, entries };
      if (ioctl (fd, GIO_UNIMAP, &unimapdesc) == 0)
	{
	  glyphtab = Fmake_char_table (Qnil, make_fixnum (-1));
	  for (int i = 0; i < unimapdesc.entry_ct; i++)
	    char_table_set (glyphtab, entries[i].unicode,
			    make_fixnum (entries[i].fontpos));
	  break;
	}
      if (errno != ENOMEM)
	break;
      entry_ct = unimapdesc.entry_ct;
      entries = alloced = xrealloc (alloced, entry_ct * sizeof *alloced);
    }

  xfree (alloced);
  t->glyph_code_table = glyphtab;
}
#endif

/* Return the glyph code in T of character CH, or -1 if CH does not
   have a font position in T, or nil if T does not report glyph codes.  */

Lisp_Object
terminal_glyph_code (struct terminal *t, int ch)
{
#if HAVE_STRUCT_UNIPAIR_UNICODE
  /* Heuristically assume that a terminal supporting glyph codes is in
     UTF-8 mode if and only if its coding system is UTF-8 (Bug#26396).  */
  if (t->type == output_termcap
      && t->terminal_coding->encoder == encode_coding_utf_8)
    {
      /* As a hack, recompute the table when CH is the maximum
	 character.  */
      if (NILP (t->glyph_code_table) || ch == MAX_CHAR)
	calculate_glyph_code_table (t);

      if (! EQ (t->glyph_code_table, Qt))
	return char_table_ref (t->glyph_code_table, ch);
    }
#endif

  return Qnil;
}

/* Initial frame has no device-dependent output data, but has
   face cache which should be freed when the frame is deleted.  */

static void
initial_free_frame_resources (struct frame *f)
{
  eassert (FRAME_INITIAL_P (f));
  free_frame_faces (f);
}

/* Create the bootstrap display terminal for the initial frame.
   Returns a terminal of type output_initial.  */

struct terminal *
init_initial_terminal (void)
{
  if (initialized || terminal_list || tty_list)
    emacs_abort ();

  initial_terminal = create_terminal (output_initial, NULL);
  initial_terminal->name = xstrdup ("initial_terminal");
  initial_terminal->kboard = initial_kboard;
  initial_terminal->delete_terminal_hook = &delete_initial_terminal;
  initial_terminal->delete_frame_hook = &initial_free_frame_resources;
  initial_terminal->defined_color_hook = &tty_defined_color; /* xfaces.c */
  /* Other hooks are NULL by default.  */

  return initial_terminal;
}

/* Deletes the bootstrap terminal device.
   Called through delete_terminal_hook. */

static void
delete_initial_terminal (struct terminal *terminal)
{
  if (terminal != initial_terminal)
    emacs_abort ();

  delete_terminal (terminal);
  initial_terminal = NULL;
}

#ifdef HAVE_PROTO_UI

extern int proto_ui_lifecycle_session_create (uint64_t *);
extern int proto_ui_terminal_create (uint64_t, uint64_t *);
extern int proto_ui_frame_create (uint64_t, uint64_t, uint64_t *);
extern int proto_ui_frame_destroy (uint64_t, uint64_t);
extern int proto_ui_terminal_destroy (uint64_t, uint64_t);
extern int proto_ui_frame_update_begin (uint64_t, uint64_t);
extern int proto_ui_frame_update_cancel (uint64_t, uint64_t);
extern int proto_ui_window_create (uint64_t, uint64_t, uint64_t *);
extern int proto_ui_window_geometry (uint64_t, uint64_t, uint64_t,
                                     int, int, int, int);
extern int proto_ui_frame_row (uint64_t, uint64_t, uint64_t,
                               uint32_t, uint32_t,
                               int, int, int, int, int, int, int, int);
#ifdef HAVE_WINDOW_SYSTEM
extern int proto_ui_frame_cursor (uint64_t, uint64_t, uint64_t,
                                  int, int, int, int,
                                  unsigned char, bool, bool);
#endif
extern int proto_ui_frame_damage (uint64_t, uint64_t,
                                  int, int, int, int);
extern int proto_ui_frame_flush (uint64_t, uint64_t, int, int);
extern int proto_ui_frame_update_count (uint64_t);

static struct terminal *proto_terminal;
static intmax_t proto_frame_count;

static void
proto_delete_frame (struct frame *frame)
{
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (output && output->frame_id != 0 && !output->destroy_sent)
    {
      output->destroy_sent = true;
      if (proto_ui_frame_destroy (output->session_id,
                                  output->frame_id) != 0)
        emacs_abort ();
    }
  xfree (output);
  FRAME_PROTO_OUTPUT (frame) = NULL;
}

/* Fdelete-terminal invokes this hook while the terminal is still live.  It
   deletes remaining proto frames first, marks the EUP terminal dead, and then
   lets generic terminal deletion reclaim Emacs-owned state.  */
static void
proto_delete_terminal (struct terminal *terminal)
{
  /* Ignore recursive deletion after the terminal is already dead.  */
  if (!terminal->name)
    return;

  /* Fdelete-terminal invokes this hook before generic deletion.  Delete any
     remaining proto frames first so EUP frame-destroy messages precede the
     EUP terminal-destroy transition.  */
  bool deleted_frame;
  do
    {
      deleted_frame = false;
      Lisp_Object tail, frame;
      FOR_EACH_FRAME (tail, frame)
        {
          struct frame *f = XFRAME (frame);
          if (FRAME_LIVE_P (f) && f->terminal == terminal)
            {
              delete_frame (frame, Qnoelisp);
              deleted_frame = true;
              break;
            }
        }
    }
  while (deleted_frame);

  if (proto_ui_terminal_destroy (terminal->proto_session_id,
                                 terminal->proto_terminal_id) != 0)
    emacs_abort ();
  delete_terminal (terminal);
  if (terminal == proto_terminal)
    proto_terminal = NULL;
}

/* Handler for signals raised while a lifecycle-only proto frame is built.
   An unfinished frame is not in Vframe_list; free its resources directly.  */
static Lisp_Object
proto_unwind_create_frame (Lisp_Object frame)
{
  struct frame *f = XFRAME (frame);
  if (!FRAME_LIVE_P (f))
    return Qnil;

  if (NILP (Fmemq (frame, Vframe_list)))
    {
      proto_delete_frame (f);
      free_glyphs (f);
      if (f->terminal)
        f->terminal->reference_count--;
      f->terminal = NULL;
    }
  return Qnil;
}

static void
proto_do_unwind_create_frame (Lisp_Object frame)
{
  proto_unwind_create_frame (frame);
}

static uint64_t
proto_window_id (struct frame *frame, struct window *window)
{
  if (WINDOW_PROTO_ID (window) != 0)
    return WINDOW_PROTO_ID (window);
  uint64_t id;
  if (proto_ui_window_create (FRAME_PROTO_OUTPUT (frame)->session_id,
                              FRAME_PROTO_OUTPUT (frame)->frame_id,
                              &id) != 0 || id == 0)
    return 0;
  WINDOW_PROTO_ID (window) = id;
  return id;
}

static void
proto_after_update_window_line (struct window *window,
                                struct glyph_row *row)
{
  struct frame *frame = XFRAME (WINDOW_FRAME (window));
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output || !output->update_active)
    return;
  uint64_t window_id = proto_window_id (frame, window);
  if (window_id == 0)
    return;
  uint32_t row_index = (uint32_t) MATRIX_ROW_VPOS (row,
                                                   window->desired_matrix);
  proto_ui_frame_row (output->session_id, output->frame_id, window_id,
                      row_index, 0, row->x, row->y,
                      row->pixel_width, row->height, row->ascent,
                      row->height - row->ascent, row->y + row->ascent,
                      row->visible_height);
}

static void
proto_update_window_begin (struct window *window)
{
  struct frame *frame = XFRAME (WINDOW_FRAME (window));
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output || output->frame_id == 0)
    return;
  uint64_t window_id = proto_window_id (frame, window);
  if (window_id == 0)
    return;
  if (proto_ui_window_geometry (output->session_id, window_id,
                                output->frame_id,
                                WINDOW_LEFT_PIXEL_EDGE (window),
                                WINDOW_TOP_PIXEL_EDGE (window),
                                WINDOW_PIXEL_WIDTH (window),
                                WINDOW_PIXEL_HEIGHT (window)) != 0)
    return;
  if (output->update_active)
    return;
  if (proto_ui_frame_update_begin (output->session_id, output->frame_id) != 0)
    return;
  output->update_active = true;
  output->capture_failed = false;
  output->window_update_seen = false;
}

static void
proto_record_frame_damage (struct frame *frame, int x, int y,
                           int width, int height)
{
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output || !output->update_active || width <= 0 || height <= 0)
    return;
  (void) proto_ui_frame_damage (output->session_id, output->frame_id,
                                x, y, width, height);
}

static void
proto_record_row_damage (struct window *window, struct glyph_row *row)
{
  if (!row || row->pixel_width <= 0 || row->height <= 0)
    return;
  proto_record_frame_damage (XFRAME (WINDOW_FRAME (window)),
                             WINDOW_LEFT_PIXEL_EDGE (window) + row->x,
                             WINDOW_TOP_PIXEL_EDGE (window) + row->y,
                             row->pixel_width, row->height);
}

static void
proto_record_scroll_damage (struct window *window, struct run *run)
{
  struct frame *frame = XFRAME (WINDOW_FRAME (window));
  int top = min (run->desired_y, run->current_y);
  int bottom = max (run->desired_y, run->current_y);
  int y = WINDOW_TOP_PIXEL_EDGE (window) + top;

  if (run->height <= 0 || bottom > INT_MAX - run->height
      || y > INT_MAX - (run->height + (bottom - top)))
    return;
  proto_record_frame_damage (frame, WINDOW_LEFT_PIXEL_EDGE (window), y,
                             WINDOW_PIXEL_WIDTH (window),
                             run->height + (bottom - top));
}

static void
proto_update_window_end (struct window *window, bool cursor_on_p,
                         bool mouse_face_overwritten_p)
{
  struct frame *frame = XFRAME (WINDOW_FRAME (window));
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  (void) window;
  (void) cursor_on_p;
  (void) mouse_face_overwritten_p;
  if (output && output->update_active)
    output->window_update_seen = true;
}

#ifdef HAVE_WINDOW_SYSTEM

static void
proto_write_glyphs (struct window *window, struct glyph_row *row,
                    struct glyph *string, enum glyph_row_area area, int len)
{
  /* The generic path advances the output cursor and invalidates an
     overwritten physical cursor; RIF draw/clear hooks capture damage.  */
  gui_write_glyphs (window, row, string, area, len);
}

static void
proto_insert_glyphs (struct window *window, struct glyph_row *row,
                     struct glyph *start, enum glyph_row_area area, int len)
{
  /* Preserve the generic cursor/shift semantics; shift and draw hooks
     capture the affected frame rectangles.  */
  gui_insert_glyphs (window, row, start, area, len);
}

static void
proto_clear_end_of_line (struct window *window, struct glyph_row *row,
                         enum glyph_row_area area, int x)
{
  (void) area;
  (void) x;
  proto_record_row_damage (window, row);
}

static void
proto_scroll_run (struct window *window, struct run *run)
{
  proto_record_scroll_damage (window, run);
}

static void
proto_clear_window_mouse_face (struct window *window)
{
  (void) window;
}

static void
proto_get_glyph_overhangs (struct glyph *glyph, struct frame *frame,
                           int *left, int *right)
{
  gui_get_glyph_overhangs (glyph, frame, left, right);
}

static void
proto_fix_overlapping_area (struct window *window, struct glyph_row *row,
                            enum glyph_row_area area, int overlaps)
{
  (void) area;
  (void) overlaps;
  proto_record_row_damage (window, row);
}

static void
proto_draw_fringe_bitmap (struct window *window, struct glyph_row *row,
                          struct draw_fringe_bitmap_params *p)
{
  (void) row;
  int height = p->h;
  if (p->dh > 0 && height <= INT_MAX - p->dh)
    height += p->dh;
  proto_record_frame_damage (XFRAME (WINDOW_FRAME (window)),
                             p->x, p->y, p->wd, height);
}

static void
proto_define_fringe_bitmap (int which, unsigned short *bits, int h, int wd)
{
  (void) which;
  (void) bits;
  (void) h;
  (void) wd;
}

static void
proto_destroy_fringe_bitmap (int which)
{
  (void) which;
}

static void
proto_draw_glyph_string (struct glyph_string *s)
{
  proto_record_frame_damage (s->f, s->x, s->y, s->width, s->height);
}

static void
proto_define_frame_cursor (struct frame *frame, Emacs_Cursor cursor)
{
  (void) frame;
  (void) cursor;
}

static void
proto_clear_frame_area (struct frame *frame, int x, int y,
                        int width, int height)
{
  proto_record_frame_damage (frame, x, y, width, height);
}

static void
proto_clear_under_internal_border (struct frame *frame)
{
  proto_record_frame_damage (frame, 0, 0, FRAME_PIXEL_WIDTH (frame),
                             FRAME_PIXEL_HEIGHT (frame));
}

static void
proto_draw_vertical_window_border (struct window *window, int x,
                                   int y0, int y1)
{
  proto_record_frame_damage (XFRAME (WINDOW_FRAME (window)), x,
                             min (y0, y1), 1, max (y0, y1) - min (y0, y1));
}

static void
proto_draw_window_divider (struct window *window, int x0, int x1,
                           int y0, int y1)
{
  proto_record_frame_damage (XFRAME (WINDOW_FRAME (window)),
                             min (x0, x1), min (y0, y1),
                             max (x1, x0) - min (x1, x0),
                             max (y1, y0) - min (y1, y0));
}

static void
proto_shift_glyphs_for_insert (struct frame *frame, int x, int y,
                               int width, int height, int shift_by)
{
  if (width > 0 && shift_by > 0 && width <= INT_MAX - shift_by)
    proto_record_frame_damage (frame, x, y, width + shift_by, height);
  else
    proto_record_frame_damage (frame, x, y, width, height);
}

static void
proto_show_hourglass (struct frame *frame)
{
  (void) frame;
}

static void
proto_hide_hourglass (struct frame *frame)
{
  (void) frame;
}

static void
proto_draw_window_cursor (struct window *window,
                          struct glyph_row *glyph_row,
                          int x, int y,
                          enum text_cursor_kinds cursor_type,
                          int cursor_width, bool on_p, bool active_p)
{
  struct frame *frame = XFRAME (WINDOW_FRAME (window));
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output || !output->update_active)
    return;
  uint64_t window_id = proto_window_id (frame, window);
  if (window_id == 0)
    return;
  (void) glyph_row;
  proto_ui_frame_cursor (output->session_id, output->frame_id, window_id,
                         x, y, cursor_width, FRAME_LINE_HEIGHT (frame),
                         (unsigned char) cursor_type, on_p, active_p);
}

#endif

static void
proto_flush_display (struct frame *frame)
{
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output || !output->update_active)
    return;
  if (!output->window_update_seen)
    {
      proto_ui_frame_update_cancel (output->session_id, output->frame_id);
      output->update_active = false;
      output->capture_failed = true;
      return;
    }
  int rc = proto_ui_frame_flush (output->session_id, output->frame_id,
                                 FRAME_PIXEL_WIDTH (frame),
                                 FRAME_PIXEL_HEIGHT (frame));
  output->update_active = false;
  if (rc != 0)
    {
      proto_ui_frame_update_cancel (output->session_id, output->frame_id);
      output->capture_failed = true;
    }
}

static struct redisplay_interface proto_redisplay_interface = {
  .update_window_begin_hook = proto_update_window_begin,
  .after_update_window_line_hook = proto_after_update_window_line,
#ifdef HAVE_WINDOW_SYSTEM
  .frame_parm_handlers = NULL,
  .produce_glyphs = gui_produce_glyphs,
  .write_glyphs = proto_write_glyphs,
  .insert_glyphs = proto_insert_glyphs,
  .clear_end_of_line = proto_clear_end_of_line,
  .scroll_run_hook = proto_scroll_run,
#endif
  .update_window_end_hook = proto_update_window_end,
  .flush_display = proto_flush_display,
#ifdef HAVE_WINDOW_SYSTEM
  .clear_window_mouse_face = proto_clear_window_mouse_face,
  .get_glyph_overhangs = proto_get_glyph_overhangs,
  .fix_overlapping_area = proto_fix_overlapping_area,
  .draw_fringe_bitmap = proto_draw_fringe_bitmap,
  .define_fringe_bitmap = proto_define_fringe_bitmap,
  .destroy_fringe_bitmap = proto_destroy_fringe_bitmap,
  /* Overhangs are renderer-specific; W4c metadata capture does not render.  */
  .compute_glyph_string_overhangs = NULL,
  .draw_glyph_string = proto_draw_glyph_string,
  .define_frame_cursor = proto_define_frame_cursor,
  .clear_frame_area = proto_clear_frame_area,
  .clear_under_internal_border = proto_clear_under_internal_border,
  .draw_window_cursor = proto_draw_window_cursor,
  .draw_vertical_window_border = proto_draw_vertical_window_border,
  .draw_window_divider = proto_draw_window_divider,
  .shift_glyphs_for_insert = proto_shift_glyphs_for_insert,
  .show_hourglass = proto_show_hourglass,
  .hide_hourglass = proto_hide_hourglass,
  .default_font_parameter = NULL,
#endif
};

static void
proto_capture_frame_update (struct frame *frame)
{
  struct frame *f = frame;
  struct proto_output *output = FRAME_PROTO_OUTPUT (frame);
  if (!output)
    error ("proto-ui frame is not initialized");
  if (proto_ui_frame_update_begin (output->session_id,
                                   output->frame_id) != 0)
    error ("proto-ui frame update begin failed");
  output->update_active = true;
  output->capture_failed = false;
  output->window_update_seen = true;
  struct window *window = XWINDOW (f->root_window);
  uint64_t window_id = proto_window_id (f, window);
  if (window_id != 0
      && proto_ui_frame_row (output->session_id, output->frame_id, window_id,
                             0, 0, 0, 0, FRAME_PIXEL_WIDTH (f),
                             FRAME_LINE_HEIGHT (f), FRAME_LINE_HEIGHT (f), 0,
                             FRAME_LINE_HEIGHT (f), FRAME_LINE_HEIGHT (f)) != 0)
    {
      output->update_active = false;
      proto_ui_frame_update_cancel (output->session_id, output->frame_id);
      error ("proto-ui frame row capture failed");
    }
  int rc = proto_ui_frame_flush (output->session_id, output->frame_id,
                                 FRAME_PIXEL_WIDTH (frame),
                                 FRAME_PIXEL_HEIGHT (frame));
  output->update_active = false;
  if (rc != 0)
    {
      proto_ui_frame_update_cancel (output->session_id, output->frame_id);
      error ("proto-ui frame update flush failed");
    }
  if (output->capture_failed)
    {
      output->update_active = false;
      proto_ui_frame_update_cancel (output->session_id, output->frame_id);
      error ("proto-ui frame row capture exceeded limit");
    }
}

DEFUN ("proto-ui-capture-frame-update", Fproto_ui_capture_frame_update,
       Sproto_ui_capture_frame_update, 1, 1, 0,
       doc: /* Capture one synthetic FRAME_UPDATE for a headless proto FRAME.
The update carries W4b/W4c-a metadata with fallback damage and proves the
redisplay-to-EUP encoder path without rendering.  */)
  (Lisp_Object frame)
{
  struct frame *f = decode_live_frame (frame);
  if (!FRAME_PROTO_P (f))
    error ("FRAME is not a proto-ui frame");
  proto_capture_frame_update (f);
  uint64_t session_id = FRAME_PROTO_OUTPUT (f)->session_id;
  return make_uint (proto_ui_frame_update_count (session_id));
}

DEFUN ("proto-ui-create-terminal", Fproto_ui_create_terminal,
       Sproto_ui_create_terminal, 0, 0, 0,
       doc: /* Create the headless EUP terminal used by proto-ui.
Return the terminal object.  Repeated calls return the same live terminal.
Use `proto-ui-create-frame' to create a frame on this terminal.  */)
  (void)
{
  uint64_t session_id, terminal_id;

  if (proto_terminal && proto_terminal->name)
    {
      Lisp_Object terminal;
      XSETTERMINAL (terminal, proto_terminal);
      return terminal;
    }

  if (!proto_ui_registration_compatible (PROTO_UI_ABI_VERSION,
					 PROTO_UI_EUP_MAJOR_VERSION,
					 PROTO_UI_EUP_MINOR_VERSION))
    error ("proto-ui registration ABI is incompatible");
  if (proto_ui_lifecycle_session_create (&session_id) != 0)
    error ("proto-ui lifecycle session creation failed");
  if (proto_ui_terminal_create (session_id, &terminal_id) != 0)
    error ("proto-ui terminal lifecycle creation failed");

  proto_terminal = create_terminal (output_proto, NULL);
  proto_terminal->name = xstrdup ("proto");
  proto_terminal->kboard = allocate_kboard (Qproto);
  proto_terminal->kboard->reference_count++;
  proto_terminal->delete_terminal_hook = proto_delete_terminal;
  proto_terminal->delete_frame_hook = proto_delete_frame;
  proto_terminal->rif = &proto_redisplay_interface;
  proto_terminal->proto_session_id = session_id;
  proto_terminal->proto_terminal_id = terminal_id;

  Lisp_Object terminal;
  XSETTERMINAL (terminal, proto_terminal);
  return terminal;
}

DEFUN ("proto-ui-create-frame", Fproto_ui_create_frame,
       Sproto_ui_create_frame, 0, 0, 0,
       doc: /* Create a headless frame owned by proto-ui.
The frame has the `proto' output identity and a stable EUP frame ID.
It is invisible and intentionally has no face or render state yet.  W4b
captures metadata but does not render.  */)
  (void)
{
  if (!proto_terminal || !proto_terminal->name)
    error ("proto-ui terminal is not created");

  specpdl_ref count = SPECPDL_INDEX ();
  struct frame *f = make_frame (true);
  Lisp_Object frame;
  XSETFRAME (frame, f);

  f->output_method = output_proto;
  f->terminal = proto_terminal;
  FRAME_PROTO_OUTPUT (f) = xzalloc (sizeof *FRAME_PROTO_OUTPUT (f));
  f->terminal->reference_count++;

  /* Install cleanup before the first fallible EUP transition.  frame_id==0
     tells the hook that no protocol frame was created yet.  */
  FRAME_PROTO_OUTPUT (f)->session_id = proto_terminal->proto_session_id;
  FRAME_PROTO_OUTPUT (f)->terminal_id = proto_terminal->proto_terminal_id;
  FRAME_PROTO_OUTPUT (f)->frame_id = 0;
  FRAME_PROTO_OUTPUT (f)->frame_generation = 0;
  record_unwind_protect (proto_do_unwind_create_frame, frame);

  uint64_t frame_id;
  if (proto_ui_frame_create (proto_terminal->proto_session_id,
                             proto_terminal->proto_terminal_id,
                             &frame_id) != 0)
    error ("proto-ui frame lifecycle creation failed");
  FRAME_PROTO_OUTPUT (f)->frame_id = frame_id;
  FRAME_PROTO_OUTPUT (f)->frame_generation = 1;

  char name[32];
  sprintf (name, "proto-%"PRIdMAX, ++proto_frame_count);
  fset_name (f, build_string (name));
  frame_set_id_from_params (f, Qnil);
  SET_FRAME_VISIBLE (f, false);
  adjust_frame_size (f, 80 * FRAME_COLUMN_WIDTH (f),
                     24 * FRAME_LINE_HEIGHT (f), 5, true,
                     Qproto_frame);
  adjust_frame_glyphs (f);
  calculate_costs (f);

  f->can_set_window_size = true;
  f->after_make_frame = true;

  /* Officialize only after all fallible setup has succeeded.  */
  Vframe_list = Fcons (frame, Vframe_list);
  return unbind_to (count, frame);
}

#endif /* HAVE_PROTO_UI */

void
syms_of_terminal (void)
{
  DEFVAR_LISP ("ring-bell-function", Vring_bell_function,
    doc: /* Non-nil means call this function to ring the bell.
The function should accept no arguments.  */);
  Vring_bell_function = Qnil;

  DEFVAR_LISP ("delete-terminal-functions", Vdelete_terminal_functions,
    doc: /* Special hook run when a terminal is deleted.
Each function is called with argument, the terminal.
This may be called just before actually deleting the terminal,
or some time later.  */);
  Vdelete_terminal_functions = Qnil;

  DEFSYM (Qterminal_live_p, "terminal-live-p");
  DEFSYM (Qframe_initial_p, "frame-initial-p");
  DEFSYM (Qdelete_terminal_functions, "delete-terminal-functions");
  DEFSYM (Qrun_hook_with_args, "run-hook-with-args");

  defsubr (&Sdelete_terminal);
  defsubr (&Sframe_terminal);
  defsubr (&Sterminal_live_p);
  defsubr (&Sframe_initial_p);
  defsubr (&Sterminal_list);
  defsubr (&Sterminal_name);
  defsubr (&Sterminal_parameters);
  defsubr (&Sterminal_parameter);
  defsubr (&Sset_terminal_parameter);

#ifdef HAVE_PROTO_UI
  defsubr (&Sproto_ui_create_terminal);
  DEFSYM (Qproto_frame, "proto-frame");
  DEFSYM (Qproto_ui_capture_frame_update, "proto-ui-capture-frame-update");
  defsubr (&Sproto_ui_capture_frame_update);
  defsubr (&Sproto_ui_create_frame);
#endif

  Fprovide (intern_c_string ("multi-tty"), Qnil);
  DEFSYM (Qdefault_keyboard_coding_system, "default-keyboard-coding-system");
  DEFSYM (Qdefault_terminal_coding_system, "default-terminal-coding-system");
}
