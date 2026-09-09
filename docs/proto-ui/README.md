# Emacs Proto-UI and SDL3 Frontend

Status: design baseline
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

The repository contains the complete English design baseline.  Historical W1-W4c-b0 direct-core prototypes were reviewed, but their inherited C/Lisp integration has been rolled back under the adapter-first rule.  The current implemented surface is adapter/frontend-only: the adapter implements the EUP v1 codec and bounded transport/replay, defines ABI v1, validates capture state with a fake host, and audits boundary paths through `zig build`.  The independent SDL3 frontend can consume real public Emacs frame-fact snapshots and a token-authenticated local live Unix stream with per-message ACK backpressure, rendering frame/window/row/cursor geometry.  An opt-in Emacs dynamic-module seam can continuously capture public frame/window dimensions, bounded visible ASCII text, and public point/cursor facts; SDL3 validates each changed snapshot as an EUP scene and renders the latest result. It exposes a bounded printable-ASCII text bridge and pressed, unmodified backspace/cursor intents through public observation APIs; W8b-a adds a persistent public-fact bridge in which a real SDL window delivers translated ASCII actions to a real Emacs process and renders the republished facts; W8c-c-a adds a frontend-owned EPXL delivery journal that retains an unacknowledged bounded intent and sequence across reconnect retry. W8c-c-b proves that recovery with a real Emacs ACK-loss smoke; W8d-a adds a real SDL EPXL interactive input smoke that translates an SDL event, carries it through authenticated EPXL, applies it in Emacs, and renders the refreshed facts. W8d-b makes this authenticated EPXL path the default for `--emacs-interactive` while retaining an explicit bounded local-action fallback. W8d-c carries the bounded copy intent over EPXL and installs the validated result in SDL clipboard. W8e-a adds bounded SDL pointer motion and single left-click intents over the same authenticated EPXL journal, and W8e-b orders left press/drag/release sessions; W8f-a adds bounded vertical wheel ticks over the same authenticated EPXL path, and W9g2 returns bounded window-start/visible-line viewport facts so scroll changes are observable in SDL; full recovery and full interactive frames remain pending; it does not expose redisplay internals, full keyboard/keymap/IME/command input, redisplay-owned cursor semantics, fonts, resources, or a complete interactive frame.  Glyph, face, font, and image resource capture, Emacs runtime integration, generic graphic frame creation, and the final objective remain pending adapter-first work.

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
frontend state only, not Emacs title publication or `output_proto` frame
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
contract. Its current decision is pending, so runtime registration and a real
`output_proto` frame remain explicitly unavailable.

W14-a adds an opt-in, adapter-only hot-path benchmark. It measures five
memory-transport scenarios with deterministic 960x600 fixtures, reports
iteration/warmup counts, byte volume, monotonic p50/p95/p99/mean latency,
throughput, observed allocation counts, build mode, and protocol version.
It is evidence only: success does not depend on host timing, the runtime
contract stays pending, and no SDL or inherited Emacs C/Lisp dependency is
introduced.

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
remains fail-closed preparation; R7 approval and a real Emacs terminal are
still absent.
`zig build -Dproto-ui=true proto-ui-terminal-service` runs the deterministic
fake-host evidence gate and reports `emacs_registered=false` plus
`runtime_available=false`.

P16 host-adapter selection preparation adds a versioned pure-SDL3
`output_proto` candidate policy.  While R7 is pending, the candidate remains
`unselected`; approval and complete review metadata are required before
selection.  The candidate forbids inherited-source edits, backend fallback, and
frontend ownership.  The current gate still reports no activation, registration,
or runtime.

P17 runtime-activation preparation defines the approved activation order and
reverse rollback order.  A selection-gated controller can exercise the path with
a fake host, but the repository's current activation gate is `blocked_by_r7`,
performs no host callback, and still reports `runtime_available=false`.

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
implemented adapter prerequisites.  The R7 decision remains pending.

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
P57 real-window snapshot preparation projects bounded public live-window geometry into `FRAME_UPDATE`; the selected window carries existing text/cursor evidence and SDL receives other observed windows as authoritative boxes.  Cross-restart stable IDs, per-window cursors, hierarchy, faces, and command dispatch remain pending; bounded per-window text is now unit-projected.
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
| [`protocol.md`](protocol.md) | Complete EUP v1 wire protocol, envelope, message IDs, payload semantics, and state machines |
| [`capabilities.md`](capabilities.md) | Backend, frontend, renderer, widget, and PGTK parity capability matrices |
| [`frame-lifecycle-smoke.md`](frame-lifecycle-smoke.md) | Current real-frame lifecycle bridge smoke, scope, environment, and acceptance |
| `sdl3-frontend.md` | SDL3 process model, window handling, input bridge, rendering pipeline, and platform integration |
| `performance.md` | Performance tiers, budgets, test scenarios, instrumentation, and regression gates |
| `implementation-plan.md` | Workstreams, concrete tasks, acceptance gates, and final definition of done |
| [`runbook.md`](runbook.md) | Current build/test commands, expected smoke behavior, and troubleshooting boundary |

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
