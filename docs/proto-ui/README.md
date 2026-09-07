# Emacs Proto-UI and SDL3 Frontend

Status: design baseline
Protocol: Emacs UI Protocol (EUP) v1
Branch: `zig-build-step-4`

## 1. Objective

Proto-UI adds an optional headless Emacs terminal backend, called `output_proto`, that exports Emacs display semantics through a stable protocol. A separate SDL3 frontend consumes the protocol, opens real operating-system windows, renders Emacs frames, and sends user input back to Emacs.

Adapter-first is a hard constraint.  New Proto-UI behavior is implemented in the Zig adapter, SDL3 frontend, protocol tooling, Lisp integration, or build glue—not by intrusively modifying inherited GNU Emacs C source.  See [`adapter-boundary.md`](adapter-boundary.md).

The completed system must:

1. Open a real Emacs frame with a real SDL3 frontend.
2. Preserve Emacs as the authoritative owner of buffers, windows, frames, faces, fonts, and redisplay.
3. Support an optional GPU-accelerated frontend while retaining a software fallback.
4. Provide a complete EUP interface and protocol table.
5. Preserve existing Emacs behavior when proto-ui is disabled.
6. Improve interactive display latency and frame scheduling relative to a non-accelerated fallback.
7. Reach PGTK-level Emacs UI capability over time, with every gap explicitly tracked.

## 2. Current status

The repository contains the complete English design baseline.  Historical W1-W4c-b0 direct-core prototypes were reviewed, but their inherited C/Lisp integration has been rolled back under the adapter-first rule.  The current implemented surface is adapter/frontend-only: the adapter implements the EUP v1 codec and bounded transport/replay, defines ABI v1, validates capture state with a fake host, and audits boundary paths through `zig build`.  The independent SDL3 frontend can consume real public Emacs frame-fact snapshots and a token-authenticated local live Unix stream with per-message ACK backpressure, rendering frame/window/row/cursor geometry.  An opt-in Emacs dynamic-module seam can continuously capture public frame/window dimensions, bounded visible ASCII text, and public point/cursor facts; SDL3 validates each changed snapshot as an EUP scene and renders the latest result. It exposes a bounded printable-ASCII text bridge and pressed, unmodified backspace/cursor intents through public observation APIs; W8b-a adds a persistent public-fact bridge in which a real SDL window delivers translated ASCII actions to a real Emacs process and renders the republished facts; W8c-c-a adds a frontend-owned EPXL delivery journal that retains an unacknowledged bounded intent and sequence across reconnect retry. W8c-c-b proves that recovery with a real Emacs ACK-loss smoke; W8d-a adds a real SDL EPXL interactive input smoke that translates an SDL event, carries it through authenticated EPXL, applies it in Emacs, and renders the refreshed facts. W8d-b makes this authenticated EPXL path the default for `--emacs-interactive` while retaining an explicit bounded local-action fallback. W8d-c carries the bounded copy intent over EPXL and installs the validated result in SDL clipboard. W8e-a adds bounded SDL pointer motion and single left-click intents over the same authenticated EPXL journal, and W8e-b orders left press/drag/release sessions; W8f-a adds bounded vertical wheel ticks over the same authenticated EPXL path, and W9g2 returns bounded window-start/visible-line viewport facts so scroll changes are observable in SDL; full recovery and full interactive frames remain pending; it does not expose redisplay internals, full keyboard/keymap/IME/command input, redisplay-owned cursor semantics, fonts, resources, or a complete interactive frame.  Glyph, face, font, and image resource capture, Emacs runtime integration, generic graphic frame creation, and the final objective remain pending adapter-first work.

W10a adds adapter-owned SDL renderer negotiation: the frontend reports the actual renderer tier, supports explicit software/GPU/named-driver selection, and falls back from GPU to software when required. W10b-a adds change-aware full-frame presentation with frontend full-frame-path and present/skip counters. W10b-b1 adds a reusable backend-neutral clear/fill/text draw list executed by SDL software and GPU-backed renderers. It also adds bounded SDL key/text translation, cursor/backspace artifact actions, and explicit monotonic reverse-input sequencing with one in-flight EPXL intent, exact transport ACK matching, and an Emacs apply-ACK before that transport ACK. Glyph atlas, image cache, blend/scissor, rectangle damage, native GPU counters, and full interactive-frame compatibility remain pending; persistent EPXL input subsequently arrived through W8c/W8d and now supports bounded pointer sessions. W11a adds the first bounded desktop clipboard paste path: Ctrl+V captures printable SDL clipboard text through the same validated input queue. W11b adds the matching bounded copy path: Ctrl+C observes an Emacs smoke buffer, publishes the validated first line through a local artifact, and SDL3 installs it in the platform clipboard; Unicode, rich text, MIME negotiation, and selection ownership remain pending. W10b-b2a adds a bounded adapter-owned glyph-atlas placement/LRU policy with hit/miss/eviction counters. W10c-a adds conservative initial/cursor/viewport/unchanged damage classification and counters; unchanged scene states skip presentation. W10c-b uses a bounded old/new cursor clip for cursor-only changes to avoid a full clear/redraw. W10c-c extends the retained target to bounded ASCII line/cursor region clips, while viewport, oversized, incomplete, and resource-level damage remain conservative full-frame work; GPU timestamps and partial present remain pending. Texture allocation and glyph-run rendering remain pending. W12a adds bounded EPXL capability negotiation with required-feature intersection, SHA-256 effective-set verification, and a generated machine-readable status manifest; full EUP-wide feature negotiation remains pending. W12b adds bounded frame create/update/destroy state and resource-generation declarations with atomic stale-generation rejection; real frame teardown and resource payloads remain pending.

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

PGTK remains the reference full-capability graphic backend. Proto-UI is compared against PGTK semantics but does not replace PGTK.

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
* Replace emacsclient or PGTK.
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
