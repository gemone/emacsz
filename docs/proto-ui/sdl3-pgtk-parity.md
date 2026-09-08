# Pure SDL3 Emacs Frontend and PGTK Parity

Status: **normative target architecture**
Runtime status: **not implemented**; R7 remains fail-closed
Protocol: EUP v1
Reference backend: PGTK, used only for behavior and capability comparison
UI backend: SDL3 owns the final visible surface

## 1. Target statement

Proto-UI's end state is a real Emacs terminal, `output_proto`, whose visible
frames are rendered entirely by an independent SDL3 frontend.  PGTK is not part
of that runtime path.  PGTK is retained only as a reference implementation for
comparing behavior, capability coverage, and visual semantics.

The corrected architecture is:

```text
GNU Emacs core
  buffer, command, window-layout, face, font, image, redisplay, and
  input-interpretation truth
        |
        | host terminal/frame/redisplay/input seam
        v
output_proto adapter
  terminal identity, frame identity, capture translation, resources,
  damage, transport lifecycle, recovery, and protocol encoding
        |
        | EUP v1
        v
SDL3 frontend
  real OS window, GPU/software renderer, input capture, IME surface,
  desktop integration, damage presentation, and frontend-side caches
```

A diagnostic path may observe a PGTK Emacs and render bounded facts in SDL3.
That path is useful evidence, but it is **not** `output_proto`, not a pure SDL3
frame, and not PGTK parity.  In particular, W10d/W10e/W10f glyph-run smokes are
protocol/renderer diagnostics, not production redisplay.

## 2. Pure-runtime rule

A final Proto-UI frame must satisfy all of the following:

1. `frame-parameter FRAME 'window-system` is `proto`.
2. The visible surface is created and owned by the SDL3 frontend.
3. Keyboard, pointer, wheel, IME geometry, drag-and-drop, clipboard, selection,
   and desktop events return through `output_proto`.
4. GTK/GDK is not initialized for the frame and no GTK widget is part of the
   frame's implementation.
5. If SDL3 disconnects, the frame survives or fails deterministically; it must
   not silently become a PGTK or TTY frame.
6. TTY may remain a separate Emacs backend, but it is not a Proto-UI runtime
   fallback.
7. A frontend crash is contained and recoverable without corrupting Emacs state.

The reference PGTK build and the pure SDL3 runtime build must remain separate:

| Profile | Purpose | Required shape |
|---|---|---|
| PGTK reference | Source of behavioral and visual comparisons | `-Dpgtk=true -Dproto-ui=false` |
| Pure SDL3 target | Final `output_proto` runtime | `-Dpgtk=false -Dproto-ui=true -Dproto-ui-runtime=true -Dsdl3-frontend=true` |
| Diagnostic bridge | Current bounded public-fact and protocol evidence | Opt-in only; never described as the final runtime |

The pure SDL3 profile must not require GTK3 development files solely to open a
Proto frame.  Existing unrelated dependencies may remain in the broader Emacs
build, but the Proto frame path must not initialize GDK/GTK.

## 3. Ownership model

| Concern | Owner | Rationale |
|---|---|---|
| Buffer text, undo, commands, keymaps, minibuffer | Emacs core | Emacs semantics are authoritative. |
| Window layout, selected window, point, mark, region, scrolling model | Emacs core | The frontend must not reflow or invent editor state. |
| Face merging, font selection, shaping, glyph metrics, image decoding policy | Emacs core / core-support libraries | PGTK-compatible rendering requires core-authoritative metrics and visual order. |
| Redisplay generation, rows, runs, cursor, damage, and update cause | Emacs redisplay, observed by adapter | SDL must present what Emacs decided to display. |
| Terminal and frame identity | Emacs terminal truth + adapter ID mapping | `output_proto` is a real terminal; protocol IDs must be stable and generation-qualified. |
| Face/font/image/string resource identity and transport | output_proto adapter | The frontend receives versioned resources; it does not query Emacs objects directly. |
| EUP sequencing, capability negotiation, replay, and recovery | adapter + frontend protocol layers | Protocol correctness must not depend on UI code. |
| OS window, renderer, input queue, presentation, GPU recovery | SDL3 frontend | This is the final UI backend. |
| Frontend glyph/image caches | SDL3 frontend | Caches may only hold versioned backend-owned data. |
| Layout, command execution, buffer mutation | Never SDL3 | Frontend input is intent; Emacs decides the result. |

## 4. PGTK-to-SDL3 responsibility matrix

Status meanings:

* **Target**: required for PGTK parity.
* **Current**: bounded diagnostic or groundwork only.
* **Gate**: evidence required before claiming parity.

### 4.1 Frame and platform

| Capability | Emacs / adapter / EUP / SDL3 split | PGTK parity gate | Current status |
|---|---|---|---|
| Frame create/delete | Emacs creates/destroys terminal frame; adapter maps generation-qualified IDs; EUP carries frame lifecycle; SDL creates/destroys surface | Create, resize, iconify, raise, focus, delete, and exit cleanly on X11/Wayland | Pending; diagnostic PGTK frame smoke only |
| Visibility, iconification, maximization, fullscreen | Emacs owns requested and reported state; adapter translates state; SDL applies and reports platform truth | PGTK-equivalent state transitions and events | Pending |
| Monitor move, DPI, scale | Emacs owns logical geometry; EUP carries logical/physical geometry and scale; SDL reports monitor/scale events | No text relayout drift after move/scale | Pending |
| WM hints, app icon, taskbar, urgency | Adapter carries host requests; SDL applies supported hints | PGTK-equivalent visible hints with documented OS limits | Pending |
| System theme and font preference | Emacs owns settings; adapter publishes change events; frontend forwards platform changes | Face refresh and theme-sensitive frames match PGTK semantics | Pending |

### 4.2 Editor display

| Capability | Emacs / adapter / EUP / SDL3 split | PGTK parity gate | Current status |
|---|---|---|---|
| Window tree and splits | Emacs owns tree/layout; adapter observes window records; EUP carries rectangles; SDL positions scenes | Horizontal/vertical splits, resize, deletion, and selected-window behavior match | Pending |
| Redisplay glyph rows | Emacs redisplay owns rows; adapter captures authoritative rows; EUP carries row/run records; SDL renders them | Fresh dump, byte-compile, scroll, truncation, continuation, variable-width text | Pending; current rows are bounded public facts |
| Cursor | Emacs owns point and cursor style; EUP carries shape/state; SDL draws cursor | Box, bar, hollow, underline, blink state, inactive cursor | Pending |
| Faces and colors | Emacs merges faces; EUP carries generation-qualified face resources; SDL uses them for drawing | Foreground/background, inverse video, underline, overline, strike, box | Pending; resource codecs exist, presentation absent |
| Fonts and shaping | Emacs/font stack selects and shapes; EUP carries runs/metrics/atlas data; SDL never reshapes or reorders | ASCII, CJK, BiDi, ligatures, variable pitch, missing glyph | Pending |
| Images | Emacs decodes/places images; adapter sends versioned payload; SDL creates textures | PNG/JPEG/SVG/XPM where PGTK supports them, scaling, masking, animation where applicable | Pending; static bounded resource contract exists |
| Fringe, margin, scrollbar | Emacs defines visuals and hit-test semantics; EUP carries widgets/runs; SDL renders and returns input | Continuation/wrap/truncation indicators and draggable scrollbars | Pending |
| Mode line, header line, tab line, tool bar | Emacs owns model and layout; EUP carries items and faces; SDL renders and routes clicks | Visual refresh and mouse action mapping match PGTK | Pending |

### 4.3 Input and desktop integration

| Capability | Emacs / adapter / EUP / SDL3 split | PGTK parity gate | Current status |
|---|---|---|---|
| Keyboard and keymap | SDL captures physical/text events; adapter delivers intent; Emacs keymap/command loop decides result | modifiers, function keys, `C-x`-style prefix commands, keyboard macros, localized keys | Pending; bounded subset only |
| Pointer and wheel | SDL translates motion/buttons/wheel; Emacs maps to position/command | click counts, drag, right/middle behavior, modifiers, scroll units | Degraded; bounded left/middle subset |
| Touch and gestures | SDL captures supported gestures; adapter normalizes intents; Emacs maps commands | PGTK-equivalent touch behavior where platform exposes it | Pending |
| IME | SDL owns candidate UI/platform connection; EUP carries preedit/candidate geometry; Emacs commits text and supplies cursor rectangle | CJK input, candidate placement, commit, preedit movement | Pending |
| Clipboard and selection | SDL talks to platform clipboard; Emacs owns kill-ring/yank semantics; EUP carries targets/content | clipboard, PRIMARY, SECONDARY, targets, Unicode, images where supported | Degraded for bounded text |
| Drag and drop | SDL/platform captures DND; adapter forwards protocol events; Emacs decides action | text/file/image drops, copy/move/link, position feedback | Pending |
| Menus and popup menus | Emacs owns menu model; EUP carries model; SDL renders or invokes native menu and returns selection | menubar, popup, keymap-backed menus, separators, checkboxes/radio items | Pending |
| Dialogs and prompts | Emacs owns questions/models; EUP carries dialog spec; SDL presents and returns result | yes/no, prompt, file, color, font dialogs | Pending |
| Tooltips | Emacs owns help text/position; EUP carries tooltip model; SDL presents | delay, placement, multiline text, hide behavior | Pending |
| Accessibility | Emacs retains semantic model; adapter exposes accessible display state; SDL/platform integrates where possible | screen-reader parity on supported desktops | Pending and explicitly platform-dependent |
| Shutdown and recovery | Emacs terminates frame; adapter drains sessions; SDL closes deterministically | disconnect, GPU reset, frontend crash, restart, frame deletion | Pending; bounded containment gates exist |

### 4.4 Performance

| Capability | Emacs / adapter / EUP / SDL3 split | PGTK parity gate | Current status |
|---|---|---|---|
| Interactive latency, frame scheduling, and recovery cost | Emacs owns update cause; adapter owns capture/damage coalescing and transport diagnostics; EUP carries sequence/timing facts; SDL owns input-to-intent and present timing | Meet the documented frame/input/resize/recovery budgets on the same fixtures as PGTK without semantic divergence | Pending; current benchmark and smoke counters are diagnostics only |

## 5. Protocol gaps that block parity

EUP v1 already defines many message IDs, but the following require complete,
implemented, fuzzed, and recovery-aware contracts before pure SDL3 parity:

1. Authoritative window-tree snapshots and patches.
2. Redisplay-owned row records, glyph runs, glyphless/composition runs, image
   runs, stretch runs, rectangles, fringe, divider, and cursor records.
3. Generation-qualified face, font, image, string, fringe, and icon resources.
4. Glyph atlas publication or backend-pixel fallback.
5. Conservative and exact damage, clear-area, scroll-copy, flush, and present
   hints.
6. Complete cursor styles, blink state, IME rectangle, and preedit geometry.
7. Menu, menu item, tool bar, dialog, tooltip, scrollbar, and fringe widget
   models.
8. Clipboard targets, PRIMARY/SECONDARY ownership, DND operations, and file URI
   policy.
9. Platform visibility, monitor, scale, theme, WM hint, and accessibility events.
10. Frontend resource requests, eviction, resync, replay, and crash recovery.
11. Diagnostics correlating Emacs redisplay generation with frontend frames.

Unknown optional capabilities may be ignored.  Missing required parity
capabilities must keep the relevant capability pending and block W16.

## 6. Milestones from current bridge to pure runtime

| Milestone | Outcome | Completion evidence |
|---|---|---|
| P0. Freeze this target | Documents and gates agree that PGTK is reference-only | This file plus consistent status manifests/docs |
| P1. PGTK semantic inventory and differential plan | Every PGTK capability row maps to an owner, EUP record, SDL action, fallback, and gate; 48 concrete differential cases remain planned | `proto-ui-pgtk-parity-plan` emits and audits `pgtk_parity_manifest.json` |
| P2. R7 registration proposal and decision | A source-authoritative proposal is ready for review, then explicitly approved or denied | `r7_proposal.json`, proposal gate, signed-off host registration contract, and review metadata |
| P3. Runtime host ABI preparation | All five required callback groups have a versioned C-ABI table, validator, fake-host conformance, generated C header, and manifest | `proto-ui-runtime-host` and `proto-ui-runtime-host-abi`; live terminal registration still requires R7 approval |
| P4-prep. Runtime bridge | `PureRuntimeHostV1` observations can drive deterministic EUP create/update/destroy messages in fake-host conformance | `runtime_bridge` unit suite; still no Emacs registration |
| P5-prep. Run payload bridge | Host text runs become bounded EUP debug glyph runs and are rendered as fallback text | `runtime_bridge` unit suite and `sdl3-runtime-bridge-smoke`; still not redisplay capture or shaped text |
| P6-prep. Reverse input bridge | SDL key/text intents reach `PureRuntimeHostV1` deliver/result/completion callbacks with bounded tracking | `sdl3-runtime-bridge-smoke`; still not keymap/command parity |
| P7-prep. Visibility/focus bridge | Host frame-state observations project to EUP `FRAME_VISIBILITY` and `FRAME_FOCUS` | `runtime_bridge` unit suite; real platform visibility/focus still requires R8 |
| P7-prep. Title bridge | EUP `FRAME_TITLE` resolves a live string resource and the diagnostic SDL bridge applies the Scene-owned title | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; Emacs title publication still requires R8 |
| P7-prep. Alpha bridge | EUP `FRAME_ALPHA` carries active/inactive/background opacity; the diagnostic SDL bridge probes active opacity with opaque fallback | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; focus transitions and PGTK visual parity require R8 |
| P7-prep. Decoration bridge | EUP `FRAME_DECORATIONS` maps decorated/undecorated policy to the SDL border flag | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; parent/tooltip and complete WM policy require R8 |
| P7-prep. Scale bridge | EUP `FRAME_SCALE` owns scale/DPI state and SDL reports per-window display scale | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; live migration and redisplay adaptation require R8 |
| P7-prep. Fullscreen bridge | EUP `FRAME_FULLSCREEN` models Emacs modes and SDL probes/restores `fullboth` | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; width/height/maximized mapping and geometry parity require R8 |
| P7-prep. Monitor bridge | EUP `FRAME_MONITOR` owns monitor identity, primary flag, and bounds; SDL queries display geometry | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; live monitor changes and frame migration require R8 |
| P7-prep. Maximize bridge | EUP `FRAME_MAXIMIZE` carries horizontal/vertical policy and SDL probes/restores both-axis maximization | `proto-ui-unit` and `sdl3-runtime-bridge-smoke`; single-axis mapping and geometry parity require R8 |
| P8-prep. Lifecycle bridge | Heartbeat, flush, diagnostic, cancel-all, and input cancellation are bound to `PureRuntimeHostV1` | `runtime_bridge` unit suite; real host lifecycle still requires R8 |
| P9-prep. Authoritative geometry | Host geometry refresh bounds observed windows/damage and `FRAME_UPDATE` headers | `runtime_bridge` unit suite and SDL bridge smoke; real monitor/DPI still requires R8 |
| P14-prep. Continuous capture generations | A committed capture can begin a strictly newer redisplay generation, atomically reset bounded observations, bind accepted updates to flush, retain frame-lifetime hints, and invoke host flush before EUP emission | `runtime_bridge` unit suite; redisplay source and real host still require R8 |
| P15-prep. Terminal runtime service | Host terminal create/activate/drain/delete callbacks drive a bounded no-reuse registry with drain retry and rollback-pending cleanup | `terminal_service` unit suite and `proto-ui-terminal-service`; R7 approval and real Emacs host still required |
| P16-prep. Host adapter selection | A versioned pure-SDL3 `output_proto` candidate is unselected until R7 approval with complete metadata and policy validation | `host_adapter` unit suite and `proto-ui-host-adapter`; real adapter linkage still requires R8 |
| P17-prep. Runtime activation contract | Explicit activation and rollback sequences are selection-gated; conformance covers approved fake-host activate/rollback/drain | `runtime_activation` unit suite and `proto-ui-runtime-activation`; real activation still requires R8 |
| P18-prep. Explicit damage array | Bounded `DAMAGE_RECTS` codec, active-frame validation, atomic Scene replacement, bridge emission, and clipped retained-target present and command-culling smoke | Redisplay-owned incremental damage and dirty-texture upload still require R8 |
| P19-prep. Clear-area render control | A bounded face-colored rectangle is validated against the active frame/window and rendered by SDL | Redisplay-owned clear semantics still require R8 |
| P20-prep. Scroll-copy execution | A bounded full-window-width vertical `SCROLL_RUN` is validated, planned with overlap/upload metrics, and copied through a scratch SDL target | Redisplay-owned scroll semantics and general GPU batching still require R8 |
| P21-prep. Border style | `BORDER_UPDATE` validates side mask, bounded thickness, RGBA color, and active generation; SDL renders selected edges | Core-owned border geometry and window-manager parity still require R8 |
| P4. Terminal registration | `output_proto` can exist as a real terminal without PGTK initialization | Fake-host plus live terminal lifecycle tests after explicit R7 approval |
| P4. First pure frame | Emacs creates `window-system = proto`; SDL creates the visible surface | One local command creates, focuses, resizes, deletes the frame |
| P5. Redisplay-owned display | Rows/runs/cursor/damage come from Emacs redisplay | ASCII/CJK/BiDi/face fixtures compare against PGTK baselines |
| P6. Resources | Faces/fonts/images/strings are versioned, requested, evicted, and recovered | Snapshot/replay/eviction/resource-request suites pass |
| P7. Complete input | Keyboard, pointer, wheel, IME, selection, and DND reach Emacs and results render | PGTK/SDL differential input scenarios pass |
| P8. Desktop widgets | Menus, dialogs, tooltips, tool bars, scrollbars, and WM integration work | PGTK semantic matrix plus platform-specific checks |
| P9. Recovery/performance | Frontend failure is contained and performance targets are met | replay, fuzz, disconnect, GPU-reset, latency, throughput evidence |
| P10. W16 acceptance | Final user scenario is fully green | W16 checklist plus machine-readable artifacts |

P1 preparation adds `proto-ui-pgtk-parity-plan`.  The generated manifest is a
planned differential suite, not parity evidence; all cases remain `planned` and
the aggregate result remains `not_implemented`.  It is distinct from the future
`sdl3-pgtk-parity` runtime acceptance gate.

P12 session-setup preparation adds standard EUP setup codecs and a bounded
frontend state machine; EPXL authentication remains the current transport path
and standard setup is not yet wired into runtime.
P11 image presentation adds bounded RGBA8 resource rendering to the SDL bridge
smoke.  The smoke uses adapter-owned fake resources, so it is not Emacs
redisplay capture, production image policy, or PGTK parity.
P10 preparation adds face-bound GLYPH_RUN v2 to the bridge and SDL fallback.
The scene validates an exact live face generation and uses its bounded
foreground/background colors for diagnostic ASCII text only.  This is not
redisplay capture, shaping, font rendering, atlas rendering, or face parity.

P9 preparation adds authoritative host geometry: `runtime_bridge` refreshes
`read_geometry`, caches the host rectangle, validates observed windows and
damage against it, and emits frame headers from that authoritative geometry.
Real monitor, DPI, and scale events remain pending.

P8 preparation adds adapter-owned lifecycle operations to the bridge:
heartbeat, flush, diagnostic, and cancel-all-pending-work.  Cancelled SDL input
transactions can no longer report results or completions, preventing stale work
from re-entering the future host seam.

P7 preparation adds visibility/focus synchronization: `runtime_bridge` reads the
authoritative frame state, caches generation and values, validates legal focus
combinations, and can emit the existing EUP state messages.  No real platform or
Emacs host is attached yet.

P6 preparation adds the reverse input path: SDL key/text intents are normalized
to bounded `PureRuntimeHostV1.InputEvent` records and tracked through delivery,
result, and terminal completion states.  The host callback remains authoritative
for command interpretation; the frontend still evaluates no Elisp.

`sdl3-runtime-bridge-smoke` closes the fake-host loop through the independent
SDL3 renderer: the bridge emits EUP, `frontend.Scene` applies it, and SDL
presents the debug glyph text.  It deliberately reports
`emacs_registered=false`; this is not `output_proto` ownership.

P5 preparation extends the pure host run record with a bounded printable-ASCII
payload and lets `runtime_bridge` emit negotiated debug `GLYPH_RUN` messages
after a frame update.  This enables fallback text presentation in tests, but it
is not redisplay capture, shaping, BiDi reordering, faces, fonts, or production
glyph rendering.

A P4-preparation bridge now connects the same host ABI to bounded EUP frame
lifecycle messages.  It is exercised only with the adapter-owned fake host and
remains independent of Emacs registration, transport, and SDL presentation.

P3 also adds `proto-ui-runtime-host-abi`, which emits the matching C header and
runs a generated C conformance translation unit.  The C projection is build
output only; it is not linked into inherited Emacs and does not enable runtime.

P3 preparation adds `proto-ui-runtime-host`: a versioned
`PureRuntimeHostV1` ABI now defines all terminal, frame, redisplay, input, and
lifecycle callbacks with required nested contexts, fake-host conformance, and a
deterministic manifest.  This is an unlinked adapter contract; it does not
approve R7 or register `output_proto`.

P2 preparation adds `proto-ui-r7-proposal`, which emits
`zig-out/proto-ui/r7_proposal.json`.  The proposal is **ready for review** while
the decision itself remains **pending**.  The gate verifies pure-SDL3 target
policy, required callback groups, prerequisite groundwork, and fail-closed
state.  It does not approve R7, register a terminal, enable runtime, or relax
PGTK isolation.

## 7. PGTK differential gates

A capability is PGTK-parity green only when the same Emacs state produces the
same authoritative semantics in both reference and Proto builds.  Pixel equality
is not required because renderers differ, but semantics and visible content are
compared.

Required differential classes:

1. Frame creation, geometry, title, visibility, focus, iconification, fullscreen,
   monitor move, DPI change, and deletion.
2. Window split, resize, delete, balance, selected window, minibuffer, echo area.
3. Buffer text, point, mark, region, scroll, recenter, truncation, continuation,
   horizontal scrolling, tabs, overlays, and display properties.
4. ASCII, CJK, BiDi, ligature, variable-pitch, missing glyph, underline, box,
   inverse video, face remapping, theme change, and image display.
5. Keyboard, modifiers, prefixes, macros, pointer click/drag, wheel, touch where
   available, IME commit, and preedit placement.
6. Clipboard, PRIMARY selection, targets, encoding, DND text/files, and menus.
7. Tooltips, dialogs, mode/header/tab lines, tool bar, fringe, margin, and
   scrollbar behavior.
8. Reconnect, replay, malformed input, frontend crash, GPU loss, resource
   eviction, and clean shutdown.

Each scenario must record PASS/FAIL/SKIP with reason, PGTK digest or semantic
fingerprint, Proto digest or fingerprint, protocol counters, and screenshots
where visual behavior is relevant.

## 8. Final acceptance

The target is complete only when all of the following are true:

```sh
# Reference comparison build
zig build -Dpgtk=true -Dproto-ui=false

# Pure runtime build
zig build -Dpgtk=false -Dproto-ui=true -Dproto-ui-runtime=true \
  -Dsdl3-frontend=true

# Required suites
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-recovery-diff
zig build -Dproto-ui=true proto-ui-crash-isolation
zig build -Dpgtk=false -Dproto-ui=true -Dproto-ui-runtime=true \
  -Dsdl3-frontend=true sdl3-pgtk-parity
zig build check
```

These are target-state acceptance commands, not a statement that every step
currently exists.  In particular, `sdl3-pgtk-parity` is the future aggregate
gate.  Step names may be introduced for missing suites, but the evidence must
be real.
A green result requires:

1. A user-created Emacs frame reports `window-system` `proto`.
2. The visible surface is SDL3-owned and PGTK is not initialized on that path.
3. Redisplay-owned rows, resources, cursor, input, and desktop integration pass
   the differential gates.
4. The inherited-C boundary audit remains clean according to the approved
   adapter contract.
5. Replay, fuzz, recovery, crash-isolation, and default-isolation suites pass.
6. Performance evidence meets the targets in [`performance.md`](performance.md).
7. Capability status, protocol table, ABI manifest, runtime manifest, and docs
   describe exactly the same implementation state.

Until every gate is green, the status remains: **pure SDL3 target designed;
runtime and PGTK parity not implemented.**
