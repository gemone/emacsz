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

1. Parse transport endpoint, session token, log level, and renderer preference.
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

## 10. Input bridge

### 10.1 Keyboard

SDL keyboard events map to `KEY_EVENT`; text input events map to `TEXT_INPUT`.

Required fields include physical key, logical key, platform key, Unicode text, modifiers, state, repeat count, layout ID, lock state, and timestamp.

The frontend does not resolve Emacs key bindings.

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
| Emacs disconnect | Keep window briefly, show disconnected state, or exit according to policy |
| Sequence gap | Request resync |
| Missing resource | Skip affected drawing and request resource |
| Corrupt update | Drop update and request resync |
| GPU device loss | Rebuild renderer and request full snapshot |
| Out of texture memory | Evict cache; downgrade to software if needed |
| Renderer panic | Exit frontend without affecting Emacs |

## 16. Diagnostics

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

## 17. CLI contract

The final frontend supports at least:

```text
--endpoint <path-or-address>
--token <session-token>
--renderer software|gpu|auto
--log-level error|warn|info|debug|trace
--replay <file>
--width <logical-width>
--height <logical-height>
--fullscreen
```

`--replay` runs without a live Emacs connection for deterministic frontend testing.

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
