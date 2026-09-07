# Proto-UI Capability and Compatibility Matrix

Status: normative design baseline
Reference backend: PGTK
Protocol: EUP v1

Adapter-first is normative: new Proto-UI capability implementation belongs in
the adapter, frontend, tooling, Lisp integration, or build glue—not in
inherited GNU Emacs C source.  See
[`adapter-boundary.md`](adapter-boundary.md).

## 1. Capability model

Each capability has:

1. Owning side.
2. Support level.
3. Negotiation direction.
4. Degradation strategy.
5. Conformance evidence.

Unknown optional capabilities are ignored. Unknown required messages trigger controlled resync or session error. Missing optional capabilities must produce a safe fallback.

## 2. Support levels

| Level | Meaning |
|---|---|
| Required | Every complete implementation must provide it |
| Recommended | Required for production quality; fallback allowed |
| Optional | May be absent with defined behavior |
| Conditional | Present only when platform/renderer supports it |
| Explicitly unsupported | Protocol can describe request, implementation rejects safely |

## 3. Backend and session capabilities

| Capability | Level | Owner | Fallback |
|---|---|---|---|
| `protocol.v1` | Required | both | No session |
| `session.control_v1` | Required | both | Disconnect/reconnect |
| `session.resume` | Recommended | backend | New session/full snapshot |
| `session.replay` | Recommended | backend | Snapshot fallback |
| `multi_frame` | Required | backend/core | One frame only |
| `multi_monitor` | Recommended | frontend/platform | Primary monitor |
| `dpi_scale` | Required on scalable platforms | frontend | Scale 1.0 |
| `frame.alpha` | Optional | frontend | Opaque frame |
| `frame.opacity` | Optional | frontend | No fade |
| `frame.fullscreen` | Required desktop | frontend | Normal window |
| `frame.maximize` | Required desktop | frontend | Manual resize |
| `frame.undecorated` | Optional | frontend/platform | Decorated frame |
| `frame.override_redirect` | Conditional | frontend/platform | Managed frame |
| `frame.child` | Required for PGTK parity | negotiated | Tooltip/child unavailable |
| `frame.tooltip` | Required for PGTK parity | negotiated | Echo-area fallback |
| `window_tree` | Required | core/backend | Backend cannot operate |
| `window.tree_snapshot_v1` | Optional/degraded | adapter/frontend | Bounded complete-tree state codec and Scene validation; no rendering/management parity |
| `glyph_rows` | Required | core/backend | Backend cannot operate |
| `shaped_glyphs` | Required | core/font stack + frontend | Incomplete text fallback |
| `bidi` | Required | core/redisplay | RTL text nonconformant |
| `cjk` | Required production | core/font stack + frontend | Missing CJK rendering |
| `composition` | Required production | core/font stack | Complex script degradation |
| `emoji` | Optional | fonts/frontend | Boxes/fallback glyph |
| `color_fonts` | Optional | frontend/backend atlas | Monochrome fallback |
| `font_metrics` | Required | core/backend | Protocol cannot operate |
| `font_frontend_raster` | Recommended | frontend | Backend atlas required |
| `font_backend_atlas` | Required fallback | backend/frontend | Frontend raster unavailable |
| `face_resources` | Required | backend | Backend cannot operate |
| `image_resources` | Required graphic parity | backend/frontend | Images unavailable |
| `animated_images` | Optional | backend/frontend | Static first frame |
| `fringe_bitmaps` | Required graphic parity | backend/frontend | Fringe degraded |
| `partial_damage` | Required | backend/frontend | Full redraw |
| `damage_coalescing` | Required | backend | Higher bandwidth/frame drops |
| `render.glyph_run_debug_v1` | Optional/degraded | adapter/frontend | Facts text remains the safe baseline |
| `render.glyph_face_debug_v2` | Optional/degraded | adapter/frontend | Facts text remains the safe baseline; no shaped-text or face parity |
| `render.image_debug_v1` | Optional/degraded | adapter/frontend | Complete bounded RGBA8 resource rendering only |
| `scroll_optimization` | Recommended | backend/frontend | Full redraw |
| `scrollbars` | Required PGTK parity | negotiated | Scrollbar hidden |
| `menu_model` | Required | core/backend | Menus unavailable |
| `native_menus` | Optional | frontend/platform | Custom renderer |
| `dialog_model` | Required | core/backend | Lisp fallback |
| `tooltips` | Required PGTK parity | negotiated | Echo-area fallback |
| `selection` | Required GUI | negotiated | Clipboard unavailable |
| `clipboard` | Required GUI | frontend | Clipboard unavailable |
| `input.pointer_selection_left` | Optional | adapter/frontend | Pointer events remain observed |
| `input.pointer_middle_paste` | Optional | adapter/frontend | Requires the completed bounded left-selection evidence |
| `dnd` | Optional | frontend/platform | DND unavailable |
| `ime` | Required CJK production | frontend + core | No platform IME |
| `shared_memory` | Optional | transport | Socket/pipe |
| `file_replay` | Recommended | backend/tools | Live session only |
| `compression` | Optional | transport | Uncompressed |
| `encryption` | Optional | transport | Local trusted IPC |
| `diagnostics` | Recommended | both | Minimal errors |

## 4. Frontend renderer capabilities

| Capability | Purpose | Fallback |
|---|---|---|
| `renderer.class` | Software, GPU basic, GPU advanced, hybrid | Software |
| `renderer.api` | SDL Renderer, SDL GPU, Vulkan, Metal, D3D12, compositor | Software |
| `texture.max_width/height` | Resource limits | Clamp/slice |
| `texture.formats` | Accepted pixel formats | Convert RGBA8 |
| `texture.srgb` | Correct sRGB output | Manual gamma approximation |
| `blend.premultiplied_alpha` | Correct alpha | Conversion |
| `clip.scissor` | Efficient clipping | Software clip |
| `glyph.atlas` | Cached glyph textures | Per-glyph textures |
| `glyph.persistent_atlas` | Avoid churn | Recreate pages |
| `glyph.subpixel` | Better positioning | Integer positioning |
| `image.cache` | Avoid re-upload | Reupload |
| `image.mipmap` | Downscale quality | Linear filtering |
| `async_upload` | Avoid stalls | Synchronous upload |
| `damage.present` | Present changed regions | Full present |
| `render.glyph_run_debug_v1` | Diagnostic ASCII run transport/render | Ignore unsupported message; keep facts text |
| `present.vsync` | Avoid tearing | Software pacing |
| `present.adaptive_vsync` | Latency control | Regular vsync |
| `present.mailbox` | Low latency | Vsync/immediate fallback |
| `refresh.range` | Supported refresh rates | Platform default |
| `multi_window` | Multiple frames | One visible frame |
| `msaa` | Primitive quality | No MSAA |
| `hdr` | HDR output | SDR |
| `wide_gamut` | Extended color | sRGB |

## 5. Widget renderer capabilities

Semantic ownership remains in Emacs regardless of renderer.

| Widget | Semantic owner | Renderer options | Baseline |
|---|---|---|---|
| Menu | Core/backend | Custom GPU/CPU, native | Functional model |
| Menu bar | Core/backend | Custom/native | Visible model |
| Popup menu | Core/backend | Custom/native | Functional model |
| Tool bar | Core/backend | Glyph, custom, native | Visible model |
| Tab bar | Core/redisplay | Glyph/custom | Visible model |
| Dialog | Core/backend | Custom/native | Result returns |
| File dialog | Core/backend | Native/custom | Path returns |
| Color dialog | Core/backend | Native/custom | Color returns |
| Font dialog | Core/backend | Native/custom | Font spec returns |
| Tooltip | Core/backend | Custom/native | Content/placement |
| Scrollbar | Core/backend | Custom/native | Scroll intent |
| IME candidate | Platform/frontend | Platform/custom | Composition works |

## 6. PGTK parity matrix

Priority and requirement columns define the specification target. The Status and Evidence columns are the current implementation snapshot. They are intentionally more conservative than historical workstream approvals: an approved bounded bridge is not claimed as PGTK parity.

### Status legend

| Status | Meaning |
|---|---|
| Implemented | Full row scope is available in the adapter-first path and covered by a gate |
| Degraded | A bounded, safe subset works; the fallback and missing scope are explicit |
| Pending | No adapter-first runtime implementation yet; the protocol/design may be specified |
| Blocked | Requires a defined runtime seam or capability before it can proceed |

The base snapshot below records `23da8d92855`; the current revision adds W12a
bounded capability/status negotiation, W12b bounded frame/resource generation
contracts, W12c real-frame lifecycle bridge smoke, W12d frame
visibility/focus state contracts, W12e bounded resource payload/eviction
policy, W12f optional host frame-state ABI seam, W12g terminal-lifecycle core,
W12h fail-closed runtime manifest/gate, W12i generated C adapter plus
linkable observation library, W12j R5 frame-service mapping, and W12k R6
atomic capture batches. 118 PGTK rows are audited: 21 Degraded,
97 Pending, 0 Blocked, and 0 fully Implemented. Pending rows are not failures
of the protocol design; they are requirements still separating the bounded
facts bridge from W12 PGTK parity and the W16 real-frame acceptance test.

Outside that audited PGTK count, W10d additionally reports
`render.glyph_run_debug_v1` as optional/degraded/negotiable.  Its evidence is
`sdl3-glyph-run-smoke`; it is a transport/render diagnostic and does not change
the pending `redisplay.glyph_rows` or any PGTK status above.  W10e also uses
that bounded path in `sdl3-frame-smoke` to render the public-facts marker
`Emacs Proto-UI`, and W10f adds its exact-delete lifecycle and facts fallback;
this remains diagnostic fallback, not redisplay-owned capture, shaped text,
face/font rendering, or `output_proto`.

Priorities:

| Priority | Meaning |
|---|---|
| P0 | Required for first real SDL3 Emacs frame |
| P1 | Required for production proto UI |
| P2 | Required for complete PGTK parity |
| EXP | Protocol-defined experimental/explicitly unsupported initially |

### 6.1 Terminal/display

| Capability | PGTK equivalent | Proto requirement | Priority | Status | Evidence |
|---|---|---|---|---|---|
| Terminal creation | `create_terminal(output_pgtk)` | `create_terminal(output_proto)` | P0 | Pending | Existing-frame observation is not terminal creation; no `output_proto` terminal |
| Terminal deletion | PGTK terminal hooks | EUP session/frame teardown | P0 | Pending | Smoke process cleanup is not terminal deletion; no teardown contract |
| Graphic frame predicate | `output_pgtk` frame | `output_proto` frame | P0 | Pending | No `output_proto`; W12/W16 P0 gap |
| Focus frame | GDK focus | Frontend focus + core state | P0 | Degraded | W12d strict EUP focus state contract; no frame-focus event round trip |
| Multi-frame | GTK windows | Multiple SDL windows | P1 | Pending | Single SDL facts window and one EUP frame profile |
| Monitor attributes | GDK monitor | SDL monitor events | P1 | Degraded | EUP `FRAME_MONITOR` v1 owns generation-qualified identity, primary flag, and bounds; SDL queries display ID/bounds, while change events and migration remain pending |
| Scale factor | GDK scale | SDL display scale | P1 | Degraded | `FRAME_SCALE` v1 owns generation-qualified scale state and SDL reports per-window scale; redisplay still consumes fixed `FRAME_UPDATE` values |
| DPI | GTK/GDK | SDL display data | P1 | Degraded | `FRAME_SCALE` v1 owns generation-qualified X/Y DPI state and SDL reports per-window scale; redisplay still consumes fixed `FRAME_UPDATE` values |
| Monitor change | GDK signal | Frontend event/redisplay | P1 | Pending | No monitor event or live redisplay bridge |

### 6.2 Frame lifecycle

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Create/delete frame | P0 | Degraded | W12c creates/deletes one real PGTK observation frame and one EUP/SDL3 frame in a bounded smoke; no `output_proto`-owned frame predicate or general lifecycle |
| Visible/invisible | P0 | Degraded | W12d strict EUP hidden/visible state contract and scene registry; no Emacs/SDL3 runtime round trip |
| Iconify/deiconify | P1 | Pending | W12/W16 PGTK parity gate not met |
| Raise/lower | P1 | Degraded | EUP `FRAME_Z_ORDER` v1 models raise/lower; SDL probe covers top/always-on-top only while portable raise/lower and Emacs round trips remain pending |
| Restack | P1 | Degraded | EUP relative above/below records validate another active frame generation; SDL relative restacking and redisplay adaptation remain pending |
| Fullscreen states | P1 | Degraded | EUP `FRAME_FULLSCREEN` v1 models none/fullboth/fullwidth/fullheight/maximized and SDL probes and restores fullboth; width-only, height-only, maximized, persistence policy, and PGTK parity remain pending |
| Maximize horizontal/vertical | P1 | Degraded | EUP `FRAME_MAXIMIZE` v1 carries independent axis flags; SDL probes/restores both-axis maximization, while single-axis mapping, geometry adaptation, and PGTK parity remain pending |
| Undecorated frame | P1 | Degraded | EUP `FRAME_DECORATIONS` v1 maps decorated/undecorated policy to the diagnostic SDL border flag; persistence, parent/tooltip policies, and PGTK parity remain pending |
| Override redirect | P2 | Pending | W12/W16 PGTK parity gate not met |
| Parent frame | P2 | Pending | W12/W16 PGTK parity gate not met |
| Child frame | P2 | Pending | W12/W16 PGTK parity gate not met |
| Tooltip frame | P2 | Pending | W12/W16 PGTK parity gate not met |
| Title/name | P0 | Degraded | EUP `FRAME_TITLE` v1 resolves a generation-qualified string and sets the diagnostic SDL window title; Emacs title publication and frame-parameter parity remain pending |
| Icon | P1 | Degraded | `FRAME_ICON` v1 references a complete RGBA image and SDL applies an icon surface; multi-resolution, animated, and taskbar parity remain pending |
| Outer/native/text geometry | P0 | Degraded | Public frame/window geometry facts; no platform-native geometry contract |
| Size hints | P1 | Degraded | EUP `FRAME_SIZE_HINTS` v1 models min/max, increment, and aspect constraints; SDL applies min/max/aspect and Scene owns increments, while redisplay geometry adaptation remains pending |
| Alpha/background alpha | P1 | Degraded | EUP `FRAME_ALPHA` v1 carries active/inactive/background opacity; SDL probe applies active window opacity and falls back opaque, while focus transitions and complete PGTK visual parity remain pending |
| Internal border | P0 | Pending | Window edges are debug geometry, not frame border semantics |
| Skip taskbar | P2 | Pending | W12/W16 PGTK parity gate not met |
| Sticky | P2 | Pending | W12/W16 PGTK parity gate not met |
| Z-group | P2 | Pending | W12/W16 PGTK parity gate not met |

### 6.3 Redisplay/rendering

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Glyph rows | P0 | Degraded | Bounded public-fact rows in EUP; not redisplay-owned glyph rows |
| Glyph runs | P0 | Pending | W12/W16 PGTK parity gate not met |
| Character glyphs | P0 | Degraded | Bounded printable ASCII through SDL debug text |
| Composite glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Glyphless glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Image glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Stretch glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| XWidget glyphs | EXP | Pending | W12/W16 PGTK parity gate not met |
| Faces | P0 | Pending | W12/W16 PGTK parity gate not met |
| Cursor styles | P0 | Degraded | Single filled rectangle; no shape, blink, or face model |
| Mouse face | P1 | Pending | W12/W16 PGTK parity gate not met |
| Fringe bitmaps | P1 | Pending | W12/W16 PGTK parity gate not met |
| Window divider | P1 | Pending | W12/W16 PGTK parity gate not met |
| Vertical border | P1 | Pending | W12/W16 PGTK parity gate not met |
| Mode line | P0 | Pending | W12/W16 PGTK parity gate not met |
| Header line | P1 | Pending | W12/W16 PGTK parity gate not met |
| Tab line | P1 | Pending | W12/W16 PGTK parity gate not met |
| Tab bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Tool bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Menu bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Scrollbar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Overlay arrow | P1 | Pending | W12/W16 PGTK parity gate not met |
| Hourglass | P2 | Pending | W12/W16 PGTK parity gate not met |
| Visible bell | P2 | Pending | W12/W16 PGTK parity gate not met |
| Audible bell | P1 | Pending | W12/W16 PGTK parity gate not met |
| Partial damage | P0 | Degraded | Cursor and bounded text/region retained-frame clips; no partial present |
| Scroll optimization | P1 | Pending | W12/W16 PGTK parity gate not met |
| Double-buffer equivalent | P1 | Degraded | Adapter-owned SDL target; no full redisplay invalidation model |

### 6.4 Text/fonts

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Monospace Latin text | P0 | Degraded | Bounded printable ASCII, 120 columns/32 lines, 8x8 debug font |
| Font fallback | P1 | Pending | W12/W16 PGTK parity gate not met |
| CJK text | P1 | Pending | W12/W16 PGTK parity gate not met |
| BiDi ordering | P1 | Pending | W12/W16 PGTK parity gate not met |
| Arabic shaping | P2 | Pending | W12/W16 PGTK parity gate not met |
| Indic shaping | P2 | Pending | W12/W16 PGTK parity gate not met |
| Emoji | P2 | Pending | W12/W16 PGTK parity gate not met |
| Color emoji | P2 | Pending | W12/W16 PGTK parity gate not met |
| Variable fonts | P2 | Pending | W12/W16 PGTK parity gate not met |
| Color fonts | P2 | Pending | W12/W16 PGTK parity gate not met |
| Synthetic bold/italic | P1 | Pending | W12/W16 PGTK parity gate not met |
| Underline/overline/strike-through | P0 | Pending | W12/W16 PGTK parity gate not met |
| Box faces | P0 | Pending | W12/W16 PGTK parity gate not met |
| Baseline/line spacing | P0 | Degraded | Facts-profile row baseline and visible-height geometry only |
| Frame font change | P1 | Pending | W12/W16 PGTK parity gate not met |
| Fontset semantics | P1 | Pending | W12/W16 PGTK parity gate not met |

### 6.5 Input/IME

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Keyboard events | P0 | Degraded | Printable ASCII insert, backspace, arrows, copy, paste; no keymap commands |
| Modifier state | P0 | Degraded | Ctrl+C and Ctrl+V only; general modifier sets rejected |
| Multibyte input | P0 | Pending | W12/W16 PGTK parity gate not met |
| Dead keys | P1 | Pending | W12/W16 PGTK parity gate not met |
| Mouse motion | P0 | Degraded | Bounded hover/drag admission; negotiated v2 preserves the exact button mask |
| Mouse buttons | P0 | Degraded | Bounded left plus negotiated strict left/middle/right/X1/X2 v2 intents |
| Click count | P1 | Degraded | V2 validates and transports clicks 1..8; execution/selection parity remains pending |
| Drag events | P1 | Degraded | Ordered bounded left or negotiated v2 exact-mask drag; not selection drag |
| Left-drag selection | P1 | Degraded | One negotiated smoke subset sets public mark/point and copies at most 120 ASCII bytes (`sdl3-pointer-selection-smoke`); no mouse parity |
| Middle-click paste | P1 | Degraded | One negotiated smoke subset yanks the most recent kill after a prior bounded left selection (`sdl3-pointer-middle-paste-smoke`); no X11 PRIMARY or generic mouse yank |
| Wheel scroll | P0 | Degraded | Vertical whole line ticks only |
| Touchpad scroll | P1 | Pending | W12/W16 PGTK parity gate not met |
| Touch | EXP | Pending | W12/W16 PGTK parity gate not met |
| Pen | EXP | Pending | W12/W16 PGTK parity gate not met |
| Gestures | EXP | Pending | W12/W16 PGTK parity gate not met |
| Focus enter/leave | P0 | Degraded | Negotiated strict FOCUS_EVENT observation; no Emacs core focus mutation (`sdl3-focus-window-smoke`) |
| Window requests | P1 | Degraded | Negotiated strict close/resize/move/fullscreen/maximize/minimize/restore intents; no host contract or runtime mutation (`sdl3-focus-window-smoke`) |
| IME activation | P1 | Pending | W12/W16 PGTK parity gate not met |
| Preedit | P1 | Pending | W12/W16 PGTK parity gate not met |
| Commit | P1 | Pending | W12/W16 PGTK parity gate not met |
| Surrounding text | P2 | Pending | W12/W16 PGTK parity gate not met |
| Candidate placement | P1 | Pending | W12/W16 PGTK parity gate not met |

### 6.6 Desktop integration

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Clipboard text | P0 | Degraded | Bounded printable ASCII paste and copy smoke paths |
| Clipboard images | P2 | Pending | W12/W16 PGTK parity gate not met |
| PRIMARY selection | P1 | Pending | W12/W16 PGTK parity gate not met |
| SECONDARY selection | P2 | Pending | W12/W16 PGTK parity gate not met |
| Selection ownership | P1 | Pending | W12/W16 PGTK parity gate not met |
| Selection target negotiation | P1 | Pending | W12/W16 PGTK parity gate not met |
| DND text | P2 | Pending | W12/W16 PGTK parity gate not met |
| DND files | P2 | Pending | W12/W16 PGTK parity gate not met |
| DND images | P2 | Pending | W12/W16 PGTK parity gate not met |
| DND copy/move/link | P2 | Pending | W12/W16 PGTK parity gate not met |
| System theme event | P2 | Pending | W12/W16 PGTK parity gate not met |
| System font preference | P2 | Pending | W12/W16 PGTK parity gate not met |
| App icon | P1 | Pending | W12/W16 PGTK parity gate not met |
| Taskbar state | P2 | Pending | W12/W16 PGTK parity gate not met |
| WM hints | P2 | Pending | W12/W16 PGTK parity gate not met |

### 6.7 Widgets

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Menu bar model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Popup menu model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Native menu | Optional | Pending | No platform menu bridge |
| Tool bar model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Dialog model | P1 | Pending | W12/W16 PGTK parity gate not met |
| File dialog | P1 | Pending | W12/W16 PGTK parity gate not met |
| Color dialog | P2 | Pending | W12/W16 PGTK parity gate not met |
| Font dialog | P2 | Pending | W12/W16 PGTK parity gate not met |
| Tooltip model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Scrollbar model | P1 | Pending | Wheel intent exists, but no scrollbar model/render/interaction |

## 7. GPU acceleration tiers

GPU acceleration is negotiated frontend capability, not core obligation.

### Tier 0: software correctness

Required fallback.

```text
No GPU dependency
Complete semantics
Full redraw allowed
CI/headless/replay baseline
```

### Tier 1: GPU basic

Minimum production GPU path.

```text
GPU surface
Glyph atlas
Image textures
Blend/scissor
Damage redraw
Vsync
1080p60 target
```

### Tier 2: GPU advanced

Performance target.

```text
Persistent glyph atlas
Image cache
Async texture upload
Damage-only present
Multi-window batching
Frame pacing
1440p60 / capable 4K60 target
```

### Tier 3: low latency/high refresh

Optional.

```text
VRR
Mailbox/low-latency present
GPU timestamps
Zero-copy shared textures
120Hz+ scheduling
```

## 8. Font render modes

| Mode | Producer | Consumer | Use |
|---|---|---|---|
| Frontend raster | Core supplies font descriptor/metrics | Frontend rasterizes/caches | Low bandwidth production path |
| Backend atlas | Backend supplies glyph pixels | Frontend textures | Deterministic/fallback path |
| Hybrid | Per-font/per-glyph decision | Frontend | Production default target |

Backend atlas is mandatory fallback for missing frontend fonts, emoji, color fonts, and deterministic replay.

## 9. Capability negotiation rules

1. Backend and frontend both advertise capabilities.
2. Effective capability is intersection.
3. Required capability missing -> deterministic session error.
4. Optional capability missing -> explicit fallback.
5. Capability set is echoed in `SESSION_READY`.
6. Capability changes after initialization require session reset.
7. Unknown optional capabilities are ignored.

## 10. Degradation requirements

| Missing capability | Required fallback |
|---|---|
| GPU | Software renderer |
| Glyph atlas | Per-glyph textures or backend pixels |
| Image format | Convert to RGBA8 |
| Partial present | Full present |
| Native menu | Custom menu or glyph fallback |
| Native dialog | Custom dialog |
| Clipboard | Disable clipboard capability |
| DND | Disable DND capability |
| IME | Disable IME capability |
| Shared memory | Socket/pipe |
| Replay | Live session only |
| Compression | Uncompressed payload |

## 11. Compatibility acceptance

A capability row is complete only when:

1. Negotiation is specified.
2. Payload is specified.
3. Fallback is specified.
4. Emacs semantics are correct.
5. A replay or live test covers it.
6. Performance is measured when applicable.
7. Failure cannot crash Emacs.
8. Implementation status is recorded.

The base compatibility gate checks existing Emacs behavior only.  It runs
isolated batch scenarios for identity, buffer text and undo, point/mark and
narrowing, text/overlay properties, face definition/readback, window split and
delete, resize/scroll/recenter, and buffer-local variables.  When
`DISPLAY`/`WAYLAND_DISPLAY` is present it creates one real PGTK frame, repeats
the window/scroll/face checks there, deletes the frame, and verifies cleanup.
Without a display the PGTK scenarios are explicit skips, never passes disguised
as GUI evidence.

The backend semantic matrix extends that gate with seven fixed
backend-neutral scenarios.  It runs the same semantic scenarios in the
isolated batch/TTY parent and, when a display is present, in a real PGTK
child.  Each backend record has a canonical signature and SHA-256 digest, and
the report includes ordered combined digests plus per-pair match/skip status.
Digests exclude pixel dimensions, font names, frame identities/types, object
IDs, and elapsed time.  The Zig gate validates exact scenario order and
recomputes the combined and pair digests.  This is not proto-frame parity.

## 12. Current implementation evidence

Base snapshot: `zig-build-step-4` through `8bebccada16` plus the W12d state
contract. This summary is scope-sensitive; "implemented" never implies PGTK
parity.

### 12.1 Layer status

| Layer | Working now | Still required for parity | Evidence |
|---|---|---|---|
| Protocol coverage | All 164 assigned EUP IDs are classified in a deterministic manifest: 53 implemented codecs, 3 partial, and 108 planned; no unassigned or unclassified ID | Production implementation of the 108 planned IDs |
| Protocol/transport | EUP envelope, bounded `FRAME_UPDATE`, replay, EPXL framing, resync, ACK/retry, deterministic ordered/resync/ACK-loss/ERP1 convergence differential with
`RESOURCE_SNAPSHOT`-aware concrete face/font/string/image fingerprints, bounded EPXL capability negotiation/status manifest, frame visibility/focus state codec, bounded resource payload cache/eviction policy, request/evict codecs, bounded string define/delete, fixed-layout face/font/image define/data/delete, and atomic concrete `RESOURCE_SNAPSHOT` v1 restore with frontend ownership, optional host frame-state ABI seam, terminal-lifecycle core, generated read-only C adapter, dynamically linkable observation library, bounded host-frame to EUP-frame service mapping, deterministic atomic capture batches, deterministic protocol fuzz hardening, and bounded process-level frontend crash isolation, and negotiated strict focus/window observation | General resource/widget capability coverage, arbitrary recovery, remote safety, runtime terminal registration | `proto-ui-conformance`, `proto-ui-unit`, `proto-ui-fuzz`, `proto-ui-recovery-diff`, `proto-ui-crash-isolation`, `proto-ui-shim-conformance`, `proto-ui-shim-library-conformance`, `sdl3-live-smoke`, `sdl3-epxl-resync-smoke`, `sdl3-epxl-recovery-smoke` |
| Emacs observation | Real Emacs process publishes public frame/window geometry, bounded printable-ASCII text, point/cursor, and viewport facts; W12c creates/deletes one real display-backed frame and synchronizes one EUP/SDL3 frame lifecycle; W10e renders that public-facts marker through the bounded glyph-run debug fallback | Redisplay-owned rows/glyphs/faces/fonts, full window tree, `output_proto`-owned frame creation/deletion, runtime visibility/focus events | `proto-ui-module-smoke`, `sdl3-emacs-smoke`, `sdl3-epxl-facts-smoke`, `sdl3-frame-smoke` |
| SDL3 rendering | Real SDL window, frame/window/row/cursor scene, software/GPU selection, clear/fill/debug-text list, retained cursor/text clips, bounded debug glyph runs, EUP-resolved Scene title application, and optional face-colored fallback text | Glyph atlas, production glyph runs, full faces, image presentation, widgets, true partial present, GPU timestamps | `sdl3-ui-smoke`, `sdl3-renderer-smoke`, `sdl3-pointer-smoke`, `sdl3-epxl-interactive-smoke`, `sdl3-runtime-bridge-smoke` |
| Input | Bounded ASCII insert/delete, negotiated bounded UTF-8 text, arrows, negotiated strict down/up/repeat key v2, Ctrl+C/Ctrl+V, left pointer sessions, negotiated bounded left-drag selection, bounded middle-click yank, vertical wheel, negotiated focus and strict window request observation | General keymap/command execution, IME, shaped Unicode rendering, host-applied window mutations, general selection semantics, right-button semantics, generic mouse behavior, pixel/horizontal scroll | `sdl3-input-translate-smoke`, `sdl3-epxl-input-smoke`, `sdl3-epxl-unicode-input-smoke`, `sdl3-epxl-key-v2-smoke`, `sdl3-epxl-edit-smoke`, `sdl3-pointer-smoke`, `sdl3-pointer-selection-smoke`, `sdl3-pointer-middle-paste-smoke`, `sdl3-wheel-smoke`, `sdl3-focus-window-smoke` |
| Desktop | Bounded UTF-8 clipboard paste/copy, with Unicode gated by negotiated `clipboard.text_unicode` | MIME, PRIMARY/SECONDARY selection, DND, dialogs, menus, scrollbars | `sdl3-clipboard-smoke`, `sdl3-clipboard-unicode-smoke`, `sdl3-emacs-copy-smoke` |
| Performance | Change-aware present/skip, damage-class counters, clip counters, renderer tier reporting, `FRAME_PRESENTED`/`FRAME_DROPPED` codec conformance, opt-in adapter hot-path baseline for EUP encode/decode, Scene application, atomic capture, and bounded memory send | Core feedback consumption, adaptive pacing, latency percentiles, bandwidth/allocation evidence, real redisplay/typing/scroll benchmarks, GPU-tier comparisons | `proto-ui-bench` (opt-in), renderer/interactive smoke diagnostics; W14 remains partial |
| Base Emacs compatibility | Existing-buffer health gate for version, text/undo, narrowing, properties, faces, windows, scroll/recenter, buffer locals, optional real PGTK frame lifecycle, and a seven-scenario deterministic TTY/PGTK semantic matrix | Proto-frame compatibility and full PGTK parity | `proto-ui-compat` (opt-in); `compatibility.pgtk_base_gate` and `compatibility.backend_semantic_matrix` are degraded and non-negotiable |
| Disabled/default isolation | Bounded marker audit of inherited C/Header/Lisp files and generated `src/config.h`; explicit owned-root/build-output exclusion; deterministic machine-readable fail-closed JSON | Runtime host registration, real `output_proto` enablement, and proto-frame compatibility | `proto-ui-isolation-audit`; `isolation.disabled_default_gate` is degraded and non-negotiable |

The status audit contains 120 PGTK capability rows: 23 Degraded, 97 Pending,
0 Blocked, and 0 fully Implemented. A Degraded row always identifies both the
verified bounded subset and the parity gap that remains.

### 12.2 Largest P0 gaps

1. **Graphic frame ownership.** The dynamic-module bridge observes a real Emacs process, but there is no `output_proto` terminal or graphic frame predicate.
2. **Redisplay-owned rendering.** EUP carries bounded facts rows, not authoritative glyph rows, runs, faces, fonts, or redisplay damage.
3. **Frame lifecycle and focus.** W12c proves one bounded real-frame create/update/delete bridge and W12d defines strict visibility/focus scene state, but `output_proto` frame ownership and runtime focus/visibility round trips remain absent.
4. **Capability coverage.** The bounded EPXL profile now negotiates, but resources, widgets, and the full EUP feature table are outside that set.
5. **Resource model.** Generation declarations, a bounded payload cache/eviction policy, request/evict wire contracts, bounded `STRING_DEFINE`/`STRING_DELETE`, fixed-layout `FACE_DEFINE`/`FACE_DELETE`, `FONT_DEFINE`/`FONT_DELETE`, and bounded `IMAGE_DEFINE`/`IMAGE_DATA`/`IMAGE_DELETE`, and atomic concrete `RESOURCE_SNAPSHOT` v1 restore exist. Snapshot presentation, runtime recovery activation, redisplay face/font/image capture, and full resource parity remain pending.

### 12.3 Minimum next milestone

The normative target is a **pure SDL3 `output_proto` UI backend** with PGTK used
only as a reference/parity backend.  PGTK must not be a runtime fallback for a
Proto frame.  The target ownership model, PGTK responsibility matrix, protocol
gaps, differential gates, and final acceptance rules are defined in
[`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md).

`runtime_bridge` now refreshes authoritative host geometry, rejects records
outside it, and emits `FRAME_UPDATE` headers from that rectangle.
`runtime_bridge` also exposes bounded lifecycle operations and marks accepted
input transactions cancelled after host-wide cancellation.
`render.glyph_face_debug_v2` binds a bounded run to a live generation-qualified
face and projects foreground/background colors in the SDL debug fallback.
`runtime_bridge` also refreshes host frame visibility/focus and projects changes
to existing EUP state messages in unit conformance.  Real platform events and
Emacs visibility still require R8.
The same smoke now delivers one SDL key and one bounded SDL text intent through
`PureRuntimeHostV1` input callbacks with result/completion tracking.  This is
not keymap or command parity.
`sdl3-runtime-bridge-smoke` presents that fake-host bridge scene through SDL3
without Emacs registration.  `runtime_bridge` can also project bounded host ASCII run payloads into existing
debug `GLYPH_RUN` messages; this remains fallback diagnostic rendering.
`runtime_bridge` proves the same host ABI can produce deterministic EUP frame
create/update/destroy messages with a fake host.  It is not runtime registration.
`proto-ui-runtime-host-abi` projects that contract to a generated C header and
compiles a conformance translation unit.  `proto-ui-runtime-host` defines and conformance-tests a versioned five-group
PureRuntimeHostV1 ABI while keeping runtime unavailable.  It does not register a
terminal or claim output_proto.  `proto-ui-pgtk-parity-plan` emits a 48-case planned PGTK/SDL differential
matrix; it is planning policy, not parity evidence.  R7 host-registration
decision infrastructure is implemented, and `proto-ui-r7-proposal` emits a
source-authoritative pure-SDL3 registration proposal with `ready_for_review`
status.  The source decision itself remains
`pending` with `host_registration_contract_missing`, so no terminal can be
registered and runtime remains fail closed.  Current PGTK/SDL diagnostic bridges
therefore remain non-final compatibility evidence.
The task split and fail-closed runtime contract are defined in
[`output-proto-runtime.md`](output-proto-runtime.md).

## 13. Initial explicit limitations

These may be represented by the protocol but are not required for first completion:

* XWidget rendering.
* Raw GPU command buffers.
* Shader graph exposure.
* Untrusted remote transport.
* Non-uniform X/Y scale.
* Frontend ownership of Emacs layout.
