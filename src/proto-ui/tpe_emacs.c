#include <config.h>

#include "keyboard.h"
#include "dispextern.h"
#include "lisp.h"
#include "termhooks.h"
#include "window.h"
#include "frame.h"
#include "termchar.h"
#include "buffer.h"
#include "tpe_core.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>

#include <signal.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern bool tty_defined_color (struct frame *, const char *, Emacs_Color *, bool, bool);
extern Lisp_Object get_char_property_and_overlay (Lisp_Object, Lisp_Object, Lisp_Object, Lisp_Object *);

typedef struct TpeEmacsHost {
  ProtoUiTerminalGroupV1 terminal;
  ProtoUiFrameGroupV1 frame;
  ProtoUiRedisplayGroupV1 redisplay;
  ProtoUiInputGroupV1 input;
  ProtoUiLifecycleGroupV1 lifecycle;
  ProtoUiPureRuntimeHostV1 table;
  struct terminal *terminal_object;
  ProtoUiIdentity identity;
  ProtoUiIdentity frame_identity;
  uint64_t session_id;
  uint64_t redisplay_generation;
  void *adapter_session;
  bool deleted;
} TpeEmacsHost;

static TpeEmacsHost tpe_host;
static ProtoUiTerminalProviderRegistration *tpe_registration;
static ProtoUiIdentity tpe_active_terminal;
static bool tpe_shutdown_registered;
static Mouse_HLInfo tpe_mouse_highlight;
static bool tpe_capture_acknowledged;
static bool tpe_mouse_highlight_acknowledged;
static int tpe_mouse_highlight_debug;
enum { TPE_INPUT_QUEUE_DEPTH = 16 };
static unsigned char tpe_input_buffer[TPE_INPUT_QUEUE_DEPTH * 48];
static size_t tpe_input_head;
static size_t tpe_input_count;
static size_t tpe_input_length;
static struct {
  int x, y;
  uint64_t timestamp;
  bool valid;
} tpe_mouse;

static ProtoUiPureRuntimeStatus unsupported3 (
    void *context, const void *first, const void *second) {
  (void)context; (void)first; (void)second;
  return PROTO_UI_RUNTIME_UNSUPPORTED;
}

static ProtoUiPureRuntimeStatus unsupported1 (void *context) {
  (void)context;
  return PROTO_UI_RUNTIME_UNSUPPORTED;
}

static ProtoUiPureRuntimeStatus host_create_terminal (
    void *context, const ProtoUiTerminalCreateRequest *request,
    ProtoUiIdentity *result) {
  TpeEmacsHost *host = context;
  if (host == NULL || host->terminal_object != NULL || result == NULL ||
      request == NULL || request->kind != 1 || request->requested_generation == 0)
    return PROTO_UI_RUNTIME_INVALID;

  struct terminal *terminal = create_terminal (output_provider, NULL);
  terminal->provider_data = host;
  terminal->provider_generation = (uint32_t)request->requested_generation;
  terminal->provider_reserved = 0;
  terminal->name = xstrdup ("terminal-provider");
  terminal->kboard = allocate_kboard (Qnil);
  terminal->defined_color_hook = tty_defined_color;
  if (current_kboard == initial_kboard)
    current_kboard = terminal->kboard;

  host->terminal_object = terminal;
  host->identity.id = (uint64_t)terminal->id + 1;
  host->identity.generation = request->requested_generation;
  host->deleted = false;
  *result = host->identity;
  return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus host_identity_operation (
    void *context, const ProtoUiIdentity *identity) {
  TpeEmacsHost *host = context;
  if (host == NULL || identity == NULL || host->terminal_object == NULL ||
      identity->id != host->identity.id ||
      identity->generation != host->identity.generation)
    return PROTO_UI_RUNTIME_INVALID;
  return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus host_delete_terminal (
    void *context, const ProtoUiIdentity *identity) {
  TpeEmacsHost *host = context;
  ProtoUiPureRuntimeStatus status = host_identity_operation (context, identity);
  if (status != PROTO_UI_RUNTIME_OK)
    return status;
  delete_terminal (host->terminal_object);
  host->terminal_object = NULL;
  host->deleted = true;
  return PROTO_UI_RUNTIME_OK;
}

static void initialize_host_table (TpeEmacsHost *host) {
  memset (host, 0, sizeof (*host));
  host->terminal = (ProtoUiTerminalGroupV1) {
    1, sizeof (ProtoUiTerminalGroupV1), host,
    host_create_terminal, host_identity_operation, host_delete_terminal
  };
  host->frame = (ProtoUiFrameGroupV1) {
    1, sizeof (ProtoUiFrameGroupV1), host,
    (ProtoUiFrameRegisterFn)unsupported3,
    (ProtoUiIdentityOperationFn)unsupported3,
    (ProtoUiFrameStateFn)unsupported3,
    (ProtoUiFrameGeometryFn)unsupported3
  };
  host->redisplay = (ProtoUiRedisplayGroupV1) {
    1, sizeof (ProtoUiRedisplayGroupV1), host,
    (ProtoUiCaptureBeginFn)unsupported3,
    (ProtoUiCaptureWindowFn)unsupported3,
    (ProtoUiCaptureRowFn)unsupported3,
    (ProtoUiCaptureRunFn)unsupported3,
    (ProtoUiCaptureCursorFn)unsupported3,
    (ProtoUiCaptureDamageFn)unsupported3,
    (ProtoUiCaptureFaceFn)unsupported3,
    (ProtoUiCaptureFontFn)unsupported3,
    (ProtoUiCaptureShapedRunFn)unsupported3,
    (ProtoUiCaptureImageDefineFn)unsupported3,
    (ProtoUiCaptureImageFragmentFn)unsupported3,
    (ProtoUiCaptureOperationFn)unsupported3,
    (ProtoUiCaptureOperationFn)unsupported3
  };
  host->input = (ProtoUiInputGroupV1) {
    1, sizeof (ProtoUiInputGroupV1), host,
    (ProtoUiInputDeliverFn)unsupported3,
    (ProtoUiInputResultFn)unsupported3,
    (ProtoUiCompletionFn)unsupported3
  };
  host->lifecycle = (ProtoUiLifecycleGroupV1) {
    1, sizeof (ProtoUiLifecycleGroupV1), host,
    (ProtoUiHeartbeatFn)unsupported3,
    (ProtoUiOperationFn)unsupported1,
    (ProtoUiDiagnosticFn)unsupported3,
    (ProtoUiOperationFn)unsupported1
  };
  host->table = (ProtoUiPureRuntimeHostV1) {
    1, sizeof (ProtoUiPureRuntimeHostV1), host,
    &host->terminal, &host->frame, &host->redisplay,
    &host->input, &host->lifecycle
  };
}

extern ProtoUiPureRuntimeStatus proto_ui_runtime_host_adapter_session_create (
    const ProtoUiPureRuntimeHostV1 *table, void **session);
extern ProtoUiPureRuntimeStatus proto_ui_runtime_host_adapter_session_activate (
    void *session, ProtoUiIdentity *terminal);
extern ProtoUiPureRuntimeStatus proto_ui_runtime_host_adapter_session_drain (
    void *session);
extern ProtoUiPureRuntimeStatus proto_ui_runtime_host_adapter_session_destroy (
    void *session);

static int provider_surface_fd = -1;
static pid_t provider_surface_pid = -1;

static bool provider_read_exact (int fd, void *buffer, size_t size) {
  unsigned char *bytes = buffer;
  size_t offset = 0;
  while (offset < size) {
    ssize_t count = read (fd, bytes + offset, size - offset);
    if (count < 0) continue;
    if (count == 0) return false;
    offset += (size_t)count;
  }
  return true;
}

static struct frame *provider_terminal_frame (void) {
  Lisp_Object tail, frame;
  FOR_EACH_FRAME (tail, frame)
    {
      struct frame *candidate = XFRAME (frame);
      if (FRAME_LIVE_P (candidate) &&
          candidate->terminal == tpe_host.terminal_object &&
          candidate->terminal->type == output_provider)
        return candidate;
    }
  return NULL;
}

static bool provider_update_mouse (int x, int y, uint64_t timestamp,
                                   bool motion) {
  struct frame *frame = provider_terminal_frame ();
  if (!frame || frame->terminal != tpe_host.terminal_object ||
      frame->terminal->type != output_provider)
    return false;
  tpe_mouse.x = x;
  tpe_mouse.y = y;
  tpe_mouse.timestamp = timestamp;
  tpe_mouse.valid = true;
  if (motion)
    {
      MOUSE_HL_INFO (frame)->mouse_face_defer = false;
      frame->mouse_moved = true;
      update_mouse_position (frame, x, y);
    }
  else
    frame->mouse_moved = false;
  return true;
}

static bool provider_resize_frame (int width, int height) {
  struct frame *frame = provider_terminal_frame ();
  if (width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
      !frame || frame->terminal != tpe_host.terminal_object ||
      frame->terminal->type != output_provider)
    return false;
  change_frame_size (frame, width, height, false, false, false);
  return true;
}

static bool provider_store_event (uint16_t kind, uint16_t flags,
                                  uint32_t modifiers, uint32_t code,
                                  int32_t x, int32_t y, uint64_t timestamp) {
  struct input_event event;
  EVENT_INIT (event);
  event.timestamp = (Time)timestamp;
  event.modifiers = modifiers;
  event.code = code;
  event.frame_or_window = selected_frame;

  if (kind == 0)
    event.kind = code < 0x80 ? ASCII_KEYSTROKE_EVENT : NON_ASCII_KEYSTROKE_EVENT;
  else if (kind == 1)
    event.kind = code < 0x80 ? ASCII_KEYSTROKE_EVENT
      : MULTIBYTE_CHAR_KEYSTROKE_EVENT;
  else if (kind == 2)
    {
      if (!provider_update_mouse (x, y, timestamp, false))
        return false;
      event.kind = MOUSE_CLICK_EVENT;
      event.modifiers |= (flags & 1) ? up_modifier : down_modifier;
      XSETINT (event.x, x);
      XSETINT (event.y, y);
    }
  else if (kind == 4)
    {
      if (!provider_update_mouse (x, y, timestamp, true))
        return false;
      return true;
    }
  else if (kind == 5)
    {
      if (!provider_update_mouse (x, y, timestamp, false))
        return false;
      event.kind = WHEEL_EVENT;
      event.modifiers |= code ? down_modifier : up_modifier;
      XSETINT (event.x, x);
      XSETINT (event.y, y);
    }
  else if (kind == 6)
    {
      if (!provider_update_mouse (x, y, timestamp, false))
        return false;
      event.kind = HORIZ_WHEEL_EVENT;
      event.modifiers |= code ? down_modifier : up_modifier;
      XSETINT (event.x, x);
      XSETINT (event.y, y);
    }
  else if (kind == 7 || kind == 8)
    event.kind = kind == 7 ? FOCUS_IN_EVENT : FOCUS_OUT_EVENT;
  else if (kind == 9)
    event.kind = DELETE_WINDOW_EVENT;
  else if (kind == 10)
    return provider_resize_frame (x, y);
  else
    return false;
  kbd_buffer_store_event (&event);
  return true;
}

static bool provider_decode_input (const unsigned char packet[48]) {
  uint16_t kind, flags;
  uint32_t modifiers, code;
  int32_t x, y;
  uint64_t timestamp;
  if (memcmp (packet, "TPEINP1", 8) != 0)
    return false;
  memcpy (&kind, packet + 8, sizeof kind);
  memcpy (&flags, packet + 10, sizeof flags);
  memcpy (&modifiers, packet + 12, sizeof modifiers);
  memcpy (&code, packet + 16, sizeof code);
  memcpy (&timestamp, packet + 24, sizeof timestamp);
  memcpy (&x, packet + 32, sizeof x);
  memcpy (&y, packet + 36, sizeof y);
  return provider_store_event (kind, flags, modifiers, code, x, y, timestamp);
}

static bool provider_read_acknowledgment (int fd, unsigned char expected);

static bool provider_read_input_byte (int fd, unsigned char *byte) {
  ssize_t count;
  do
    count = read (fd, byte, 1);
  while (count < 0 && errno == EINTR);
  return count == 1;
}

static bool provider_write_all (int fd, const void *buffer, size_t size) {
  const unsigned char *bytes = buffer;
  size_t offset = 0;
  while (offset < size) {
    ssize_t count = write (fd, bytes + offset, size - offset);
    if (count < 0) continue;
    offset += (size_t)count;
  }
  return true;
}

static bool launch_provider_surface (uint64_t id, uint64_t generation,
                                     uint64_t frame_id,
                                     uint64_t frame_generation) {
  int fds[2];
  if (socketpair (AF_UNIX, SOCK_STREAM, 0, fds) != 0)
    {
      perror ("terminal-provider socketpair");
      return false;
    }

  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init (&actions) != 0)
    {
      perror ("terminal-provider spawn actions");
      close (fds[0]); close (fds[1]);
      return false;
    }
  posix_spawn_file_actions_adddup2 (&actions, fds[1], 3);
  posix_spawn_file_actions_addclose (&actions, fds[0]);
  posix_spawn_file_actions_addclose (&actions, fds[1]);
  char *argv[] = {"./zig-out/bin/proto-ui-sdl3", "--provider-frame", NULL};
  pid_t pid;
  bool spawned = posix_spawn (&pid, "./zig-out/bin/proto-ui-sdl3", &actions,
                              NULL, argv, environ) == 0;
  posix_spawn_file_actions_destroy (&actions);
  close (fds[1]);
  if (!spawned)
    {
      perror ("terminal-provider posix_spawn");
      close (fds[0]);
      return false;
    }

  unsigned char wire[48];
  memcpy (wire, "TPESURF1", 8);
  memcpy (wire + 8, &id, sizeof (id));
  memcpy (wire + 16, &generation, sizeof (generation));
  memcpy (wire + 24, &frame_id, sizeof (frame_id));
  memcpy (wire + 32, &frame_generation, sizeof (frame_generation));
  uint32_t width = 960, height = 600;
  memcpy (wire + 40, &width, sizeof (width));
  memcpy (wire + 44, &height, sizeof (height));
  if (!provider_write_all (fds[0], wire, sizeof (wire)) ||
      !provider_read_input_byte (fds[0], &wire[0]) ||
      !provider_read_input_byte (fds[0], &wire[1]) ||
      wire[0] != 'O' || wire[1] != 'K')
    {
      perror ("terminal-provider handshake");
      kill (pid, SIGTERM);
      waitpid (pid, NULL, 0);
      close (fds[0]);
      return false;
    }
  fcntl (fds[0], F_SETFL, fcntl (fds[0], F_GETFL, 0) | O_NONBLOCK);
  provider_surface_fd = fds[0];
  provider_surface_pid = pid;
  return true;
}


typedef struct TpeWireRow {
  uint64_t window_id;
  uint32_t index;
  uint32_t flags;
  int32_t x, y, width, height;
  int32_t ascent, descent, baseline, visible_height;
} TpeWireRow;

typedef struct TpeWireRun {
  uint32_t run_id;
  uint32_t generation;
  uint64_t window_id;
  uint32_t row_index;
  uint32_t face_id;
  uint32_t face_generation;
  int32_t x, y, width, height;
  uint32_t text_length;
  unsigned char text[256];
} TpeWireRun;

typedef struct TpeWireCursor {
  uint64_t window_id;
  int32_t x, y, width, height;
  uint8_t kind;
  bool visible;
  bool active;
} TpeWireCursor;

typedef struct TpeWireFace {
  uint32_t face_id;
  uint32_t generation;
  uint8_t background[4];
} TpeWireFace;

typedef struct TpeWireHighlight {
  uint8_t flags;
  uint64_t window_id;
  uint32_t frame_generation;
  int32_t x, y, width, height;
  uint32_t face_id;
  uint32_t face_generation;
} TpeWireHighlight;

typedef struct TpeWireSnapshot {
  uint32_t frame_id;
  uint32_t frame_generation;
  uint64_t session_id;
  uint64_t redisplay_generation;
  int32_t width, height;
  const TpeWireRow *rows;
  size_t row_count;
  const TpeWireRun *runs;
  size_t run_count;
  TpeWireCursor cursor;
  const TpeWireFace *faces;
  size_t face_count;
  const TpeWireHighlight *highlights;
  size_t highlight_count;
} TpeWireSnapshot;

extern ProtoUiPureRuntimeStatus proto_ui_tpe_encode_snapshot (
    const TpeWireSnapshot *, unsigned char **, size_t *);
extern void proto_ui_tpe_free_snapshot (unsigned char *, size_t);

static bool tpe_utf8_put (unsigned char *text, size_t *length, unsigned int code) {
  if (*length >= 254)
    return false;
  if (code < 0x80)
    text[(*length)++] = (unsigned char)code;
  else if (code < 0x800)
    {
      text[(*length)++] = 0xc0 | (code >> 6);
      text[(*length)++] = 0x80 | (code & 0x3f);
    }
  else if (code < 0x10000)
    {
      text[(*length)++] = 0xe0 | (code >> 12);
      text[(*length)++] = 0x80 | ((code >> 6) & 0x3f);
      text[(*length)++] = 0x80 | (code & 0x3f);
    }
  else
    {
      text[(*length)++] = 0xf0 | (code >> 18);
      text[(*length)++] = 0x80 | ((code >> 12) & 0x3f);
      text[(*length)++] = 0x80 | ((code >> 6) & 0x3f);
      text[(*length)++] = 0x80 | (code & 0x3f);
    }
  return true;
}

static bool tpe_face_background (struct frame *frame, struct face *face,
                                 unsigned char color[4]) {
  Lisp_Object spec;
  unsigned short red, green, blue;
  Emacs_Color tty_color;

  if (!face || !STRINGP (face->lface[LFACE_BACKGROUND_INDEX]))
    return false;
  spec = face->lface[LFACE_BACKGROUND_INDEX];
  if (parse_color_spec (SSDATA (spec), &red, &green, &blue))
    {
      color[0] = red >> 8;
      color[1] = green >> 8;
      color[2] = blue >> 8;
    }
  else if (tty_defined_color (frame, SSDATA (spec), &tty_color, false, false))
    {
      color[0] = tty_color.red >> 8;
      color[1] = tty_color.green >> 8;
      color[2] = tty_color.blue >> 8;
    }
  else
    return false;
  color[3] = 255;
  return true;
}

static size_t tpe_capture_mouse_highlights (struct frame *frame,
                                            struct window *window,
                                            uint64_t window_id,
                                            uint32_t generation,
                                            TpeWireFace *faces,
                                            TpeWireHighlight *highlights) {
  Mouse_HLInfo *hlinfo = MOUSE_HL_INFO (frame);
  struct glyph_matrix *matrix = window->current_matrix;
  struct face *resolved;
  size_t count = 0;

  tpe_mouse_highlight_debug = 1;
  if (!tpe_mouse.valid)
    return 0;
  hlinfo->mouse_face_window = window;
  {
    Lisp_Object overlay = Qnil;
    struct display_pos position;
    int dx = 0, dy = 0, width = 0, height = 0;
    int x = tpe_mouse.x - WINDOW_LEFT_EDGE_X (window);
    int y = tpe_mouse.y - WINDOW_TOP_EDGE_Y (window);
    Lisp_Object mouse_face = buffer_posn_from_coords (
      window, &x, &y, &position, &overlay, &dx, &dy, &width, &height);
    if (NILP (mouse_face))
      mouse_face = get_char_property_and_overlay (
        make_fixnum (CHARPOS (position.pos)), Qmouse_face,
        window->contents, &overlay);
    if (!NILP (mouse_face))
      {
        ptrdiff_t ignore = 0;
        hlinfo->mouse_face_face_id = face_at_buffer_position (
          window, CHARPOS (position.pos), &ignore,
          CHARPOS (position.pos) + 1, true, -1, 0);
        hlinfo->mouse_face_beg_row = 0;
        hlinfo->mouse_face_beg_col = 0;
        hlinfo->mouse_face_end_row = 0;
        hlinfo->mouse_face_end_col = matrix ? matrix->nrows : 0;
        hlinfo->mouse_face_past_end = true;
      }
  }
  if (hlinfo->mouse_face_face_id < 0 || matrix == NULL)
    {
      tpe_mouse_highlight_debug = 3;
      return 0;
    }

  resolved = FACE_FROM_ID_OR_NULL (frame, hlinfo->mouse_face_face_id);
  unsigned char background[4] = {0, 0, 0, 255};
  if (!tpe_face_background (frame, resolved, background))
    {
      tpe_mouse_highlight_debug = 4;
      return 0;
    }

  faces[0] = (TpeWireFace) {9, generation, {background[0], background[1],
                                            background[2], background[3]}};
  int first_row = hlinfo->mouse_face_beg_row;
  int last_row = hlinfo->mouse_face_past_end
    ? matrix->nrows - 1 : hlinfo->mouse_face_end_row;
  for (int row_index = first_row;
       row_index <= last_row && row_index < matrix->nrows && count < 8;
       row_index++)
    {
      struct glyph_row *row = MATRIX_ROW (matrix, row_index);
      if (!row->enabled_p)
        continue;
      int start_hpos = row_index == first_row ? hlinfo->mouse_face_beg_col : 0;
      int end_hpos = row_index == last_row && !hlinfo->mouse_face_past_end
        ? hlinfo->mouse_face_end_col : row->used[TEXT_AREA];
      if (end_hpos <= start_hpos || end_hpos > row->used[TEXT_AREA] ||
          row->visible_height <= 0 || row->y < 0)
        continue;

      int left = row->x;
      for (int glyph_index = 0; glyph_index < start_hpos; glyph_index++)
        left += row->glyphs[TEXT_AREA][glyph_index].pixel_width;
      int right = left;
      for (int glyph_index = start_hpos; glyph_index < end_hpos; glyph_index++)
        right += row->glyphs[TEXT_AREA][glyph_index].pixel_width;
      if (right <= left)
        continue;

      highlights[count++] = (TpeWireHighlight) {
        1, window_id, generation,
        left, row->y, right - left, row->visible_height,
        9, generation
      };
    }
  tpe_mouse_highlight_debug = count == 0 ? 5 : 6;
  return count;
}

void terminal_provider_capture_frame (struct frame *frame) {
  TpeEmacsHost *host = frame && frame->terminal
    ? frame->terminal->provider_data : NULL;
  if (!frame || !host || host->deleted || host->terminal_object != frame->terminal ||
      host->adapter_session == NULL || provider_surface_fd < 0 ||
      frame->terminal->type != output_provider)
    return;

  TpeWireRow rows[256];
  TpeWireRun runs[64];
  TpeWireFace faces[8];
  TpeWireHighlight highlights[8];
  size_t row_count = 0;
  size_t run_count = 0;
  size_t face_count = 0;
  size_t highlight_count = 0;
  struct window *window = XWINDOW (frame->root_window);
  uint64_t window_id = (uint64_t)(uintptr_t)window;
  struct glyph_matrix *matrix = window->current_matrix;

  host->redisplay_generation++;
  uint32_t wire_generation = (uint32_t)host->frame_identity.generation;
  if (wire_generation == 0) wire_generation = 1;
  for (int index = 0; index < matrix->nrows && row_count < 256; index++)
    {
      struct glyph_row *row = MATRIX_ROW (matrix, index);
      if (!row->enabled_p)
        continue;
      rows[row_count++] = (TpeWireRow) {
        window_id, (uint32_t)index, 0,
        row->x, row->y, row->pixel_width, row->height,
        row->ascent,
        row->height > row->ascent ? row->height - row->ascent : 0,
        row->y + row->ascent, row->visible_height
      };
      if (run_count == 64 || row->used[TEXT_AREA] == 0)
        continue;
      TpeWireRun *run = &runs[run_count];
      size_t text_length = 0;
      memset (run, 0, sizeof (*run));
      run->run_id = (uint32_t)(index + 1);
      run->generation = wire_generation;
      run->window_id = window_id;
      run->row_index = (uint32_t)index;
      run->x = row->x;
      run->y = row->y;
      run->width = row->pixel_width;
      run->height = row->height;
      for (int glyph_index = 0; glyph_index < row->used[TEXT_AREA]; glyph_index++)
        {
          struct glyph *glyph = row->glyphs[TEXT_AREA] + glyph_index;
          if (glyph->type != CHAR_GLYPH)
            continue;
          unsigned int code = (unsigned int)glyph->u.ch;
          if (code == 0 || code == 0x7f || (code == ' ' && text_length == 0))
            continue;
          if (!tpe_utf8_put (run->text, &text_length, code))
            break;
        }
      run->text_length = (uint32_t)text_length;
      if (run->text_length != 0)
        run_count++;
    }

  if (row_count == 0 || run_count == 0)
    return;

  int cursor_width = FRAME_COLUMN_WIDTH (frame);
  int cursor_height = FRAME_LINE_HEIGHT (frame);
  TpeWireCursor cursor = {
    window_id, window->cursor.x, window->cursor.y,
    cursor_width, cursor_height, 1, true, true
  };
  if (tpe_mouse.valid)
    provider_update_mouse (tpe_mouse.x, tpe_mouse.y, tpe_mouse.timestamp, true);

  highlight_count = tpe_capture_mouse_highlights (frame, window, window_id,
                                                  wire_generation,
                                                  faces, highlights);
  face_count = highlight_count == 0 ? 0 : 1;
  tpe_capture_acknowledged = false;
  tpe_mouse_highlight_acknowledged = false;
  TpeWireSnapshot snapshot = {
    (uint32_t)host->frame_identity.id,
    (uint32_t)host->frame_identity.generation,
    host->session_id,
    host->redisplay_generation,
    FRAME_PIXEL_WIDTH (frame), FRAME_PIXEL_HEIGHT (frame),
    rows, row_count, runs, run_count, cursor,
    faces, face_count, highlights, highlight_count
  };
  unsigned char *bytes = NULL;
  size_t length = 0;
  uint32_t wire_length = 0;
  if (proto_ui_tpe_encode_snapshot (&snapshot, &bytes, &length) != 0 ||
      length > UINT32_MAX)
    return;
  wire_length = (uint32_t)length;
  unsigned char ack = 0;
  if (provider_write_all (provider_surface_fd, &wire_length,
                          sizeof (wire_length)) &&
      provider_write_all (provider_surface_fd, bytes, length) &&
      provider_read_acknowledgment (provider_surface_fd, 'R'))
    tpe_capture_acknowledged = true;
  if (tpe_capture_acknowledged)
    if (highlight_count != 0) tpe_mouse_highlight_acknowledged = true;
  if (bytes)
    proto_ui_tpe_free_snapshot (bytes, length);
}

static int provider_read_socket (struct terminal *terminal,
                                 struct input_event *hold_quit) {
  TpeEmacsHost *host = terminal ? terminal->provider_data : NULL;
  int events = 0;
  if (hold_quit)
    hold_quit->kind = NO_EVENT;
  if (!host || host->deleted || provider_surface_fd < 0)
    return -2;

  while (events < 32)
    {
      unsigned char *packet;
      if (tpe_input_count != 0)
        {
          packet = tpe_input_buffer + tpe_input_head * 48;
          if (!provider_decode_input (packet))
            return -2;
          tpe_input_head = (tpe_input_head + 1) % TPE_INPUT_QUEUE_DEPTH;
          tpe_input_count--;
          events++;
          continue;
        }
      packet = tpe_input_buffer + tpe_input_head * 48;
      if (tpe_input_length >= 48)
        return -2;
      if (!provider_read_input_byte (provider_surface_fd,
                                     packet + tpe_input_length))
        return events;
      tpe_input_length++;
      if (tpe_input_length == 8 && memcmp (packet, "TPEINP1", 8) != 0)
        tpe_input_length = 0;
      else if (tpe_input_length == 48)
        {
          tpe_input_count = 1;
          tpe_input_length = 0;
        }
    }
  return events;
}

static bool provider_read_acknowledgment (int fd, unsigned char expected) {
  struct pollfd waiter = {.fd = fd, .events = POLLIN, .revents = 0};
  for (;;)
    {
      unsigned char byte;
      if (poll (&waiter, 1, 10000) != 1 || !(waiter.revents & POLLIN) ||
          !provider_read_input_byte (fd, &byte))
        return false;
      if (byte == expected)
        return true;
      if (byte != 'T' || tpe_input_count == TPE_INPUT_QUEUE_DEPTH)
        return false;
      size_t slot = (tpe_input_head + tpe_input_count) % TPE_INPUT_QUEUE_DEPTH;
      unsigned char *packet = tpe_input_buffer + slot * 48;
      packet[0] = byte;
      for (size_t offset = 1; offset < 48; ++offset)
        {
          waiter.revents = 0;
          if (poll (&waiter, 1, 10000) != 1 ||
              !(waiter.revents & POLLIN) ||
              !provider_read_input_byte (fd, packet + offset))
            return false;
        }
      tpe_input_count++;
    }
}

static void shutdown_provider_surface (void) {
  if (provider_surface_fd >= 0)
    close (provider_surface_fd);
  if (provider_surface_pid > 0)
    {
      int status;
      waitpid (provider_surface_pid, &status, 0);
    }
  provider_surface_fd = -1;
  provider_surface_pid = -1;
}

Lisp_Object Fterminal_provider_capture_p (void);
Lisp_Object Fterminal_provider_mouse_face_p (void);
Lisp_Object Fterminal_provider_mouse_face_debug (void);

DEFUN ("terminal-provider-capture-p", Fterminal_provider_capture_p,
       Sterminal_provider_capture_p, 0, 0, 0,
       doc: /* Return non-nil when the latest provider snapshot was acknowledged.  */)
  (void)
{
  return tpe_capture_acknowledged ? Qt : Qnil;
}

DEFUN ("terminal-provider-mouse-face-debug", Fterminal_provider_mouse_face_debug,
       Sterminal_provider_mouse_face_debug, 0, 0, 0,
       doc: /* Return provider mouse-face resolver diagnostic.  */)
  (void)
{
  return make_fixnum ((EMACS_INT)tpe_mouse_highlight_debug);
}

DEFUN ("terminal-provider-mouse-face-p", Fterminal_provider_mouse_face_p,
       Sterminal_provider_mouse_face_p, 0, 0, 0,
       doc: /* Return non-nil when the acknowledged snapshot has mouse-face.  */)
  (void)
{
  return tpe_mouse_highlight_acknowledged ? Qt : Qnil;
}

static void provider_mouse_position (struct frame **frame, int insist,
                                     Lisp_Object *bar_window,
                                     enum scroll_bar_part *part,
                                     Lisp_Object *x, Lisp_Object *y,
                                     Time *timestamp) {
  struct frame *provider_frame = provider_terminal_frame ();
  if (tpe_mouse.valid && frame && provider_frame &&
      provider_frame->terminal == tpe_host.terminal_object)
    {
      *frame = provider_frame;
      provider_frame->mouse_moved = false;
      *bar_window = Qnil;
      *part = scroll_bar_nowhere;
      XSETINT (*x, (EMACS_INT)tpe_mouse.x);
      XSETINT (*y, (EMACS_INT)tpe_mouse.y);
      *timestamp = (Time)tpe_mouse.timestamp;
    }
  (void)insist;
}

static ProtoUiPureRuntimeStatus provider_create_terminal (
    void *context, const ProtoUiTerminalCreateRequest *request,
    ProtoUiIdentity *result) {
  TpeEmacsHost *host = context;
  ProtoUiPureRuntimeStatus status;
  if (host->adapter_session == NULL) {
    status = proto_ui_runtime_host_adapter_session_create (
        &host->table, &host->adapter_session);
    if (status != PROTO_UI_RUNTIME_OK)
      return status;
  }
  status = proto_ui_runtime_host_adapter_session_activate (
      host->adapter_session, result);
  if (status != PROTO_UI_RUNTIME_OK)
    return status;
  if (request->kind != 1)
    return PROTO_UI_RUNTIME_INVALID;
  return PROTO_UI_RUNTIME_OK;
}

bool terminal_provider_attach_frame (struct terminal *terminal,
                                     EMACS_UINT frame_id) {
  if (terminal == NULL || tpe_host.deleted ||
      tpe_host.terminal_object != terminal || frame_id == 0 ||
      tpe_host.adapter_session == NULL)
    return false;
  struct frame *frame = provider_terminal_frame ();
  if (!frame)
    return false;
  static uint64_t provider_session_counter;
  reset_mouse_highlight (&tpe_mouse_highlight);
  frame->provider_data = &tpe_mouse_highlight;
  tpe_host.frame_identity.id = (uint64_t)frame_id;
  tpe_host.frame_identity.generation =
    (uint64_t)terminal->provider_generation;
  tpe_host.session_id = ((uint64_t)getpid() << 32) |
    (++provider_session_counter & 0xffffffffu);
  if (!launch_provider_surface (tpe_host.identity.id,
                                tpe_host.identity.generation,
                                tpe_host.frame_identity.id,
                                tpe_host.frame_identity.generation))
    return false;
  terminal->read_socket_hook = provider_read_socket;
  terminal->mouse_position_hook = provider_mouse_position;
  add_keyboard_wait_descriptor (provider_surface_fd);
  return true;
}

static ProtoUiPureRuntimeStatus provider_activate_terminal (
    void *context, const ProtoUiIdentity *identity) {
  TpeEmacsHost *host = context;
  return identity != NULL && identity->id == host->identity.id &&
             identity->generation == host->identity.generation
             ? PROTO_UI_RUNTIME_OK : PROTO_UI_RUNTIME_INVALID;
}

static ProtoUiPureRuntimeStatus provider_delete_terminal (
    void *context, const ProtoUiIdentity *identity) {
  TpeEmacsHost *host = context;
  if (host->adapter_session == NULL)
    return PROTO_UI_RUNTIME_INVALID;
  return proto_ui_runtime_host_adapter_session_drain (host->adapter_session);
}

static ProtoUiTerminalProviderV1 tpe_provider;

static void shutdown_terminal_provider (void) {
  if (tpe_registration == NULL)
    return;
  shutdown_provider_surface ();
  (void)proto_ui_tpe_terminal_delete (tpe_registration, &tpe_active_terminal);
  if (tpe_host.adapter_session != NULL) {
    (void)proto_ui_runtime_host_adapter_session_destroy (tpe_host.adapter_session);
    tpe_host.adapter_session = NULL;
  }
  (void)proto_ui_tpe_provider_unregister (tpe_registration);
  tpe_registration = NULL;
}

bool init_terminal_provider (void) {
  const char *selected = getenv ("EMACS_TERMINAL_PROVIDER");
  if (selected == NULL || strcmp (selected, "proto") != 0)
    return false;
  if (tpe_registration != NULL)
    return true;

  initialize_host_table (&tpe_host);
  Fset (intern_c_string ("frame-background-mode"), Qdark);
  defsubr (&Sterminal_provider_capture_p);
  defsubr (&Sterminal_provider_mouse_face_p);
  defsubr (&Sterminal_provider_mouse_face_debug);
  tpe_provider = (ProtoUiTerminalProviderV1) {
    1,
    PROTO_UI_TPE_FLAG_GRAPHIC | PROTO_UI_TPE_FLAG_INPUT,
    sizeof (ProtoUiTerminalProviderV1),
    "proto", "proto", &tpe_host,
    provider_create_terminal, provider_activate_terminal,
    provider_delete_terminal
  };
  if (proto_ui_tpe_registry_reset () != PROTO_UI_RUNTIME_OK ||
      proto_ui_tpe_provider_register (
          &tpe_provider, &tpe_host.table, &tpe_registration) != PROTO_UI_RUNTIME_OK)
    return false;

  ProtoUiTerminalCreateRequest request = {1, 1, {0}};
  ProtoUiIdentity terminal;
  if (proto_ui_tpe_terminal_create (tpe_registration, &request, &terminal) !=
          PROTO_UI_RUNTIME_OK ||
      proto_ui_tpe_terminal_activate (tpe_registration, &terminal) !=
          PROTO_UI_RUNTIME_OK)
    return false;
  tpe_active_terminal = terminal;
  if (!tpe_shutdown_registered) {
    atexit (shutdown_terminal_provider);
    tpe_shutdown_registered = true;
  }
  return true;
}

Lisp_Object terminal_provider_identity (struct terminal *terminal) {
  TpeEmacsHost *host = terminal ? terminal->provider_data : NULL;
  if (host == NULL || host->deleted || host->terminal_object != terminal)
    return Qnil;
  if (tpe_registration == NULL)
    return Qnil;
  return intern (tpe_registration->provider.name);
}
