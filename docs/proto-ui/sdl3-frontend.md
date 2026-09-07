# SDL3 Frontend Design

Status: normative frontend design
Protocol: EUP v1
Renderer requirement: software fallback required; GPU acceleration optional

## 1. Purpose

The SDL3 frontend is an independent process that receives EUP state, opens real operating-system windows, renders Emacs frames, captures platform input, and returns user intent to Emacs.

It must be possible to start it as a real UI for Emacs without going through emacsclient.

## 2. Process model

```text
Emacs process
  output_proto backend + EUP server
        |
        | EUP over shared memory, Unix socket, or pipe
        v
SDL3 frontend process
  Protocol client, scene model, SDL event loop, renderer, platform bridges
        |
        v
OS windows and input
```

The frontend may be launched by the Emacs wrapper or independently. In both cases it connects using a local transport token and performs normal EUP negotiation.

## 3. Module map

| Module | Responsibility |
|---|---|
| `main` | CLI parsing, lifecycle, shutdown |
| `app` | Event loop, scheduling, suspend/resume |
| `session` | EUP connection, negotiation, sequence tracking, recovery |
| `protocol_client` | Envelope validation, decode, dispatch |
| `scene` | Frontend render model built only from EUP state |
| `window` | SDL windows and frame state |
| `display` | Monitors, workarea, DPI, refresh |
| `renderer` | Draw-list execution |
| `gpu` | GPU device/context selection and limits |
| `atlas` | Glyph and image texture cache |
| `text` | Glyph placement, raster policy, fallback |
| `image` | Texture loading and animation |
| `input` | SDL to EUP input translation |
| `ime` | Platform IME integration |
| `clipboard` | Selection/clipboard access |
| `dnd` | Drag-and-drop bridge |
| `widgets` | Menu, dialog, tooltip, scrollbar rendering |
| `diagnostics` | Timing, counters, logs |

## 4. Startup sequence

1. Parse transport endpoint, session token, log level, renderer preference, and
   present-mode preference.
2. Initialize SDL subsystems.
3. Connect EUP transport.
4. Send `HELLO`.
5. Negotiate capabilities.
6. Receive resources, frame snapshots, and window-tree snapshots.
7. Receive `SESSION_READY`.
8. Build the initial scene without presenting partial state.
9. Enter the event/render loop.
10. Send `READY_ACK`.

If negotiation fails, the frontend exits with a diagnostic. Emacs must survive.

## 5. Window lifecycle

### 5.1 Frame creation

On `FRAME_CREATE`:

1. Validate frame ID/generation.
2. Create an SDL window when multi-window is supported.
3. Associate the SDL window with the EUP frame ID.
4. Apply title, icon, geometry, decorations, fullscreen, maximize, and alpha where available.
5. Create a renderer or surface for the window.
6. Mark the frame ready for updates.

On `FRAME_DESTROY`:

1. Stop accepting updates for the frame.
2. Release textures, atlas references, and render targets owned by the frame.
3. Destroy the SDL window.
4. Remove the frame from the scene.

### 5.2 Geometry

The frontend distinguishes outer, content, text, window, and body rectangles. Logical pixels are converted using frame scale.

OS resize requests are sent to Emacs as `WINDOW_REQUEST`. Emacs decides final geometry and sends authoritative EUP geometry.

### 5.3 Fullscreen and maximize

Supported states:

```text
normal
fullscreen
fullscreen desktop/current monitor
maximized horizontally
maximized vertically
```

If SDL or the platform cannot represent a requested state exactly, the frontend reports actual state and marks the capability degraded.

### 5.4 Child and tooltip frames

A complete implementation maps child frames to dependent SDL windows or composited render surfaces. Tooltip frames may use native tooltips, custom overlay windows, or scene overlays.

Parent/child semantics and visibility remain controlled by Emacs.

## 6. Protocol client requirements

The client must:

1. Validate magic, version, envelope size, payload size, and checksum.
2. Track sequence and session generation.
3. Decode control, resource, input, frame, widget, and diagnostic messages.
4. Apply resources before dependent frame updates when ordering allows.
5. Detect missing resources and send `RESOURCE_REQUEST`.
6. Apply each `FRAME_UPDATE` atomically.
7. Send present feedback.
8. Request resync on inconsistency.

It must not mutate semantic EUP state before validation completes.

## 7. Scene model

The frontend scene is a render cache, not an alternative Emacs data model.

Scene objects include:

```text
frame state
window region
zone geometry
row
render item
glyph run
cursor
fringe
divider/border
scrollbar visual
image/texture reference
menu/dialog/tooltip overlay
damage list
```

The scene is rebuilt incrementally where possible. A full rebuild occurs after snapshot, resync, renderer loss, or frame-scale change.

## 8. Rendering pipeline

### 8.1 Frame update application

1. Validate resource references.
2. Apply frame parameter patch.
3. Apply window patches.
4. Replace or update rows.
5. Replace or update render items.
6. Update cursor, fringe, divider, border, and scrollbar state.
7. Merge damage rectangles.
8. Record present hint and deadline.

### 8.2 Draw graph

```text
begin frame
  acquire window surface/target
  apply scale and logical transform
  clear damaged regions
  draw frame background
  draw window backgrounds
  draw margins
  draw glyph runs
  draw images
  draw stretch/rect items
  draw fringes
  draw dividers and borders
  draw mode/header/tab lines
  draw scrollbars
  draw cursor
  draw widgets and overlays
  present damaged or full region
end frame
```

Draw order preserves EUP row and item order within a row. BiDi ordering is already visual order.

### 8.3 Text rendering

| Mode | Meaning |
|---|---|
| Frontend raster | Frontend loads/rasterizes font resource and fills glyph atlas |
| Backend atlas | Backend supplies glyph pixels; frontend uploads/caches |
| Hybrid | Normal glyphs frontend raster; fallback glyphs backend atlas |

Requirements:

1. Emacs metrics are authoritative.
2. The frontend must not reshape or reorder glyph runs.
3. Baseline, ascent, descent, advance, and offsets come from EUP.
4. Atlas misses fall back without blocking semantic updates.
5. Missing glyphs render a deterministic fallback.

W10d adds the first bounded scene storage and debug-draw execution for
negotiated `render.glyph_run_debug_v1`.  It accepts the exact 60-byte v1
header plus 1..120 printable-ASCII bytes, retains at most 64 active owned text
buffers, validates active frame/window/row context and frame bounds, and
replaces a run only with a strictly newer generation.  The SDL draw path emits
the existing ASCII debug-text command at the run's logical position.  This is
not redisplay ownership or the production glyph path: no shaping, BiDi
reordering, faces, fonts, atlas entries, images, widgets, Emacs capture, or
`output_proto` registration is claimed.

### 8.4 Images

Image resources become textures. The frontend honors format, stride, alpha mode, color space, scaling filter, mipmap policy, cache policy, and animation timing.

Unsupported formats negotiate down to RGBA8 or are reported unsupported.

### 8.5 Damage and present

Preferred order:

1. Damage-only GPU present.
2. Partial surface update followed by buffer present.
3. Full redraw.

The frontend never presents a partially decoded update. It applies the complete `FRAME_UPDATE` first.

Present modes:

```text
vsync
adaptive vsync
mailbox
immediate
```

EUP present hints are advisory. The frontend reports actual mode and timing.

## 9. Renderer tiers

### Tier 0: software fallback

Required. CPU raster, no GPU dependency, complete semantics, full redraw allowed.

### Tier 1: GPU basic

Production minimum. GPU window surface, texture atlas, image textures, blend/scissor, damage redraw, and vsync.

### Tier 2: GPU advanced

Performance target. Persistent glyph atlas, image cache, async upload, damage-only present, multi-window batching, and frame pacing.

### Tier 3: low latency/high refresh

Optional. VRR, mailbox/low-latency present, GPU timestamps, zero-copy shared texture, and 120Hz+ scheduling.

Current selection policy:

| Request | Behavior |
|---|---|
| `auto` | Ask SDL for its best renderer, then classify the actual name/tier. |
| `software` | Create the SDL software renderer. |
| `gpu` | Try the SDL GPU renderer first; if unavailable, fall back to software. |
| named driver | Try the requested SDL driver only. |

The frontend reports the actual renderer name and capability tier. It does not
infer GPU acceleration from a request that failed. W10b-b1 builds an
adapter-owned clear/fill/text draw list and executes the same list through SDL
software and GPU-backed renderers. The production atlas, image resources,
scissor/blend graph, and GPU counters are still required before a Tier 1/2 claim
means full production performance.

## 10. Input bridge

### 10.1 Keyboard

SDL keyboard events map to `KEY_EVENT`; text input events map to `TEXT_INPUT`.

Required fields include physical key, logical key, platform key, Unicode text, modifiers, state, repeat count, layout ID, lock state, and timestamp.

The frontend does not resolve Emacs key bindings.

W8a implements the first bounded translation policy: pressed, unmodified
backspace and cursor-direction keys map to facts-profile `KEY_EVENT`; bounded
UTF-8 `TEXT_INPUT` is copied into a fixed queue. Key release, repeat, modifiers,
empty/NUL/invalid-UTF-8/oversized text, and queue overflow are rejected.
W8g adds negotiated `input.text_unicode`; an ASCII-only negotiated set still
accepts printable ASCII and rejects non-ASCII without queue side effects. A
synthetic SDL event smoke verifies this path.

W8h adds optional `input.key_full_v2`. When negotiated, SDL key down, up,
and repeat events become strict v2 intents with scancode, logical-key name,
folded left/right modifiers, and explicit state/repeat. Printable unmodified
presses defer to `TEXT_INPUT`; ASCII-only peers continue using the existing
4-byte profile. The frontend never evaluates Elisp. The EPXL Emacs bridge
ACKs observed v2 events and may execute only a tiny explicit compatibility
subset; all other events remain observed/unhandled. This is not full keymap,
IME, or command execution parity.

W11a implements the first clipboard capture path: Ctrl+V reads SDL clipboard
text, validates it as a bounded one-line UTF-8 payload, and frees SDL-owned
text on every path. W11c adds optional `clipboard.text_unicode`; without it,
non-ASCII paste is rejected without queue mutation. Rich text, MIME selection,
ownership events, and external clipboard targets remain pending.

W11b implements the opposite bounded smoke path: Ctrl+C publishes a first-line
Emacs buffer artifact after `kill-ring-save`; SDL3 installs only a non-empty,
bounded payload. W11c gates the Unicode copy direction on effective
`clipboard.text_unicode`: the Emacs-owned adapter explicitly encodes UTF-8,
publishes `base64:<RFC 4648 bytes>`, and SDL decodes and verifies the exact
UTF-8 bytes before `SDL_SetClipboardText`. Without that capability, copy retains
the ASCII path. MIME, selection ownership, external targets, and rich text
remain out of scope.

W8b-a adds a persistent public-fact bridge: the SDL loop writes one translated
action to an atomic local file, waits for consumption, polls the republished
public facts, and rebuilds the scene. This is not persistent EPXL input and not
a full keyboard surface; modifiers, Unicode, pointer, keymaps, and
redisplay-owned sessions remain pending.

### 10.2 Platform focus and window requests

W9m adds optional `platform.focus_window_events`. SDL focus gained/lost maps to
`FOCUS_EVENT`; close, resized, moved, minimized, maximized, and restored window
events map to the corresponding strict `WINDOW_REQUEST`. The adapter supplies a
nonzero protocol frame ID and preserves the nonzero SDL WindowID. Unknown SDL
window events remain unobserved. Without effective negotiation, translation is
rejected before queue mutation.

Platform intents join the existing bounded delivery queue and use the same
one-in-flight EPXL ordering and exact-sequence ACK discipline as input. The
opt-in synthetic smoke verifies focus gained, resize, and close order. It never
turns a synthetic close into Emacs destruction.

### 10.2 Mouse and wheel

SDL mouse events map to `POINTER_EVENT`.

Required behavior:

1. Convert coordinates to EUP logical frame coordinates.
2. Include buttons, modifiers, and click count.
3. Generate enter, leave, motion, press, release, drag, and cancel states.
4. Translate wheel/touchpad motion to `WHEEL_EVENT`.
5. Preserve event order per pointer.

### 10.3 Window and monitor events

SDL window/display events map to `WINDOW_REQUEST`, `FOCUS_EVENT`, `MONITOR_EVENT`, `DPI_EVENT`, and `THEME_EVENT`.

Resize, move, and fullscreen are requests, not commands. Emacs sends authoritative geometry.

### 10.4 Touch and pen

Touch and pen are protocol-defined but optional implementation capabilities. If unsupported, the frontend must not claim the capability.

## 11. IME integration

The frontend owns platform IME contact.

Flow:

1. Backend sends `IME_ATTACH` and cursor rectangle.
2. Frontend activates the platform input context.
3. Frontend reports `IME_ATTACHED`.
4. Platform preedit updates are reported with `IME_PREEDIT_UPDATE`.
5. Commit text is sent with `IME_COMMIT`.
6. Candidate placement uses `IME_CURSOR_RECT`.
7. Focus loss reports blur/detachment according to platform state.

If the platform cannot delete surrounding text, the frontend must not advertise that capability.

## 12. Clipboard, selection, and DND

### 12.1 Clipboard

Core sends ownership intent and offered MIME types. The frontend publishes them through platform APIs.

When another application owns the clipboard, the frontend reports `SELECTION_LOST`.

Paste produces a frontend request and then `CLIPBOARD_DATA` or an error.

### 12.2 Selection

`PRIMARY`, `SECONDARY`, and `CLIPBOARD` are separate EUP selections. The frontend maps them to platform semantics where supported.

### 12.3 DND

The frontend reports enter, position, leave, drop, cancel, MIME offers, and data. Emacs decides accepted action and data policy.

The frontend must not open dropped files or infer Emacs commands.

## 13. Widgets

### 13.1 Rendering modes

| Mode | Description |
|---|---|
| Native platform | OS/system toolkit widget |
| Custom GPU | Frontend-drawn widget in main renderer |
| Custom CPU | Frontend-drawn software widget |
| Glyph fallback | Emacs redisplay draws equivalent content |

The mode is negotiated separately for menu, dialog, tooltip, scrollbar, and tool bar.

### 13.2 Menu

The frontend receives semantic menu model and placement. It handles navigation and interaction, then returns selected item or cancellation.

It must not enable/disable items independently.

### 13.3 Dialog

The frontend renders modal or non-modal dialogs. Results include button selection, prompt text, file paths, color, font, and custom fields.

File paths are returned as strings. The frontend does not open them.

### 13.4 Tooltip

Tooltips may be native, overlay windows, or scene overlays. Emacs owns content and requested placement.

### 13.5 Scrollbar

The frontend renders scrollbar state and sends drag/page/step intent. Emacs returns authoritative scroll state through redisplay.

## 14. Resource and memory policy

Frontend caches glyph atlas pages, image textures, icons, font instances, renderer contexts, scene objects, and widget assets.

Required policies:

1. Respect negotiated texture and memory limits.
2. Use generation-qualified resource keys.
3. Evict least-recently-used resources under pressure.
4. Never use stale generations.
5. Report eviction/upload statistics.
6. Keep emergency headroom for resize/fullscreen transitions.

## 15. Failure and recovery

| Failure | Required behavior |
|---|---|
| Reverse-input ACK lost before disconnect | Keep the bounded intent pending; retry the same EPXL sequence up to the negotiated attempt bound |
| Emacs disconnect | Keep window briefly, show disconnected state, or exit according to policy |
| Sequence gap | Request resync |
| Missing resource | Skip affected drawing and request resource |
| Corrupt update | Drop update and request resync |
| GPU device loss | Rebuild renderer and request full snapshot |
| Out of texture memory | Evict cache; downgrade to software if needed |
| Renderer panic | Exit frontend without affecting Emacs |

`--emacs-interactive` selects the authenticated EPXL interactive path by default. `--emacs-interactive-local` explicitly selects the older atomic local-action bridge for diagnostics and rollback. `sdl3-emacs-copy-smoke` uses the default EPXL path; `sdl3-emacs-copy-local-smoke` explicitly exercises that fallback.

The default EPXL interactive path also translates Ctrl+C to `KEY_EVENT.copy`. Emacs performs the bounded first-line kill-ring save, publishes a validated printable-ASCII result artifact, and SDL installs that result through its platform clipboard. `sdl3-emacs-copy-local-smoke` retains the explicit rollback path.

With negotiated `input.pointer_v2`, SDL motion and buttons 1..5 map to strict
v2 intents. Motion state maps to hover or the exact drag button mask, button
1..5 maps to left/middle/right/X1/X2, SDL click counts 1..8 are preserved, and
current SDL modifiers fold to EUP bits. The delivery journal rejects a drag
whose mask differs from the active mask and a release whose button/click state
does not match the active session. This is capability-gated and ordered by the
existing one-in-flight EPXL journal. The bounded pointer path remains the
explicit rollback/fallback profile.

The bounded pointer profile accepts zero-modifier idle motion and ordered
single-left-button press/drag/release sessions. Idle motion is best-effort and
coalesced to the idle journal boundary. Drag motion is admitted only while a
left session is active; release closes that session. Pointer intents use the
same EPXL sequence and ACK rules. Emacs maps accepted press/release endpoints
through public `posn-at-x-y` / `posn-point` and republishes the resulting
point; intermediate drag motion is not text-selection semantics.

With both `input.pointer_v2` and `input.pointer_selection_left` negotiated, the
opt-in `sdl3-pointer-selection-smoke` executes one additional bounded left-drag
subset. Press sets an active mark at public `posn-at-x-y` point, drag moves
point, and release moves point before `kill-ring-save` copies at most 120
printable-ASCII characters to the existing validated clipboard artifact. This
is not full mouse parity: no right-click menu, touch/pen, multi-window hit
testing, overlays, or variable-pitch hit testing.

With `input.pointer_middle_paste` also negotiated,
`sdl3-pointer-middle-paste-smoke` reuses W9o selection first, then sends a
deterministic zero-modifier middle press/release with one click. Only an ACKed
middle release after a successful bounded left selection executes public `yank`
at the public `posn-at-x-y` release point. The frontend fails the gate unless
the left release precedes the middle release in the delivery journal and the
first scene line is exactly `EmacsEmacs Proto-UI`. All other
chord/touch/pen/multi-click cases remain transport-observed or no-op; X11
PRIMARY, generic mouse yank, and full mouse behavior remain out of scope.

The frontend classifies scene changes as initial, cursor-only, bounded
text-only, mixed text/cursor region, viewport, or unchanged. It uses SHA-256
text/structure signatures, per-line hashes and rectangles for up to 32 bounded
ASCII lines, and complete rendered cursor state. Unchanged states are skipped.
Cursor-only and bounded text/region changes use a sized, primed offscreen
retained target and a conservative clip; the clipped pass still submits the
explicit opaque full-frame background fill, and the clip restricts it to the
changed union before row/text/cursor commands. Viewport, oversized, incomplete,
and unmapped observations remain conservative full-frame work.
Smoke diagnostics report
`initial/cursor/text/region/viewport/unchanged` damage counts and clipped or
fallback frames for cursor/text/region changes; general EUP rectangle damage,
partial present, GPU submit counters, and resource-level dirty uploads remain
pending.

A bounded viewport section accompanies each facts `FRAME_UPDATE`. It carries
the absolute Emacs `window-start` line, visible line count, and viewport-relative
cursor text so SDL can verify that scrolling changes displayed state.

Bounded vertical wheel ticks use line units and the same EPXL journal, apply-ACK,
and transport-ACK rules. Horizontal ticks, pixel/page units, momentum phases,
touchpad sources, and modifiers are explicitly rejected.
Because the Emacs bridge replaces its non-atomic Lisp apply-ACK artifact in
place, the frontend retries torn or stale payloads until the bounded apply-ACK
deadline expires.

The `sdl3-epxl-interactive-smoke` connects the real SDL event queue to
authenticated EPXL. It translates printable ASCII text, sends it through the
delivery journal, waits for Emacs apply and EPXL ACKs, receives refreshed fact
frames, and presents the scene with the same draw list as replay.

The `sdl3-epxl-recovery-smoke` exercises the reverse-input row against a real
Emacs publisher: the frontend discards the first ACK event, reconnects with a
new authenticated resync, retries sequence one, and the publisher ACKs it
without applying the text a second time.

## 16. Diagnostics

The EPXL transport performs bounded capability negotiation immediately after
the authenticated transport handshake. Both sides reject missing required
profile features, malformed known values, sequence/ACK mismatches, or an
effective-set hash mismatch. The generated status manifest records the declared EPXL profile feature scope,
implementation status, required/negotiable flags, and evidence gates; it is not
a per-session effective-set snapshot.

The frontend reports:

```text
present timestamp
render CPU time
GPU submit/present estimate
frame dropped reason
damage area
resource hits/misses
atlas hit rate
texture uploads
input latency
actual present mode
scene object counts
memory usage
```

W10b-a implements the first subset in smoke diagnostics: actual renderer
name/tier and present mode, `presented_frames`, `skipped_frames`, full-frame path
nanoseconds, and the last monotonic present timestamp.

W10c adds damage classification counters to EPXL smoke diagnostics:
`initial_damage_frames`, `cursor_damage_frames`, `text_damage_frames`,
`region_damage_frames`, `viewport_damage_frames`, and `unchanged_frames`.
Cursor-only and bounded text/region changes may use a conservative
retained-frame clip and skip full-frame clear. The explicit opaque background
fill is still submitted and restores every pixel in the clip before other draw
commands. Viewport, oversized, and incomplete observations remain conservative
full-frame work. Smoke diagnostics also report clipped/fallback frames for
cursor, text, and region changes plus submitted clipped commands; partial
present, GPU submit counters, general EUP rectangle damage, and resource-level
dirty uploads remain pending.

## 17. CLI contract

The final frontend supports at least:

```text
--endpoint <path-or-address>
--token <session-token>
--renderer software|gpu|auto|<sdl-driver>
--present off|on|adaptive
--log-level error|warn|info|debug|trace
--replay <file>
--width <logical-width>
--height <logical-height>
--fullscreen
```

`--replay` runs without a live Emacs connection for deterministic frontend testing.
`--renderer` may also name an SDL driver; an unavailable named driver is an error.
`--renderer=gpu` is the only request with automatic software fallback.
`--glyph-run-smoke` opens an active one-window/one-row diagnostic frame, sends
one valid `GLYPH_RUN` v1, asserts scene and draw-list state, and auto-closes.

## 18. Acceptance criteria

The SDL3 frontend is accepted when:

1. It opens a real SDL3 window from a live proto frame.
2. Text, cursor, face, mode line, fringe, damage, and resize work.
3. Keyboard and mouse commands drive Emacs.
4. Frame deletion closes the window without affecting unrelated frames.
5. Reconnect restores a coherent display.
6. Software fallback works without GPU.
7. GPU tier reports real performance counters.
8. Advertised widget capabilities return results to Emacs.
9. Fuzzed or truncated protocol input does not crash the frontend.
