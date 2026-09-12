# Proto-UI Runbook

## 1. Audience and scope

This runbook builds and exercises the current adapter-first Proto-UI slices on
a graphical Linux host.  It is **not** a release guide for a production SDL3
Emacs backend: `output_proto`, redisplay-owned rows, complete input, faces,
fonts, images, widgets, and PGTK parity remain documented gaps in
[`capabilities.md`](capabilities.md).

## 2. Prerequisites

1. Zig 0.16.0.
2. A working graphical session (`DISPLAY` or `WAYLAND_DISPLAY` and
   `XDG_RUNTIME_DIR`).
3. GTK3 development files for the default Linux PGTK build.
4. SDL3, SDL3_ttf, and `pkg-config` for `-Dsdl3-frontend=true`.
5. No running Emacs daemon is required; lifecycle smoke tests create an
   isolated private daemon.

## 3. Adapter and protocol checks

Run from the repository root:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-status --summary all
zig build -Dproto-ui=true proto-ui-protocol-coverage --summary all
zig build -Dproto-ui=true proto-ui-shim --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

Expected result: all adapter unit tests pass and the boundary audit reports
`boundary: OK`; coverage reports 165 implemented codecs and 0 partial or
planned; and `zig-out/proto-ui/status_manifest.json` is regenerated from
`src/proto-ui/capability.zig`.  The generated ABI, C shim, and capability
summaries are installed under `zig-out/include/proto-ui/` and
`zig-out/proto-ui/`.

## 4. SDL3 rendering checks

Build and run the deterministic replay and renderer checks:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke --summary all
```

The standalone input-translation smokes need no Emacs process:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-input-translate-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-pointer-v2-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-touch-tap-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-pen-tap-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-menu-hit-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-toolbar-hit-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-dialog-hit-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-scrollbar-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-face-text-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-cursor-style-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-primary-selection-smoke --summary all
```

`sdl3-primary-selection-smoke` sets the SDL PRIMARY selection to bounded UTF-8
text and requires translation into one queued input intent.  It is a platform
capture check only: it starts no Emacs publisher and claims no selection
ownership, transfer, or paste round trip.

`sdl3-touch-tap-smoke` seeds one synthetic SDL finger sequence and proves the
bounded single-contact translation into `press` / `drag` / `release` / `press`
/ `cancel` Pointer v2 intents, the converted pixel, that a second concurrent
contact is rejected, and that an out-of-window normalized coordinate produces
no intent.  Multi-touch gestures, pressure, pen input, and Emacs gesture
commands are not covered.

`sdl3-pen-tap-smoke` seeds one synthetic SDL pen sequence and proves the bounded
pen-tip translation into `motion` (air hover) / `press` / `drag` / `release`
Pointer v2 intents, that an eraser-tip event produces no intent, and that the
journal preserves the tip lifecycle order.  Pressure, tilt, barrel buttons,
drawing surfaces, and Emacs command dispatch are not covered.

`sdl3-face-text-smoke` builds one live frame with a body text line and an
explicit `FACE_DEFINE`/`WINDOW_FACE` pair: it proves the text keeps the draw
default while the window has no face, uses the face foreground once the window
is bound to a live generation, and follows a replacement generation on the next
frame.  Per-line faces, face merging, overlays, and shaped-text faces are not
covered.
The graphic smoke also pins a three-line region on plain rows and requires
more than one region highlight record plus the region color in the draw list
(`region_rects`), proving the per-row region shape; region shapes beyond one
rectangle per displayed row are not covered.

`sdl3-cursor-style-smoke` builds one live frame with a window default face and
drives one `CURSOR_UPDATE` per bounded kind: it proves the solid box/bar/hbar
shapes emit one fill, the hollow kind emits a four-edge outline, the underline
kind emits a bottom edge, an unknown kind falls back to the solid box, and the
cursor uses the window's face foreground in every case.  Blink state, IME
carriage, and redisplay-owned cursor semantics are not covered.

`sdl3-menu-hit-smoke` builds one live frame with an open popup and drives the
shared popup geometry: it proves the clicked row reports the backend-owned item,
a press outside reports user dismissal, Escape reports keyboard cancellation, a
separator press is inert, pointer hover and Up/Down report one `leave` + `enter`
pair per highlight change, Enter reports a command and an enabled submenu reports
an open request, selected checkbox and radio rows use distinct 4x4 and 2x2
markers with shifted labels, a complete 2x2 image resource draws its exact pixels
with label fallback for a stale reference, a disabled row is dimmed, and the
highlighted row's printable-ASCII help wraps into at most three owner-safe tip
lines (`popup_help`).  Streaming `move` phases, hover timing, backend
radio-group mutation, live extraction of Emacs `:image` forms, non-ASCII help,
and Emacs command execution are not covered.

`sdl3-toolbar-hit-smoke` builds one live frame with a tool-bar model and drives
the shared tool-bar layout: it proves a press/release pair for the clicked
button and toggle with the correct item identity, that a separator is inert,
that a press whose toolbar generation was replaced by a patch produces no
release, that an item with a live icon resource draws those exact pixels in its
slot instead of a label, and that a stale icon generation falls back to the text
label.  Overflow, orientation, item text beside an icon, keyboard activation,
and Emacs command execution are not covered.

`sdl3-scrollbar-smoke` builds one live frame with a vertical scrollbar state and
drives the shared track/thumb geometry: it proves the thumb rectangle, a
relative drag delta, that a release (and a motion without the primary button
held) ends the drag session, that a trough press pages by exactly one viewport
in each direction, and that a press outside the track falls through to the
ordinary pointer path.  Horizontal state, arrow-step geometry, and Emacs
dispatch are not covered.

`sdl3-dialog-hit-smoke` builds one live frame with an open prompt dialog and
drives the shared dialog layout: it proves that clicking a standard button
reports that button's identity, that a click on the box body is consumed
without a result, that a click outside the box falls through, that Escape
reports the cancel button, and that the bounded prompt field accepts printable
ASCII text, rejects control and non-ASCII bytes, renders what it accepted,
stops at its capacity, and submits the text in the `DIALOG_RESULT` tail on both
the button and Escape paths.  Unicode field input, a caret, custom buttons,
file/color/font dialogs, and Emacs callback dispatch are not covered.

For an opt-in, host-dependent renderer timing report, use:

```sh
zig build -Doptimize=ReleaseFast -Dproto-ui=true -Dsdl3-frontend=true \
  sdl3-renderer-bench --summary all
cat zig-out/proto-ui/sdl3-renderer-benchmark.json
```

The smoke may briefly open an SDL window by design.  The benchmark uses a hidden
window and renders bounded fixtures and deterministic renderer-call
typing/scroll/resize proxies; neither proves a complete Emacs editor frame,
real typing/scroll/resize, core redisplay, Emacs end-to-end behavior, GPU
timestamps, PGTK comparison, host-independent regression evidence, or a real
Emacs performance improvement.  Benchmark numbers describe the local host and
run only.

For an opt-in round-trip report over the real bounded EPXL edit path, use:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-roundtrip-bench --summary all
cat zig-out/proto-ui/sdl3-epxl-roundtrip-benchmark.json
```

This starts the owned public-facts publisher and alternates a backspace and a
bounded ASCII insertion at window point, one intent in flight at a time.  It
reports control-ACK and next-`FRAME_UPDATE` latency percentiles for the bounded
public-facts bridge only; it does not exercise core redisplay, renderer present,
GPU timestamps, PGTK comparison, or end-to-end latency, and the numbers describe
the local host and this build mode only.

## 4.1 Current window command checks

The bounded command bridge can split, select, edit, and restore one live Emacs
window:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-split-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-navigation-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-restore-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-pointer-select-smoke --summary all
```

They exercise only the explicit `C-x 2`, `C-x 3`, `C-x o`, insertion, and
`C-x 1` whitelist entries; the pointer-select gate adds a zero-modifier left
click on the right split window.  They do not enable arbitrary keymaps,
prefixes, right buttons, or modifier chords.

## 5. Real-frame lifecycle smoke

The current closest approximation to “open Emacs through SDL3” is the W12c
lifecycle bridge:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-frame-smoke --summary all
```

Success prints output similar to:

```text
sdl3-frame-smoke: renderer <name> tier=<tier>
sdl3-frame-smoke: real Emacs frame WIDTHxHEIGHT created, rendered, and deleted through SDL3; lifecycle OK
```

This smoke starts a private PGTK Emacs daemon, creates and deletes one real
display-backed Emacs frame, and applies the matching EUP frame lifecycle in an
SDL3 scene.  It deliberately closes quickly.  A brief window flash is expected
and is not a failure when the command exits zero.

The exact contract, limits, and cleanup behavior are in
[`frame-lifecycle-smoke.md`](frame-lifecycle-smoke.md).

## 6. Interactive bounded-input checks

Exercise the authenticated EPXL facts and input path:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-facts-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-ime-commit-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-dnd-drop-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-face-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-cursor-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-scrollbar-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-scrollbar-interaction-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-hscroll-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-mouse-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-menu-bar-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-menu-open-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-menu-apply-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-graphic-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-interactive-smoke --summary all
```

These checks cover bounded ASCII text, negotiated bounded Unicode text, a few
key actions, pointer/wheel intents, live face/cursor/scrollbar/mouse facts,
bounded menus, and refreshed public facts.  The Unicode
gate also renders one bounded UTF-8 public-facts line with SDL_ttf; it has no
shaping, BiDi, Emacs font metrics, or complete fallback.  The committed-input
gate covers only one bounded, smoke-seeded `SDL_EVENT_TEXT_INPUT` UTF-8 commit:
no OS-generated commit, composition, candidate/preedit acquisition,
surrounding-text deletion, or full IME lifecycle.  These checks do not provide
a full Emacs keyboard/keymap/IME input stack.

`sdl3-dnd-drop-smoke` seeds one real SDL begin/position/text/position/complete
sequence for a 256-byte-bounded payload, proves the negotiated `dnd.bounded_v1`
capability, requires the frontend to send exactly one bounded `DND_POSITION`
(the later position is coalesced away while the journal is busy) plus the exact
`DND_ENTER`/`DND_DROP`/`DND_DATA` triple over authenticated EPXL, and requires
the owned publisher to apply the bounded text so the republished facts show it.
Only the receive direction is covered: drag-out, MIME negotiation, multiple
offers or files, drag leave/cancel, and a request/data handshake are not
covered.

`sdl3-emacs-face-smoke` runs the owned publisher with deterministic default-face
colors and requires the live SDL scene to own that face, bind the live window to
it, and draw the body text with it.  Per-line faces, face merging, overlays, and
shaped-text faces are not covered.

`sdl3-emacs-cursor-smoke` runs the owned publisher with a deterministic
`cursor-type` (`hbar`) and requires the live SDL scene to own the mapped
`cursor_kind` 3 and draw the horizontal-bar shape while real frame updates keep
arriving.  Other cursor types are exercised only by the synthetic
`sdl3-cursor-style-smoke`; blink state, per-window cursor faces, IME-coupled
caret behavior, and redisplay-owned cursor semantics are not covered.

`sdl3-emacs-mouse-smoke` runs the owned publisher, drives one synthetic pointer motion over the first body row, and requires the live mouse-face highlight and its real face background.  Text-property mouse-face pins do not survive redisplay, so the smoke pins an overlay; the pinned overlay spans three displayed rows, so the smoke requires one bounded highlight rectangle per row (`mouse_rects`:3).

`sdl3-emacs-scrollbar-smoke` runs the owned publisher with a deterministic
scroll-bar width and window start and requires the live SDL scene to own the
proportional `WINDOW_SCROLL_STATE` for a real 200-line buffer scrolled to line
11 with the 32-line mirror viewport.  Other scroll positions are exercised only
by the synthetic `sdl3-scrollbar-smoke`; horizontal state, arrow-step geometry,
and core-owned scroll dispatch are not covered.

`sdl3-emacs-scrollbar-interaction-smoke` drives the live scrollbar pointer path:
it clicks the trough below the thumb (one 32-line page) and then drags the thumb
(4 logical units), and requires the republished state to show the real Emacs
window scrolled to position 42 and then 46.  Horizontal scroll, arrow-step
geometry, and non-line scroll units are not covered.

`sdl3-emacs-hscroll-smoke` drags the live horizontal scrollbar thumb ten columns
and requires the republished state to show the real `window-hscroll` moving from
5 to 15.  Arrow-step geometry, sub-cell or pixel scroll units, and redisplay-owned
scroll semantics are not covered.

`sdl3-emacs-menu-bar-smoke` runs the owned publisher and requires the live scene
to own the frame's real menu-bar labels in display order and the draw list to
render each of them in the reserved strip with the frame's real font
(`font_backed`).  It does not open a menu.

`sdl3-emacs-menu-open-smoke` presses the real "Edit" slot and requires one
bounded `MENU_OPEN_REQUEST`, then requires the publisher's real child rows to
appear, chooses a selectable row, and requires the popup to close.  The rows
carry evaluated `:enable`, `:filter`/`:visible`, key hints, bounded `:help`,
stateful-row kind/selection vectors, and one appended file-backed XBM icon
payload backed by a complete generation-correct scene image.  The live gate
proves that metadata and resource identity; it does not claim a drawn live icon
or rendered help when the current rows are non-ASCII, too large for the
owner-safe width, or cannot fit above/below the popup.
Non-XBM image capture, non-allowlisted commands, and paths beyond the bounded
depth-four submenu model are not covered.
`proto-ui-unit` separately proves that well-encoded malformed or oversized XBM
falls back per row; invalid base64 and mismatched icon vectors remain fatal.

`sdl3-emacs-menu-apply-smoke` seeds one bounded edit and chooses real "Undo"
through the popup; `proto-ui-unit` also applies the closed line-number and
line-wrapping radio groups and proves their backend-owned selections republish.
Commands outside the closed safe set and arbitrary radio groups are not
covered.

`sdl3-emacs-graphic-smoke` runs the publisher against a display-backed PGTK/X
frame (it starts Emacs without `--batch` so the real `format-mode-line` and a
real scroll-bar width exist at all) and requires the live scene to own the real
mode line text, height, and a draw command, a real scroll-bar width, and rows
spaced by the frame's own line height (it also prints `row_height`), plus both
real fringe records and their draw commands (`fringe`), with the reserved
fringe columns insetting the rows and cursor.  It also requires the frame's real mode-line face colors to reach the bar fill (`mode_line_face_colors`). and the diagnostic text font to be sized from the frame's real font pixel size (`text_font_size`, 13, below the 15-pixel row height).  It also requires the real font file to reach the renderer (`font_file`).  It also reports how many alternate font families it resolved (`font_families`, one on the stock theme's serif variable-pitch face).  The live cursor is required to be one real character cell wide and one line tall (`cursor`).  The real cursor and fringe face colors are required to reach their draw paths too.  The rows and mode line are also required to stop before the real scroll bar (`row_width`).  It splits the real frame with `C-x 2` and requires the inactive window's mode line to use the published `mode-line-inactive` colors.  Its publisher profile also pins one active region, and the smoke requires the live highlight record and its draw color (`region_highlight`).  It pins one Lisp line as well, and requires its font-lock runs to reach the draw list in at least two distinct colors (`line_font_lock_runs`) and at least three rows with two or more distinct colors (`line_font_lock_row_count`) and at least one run face background to reach a fill (`line_font_lock_run_backgrounds`) and a decorated run to reach a bar fill (`line_font_lock_run_decorations`, using the pinned `#00a0a0` underline color) and an inverse-video run to fill with its foreground half (`line_font_lock_run_inverse`). A bold-italic run must keep its style bits into the draw list (`line_font_lock_run_style`). An overlay face must reach a run (`line_font_lock_run_overlay`). After the split, a run for the non-first window must arrive (`line_font_lock_multi_window`) and a bold mode-line segment run (`mode_line_face_runs`). It also requires a system font fallback that resolves CJK codepoints (`cjk_fallback`). It also pins a deterministic echo message and requires the resource and its drawn text in the bottom strip (`echo_area`). It also pins a header line and a tab line, and requires each aux bar to use its own real published face color (`header_line_face_colors`, `tab_line_face_colors`). It also requires the mirror to carry at least twenty-four window lines (`mirrored_lines`). It also requires a plain body row to be drawn with the frame's real font (`body_text_font`). It prints a bounded
`skipped` result when no DISPLAY/WAYLAND_DISPLAY is available, so headless jobs
stay green. Both the header and tab lines also carry their own segment faces:
the smoke pins an accent face on each and requires a run of that line to reach
the draw list in the run's face color (`header_line_face_runs`,
`tab_line_face_runs`), sampled per applied message because the next
authoritative frame update clears the glyph-run table. Fringe bitmaps, dividers,
per-character font selection within a run, and multiple chrome
segments per line from a graphic frame are not covered.  The smoke also requires
the live tool bar: the publisher mirrors the frame's real `tool-bar-map` items
into the bounded toolbar model (thirteen for the stock `-Q` frame) and the smoke
requires the model and at least four of its labels in the draw list (`tool_bar`,
`tool_bar_items`), plus the frame's real `tool-bar` face colors reaching the
strip (`tool_bar_face_colors`); real tool-bar icons and exact tool-bar geometry
are not covered.  The mirror also draws the real `:box` decorations: the
mode-line's released-button box (a border around the bar) and the tool-bar
buttons' boxes are required (`mode_line_box`, `tool_bar_box`), and the real
`:line-width` plus the light/dark bevel must reach the border bars
(`tool_bar_box_width`, `tool_bar_box_bevel`); exact PGTK bevel parity is not covered.
The smoke also pins a CJK line among the font-lock rows: because the bounded
run wire is printable-ASCII only, that line must fall back to its plain SDL_ttf
text and still reach the draw list (`non_ascii_text`) instead of failing the
whole snapshot.
Long-line runs are clamped to the owning window (a 120-column run in a
600-pixel frame is pinned by `proto-ui-unit`), because an unclamped run that
exceeds the frame bounds would otherwise reject the snapshot and blank the
mirror; the drawn glyphs may still overflow the window edge, which is not
covered.
A cursor that does not fit its window clamps into it instead of failing the
whole snapshot (`proto-ui-unit` pins a short window and a real column); the
publisher still bounds the mirrored cursor column at nine, so exact cursor
column and `window-hscroll`-adjusted placement are not covered.
The split frame's carets are checked too: the scene's tracked cursor must be
the active one (solid) while the non-selected window's caret is drawn hollow
(`inactive_cursor_hollow`); cursor blinking and other inactive-cursor shapes
are not covered.
The smoke also pins an over-long line and a blank line: the over-long line is
truncated to the byte bound and the blank line keeps its row, so the rows after
them stay aligned with the real display (`row_alignment`); wrapping and full long-line mirroring are not covered.
The horizontal-scroll smoke drags the real bar to `window-hscroll` 15 and
requires the mirrored rows to drop the scrolled-off columns — the base
`visible ASCII textZ` line becomes `extZ` (`text_trimmed`); hscroll-aware cursor
placement beyond the bounded column cap is not covered.
The smoke also pins a 1000-character line (wider than the window) and requires
the mirror to hold several rows of its wrapped text (`wrapped_rows`), proving
that displayed rows are followed; a caret on a wrapped continuation row and a
displayed row past the 256-byte bound are not covered.
The smoke also pins a mixed `你好 note4` line: the plain text (the non-ASCII
part) must still reach the draw list while the keyword-coloured ASCII span
arrives as a partial run (`line_font_lock_run_mixed`); shaped text and
substitution-spanning runs are not covered.
A mirrored row now carries up to 256 bytes (the earlier 120-byte cap was the
chrome/echo/title bound), so a wide frame's rows are mirrored in full; the smoke
requires a row longer than 120 bytes when the window is wider than 120 cells (`row_bound_256`), while rows wider than
256 cells are not covered.
The smoke's pins are ordered so that a narrow display wrapping the over-long
lines cannot push the coloured rows out of the bounded run budget, and the row
bound is only asserted when the window is wide enough to hold a >120-byte row,
so the smoke is display-width independent.  It does need a working Wayland/X
display: if the session's compositor restarts, `DISPLAY`/`WAYLAND_DISPLAY` must
be pointed at the new sockets (a stale pair hangs the GUI publisher and fails
SDL window creation).
The echo strip now uses the frame's real default face colors, and the graphic
smoke requires the drawn message to carry the default-face foreground
(`echo_face_color`); the minibuffer prompt face and completion UI are not
covered.

### 6.0 Manual graphic mirror

To see the display-backed fidelity work rather than assert it:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-graphic-interactive
```

This starts a real Emacs publisher without `--batch` (so it opens its own
PGTK/X frame), one authenticated EPXL session, and an SDL window that mirrors
that frame's real mode line and mode-line faces, fonts, fringes, cursor cell,
active region, menu bar, and scroll bar; close the SDL window to stop. It needs
a display server and is skipped by the automated gate when none exists (the
gate itself is `sdl3-emacs-graphic-smoke`).

### 6.1 Manual authenticated session

Use this target when you want the bounded bridge to stay open instead of
running a timed smoke:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive
```

This starts a real Emacs publisher, one authenticated EPXL session, and an
SDL3 window.  `--auto-quit-ms=0` means “no smoke deadline”: closing the SDL
window closes the transport, lets the publisher terminate its Emacs child, and
then removes private artifacts.  The session remains a bounded public-facts
bridge, not an `output_proto` terminal or complete Emacs UI.

The target intentionally returns after closing that EPXL window; it does not
open the separate replay-only diagnostic window used by timed smokes.

## 7. Interpreting failures

| Symptom | First response |
|---|---|
| `NoGraphicalDisplay` or SDL video initialization fails | Confirm `DISPLAY`/`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and SDL3 availability. |
| `FrameLifecycleTimeout` | Ensure no test is waiting for a nonexistent display and that the graphical session allows GTK window creation. |
| GTK module warnings | Treat them as host-environment noise only if the smoke exits zero; investigate when the lifecycle fails. |
| `InvalidSequence` | Report it as a producer/frontend sequence-state bug; do not bypass scene validation. |
| Private daemon remains running | Check for an interrupted run; the smoke cleans its uniquely named `/tmp/proto-ui-frame-*` directory and owned children on normal/failure paths. |

Do not attach the lifecycle smoke to a user Emacs daemon and do not delete
another process’s `/tmp/proto-ui-frame-*` directory.

## 8. Current completion boundary

Green smoke commands prove only their documented bounded scope.  Candidate R8
adapter linkage is state-aware: it is unlinked by default, audited as
`linked_not_registered` only under explicit native Linux glibc runtime linking,
and never called or able to register a terminal.  The final system requires the W16 gates in
[`implementation-plan.md`](implementation-plan.md): an `output_proto` real
graphic frame, redisplay-owned rendering, full input/platform coverage,
resource/widget behavior, performance evidence, and unchanged default Emacs
builds.
