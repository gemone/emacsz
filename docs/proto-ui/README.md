# Emacs Proto-UI and SDL3 Frontend

Status: active implementation baseline; final pure-runtime frame pending
Protocol: Emacs UI Protocol (EUP) v1
Branch: `zig-build-step-4`

## 1. Objective

Proto-UI adds an optional headless Emacs terminal backend, called `output_proto`, that exports Emacs display semantics through a stable protocol. A separate SDL3 frontend consumes the protocol, opens real operating-system windows, renders Emacs frames, and sends user input back to Emacs.

Adapter-first is a hard constraint.  New Proto-UI behavior is implemented in the Zig adapter, SDL3 frontend, protocol tooling, Lisp integration, or build glue—not by intrusively modifying inherited GNU Emacs C source.  See [`adapter-boundary.md`](adapter-boundary.md).

The completed system must:

1. Open a real Emacs frame with a real SDL3 frontend.
2. Preserve Emacs as the authoritative owner of buffers, commands, window layout, frames, faces, fonts, images, redisplay, and input interpretation.
3. Support an optional GPU-accelerated frontend while retaining a software fallback.
4. Provide a complete EUP interface and protocol table.
5. Preserve existing Emacs behavior when proto-ui is disabled.
6. Improve interactive display latency and frame scheduling relative to a non-accelerated fallback.
7. Reach PGTK-level Emacs UI capability over time, with every gap explicitly tracked.

The normative end state is a **pure SDL3 `output_proto` UI backend**.  PGTK is a
reference backend for semantic and visual parity, never a runtime fallback for a
Proto frame.  See [`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md).

## 2. Current status

The design baseline is complete and implementation is active.  The following
status records are chronological review history: later milestones supersede the
capability exclusions in earlier records, and no historical paragraph alone is
the current status.  Use [`capabilities.md`](capabilities.md) and the
machine-readable manifest generated from `src/proto-ui/capability.zig` for the
authoritative feature set, with [`implementation-plan.md`](implementation-plan.md)
for milestone scope.

The current hard boundaries remain explicit: there is still no real
`output_proto` Emacs frame, redisplay-owned glyph capture, complete EUP resource
model, full keyboard/keymap/IME input, or PGTK parity.  Within those boundaries,
the adapter and SDL3 frontend implement and exercise the bounded transport,
facts, rendering, resource, input, widget, recovery, and performance slices
recorded by the manifest and current capability matrix.

### 2.1 Current checkpoint matrix

| Area | Available now | Explicit boundary |
|---|---|---|
| Manual SDL3 session | Authenticated EPXL publisher, real Emacs process, and manually closable SDL window via `sdl3-emacs-interactive` | Bounded public-facts bridge; not `output_proto` or a complete Emacs UI |
| Title facts | Bounded public Emacs title facts publish through `STRING_DEFINE` plus `FRAME_TITLE` and apply to the SDL window | No complete frame-parameter ownership, renaming, icon title, runtime registration, or PGTK parity |
| Focus facts | SDL gain/loss intents deliver over EPXL and one-frame focused state round-trips through `FRAME_FOCUS` | No OS focus control, multi-frame focus isolation, or complete PGTK focus parity |
| Window state intents | Negotiated SDL resize/move/fullscreen/maximize intents apply through or record public Emacs frame-parameter acceptance, and bounded minimize/restore dispatch is smoke-verified | Exact WM geometry/completion, close request runtime, and multi-frame control remain pending |
| Selection state | Negotiated primary owner, owner-cancelled loss, replacement, and request/data/error transitions transport into Scene; exported owners can claim/release bounded SDL PRIMARY text (OS-shared on X11/Wayland; app-local SDL fallback elsewhere) | No external target-request service, target conversion, multi-format data, or general Emacs selection parity |
| Monitor changes | Real SDL display/scale changes refresh frontend-local `FRAME_MONITOR` state and negotiated `MONITOR_EVENT`/`DPI_EVENT` transport is smoke-verified | No redisplay adaptation or Emacs frame migration |
| System theme | Negotiated `THEME_EVENT` EPXL transport and Emacs recording of delivered dark/light appearance via `sdl3-theme-event-smoke` | No complete theme refresh, accessibility preferences, face remapping, or PGTK parity |
| Input | Bounded Unicode text, pointer sessions, bounded single-contact touch and pen-tip translation into Pointer v2, popup-menu click selection, pointer hover, Up/Down navigation, Enter selection, outside dismissal, and Escape cancellation from one shared popup geometry source, vertical/horizontal line wheel, single-key commands, exact `C-x 1/2/3/o` window lifecycle commands, and ACK/recovery evidence | No general keymap execution, full IME, submenu paths beyond the bounded depth-four model, multi-touch gestures, pen pressure/tilt, redisplay-owned input feedback, or complete pointer parity |
| IME state | Scene state for bounded preedit, selected candidate metadata, and commit reports; bounded ASCII SDL diagnostics where implemented | No platform IME backend, core buffer application, full candidate lists, Unicode diagnostic rendering, or complete multibyte input |
| Widget state | Bounded menu model/open/result/hover, toolbar model/click/patch, dialog model/result, and scrollbar state/event paths; live menu-bar and popup rows, closed-safe command application, file-backed XBM menu icons, and shared popup geometry are smoke-covered | No native menus/dialogs/tooltips, non-XBM payload capture, general command execution, complete widget policy, or PGTK parity |
| R7/R8 gate | Fail-closed reviewer packet, contract, selected host adapter, adapter-only TP2 registration policy, blocked activation, state-aware R8 readiness, fail-closed host-audit adapter, and opt-in native-glibc target link audit with pinned ABI/table provenance | Default builds remain unlinked; linked state is `linked_not_registered`, with no production core dispatch, call, registration, runtime activation, `output_proto`, or PGTK fallback |
| Performance | ReleaseFast adapter hot-path JSON, an opt-in SDL3 full-draw/unchanged-skip plus typing/scroll/resize renderer-proxy benchmark with nearest-rank latency/FPS/command counters, and an opt-in bounded EPXL edit round-trip benchmark with per-step ACK and next-frame-update latency percentiles | Adapter/renderer/bound-facts-bridge baselines only; host-dependent CPU timing, no end-to-end, real redisplay/typing/scroll/resize, PGTK comparison, GPU timestamps, or production GPU-tier proof |

### 2.2 Milestone chronology

The remaining entries in this chronology are retained as review history, not as
a flattened current claim.

Historical W1-W4c-b0 direct-core prototypes were reviewed, but their inherited C/Lisp integration has been rolled back under the adapter-first rule.  At that historical point the adapter implemented the EUP v1 codec and bounded transport/replay, defined ABI v1, validated capture state with a fake host, and audited boundary paths through `zig build`.  The independent SDL3 frontend could consume real public Emacs frame-fact snapshots and a token-authenticated local live Unix stream with per-message ACK backpressure, rendering frame/window/row/cursor geometry.  An opt-in Emacs dynamic-module seam could continuously capture public frame/window dimensions, bounded visible ASCII text, and public point/cursor facts; SDL3 validated each changed snapshot as an EUP scene and rendered the latest result. It exposed a bounded printable-ASCII text bridge and pressed, unmodified backspace/cursor intents through public observation APIs; W8b-a added a persistent public-fact bridge in which a real SDL window delivered translated ASCII actions to a real Emacs process and rendered the republished facts; W8c-c-a added a frontend-owned EPXL delivery journal that retained an unacknowledged bounded intent and sequence across reconnect retry. W8c-c-b proved that recovery with a real Emacs ACK-loss smoke; W8d-a added a real SDL EPXL interactive input smoke that translated an SDL event, carried it through authenticated EPXL, applied it in Emacs, and rendered the refreshed facts. W8d-b made this authenticated EPXL path the default for `--emacs-interactive` while retaining an explicit bounded local-action fallback. W8d-c carried the bounded copy intent over EPXL and installed the validated result in SDL clipboard. W8e-a added bounded SDL pointer motion and single left-click intents over the same authenticated EPXL journal, and W8e-b ordered left press/drag/release sessions; W8f-a added bounded vertical wheel ticks over the same authenticated EPXL path, and W9g2 returned bounded window-start/visible-line viewport facts so scroll changes were observable in SDL; full recovery and full interactive frames remained pending; it did not yet expose redisplay internals, full keyboard/keymap/IME/command input, redisplay-owned cursor semantics, fonts, resources, or a complete interactive frame.  Glyph, face, font, and image resource capture, Emacs runtime integration, generic graphic frame creation, and the final objective remained pending adapter-first work.

W10a adds adapter-owned SDL renderer negotiation: the frontend reports the actual renderer tier, supports explicit software/GPU/named-driver selection, and falls back from GPU to software when required. W10b-a adds change-aware full-frame presentation with frontend full-frame-path and present/skip counters. W10b-b1 adds a reusable backend-neutral clear/fill/text draw list executed by SDL software and GPU-backed renderers. It also adds bounded SDL key/text translation, cursor/backspace artifact actions, and explicit monotonic reverse-input sequencing with one in-flight EPXL intent, exact transport ACK matching, and an Emacs apply-ACK before that transport ACK. Glyph atlas, image cache, blend/scissor, rectangle damage policy and native GPU counters remain under development; explicit damage-array retained-target clipping and CPU command culling are now smoke-verified, while full interactive-frame compatibility remains pending; persistent EPXL input subsequently arrived through W8c/W8d and now supports bounded pointer sessions. W11a adds the first bounded desktop clipboard paste path: Ctrl+V captures validated SDL clipboard text through the same input queue. W11b adds the matching bounded copy path: Ctrl+C observes an Emacs smoke buffer, publishes an ASCII-safe artifact, and SDL3 installs it in the platform clipboard. W11c negotiates optional bounded UTF-8 clipboard text: paste accepts Unicode only with `clipboard.text_unicode`, and copy explicitly encodes UTF-8, base64-encodes the exact bytes, and restores them on SDL. Rich text, MIME negotiation, and selection ownership remain pending. W10b-b2a adds a bounded adapter-owned glyph-atlas placement/LRU policy with hit/miss/eviction counters. W10c-a adds conservative initial/cursor/viewport/unchanged damage classification and counters; unchanged scene states skip presentation. W10c-b uses a bounded old/new cursor clip for cursor-only changes to avoid a full clear/redraw. W10c-c extends the retained target to bounded ASCII line/cursor region clips, while viewport, oversized, incomplete, and resource-level damage remain conservative full-frame work; GPU timestamps remain pending. Texture allocation and production glyph rendering remain pending. W10e connects the real-frame lifecycle smoke's public-facts marker to the bounded `GLYPH_RUN` debug fallback and suppresses duplicate facts text for that row. W10f adds its exact 24-byte `GLYPH_RUN_DELETE` lifecycle and restores facts fallback. W12a adds bounded EPXL capability negotiation with required-feature intersection, SHA-256 effective-set verification, and a generated machine-readable status manifest; full EUP-wide feature negotiation remains pending. W12b adds bounded frame create/update/destroy state and resource-generation declarations with atomic stale-generation rejection; real frame teardown and resource payloads remain pending.

W12c adds the first real-frame lifecycle bridge smoke: an isolated PGTK Emacs
daemon creates one visible display-backed frame, the smoke waits for stable
public pixel geometry and bounded facts, a producer scene emits EUP
`FRAME_CREATE`/`FRAME_UPDATE`, a separate frontend scene applies them, SDL3
renders the created/active states, and an atomic delete marker tears down the
exact Emacs frame followed by EUP `FRAME_DESTROY`.  This is not `output_proto`
frame ownership and does not stream redisplay-owned glyphs or full input.

W12d adds strict adapter-owned EUP state contracts for `FRAME_VISIBILITY`
(`hidden`/`visible`/`iconified`) and `FRAME_FOCUS`.  The frontend scene applies
these messages only to the active frame generation; focusing requires a visible
frame, and hiding/iconifying clears focus.  This is wire/lifecycle state, not
yet an Emacs-to-SDL3 focus or visibility runtime round trip.

W12d-t adds `FRAME_TITLE` v1 as a strict generation-qualified reference to a
live string resource.  `Scene` owns a zero-terminated resolved title and the
diagnostic SDL bridge applies it to its real SDL window.  This is protocol and
frontend state only, not full Emacs frame-title/parameter ownership or `output_proto` frame
ownership.

W12d-a adds `FRAME_ALPHA` v1 for active, inactive, and background opacity in
hundredths of a percent.  `Scene` validates and owns the complete triple, and
the diagnostic SDL bridge probes active-window opacity with explicit opaque
fallback.  This is not focus-runtime or redisplay blending parity.

W12d-d adds `FRAME_DECORATIONS` v1 for the decorated/undecorated frame policy.
`Scene` validates and owns the policy, and the diagnostic SDL bridge verifies
the platform border state before restoring its smoke window.  This is not
parent-frame, tooltip-frame, or complete WM policy parity.

W12d-s adds `FRAME_SCALE` v1 for generation-qualified scale and X/Y DPI state.
The diagnostic SDL bridge reads SDL's per-window display scale for comparison.
Live monitor migration and redisplay-owned scaling remain pending.

W12d-f adds `FRAME_FULLSCREEN` v1 for Emacs's none, fullboth, fullwidth,
fullheight, and maximized modes.  The diagnostic SDL bridge applies and
restores `fullboth`; the other modes remain Scene-only until platform mapping
and redisplay geometry adaptation land.

W12d-m adds `FRAME_MONITOR` v1 for a generation-qualified monitor identity,
primary flag, and logical bounds.  The diagnostic SDL bridge queries the real
SDL display ID and bounds; change events and frame migration remain pending.

W12d-x adds `FRAME_MAXIMIZE` v1 for independent horizontal and vertical
maximize policy.  The diagnostic SDL bridge applies and restores both-axis
maximization; single-axis platform mapping and redisplay adaptation remain
pending.

W12c-ctl adds standard EUP `SESSION_SUSPEND`, `SESSION_RESUME`,
`SESSION_RESUMED`, `SESSION_CLOSE`, `PING`, `PONG`, `ERROR`, and
`VERSION_MISMATCH` codecs with a bounded control state machine.  `Scene` now
blocks frame traffic while suspended and resumes only after `SESSION_RESUMED`,
honoring that message's authoritative next sequence.  `sdl3-live-smoke` now
carries suspend/resume, PING/PONG, a recoverable ERROR, and normal close over
authenticated EPXL frames, then asserts the frontend reached a clean closed
state and requires the control capability on both peers.  An automatic PONG
responder is implemented; a separate fresh connection proves fatal
`VERSION_MISMATCH` transport.

W12f-p adds little-endian `FRAME_PRESENTED` and `FRAME_DROPPED` codecs.  The
SDL bridge now encodes and validates real `FRAME_PRESENTED` counter data from a
rendered frame plus a deterministic superseded-frame drop record; core
consumption and pacing remain pending.

W12f-g adds `FRAME_GEOMETRY` v1 for outer, content, text, window, and body
rectangles with containment validation.  The SDL bridge consumes Scene geometry
and queries real window border sizes; core-owned platform placement and resize
migration remain pending.

W12f-icon adds `FRAME_ICON` v1 for a nullable, generation-qualified RGBA icon
reference.  `Scene` validates the live image and hotspot, and the SDL bridge
creates a surface and applies the icon; multi-resolution and animated icons
remain pending.

W12f-hints adds `FRAME_SIZE_HINTS` v1 for min/max size, resize increments, and
aspect limits.  The SDL bridge applies min/max and aspect constraints, while
size increments and redisplay geometry adaptation remain pending.

W12f-z adds `FRAME_Z_ORDER` v1 for raise, lower, top, bottom, above, and below
stack requests.  The diagnostic SDL bridge verifies the top/always-on-top probe
and restores normal state; relative and bottom stacking remain pending.

W12f-parent adds `FRAME_PARENT` v1 for a nullable, generation-qualified parent
relation with modal policy.  The Scene validates child and active-parent
identity; the SDL bridge proves the nullable unparent path.  Linked child
windows and modal propagation remain pending.

W12f-window-patch adds `WINDOW_PATCH` v1 for bounded geometry, parent,
visibility, default-face, and depth changes with cycle and depth validation.
Window zones, scroll state, and mouse-highlight records remain pending.

W12f-cursor adds `CURSOR_UPDATE` v1 as a dedicated 64-byte cursor-state update
with owner/geometry validation and SDL render evidence.  Cursor styles,
IME-coupled caret behavior, and redisplay-owned cursor semantics remain
pending.

W12e adds a bounded adapter-owned resource payload cache with LRU eviction and
strict wire contracts for `RESOURCE_REQUEST` and `RESOURCE_EVICT`.  The cache
accepts at most 32 entries, 4096 bytes per payload, and 16 KiB total; existing
identities require strictly newer generations.  This remains a policy/transport
contract: it does not define or render real face, font, or image payloads.

W12f adds an optional, backward-compatible ABI v1 host callback for reading a
frame's generation, visibility, and focus.  A future `output_proto` host seam
can implement this callback without changing frontend scene semantics.  This
is fail-closed ABI groundwork, not Emacs runtime integration.

W12g publishes the final `output_proto` runtime bridge design and implements
R1 terminal-lifecycle core plus R2's fail-closed runtime manifest/gate. R3
adds the generated thin C shim and its C/Zig conformance gate. R4 builds that
same generated shim as `zig-out/lib/libproto-ui-shim.so` and validates it
through the host dynamic loader. R5 adds bounded host-frame to EUP-frame
identity/state/delete mapping, and R6 adds deterministic atomic
window/row/cursor/damage capture batches with replay byte-stability evidence.
R7 adds a source-authoritative, machine-checkable host-registration decision
contract.  Its policy decision is approved for candidate selection only, while
runtime registration and a real `output_proto` frame remain explicitly
unavailable.

The R7 reviewer packet packages the proposal, policy contract, selected host
adapter, blocked activation plan, and R8 readiness into one deterministic
SHA-256 provenance audit.  It remains fail-closed.  R8 can link the selected
static candidate only on a native Linux glibc target under an explicit option;
the audited state is `linked_not_registered`, never activation.

W14-a adds an opt-in, adapter-only hot-path benchmark in ReleaseFast. It
measures five memory-transport scenarios with deterministic 960x600 fixtures, reports
iteration/warmup counts, byte volume, monotonic p50/p95/p99/mean latency,
throughput, observed allocation counts, build mode, and protocol version. The
step installs the JSON report at `zig-out/proto-ui/benchmark.json`.
It is evidence only: success does not depend on host timing, the runtime
contract stays pending, and no SDL or inherited Emacs C/Lisp dependency is
introduced.

W14-b adds an opt-in SDL3 renderer benchmark over a deterministic ERP1 replay
scene.  It reports nearest-rank p50/p95/p99/mean latency, FPS, draw-command
totals, presented/skipped frames, renderer tier/name, and build mode.
W14-c adds bounded deterministic `typing_proxy`, `scroll_proxy`, and
`resize_proxy` renderer calls; they mutate only the frontend replay scene or
hidden SDL window geometry; resize setup is outside the timed renderer call.
The benchmark uses CPU wall-clock timing and makes no performance-improvement,
end-to-end, GPU-timestamp, real typing/scrolling/resize, redisplay, PGTK-
comparison, or host-independent regression claim.

W14-d adds an opt-in round-trip benchmark over the real bounded EPXL edit path.
It starts the owned public-facts publisher and alternates a backspace and a
bounded ASCII insertion at window point, one intent in flight per step, and
installs `zig-out/proto-ui/sdl3-epxl-roundtrip-benchmark.json` with
nearest-rank control-ACK and next-`FRAME_UPDATE` latency percentiles plus
submitted/acked intent and `input_lost` counts.  It is a bounded
public-facts-bridge, Debug-build, local-socket diagnostic only: no core
redisplay, renderer present, GPU timestamps, PGTK comparison, end-to-end
latency, or performance-improvement claim.

W9q adds the first bounded SDL3 touch-contact slice.  With `input.pointer_v2`
negotiated, one SDL finger contact is converted from SDL's window-normalized
coordinates to a pixel and emitted as `press` / `drag` / `release` / `cancel`
Pointer v2 intents, so Emacs keeps its existing public `posn` mapping and no new
wire record is introduced.  `sdl3-touch-tap-smoke` proves the exact phase order,
the converted coordinate, and that a second concurrent contact and
out-of-window coordinates are rejected.  The same translation is wired into the
live interactive EPXL loop.  Multi-touch gestures, pressure, pen input, and
Emacs gesture commands remain pending.

P84 adds the first bounded popup-menu interaction.  `Scene.menuPopupBounds` is
the single geometry source shared by the draw path and a new pointer hit test,
so a rendered row and a clickable row cannot drift.  With
`widget.menu_result_v1` negotiated, a primary press selects a
command/checkbox/radio row, a press outside the popup dismisses it, and Escape
reports the keyboard cancellation; separators, submenus, disabled rows, and
padding report nothing, and the matching release is consumed so it cannot also
become a text click.  The frontend never enables, disables, reorders, or
executes an item.  `sdl3-menu-hit-smoke` proves the selected identity, the
dismissal, the Escape cancellation, and the inert separator.  Keyboard
navigation, streaming hover highlight, submenu traversal, and Emacs command
execution remain pending.

P85 adds the matching bounded tool-bar interaction.  `Scene.toolbarLayout` is
the single geometry source shared by the SDL tool-bar draw path and a new
pointer hit test, so a drawn button and a clickable button cannot drift (the
shared layout also fixed items being drawn at an absolute x that ignored the
owning window origin).  With `widget.toolbar_click_v1` negotiated, a primary
press on a visible enabled button or toggle reports `TOOLBAR_CLICK(press)` and
the matching release reports `TOOLBAR_CLICK(release)` for the same item;
separators, spaces, disabled items, and presses outside the row fall through to
the ordinary pointer path, and a stale press whose toolbar generation was
replaced is dropped.  `sdl3-toolbar-hit-smoke` proves the pair, the identity,
the inert separator, and the stale-generation drop.  Icons, overflow, and Emacs
command execution remain pending.

P86 adds bounded dialog buttons.  `Scene.dialogLayout` is the single geometry
source shared by the SDL dialog draw path and a new pointer hit test: the
backend's `buttons` policy mask is presented in a canonical order (OK, Cancel,
Yes, No, Retry, Close), right-aligned in the box and shrunk uniformly when a
wide policy would overflow so every presented button stays inside the box.  With
`widget.dialog_result_v1` negotiated, a press on a standard button reports
`DIALOG_RESULT` with the backend identity and no input text, a press elsewhere
in the box is consumed, a press outside falls through to the ordinary pointer
path, and Escape reports cancel (or close) when the policy offers one.
`sdl3-dialog-hit-smoke` proves the button identity, the consumed body click, the
outside fall-through, and the Escape dismissal.  Text input fields, custom
buttons, file/color/font dialogs, and Emacs callback dispatch remain pending.

P87 adds the first bounded drag-and-drop slice, `dnd.bounded_v1`.  SDL reports a
drop as an ordered begin/position/file-or-text/complete sequence, so a bounded
frontend tracker accumulates one offer (`text/plain` for dropped text,
`text/uri-list` for a dropped file name) plus at most 256 payload bytes and, on
completion, sends the exact `DND_ENTER`/`DND_DROP`/`DND_DATA` triple through the
authenticated EPXL journal.  SDL does not expose the drag source's action
policy, so the frontend synthesizes the copy action and Emacs decides what the
drop means; the frontend never opens a dropped file.  Oversized payloads are not
reported rather than truncated.  `sdl3-dnd-drop-smoke` seeds one real SDL drop
sequence and requires the owned publisher to apply the bounded payload, so the
republished facts show the dropped text.  Drag-out, MIME negotiation, multiple
offers or files, drag positions, and drag cancel remain pending.

P88 adds bounded popup navigation over the same shared geometry.  The frontend
owns one highlight cursor for the open popup (presentation state that is never
encoded into EUP) and renders it as a highlighted row.  Pointer motion moves the
cursor to the selectable row under the pointer, and Up/Down move it to the
previous/next selectable row without wrapping, skipping separators, submenus,
and disabled rows; Enter chooses the highlighted row.  Every cursor change is
reported as exactly one `MENU_HOVER` transition — a `leave` followed by an
`enter` — and motion while a popup is open is consumed so it cannot also become
a text hover/drag sample.  `sdl3-menu-hit-smoke` proves the hover sequence, the
separator skip, the keyboard walk, and the Enter selection.  Streaming `move`
phases, submenu traversal, and backend-driven highlight dispatch remain
pending.

P89 adds bounded vertical-scrollbar interaction.  `Scene.scrollbarLayout` is the
single geometry source shared by the SDL track/thumb draw path and a new pointer
hit test.  A press on the thumb opens a relative drag session, a press on the
trough pages by exactly one viewport in the matching direction, and a press
outside the track falls through to the ordinary pointer path; the matching
release ends the session, and a motion sample with the primary button no longer
held ends it too.  That last rule fixed a real leak: once the scrollbar was
touched, every later motion was still treated as a drag.
`sdl3-scrollbar-smoke` proves the thumb geometry, the drag delta, the session
lifecycle, both page directions, and the outside fall-through.  Horizontal
state, arrow-step geometry, and Emacs dispatch remain pending.

P90 adds the bounded pen slice, `input.pen_bounded_v1`.  With `input.pointer_v2`
negotiated, the pen tip is a left-button producer: air hover reports `motion`,
tip-down reports `press`, a tip-down motion reports `drag`, and tip-up reports
`release`, all reusing the strict Pointer v2 transport and Emacs's existing
`posn` mapping.  SDL reports pen positions in window coordinates rather than
normalized ones, so no normalization is applied.  The eraser tip, barrel
buttons, pressure axes, tilt, and proximity events produce no intent rather than
a guessed mapping, and the same translation is wired into the live interactive
EPXL loop.  `sdl3-pen-tap-smoke` proves the hover/press/drag/release order, the
eraser rejection, and the bounded journal ordering.  Pressure, tilt, barrel
buttons, drawing surfaces, and Emacs command dispatch remain pending.

P91 makes popup rows reflect the backend-owned item state.  A checkbox or radio
row reserves a leading marker slot, draws the selection marker when the model's
`selected` flag is set, and shifts its label past that slot; a row the model
marks as not `enabled` is drawn with a dimmer label color.  The frontend only
reflects those flags — it never enables, disables, or toggles an item — and a
separator row now draws no label at all, which also fixed a latent crash: the
draw list rejects empty text, so an open popup containing a separator used to
fail the whole render pass.  `sdl3-menu-hit-smoke` proves the marker, the
shifted checkbox label, the dimmed disabled label, and the bright enabled
label.  Submenu traversal, radio grouping semantics, and item icons remain
pending.

P92 renders tool-bar item icons.  An item that references an
`icon_image_id`/`icon_image_generation` pair resolving to a complete image
resource of exactly that generation draws that image in its slot; a missing,
incomplete, or stale generation falls back to the text label instead of drawing
a guessed icon, so the frontend never invents an icon, substitutes a different
generation, or keeps a deleted resource alive.  `sdl3-toolbar-hit-smoke` now
defines a 2x2 icon resource, proves the icon rectangle and exact pixels for a
live resource, that the icon replaces the label, and that a stale generation
falls back to the text label.  Overflow, orientation, item text beside an icon,
and multi-resolution icon bundles remain pending.

P93 adds a bounded prompt text field.  A prompt dialog tall enough to hold the
field shows one: while it is open the field owns SDL text input and Backspace,
so those bytes never reach Emacs as buffer input, and the accepted text rides
the bounded `DIALOG_RESULT` text tail when the user chooses a button or presses
Escape.  The field rejects control bytes, DEL, and non-ASCII bytes rather than
guessing, stops at its 128-byte capacity instead of overflowing, and is cleared
whenever the dialog opens, closes, or loses its owner window.
`sdl3-dialog-hit-smoke` proves the field rectangle, the accepted text, the
rejection of control and non-ASCII bytes, the render of the typed text, the
capacity bound, and the text tail on both the button and Escape paths.  Unicode
field input, an explicit caret, custom button labels, and file/color/font
dialogs remain pending.

P94 adds best-effort drag-position feedback and a shared idle-journal boundary.
A `SDL_EVENT_DROP_POSITION` while a drag is active now reports a bounded
`DND_POSITION`, and the same rule now also guards idle v2 pointer hover and pen
air hover: a best-effort observation is enqueued only when the bounded delivery
journal has no in-flight intent and an empty queue, so routine motion can never
fill the queue and turn a fast pointer or a slow backend into a session failure.
Ordered press/drag/release and every payload report stay exact.
`sdl3-dnd-drop-smoke` seeds two positions and proves exactly one is reported
(the later one is coalesced while the journal is busy) while the drop payload
still reaches Emacs.  Drag-out, MIME negotiation, multiple offers or files, and
drag leave/cancel remain pending.

P95 wires faces into the live text.  The bounded facts rows carry no
per-line or per-run face, so a window bound by `WINDOW_FACE` to a live face now
draws its body text with that face's foreground — and falls back to the draw
default when there is no binding, the generation is stale, or the face carries
no foreground.  The unicode text path uses the same color instead of its former
hardcoded one.  `sdl3-face-text-smoke` proves the fallback, the face foreground,
and that a replacement face generation is honoured on the next frame.  Per-line
faces, face merging, overlays, and shaped-text faces remain pending.

P96 closes the face loop on the live path.  The owned publisher now reports the
frame's real default face foreground and background as bounded `#rrggbb` values
in its snapshot (a literal `#rrggbb` is passed through unchanged so the terminal
color model cannot remap it, while a named attribute still goes through
`color-values`); the adapter parses them, projects a generation-qualified
`FACE_DEFINE` that only advances when the colors change, and re-sends the
per-window `WINDOW_FACE` binding after every `FRAME_UPDATE`, because an update
is authoritative window state that replaces that binding.  `sdl3-emacs-face-smoke`
proves the round trip end to end: the live scene owns the reported face, the
live window is bound to it, and the body text is drawn with it.  Per-line
faces, face merging, overlays, and shaped-text faces remain pending.

P97 renders bounded cursor styles.  The `CURSOR_UPDATE` v1 `cursor_kind` stays
opaque on the wire; the SDL frontend gives it a bounded rendering
interpretation — a solid box, bar, or horizontal bar (whose shape already comes
from the published cursor geometry), a four-edge hollow outline, or a
bottom-edge underline, with any unrecognised kind falling back to the solid box
that the frontend drew before styles existed.  Every shape stays inside the
cursor rectangle the backend validated, and the fill uses the owning window's
live default-face foreground when one is bound.  `sdl3-cursor-style-smoke`
proves all five shapes, the unknown-kind fallback, and the face-derived color.
Blink state and redisplay-owned cursor semantics remain pending.

P98 publishes Emacs's real cursor type onto the live path.  The owned publisher
maps the selected window's `cursor-type` to the bounded v1 `cursor_kind`
(`t`/`box`→1, `bar`→2, `hbar`→3, `hollow`→4, anything else→1) and stamps that
value into every facts snapshot, so a live `cursor-type` change reaches the
wire.  `sdl3-emacs-cursor-smoke` runs the owned publisher with a deterministic
`hbar` profile and requires the live SDL scene to own `cursor_kind` 3 and draw
the horizontal-bar shape.  Blink state, per-window cursor faces, IME-coupled
caret behavior, and redisplay-owned cursor semantics remain pending.

P99 publishes the live window scroll state.  The owned publisher reports, for
each observed window that has a scroll bar, the real buffer line count, the
window start, and a bounded scroll-bar width; when that width is nonzero the
adapter projects one bounded `WINDOW_SCROLL_STATE` per window and re-sends it
after every `FRAME_UPDATE`, because an update replaces the state, clamping the
position so a shifted window start can never exceed the scroll range.  A batch
Emacs frame has no scroll bars of its own, so `sdl3-emacs-scrollbar-smoke` pins
the width and a known window start; it reads back a real 30-line buffer scrolled
to line 11 and requires the live scene to own the proportional thumb (content
30, viewport 8, position 10).  Horizontal state, arrow-step geometry, and
core-owned scroll dispatch remain pending.

P100 closes the live scrollbar loop.  SDL reports window coordinates, so the
frontend's scrollbar policy now converts once to frame-logical units before the
hit test and the drag tracker — a scaled live window could previously hit the
thumb but never open a drag session.  The owned publisher consumes a delivered
bounded scroll intent and moves the target window's real `window-start` by that
many lines; `sdl3-emacs-scrollbar-interaction-smoke` pages the trough below the
thumb (position 10 to 18) and then drags the thumb (18 to 22, clamped at the
scroll range end), reading both back from the republished state.  Horizontal
scroll, arrow-step geometry, and full core dispatch remain pending.

P101 adds the horizontal scrollbar.  `WINDOW_SCROLL_STATE`'s second flag makes a
window's horizontal bar an independent state keyed by window *and*
orientation, so both bars of one window coexist; its fields are columns, its
track runs along the window's bottom edge and stops where the vertical bar's
column starts, and its thumb comes from `horizontalScrollbarLayout`, the mirror
of the vertical geometry source.  The drag tracker records its axis, so a
horizontal drag reports `axis = horizontal` and a trough press pages one
viewport sideways.  On the live path the publisher reports the widest visible
line and the real `window-hscroll`, and a delivered horizontal intent is
applied with `set-window-hscroll`; `sdl3-emacs-hscroll-smoke` drags the live
thumb ten columns and reads the republished offset back as 15.

P102 puts the real menu bar into the SDL window.  The owned publisher enumerates
the frame's live `menu-bar-keymap` after the menu filters ran, so the published
labels are the items a real Emacs would show and in display order (the fallback
click handler and labels this bounded publisher cannot express are skipped).
The adapter turns them into a bounded `MENU_MODEL` whose depth-0 nodes are those
items, sent only when the labels change because the model survives a
`FRAME_UPDATE`, and the frontend draws that model as a menu-bar row anchored at
the frame origin with each slot sized by its own label and the strip height
taken from the row the frame reserves above the window.
`sdl3-emacs-menu-bar-smoke` requires the live scene to own the real labels in
order and the draw list to render each of them.  `menuBarLayout` is also the
menu-bar hit test's single source of truth, so a press on a real slot is
reported to the backend as one bounded request (P103) instead of being acted on
locally.

P103 adds the reverse menu-open intent.  `MENU_OPEN_REQUEST` v1 is an exact
40-byte intent naming the backend-owned menu-bar item the user pressed, the
model identity it was shown from, the owning window, the active frame
generation, and the logical origin of that slot; it validates strictly and
travels in the negotiated acknowledged delivery queue like the other widget
intents.  With `widget.menu_open_request_v1` negotiated, a primary press on a
visible slot is consumed and sent, and nothing is opened locally — the frontend
still never opens, reorders, relabels, or executes a menu item.
`sdl3-emacs-menu-open-smoke` presses the real "Edit" slot of a live Emacs menu
bar and requires exactly one delivered request for that item with an empty
journal.  The backend does not yet open a menu or publish its popup from the
request, so submenus and command dispatch remain pending.

P104 makes that request open a real menu.  The owned publisher resolves the
requested id back to the live `menu-bar-keymap` entry, publishes that entry's
real child rows (labels and separators, bounded to 24) plus a bounded popup
rectangle clamped inside the owning window, and the adapter projects them into
the same `MENU_MODEL` the bar uses plus a `MENU_OPEN` naming the model
generation.  The SDL frontend then draws, hovers, navigates, and hit-tests real
Emacs menu items through its existing popup policy; choosing a row reports
`MENU_RESULT`, and the publisher closes the menu when it consumes that report so
the adapter dismisses the popup.  `sdl3-emacs-menu-open-smoke` proves the loop
end to end: press the real "Edit" slot, see the real Edit menu (rows including
"Undo"), choose the first selectable row, and watch the popup close.  Submenu
traversal and command execution remain pending.

P105 applies the choice.  When the publisher consumes a `MENU_RESULT` it maps
the chosen wire id back to the row it published, resolves that row's real
command from the keymap, and runs it only when the command is in a closed
headless-safe set (`undo`, `undo-redo`, `mark-whole-buffer`, `keyboard-quit`);
anything else is resolved but never executed, so an unattended publisher cannot
prompt or run arbitrary commands.  The publisher's smoke setup is also kept out
of the undo history, so the real Edit→Undo row can only undo what the frontend
itself sent.  `sdl3-emacs-menu-apply-smoke` proves it: seed one bounded edit,
open the real "Edit" menu, choose "Undo", and watch the edit disappear from the
republished facts because the real `undo` command ran.  Submenu traversal, item
publication, and non-allowlisted commands remain pending.

P106 runs the publisher against a display-backed frame.  A graphic profile
starts Emacs without `--batch` so it opens its own PGTK/X frame from the
inherited display, which is what makes the real `format-mode-line` text (empty
in a batch frame), a real 16-pixel scroll-bar width, and other display-only
facts observable at all; the frontend then draws that real mode line, so the
threshold for drawing mode-line text drops to eight pixels to admit a real
15-pixel mode line without giving one- or two-pixel diagnostic bars any text.
The publisher child now also inherits the display and locale environment
instead of running with an empty one, and the batch publisher runs `-Q` so the
probe stays independent of the user's init file.  `sdl3-emacs-graphic-smoke`
requires the live scene to own the real mode line (text, height, and a draw
command) and a real scroll-bar width, and reports a bounded skip when no display
server exists.

P107 gives the pointer wire one coordinate space.  The frontend now converts
SDL window coordinates to frame-logical units before building a pointer or
pointer-v2 intent, matching the geometry facts and the scrollbar and menu-bar
hit tests, and the publisher maps every pointer path through the owning window
(previously only the generic path did), so a press below the reserved menu-bar
row lands on the window row the user clicked instead of being read as a row
count in window space.  This also removes the conflict the P103 menu-bar press
introduced: pointer smokes now click inside the window body, and the
middle-click-paste evidence accepts a window manager's own point-min markers
instead of requiring an exact first line.

P108 uses the display-backed frame's real line metrics.  The publisher reports
the frame's character height (omitted for a one-unit batch frame), and the
adapter drives row spacing, cursor geometry, and the visible-row cap from it
instead of the bounded fifteen-row guess: a PGTK frame reporting 15-pixel lines
now lays its rows and cursor out at 15 pixels, so the real 15-pixel mode line
and the text rows share one rhythm rather than being stretched across an
87-pixel guess.  `sdl3-emacs-graphic-smoke` requires the live rows to be spaced
by the frame's own line height (`row_height:15`), and the row count stays capped
so the bounded row model does not grow.

P109 draws the real fringes.  A display-backed window reports its real fringe
widths (`window-fringes` is `(8 8)` for the default PGTK frame), and the
publisher reports them as bounded window facts; the adapter projects them as
the same `FRINGE_UPDATE` records the synthetic path uses, in the real
background color, and the frontend draws them as edge bars clipped to the
window.  `sdl3-emacs-graphic-smoke` now requires both a left and a right fringe
record and the matching draw commands (`fringe:[8,8] fringe_drawn:true`), and
the reserved fringe columns inset the layout for real: rows start after the left
fringe and are narrowed by both fringes, so body text and the cursor sit in the
text area instead of under a fringe.  Fringe bitmaps and draggable fringe
semantics remain pending.

P111 uses the real mode-line face colors.  The publisher reports the frame's
`mode-line` face `:foreground`/`:background` (the default PGTK theme says
`grey75` on `black`), and the adapter publishes them under a reserved
mode-line face id with the same generation-qualified `FACE_DEFINE` the default
face uses, so an unchanged face adds no traffic.  The mode-line draw path uses
that face's background and foreground for the bar and its text when it is
present and keeps the bounded diagnostic colors otherwise, which means the SDL
mode line finally looks like Emacs's mode line instead of a dark bar.
`sdl3-emacs-graphic-smoke` requires the published face and the matching bar fill
color (`mode_line_face_colors:true`).  Per-face text attributes, faces inside
one line, themes, and face merging remain pending.

P112 sizes the diagnostic text from the real frame.  The graphic frontend adopts
the published line height as its SDL_ttf point size whenever it looks like a real
font size (8..72) and reopens the font when the size changes, so glyphs fit the
rows the frame itself lays out (a PGTK frame's 15-pixel line now renders 15-point
text instead of a fixed 16) while `PROTO_UI_FONT_SIZE` still overrides
everything.  `sdl3-emacs-graphic-smoke` requires the renderer's active point size
to equal the live row height (`text_font_size:15`).  Real font families, font
files, per-face sizes, variable-pitch rows, and shaped text remain pending.

P113 uses the frame's real font file.  The publisher resolves the default
face's font object through `font-info`, takes the first existing font file the
info vector names (the element's position varies between builds) plus its pixel
size, and reports both bounded facts; the adapter publishes the file as a
bounded string resource under a reserved id, regenerated only when the path
changes.  The frontend's text renderer adopts that file and reopens it at the
adopted size, falling back to its bundled candidates whenever the resource is
absent or the file cannot be opened, so a PGTK frame's Liberation Mono renders
the diagnostic text instead of hard-coded DejaVu Sans.
`sdl3-emacs-graphic-smoke` requires the active font file to equal the published
resource and to be a real `.ttf` (`font_file:"LiberationMono-Regular.ttf"`).
Per-face fonts and sizes, variable-pitch rows, and shaped text remain pending.

P114 gives the cursor the frame's real character cell.  The publisher reports
the frame's `frame-char-width`, and the adapter uses it as the cursor's width
(never thinner than the two-unit diagnostic bar) and in the cursor-fit check,
so a PGTK frame with 8-pixel cells shows an 8-by-15 cursor block instead of a
2-unit bar.  `sdl3-emacs-graphic-smoke` requires the live cursor to be one real
cell wide and one line tall (`cursor:[8,15]`).  Per-face fonts and sizes,
variable-pitch rows, and shaped text remain pending.

P115 extends the reserved live-face table.  The mode-line face publication became
one small helper, and the publisher now reports the frame's real `cursor` and
`fringe` face backgrounds too, each published under its own reserved face id with
the same generation-qualified `FACE_DEFINE`.  The cursor fill uses the published
cursor face (black on the default PGTK theme) instead of the window's default
foreground, and the fringe bars use the real fringe face background (`grey95`)
instead of the window background, so both match what Emacs itself draws.
`sdl3-emacs-graphic-smoke` requires both reserved faces and the matching draw
colors.  Per-face fonts and sizes, the scroll-bar face (unspecified in this
theme), variable-pitch rows, and shaped text remain pending.

P116 reserves the text area properly and restores manifest headroom.  A
display-backed window reserves both its fringe columns and its scroll bar, so
rows now stop before the scroll bar as well and the mode-line/header-line/tab-line
records span only the text area, which matches where Emacs itself draws them
(the graphic smoke's 2556-pixel window yields a 2524-pixel row).  The bounded
status-manifest test also moves from a 24 KiB to a 32 KiB runaway guard: the
manifest has grown with the feature set, so the old bound had become a
per-slice trimming tax rather than a useful limit.

P117 gives the split mirror its inactive mode line.  The publisher reports the
frame's `mode-line-inactive` face colors (the default theme says `grey90` on
`grey20` against the active `grey75` on `black`), the adapter publishes them
under another reserved face id through the same helper, and the diagnostic
mode-line draw path picks the face by the record's active flag, so a
non-selected window's mode line stops looking like the selected one.
`sdl3-emacs-graphic-smoke` now splits the real frame with a real `C-x 2` key
sequence, requires two mode lines, and requires the inactive window's bar to be
drawn in the published inactive color.  Per-face fonts and sizes, header/tab
face distinctions, variable-pitch rows, and shaped text remain pending.

P118 puts the live active region in the mirror.  When the region is active the
publisher maps its two endpoints through `posn-at-point`/`posn-x-y` (window
pixels, so the mapping is real) and reports one bounded rectangle plus the real
`region` face background (`lightgoldenrod2` in the default theme); the adapter
validates the rect, publishes that face under a reserved id, and reuses the
frontend's bounded visible-highlight record, so the same validation, ownership,
and draw path the synthetic mouse highlight uses now carries the region.  A
region whose endpoints are not visible, or that is larger than the bounded
limits, publishes nothing rather than a guessed rectangle.
`sdl3-emacs-graphic-smoke` pins one active region in the publisher profile and
requires the highlight record and its draw color (`region_highlight:true`).
Mouse-face capture, multi-rectangle regions, and per-line region shapes remain
pending.

P119 adds the manual graphic mirror target.  Every fidelity slice since P106
only becomes visible in a real session, so
`zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true
sdl3-emacs-graphic-interactive` now opens the same authenticated EPXL session
with a display-backed publisher (`--graphic-frame-publisher=true`), which means
the SDL window mirrors a real Emacs frame's own mode line and mode-line faces,
fonts, fringes, cursor cell, active region, menu bar, and scroll bar until it is
closed.  The automated `sdl3-emacs-graphic-smoke` remains the CI-checked proof
of those facts; this target is the operator's view of them.

P120 colors the visible lines.  Font-lock only fontifies a display-backed
frame, so the publisher resolves each visible line's per-character face
foregrounds, groups adjacent equal colors into at most six bounded runs per
row, and publishes a row only when its runs cover the whole line (a partially
colored line would hide text, because a row with glyph runs stops drawing its
plain text).  The adapter carries each run's row through the wire, validates the
runs, publishes each run's color as a reserved face, and emits the same bounded
face-bound glyph runs the synthetic path uses at that row's geometry, so the
mirror shows real syntax colors — the default theme's `VioletRed4` string and
`Firebrick` comment.  The publication is bounded to eight visible rows and
twenty-four runs, which spans the whole eight-line window the publisher reads.
`sdl3-emacs-graphic-smoke` pins three Lisp lines in the publisher profile and
requires at least two distinct run colors to reach the draw list
(`line_font_lock_runs:true`) and at least three rows to carry two or more
distinct colors (`line_font_lock_row_count`), so the evidence covers multi-row
font-lock instead of one line.  Per-run fonts, bold/italic/underline faces, face
merging, and shaped text remain pending.

P121 gives the aux lines their own faces.  The mirror already drew the header
line and tab line, but both used the mode-line face colors.  The publisher now
reports the frame's real `header-line` and `tab-line` face foreground/background
through the same `proto-ui--face-color` helper, the adapter validates them and
publishes each under its own reserved face id (`header_line_face_id`,
`tab_line_face_id`), and `drawDiagnosticWindowLine` picks the face from the
record's kind bits (header / tab / active-inactive mode line) with the
mode-line face as the fallback.  `sdl3-emacs-graphic-smoke` pins a header line
and a tab line in the publisher profile and requires both aux records plus
their own face-colored bars, reporting `header_line_face_colors` and
`tab_line_face_colors` (PGTK: header `#333333`/`#e5e5e5`, tab
`#000000`/`#d9d9d9`, so the tab bar is distinguishable from the mode line's
`#bfbfbf`).  Header/tab items, mouse faces, and PGTK parity remain pending.

P123 carries per-run face backgrounds.  A run's face background is published
only when it differs from the frame's default background, so a plain line keeps
its single-face text and only real face backgrounds travel; the adapter
validates the extra `background` half, publishes it on the same reserved run
face, and the existing glyph-run draw path fills that rect before the text.
The shared resolver also falls back to the default face for an unspecified
foreground/background, so a background-only face still contributes its own
foreground instead of dropping the row.  `sdl3-emacs-graphic-smoke` pins a
`#204060` background on the runs-smoke comment spans and requires the matching
fill (`line_font_lock_run_backgrounds:true`).  Underline/strike/overline and
bold/italic, face merging, and shaped text remained pending at that point.

P124 carries per-run face decorations.  The publisher resolves each
character's `:underline`, `:strike-through`, and `:overline` (each with the
default-face fallback) and folds them into the run grouping key, so a decorated
span splits a run; the adapter validates the three flags and publishes them as
`FaceStyle.single` on the same reserved run face.  The renderer's existing
`faceDecorationBars` path already drew those styles for glyph runs, so no draw
or protocol change was needed: the underline bar uses the run foreground when
no explicit decoration color is published.  `sdl3-emacs-graphic-smoke` pins an
underlined `"second"` span and requires a matching bar fill
(`line_font_lock_run_decorations:true`).  Bold/italic weight and slant, face
merging, and shaped text remain pending.

P125 mirrors a real screenful of window text.  The publisher used to send only
the first eight lines of each window; it now sends up to thirty-two (each line
still capped at 120 bytes), and the adapter accepts up to thirty-two lines per
window.  The viewport check no longer couples the window's absolute start line
to that line table — `start_line` is the real window-start line (used by the
scrollbar and damage tracking) and `line_count` is the bounded mirror — so a
window scrolled deep into a buffer still validates instead of being rejected.
The diagnostic scrollbar keeps its line-derived viewport, so the scrollbar and
interaction smokes now run against a 200-line buffer with a 32-line viewport
(page 10→42, drag 42→46).  `sdl3-emacs-graphic-smoke` requires at least
twenty-four mirrored lines and reports `mirrored_lines` (30 for the default
frame).  Full-screen redisplay capture, variable-height rows, and folding
remain pending.

P126 carries the real decoration colors.  The publisher resolves a face's
`:underline`/`:strike-through`/`:overline` color — a plain `#rrggbb`, or the
`:color` of a spec such as `(:color "red" :style wave)` — and folds it into the
run key; the adapter validates the three colors and publishes `FaceStyle.color`
with an explicit `underline_color`/`strike_color`/`overline_color`, so the
existing `faceDecorationBars` path draws the bar in the face's own color
instead of the run foreground.  `sdl3-emacs-graphic-smoke` pins a `#00a0a0`
underline on `"second"` and requires the matching bar fill
(`line_font_lock_run_decorations:true`).  Bold/italic weight and slant,
wave/dotted underline styles, face merging, and shaped text remain pending.

P127 honours `:inverse-video`.  The publisher resolves the flag per character
and folds it into the run key; the adapter validates it and publishes it on the
reserved run face, and the glyph-run draw path swaps the fill and text halves
(fill with the face foreground, draw the text with the face background) instead
of ignoring the attribute.  That is how the default theme's `match` and
`secondary-selection` faces read.  `sdl3-emacs-graphic-smoke` pins an
`(:inverse-video t)` span and requires the swapped foreground fill
(`line_font_lock_run_inverse:true`).  Bold/italic weight and slant, wave/dotted
underline styles, face merging, and shaped text remain pending.

P128 sizes the mirror's text from the frame's real font pixel size.  The
publisher already reported `font_pixel_size` (13 for the default PGTK font) but
the adapter only validated it — the renderer sized text from the line height
(15), so glyphs were one size too large for the row.  The adapter now publishes
the size as a second bounded string resource beside the font file
(`default_font_size_string_id`), the frontend parses it and adopts it as the
text point size, and the line height stays the fallback for scenes with no
font fact.  `sdl3-emacs-graphic-smoke` requires the active point size to equal
the published pixel size and not exceed the row height, reporting
`text_font_size:13` with `row_height:15`.  Bold/italic weight and slant,
variable-pitch rows, and shaped text remain pending.

P129 draws the mirror's text with the frame's real font.  Until now every ASCII
string (body rows, mode line, header/tab lines) went through SDL's eight-pixel
debug font, so the mirror's glyphs were both the wrong shape and the wrong size
next to P128's real point size.  The body rows, fontified runs, mode line, and
aux lines now emit font-backed text, vertically centred in the row with the
adopted font's real height (`TTF_GetFontHeight`), and the fallback for
non-ASCII is unchanged.  `sdl3-emacs-graphic-smoke` requires a plain body row
("Emacs Proto-UI") to reach the draw list as font-backed text
(`body_text_font:true`).  The menu bar, dialogs, tool bar, and tooltips still
use the bounded debug font, and bold/italic weight and slant, variable-pitch
rows, shaping, and the real tool bar remain pending.

P130 puts the menu chrome on the real font too.  The real menu-bar labels and
the bounded popup rows now draw through the adopted SDL_ttf font, centred in
their strip/row, instead of the eight-pixel debug font, so the whole live menu
path (bar and popup) matches the body.  `sdl3-emacs-menu-bar-smoke` requires
each real label to reach the draw list as font-backed text
(`font_backed:true`), and the runtime-bridge menu/patch scans were updated to
the same command.  Dialogs, the tool bar, and tooltips still use the bounded
debug font.

P131 renders per-run bold and italic.  The publisher resolves each character's
`:weight` (semi-bold and heavier) and `:slant` (italic/oblique) and folds both
into the run key; the adapter carries the style as two bounded glyph-run flag
bits, the frontend keeps them on the scene run, and the text renderer opens
(and caches) a styled variant of the adopted font with `TTF_SetFontStyle` and
keys the text cache by style so a bold glyph never reuses a plain texture.
`sdl3-emacs-graphic-smoke` pins a bold-italic span and requires the run to
reach the draw list with style bits set (`line_font_lock_run_style:true`).
Variable-pitch rows, per-character font selection within a run, and shaped text
remain pending.

P132 puts the remaining chrome on the real font.  Dialogs, the tool-bar strip,
tooltips, and the IME preedit/candidate boxes now draw through a shared
`drawLabel` helper that centres the frame font in the widget's band, so the
mirror no longer emits SDL's eight-pixel debug text at all.  The synthetic
widget smokes (`sdl3-toolbar-hit-smoke`, `sdl3-dialog-hit-smoke`, and
`sdl3-runtime-bridge-smoke`'s tooltip/dialog/tool-bar/IME checks) were updated
to the font-backed command, keeping the suppression and non-ASCII-filter
assertions.  Variable-pitch rows, per-character font selection within a run, and
shaped text remain pending.

P133 resolves overlay-aware faces.  The run publisher read the `face` *text*
property, which misses overlays; it now reads `get-char-property`, so the
highest-priority overlay face wins.  That picks up `hl-line`, `isearch`,
spell-check, and the active `region` face (the region smoke's pin now colors
its run with the real `region` background as well as drawing the highlight
rectangle), and it picks up any other overlay-driven highlighting.  Because a
row can now carry more distinct faces (text property + overlay + region), the
bounded runs-per-line cap moves from six to eight, still inside the
twenty-four-run snapshot bound.  `sdl3-emacs-graphic-smoke` pins an overlay
face and requires its color to reach a run (`line_font_lock_run_overlay:true`).
Face merging beyond Emacs's own resolved face, mouse-face, and shaped text
remain pending.

P134 positions font-lock runs on the frame's real character cell.  The run x
and width used a hardcoded eight-unit cell, which only happens to match the
default theme; the adapter now uses the published `char_width` (falling back to
eight when the producer reports none), so a frame whose cell is a different
width keeps its runs aligned.  `proto-ui-unit` pins a ten-unit cell and requires
the emitted glyph run to start at column × 10 with the matching width.
Variable-pitch rows, per-character font selection within a run, and shaped text
remain pending.

P135 colors every visible window.  The publisher only resolved runs for the
selected window, so after `C-x 2` the other window's body text stayed plain.
Each run now names its window, the publisher emits runs for up to two windows
inside the same bounded run budget, and the adapter maps each window's rows
into the scene's flat row table (a window's base row plus its local row) so the
glyph runs validate against the right window.  `sdl3-emacs-graphic-smoke` now
requires a run belonging to the non-first window after the split
(`line_font_lock_multi_window:true`), and `proto-ui-unit` pins the flat-row
index mapping for a two-window snapshot.  More than two windows, variable-pitch
rows, and shaped text remain pending.

P136 resolves the live `mouse-face` highlight.  The publisher records the last
pointer sample the frontend sends (including idle hover motion), resolves
`get-char-property point 'mouse-face` at that glyph, and reports a bounded
highlight rect plus the face's real background; the adapter publishes it under
a reserved mouse-face face id and the frontend keys highlights by (window,
face) so the region and mouse-face highlights coexist.  A new
`sdl3-emacs-mouse-smoke` drives a real synthetic pointer motion at the first
body row and requires the highlight (`mouse_face:true`).  Two details this
exposed: `mouse-face` *text* properties do not survive redisplay (Emacs removes
them after drawing), so the pin lives on an overlay — which is also how buttons
and links carry it — and the highlight arrives as its own message, so the smoke
samples it per applied message instead of only while a frame update holds.
P160 extends the same path to a span that covers several displayed rows (see
below): the publisher now reports one bounded rectangle per displayed row.

P137 mirrors the echo area.  The real frame reserves a bottom strip for the
minibuffer (the root window's bottom 15 pixels), which the mirror left empty.
The publisher reports `(current-message)` as a bounded `:echo` string, the
adapter publishes it as a reserved string resource (`echo_string_id`), and the
frontend draws it in that bottom strip with the frame font.  The graphic smoke
pins a deterministic message and requires the resource and its drawn text
(`echo_area:true`), and `proto-ui-unit` covers the parse/validation and the
resource publication.  The active minibuffer prompt face, completion UI,
multi-line echo, and shaped text remain pending.

P138 keeps the mode line's own segment faces.  `format-mode-line` returns the
mode-line string *with* its face properties — the default frame's buffer id
carries `mode-line-buffer-id` (bold) — but the mirror drew the whole line in one
face.  The publisher now resolves those per-segment faces into bounded runs
marked `:mode_line`, the adapter emits them as glyph runs anchored to the
window's first row (for validation) but positioned at the mode-line geometry,
and a new bounded glyph-run flag distinguishes them so the row's plain text is
not suppressed.  The frontend skips the single-face mode-line text when runs
exist for that window, and the bounded run total moves from 24 to 32 so both
body and mode-line runs fit.  `sdl3-emacs-graphic-smoke` requires a bold
mode-line run (`mode_line_face_runs:true`).  Header/tab-line segments,
variable-pitch rows, per-character font selection within a run, and shaped text
remain pending.

P139 falls back for scripts the adopted font lacks.  Emacs picks a covering
font per character, but the mirror opened only the frame's own font file, so
CJK and other uncovered scripts rendered as tofu.  The renderer now opens the
first available system fallback (WenQuanYi Micro Hei, Sarasa Gothic, Noto CJK,
Unifont, PingFang, Microsoft YaHei / SimSun), attaches it to the adopted font
and to each styled variant with `TTF_AddFallbackFont`, and closes it with the
rest of the font set on a size or file change.  `sdl3-emacs-graphic-smoke`
requires both an installed fallback and that CJK codepoints resolve through it
(`cjk_fallback:true`, checked with `TTF_FontHasGlyph`).  Per-character font
selection, shaping/BiDi, variable-pitch rows, and shaped text remain pending.
P140 opens the first bounded variable-pitch path. The publisher resolves a
face's file-backed font, compares it with the frame default, and reports one
alternate font resource plus `variable_pitch` on each run that uses it; the
adapter carries a reserved glyph-run flag, and the renderer opens that real
SDL_ttf font separately from the default and styled variants while keying its
texture cache by the flag. The graphic smoke pins DejaVu Serif beside the
default Liberation Mono and requires the run to reach the draw list with the
alternate-font flag (`variable_pitch_font:true`). This proves distinct font
families on bounded runs; further alternate families are bounded by P159, and
per-character font fallback within a run, exact variable metrics/hit testing,
shaping/BiDi, and shaped text remain pending.

P141 gives the header line and tab line their own segment faces.  Emacs returns
those lines from `format-mode-line` with their own face properties too, but the
mirror drew one face for each.  The publisher now derives bounded per-segment
runs for the mode line, header line, and tab line through one
`proto-ui--chrome-runs` helper, marking each run `:mode_line`, `:header_line`,
or `:tab_line`; the adapter anchors every chrome run to the window's first row
but positions it at that aux row's geometry (header at the window top, tab
below the header, mode line at the bottom) and carries a distinct bounded
glyph-run flag.  A plain chrome line is only suppressed by runs of its own
kind, which also fixes the P138 regression where a mode-line run hid the header
and tab text.  `sdl3-emacs-graphic-smoke` pins an accent face on the header and
tab lines and requires each run to reach the draw list in its face color
(`header_line_face_runs:true`, `tab_line_face_runs:true`).  Mixed chrome kinds
on one run are rejected, and per-character header/tab font selection and
non-ASCII segments remain pending.

P142 mirrors the real tool bar.  Emacs reserves a strip below the menu bar for
the frame's `tool-bar-map`, but the mirror only had a synthetic tool-bar model.
The publisher now enumerates the real keymap in display order and reports one
bounded item per binding — a separator or space, or a button/toggle with its
printable name, bounded command key, `:help` text, and the item's real
`:enable`/`:visible`/`:button` state, which it evaluates in the selected window
exactly as the frame's own tool bar does.  The adapter validates the items,
publishes them as the existing `TOOLBAR_MODEL` (one adapter-owned id, generation
advancing only when the items change), and the SDL draw path renders the real
labels; a batch frame with no tool bar publishes nothing.  The graphic smoke
requires the live model (thirteen items for the stock `-Q` tool bar) and that
its labels reach the draw list (`tool_bar`, `tool_bar_items`).  Real tool-bar
icons, overflow, orientation, and exact tool-bar geometry remain pending.

P143 puts the tool bar on the frame's real colors.  The mirror drew the
tool-bar strip with bounded diagnostic colors, but Emacs's `tool-bar` face is a
real `black`-on-`grey75` released-button face.  The publisher now reports that
face's `:foreground`/`:background` (only while the frame has tool-bar lines),
the adapter validates them and publishes a generation-qualified `FACE_DEFINE`
under a reserved `tool_bar_face_id`, and the SDL draw path uses the background
for the strip and buttons and the foreground for the labels, keeping the
bounded diagnostic colors otherwise.  `sdl3-emacs-graphic-smoke` requires the
published face and a strip/slot fill in its real color
(`tool_bar_face_colors`).  The diagnostic tool-bar placement (the strip still
overlaps the window's top strip because the mirror has no per-chrome geometry),
border styles, and exact PGTK tool-bar parity remain pending.

P144 carries the real `:box` face decoration.  Emacs gives the default
mode-line face a `(:line-width -1 :style released-button)` box — but the run
publisher only resolved underline/strike-through/overline and inverse-video, so
the mirror drew no box at all.  The publisher now resolves a face's `:box`
(its color when it names one) and folds it into the run key, and reports the
mode-line and tool-bar faces' bounded box style; the adapter validates both
(a box always carries a color, defaulting to the face foreground) and publishes
them on the reserved run faces and the reserved mode-line/tool-bar faces, and
the SDL draw path renders them through the existing `faceDecorationBars` box
approximation.  `sdl3-emacs-graphic-smoke` requires the real released-button
boxes on both chrome faces and a drawn tool-bar button border (`mode_line_box`,
`tool_bar_box`), and `proto-ui-unit` pins the bounded parse.  Full PGTK box parity remains pending.

P145 stops a non-ASCII line from breaking the whole mirror.  The bounded run
wire carries only printable ASCII, and the adapter rejects any run whose text
is not ASCII — but the publisher emitted a run for every character, so a single
non-ASCII character in any visible line (CJK, accented letters, smart quotes,
emoji) made the adapter reject the entire snapshot, which the live bridge
reports as `NoEmacsFacts` and leaves the mirror blank.  The publisher now
requires a printable-ASCII row (and chrome line) before publishing runs, so a
line with any other character keeps its plain-text path — which the mirror
already draws through SDL_ttf with the system fallback — instead of failing.
`sdl3-emacs-graphic-smoke` pins a CJK line among the font-lock rows and requires
the mirror to still publish and draw that line as plain text (`non_ascii_text`),
and `proto-ui-unit` pins the ASCII-only run contract.  Runs for mixed-ASCII
lines, shaping/BiDi, and per-character fonts remain pending.

P146 stops a long line from breaking a narrow mirror.  The adapter emits glyph
runs in window-relative coordinates because the draw path adds the window
origin, but the scene validated a run's `x + width` against the whole frame.
A line wider than the window (a URL, minified code, or any long line in a frame
narrower than the run's pixel width) therefore failed that bounds check and
rejected the entire snapshot, blanking the mirror the same way P145's non-ASCII
run did.  The adapter now clamps each run to the owning window — it skips a run
whose origin is past the window edge and caps the emitted width so `x + width`
never exceeds the window — which also keeps the fill, box, and damage geometry
inside the window.  `proto-ui-unit` reproduces the failure (a 120-column run in
a 600-pixel frame) and pins the clamped result.  Truncation versus continuation
of the overflowing text, and per-window clipping of the drawn glyphs, remain
pending.

P147 hardens the cursor the same way.  The adapter used to reject the whole
snapshot when a cursor did not fit its window (`fringe_left + column * 8 +
cell > window.width` or a line past the visible rows), which is the same
fail-blank failure mode as P146's long line.  It now clamps the cursor's line
and column into the window instead of failing, and `proto-ui-unit` pins both a
short window and a real column reaching the cursor rect.  The publisher still
bounds the per-window cursor column at nine (a bounded diagnostic cap — raising
it perturbed the pointer/menu/scrollbar interaction smokes), so the mirror's
cursor column remains a bounded diagnostic value; exact cursor column,
`window-hscroll`-adjusted cursor placement, and blinking remain pending.

P148 tracks the right cursor.  Every `CURSOR_UPDATE` used to set the scene's
single "current" cursor, so in a split frame the scene reported whichever window
was emitted last — often an inactive one — and the presentation gate, scene
hash, and cursor evidence all described the wrong caret.  The scene now keeps
the active cursor, and the SDL draw path marks a non-selected window's caret
hollow (four one-unit edge bars) the way Emacs draws an inactive cursor, while
the selected window keeps its real kind; an invisible cursor is skipped.
`sdl3-emacs-graphic-smoke` now splits the frame and requires the scene's tracked
cursor to be the active one with a solid rect plus a hollow inactive caret
(`inactive_cursor_hollow`).  Per-window inactive cursor shapes beyond the hollow
box, cursor blinking, and `cursor-in-non-selected-windows` policy remain
pending.

P149 keeps the mirrored rows aligned.  The publisher built its line list with
`split-string ... t` (drop empty elements) and dropped any line past the
120-byte wire bound, so a blank line or an over-long line vanished from the
list and every following row shifted up out of alignment with the real display
(and the cursor's line index moved with them).  The publisher now keeps
interior blank lines (dropping only a trailing element that a region-final
newline produces) and truncates an over-long line to the wire bound at a
character boundary instead of dropping it; the adapter skips emitting a
`TEXT_LINE_V2` record for a blank row (which the wire rejects) while keeping
every later row's index, so a blank line leaves a blank row rather than a gap.
`sdl3-emacs-graphic-smoke` pins an over-long line and a blank line in the runs
profile and requires the truncated row plus the row after the blank to stay
aligned (`row_alignment`).  Wrapped (visual-line) rows
and mirroring a line past the 120-byte bound in full are still pending.

P150 mirrors horizontal scrolling.  The mirror only reflected `window-hscroll`
in the scrollbar state; the text and font-lock runs always started at display
column zero, so whenever Emacs auto-scrolled a long line (`auto-hscroll-mode`
is on by default) the mirror showed the wrong part of the line.  The publisher
now drops each row's scrolled-off display columns before emitting its text and
starts each row's runs after the scrolled-off prefix (a wide-character-aware
`proto-ui--column-index` finds the character boundary), and it offsets the
cursor column by the hscroll amount, so the mirrored rows and runs match what
the real display shows.  `sdl3-emacs-hscroll-smoke` drags the real horizontal
bar to `window-hscroll` 15 and requires the base `visible ASCII textZ` line to
be mirrored as its remaining `extZ` (`text_trimmed:true`).  Wrapped
(visual-line) rows, hscroll-aware cursor placement beyond the bounded column
cap, and mirroring a line past the 120-byte bound in full remain pending.

P151 mirrors displayed rows, wrapping included.  The mirror's rows were the
buffer's logical lines, but with `truncate-lines` off (the default) Emacs wraps
a long line across several display rows, so a wrapped line appeared as one
mirrored row holding only its first 120 bytes.  The publisher now walks the
window's displayed rows with `vertical-motion` (bounded to 32 rows) and emits
one mirrored row per display row, and both the flat text and each window's rows
use that walk; the font-lock runs walk the same displayed rows, so they line up
with the rows they color.  `sdl3-emacs-graphic-smoke` pins a 1000-character line
(wider than the frame window) and requires the mirror to hold several rows of
its wrapped text (`wrapped_rows`), while the over-long/blank-line pins keep
their alignment.  The cursor's row still comes from the logical line delta, so
a caret on a wrapped continuation row is a known limitation (the display-row
cursor line perturbed the interactive window smokes), as is mirroring a
displayed row past the 120-byte bound in full.

P152 colours mixed ASCII/non-ASCII lines.  The bounded run wire is printable
ASCII only, so a row with any non-ASCII character kept no font-lock colours at
all (P145's fallback).  A run can now mark itself *partial*: it colours an
ASCII span of a row without replacing that row's plain text, and the draw path
keeps the plain text (which carries the characters the run wire cannot) while
drawing the partial runs over it.  The publisher emits partial runs for a mixed
row's ASCII spans, positioned by display column (a wide character advances the
column by two), and the adapter carries the bounded partial bit; a row with no
resolvable colour still falls back to plain text.  `sdl3-emacs-graphic-smoke`
pins `你好 note4` (a non-ASCII span plus a keyword-coloured ASCII span) and
requires both the plain text and a partial run (`line_font_lock_run_mixed`).
Shaped text/BiDi and runs that span a substitution remain pending.

P153 mirrors a full wide row.  The bounded row text was capped at 120 bytes
(shared with the mode line, echo, title, and cursor bound), so on a wide frame
(a maximized window on a large display with a small font is easily 200+ columns)
the mirror showed only the first 120 cells of every row.  The row and run text
now share a separate, larger `max_row_columns` (256 bytes) bound across the
publisher, the facts validators, the `TEXT_LINE_V2` codec, the SDL_ttf draw
path, and the text-texture cache key, while the chrome/echo/title/cursor bound
stays at 120.  `sdl3-emacs-graphic-smoke` requires a mirrored row longer than
120 bytes (`row_bound_256`, asserted only when the window is wider than 120 cells so the smoke is display-width independent), and its over-long-line pin still truncates rows
past the new bound.  Rows wider than 256 cells, the display-row cursor on
wrapped rows, and shaped text/BiDi remain pending.

P156 puts the echo area on the frame's real colors.  The mirror reserved the
frame's bottom strip for `current-message` but painted it with bounded
diagnostic colors (a dark strip and yellow text), so a message on a light PGTK
frame was drawn in colors the real frame never uses.  The strip now fills with
the frame's published default face background and draws the message with its
default face foreground (falling back to the diagnostic pair when no default
face is live), which is what the real minibuffer/echo area shows for a plain
message.  `sdl3-emacs-graphic-smoke` requires the drawn echo text to carry that
default-face color (`echo_face_color`).  The active minibuffer prompt's own
face, completion UI, multi-line echo, and message-specific faces remain
pending.

P157 makes a multi-line region a set of rows instead of one box.  The active
region is applied by redisplay rather than by a property, and the publisher
reported its two endpoints as a single bounding rectangle, so a region spanning
several lines collapsed to a narrow band matching neither the first line nor
the last.  The publisher now walks the displayed rows the region touches and
reports one bounded rectangle per row covering exactly the selected part of
that row; the adapter validates up to eight, publishes the region color under a
bounded block of reserved face ids, and emits one bounded highlight record per
row, which the frontend's `(window, face)`-keyed highlight table draws.
`sdl3-emacs-graphic-smoke` pins a three-line region on plain rows and requires
more than one region record plus the region color in the draw list
(`region_rects`).  Per-line shapes beyond one rectangle per displayed row, the
inactive-region face, and shaped text remain pending.

P159 carries more than one alternate font family per snapshot.  The publisher
already named each run's file-backed font (`:font_file`), but the adapter only
kept the single negotiated variable-pitch file, so a second distinct family
(for example a serif run beside a sans run, or any face that names its own
font) fell back to family 1.  The adapter now groups the distinct run font
files that are neither the frame default nor the negotiated variable-pitch file
into a bounded pair of extra families, publishes each as a reserved string
resource (`variable_font_string_id + 1`, `+ 2`), and carries a run's family as a
two-bit glyph-run field (family 1 keeps the existing `variable_pitch` flag, so
older publishers are unchanged).  The frontend stores the family on the scene
run, and the renderer keeps one alternate font handle per family, still keying
its texture cache by the full style byte so two families never share a texture.
`proto-ui-unit` pins two distinct alternate files as families `0/1/2/3` with
three published resources, and `sdl3-emacs-graphic-smoke` reports the live
`font_families` count (one on this theme, where only the serif variable-pitch
face differs from the default).  Per-character selection *within* a run, a
family that appears only through an unresolvable symbolic font, exact variable
metrics, and shaping/BiDi remain pending.

P160 makes the mouse-face highlight a set of rows instead of one cell.  The
publisher reported only the character cell under the mirror's pointer, so a
`mouse-face` span covering several displayed rows (a button, a link, or any
multi-line overlay) drew a single rect matching neither end.  The publisher now
finds the contiguous `mouse-face` span around the pointer (bounded to 400
characters each way), walks the displayed rows it touches, and reports one
bounded rectangle per row — the same shape as the P157 region — falling back to
the frame's character cell when a batch/TTY frame has no `posn-at-point` and no
visual-line layout; the adapter validates up to eight rectangles, publishes the
background under a reserved mouse-rect face block, and emits one bounded
highlight record per rectangle.  `sdl3-emacs-mouse-smoke` now pins an overlay
that spans three displayed rows and requires three highlight records
(`mouse_rects`:3).  Arbitrary region/mouse-face shapes beyond whole-row slices,
the inactive-region face, and shaped text remain pending.

P161 draws the real `:box` bevel and thickness.  The face payload already
carried a bounded `box_line_width`, but the adapter never set it and
`faceDecorationBars` drew all four border bars in one color at a guessed
`height * 0.08` thickness, so the released-button mode-line/tool-bar border was
a flat hairline.  The publisher now resolves each face's `:box` `:line-width`
(an integer or a horizontal/vertical cons; a negative width is relative to the
frame's border, so its magnitude is the bounded stand-in) into a 1..8 pixel
width, the adapter publishes it on the face payload — defaulting the box color
to the face foreground when the box names none — and the renderer uses that
width and draws a bevel: top/left lightened, bottom/right darkened for
`released`, the inverse for `pressed`, flat for `simple`, derived from the box
color so a black box still shows a readable edge.  `sdl3-emacs-graphic-smoke`
requires a real box width on both chrome faces and two distinct tool-bar border
colors (`tool_bar_box_bevel`, `tool_bar_box_width`:1).  Exact PGTK bevel
geometry (Emacs's own highlight/shadow faces, rounded corners) remains pending.

P162 carries each live menu row's real `:enable` state.  The publisher resolved
a menu item's label and command but never its `:enable` form, so the mirror drew
every popup row as available — Cut/Copy/Clear appeared enabled with no active
mark.  `proto-ui--menu-children` now also returns a parallel enable vector,
evaluating each item's `:enable` form in the selected window through the same
safe evaluator the tool bar uses (an absent form means enabled, an erroring form
stays disabled), and the open-menu facts carry it.  The adapter validates the
parallel vector (absent means every row enabled; a mismatched length is
rejected), projects a disabled row as a `MENU_MODEL` node without
`MenuNodeFlags.enabled`, and the existing popup draw path dims it while
`menuRows` skips it as non-selectable.  `sdl3-emacs-menu-open-smoke` requires the
real Edit menu's mark-dependent rows to arrive disabled
(`popup_enable_state`:true), and the apply smoke still chooses "Undo" once the
seeded edit makes it enabled.  P165 and P166 close `:keys`, `:filter`, and `:visible`; submenu
traversal remains pending.

P165 publishes and draws real menu key hints.  For each live popup row the
publisher resolves an explicit string `:keys` property, or the command's first
`where-is-internal` binding when the row omits it, and keeps only a bounded
printable key description.  The open-menu facts carry the parallel key vector
and the adapter rejects a mismatched non-empty vector.  `MENU_MODEL` stores each
key on its row and the popup draw path right-aligns it with the row's font
baseline.  `proto-ui-unit` pins the real Edit-menu keys and rejects a mismatched
vector; `sdl3-emacs-menu-open-smoke` requires both the live model and popup draw
list to contain a key hint (`popup_key_hint`:true).

P166 applies real menu visibility and filters before row enumeration.  The
publisher resolves both raw `menu-item` bindings and the normalized forms Emacs
returns from keymap traversal, applies `:filter` first, then evaluates a present
`:visible` form in the selected window.  A filter may replace the binding (which
therefore feeds safe-command resolution and `where-is-internal` key lookup) or
return nil to remove the row; an erroring filter removes the row.  Absent
`:visible` remains visible, and nil-bound separators survive unless a filter or
visibility form removes them.  `proto-ui-unit` now runs the
`proto-ui-menu-filter-unit` producer fixture across visible, hidden, separator,
filtered, filter-removed, and erroring rows.

P167 adds bounded one-level pointer traversal into real submenus.  The open-menu
facts now carry a parallel submenu vector and, for a nested popup, the parent id
and label.  The adapter projects the requested submenu row as the parent of
bounded depth-2 children so the existing `MENU_OPEN`/`MENU_MODEL` contract stays
unchanged.  The frontend identifies an enabled submenu row in the same popup hit
test used by drawing and navigation, then reports a normal negotiated
`MENU_OPEN_REQUEST` whose origin is that row’s right edge.  The publisher keeps
submenu keymaps adapter-local and replaces the popup through the same open
action.  `proto-ui-menu-submenu-unit` pins producer replacement, `proto-ui-unit`
pins nested facts and frontend hit/origin geometry, and the existing live menu
round trip remains green.  P168 completes one-level activation: an enabled
submenu row is highlighted by hover or Up/Down, motion/Enter reports the same
backend-owned open request as clicking it, and `sdl3-menu-hit-smoke` requires
both request paths.  P169 generalizes publisher state into a bounded selected
path: each ancestor is projected as a hidden submenu node, row IDs are
depth-specific, and traversal follows the existing protocol limit of four row
depths.  `proto-ui-menu-submenu-unit` now requires two successive selections
and the facts/model unit pins a depth-three ancestor chain.  Paths beyond that
wire bound and full PGTK popup parity remain pending.  P170 feeds real popup
checkbox/radio state from Emacs `:button` forms through bounded producer
`kind`/`selected` vectors; the adapter validates and projects them as model
state.  Producer and facts/model units cover on/off radio, checkbox, unaffected
commands, and mismatched vectors.  P171 allowlists one real Emacs radio group
and proves result application moves its published selection from Absolute to
Relative without frontend state mutation.  At this milestone, general radio grouping, icons, and
full PGTK popup parity remained pending.  P172 refreshes the documented gate
surface and removes stale hardcoded cursor-pixel assertions from older input
smokes, keeping their text and row semantics authoritative across real frame
fonts.  P173 publishes a toggle plus two independent radio groups in one
validated state vector and requires a distinct radio dot in the SDL fixture.  P174 allowlists Emacs's line-wrapping radio commands and proves closed result
application for two independent groups.  P175 carries generation-qualified image references on complete menu models and
patches, renders complete resources, and falls back to labels for missing/stale
resources.  P176 refreshes stale popup gate documentation.  P177 publishes bounded row
`:help` through a validated producer vector and proves it on the live Edit
menu.  P178 publishes validated generation-qualified references from real menu
`:image` specs.  P179 initially
rendered the highlighted row's bounded help through shared popup geometry in
the fixture and live Edit-menu smoke.

P180 wraps ASCII popup help by whitespace into a bounded owner-safe tip, while
non-ASCII help remains suppressed pending glyph metrics.  P181 reconciles the
gate wording: `sdl3-menu-hit-smoke` proves the rendered wrapped tip, while the
live smoke proves producer help and correctly permits frontend suppression.
P182 adds live capture of a bounded real XBM payload and requires its
generation-correct resource in the menu-open smoke.
P184 pins that a well-encoded malformed XBM emits no image resource and safely
falls back to the row label.
P185 pins that a payload above the decoded 4096-byte bound takes the same
per-row label fallback instead of rejecting the whole snapshot.
P186 records that boundary in the normative EPXL public-facts contract.

P163 gives line runs face-aware pixel advances.  The adapter previously
derived every run from `column × char_width` and `text.len × char_width`, so a
variable-pitch run had the right font but the wrong origin and width.  The
publisher now measures each printable ASCII character with `string-pixel-width`
against its resolved face and accumulates a bounded text-relative `pixel_x` and
`pixel_width` for both body and chrome runs.  The adapter validates the two
fields as a pair, uses them after the left fringe, and keeps the character-cell
calculation when they are absent.  `sdl3-emacs-graphic-smoke` requires the
variable run's drawn rectangle to equal the published pixel geometry and reports
`variable_pitch_metrics:true`.  The widths are unshaped, per-character advances:
kerning, BiDi, complete glyph runs, and exact hit testing remain pending.

P164 aligns the cursor with P163's run geometry.  Cursor placement previously
remained `column × char_width`, so a caret in a variable-pitch run stayed at the
monospace position even after the run itself was drawn at its measured pixels.
The adapter now locates the body run covering the cursor on the same displayed
window row; when that run has the bounded producer pair, it maps the cursor
column across the run's pixel width and uses that origin, while rows without a
matching run retain the cell fallback.  `proto-ui-unit` pins a variable-pitch
run at x=17/width=23 and requires the cursor at column 3 to land at x=28.
This is bounded run-space placement, not exact shaped-text hit testing,
wrapped-line cursor geometry, kerning, or BiDi.


W13-d adds deterministic process-level frontend crash isolation. The parent
passes a bounded, ordered corpus of valid and hostile EUP records to child
images of the crash-isolation executable. Malformed envelope, frame-update,
resource-snapshot, string/face/font/image, and `Scene.apply` cases must exit 0
with a machine-readable handled result. One controlled child exits nonzero and
the parent records it without becoming unhealthy. This proves frontend-process
containment only; it neither exercises inherited Emacs internals nor enables
`output_proto`.

W15-a adds the opt-in `proto-ui-compat` health gate for the existing Emacs
runtime.  It runs isolated batch checks for identity, text/undo, narrowing,
properties, faces, windows, scroll/recenter, and buffer locals; on a graphical
host it creates and deletes one real PGTK frame.  The report is
machine-readable and PGTK unavailable states are explicit skips.  This gate is
not Proto-UI runtime enablement and does not claim proto-frame compatibility.

W15-b extends that gate with a deterministic TTY/PGTK semantic matrix.  Seven
backend-neutral scenarios are executed in the isolated batch/TTY parent and, on
a graphical host, in a real PGTK child.  Each record carries a canonical
semantic signature and SHA-256 digest; ordered per-backend and per-pair digests
make a mismatch explicit.  Pixel sizes, fonts, frame identities/types, IDs, and
timing are excluded from digest input.  The Zig gate validates the full matrix
and recomputes every digest.  This remains evidence about existing Emacs
semantics only, not `output_proto`, proto frames, or complete PGTK parity.

W15-c adds `proto-ui-isolation-audit`, a deterministic disabled/default gate.
It scans inherited C/Header/Lisp files and generated `src/config.h`, when
present, for exact `output_proto`, `proto_ui`, and `proto-ui` markers; config
also checks `HAVE_PROTO_UI`.  Occurrences are reported even in comments.  The
scanner skips binaries, bounds file and count resources, and excludes
`src/proto-ui`, `test/proto-ui`, `tools/proto-ui-*`, docs, and build outputs.
The JSON report records the fail-closed runtime state and the source-owned
exclusions.  A marker, config finding, or oversized unreviewed text file fails
the gate.

P13 render-control preparation adds exact 40-byte `FLUSH` and 32-byte
`RENDER_HINT` EUP v1 payloads.  The runtime bridge emits `FLUSH` only for the
latest captured frame sequence; `Scene` validates the fixed wire form and
active frame generation, retains the present boundary and renderer preference,
and the SDL runtime-bridge smoke proves acceptance after a frame update.  This
is adapter protocol state; core redisplay emission and renderer pacing remain
pending.

P14 continuous-capture preparation lets a committed fake-host bridge begin a
strictly newer redisplay generation without rebuilding its terminal or frame.
The bridge atomically resets bounded observations and prior flush state only
after the host accepts the next capture.  `FLUSH` is emitted only after the
frame is explicitly accepted and the host flush callback succeeds; render hints
remain frame-lifetime policy across capture generations.  This prepares a
repeated host update cycle; it is not real redisplay capture or `output_proto`
registration.

P15 terminal-service preparation adds an adapter-owned orchestrator for
`PureRuntimeHostV1` terminal create/activate/drain/delete callbacks and the
existing no-reuse terminal registry.  Fake-host tests cover activation, safe
drain retry after host deletion failure, and rollback-pending cleanup.  This
remains fail-closed preparation.  R7 approval is recorded and a real Emacs
terminal remains absent.  The adapter candidate can be linked only by the
explicit native-glibc R8 option, and linked is not activated.
`zig build -Dproto-ui=true proto-ui-terminal-service` runs the deterministic
fake-host evidence gate and reports `emacs_registered=false` plus
`runtime_available=false`.

P16 host-adapter selection preparation adds a versioned pure-SDL3
`output_proto` candidate policy.  The approved, metadata-complete R7 decision
now selects the candidate for future linkage.  The candidate forbids
inherited-source edits, backend fallback, and frontend ownership.  The gate
reports `selected=true` while activation, linkage, registration, and runtime
remain absent.

P17 runtime-activation preparation defines the approved activation order and
reverse rollback order.  A selection-gated controller can exercise the path with
a linked fake host, but the selected repository candidate is unlinked.  Its
gate is `blocked_by_linkage_or_registration`, performs no Emacs host callback,
and reports `runtime_available=false`.

P18 damage-array preparation adds `DAMAGE_RECTS` v1.  The codec carries
1..256 active-frame logical rectangles, `Scene` atomically replaces its damage
set, and the runtime bridge emits observed arrays in the SDL smoke.  This
improves explicit protocol damage observability; true redisplay-owned
incremental damage remains pending.  A second smoke pass now uses the explicit
rectangle as a retained-target clip and reports clipped-present counters.

P19 clear-area preparation adds `CLEAR_AREA` v1 as a 40-byte face-colored
rectangle.  `Scene` validates the active frame, live face generation, and
window-relative bounds before storing one of at most 64 areas; the SDL draw
list renders the validated face background.  This remains adapter-owned
render-control evidence, not redisplay-owned capture.

P20 scroll-optimization preparation adds `SCROLL_RUN` v1 as a bounded
full-window-width vertical copy.  `Scene` validates both bands against the
owner and the renderer policy reports overlap plus estimated RGBA upload bytes.
The runtime smoke now executes the copy through a scratch target snapshot and
records planned bytes/submitted commands.  Redisplay-owned scroll semantics and
GPU batching remain pending.

P21 border-style preparation adds `BORDER_UPDATE` v1 as a bounded 16-byte
side mask, thickness, RGBA color, and generation payload.  `Scene` validates
the active frame and the SDL draw list renders selected window edges with the
requested color/thickness.  This improves bounded border styling; full
window-manager border semantics and core-owned geometry remain pending.

P22 divider preparation adds `DIVIDER_UPDATE` v1 for bounded vertical or
horizontal dividers.  `Scene` validates active frame/window bounds and replaces
a divider only with a strictly newer generation; SDL renders its fixed-color
geometry.  Draggable divider semantics remain pending.

P24 face-decoration preparation adds policy-derived underline, overline,
strike-through, and box-edge bars to the SDL debug glyph path.  Dedicated face
colors are honored when present; font metrics and full shaped-text parity remain
pending.

P23 fringe preparation adds `FRINGE_UPDATE` v1 as bounded left/right color
bands.  `Scene` validates active frame/window bounds and strictly newer
generations, while SDL renders the validated bands.  Bitmap glyphs and
redisplay-owned fringe capture remain pending.

P30 window-default-face preparation adds `WINDOW_FACE` v1.  The Scene requires
the active frame and owner window, validates the exact live face generation,
upserts one bounded state per window, and removes dependent states on face
replacement/patch/delete.  SDL renders the validated background over the owner
window as evidence only; redisplay-owned face capture and PGTK face parity
remain pending.

P31 window-geometry preparation adds `WINDOW_GEOMETRY` v1.  `Scene` validates
owner-relative content and body rectangles against the active live window,
upserts one bounded geometry per window, clears it on authoritative updates,
and invalidates it on shrink/delete.  SDL draws the validated body boundary as
evidence; redisplay-owned layout and complete zone/PGTK parity remain pending.

P32 window-zone preparation adds `WINDOW_ZONES` v1 with nine bounded region
slots, strict disjoint/owner containment checks, body-conflict validation, one
upsert per window, and SDL top-boundary evidence.  Redisplay-owned layout,
complete widget geometry, and PGTK parity remain pending.

P33 window-position preparation adds `WINDOW_POSITION` v1 as a bounded
diagnostic identity/start/point fact.  It contains no buffer text or layout
authority; complete point, narrowing, invisible-text, BiDi, and viewport
semantics remain pending.

P34 runtime-face preparation adds a `PureRuntimeHostV1` redisplay face
observation, bounded `FACE_DEFINE` emission, and live-face checks for captured
runs.  This is an adapter-owned fake-host seam; real Emacs redisplay attachment
and complete face parity remain pending.

P35 runtime-font preparation adds a `PureRuntimeHostV1` redisplay font
observation, bounded `FONT_DEFINE` emission, and live font checks for
font-backed faces.  Real font rasterization and shaped rendering remain pending.

P36 runtime-image preparation adds bounded RGBA8 image define/fragment
observations, ordered validation, and `IMAGE_DEFINE`/`IMAGE_DATA` emission.
The first seam accepts at most four 1 KiB fragments per image; full-size image
capture remains pending.

P37 glyph-atlas preparation implements `ATLAS_DEFINE`, `ATLAS_PAGE_UPDATE`,
`ATLAS_GLYPH_ADD`, and `ATLAS_INVALIDATE` with bounded RGBA8 Scene ownership.
GPU texture upload, shaped-glyph rendering, and eviction policy remain pending.

P38 atlas-render preparation adds an SDL `image_region` command, a per-frame
page texture cache, and ASCII atlas-glyph rendering with debug-text fallback.
Persistent atlases, shaping, eviction policy, and full font parity remain
pending.

P39 shaped-atlas-run preparation adds `GLYPH_RUN` schema 3 with up to seven
bounded glyph records, face/font linkage, atlas-entry validation, and SDL
atlas-backed glyph drawing. Full shaping, BiDi, persistent run capture, and
complete font parity remain pending.

P40 runtime shaped-run capture preparation adds a bounded `ShapedRunRecord`
observation to the PureRuntimeHostV1 redisplay ABI, with duplicate-run rejection,
live face/font checks, and schema-3 EUP emission.  Real Emacs redisplay
attachment remains pending.

P41 R7-readiness audit synchronizes the fail-closed runtime contract with the
full redisplay callback inventory and records resource/shaped-run capture as
implemented adapter prerequisites.  The R7 decision is approved for policy and
candidate selection only; registration remains absent, while linkage is
available only as the explicitly gated native-glibc `linked_not_registered`
audit.

P42 mouse-highlight preparation adds `WINDOW_MOUSE_HIGHLIGHT` v1 as a bounded,
visible face rectangle.  The Scene validates active frame/header identity, owner
containment, exact live face generation, window deletion, face lifecycle, and
authoritative-update cleanup; SDL renders the validated rect.  Pointer motion,
Emacs mouse-face resolution, overlays, and PGTK parity remain pending.

P43 font-patch preparation adds `FONT_PATCH` v1 for bounded scalar descriptor
evolution with strict generation replacement and stale shaped-run invalidation.
Runtime smoke proves weight/generation evolution; real font objects, metadata and
metric patching, frame font changes, and PGTK parity remain pending.

P44 fringe-bitmap preparation adds bounded monochrome `FRINGE_BITMAP_DEFINE`/
`DELETE` v1 resources.  The Scene enforces generation lifecycle, snapshot
restore, and stale placement cleanup; SDL expands validated bits into a live
fringe placement.  Color bitmaps, authoring semantics, and PGTK parity remain
pending.

P45 bounded-tooltip preparation adds `TOOLTIP_SHOW`/`MOVE`/`HIDE` v1 with active
frame/window validation, exact-generation lifecycle, bounded strict UTF-8 text,
authoritative cleanup, and SDL box/text rendering.  Platform tooltip policy,
Unicode glyph rendering, accessibility, and PGTK parity remain pending.

P46 menu-model preparation adds `MENU_MODEL` v1 with a bounded authoritative
menu tree, strict UTF-8 and hierarchy validation, generation replacement, Scene
ownership, and a diagnostic SDL menu bar.  Open state, navigation, result
dispatch, native menus, and full menu semantics remain pending.

P47 menu-open preparation adds `MENU_OPEN`/`CLOSE` v1 with one bounded popup
tied to an enabled visible submenu and exact live generation.  SDL renders direct
child rows; navigation, selection results, native menus, and full menu semantics
remain pending.

P48 menu-result preparation adds `MENU_RESULT`/`CANCEL` v1 as bounded, ordered,
acknowledged reverse intents with live model/window/frame identity.  Hit testing,
keyboard navigation, core command execution, and PGTK parity remain pending.

P49 frame-patch preparation adds `FRAME_PATCH` v1, an exact 40-byte atomic batch
for selected visibility/focus/opacity/decoration/scale state with active-frame
lifecycle checks and SDL runtime evidence.  Complete snapshot and PGTK
frame parity are covered by the next slice and remain pending.

P50 frame-snapshot preparation adds `FRAME_SNAPSHOT` v1, an exact 128-byte atomic core presentation snapshot with strict geometry containment, Scene restoration, and bounded SDL evidence.  Full Emacs frame parameters and PGTK parity remain pending.
P52 menu-patch preparation adds `MENU_PATCH` v1 with ordered upsert/delete operations, strict generation and hierarchy validation, atomic Scene replacement, and SDL render evidence.  Full menu policy remains pending.
P51 menu-hover preparation adds `MENU_HOVER` v1, an exact 40-byte enter/move/leave reverse intent with phase-specific validation and negotiated acknowledged delivery.  SDL hit testing and menu highlight dispatch remain pending.
P53 tool-bar preparation adds `TOOLBAR_MODEL` and `TOOLBAR_CLICK` v1 with bounded UTF-8 items and negotiated press/release intents.  SDL renders a diagnostic row; icons, overflow, hit testing, command dispatch, and PGTK parity remain pending.
P54 tool-bar patch preparation adds `TOOLBAR_PATCH` v1 with ordered upsert/delete operations, strict toolbar generations, atomic Scene evolution, and SDL render evidence.  Moves, icons, overflow, and full toolbar policy remain pending.
P55 bounded-dialog preparation adds `DIALOG_OPEN`/`UPDATE`/`CLOSE`/`RESULT` v1 with message/prompt/confirm models, owner and generation validation, negotiated result delivery, lifecycle cleanup, and SDL diagnostic render.  Native/file/color/font dialogs, input fields, callback dispatch, and PGTK parity remain pending.
P57 real-window snapshot preparation projects bounded public live-window geometry and per-window point cursors into `FRAME_UPDATE`; the selected window owns the active EUP cursor and SDL receives other observed windows as authoritative boxes.  Cross-restart stable IDs, redisplay-owned cursor semantics, hierarchy, faces, and command dispatch remain pending; bounded per-window text, mode-line, header-line, and tab-line observations are now unit-projected.
P56 dedicated-scrollbar preparation wires `SCROLLBAR_STATE`/`EVENT` v1 to the existing bounded state/request codecs, adds negotiated DeliveryJournal/EPXL event admission and Scene alias dispatch, and keeps horizontal state, complete interaction policy, and Emacs dispatch pending.
P39 atlas-cache preparation adds a persistent SDL page-texture cache keyed by
atlas/page identity, generation, and page revision.  The runtime smoke requires
one upload followed by at least four cache hits; smoke-level renderer-reset clearing is wired; production-wide renderer-loss
integration and eviction policy remain pending.

W6-a adds the bounded EUP `STRING_DEFINE`/`STRING_DELETE` v1 contract and its
frontend-owned active table.  Strings are strict UTF-8, at most 4096 bytes, and
the scene retains at most 64 with strict generation replacement/deletion and
atomic cleanup.  This is adapter protocol evidence only: `resource.v1`,
faces, fonts, images, `output_proto`, and rendering parity remain pending.

W6-b adds the bounded fixed-layout `FACE_DEFINE`/`FACE_DELETE` v1 contract and
its frontend-owned face table.  It covers a strict 96-byte subset of face
attributes with optional font/stipple references, exact generation replacement
and deletion, bounded capacity, and explicit resync/teardown cleanup.  It is not
redisplay face capture, rendering, full Emacs face parity, or runtime
enablement; `resource.v1` remains pending.

W6-c adds the bounded fixed-layout `FONT_DEFINE`/`FONT_DELETE` v1 contract and
its frontend-owned font table.  It covers a strict 224-byte descriptor with
bounded UTF-8 family/foundry/style metadata, slant/spacing tags, weight/width,
optional size/DPI values, authoritative vertical and advance metrics, and
explicitly zero feature/variation/fallback counts.  Strict generation
replacement/deletion, bounded capacity, sequence continuity, frame-destroy
retention, and resync/teardown cleanup are tested.  This is not shaping,
rasterization, rendering, redisplay font capture, Emacs font parity, or runtime
enablement; `resource.v1` remains pending.

W6-d adds the bounded `IMAGE_DEFINE`/`IMAGE_DATA`/`IMAGE_DELETE` v1 contract
and its frontend-owned image table.  It covers a strict 72-byte static RGBA8
metadata record, ordered fragmented payload assembly, a 4 MiB aggregate
declared-byte budget, at most 8 active images, exact generation replacement and
deletion, and resync/teardown cleanup.  It is not image decoding, color
management, texture upload, scaling, rendering, redisplay image capture, Emacs
image parity, or runtime enablement; `resource.v1` remains pending.

W6-e adds an atomic `RESOURCE_SNAPSHOT` v1 restore for the concrete adapter
resource model.  A bounded snapshot carries up to 64 unique live/deleted
records, validates exact face/font/string/image payload encodings and identity
agreement, caps live image bytes at 4 MiB, and replaces the frontend's
string/face/font/image tables and shared registry only after a complete
replacement state is built.  This is protocol/frontend restore evidence, not
runtime enablement, rendering, full resource parity, or a claim that
`frame.output_proto` is available.

W4c-b1-p0 adds the executable EUP v1 codec, including envelope, capability, message-ID, and FRAME_UPDATE section conformance.  W4c-b1-t0 adds bounded memory-sink sequencing and ERP1 replay-file conformance.  W4c-b1-b0 adds the versioned adapter ABI, a fake-host conformance harness, and generated ABI artifacts under `zig-out/include/proto-ui`; none introduces runtime integration.  Inherited C/Lisp changes in the rollback patch are restoration-only and return Proto-UI runtime files to their pre-Proto-UI state.  The adapter source is the authoritative ownership manifest; generated JSON is only a non-normative ABI summary.

The documentation in this directory is the source of truth for the implementation workstreams.

## 3. Documents

Available:

| Document | Contents |
|---|---|
| [`architecture.md`](architecture.md) | System components, ownership model, backend integration, state model, failure rules, and compatibility contract |
| [`adapter-boundary.md`](adapter-boundary.md) | Normative adapter-first boundary, C-file restrictions, review gates, and rollback requirements |
| [`zig-build-adapter.md`](zig-build-adapter.md) | Normative Zig-build adapter runtime, versioned ABI, generated shim rules, and streaming redesign |
| [`output-proto-runtime.md`](output-proto-runtime.md) | Final `output_proto` host-adapter bridge, terminal lifecycle, recovery, build model, and first-frame task split |
| [`registration-seam.md`](registration-seam.md) | Terminal Provider Extension design, ABI ownership, registration/rollback order, first-frame acceptance, and explicit non-goals |
| [`protocol.md`](protocol.md) | Complete EUP v1 wire protocol, envelope, message IDs, payload semantics, and state machines |
| [`capabilities.md`](capabilities.md) | Backend, frontend, renderer, widget, and PGTK parity capability matrices |
| [`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md) | Normative pure-SDL3 target, ownership boundaries, protocol and parity gaps, differential gates, milestones, and final acceptance |
| [`frame-lifecycle-smoke.md`](frame-lifecycle-smoke.md) | Current real-frame lifecycle bridge smoke, scope, environment, and acceptance |
| [`sdl3-frontend.md`](sdl3-frontend.md) | SDL3 process model, window handling, input bridge, rendering pipeline, and platform integration |
| [`performance.md`](performance.md) | Performance tiers, budgets, test scenarios, instrumentation, and regression gates |
| [`implementation-plan.md`](implementation-plan.md) | Workstreams, concrete tasks, acceptance gates, and final definition of done |
| [`runbook.md`](runbook.md) | Current build/test commands, expected smoke behavior, and troubleshooting boundary |
| [`publisher-lifecycle.md`](publisher-lifecycle.md) | Bounded authenticated publisher contract, atomic facts, reverse-input gates, and shutdown ordering |

## 4. Core principle

```text
Emacs core decides what must be displayed.
EUP describes the display state and user intent.
SDL3 frontend decides how to render it.
```

The frontend never reads buffers, reruns redisplay, rewraps lines, or owns authoritative UI state.

Likewise, the adapter never embeds Proto-UI policy in inherited Emacs C code.  Emacs exposes or delegates through a stable boundary; the adapter translates and transports it.

## 5. Final runtime shape

```text
GNU Emacs core
  Buffers, windows, frames, faces, fonts, redisplay
        |
        v
output_proto terminal backend
  Zig backend logic exposed through the existing terminal ABI
        |
        v
EUP v1 protocol
  Session, resource, damage, frame update, and input messages
        |
        v
SDL3 frontend
  Windows, input, GPU renderer, platform integration
        |
        v
OS compositor / display
```

## 6. Planned build entry points

The target build entry points are:

```sh
# Build Emacs with the headless proto-ui terminal backend.
zig build -Dproto-ui=true

# Run protocol and adapter boundary tests.
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-recovery-diff
zig build -Dproto-ui=true proto-ui-crash-isolation
zig build -Dproto-ui=true proto-ui-isolation-audit

# Build the independent SDL3 frontend.
zig build -Dproto-ui=true -Dsdl3-frontend=true

# Run current frontend and real-frame lifecycle smoke tests.
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-focus-window-smoke
```

Additional facts, input, clipboard, recovery, renderer, and interactive smoke
steps are listed in [`implementation-plan.md`](implementation-plan.md).  The
final full-frame acceptance build remains future work.

## 7. Compatibility rule

Proto-UI is additive.

When disabled:

```sh
zig build
```

must preserve existing TTY, PGTK, Windows, macOS, Haiku, and Android behavior.

When enabled:

```sh
zig build -Dproto-ui=true
```

must not alter existing TTY, PGTK, Windows, macOS, Haiku, or Android behavior in the current adapter-only slice.  The eventual runtime-integration goal is to expose `output_proto` only after a separately owned stable seam and review.

PGTK is the reference for full-capability graphic behavior.  In the current
adapter-only slice Proto-UI does not replace PGTK.  The completed target is a
separate pure SDL3 `output_proto` runtime whose Proto frames do not initialize
or fall back to GDK/GTK; PGTK remains an independent reference build used for
semantic and visual differential acceptance.

## 8. Minimal target Lisp behavior

The first real SDL3-backed frame must support:

```elisp
(setq frame (make-frame '((window-system . proto))))
(select-frame frame)
(set-frame-size frame 100 40)
(switch-to-buffer "*proto-ui*")
(insert "Hello from Emacs via SDL3")
(redisplay)
```

The visible SDL3 window must show the inserted text, correct cursor position, default face, and frame chrome state reported by Emacs.

Deleting the frame must destroy the SDL window without crashing Emacs:

```elisp
(delete-frame frame)
```

## 9. Non-goals

EUP does not:

* Send buffer text for independent frontend layout.
* Move redisplay to the frontend.
* Require GPU acceleration.
* Expose raw GPU command buffers.
* Make SDL3 a dependency of Emacs core.
* Use emacsclient as the transport or command channel.
* Allow the frontend to evaluate Elisp.
* Intrusively modify inherited GNU Emacs C source.

## 10. Completion definition

The project is complete only when all of the following are demonstrated from the current repository:

1. `-Dproto-ui=true` builds and default builds remain green.
2. `output_proto` creates a real Emacs graphic frame.
3. Redisplay produces complete protocol-visible rows, glyph runs, faces, fonts, cursors, damage, and flush boundaries.
4. A real SDL3 frontend opens and operates the frame.
5. Keyboard, mouse, wheel, focus, resize, clipboard, IME, menu, dialog, tooltip, and scrollbar capabilities meet the documented baseline or have explicit negotiated fallbacks.
6. Multi-frame, monitor, DPI, and scale behavior works.
7. Replay, protocol conformance, fuzz, performance, and frontend smoke tests pass.
8. The PGTK parity matrix has an implementation status for every row.
9. Performance meets the documented baseline on the reference host.
10. Existing Emacs capabilities and CI remain intact.
11. The adapter-first boundary is satisfied: new subsystem behavior is adapter-owned, inherited C files carry no new Proto-UI modifications, and the adapter can be disabled or removed without changing core behavior.
