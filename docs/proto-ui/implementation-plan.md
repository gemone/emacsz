# Proto-UI Implementation Plan

Status: active planning baseline
Goal: implement a real SDL3-backed Emacs UI through EUP without breaking existing Emacs behavior

Historical runtime record: W0's schema design remains normative.  W1-W4c-b0
section headings, acceptance commands, and present-tense implementation notes
are historical review records.  Their runtime code and inherited C/Lisp
integration were rolled back; the current status table and W4c-b1-p0/t0/b0
describe the implemented adapter-only Proto-UI surface.

Hard constraint: adapter-first.  New behavior is implemented in the Zig
adapter, SDL3 frontend, Lisp integration, replay/protocol tooling, or build
glue.  Intrusive changes to inherited GNU Emacs C source are prohibited; see
[`adapter-boundary.md`](adapter-boundary.md).

## 1. Execution rules

1. Each implementation workstream is broken into independently reviewable tasks.
2. Every code-writing task requires a dedicated review agent cycle.
3. The review cycle has at least three passes:
   * Correctness and semantic conformance.
   * Repository/build/integration impact.
   * Alignment with proto-ui, EUP, SDL3, and Emacs compatibility goals.
4. Concrete fixes are made between review passes.
5. A task is not complete until review findings are resolved and its acceptance command or evidence exists.
6. Documentation changes still require consistency review, but the mandatory three-pass gate applies to code.
7. Every code or documentation change includes an adapter-boundary audit:
   identify the owner of each behavior, prove default isolation, and show a
   rollback path.

## 2. Current status

| Area | Status |
|---|---|
| Architecture specification | Documented |
| EUP protocol specification | Documented |
| Capability/PGTK parity matrix | Documented |
| EUP envelope/resource/FRAME_UPDATE codec | Implemented (adapter-only) |
| Memory sink and replay-file transport | Implemented (adapter-only) |
| SDL3 frontend design | Documented |
| SDL3 window/renderer lifecycle | Implemented (independent frontend smoke) |
| EUP replay scene client | Implemented (window/row/cursor geometry only) |
| Local live EUP transport handshake | Implemented (token-authenticated Unix stream) |
| Live EUP ACK backpressure | Implemented (one in-flight message) |
| Performance baseline | Documented |
| Build option `-Dproto-ui` | Adapter-only EUP codec/transport, ABI/summary generation, unit tests, fake-host conformance, and boundary audit; no Emacs runtime integration |
| W2 registration seam | Approved historically; runtime integration rolled back |
| W3a lifecycle identity | Approved historically; runtime integration rolled back |
| W3b terminal lifecycle | Approved historically; runtime integration rolled back |
| W3c lifecycle-only frame objects | Approved historically; runtime integration rolled back |
| W4a redisplay begin/cursor/flush capture | Approved historically; runtime integration rolled back |
| W4b window/row metadata capture | Approved historically; runtime integration rolled back |
| W4c-a damage/hook coverage | Approved historically; runtime integration rolled back |
| W4c-b0 headless frame visibility/count observability | Approved historically; runtime integration rolled back |
| W4c-b1-b0 adapter ABI and fake-host conformance | Approved (adapter-only) |
| W4c-b1-p0 adapter-only EUP protocol codec | Approved (adapter-only) |
| W4c-b1-t0 adapter-only bounded transport/replay | Approved (adapter-only) |
| Automated W3c frame smoke | Rolled back with runtime integration |
| `output_proto` terminal | Rolled back with runtime integration |
| Redisplay capture | Rolled back; adapter ABI v1 contract only |
| Resource model | Bounded identity, payload-cache/eviction, and request/evict wire contract; actual resource payload/render model not implemented |
| SDL3 frontend | Partial: EUP replay/live rendering, renderer tiers, damage classes, bounded facts, ASCII/key/pointer/wheel/clipboard bridges, and EPXL recovery; no redisplay streaming, full keyboard/keymap/IME input, faces, fonts, images, widgets, or production frame ownership |
| Bounded real-frame lifecycle bridge | Implemented by W12c: one real PGTK observation frame and one EUP/SDL3 frame are created, rendered, and deleted |
| Final real `output_proto` SDL3 Emacs frame | Not achieved |
| Pure SDL3 PGTK-parity target | Normative target documented; runtime and parity not implemented |
| P1 PGTK/SDL differential parity plan | Implemented as a 48-case planned policy manifest; no differential case or parity evidence is complete |
| P3 PureRuntimeHostV1 ABI | Implemented as adapter-owned fake-host contract for five callback groups; Emacs registration and runtime remain absent |
| P3 PureRuntimeHostV1 C projection | Implemented with generated header and compiled C conformance; not linked to inherited Emacs or runtime |
| P4-prep PureRuntimeHostV1 bridge | Implemented with bounded fake-host EUP frame lifecycle/update conformance; no Emacs registration, transport, or SDL presentation |
| P5-prep bounded run payload | Implemented for fake-host debug `GLYPH_RUN` fallback; redisplay capture, shaping, faces, and production runs remain pending |
| P5-prep SDL bridge presentation | Implemented as a fake-host SDL3 smoke; not `output_proto`, Emacs registration, production redisplay, or parity evidence |
| P6-prep reverse input bridge | Implemented for bounded SDL key/text intents through PureRuntimeHostV1 delivery/result/completion; not keymap/command parity |
| P7-prep visibility/focus bridge | Implemented for cached host state and EUP state message conformance; real platform/Emacs round trips pending |
| P8-prep lifecycle bridge | Implemented for heartbeat, flush, diagnostic, and cancel-all through PureRuntimeHostV1; real host lifecycle still pending |
| Protocol coverage manifest | Implemented for all 164 assigned EUP IDs: 164 implemented codecs, 0 partial, and 0 planned; prevents an unclassified or overclaimed protocol table |
| Protocol coverage gate | Implemented as `proto-ui-protocol-coverage`; deterministic artifact and boundary dependency |
| P12-prep EUP session setup | Implemented standard HELLO/HELLO_ACK/SESSION_READY/READY_ACK codecs and bounded state machine; not yet wired to EPXL transport |
| P12-prep EUP session control | Implemented all eight standard-control codecs, automatic PONG, Scene integration, and EPXL transport for every control, including fatal VERSION_MISMATCH |
| P12-prep frame presentation feedback | Implemented `FRAME_PRESENTED`/`FRAME_DROPPED` codecs and SDL counter conformance; core consumption and adaptive pacing pending |
| P12-prep frame geometry | Implemented `FRAME_GEOMETRY` codec, nested-rectangle validation, Scene state, and SDL border query; core-owned resize migration pending |
| P12-prep frame icon | Implemented nullable `FRAME_ICON` codec, live RGBA image/hotspot validation, Scene state, and SDL surface icon; multi-resolution/animated icons pending |
| P12-prep frame size hints | Implemented min/max/increment/aspect codec, Scene state, and SDL min/max/aspect constraints; size increments and redisplay adaptation pending |
| P12-prep frame z-order | Implemented operation codec, relative-frame validation, Scene state, and SDL always-on-top probe; bottom/relative stacking and redisplay adaptation pending |
| P12-prep frame parent | Implemented nullable parent/modal codec, child/active-parent identity validation, Scene state, and SDL unparent probe; linked/modal child windows pending |
| P12-prep window patch | Implemented bounded geometry/parent/visibility/face/depth patch with cycle and depth validation; zones/scroll pending |
| P12-prep cursor update | Implemented dedicated cursor codec, Scene owner/geometry validation, and SDL render evidence; cursor styles/IME pending |
| P14-prep continuous capture generations | Implemented monotonic host-capture reuse from `captured` to `capturing`, atomic observation reset, stale-generation rejection, monotonic encoded/accepted `FRAME_UPDATE` identity, host-flush-bound `FLUSH` emission, and frame-lifetime render hints; no real Emacs host |
| P15-prep terminal runtime service | Implemented `proto-ui-terminal-service` for fake-host create/activate/drain/delete orchestration with no-reuse registry IDs, drain retry, rollback-pending cleanup, and strict identity validation; no R7 approval or Emacs terminal |
| P16-prep host adapter selection | Implemented the versioned pure-SDL3 `output_proto` candidate as unselected until an approved, metadata-complete R7 decision; machine-readable gate records no activation, registration, or runtime |
| P17-prep runtime activation contract | Implemented a selection-gated controller plus explicit activation/rollback sequences; current gate remains blocked by pending R7 with no registration or runtime |
| P21-prep R8 entry readiness | Implemented a machine-readable blocked-entry manifest with seven readiness requirements, inherited-source audit, rollback-order audit, and opt-in negative launch gate |
| P18-prep explicit damage array | Implemented bounded `DAMAGE_RECTS` codec, atomic Scene replacement, bridge emission, union clipping, clipped retained-target present, and command-culling counters with smoke evidence; redisplay-owned incremental damage pending |
| P19-prep clear-area render control | Implemented a 40-byte face-colored `CLEAR_AREA` v1 codec with bounded Scene table, active-frame/window bounds, live-face validation, and SDL render evidence; not redisplay capture |
| P20-prep scroll-copy execution | Implemented bounded full-width vertical `SCROLL_RUN` v1, Scene band validation, overlap planning, estimated RGBA upload metrics, and scratch-target SDL retained-frame copy execution; redisplay ownership and GPU batching pending |
| P21-prep border style | Implemented 16-byte `BORDER_UPDATE` v1 with side mask, bounded thickness, RGBA color, active-frame validation, and SDL selected-edge rendering; window-manager border semantics pending |
| P22-prep divider update | Implemented 40-byte vertical/horizontal `DIVIDER_UPDATE` v1 with generation replacement, active-window bounds, bounded Scene table, and SDL fixed-color rendering; draggable semantics pending |
| P23-prep fringe update | Implemented 40-byte left/right `FRINGE_UPDATE` v1 with generation replacement, bounds validation, bounded Scene table, and SDL color-band rendering; bitmap glyphs and redisplay capture pending |
| P24-prep face decoration bars | Implemented policy-derived underline, overline, strike-through, and box-edge approximation bars in the SDL debug glyph path; shaped text, font metrics, and core face parity pending |

| P9-prep authoritative geometry | Implemented in runtime bridge with host rectangle caching and frame/window/damage bounds; real monitor/DPI events pending |
| P10-prep face-bound debug runs | Implemented with GLYPH_RUN v2, exact live-face validation, and colored SDL fallback; not production face/shaping parity |
| P11-prep SDL image presentation | Implemented for complete bounded RGBA8 resources in fake-host bridge smoke; redisplay capture and PGTK parity pending |
| P11-prep window tree snapshot | Implemented as bounded codec/Scene state for complete trees; window management commands and rendering parity remain pending |












| P2 R7 registration proposal | Implemented as ready-for-review policy artifact; R7 decision, terminal registration, and runtime remain pending |


| Adapter-first C boundary | Required; no new inherited-C Proto-UI edits |
| W9a independent SDL3 lifecycle smoke | Approved |
| W9b SDL3 EUP replay scene renderer | Approved |
| W9c-a local live EUP transport smoke | Approved |
| W9c-b live ACK backpressure | Approved |
| W9c-c1 Emacs dynamic-module seam | Approved: identity/string + public frame facts |
| W9c-c2 public frame-fact observation | Approved (display-capable host) |
| W9d real Emacs facts to EUP/SDL3 snapshot | Approved |
| W9e continuous real Emacs public-fact stream | Approved |
| W9f continuous facts validated as EUP snapshots | Approved |
| W9g authenticated EPXL continuous facts transport | Approved |
| W9h real-fact producer coalescing | Approved |
| W9i authenticated EPXL resync reconnect | Approved |
| W9j public ASCII text observation | Approved |
| W9k bounded ASCII text input bridge | Approved |
| W9l public point and dynamic cursor | Approved |
| W10a SDL renderer negotiation | Approved |
| W10b-a change-aware present and frontend counters | Approved |
| W10b-b1 renderer-agnostic SDL draw list | Approved |
| W8a bounded SDL input translation | Approved |
| W8b-a persistent public-fact interactive bridge | Approved |
| W8c-a EPXL reverse-input sequencing | Approved |
| W8c-b Emacs apply-ACK | Approved |
| W8c-c-a persistent EPXL delivery journal | Approved |
| W8c-c-b EPXL ACK-loss recovery smoke | Approved |
| W8d-a real SDL3 EPXL interactive input | Approved |
| W8d-b default SDL3 interactive transport selection | Approved |
| W8d-c EPXL interactive clipboard copy | Approved |
| W8e-a bounded SDL pointer motion/click | Approved |
| W8e-b ordered left drag/release | Approved |
| W8f-a bounded wheel scroll intent | Approved |
| W8f-b bounded horizontal wheel intent | Implemented |
| W8g2 publisher Elisp resource and atomic facts | Approved |
| W8g3 manual authenticated EPXL session | Implemented; bounded bridge, not `output_proto` |
| W9g2 bounded viewport facts | Approved |
| W10b-b2a bounded glyph-atlas policy | Approved |
| W10c-a damage classification baseline | Approved |
| W10c-b cursor-only clipped redraw | Approved |
| W10c-c bounded text-region clipping | Approved |
| W10d bounded GLYPH_RUN debug fallback | Approved |
| W10e real-frame public-facts glyph marker | Approved |
| W10f explicit bounded glyph-run delete | Approved |
| W12a EPXL capability/status manifest | Approved |
| W12b frame lifecycle/resource generation contract | Approved |
| W12c real-frame lifecycle bridge smoke | Approved |
| W12d frame visibility/focus state contract | Approved |
| W12e resource payload/eviction contract | Approved |
| W12f optional host frame-state ABI seam | Approved |
| W12g output-proto runtime design and R1 terminal lifecycle | Approved |
| W12h fail-closed runtime manifest/gate | Approved |
| W12i generated C shim and linkable observation library | Approved |
| W12j R5 frame service mapping | Approved |
| W12k R6 atomic capture batches | Approved |
| W12l R7 host-registration decision contract | Approved |
| W12l-a R7 reviewer packet | Implemented; decision remains pending |
| W12m R8 entry-readiness manifest and negative gate | Approved; R8 entry remains blocked |
| W11a bounded clipboard paste | Approved |
| W11b bounded clipboard copy | Approved |
| Build option `-Dsdl3-frontend` | EUP replay, local live, and opt-in Emacs facts/text/input/cursor modes; the Emacs mode is process/public-API observation and adapter-owned EUP transport, not redisplay-hook streaming |
| W8b-a persistent public-fact bridge | Approved historically: real SDL frame polls public Emacs facts and applies bounded local-file actions; persistent EPXL delivery subsequently arrived through W8c/W8d and W8e-a adds bounded pointer intents |

The workstream sections below retain their historical review records and
implementation details.  The Current status table is authoritative when an
older section says that rolled-back runtime code is present.

## 3. Workstreams

### W0 — Protocol and schema freeze

Goal: establish a stable implementation contract before coding.

Tasks:

1. Freeze EUP v1 envelope field order and flags.
2. Freeze message ID table.
3. Freeze `FRAME_UPDATE` table order.
4. Define resource ID/generation encoding.
5. Define capability key names and effective-intersection rules.
6. Define unknown-message/unknown-capability behavior.
7. Add protocol conformance examples to documentation.

Deliverables:

* Complete protocol document.
* Message ID table with no collisions.
* Capability tables with fallbacks.
* Explicit v1 non-goals.

Acceptance:

* Protocol document is internally consistent.
* Every message has direction, payload summary, QoS class, and state effect.
* Every required capability has a fallback.

Historical status: approved before the adapter-first rollback.  The W1
protocol/transport implementation is no longer present.

Historical implemented W1 evidence (runtime code rolled back):

1. `src/proto-ui/protocol.zig` encodes/decodes the 62-byte envelope, capability name/value table, resource identity, and the `FRAME_UPDATE` concrete header/section envelope.
2. `src/proto-ui/transport.zig` implements ordered memory-sink and bounded replay-file primitives.
3. `zig build -Dproto-ui=true proto-ui-unit --summary all` passes.
4. The dedicated reviewer completed three-plus passes and approved the W1 skeleton on commit `9548f0a6a4d`.
5. Native, foreign-target host-runner, clean-export, and default-build gates were reproduced by the reviewer.

### W1 — Protocol implementation skeleton (historical; runtime rolled back)

Goal: implement EUP encode/decode independently of Emacs.

Tasks:

1. Add Zig protocol module layout.
2. Implement envelope serialization and validation.
3. Implement message registry and unknown-message policy.
4. Implement resource ID/generation types.
5. Implement capability set encoding.
6. Implement `FRAME_UPDATE` table encode/decode.
7. Implement memory sink and replay-file sink.
8. Add round-trip and malformed-input tests.

Deliverables:

```text
src/proto-ui/root.zig
src/proto-ui/protocol.zig
src/proto-ui/transport.zig
Inline Zig tests in the protocol/transport modules
```

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
```

Review gates:

1. Wire-format correctness.
2. Zig/build integration and dependency impact.
3. Compatibility with the frozen EUP document.

### W2 — Build and terminal registration

Goal: introduce `output_proto` without changing default behavior.

Tasks:

1. Add `-Dproto-ui` build option.
2. Define `HAVE_PROTO_UI` only when enabled.
3. Add `output_proto` to the terminal enum behind the feature.
4. Add proto frame storage and `FRAME_PROTO_P`.
5. Defer proto graphic-predicate integration until W4 (revised during W3c).
6. Map `output_proto` to the `proto` Lisp symbol.
7. Add empty initialization/frame-creation Lisp methods.
8. Keep `-Dproto-ui=false` default behavior identical.

Deliverables:

* Existing C/header seams.
* `build.zig` option and linkage.
* Initial `lisp/term/proto-win.el`.

Acceptance:

```sh
zig build --summary all
zig build -Dproto-ui=true --summary all
```

Additional evidence:

1. Default configured feature list does not mention proto unless enabled.
2. Enabled build exposes the backend registration symbols.
3. No new C source file is added.

Review gates:

1. Terminal integration correctness.
2. Build/default-config isolation.
3. Emacs backend ABI compatibility.

#### W4a evidence

1. `src/proto-ui/backend.zig` implements frame redisplay generations, cursor state, full-damage `FRAME_UPDATE`, and stable window IDs.
2. `src/terminal.c` installs update-begin, cursor, and flush hooks through `proto_redisplay_interface`.
3. `zig build -Dproto-ui=true proto-ui-unit --summary all` passes 18/18.
4. `zig build -Dproto-ui=true proto-ui-smoke --summary all` creates a real lifecycle-only frame, captures exactly one `FRAME_UPDATE`, and verifies deletion/cleanup.
5. The dedicated reviewer completed three-plus passes and approved W4a.

### W3a — Headless lifecycle identity (approved)

Goal: implement protocol-safe frame identity and emitted lifecycle messages
before touching Emacs terminal objects.

Tasks:

1. Implement lifecycle session state.
2. Allocate non-recycled terminal/frame IDs and generations.
3. Emit `FRAME_CREATE` / `FRAME_DESTROY` messages.
4. Guarantee rollback or explicit failure ordering.
5. Decode and verify successful emitted create/destroy protocol payloads and
   rollback behavior.

Deliverables:

* Zig lifecycle state and C-facing ABI.
* Headless lifecycle messages.
* Protocol conformance tests.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
```

Status: approved.

### W3b — Real headless terminal lifecycle (approved)

Goal: create and delete a real `output_proto` terminal without frames.

Tasks:

1. Connect lifecycle ABI to `create_terminal` and terminal deletion.
2. Assign a stable EUP terminal ID and preserve it on the terminal object.
3. Install terminal deletion hooks and release lifecycle state.
4. Expose `proto-ui-create-terminal` for controlled runtime tests.

Deliverables:

* `output_proto` terminal object.
* Terminal state mapping.
* Controlled create/delete/recreate runtime evidence.

Acceptance:

```sh
zig build -Dproto-ui=true --summary all
```

```elisp
(setq terminal (proto-ui-create-terminal))
(terminal-live-p terminal)              => proto
(terminal-name terminal)                => "proto"
(delete-terminal terminal)
(terminal-live-p terminal)              => nil
(setq terminal (proto-ui-create-terminal))
(terminal-live-p terminal)              => proto
(delete-terminal terminal)
(terminal-live-p terminal)              => nil
```

Status: approved.

### W3c — Lifecycle-only headless frame lifecycle (approved)

Goal: create and delete a real, invisible Emacs frame object with a stable
EUP frame ID, while explicitly deferring rendering and `FRAME_WINDOW_P`
support to W4+.

Tasks:

1. Define lifecycle-only `struct proto_output`.
2. Create real Emacs frame objects on a real `output_proto` terminal.
3. Map Emacs frame objects to stable EUP session/frame IDs.
4. Emit `FRAME_CREATE` / `FRAME_DESTROY` and roll back failed creation.
5. Add `proto-ui-create-frame` and `delete-frame` lifecycle smoke coverage.

Deliberate W3c limitation: proto frames are not `FRAME_WINDOW_P`, are
invisible, and have no face/render state until W4 adds redisplay capture.

Review gates:

1. Emacs frame lifecycle correctness.
2. Protocol frame create/destroy message coherence.
3. Failure/deletion safety.

Automated gate: `zig build -Dproto-ui=true proto-ui-smoke`.

### W4a — Synthetic redisplay capture foundation (approved)

Goal: prove the first redisplay-interface-to-EUP path without rendering.

Tasks:

1. Install a proto `redisplay_interface`.
2. Capture update-begin and flush boundaries.
3. Assign stable proto window IDs.
4. Capture cursor geometry/state.
5. Emit exactly one conservative full-damage `FRAME_UPDATE` with cursor,
   damage, and present-hint sections.

Deliberate limitation: update-end is a no-op in W4a.  Glyph, face, font,
image, partial-damage, and real redisplay capture remain W4b/W4c.


### W4b — Window and row metadata capture (approved)

Goal: add the first real after-update window and row metadata capture without
rendering or claiming full redisplay parity.

Tasks:

1. Maintain stable proto window IDs and geometry.
2. Capture zero-based row index and row metrics.
3. Encode bounded WINDOWS/ROWS sections in `FRAME_UPDATE`.
4. Mark row-cap failures and reject the update.
5. Remove window/row state on frame/terminal destruction.

Deliberate limitations: no glyph runs, face/font/image resources, partial row
updates, clear-area hooks, replay fixtures, or update-end semantics.

Acceptance:

A metadata-only backend gate proves:

```text
update begin
stable window ID and geometry
zero-based row index and metrics
ordered WINDOWS/ROWS/DAMAGE/PRESENT_HINT sections
zero row flags and zero reserved bytes
256-row cap; exceeding it marks capture failed
rejected/cancelled flush commits no partial update
frame/window removal clears metadata
```

Review gates:

1. `zig build -Dproto-ui=true proto-ui-unit` on native Linux, musl Linux, and
   Windows targets.
2. `zig build -Dproto-ui=true proto-ui-smoke`.
3. Atomic-update and cleanup assertions.
4. Absence of glyph, face, font, image, and buffer-text layout claims.

### W4c — Full redisplay capture

#### W4c-a — Bounded damage capture and safe hook coverage (approved)

Goal: remove unsafe null redisplay seams and capture actual damage rectangles
without rendering.

Tasks:

1. Track successful window-update boundaries before frame flush.
2. Capture bounded write, clear, scroll, glyph-string, fringe, border, and
   divider damage rectangles.
3. Use partial damage when rectangles are captured; keep the conservative
   full-frame fallback when none are captured.
4. Enforce a 256-rectangle cap and reject/cancel overflow atomically.
5. Use core glyph production without drawing; leave renderer-specific
   overhangs and frame parameters explicitly unsupported in this slice.

Acceptance:

Backend tests prove payload ordering, multiple damage rectangles, fallback
damage mode, invalid rectangle rejection, and atomic overflow behavior.  The
Emacs smoke still uses its deterministic synthetic gate and proves the C
integration/link remains clean.  Real-frame fixtures remain W4c-b1-b.

#### W4c-b0 — Headless frame display observability (approved)

Goal: add the minimum frame-control and observation surface needed before
driving real redisplay.

Tasks:

1. Let the headless proto terminal set real Emacs frame visibility without an
   OS window.
2. Expose the committed `FRAME_UPDATE` count without forcing a synthetic
   capture.
3. Verify visible/invisible transitions, count isolation, synthetic capture,
   and cleanup in smoke.

Acceptance: the smoke proves all three.  This is not a redisplay fixture and
does not make `FRAME_WINDOW_P` true.

#### W4c-b1-a — Batch-safe real-row redisplay fixture (reverted and quarantined)

Goal: prove that a visible proto frame can run core redisplay and publish real
desired rows without rendering.

Status: reverted and quarantined.  This slice modified `terminal.c`,
`xdisp.c`, and `xfaces.c` directly, violating the adapter-first boundary.  Do
not restore it without an adapter-owned redesign.

Tasks:

1. Add a controlled `proto-ui-redisplay-frame` primitive.
2. Temporarily detach the proto RIF while core redisplay builds desired rows,
   restoring it through an unwind protector.
3. Capture enabled desired rows, their geometry, and row damage as one atomic
   `FRAME_UPDATE`.
4. Use deterministic terminal-style placeholder metrics until W5 adds font and
   face resources.
5. Reject nested redisplay and fail/cancel atomically on row or damage limits.

Acceptance:

The smoke creates a visible proto frame, inserts text, runs the real-row
fixture, observes exactly one committed update, then runs the synthetic capture
as a second update.  It does not encode glyphs, faces, fonts, images, cursors,
scroll optimization, or rendering.

#### W4c-b1-p0 — Adapter-only EUP protocol codec (approved)

Goal: make the normative EUP v1 contract executable before adding transport or
Emacs integration.

Implemented:

1. `src/proto-ui/protocol.zig` implements the 62-byte envelope, assigned
   message-ID table, delivery classes, capability table, resource identity,
   and 88-byte `FRAME_UPDATE` header/section codec.
2. The decoder validates little-endian layout, CRC-32C integrity, reserved
   flags, unsupported transport features, trailing bytes, canonical section
   ordering, extension ranges, and untrusted allocation bounds.
3. A canonical-table test pins the 164 assigned IDs from the normative
   protocol tables and rejects unknown mapped classes, disorder, and the
   invalid sentinel.

Acceptance:

`zig build -Dproto-ui=true proto-ui-unit --summary all` passes 18/18.  The
implementation is adapter-only, has no Emacs runtime seam, and the changed-path
boundary audit rejects inherited C edits.

#### W4c-b1-t0 — Adapter-only bounded transport/replay (approved)

Goal: provide deterministic in-memory sequencing and durable replay without
attaching a socket or Emacs runtime seam.

Implemented:

1. `src/proto-ui/transport.zig` owns a bounded `MemorySink` that encodes EUP
   envelopes, assigns ordered sequences, rejects stale sequences, and evicts
   the oldest record beyond 256 entries.
2. `ERP1` replay files store a u32 message count and length-prefixed messages.
3. The reader enforces the 64 MiB ceiling and rejects bad magic/count, short
   lengths, truncation, and trailing corruption without returning partial
   ownership.

Acceptance:

`zig build -Dproto-ui=true proto-ui-unit --summary all` passes 23/23.  The
transport remains adapter-only and is not linked into Emacs.

#### W4c-b1-b0 — Adapter ABI and fake-host conformance (approved)

Goal: establish the versioned adapter/ABI contract before any new redisplay
integration.

Implemented:

1. `src/proto-ui/adapter.zig` owns host/adapter table definitions, capture
   state, row/damage limits, generation validation, and cancellation.
2. `src/proto-ui/conformance.zig` provides a fake host with only opaque IDs,
   generations, and geometry.
3. `src/proto-ui/abi_gen.zig` emits `abi_v1.h` and a non-normative ABI
   summary named `manifest.json` into
   `zig-out/include/proto-ui` as build artifacts.
4. `proto-ui-conformance` validates complete capture, partial capture, bad
   ABI, null callback, generation mismatch, and cancellation.
5. `proto-ui-boundary` runs ABI generation, fake-host conformance, and the
   classifier smoke audit.  Full changed-path auditing uses
   `zig build -Dproto-ui=true proto-ui-boundary-audit -- path/to/file`.

Acceptance:

All generated files are installed outside tracked inherited C sources.  The
fake-host conformance harness and adapter unit tests pass with `zig build`.

#### W4c-b1-b1 — Normal-RIF streaming through the adapter (blocked pending design)

The first direct-core prototype was rejected and quarantined because it
required intrusive changes to inherited Emacs C code.  Do not resume that
patch.  Redesign the workstream so a Proto-UI-owned adapter observes the
normal RIF path through a stable, separately owned seam.

Normative redesign:
[`zig-build-adapter.md`](zig-build-adapter.md).

Tasks:

1. Define adapter-owned streaming state and lifecycle.
2. Define a stable registration contract to existing Emacs extension points,
   with no new inherited-C edits.
3. Capture row creation/update/deletion and complete clear-area semantics in
   the adapter.
4. Capture coalescing and ensure damage/row/window snapshots agree.
5. Preserve cursor, scrolling, truncation, continuation, and BiDi visual-order
   semantics for later encoding.
6. Add replay captures and compare synthetic versus real-frame output.
7. Keep failure atomic: reject incomplete updates.

Acceptance:

Real frame redisplay emits coherent `FRAME_UPDATE` metadata and damage without
rendering, and the adapter-boundary audit shows no new inherited-C Proto-UI
edits.  Glyph, face, font, and image resource capture remain W5.

### W5 — Glyph, face, and font capture

Goal: reproduce text visually.

Tasks:

1. Capture glyph runs with cluster and visual order.
2. Capture glyph metrics/offsets.
3. Map Emacs face IDs to EUP face resources.
4. Map Emacs font metrics to EUP font resources.
5. Capture underline, overline, strike-through, and box faces.
6. Capture BiDi visual order.
7. Capture glyphless and composition runs.
8. Add ASCII, CJK, BiDi, ligature, and face test fixtures.

Acceptance:

Replay must reproduce:

```text
ASCII text
CJK text
BiDi paragraph
bold/italic/underline
face foreground/background changes
missing glyph fallback marker
```

Review gates:

1. Text metrics fidelity.
2. Resource reference safety.
3. Hot-path allocation/bandwidth.

### W6 — Resources and cache policy

Goal: publish all render resources needed by frames.

Tasks:

1. Implement face define/patch/delete.
2. Implement font define/metrics/delete.
3. Implement image metadata and payload fragmentation.
4. Implement fringe bitmap publication.
5. Implement icon/string resources. *(W6-a covers bounded string define/delete only.)*
6. Implement generation invalidation.
7. Implement resource request handling.
8. Add cache limit diagnostics.

Acceptance:

* Every render item references available resources.
* Missing resources produce `RESOURCE_REQUEST`.
* Stale generations never render.
* Resource pressure cannot crash Emacs.

Review gates:

1. Resource lifecycle correctness.
2. Transport reliability.
3. Memory bounds.

#### W6-a status

Status: W6-a complete as a bounded adapter/frontend resource contract.

`STRING_DEFINE` (`0x050e`) carries a nonzero resource ID and generation,
a byte length of 1..4096, and exactly that many non-NUL UTF-8 bytes.
`STRING_DELETE` (`0x050f`) is exactly two nonzero little-endian `u32` values.
The decoder rejects truncation, trailing bytes, oversize, invalid UTF-8, NUL,
and invalid identity.

The frontend scene enforces normal session and contiguous-sequence rules, owns
at most 64 string payloads, synchronizes identity/generation through the
existing resource registry, allocates before mutation, rejects equal/stale
generations atomically, releases exact-generation deletes, and clears strings
on destroy/resync/deinit. `resource.string_v1` is degraded and non-negotiable
with `proto-ui-unit` evidence. `resource.v1` and full face/font/image resource
parity remain pending; no renderer claim is made.

#### W6-b status

Status: W6-b complete as a bounded adapter/frontend face resource contract.

`FACE_DEFINE` (`0x0500`) is a fixed little-endian 96-byte record with identity,
generation, optional font/stipple references, RGBA8 colors, decoration and box
style tags, box width, inverse/extend booleans, and line spacing. All reserved
bytes are zero and optional references are either both zero or both nonzero.
Style/color presence is internally consistent by construction.

`FACE_DELETE` (`0x0502`) uses exact nonzero identity/generation. The frontend
owns at most 64 active faces, synchronizes through the face resource registry,
rejects equal/stale generations without sequence drift, performs exact deletes,
and permits replacement at capacity. Faces survive frame destroy intentionally;
resync and scene teardown clear them. `resource.face_v1` is degraded and
non-negotiable with `proto-ui-unit` evidence. This is a face wire subset, not
redisplay capture or Emacs face parity; `resource.v1`, fonts, images, rendering,
and `output_proto` remain pending.

#### W6-c status

Status: W6-c complete as a bounded adapter/frontend font resource contract.

`FONT_DEFINE` (`0x0503`) is a fixed little-endian 224-byte record with
identity/generation, bounded UTF-8 family/foundry/style strings using exact
length prefixes, strict slant and spacing tags, CSS-style weight, width
percentage, strict scalable/fixed-pitch booleans, optional pixel/point/DPI
values, authoritative vertical and advance metrics, baseline and underline
metrics, and explicit zero feature/variation/fallback counts. All reserved and
unused bytes are zero. Metric ranges, DPI pairing, spacing/fixed-pitch
consistency, advance ordering, and vertical metric consistency are enforced.

`FONT_DELETE` (`0x0506`) uses exact nonzero identity/generation. The frontend
owns at most 64 active fonts, synchronizes through the font resource registry,
rejects equal/stale generations without sequence drift, performs exact
deletes, and permits replacement at capacity. Fonts survive frame destroy
intentionally; resync and scene teardown clear them. `resource.font_v1` is
degraded and non-negotiable with `proto-ui-unit` evidence. This is a descriptor
wire subset, not shaping, rasterization, rendering, redisplay font capture, or
Emacs font parity; `resource.v1`, images, full resource model, and
`output_proto` remain pending.

#### W6-d status

Status: W6-d complete as a bounded adapter/frontend image resource contract.

`IMAGE_DEFINE` (`0x0507`) is a fixed little-endian 72-byte record with
nonzero identity/generation, dimensions bounded to 1..8192, an exact
64-bit-checked `width * height * 4` total capped at 4 MiB, RGBA8
premultiplied/sRGB/premultiplied-alpha tags only, nearest or linear scaling,
identity transform, LRU or pinned cache policy, and exactly one zero-duration
animation frame.  All reserved bytes are zero.

`IMAGE_DATA` (`0x0508`) has a 16-byte little-endian header and exact payload
bytes.  It permits 1..256 fragments of 1..65536 bytes, ordered without gaps or
duplicates, for the exact declared generation.  Allocation is bounded by the
declared total before fragment copying; the final fragment is accepted only
when the assembled byte count exactly equals the declared total.  Wrong totals,
oversized chunks, wrong generations, malformed metadata, duplicate/out-of-order
fragments, truncation, and trailing bytes reject without sequence advance.

`IMAGE_DELETE` (`0x0509`) uses exact nonzero identity/generation, works for
complete or incomplete payloads, frees owned bytes, and synchronizes the image
registry to `deleted`.  The frontend owns at most 8 active images and enforces
an aggregate declared byte budget of 4 MiB.  A strictly newer generation may
replace at capacity and resets prior fragments.  Images survive frame destroy
intentionally; resync and scene teardown clear them.  `resource.image_v1` is
degraded and non-negotiable with `proto-ui-unit` evidence.

Limits: no actual image decoding, color management, texture upload, scaling,
animation, rendering, redisplay image capture, Emacs image parity,
`resource.v1`, host registration, or `output_proto` runtime is claimed.

#### W6-e status

Status: W6-e complete as an atomic concrete-resource snapshot/restore contract.

`RESOURCE_SNAPSHOT` (`0x0512`) v1 has an exact format/version header, 0..64
ordered entries, and a fixed entry header containing kind, live/deleted status,
nonzero identity/generation, payload length, and zero reserved bytes.  Entry
IDs are unique by kind.  Deleted records are zero-length tombstones.  Live
payloads use the existing exact concrete encodings: 96-byte face records,
224-byte font records, 1..4096 bytes of strict UTF-8 for strings, or complete
`IMAGE_DEFINE` metadata plus the exact declared RGBA8 bytes.  Payload identity
must agree with entry identity; aggregate live image bytes are capped at 4 MiB;
invalid boundaries, reserved bytes, duplicates, unsupported live families, and
trailing bytes reject.

The frontend builds an entire replacement state before mutation.  A successful
snapshot atomically replaces string/face/font/image tables and the shared
registry, records tombstones, and clears incomplete image state.  Any error
leaves prior resources and the contiguous sequence untouched; resync and scene
deinit release owned state.  `resource.snapshot_v1` is degraded and
non-negotiable with `proto-ui-unit` evidence; `resource.v1` remains pending.

Limits: no resource capture, runtime registration, transport activation,
rendering, image decoding, complete Emacs resource parity, or `output_proto`
runtime is claimed.

### W7 — Transport and recovery

Goal: support real frontend IPC and deterministic recovery.

Tasks:

1. Implement memory ring sink.
2. Implement replay-file writer/reader.
3. Implement local socket transport.
4. Implement pipe transport.
5. Implement shared-memory transport.
6. Implement frame coalescing.
7. Implement replay window.
8. Implement snapshot fallback and resync.

Acceptance:

1. Frontend reconnect restores coherent state.
2. Truncated replay is detected.
3. Sequence gaps trigger resync.
4. Slow frontend never blocks Emacs.

Review gates:

1. Concurrency safety.
2. Backpressure behavior.
3. Emacs isolation.

### W8 — Input translation

Goal: let SDL3 input drive Emacs commands.

Tasks:

1. Implement key event translation.
2. Implement Unicode text input.
3. Implement modifier and lock state.
4. Implement pointer motion/click/drag.
5. Implement wheel and touchpad scroll.
6. Implement focus events.
7. Implement window close/resize/move requests.
8. Implement monitor/DPI/theme events.
9. Add synthetic input test harness.

Acceptance:

Synthetic input can:

```elisp
move point
set mark
run keyboard quit
select a menu item
scroll a window
resize a frame request path
```

Review gates:

1. Emacs event correctness.
2. Device ordering.
3. No frontend-owned command policy.

#### W8a — Bounded SDL input translation (approved)

Goal: translate a deliberately narrow set of SDL keyboard and text events into
the existing facts-profile EUP input messages before integrating a persistent
interactive session.

Tasks:

1. Add adapter-owned SDL scancode translation for pressed, unmodified
   `backspace` and the four cursor direction keys.
2. Copy bounded printable `TEXT_INPUT` text into a fixed event queue.
3. Reject key release, auto-repeat, any modifier, empty/non-printable/oversized
   text, and queue overflow.
4. Expand the facts-profile key action codes to `1` through `5`.
5. Extend the EPXL artifact bridge from backspace-only to backspace and cursor
   motion.
6. Add an SDL synthetic-event smoke that pushes one modified key, five accepted
   editing keys, and printable text, then verifies the translated queue.

Implemented limits: this is translation and transport-policy preparation, not a
persistent interactive Emacs frame. Pointer, wheel, focus, IME, Unicode text,
keymaps, modifiers, repeats, commands, and full session integration remain
pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-input-translate-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes. It verified scancode/modifier/state mapping,
bounded text copies and queue limits, key-codec action validation, EPXL reverse
ACK sequencing, artifact action semantics, SDL event layout assumptions,
default isolation, changed-path and negative inherited-C audits, and explicit
deferred-scope reporting.

#### W8b-a — Persistent public-fact interactive bridge (approved)

Goal: keep a real Emacs bridge process alive while a real SDL window renders its
public facts and delivers bounded translated input through an atomic local
action file. This is an explicit bridge milestone, not persistent EPXL input.

Tasks:

1. Add a persistent Emacs public-fact/action evaluator that publishes frame,
   bounded visible ASCII, and public cursor facts every poll.
2. Add a bounded input queue with FIFO pop and atomically write one translated
   key/text action at a time.
3. Gate delivery on observed fact updates so a later intent cannot overwrite an
   unconsumed action.
4. Poll the public fact file in the SDL loop, rebuild the EUP scene on changes,
   and retain change-aware rendering/counters.
5. Add `--emacs-interactive` and an automated `--emacs-interactive-smoke`
   synthetic text case.
6. Verify that the real Emacs bridge applies the text and republishes the
   updated public facts.

Implemented limits: this bridge uses a local action file, not EPXL reverse
input; it renders public facts rather than redisplay-owned glyphs; and its
semantics are limited to printable ASCII plus backspace/cursor intent. Persistent
EPXL delivery, full keyboard support, modifiers/IME/Unicode, pointer/focus, and
complete frames remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes. It verified FIFO queue ownership, atomic action
publication and consumption, fact-snapshot lifetime and parse-failure handling,
public Emacs action semantics, real SDL/Emacs process wiring, changed-path and
negative inherited-C audits, and explicit non-EPXL/non-redisplay scope.

#### W8c-a — EPXL reverse-input sequencing (approved)

Goal: make the facts-profile reverse-input sender state explicit so multiple
key/text intents use monotonic sequences with exactly one message in flight and
exact ACK matching.

Tasks:

1. Add an adapter-owned `SenderState` for reverse-input sequence allocation and
   ACK ownership.
2. Reject sequence zero, stale ACKs, duplicate ACKs, and a new send while an
   input is in flight.
3. Replace hard-coded sequence one in the EPXL frontend auto-input path with the
   shared sender state.
4. Add a two-intent EPXL smoke that sends printable text then backspace, each
   with its own ACK.
5. Verify that the bridge applies the final transported action and renders the
   resulting public facts.

Implemented limits: the current local action bridge ACKs when an action is
published to Emacs, not when Emacs reports that Lisp has applied it. Therefore
the smoke verifies monotonic transport sequencing and the final action's result,
not ordered application of every historical action. Persistent frontend session
delivery and an Emacs apply-ACK remain W8c-b.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes. It verified one-in-flight ownership, monotonic
sequence allocation, exact ACK matching and stale/duplicate rejection, text/key
sender integration, publisher compatibility, changed-path and negative
inherited-C audits, and explicit deferral of an Emacs apply-ACK.

#### W8c-b — Emacs apply-ACK (approved)

Goal: distinguish "the bridge published an action" from "Emacs executed that
action" before EPXL acknowledges the reverse input.

Tasks:

1. Extend the EPXL action record to `sequence`, `kind`, and `value` lines.
2. Have the real Emacs bridge execute the public editing action, write an
   apply-ACK artifact containing the exact sequence, and delete the action.
3. Have the publisher validate the exact sequence, remove the apply-ACK, and
   only then send the EPXL ACK.
4. Bound apply-ACK waiting to two seconds and reject malformed, empty, stale, or
   duplicate payloads.
5. Extend the sequence smoke to assert ordered final state after text insertion
   followed by backspace.

Implemented limits: this proves action application for the bounded facts-profile
bridge. It is not an inherited terminal input-event ACK, redisplay-completion
ACK, persistent frontend delivery, or reconnect/recovery contract.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes, then approved fixes for the ACK/action cleanup race,
ACK deletion failure propagation, and the edit regression assertion. Final checks
verified exact sequence ACKs, bounded cleanup, ordered final state, changed-path
audits, negative inherited-C rejection, and explicit non-redisplay scope.

#### W8c-c-a — Persistent EPXL delivery journal (approved)

Goal: retain a bounded reverse-input intent and its wire sequence across an
EPXL reconnect instead of restarting sequence state or duplicating the intent.

1. Add a frontend-owned `DeliveryJournal` with a bounded FIFO, one pending
   intent, monotonic sender state, and a maximum of three send attempts.
2. On reconnect, arm retry for an unacknowledged intent and resend the original
   sequence; reject a second `take` while the original send remains in flight.
3. Clear the pending intent only after the exact transport ACK; retain it and
   the attempt count on malformed, stale, duplicate, or missing ACKs.
4. Unify the EPXL text/key sender on the journal so the resync frontend owns
   delivery state across sequential authenticated sessions.
5. Preserve the existing one-in-flight protocol and Emacs apply-ACK semantics.
6. Make the facts publisher recognize the immediately previous applied
   sequence after reconnect and ACK it without applying it again.

Implemented limits: the unit tests model loss of the transport ACK and bounded
retry after `beginRetry`; the live smoke still reconnects only after the prior
intent has been acknowledged. Publisher crash recovery, arbitrary transport-gap
detection, interactive SDL input over EPXL, and resources/redisplay recovery
remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build,
and boundary/docs/status passes. Final checks verified same-sequence retry and
exhaustion behavior, publisher duplicate-sequence ACK idempotence, EPXL
input/edit/sequence/resync regressions, inherited-C rejection, and the full
built-in check run.

#### W8c-c-b — EPXL ACK-loss recovery smoke (approved)

Goal: prove the W8c-c-a journal on a real Emacs EPXL session when the frontend
discards a successfully transported input ACK and reconnects.

1. Add an opt-in `--emacs-epxl-recovery-smoke` path that discards only the
   first `TEXT_INPUT` ACK after Emacs has applied it.
2. Preserve the pending intent, original sequence one, and bounded attempt
   count in the frontend journal across the authenticated session boundary.
3. On reconnect, retry sequence one. The publisher recognizes the immediately
   previous applied sequence and ACKs it without invoking Emacs again.
4. Assert that the recovered SDL scene contains exactly the once-applied
   `XEmacs Proto-UI` line and the cursor at column eight on row one.
5. Treat a peer reset after an authenticated resync as the bounded session
   boundary instead of discarding a coherent scene.

Implemented limits: the fault is an opt-in frontend ACK-event discard, not
kernel-level packet corruption; only the bounded facts profile is covered.
Publisher process crash, arbitrary sequence-gap replay, resource recovery, and
interactive SDL input over EPXL remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-recovery-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build,
and boundary/docs/status passes. Final checks verified same-sequence retry,
publisher idempotence, exact recovered text/cursor state, all EPXL regressions,
changed-path and inherited-C audits, and the default-build isolation gate.

#### W8c-c-c — Display sequence-gap recovery (implemented)

Goal: detect a lost or skipped display-frame sequence during an established EPXL
session and recover from the next authoritative snapshot instead of applying a
frame out of order or silently tearing down the session.

Implemented:

1. `frontend.Scene` records that a sequence mismatch requires recovery and
    rejects the mismatched message without advancing its sequence or mutating
    display state.
2. `Scene.resetForResync` tracks recovery generations and clears the pending
    recovery request before the authenticated `RESYNC_BEGIN` snapshot.
3. The SDL EPXL frontend converts the rejected-message signal into
    `RESYNC_REQUEST`, resets only after `RESYNC_BEGIN`, ACKs each coherent
    recovery frame, and validates `RESYNC_COMPLETE` against the final recovered
    sequence.
4. The facts publisher recognizes the mid-session request, resets its assigned
    display scene, emits one authoritative bounded-facts snapshot, and closes
    the recovery with the final sequence.
5. An opt-in gap-fault path suppresses the first changed display message and
    requires the frontend to recover in the same authenticated transport
    session.

Implemented limits: this covers the bounded facts profile and an in-session
authoritative snapshot. It does not recover arbitrary resources, replay display
history, recover a crashed publisher, or coalesce redisplay updates. Sequence
monotonicity restarts at the recovery boundary by explicit snapshot semantics.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-gap-recovery-smoke
```

#### W8d-a — Real SDL3 EPXL interactive input (approved)

Goal: connect the real SDL3 event path to authenticated EPXL reverse input so
the frontend no longer depends on local action artifacts for its interactive
smoke.

1. Add `--emacs-epxl-interactive-smoke` and `sdl3-epxl-interactive-smoke`.
2. Open a real SDL3 window, initialize text input, translate SDL text/key
   events, and queue them in the frontend delivery journal.
3. Publish bounded fact heartbeats from the Emacs publisher so reverse input
   has a deterministic transport window without polling local artifacts.
4. Deliver queued intents as EPXL `TEXT_INPUT` or `KEY_EVENT`, require Emacs
   apply-ACK followed by the EPXL ACK, and apply subsequent fact snapshots.
5. Present every coherent live scene through the existing renderer-agnostic
   SDL draw list and record present/skip counters.
6. Assert the real Emacs result `XYEmacs Proto-UI` and cursor column 2.

Implemented limits: this is the bounded facts profile and printable-ASCII
subset. Heartbeats are a smoke-session transport window, not final redisplay
coalescing or production push scheduling. Modifiers, Unicode, IME, pointer,
frames, resources, redisplay-owned glyph state, and full Emacs commands remain
pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-sequence-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes. Final checks verified SDL event translation, EPXL ACK ordering, Emacs text/cursor application, heartbeat lifecycle, all EPXL regressions, changed-path and inherited-C audits, and the full built-in check run.

#### W8d-b — Default SDL3 interactive transport selection (approved)

Goal: make the authenticated EPXL path the default for `--emacs-interactive`
while retaining the W8b-a local action file as an explicit diagnostic and
fallback.

1. Route `--emacs-interactive` and `--emacs-interactive-smoke` through the
   real SDL EPXL interactive frontend.
2. Keep local file actions available only through
   `--emacs-interactive-local` and
   `--emacs-interactive-local-smoke`; keep clipboard-copy smoke on the local
   bridge until copy is promoted to EPXL.
3. Separate synthetic-input automation from normal operation with
   `interactive_synthetic`; normal `--emacs-interactive` does not inject a
   keystroke.
4. Rename the original local smoke build step to
   `sdl3-emacs-interactive-local-smoke` and make
   `sdl3-emacs-interactive-smoke` exercise the default EPXL path.

Implemented limits: clipboard copy remains on the local fallback. This is
bounded facts-profile input and does not imply redisplay-owned frames, full
keymaps, Unicode/IME, pointer, resources, or production push scheduling.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-local-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-copy-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes. Final checks verified default/synthetic separation, EPXL interactive operation, local fallback selection, clipboard-copy rollback coverage, changed-path and inherited-C audits, and the full built-in check run.

#### W8d-c — EPXL interactive clipboard copy (approved)

Goal: move the default bounded copy shortcut from the local-action fallback to
the authenticated EPXL interactive path while retaining an explicit rollback.

1. Translate the real SDL Ctrl+C shortcut in both interactive frontends and
   queue the existing `KEY_EVENT.copy` action.
2. Carry copy intent through EPXL with the standard one-in-flight sequence,
   Emacs apply-ACK, and EPXL ACK rules.
3. Teach the Emacs facts publisher to perform the bounded first-line
   `kill-ring-save` and publish the validated result artifact.
4. Have SDL validate the printable-ASCII artifact and install it through
   `SDL_SetClipboardText`; the synthetic smoke still requires the exact
   `Emacs Proto-UI` payload.
5. Make `sdl3-emacs-copy-smoke` exercise the default EPXL path and add
   `sdl3-emacs-copy-local-smoke` for rollback.

Implemented limits: EPXL carries the copy intent; the bounded printable-ASCII
copy payload still uses a local artifact because EUP has no clipboard-data
resource yet. Unicode, rich text, MIME negotiation, selection ownership,
clipboard ownership events, external clipboard targets, and full kill-ring
semantics remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-copy-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-copy-local-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-local-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes added Emacs-side bounds before substring/copy, removed stale fallback wording, and synchronized input ownership. Final checks verified copy smoke paths, interactive regressions, boundary and inherited-C audits, and the full built-in check run.

#### W8e-a — Bounded SDL pointer motion/click (approved)

Goal: extend authenticated EPXL reverse input from text/keys to a deliberately
small pointer surface without claiming full mouse or geometry compatibility.

1. Freeze the bounded `POINTER_EVENT` payload as phase, button, bounded x/y,
   click count, modifiers, and reserved bytes.
2. Accept only bounded coordinates, zero-modifier motion, and single-button
   left press events from SDL.
3. Coalesce motion to the idle journal boundary so a motion stream cannot fill
   the bounded queue or displace clicks.
4. Carry pointer intents through the same `DeliveryJournal`, EPXL sequencing,
   Emacs apply-ACK, and EPXL ACK contract as text/keys.
5. Map a bounded left press through public Emacs `posn-at-x-y` / `posn-point`
   and republish the resulting public point.
6. Add `sdl3-pointer-smoke` to validate motion transport, click application,
   and SDL rendering of the refreshed cursor.

Implemented limits: only left-button press and zero-modifier motion are
supported. Release, drag, wheel, touch, multi-button, double-click,
multi-window hit testing, pixel-exact variable-pitch geometry, overlays, and
mouse face remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes added safe coordinate conversion, drag-state rejection, pressed-state validation, fail-closed pointer admission, and idempotent reverse-input docs. Final checks verified pointer smoke, interactive and EPXL regressions, boundary and inherited-C audits, and the full built-in check run.

#### W8e-b — Ordered left drag/release (approved)

Goal: extend W8e-a from isolated left clicks to an ordered press → drag motion →
release session while preserving the bounded, fail-closed input profile.

1. Accept drag motion only while a left press session is active and encode it as
   `POINTER_EVENT.motion` with button one.
2. Accept release only for the active left session; clear the session only after
   the release is admitted to the journal.
3. Reject duplicate press, release without press, idle drag motion while active,
   and key/text insertion into an active pointer session.
4. Preserve FIFO journal order and the existing EPXL one-in-flight, apply-ACK,
   and transport-ACK rules across all pointer events.
5. Apply both bounded press and release positions through public Emacs
   `posn-at-x-y` / `posn-point`; intermediate drag motion is transported and
   ACKed but has no text-selection semantics.
6. Extend `sdl3-pointer-smoke` with real SDL press, pressed motion, and release
   events; success requires a delivered release and a changed public cursor.

Implemented limits: this is ordered transport and public-point mapping, not
complete mouse-drag selection. Region/mark semantics, modifiers, multi-button,
double-click, hit testing, variable-pitch geometry, overlays, and mouse face
remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes made pointer session admission atomic under queue-full pressure, routed clipboard paste through journal admission, restricted drag transport to the exact left-button mask, and returned the actual delivered intent for release detection. Final checks verified ordered pointer smoke, interactive/EPXL regressions, boundary and inherited-C audits, and the full built-in check run.

#### W8f-a — Bounded wheel scroll intent (approved)

Goal: carry SDL wheel ticks through authenticated EPXL and apply them with
public Emacs scrolling without opening pixel-level or touchpad gesture scope.

1. Freeze the facts-profile `WHEEL_EVENT` payload as line unit, wheel source,
   zero modifiers, bounded horizontal/vertical ticks, and reserved zero bytes.
2. Accept only vertical whole-tick values from `-8..8`; horizontal ticks,
   pixel/page units, touchpad/gesture sources, and modifiers are rejected.
3. Queue wheel intents through the same bounded journal, EPXL sequencing,
   Emacs apply-ACK, and EPXL ACK rules as text, key, pointer, and copy intents.
4. Reject wheel admission while an ordered pointer drag session is active.
5. Map downward ticks to public `scroll-up` and upward ticks to public
   `scroll-down` in the real Emacs publisher.
6. Add `sdl3-wheel-smoke` with real SDL down/up events and require both
   delivered wheel intents to be acknowledged after Emacs application.

Implemented limits: W8f-a covered only vertical line ticks.  W8f-b extends the
same bounded profile to horizontal whole-line ticks while preserving the
one-axis-only rule.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-wheel-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes rejected zero/horizontal/diagonal, flipped-direction, and fractional/mismatched wheel deltas, and corrected reverse-input idempotence docs. Final checks verified wheel smoke, pointer/interactive regressions, boundary and inherited-C audits, and the full built-in check run.

#### W8f-b — Bounded horizontal wheel intent (implemented)

Goal: extend the existing line-wheel bridge to horizontal scrolling without
introducing pixel, momentum, touchpad, or modifier scope.

1. Keep `WHEEL_EVENT` byte compatibility and require exactly one of `x`/`y` to
   be nonzero, bounded to `-8..8`.
2. Translate normal-direction SDL horizontal wheel deltas with exact integer/
   float agreement.
3. Preserve bounded delivery-journal admission, EPXL sequencing, and apply-ACK
   rules.
4. Map positive/negative horizontal ticks to public Emacs
   `scroll-right`/`scroll-left` in the diagnostic publisher.
5. Extend `sdl3-wheel-smoke` to require two vertical and two horizontal
   acknowledged intents.
6. Extend the pointer smoke to negotiated Pointer v2 and add an explicit
   generic publisher mode that maps bounded left press/drag/release to the
   public point; selection and middle-paste publisher modes remain unchanged.

Implemented limits: pixel/page scrolling, momentum/touchpad phase, smooth
deltas, precise scroll position, modifiers, diagonal wheels, and full
window-scroll state remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-wheel-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-smoke --summary all
```

#### W8g2 — Publisher Elisp resource and atomic facts (approved)

Goal: remove the fragile escaped publisher `--eval` program while preserving
the bounded authenticated EPXL facts and reverse-input behavior.

1. Move authenticated publisher Lisp to
   `tools/proto-ui-sdl3/facts_publisher.el`.
2. Supply module, facts, input, clipboard, and capability switches through
   `PROTO_UI_*` environment variables.
3. Include `identity = "process_lifetime"` whenever public windows are present.
4. Write the complete snapshot to `facts.json.tmp`, then atomically rename it
   to `facts.json`.
5. Keep the local interactive fallback on the same resource with a local
   compatibility profile and two-field action artifacts.
6. On frontend failure, wait for the publisher to observe transport closure and
   terminate its Emacs child before deleting private session artifacts.

Implemented limits: this remains a public-facts diagnostic bridge.  It does not
register `output_proto`, capture redisplay, evaluate frontend-supplied Elisp,
or claim PGTK parity.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-local-smoke --summary all
```

A failure-path gate also verifies that a frontend error waits for publisher and
Emacs child exit before the private session directory is removed:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-failure-cleanup-smoke --summary all
```

Status: approved.  The dedicated review completed correctness, lifecycle, allocator, pointer semantics, viewport behavior, and failure-path cleanup passes.  Focused local checks included unit/boundary gates and authenticated, local, Unicode, selection, middle-paste, wheel, frame, and failure-cleanup smokes.

#### W8g3 — Manual authenticated EPXL session (implemented)

Goal: expose the authenticated EPXL bridge as a manually closable session
without changing the fail-closed `output_proto` runtime boundary.

1. Define `--auto-quit-ms=0` as “no smoke deadline” for the authenticated
   interactive publisher and frontend; positive smoke deadlines remain fixed.
2. Add `sdl3-emacs-interactive` as a manually closable authenticated EPXL
   SDL3 session backed by the adapter-owned publisher resource.
3. On SDL close, close transport, wait for publisher and Emacs child exit, and
   remove private session artifacts.
4. Keep the target explicitly bounded: public facts, negotiated text/key/wheel/
   pointer intents, no redisplay streaming, no frontend Elisp evaluation, no
   `output_proto` registration, and no PGTK parity claim.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-local-smoke --summary all
zig build help 2>&1 | grep -F 'sdl3-emacs-interactive'
```

Manual evidence requires a graphical session:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive
```

#### W9g2 — Bounded viewport facts (approved)

Goal: make wheel scrolling observable on the SDL side by publishing a bounded
snapshot of the Emacs window viewport instead of only acknowledging a scroll
intent.

1. Extend the public-facts snapshot with `window_start_line` and
   `window_visible_lines`, observed through public Emacs window APIs.
2. Capture bounded visible buffer text from `window-start` through `window-end`
   instead of the whole oversized smoke buffer.
3. Map the absolute public point into a viewport-relative cursor row for the
   15-row facts profile.
4. Add an adapter-owned EUP extension section that carries viewport start and
   bounded visible-line count with each `FRAME_UPDATE`.
5. Extend `sdl3-viewport-smoke` to inject one wheel tick and require the
   returned viewport start to advance while retaining the scrolled text.

Implemented limits: viewport facts are bounded to 32 lines, 120 columns, and
the 15-row facts renderer; they expose start/count, not full scroll state,
pixel vscroll, horizontal scroll, overlays, variable-pitch lines, or
redisplay-owned glyph runs.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-wheel-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-viewport-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-local-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes removed raw snapshot diagnostics, added overflow-safe viewport validation, required coherent viewport/text counts, protected baseline unwrapping, repaired the local evaluator, and documented EUP extension section `0x8001`. Final checks verified viewport, wheel, pointer, interactive, and EPXL regressions plus boundary and inherited-C audits.

### W9a — Independent SDL3 window lifecycle (approved)

Goal: validate the real OS window, renderer selection, event pump, and clean
shutdown before adding protocol state.

Implemented:

1. `-Dsdl3-frontend=true` builds the independent `proto-ui-sdl3` executable
   from `tools/proto-ui-sdl3/main.zig` and links the system SDL3 package.
2. `sdl3-ui-smoke` initializes video, creates a resizable 800×600 window,
   creates the default renderer, clears/presents one opaque frame, pumps quit
   events, and exits after 80 ms unless closed first.
3. SDL errors are reported with `SDL_GetError`; shutdown occurs through defer
   even when a later lifecycle operation fails.

Acceptance:

```sh
zig build -Dsdl3-frontend=true sdl3-ui-smoke --summary all
```

The command opens a real SDL3 window on a display-capable host.  It does not
connect to Emacs, decode EUP, render text, or imply final SDL3 acceptance.

### W9b — SDL3 EUP replay scene renderer (approved)

Goal: decode a deterministic EUP session and render frame/window/row/cursor
geometry before introducing a live transport.

Implemented:

1. `src/proto-ui/frontend.zig` owns frontend scene state and decodes concrete
   WINDOW, ROWS, CURSORS, DAMAGE, and PRESENT_HINT records from validated
   `FRAME_UPDATE` payloads.
2. The scene enforces session identity, ordered sequences, frame generation,
   record geometry, window ownership, damage bounds/mode, zero row flags, row
   ordering, and protocol row/damage caps before atomically replacing displayed
   state.
3. `tools/proto-ui-sdl3/fixture.zig` writes a deterministic ERP1 replay
   containing `FRAME_CREATE` and one `FRAME_UPDATE`.
4. `tools/proto-ui-sdl3/main.zig` reads that replay, applies every message,
   and renders the resulting SDL3 window, rows, window border, and cursor.

Not yet implemented: live transport negotiation, text glyphs, faces, input,
resources, and an Emacs frame.

Acceptance:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
```

The smoke opens a real SDL3 window and reports one applied update with one
window and 15 rows.  It does not connect to Emacs or imply final acceptance.

### W9c-a — Local live EUP transport smoke (approved)

Goal: prove an authenticated local stream can carry the same EUP messages that
the replay path validates, without adding an Emacs seam.

Implemented:

1. `src/proto-ui/live.zig` freezes EPXL v1: a 44-byte handshake, two message
   kinds, a 256-bit token, constant-time token comparison, and bounded
   length-prefixed EUP frames up to 16 MiB.
2. The SDL executable's `--publisher` mode reads an ERP1 source, listens on a
   Unix stream endpoint, authenticates one client, sends the server-ready
   handshake, and length-prefixes every EUP message.
3. `sdl3-live-smoke` generates an ephemeral 256-bit token, creates a private
   `0700` smoke directory and `0600` token file, starts the publisher as a
   separate process, connects from the SDL frontend, verifies the token and
   zero server-ready token, applies the live stream to the same scene validator,
   and renders the resulting frame.  The private directory is removed on the
   normal path and on post-spawn errors.

Not yet implemented: full reconnect/resync recovery, dynamic adapter-owned
publishing, frame coalescing, and nonblocking Emacs redisplay.

Acceptance:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-live-smoke --summary all
```

The smoke runs two OS processes over a private local Unix stream and renders
one live session update.  The source remains deterministic until the adapter
has a stable Emacs seam.

### W9c-b — Live ACK backpressure (approved)

Goal: prevent an unbounded publisher from outrunning the SDL frontend.

Implemented:

1. EPXL v1 defines a 20-byte control frame with `ACK`, `RESYNC_REQUEST`,
   `RESYNC_BEGIN`, and `RESYNC_COMPLETE` kinds.  `ACK` is implemented.
2. The publisher allows one outstanding EUP frame, waits for its contiguous
   `ACK`, and rejects stale, duplicate, out-of-order, or unexpected control
   frames with `AckTracker`.
3. After the scene validates and atomically applies each live EUP message, the
   frontend sends an `ACK` for that transport sequence.

This is transport backpressure only; producer-side coalescing of superseded
frame updates remains future work because final sequence assignment must happen
after coalescing.

Acceptance:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-live-smoke --summary all
```

The smoke completes only when both processes exchange contiguous EUP-sequence
ACKs for every live message.

### W9c-c — Live recovery and coalescing (planned)

Goal: recover safely after transport interruption and avoid publishing superseded
display work.

Tasks:

1. Implement frontend reconnect with a new authenticated EPXL session.
2. Request and receive resync snapshots using `RESYNC_REQUEST`, `RESYNC_BEGIN`,
   and `RESYNC_COMPLETE`.
3. Assign final EUP sequences after producer-side coalescing.
4. Maintain one pending update per frame and drop only superseded frames.
5. Add slow-client, disconnected-client, malformed-control, and interrupted-body
   tests.

Review gates:

1. No partially applied or stale frame reaches the frontend scene.
2. Sequence/resource recovery is deterministic.
3. Publisher memory remains bounded.

### W9c-d — Adapter-owned Emacs live publisher (planned)

Goal: replace the deterministic ERP1 source with a live publisher fed by a
stable, adapter-owned Emacs seam.

Tasks:

1. Select and implement an adapter-owned seam without inherited GNU Emacs C
   edits.
2. Publish authoritative Emacs display state over the existing EPXL ACK window.
3. Keep Emacs redisplay nonblocking when the frontend is slow or absent.
4. Verify process lifecycle, secret/token handling, and crash containment.

Review gates:

1. Transport security and local IPC boundary.
2. Sequence/resource recovery.
3. No inherited-C runtime coupling.

### W9c-c1 — Adapter-owned Emacs dynamic-module seam (approved)

Goal: establish a stable, opt-in Emacs seam without modifying inherited GNU
Emacs C source.

Implemented:

1. `tools/proto-ui-emacs-module/main.zig` implements the Emacs dynamic-module
   ABI in Zig and installs `zig-out/proto-ui/proto-ui-module.so` (platform
   suffix varies).
2. The module verifies GPL identity, environment ABI version, function
   registration, Lisp string extraction, and string creation.
3. `proto-ui-frame-facts` observes public Emacs APIs (`frame-selected-window`,
   `frame-pixel-width`, `frame-pixel-height`, `window-pixel-width`, and
   `window-pixel-height`) and returns bounded JSON facts.  It does not inspect
   redisplay internals.
4. `proto-ui-window-facts` observes up to 16 live windows through public APIs
   (`frame-selected-window`, `window-list`, `car`, `cdr`, `nth`,
   `window-pixel-edges`, `boundp`, `symbol-value`, `set`, `make-hash-table`,
   `gethash`, `puthash`, and `eq`) and returns bounded flat geometry facts with
   the selected-window ordinal.  Ordering remains relative to the selected
   window, but each window receives a nonzero `id` from an adapter-owned,
   process-lifetime `eq` hash registry with weak keys and a monotone counter.
   Dead keys can be collected; IDs are not reused while the Emacs process
   lives.  This is not a hierarchical window tree and does not inspect
   redisplay internals.
5. `proto-ui-module` builds the adapter-owned artifact; a batch gate loads it
   through `module-load`, verifies `proto-ui-echo`, and validates bounded
   multi-window facts.

The seam is intentionally public-API-only.  It does not expose redisplay
internals, input, resources, fonts, text content, or a complete Proto-UI frame.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true proto-ui-module-smoke --summary all
```

The gate builds a modules-enabled Emacs and loads the adapter module in the same
batch process.

On a display-capable host, `proto-ui-frame-fact-smoke` opens Emacs briefly,
observes public frame dimensions and bounded live-window geometry, validates
the JSON fields, and exits:

```sh
zig build -Dproto-ui=true -Dmodules=true proto-ui-frame-fact-smoke --summary all
```

### W9d — Real Emacs facts to EUP/SDL3 snapshot (approved)

Goal: prove the dynamic-module seam can feed actual, public Emacs frame facts
through the existing EUP codec into the SDL3 scene.

Implemented:

1. The display-capable frame-fact smoke writes the observed JSON facts to a
   build artifact.
2. The ERP1 fixture parses those facts and derives a full-frame window, fifteen
   rows, cursor geometry, full damage, and a present hint from the observed
   frame/window dimensions.
3. SDL3 consumes the resulting EUP replay through the same scene validator used
   by the live path.

This is a one-shot snapshot, not continuous redisplay streaming.  Text, faces,
resources, input, recovery, and a real interactive Proto-UI frame remain future
work.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
```

The build log proves that Emacs facts (for example, `1276x1323`) were encoded
into two EUP messages and rendered by SDL3 as one update.

### W9e — Continuous real Emacs public-fact stream (approved)

Goal: replace the one-shot W9d snapshot with repeated observation from a real
Emacs process and render changes in SDL3.

Implemented:

1. `sdl3-emacs-smoke` starts a real batch modules-enabled Emacs child that loads the
   adapter-owned module, selects a live frame, observes public frame facts every
   100 ms, and writes an atomic snapshot artifact.
2. SDL3 polls and validates those facts, preserves the latest version, and
   renders frame/window/row/cursor geometry continuously.
3. The parent guarantees child cleanup when the smoke exits normally, on user
   quit, or after the timeout.

This stream is adapter-owned and public-API-only.  It is not yet EPXL transport,
redisplay-hook streaming, text, faces, resources, or input.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-smoke --summary all
```

The smoke must report multiple observed public-fact snapshots and render them in
a real SDL3 window.

### W9f — Continuous facts validated as EUP snapshots (approved)

Goal: ensure every changed public Emacs fact snapshot crosses the same EUP
`FRAME_UPDATE` validation boundary before SDL rendering.

Implemented:

1. Added `src/proto-ui/facts.zig` as the adapter-owned facts-to-EUP converter.
2. Parsing rejects nonpositive dimensions and window dimensions larger than the
   frame.
3. Each changed snapshot builds a fresh validated scene containing
   `FRAME_CREATE`, one full-frame `WINDOW`, fifteen ordered rows, cursor,
   full-frame damage, and a present hint.
4. SDL3 renders only the latest EUP-validated snapshot and keeps replacement
   bounded to one retained scene.

This is still a public-API observation stream through a snapshot artifact, not
EPXL transport or redisplay-hook streaming.  Text, faces, resources, input, and
recovery remain future work.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-smoke --summary all
```

The smoke must observe multiple snapshots and each changed snapshot must pass
through `Scene.apply`.

### W9g — Authenticated EPXL continuous facts transport (approved)

Goal: move the W9f validated snapshots across the local EPXL transport with an
ephemeral authenticated client and ACK progression.

Implemented:

1. `sdl3-epxl-facts-smoke` creates a per-run `0700` directory, generates an
   ephemeral 256-bit EPXL token, and owns the facts/endpoint/token artifacts.
2. A publisher child loads the adapter-owned module in a real batch Emacs,
   observes public frame facts every 100 ms, and writes each atomic JSON
   snapshot.
3. The publisher authenticates the SDL client over a local Unix socket, converts
   each observed snapshot into a scene-validated contiguous EUP sequence, sends
   `FRAME_CREATE` followed by `FRAME_UPDATE`, and requires an ACK for every
   message.
4. The SDL parent reconnects using the token, validates each received frame
   through `frontend.Scene`, and reports the rendered snapshot count.
5. Cleanup removes the private artifacts and terminates children on normal,
   timeout, and error paths.

This remains public-fact observation over a snapshot artifact.  It does not yet
stream redisplay internals, text, faces, resources, input, or recovery.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-facts-smoke --summary all
```

The smoke must apply multiple EUP updates in SDL3 without printing or retaining
the ephemeral token.

### W9h — Real-fact producer coalescing (approved)

Goal: stop publishing byte-equivalent public-fact snapshots and assign EUP
sequences only to a real state transition.

Implemented:

1. `FrameFacts` has a total equality predicate for adapter-owned coalescing.
2. The Emacs fact loop writes an initial snapshot, changes the selected batch
   frame's public size, then continues observing.
3. The EPXL facts publisher compares each parsed snapshot with the last
   published facts, drops unchanged repeats, and sends only the initial and
   changed snapshots over the existing one-message ACK window.
4. `appendWireSnapshot` remains the sole sequence assignment and scene
   validation boundary, so coalescing cannot introduce gaps or stale frames.

This is producer-side suppression at the public-fact adapter.  General
redisplay coalescing, reconnect/resync, text, faces, resources, and input remain
future work.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-facts-smoke --summary all
```

The smoke must apply exactly two updates: the initial real fact transition and
the changed frame-size transition.  Repeated unchanged facts must not create EUP
frames.
The smoke returns `UnexpectedFactUpdateCount` for any other count.

### W9i — Authenticated EPXL resync reconnect (approved)

Goal: prove that a second authenticated SDL frontend can reconnect to the same
adapter-owned Emacs publisher and receive a coherent scene instead of stale or
partial sequence state.

Implemented:

1. Added the EPXL initial-session recovery profile: the frontend sends
   `RESYNC_REQUEST(1)`, the publisher validates authentication and sends
   `RESYNC_BEGIN(1)`, emits a coherent `FRAME_CREATE` plus `FRAME_UPDATE`, and
   closes with `RESYNC_COMPLETE` at the last coherent sequence.
2. Added `frontend.Scene.resetForResync` so recovery discards old display state
   while preserving the validated scene owner and allocator.
3. The facts publisher now accepts a bounded number of sequential sessions,
   resets its scene for each authenticated resync, assigns sequences from one,
   ACKs every EUP frame, and then continues normal fact streaming on the final
   session.
4. `sdl3-epxl-resync-smoke` connects two SDL frontend sessions to one live
   Emacs publisher, validates both complete snapshots, renders the final scene,
   and cleans up the private token/socket/facts artifacts.

This is an initial-session recovery profile for the bounded facts scene.  It
does not yet detect arbitrary sequence gaps after normal traffic, recover
resources, replay history, or recover a crashed publisher.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke --summary all
```

Both sessions must complete `RESYNC_*` successfully.  The final SDL3 scene must
be coherent and render at least two validated updates; additional cursor-only or
mixed snapshots are allowed under the same contiguous-sequence rules.

### W9j — Public text observation (historical; superseded by `TEXT_LINE_V2`)

This section records the original W9j ASCII bridge. Its `0x8000` and
printable-ASCII claims are historical. The current bounded facts contract is
UTF-8 `TEXT_LINE_V2` at `0x8002`, with explicit window ownership.

Goal: move the first real visible-window text from public Emacs APIs through
EPXL into the SDL3 renderer, while keeping the full glyph/face/font model
adapter-first and explicitly future work.

Implemented:

1. The facts smoke observes visible window text with public
   `window-buffer`, `window-start`, `window-end`, and
   `buffer-substring-no-properties` calls.
2. Historical `facts.parseText` bounds text to 32 lines and 120 columns per
   line and owns decoded line storage.  Current validation accepts bounded
   UTF-8, not only printable ASCII.
3. Historical `appendWireSnapshot` emitted adapter-owned extension section
   `0x8000`.  The current publisher emits `0x8002` records that carry
   `(window_id,row_index)` ownership and are length bounded.
4. `frontend.Scene` decodes text atomically with the rest of `FRAME_UPDATE`,
   validates live window/row mapping, uniqueness, ordering limits, and UTF-8,
   and owns the null-terminated line storage.
5. SDL3 renders each line with its debug text facility at the mapped window and
   row; that debug renderer remains ASCII-only.  The
   EPXL resync smoke fails unless the recovered scene contains the public text
   marker `Emacs Proto-UI`.

This is an observation-first ASCII bridge, not complete Emacs text display.  It
does not yet model tabs, overlays, display properties, BiDi, shaping, faces,
fonts, glyphs, CJK, images, scroll-backed viewport semantics, or redisplay-hook
authoritative rows.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke --summary all
```

The gate must recover, validate, and render real public window text containing
the `Emacs Proto-UI` marker.

### W9k — Bounded ASCII text input bridge (approved)

Goal: carry a bounded, adapter-owned text-input intent from SDL3 through EPXL to
the public Emacs bridge and prove that the next observed text reflects it.

Implemented:

1. Added the facts-profile bounded ASCII `TEXT_INPUT` subset: a `u32` byte length followed by
   printable-ASCII bytes, bounded to the facts-profile text column limit.
2. The SDL frontend sends `TEXT_INPUT` on the same authenticated EPXL session
   with a separate frontend-to-core sequence, requires a transport ACK, and then
   acknowledges the pending core-to-frontend EUP frame.
3. The publisher multiplexes controls and input frames, validates sequence,
   message kind, and ASCII bounds, writes an adapter-owned input artifact, and
   ACKs the input.
4. The smoke Emacs bridge observes that artifact with public file APIs and
   inserts the bounded ASCII text through public `insert`; the next public text
   observation and `FRAME_UPDATE` expose the result to SDL3.
5. `sdl3-epxl-input-smoke` fails unless the final scene contains
   `XEmacs Proto-UI`.

This is an observation-first text-input bridge, not Emacs command execution or
keymap compatibility.  Keyboard modifiers, commands, macros, themes, CJK/IME,
arbitrary buffers, point/region editing, and redisplay-owned cursors remain
future work.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke --summary all
```

The final scene must contain the applied input marker.

### W8g — Negotiated bounded Unicode text input (approved)

Goal: extend `TEXT_INPUT` from printable ASCII to bounded UTF-8 without
changing the wire shape, while ASCII-only peers continue to negotiate and run.

Implemented:

1. `TEXT_INPUT` remains `u32 byte_length` plus bytes, but accepts 1..120 valid
   UTF-8 bytes with no NUL or C0 controls. Encoders and decoders reject empty,
   oversized, malformed, NUL-bearing, and trailing-byte payloads.
2. SDL `translateText` and the fixed input queue validate the same bounded
   UTF-8 rule. Delivery is capability-aware: ASCII needs the effective
   `input.text_ascii`/Unicode superset; non-ASCII requires effective
   `input.text_unicode`. Rejected non-ASCII input does not enter the queue.
3. `input.text_unicode` is optional, negotiable, degraded, and evidenced by
   `sdl3-epxl-unicode-input-smoke`; `input.text_ascii` remains retained.
4. The publisher artifact encodes text as ASCII base64 and Emacs decodes it
   explicitly as UTF-8 before public `insert`; fact/ack writes explicitly use
   UTF-8. This avoids raw-text coding prompts and file recoding corruption.
5. Public facts and EUP text lines accept bounded UTF-8 scene text. The smoke
   asserts the scene contains `你好Emacs Proto-UI`, but the bitmap renderer
   intentionally skips non-ASCII draw text; no shaping or CJK font parity is
   claimed.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke --summary all
```

This is adapter/protocol frontend behavior. It does not enable `output_proto`,
register a runtime terminal, or implement IME, shaping, fonts, or keymaps.

### W8h — Bounded full key event v2 transport (approved)

Goal: extend the existing 4-byte `KEY_EVENT` profile with a backward-compatible,
strictly bounded full-key intent without claiming keymap or command parity.

Implemented:

1. The original facts-profile `KEY_EVENT` codec is unchanged. Within the same
   `0x0600` message, `u16 action=0` followed by `u16 schema=2` is the v2
   discriminator; legacy receivers reject it, while peers that negotiate
   `input.key_full_v2` accept it.
2. Key v2 is variable length with little-endian fields: state, a ten-bit EUP
   modifier bitset, nonzero physical key, repeat count, local device/layout
   identifiers, and bounded UTF-8 logical-key and text strings. Exact length,
   unknown bits, invalid states/repeats, NUL, malformed UTF-8, nonzero layout,
   and trailing bytes fail without queue mutation.
3. SDL down/up/repeat translation preserves scancode and folds left/right
   platform modifiers into EUP bits. Printable unmodified key presses defer to
   `TEXT_INPUT`. Delivery remains one-in-flight and is gated by negotiated
   `input.key_full_v2`; ASCII-only peers retain `input.key_bounded`.
4. EPXL artifacts carry canonical JSON with base64 logical-key/text fields.
   The Emacs-owned adapter acknowledges every observed event and executes only
   the explicit C-a/C-e subset for this smoke. It does not evaluate Elisp from
   the frontend or expose general command/keymap execution.
5. `input.key_full_v2` is optional, negotiable, and degraded with evidence from
   `sdl3-epxl-key-v2-smoke`. The smoke executes C-a/C-e and observes an
   unhandled F5 ACK without claiming full Emacs key compatibility.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-key-v2-smoke --summary all
```

### W9n — Backward-compatible pointer event v2 transport (approved)

Goal: extend the existing bounded `POINTER_EVENT` profile with strict,
negotiated pointer state while preserving the legacy codec and without
claiming selection semantics or full Emacs mouse parity.

Implemented:

1. The original 14-byte facts-profile pointer codec is unchanged. Within
   `POINTER_EVENT`, the v2 marker is `phase=0`, `reserved=0`, and `schema=2`.
   V2 is exactly 30 bytes and carries motion/press/release/cancel/drag, a
   five-bit button mask, click count, bounded coordinates, and the EUP key
   modifier bitset.
2. Press/release accept exactly one left/middle/right button and clicks 1..8.
   Motion is empty-mask hover; drag requires the active mask. Cancel is empty.
   Unknown enum, button, modifier, coordinate, reserved, and trailing-byte
   values fail without queue mutation.
3. The delivery journal stores the active v2 button mask and click count. It
   rejects lossy drag/release state, preserves one-in-flight EPXL ordering,
   and keeps v2 events capability-gated. Legacy bounded peers continue using
   `input.pointer_bounded`.
4. SDL3 motion and buttons 1..5 translate to v2. Motion state maps directly to
   hover/drag masks, button indexes map to left/middle/right/X1/X2, SDL clicks
   are preserved, and current platform modifiers fold to EUP bits.
5. `input.pointer_v2` is optional, negotiable, degraded, and evidenced by
   `sdl3-pointer-v2-smoke`. The synthetic smoke receives seven deterministic
   intents: modified left press/drag/release, two middle events, and two right
   events. These are transport intents only; no selection or full mouse parity
   is claimed.

Acceptance:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-pointer-v2-smoke --summary all
```

### W9o — Bounded left-drag selection (approved)

Goal: prove one negotiated Pointer Event v2 semantic without extending the
protocol or claiming full mouse parity.

1. Add optional, negotiable, degraded `input.pointer_selection_left`, evidenced
   by `sdl3-pointer-selection-smoke`; it requires `input.pointer_v2`.
2. Reuse the v2 codec, capability negotiation, delivery journal, one-in-flight
   EPXL ACK flow, public facts path, and clipboard artifact. Add no record.
3. In the real-Emacs smoke, translate deterministic SDL left press, drag, and
   release through the existing v2 path. Press uses public `posn-at-x-y` to set
   an active mark; drag moves point; release moves point.
4. On release, the adapter executes only the bounded selection: at most 120
   printable-ASCII characters from the active region are copied with
   `kill-ring-save` to the existing clipboard artifact. The smoke fails unless
   release is ACKed and the exact first-line substring `Emacs` arrives.
5. Other buttons/phases remain observed/no-execution. Right-click menus,
   middle-click PRIMARY paste, touch/pen, multi-window hit testing, overlays,
   and variable-pitch hit testing remain out of scope.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-selection-smoke --summary all
```

### W9p — Bounded middle-click paste (approved)

Goal: add the smallest next Pointer Event v2 semantic without a protocol record
or a claim of generic mouse / X11 selection parity.

1. Add optional, negotiable, degraded `input.pointer_middle_paste`, evidenced by
   `sdl3-pointer-middle-paste-smoke`; it requires both `input.pointer_v2` and
   `input.pointer_selection_left`.
2. Reuse the v2 codec, W9o left-selection execution, delivery journal, EPXL ACK
   flow, public facts path, clipboard artifact, and capability machinery. Add no
   wire record.
3. The real-Emacs gate first runs the deterministic W9o left press/drag/release
   subset. Only after that selection succeeds and copies `Emacs`, it sends a
   deterministic zero-modifier middle press/release with clicks 1 at the release
   point.
4. Only an ACKed middle release (`buttons=2`, `clicks=1`, no modifiers) after the
   successful bounded prior selection may map public `posn-at-x-y` /
   `posn-point` and execute public `yank`. Other chords, clicks, phases, buttons,
   touch/pen forms, or paste without prior selection are rejected or no-op.
5. The gate fails unless left release precedes middle release and the first
   scene line is exactly `EmacsEmacs Proto-UI`. No X11 PRIMARY, generic mouse
   yank, multi-window hit testing, overlays, variable-pitch hit testing, or full
   mouse behavior is claimed.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-middle-paste-smoke --summary all
```

### W9l — Public point and dynamic cursor (approved)

Goal: replace the fixed facts-profile cursor with public Emacs point observation
so an applied input changes both text and the rendered cursor.

Implemented:

1. The smoke bridge observes the selected window's point through public
   `window-point`, `line-number-at-pos`, and `current-column` APIs, then writes
   it as the `cursor` field of one atomically written combined snapshot JSON
   that also carries frame facts and text lines.
2. `CursorFacts` accepts a 1-based line and zero-based column, bounded to the
   facts-profile text viewport and column width.
3. `Snapshot` equality includes cursor movement, so cursor-only changes are not
   coalesced away.
4. `appendWireSnapshot` maps the observed point onto an existing row and emits a
   normal EUP cursor record using the profile's 8-pixel debug-text advance.  The
   full cursor rectangle, including its 2-pixel width, must fit the window.
5. The input smoke now requires `XEmacs Proto-UI`, cursor column 1, and cursor
   row 0 after the bounded input intent is applied.

This observes public point state for the simple facts viewport.  It is not
redisplay-owned cursor semantics and does not model region, mark, overlays,
multi-frame cursors, blinking, cursor faces, vertical motion limits, variable
pitch text, or bidirectional movement.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke --summary all
```

The gate must apply the bounded input and verify that both text and cursor reflect
the new public point.

### W9m — Bounded editing intents (approved)

Goal: extend the facts-profile input bridge beyond text insertion with a small,
explicit set of non-text editing intents while keeping keymap compatibility out
of scope.

Tasks:

1. Add a bounded `KEY_EVENT` facts-profile codec for pressed, unmodified
   `backspace`.
2. Use a separate frontend-to-core sequence, require transport ACK, and preserve
   the existing one-message EUP ACK window.
3. Replace the raw input artifact with a two-line adapter-owned action record:
   `text` plus printable-ASCII payload, or `key` plus `backspace`.
4. In the smoke bridge, apply text with public `insert` and backspace with public
   `delete-char`; synchronize public window point after each action.
5. Add an edit smoke that applies backspace and verifies the resulting public
   text and cursor.

Implemented profile: the action artifact is an explicit two-line record —
`text` plus printable-ASCII payload, or `key` plus `backspace` — and the bridge
deletes the artifact after consuming it. The smoke seeds a trailing `Z`, deletes
it, and verifies the final public text is `Emacs Proto-UI` with cursor at line
2, column 18. EUP cursor geometry remains logical pixels; the facts producer
uses the established 8-pixel column advance. This profile is not full editing
or keymap protocol support.

Deliberate exclusions: modifiers, repeats, commands, keymaps, macros, region and
mark, undo, kill/yank, CJK/IME, and redisplay-owned cursor semantics.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
```

#### W9m-b — Bounded focus/window event observation (approved)

Goal: observe platform focus and window-manager requests without adding an
inherited Emacs core integration or allowing the frontend to mutate Emacs.

Tasks:

1. Define strict fixed schemas for assigned `FOCUS_EVENT=0x0606` and
   `WINDOW_REQUEST=0x0607`.
2. Map SDL focus gained/lost and close/resize/move/minimize/maximize/restore
   events to bounded protocol intents.
3. Gate queue insertion and EPXL delivery on optional
   `platform.focus_window_events`.
4. Preserve one-in-flight EPXL ordering with existing reverse input.
5. Add a synthetic SDL smoke for focus gained, resize, and close ordering.

Implemented limits: this is observation/request transport only. The smoke does
not destroy Emacs for a synthetic close request. No terminal registration,
`output_proto`, host contract, fullscreen event mapping, window-manager
execution, inherited C/Lisp bridge, or full desktop parity is enabled.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-focus-window-smoke
```

### W10 — GPU renderer path

Goal: add optional acceleration without making it required.

#### W10a — Renderer negotiation and present selection (approved)

Goal: make SDL renderer selection explicit, observable, and safe on hosts with
no GPU while allowing an operator to request GPU or a named SDL driver.

Tasks:

1. Add a pure renderer selection policy (`auto`, `software`, `gpu`, or a named
   SDL driver).
2. Classify the actual SDL renderer into Tier 0 software, Tier 1 GPU basic, or
   Tier 2 GPU advanced.
3. Request explicit GPU fallback: if the `gpu` driver is unavailable, create the
   software renderer instead of failing the frontend.
4. Parse and apply `off`, `on`, and `adaptive` present-mode requests.
5. Report the actual renderer name, negotiated tier, and requested present mode
   in smoke diagnostics.
6. Add a renderer smoke gate that requests GPU, accepts software fallback on a
   GPU-less host, and renders the same EUP replay scene.

Boundary: the policy is in the adapter-owned `src/proto-ui/renderer.zig`; only
the SDL frontend binds it to SDL renderer APIs. No inherited Emacs C/Lisp file
changes.

Status: approved. A dedicated reviewer completed three passes before commit. The
GPU draw abstraction, glyph atlas, image texture cache, blend/scissor draw graph,
rectangle damage, and GPU counters remain future W10 work.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-input-translate-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
```

Review: the dedicated reviewer completed correctness, protocol/build/integration,
and boundary/docs/status passes. It verified renderer lifetime, explicit
fallback, wall-clock smoke timeouts, default-build isolation, changed-path
audits, negative inherited-C rejection, and conservative capability reporting.

#### W10b-a — Change-aware present and frontend counters (approved)

Goal: stop presenting unchanged frames, retain correctness on scene updates,
events, and resize, and collect the first frontend performance evidence.

Tasks:

1. Add an adapter-owned `FrameGate` for dirty/resize-aware presentation.
2. Add `FrameCounters` for presented frames, skipped polls, total/last
   full-frame path nanoseconds, and the last monotonic presentation timestamp.
3. Route replay and continuous-facts presentation through the gate.
4. Mark the frame dirty for scene replacement and platform events; resize also
   compares the SDL window geometry.
5. Extend replay and continuous-facts smoke diagnostics with the counters.
6. Add unit tests for unchanged, dirty, resized, skipped, and presented frames.

Implemented limits: this is full-frame change-aware presentation, not partial
rectangle damage; it does not yet expose GPU submit timestamps, atlas statistics,
texture uploads, or a software/GPU draw graph.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes. It verified gate invalidation, resize and event
handling, overflow-safe SDL timing, counter semantics, default-build isolation,
changed-path audits, negative inherited-C rejection, and conservative
capability reporting.

#### W10b-b1 — Renderer-agnostic SDL draw list (approved)

Goal: separate scene-to-draw translation from SDL execution so the same logical
commands can be submitted by software or GPU-backed SDL renderers, and so later
atlas/damage optimizations operate on an explicit command graph rather than
direct frontend calls.

Tasks:

1. Add adapter-owned `DrawList`, `DrawCommand`, `LogicalRect`, `Color`, and
   `DrawStats`.
2. Model clear, filled rectangle, and bounded printable debug-text commands.
3. Reuse command storage between presented frames and reset statistics without
   freeing capacity.
4. Keep text slices borrowed by the command list; scene text remains owned by
   the scene and the list executes before scene mutation.
5. Translate replay and continuous-facts scenes into draw lists.
6. Execute the same list through SDL software and GPU-backed renderers.
7. Record clear/fill/text command totals in `FrameCounters`.
8. Add tests for command ordering, reset behavior, counters, and text bounds.

Implemented limits: this is an explicit SDL Renderer command path, not a native
Vulkan/Metal/D3D12 backend. Text remains `SDL_RenderDebugText`; the command list
does not yet implement glyph runs, atlas eviction, image textures, scissor
clipping, blend modes, or rectangle damage.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes, then approved the clear-counter fix. It verified
draw-list ownership and reset capacity, borrowed-text safety, software/GPU
execution, counter accumulation, default-build isolation, changed-path audits,
negative inherited-C rejection, and conservative deferred-scope reporting.

#### W10b-b2a — Bounded glyph-atlas policy (approved)

Goal: establish deterministic atlas placement/replacement state and counters
before allocating backend textures or rendering glyph runs.

Tasks:

1. Add adapter-owned `GlyphKey`, `GlyphRect`, `GlyphAtlasEntry`, and
   `GlyphAtlas`.
2. Reject zero atlas capacity and zero-width/height glyph rectangles.
3. Use generation-based LRU replacement and expose hit/miss/insert/update/evict
   counters.
4. Cover lookup, insertion, update, eviction, and counter behavior with tests.

Implemented limits: this is atlas state policy only. It does not rasterize glyphs,
allocate SDL/GPU textures, upload pixels, process glyph-run resources, or claim
Tier 1/2 performance.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes, then approved fixes for monotonic generation on
fresh insertion, LRU eviction coverage, in-place update testing, and a duplicated
W11 heading. Final checks verified exact key identity, bounded capacity and rect
validation, counters, default isolation, changed-path audits, negative
inherited-C rejection, and conservative non-texture scope.

#### W10c-a — Damage classification baseline (approved)

Goal: add a conservative frontend damage classifier so unchanged scene states
are never re-presented and cursor/viewport changes are measured separately
before introducing clipped rendering.

1. Add `DamageKind`, `DamageDecision`, and `SceneDamageObservation`.
2. Extend `FrameGate` with the previous viewport start/count, complete
   rendered cursor presence/state, and a SHA-256 text signature plus line
   count.
3. Classify each scene observation as initial, unchanged, cursor-only, or
   conservative viewport damage; text-only changes are conservatively treated
   as viewport damage, and only non-none observations mark the frame dirty.
4. Record initial, cursor, viewport, and unchanged counts in `FrameCounters`.
5. Integrate classification with the real SDL EPXL interactive loop so
   repeated unchanged heartbeats do not rebuild or present the draw list.

Implemented limits: this is a conservative classification and gating baseline,
not clipped rendering. Cursor changes still use full-frame work, viewport
changes use conservative full-frame work, and no SDL clip rectangle, dirty
texture upload, GPU timestamps, or partial present is implemented.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-wheel-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes added a conservative SHA-256 text signature, complete optional cursor observation, frame-update-only observation, damage counters, and diagnostics documentation. Final checks verified unchanged-frame skipping, cursor/viewport classification, interactive and EPXL regressions, boundary and inherited-C audits, and the full built-in check run.

#### W10c-b — Cursor-only clipped redraw (approved)

Goal: use the W10c-a cursor-only classification to avoid a full-frame clear and
redraw when only the rendered cursor changes.

1. Retain the complete old and new cursor observations in `DamageDecision`.
2. Build a conservative logical clip rectangle that is the union of the old and
   new cursor rectangles plus one logical-pixel margin.
3. Classify all rendered scene inputs: viewport facts, text bytes/count,
   cursor state, frame/window/row geometry, and structure object count. Do not
   let non-render metadata such as update timestamps force a redraw.
4. Keep the prior rendered frame in a sized, primed, adapter-owned offscreen
   SDL target. Resize, render-target reset, or device loss discards it. Full
   frames rebuild that target, compose it to the window, and present. Never
   assume the window backbuffer survives present.
5. Fall back to full-frame rendering when either cursor endpoint is absent, the
   cursor changes window, the retained target is unavailable or unprimed, the
   logical dimensions exceed exact frontend coordinate representation, or the
   clipped device rectangle is empty.
6. In cursor-clipped mode, redraw the retained draw list inside the old/new
   cursor union without `SDL_RenderClear`. The explicit opaque full-frame
   background fill is still submitted and restores every pixel in the union
   before row/text/cursor commands; then compose and present the retained
   target.
7. Track cursor-clipped frames, full-fallback frames, and the actual submitted
   command count so clipped execution remains observable.

Implemented limits: this optimization applies only to cursor-only changes.
Text-only, viewport, resize, initial, and clipped-unable changes retain
conservative full-frame rendering. The implementation does not yet claim
partial GPU compositing, dirty texture uploads, GPU timestamps, or general
rectangle damage.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/runtime, and boundary/docs/status passes; approved fixes added sized/primed retained-target lifecycle handling, render-reset invalidation, exact cursor geometry and clip bounds, explicit background restoration, and accurate submitted-command counters.

#### W10c-c — Bounded text-region clipping (approved)

Goal: extend retained-frame damage work from cursor-only changes to bounded
ASCII text changes without turning every typed character into a full-frame
redraw.

1. Preserve up to 32 per-line observations: row index, bounded text hash, and
   a conservative absolute rendered-line rectangle that unions the full row
   rectangle with the actual 8x8 debug-text bounds.
2. Classify unchanged, cursor-only, bounded text-only, mixed text/cursor
   region, conservative viewport, and initial damage.
3. Build a conservative logical clip from every changed old/new line rectangle
   and both cursor endpoints. Add a one-logical-pixel margin.
4. Fall back to full-frame rendering when lines exceed the bounded profile, a
   row/owner mapping is missing, observations are incomplete, geometry is not
   exactly representable by the current frontend path, or no nonempty clip
   remains.
5. Reuse the sized and primed offscreen target. Clipped execution still submits
   the explicit opaque full-frame background fill; SDL restricts it to the clip
   before redrawing rows, text, and the cursor.
6. Report text and region damage, clipped/fallback frames, and submitted clip
   command totals.

Implemented limits: this is a frontend facts-profile optimization for bounded
ASCII line observations. It does not implement EUP resource-level damage,
partial present, dirty texture upload, general rectangle damage, or GPU
timestamps.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build check
```

Status: approved. The dedicated reviewer completed correctness, integration/runtime, and boundary/docs/status passes; approved fixes added renderer-matching row indexing, conservative row plus 8x8 debug-text damage bounds, checked text geometry, actual executed draw-stat accounting, bounded retry of torn apply-ACK artifacts, and complete diagnostics.

#### W10d — Bounded `GLYPH_RUN` debug fallback (approved)

Goal: add a strict diagnostic render-message path without allowing it to imply
redisplay ownership or production text compatibility.

1. Assign the explicit EUP `GLYPH_RUN = 0x0405` v1 schema: an exact 60-byte
   little-endian header plus 1..120 printable-ASCII bytes.
2. Validate schema, debug-fallback flag, visual-LTR diagnostic direction,
   zero reserved data, nonzero run/frame/window identities, zero face/font
   references, nonnegative geometry, row ownership, active frame generation,
   frame bounds, and exact payload length.
3. Retain at most 64 owned text runs in the frontend Scene. Replace by
   `run_id` only with a strictly newer generation; reject stale/equal input
   before mutation and without sequence advance. Free all runs on authoritative
   frame update, frame deletion, resync, clear, and deinit.
4. Negotiate optional, degraded `render.glyph_run_debug_v1`; keep
   `redisplay.glyph_rows` pending and R7 runtime fail-closed unchanged.
5. Render accepted runs through the existing ASCII debug-text draw-list path.
   Add `--glyph-run-smoke` and `sdl3-glyph-run-smoke` with one active frame,
   one window/row, scene/draw assertions, and automatic close.
6. Extend deterministic protocol fuzzing with malformed-text, trailing-byte,
   valid, and newer-generation-replacement seeds.

Non-goals: this slice is not redisplay-owned, shaped text, BiDi reordering,
faces, fonts, glyph atlas/images/widgets, Emacs capture, or `output_proto`.

Acceptance:

```sh
zig fmt --check src/proto-ui/frontend.zig src/proto-ui/protocol.zig src/proto-ui/fuzz.zig src/proto-ui/capability.zig tools/proto-ui-sdl3/main.zig build.zig
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-glyph-run-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke --summary all
```

Status: approved. Three completed review rounds covered codec/security, Scene
and renderer integration, and boundary/docs/status. No inherited Emacs C, H, or
Lisp source changed.

#### W10e — Real-frame public-facts glyph marker (approved)

Goal: prove that the existing real PGTK frame lifecycle smoke can render its
public-facts marker through the bounded W10d debug fallback without claiming a
display backend or redisplay pipeline.

1. After `FRAME_CREATE` and `FRAME_UPDATE`, derive one `GLYPH_RUN` for the exact
   public-facts line `Emacs Proto-UI` from the frontend scene's actual
   window/row geometry. Use the same text origin used by the debug draw list,
   assign sequence 7, and move `FRAME_DESTROY` to sequence 8 in producer and
   frontend scenes.
2. Render before sending the real-frame delete request. Assert one active run
   with exact text and valid owner-relative geometry, while preserving
   contiguous scene sequencing and failure-safe real-frame deletion.
3. Suppress legacy facts text only for a row/window with an active glyph run.
   Scenes without glyph runs retain the existing facts renderer unchanged.
4. Keep `sdl3-frame-smoke` as the acceptance gate.

Non-goals: this is not redisplay-owned capture, shaped text, BiDi, faces,
fonts, production glyph rendering, atlas/images/widgets, real `output_proto`
registration, or R7 bypass. Text remains a public Emacs fact.

Acceptance:

```sh
zig fmt --check tools/proto-ui-sdl3/main.zig
git diff --check
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-glyph-run-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
```

Status: approved. Three completed review rounds covered lifecycle/order,
renderer/regression, and boundary/docs/status. No inherited Emacs C, H, or Lisp
source changed.

#### W10f — Explicit bounded glyph-run delete (approved)

Goal: make the diagnostic fallback's temporary text replacement explicit and
reversible without claiming redisplay ownership.

1. Implement `GLYPH_RUN_DELETE = 0x0406` as an exact 24-byte little-endian
   identity payload (`run_id`, `generation`, `window_id`, `row_index`, and zero
   reserved bytes).
2. Require active-frame ownership and matching window/row context.  Accept only
   an exact four-field identity match; reject missing, mismatched, stale,
   malformed, and reserved input before mutation and without sequence advance.
3. On success, free the run's owned text, remove exactly that run, advance the
   sequence, and restore legacy facts text rendering for that row.
4. Extend `sdl3-glyph-run-smoke` with mismatch rejection, exact deletion, zero
   active runs, and facts fallback.  Move the real-frame lifecycle delete to
   sequence 8 and `FRAME_DESTROY` to sequence 9 with sequence 10 asserted.
5. Add deterministic codec/Scene tests and a bounded `glyph_run_delete_v1` fuzz
   target.

Non-goals: this remains bounded diagnostic ASCII fallback, not redisplay
ownership, shaped text, BiDi, faces, fonts, glyph atlas/images/widgets,
production glyph rendering, Emacs capture, `output_proto`, or an R7 bypass.

Acceptance:

```sh
zig fmt --check src/proto-ui/protocol.zig src/proto-ui/frontend.zig src/proto-ui/fuzz.zig tools/proto-ui-sdl3/main.zig
git diff --check
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-glyph-run-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke --summary all
```

Status: approved. Three completed review rounds covered codec/security, Scene
and lifecycle, and renderer/docs/boundary. No inherited Emacs C, H, or Lisp
source changed.

### W11 — Desktop integration

Goal: cover clipboard, IME, widgets, and platform state.

Tasks:

1. Implement clipboard text.
2. Implement PRIMARY/CLIPBOARD selection ownership.
3. Implement IME attach/preedit/commit.
4. Implement menu model rendering and result.
5. Implement dialog model and result.
6. Implement tooltip model.
7. Implement scrollbar interaction.
8. Implement tool-bar/tab-bar model or glyph fallback.
9. Implement monitor/DPI/theme events.

Acceptance:

1. Copy/paste text works.
2. CJK IME composition works.
3. Menu selection invokes the correct Emacs action.
4. Dialog result reaches Lisp.
5. Scrollbar drag scrolls the correct window.
6. Missing platform capability has explicit fallback.

Review gates:

1. Semantic ownership remains in Emacs.
2. Platform bridge safety.
3. Capability fallback correctness.

#### W11a — Bounded clipboard paste (approved)

Goal: provide a first desktop clipboard path without exposing unbounded or
non-ASCII payload data through the facts-profile bridge.

Tasks:

1. Add an adapter-owned Ctrl+V paste-shortcut policy that rejects release,
   repeat, missing Ctrl, extra modifiers, and non-V keys.
2. Capture SDL clipboard text through SDL3 and reuse the bounded printable-ASCII
   `TEXT_INPUT` validation and queue.
3. Free SDL-owned clipboard memory on every return path.
4. Add `sdl3-clipboard-smoke` to set, read, translate, and queue a bounded
   clipboard payload.
5. Wire Ctrl+V in the persistent interactive bridge so accepted clipboard text
   follows the existing ordered action/apply-ACK flow.

Implemented limits: only printable ASCII up to 120 bytes is accepted. Unicode,
rich text, multiple MIME offers, selection ownership, clipboard ownership
events, and native Emacs clipboard objects remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-clipboard-smoke
```

Review: the dedicated reviewer completed correctness, integration/build, and
boundary/docs/status passes, then approved fixes for explicit NULL clipboard
handling, coherent local action parsing, and a duplicate status row. Final checks
verified SDL memory ownership, text bounds and queue behavior, clipboard and
input smokes, interactive regression, changed-path audits, negative inherited-C
rejection, and explicit deferred clipboard scope.

#### W11b — Bounded clipboard copy (approved)

Goal: add the first Emacs-to-SDL clipboard direction while retaining the same
bounded desktop-integration scope as W11a.

1. Recognize pressed, non-repeat Ctrl+C as a frontend copy shortcut without
   claiming the full Emacs keymap.
2. Assign copy action code 6 while preserving the existing backspace action
   code 1 for backward compatibility.
3. In the opt-in interactive smoke, copy the deterministic first line from the
   public Emacs buffer through `kill-ring-save`.
4. Publish that text through an atomic clipboard artifact and have SDL3 read it
   into the platform clipboard only when it is non-empty, printable ASCII, and
   at most 120 bytes.
5. Require the copy smoke to observe the exact `Emacs Proto-UI` payload before
   reporting success.

The implementation remains in the SDL3 frontend, Proto-UI input codec, and
build steps; no inherited GNU Emacs C/Lisp files change. Unicode, rich text,
multiple MIME offers, selection ownership, clipboard ownership events, external
clipboard targets, and full kill-ring semantics remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-clipboard-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-copy-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build,
and boundary/docs/status passes; approved fixes added explicit copy action codec
coverage and preserved the existing backspace action ID. Final checks verified
copy/interactive smokes, changed-path and negative inherited-C audits, and the
full built-in check run.

#### W11c — Bounded Unicode clipboard text (approved)

Goal: extend the existing 120-byte, one-line clipboard bridge from printable
ASCII to strict UTF-8 while keeping capability fallback explicit.

1. Validate clipboard text as strict UTF-8, 1..120 bytes, with no NUL or C0
   control byte; newline remains rejected. ASCII compatibility is unchanged.
2. Add optional, negotiable `clipboard.text_unicode`. ASCII-only peers retain
   `clipboard.ascii_bounded`; non-ASCII paste without Unicode negotiation fails
   before the delivery queue changes.
3. Gate Unicode copy on the effective capability. The Emacs-owned adapter
   explicitly encodes UTF-8, publishes an ASCII-safe `base64:` artifact, and
   SDL decodes and validates exact bytes before installing platform clipboard
   text.
4. Add the opt-in real-process smoke `sdl3-clipboard-unicode-smoke` for CJK
   paste plus marker-text observation and exact `Emacs 你好` copy round trip.

This is a bounded plain-text bridge only. It does not claim shaped rendering,
font parity, rich text, MIME types, selection ownership, clipboard-manager
integration, or full Emacs clipboard parity.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-clipboard-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-clipboard-unicode-smoke
```

### W12 — Complete EUP feature surface

Goal: close PGTK parity gaps.

#### W12a — EPXL capability/status manifest (approved)

Goal: make the local EPXL feature scope explicit and machine-checkable before
expanding the EUP feature surface.

1. Define adapter-owned bounded capability descriptors with stable EUP names,
   required flags, negotiable flags, implementation status, and evidence gate.
2. Encode and decode standard EUP name/value capability payloads.
3. Exchange backend capabilities, frontend capabilities, effective capabilities,
   and a SHA-256 effective-set hash using `CAPABILITIES`,
   `CAPABILITIES_ACK`, `SESSION_READY`, and `READY_ACK`.
4. Reject missing required profile features, malformed known values, sequence
   or ACK mismatch, and effective-set hash mismatch. Ignore unknown optional
   names as required by EUP.
5. Generate `zig-out/proto-ui/status_manifest.json` from the same
   source-authoritative descriptors used by negotiation.
6. Wire replay, facts, and interactive EPXL sessions to the same exchange.

Implemented limits: this negotiates only the bounded EPXL profile. Resources,
widgets, frame lifecycle, redisplay glyph rows, arbitrary capability changes,
and full EUP feature coverage remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-facts-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/runtime, and boundary/docs/status passes; approved fixes added exact envelope-context validation, reserved monotonic session sequences, capability-gated clipboard/input/damage/renderer behavior, source-authoritative JSON manifest generation, and precise docs for reconnect sequence handling.

#### W12b — Frame lifecycle/resource generation contract (approved)

Goal: give bounded EPXL frames and future resources deterministic identity,
generation, teardown, and atomic commit semantics before transporting faces,
fonts, images, or redisplay-owned rows.

1. Add an adapter-owned frame registry with create, active-update, destroy,
   non-recycled identity, and bounded table behavior.
2. Add an adapter-owned resource registry covering face, font, image,
   fringe-bitmap, icon, and string identities with live/deleted state.
3. Require strictly newer generations for redeclaring a resource kind/id.
4. Validate complete `FRAME_UPDATE.resources` declaration sets before committing
   them atomically with visual state; stale declarations reject the update.
5. Implement `FRAME_DESTROY` in the frontend, validate envelope/payload frame
   identity and generation, release bounded visual state, and reject later
   updates for the destroyed generation.
6. Keep payload delivery, snapshots, eviction, and missing-resource requests
   out of scope until the full resource model lands.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build check
```

Status: approved. The dedicated reviewer completed correctness, integration/runtime, and boundary/docs/status passes; approved fixes added non-recycled single-active-frame enforcement, initial-generation checks, resource capacity preflight, duplicate/non-live declaration rejection, exact frame destroy cleanup, and precise bounded-status documentation.

#### W12c — Real-frame lifecycle bridge smoke (approved)

Goal: prove that one real display-backed Emacs frame and one EUP/SDL3 frame can
be created, updated, and destroyed in a deterministic order without modifying
inherited Emacs C/Lisp.

1. Start an isolated foreground Emacs daemon with a private 0700 runtime
   directory and socket; never attach to a user daemon.
2. Load the adapter-owned dynamic module and run a bounded daemon readiness
   ping.
3. Create one visible PGTK frame with `make-frame-on-display` from an
   `emacsclient -e` lifecycle program.
4. Require live/visible state and three consecutive equal pixel-geometry
   samples, 150 ms apart, within an eight-second settle deadline.
5. Observe bounded public frame/window/text/cursor/viewport facts atomically.
6. Encode EUP sequences 5 (`FRAME_CREATE`) and 6 (`FRAME_UPDATE`) with a
   producer scene; apply them to a separate frontend scene; render created and
   active SDL3 states.
7. Consume an atomic private delete marker, call `delete-frame` on the retained
   frame, publish the atomic deleted marker, apply EUP sequence 7
   (`FRAME_DESTROY`), and present the explicit cleared destroyed state.
8. Stop and reap the daemon/client, release renderer and scene allocations, and
   remove the private runtime directory on success and failure.

Implemented limits: this is a process/public-API lifecycle bridge, not
`output_proto` terminal integration.  It does not create a `window-system .
proto` frame, own redisplay rows, transport resources, support multiple EUP
frames, or provide full input/focus/visibility events.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-live-smoke
```

Status: approved. The dedicated reviewer completed geometry correctness,
lifecycle/producer-frontend sequence separation, cleanup/error handling, and
regression/build passes; approved fixes added bounded geometry settling and
separated producer and frontend scene sequence state. Local Linux validation
covered 89/89 adapter unit tests, three successful frame-smoke runs before the
final cleanup pass, the post-cleanup frame smoke, live smoke, and the built-in
check before cleanup.

#### W12d — Frame visibility/focus state contract (approved)

Goal: define strict core-to-frontend state transitions for visibility and
focus before an `output_proto` runtime seam can own real Emacs frame state.

1. Implement EUP `FRAME_VISIBILITY` (`0x0208`) with `hidden=0`, `visible=1`,
   and `iconified=2`.
2. Implement EUP `FRAME_FOCUS` (`0x0210`) with a strict Boolean focus byte.
3. Use exact 12-byte little-endian payloads: frame ID, frame generation, state
   byte, and three reserved zero bytes.
4. Reject zero identity/generation values, envelope/payload frame mismatch,
   invalid state bytes, and nonzero reserved bytes.
5. Store visibility and focus with the adapter-owned active-frame generation.
   New frames start visible and unfocused; hiding or iconifying clears focus.
6. Permit focus only on a visible frame; permit unfocus in any visibility
   state; reject stale, destroyed, or non-active state changes.
7. Apply both messages in `frontend.Scene`, count them as control messages,
   and preserve sequence continuity when validation fails.

Implemented limits: this is a strict protocol/lifecycle contract and frontend
scene state only.  It does not transport a real SDL platform-focus event into
Emacs, create an `output_proto` frame, or observe Emacs visibility changes.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
```

Status: approved. The dedicated reviewer completed protocol, lifecycle/state,
and regression/boundary passes; approved fixes added allocator-consistent codec
tests and complete malformed/reserved-byte coverage. Local validation passed
92/92 adapter unit tests, the boundary audit, and the W12c frame smoke.

#### W12e — Resource payload/eviction contract (approved)

Goal: establish deterministic bounded payload retention and strict
request/eviction wire forms before transporting real faces, fonts, images, or
glyph atlas pages.

1. Add `ResourcePayloadStore` over existing resource kind/id/generation
   identity with fixed limits of 32 entries, 4096 bytes per payload, and
   16384 total payload bytes.
2. Own payload bytes in the adapter, refresh LRU order on successful lookup,
   and expose hit/miss/insert/update/eviction counters and byte totals.
3. Require strictly newer generations for replacing an existing key; reject
   empty, oversized, stale, equal, or zero-identity payloads without mutation.
4. Evict least-recently-used entries only until a valid insert fits; never
   evict the key being replaced. OOM allocation must occur before mutation.
5. Define `RESOURCE_REQUEST` as a u32 count plus at most 64 unique 12-byte
   records (`kind`, reserved u24, resource ID, generation where zero means
   latest).
6. Define `RESOURCE_EVICT` as one 16-byte record containing kind, reserved
   u24, ID, generation, reason (`lru`, `capacity`, `generation`, or
   `explicit`), and reserved u24.
7. Reject malformed kinds, duplicate requests, nonzero reserved bytes, invalid
   reasons, truncated/oversized tables, and zero identities.

Implemented limits: this is adapter-owned retention and wire policy.  It does
not define face/font/image payloads, attach resources to render items, integrate
deletion into `FRAME_UPDATE`, recover snapshots, or render resources.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
```

Status: approved. The dedicated reviewer completed protocol, cache ownership,
failure atomicity, and regression passes; approved fixes added minimum-eviction
replacement behavior and deterministic LRU regression coverage. Local
validation passed 96/96 adapter unit tests, the boundary audit, and the W12c
frame smoke.

#### W12f — Optional host frame-state ABI seam (approved)

Goal: define a versioned, backward-compatible way for a future
Proto-UI-owned host adapter to expose authoritative frame generation,
visibility, and focus without modifying inherited Emacs C files.

1. Append an optional `read_frame_state` callback to the end of `HostV1`
   while keeping ABI major version 1.
2. Define C-compatible `FrameState` as generation, visibility byte
   (`hidden=0`, `visible=1`, `iconified=2`), focused byte (`0/1`), and six
   reserved zero bytes.
3. Accept legacy v1 tables that end after the required generation and geometry
   callbacks; expose frame state only when the supplied table size actually
   covers the appended callback.
4. Add `Runtime.observeFrameState` and fail closed on zero frame identity,
   unsupported/missing callback, callback failure, zero generation, invalid
   visibility, invalid focus, focused hidden/iconified state, and nonzero
   reserved bytes.
5. Keep observation read-only so it cannot mutate capture, resource, or
   transport state.
6. Generate C declarations and mark `read_frame_state` optional in the
   non-normative ABI manifest.

Implemented limits: this is a fake-host-validated ABI contract only.  No Emacs
process currently supplies the callback, no `output_proto` terminal exists, and
no runtime frame event is transported yet.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
```

Status: approved. The dedicated reviewer completed ABI compatibility/layout,
fail-closed state validation, and regression/boundary passes; approved fixes
included explicit host-size gating, reserved-byte validation, and rejection of
focused hidden/iconified host state. Local validation passed 100/100 adapter
unit tests, the boundary audit, and the W12c frame smoke.

#### W12g — Output-proto runtime bridge design (normative)

Goal: split the remaining path to a real `output_proto` terminal into safe,
testable work while keeping runtime registration fail closed.

1. Publish the authoritative host-adapter bridge design in
   [`output-proto-runtime.md`](output-proto-runtime.md).
2. Define terminal lifecycle states, generation rules, cleanup, and failure
   containment.
3. Define the host extension-callback groups required for terminal, frame,
   redisplay, input, and lifecycle operation.
4. State explicitly that no public Emacs dynamic-module API can register
   `output_proto`; runtime must remain unavailable without that contract.
5. Split implementation into R1-R9 tasks, from terminal lifecycle core through
   the first real SDL3 frame and PGTK differential compatibility.
6. Prohibit binary patching, symbol interposition, and generated replacement of
   tracked inherited C files as substitutes for an approved extension point.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

Status: normative design.  Runtime tasks R1-R7 infrastructure are implemented
through bounded frame-service mapping, deterministic capture-batch encoding,
and the pending host-registration decision contract; R8-R9 remain
unimplemented.  The boundary gate and documentation links remain green.

##### R2 evidence

R2 adds `src/proto-ui/runtime.zig` as the source-authoritative state,
`proto-ui-runtime-manifest` as the deterministic manifest step, and a required
nonzero boundary gate with reason
`host_registration_contract_missing`.  The generated manifest records all five
required callback groups, R1 groundwork, ownership boundaries, and the exact
failure command.  It never enables terminal registration or falls back to
PGTK/TTY.

##### R3 evidence

R3 extends ABI generation with deterministic `shim.c`, installs it beside
`abi_v1.h`, and compiles that generated source directly in the build graph.
The tracked Zig host harness validates C/Zig layout, success delegation, null
arguments, ABI/table mismatch, missing callbacks, callback failure, zero
generation, and legacy/current frame-state table handling.  It adds no
terminal registration, protocol encoding, EUP generation, or `output_proto`
runtime.

##### R4 evidence

R4 compiles that same generated source as a host shared library, installs it
under `zig-out/lib`, hides non-API C symbols, and runs a tracked
dynamic-loader conformance executable against the exact build-graph artifact.
It validates all five loaded function pointers, success/fail-closed paths, and
forbidden-symbol isolation without registering a terminal or enabling runtime.

##### R5 evidence

R5 adds `src/proto-ui/frame_service.zig` with bounded host-handle to EUP-frame
mapping, active-terminal enforcement, observed generation/visibility/focus
registration, stale-generation refresh rejection, delete-once teardown, and
terminal drain.  Fake-host tests cover identity collisions, table overflow,
generation range/mismatch, malformed state, unknown mappings, and cleanup
without adding terminal registration, EUP generation, transport, or
`output_proto` runtime.

##### R6 evidence

R6 adds `src/proto-ui/capture_service.zig` for one-window adapter observation
batches.  It validates window/row/cursor/damage coherence, encodes stable
section order and deterministic envelopes, verifies them through
`frontend.Scene`, guards commit against stale host generations, and proves
ERP1 replay round trips preserve bytes exactly.  It does not install redisplay
hooks or claim redisplay-owned output.

##### R7 evidence

R7 adds `src/proto-ui/host_contract.zig`, its deterministic generator and gate,
and `zig-out/proto-ui/host_registration_contract.json`.  The schema records
decision status and review metadata, acceptable and forbidden integration
mechanisms, required callback groups and evidence gates, rollback/disable
guarantees, default-build isolation, and the rule that the frontend never
evaluates Elisp or owns layout.  The source decision remains `pending` with
`host_registration_contract_missing`; the runtime manifest references this
decision and remains fail closed.

##### R8 entry-readiness evidence

R8 readiness is machine-readable in `src/proto-ui/r8_readiness.zig` and
`zig-out/proto-ui/r8_readiness.json`.  The source records seven required
conditions, tracks the pending R7 decision, asserts an empty inherited-source
edit set, keeps activation/runtime/default enablement false, and validates the
rollback order.  `proto-ui-r8-readiness` accepts the blocked state as a valid
audit result.  The opt-in `-Dr8-entry-gate=true proto-ui-r8-readiness` form is
the negative launch gate: it fails with `r8_entry_readiness_missing` until the
source itself becomes ready.

1. Implement child and tooltip frame protocol.
2. Implement multi-frame focus isolation.
3. Implement monitor change and per-monitor scale.
4. Implement undecorated/fullscreen/maximized states.
5. Implement fringe, divider, border, mouse-face, and overlay-arrow rendering.
6. Implement mode/header/tab lines.
7. Implement tool bar and menu bar.
8. Implement image glyph rendering.
9. Implement animation and cache invalidation.
10. Update capability matrix with implementation status.

Acceptance:

Every capability row in `capabilities.md` is one of:

```text
implemented
degraded
explicitly unsupported
```

No row may remain merely “specified.”

Review gates:

1. PGTK parity differential tests.
2. Fallback correctness.
3. Protocol table completeness.

### W13 — Protocol conformance, replay, and fuzz

Goal: prove protocol robustness.

Status: W13-a, W13-b, W13-c, and W13-d complete.  The deterministic protocol fuzz gate covers
envelope, frame-update, capability, visibility/focus, resource, input-codec,
and frontend `Scene.apply` seeds.  The recovery differential gate compares
ordered application, authenticated resync, ACK-loss retry, and ERP1 replay to
one canonical final `Scene` digest.  W13-c makes every route restore the same
bounded face, font, string, and complete RGBA8 image state; authenticated
resync restores them atomically from `RESOURCE_SNAPSHOT`.  It remains
adapter-only and does not open a socket, start Emacs, or enable `output_proto`.
W13-d adds `proto-ui-crash-isolation`: the parent spawns itself in bounded
child mode, transfers a fixed corpus of valid and hostile EUP records, requires
a machine-readable handled report from every malformed case, and proves that
one controlled nonzero frontend child is detected while the parent remains
healthy.  This is process-containment evidence, not evidence about inherited
Emacs internals.

Tasks:

1. Add envelope fuzzing.
2. Add payload-table fuzzing.
3. Add sequence-gap tests.
4. Add stale-generation tests.
5. Add missing-resource tests.
6. Add reconnect/replay tests. *(W13-b covers resync and ERP1 replay.)*
7. Add frontend crash isolation tests.
   *(W13-d covers 23 bounded decoder/Scene cases plus one controlled nonzero
   frontend child.)*
8. Add deterministic snapshot comparison. *(W13-b/W13-c cover canonical
   final-state and concrete-resource fingerprints, `RESOURCE_SNAPSHOT`
   recovery, payload-mutation mismatch, identity mismatch, and deliberate
   mismatch rejection.)*

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-conformance
zig build -Dproto-ui=true proto-ui-recovery-diff
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-crash-isolation
```

No malformed input may crash Emacs.

Review gates:

1. Parser safety.
2. Recovery correctness.
3. Resource bounds.
4. Process lifecycle, pipe/exit-code handling, corpus bounds, and deterministic
   case order.

### W14 — Performance hardening

Goal: prove the documented performance improvement.

Status: W14-a complete. `proto-ui-bench` is an opt-in, adapter-only
ReleaseFast baseline that installs `zig-out/proto-ui/benchmark.json`.
It covers EUP `FRAME_UPDATE` encoding, envelope/payload decode and validation,
fresh `frontend.Scene.apply`, atomic `CaptureService` encoding, and bounded
memory-sink sending on deterministic 960x600, 30-row fixtures. It reports
monotonic latency percentiles, throughput, byte volume, allocation counts,
iteration/warmup counts, build mode, and EUP version as machine-readable JSON.
It intentionally remains outside `proto-ui-boundary` so timing cannot make the
compatibility gate flaky. Frame creation, typing, scroll, resize, faces, fonts,
images, widgets, multi-frame, renderer tiers, and optimization work remain
W14 follow-up work.

Tasks:

1. Add machine-readable benchmark harness. *(W14-a covers the adapter memory-transport baseline.)*
2. Benchmark frame creation, typing, scroll, resize, faces, fonts, images, widgets, and multi-frame.
3. Add allocation counters. *(W14-a records measurable per-operation allocation counts.)*
4. Add bandwidth counters. *(W14-a records bytes/op and MiB/s for adapter paths.)*
5. Add latency percentiles. *(W14-a records p50/p95/p99 and mean.)*
6. Tune damage merging.
7. Tune glyph atlas.
8. Tune transport slab reuse.
9. Compare software, GPU basic, and GPU advanced tiers.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-bench --summary all
cat zig-out/proto-ui/benchmark.json
```

The W14-a baseline acceptance is the command above; its `result` proves only
that all requested operations completed and the report values validated. Full
W14 acceptance additionally requires the remaining workloads to meet
`performance.md` targets and retain comparative evidence.

Review gates:

1. Measurement correctness.
2. Hot-path efficiency.
3. Correctness under optimization.

### W15 — Emacs compatibility validation

Goal: prove “fully compatible with existing Emacs capabilities” within the declared capability matrix.

Status: W15-a, W15-b, and W15-c complete as bounded base/PGTK health evidence,
a deterministic TTY/PGTK semantic matrix, and a disabled/default isolation
audit.  They do **not** prove proto-frame compatibility, `output_proto`, or
complete PGTK parity.

Tasks:

1. Add an isolated batch gate that runs the installed Emacs without user,
   site, X-resource, or site-lisp initialization. *(W15-a.)*
2. Exercise identity/version, buffer text and undo, point/mark and narrowing,
   text properties and overlay faces, face definition/readback, window
   split/select/delete, resize/scroll/recenter, and buffer-local variables.
   *(W15-a.)*
3. On a graphical host, create one real PGTK frame, run window/scroll/face
   checks there, delete it, and verify cleanup. *(W15-a.)*
4. Without a display, emit explicit PGTK skips and still run backend-safe
   scenarios. *(W15-a.)*
5. Emit one machine-readable report with per-scenario details and no writable
   repository files. *(W15-a.)*
6. Run the seven fixed backend-neutral scenarios in both the batch/TTY parent
   and a real PGTK child when a display is present; emit per-scenario/backend
   signatures and SHA-256 digests, combined per-backend digests, per-pair
   digests, and explicit match/skip/fail statuses. *(W15-b.)*
7. Reject digest, scenario-order, mismatch, or fail-closed matrix violations in
   the Zig report runner. *(W15-b.)*
8. Compare TTY/PGTK/proto redisplay semantics for text, windows, faces,
   cursor, scroll, and frames.
9. Verify existing Lisp APIs on proto frames.
10. Verify proto removal/disabled state leaves no runtime trace.
    *(W15-c covers a static working-tree/generated-config isolation audit; it
    does not exercise a compiled runtime toggle.)*
11. Document every deliberate degradation.

Acceptance:

```sh
zig build check
zig build -Dpgtk=true check
zig build -Dproto-ui=true check
zig build -Dproto-ui=true proto-ui-diff
zig build -Dproto-ui=true proto-ui-compat
zig build -Dproto-ui=true proto-ui-isolation-audit
```

`proto-ui-compat` passes only when every non-skipped scenario passes.  It is
bounded and deterministic; no elapsed time participates in pass/fail.  The
source-authoritative capability descriptors are
`compatibility.pgtk_base_gate` and `compatibility.backend_semantic_matrix`:
degraded, non-negotiable, evidence `proto-ui-compat`.  The semantic matrix
covers existing TTY and PGTK behavior only and does not define a proto frame.
W15-c adds `isolation.disabled_default_gate`: degraded, non-negotiable,
evidence `proto-ui-isolation-audit`.

Review gates:

1. Default-build compatibility.
2. Existing backend isolation.
3. Emacs semantic correctness.

W15-c review gates:

1. Scanner/path coverage and false-positive control.
2. Deterministic JSON and resource bounds.
3. Build/regression/status accuracy.

### W16 — Final real SDL3 acceptance

Goal: demonstrate the user-facing objective.

Final scenario:

1. Build with:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true
```

2. Start Emacs and SDL3 frontend.
3. Open a proto frame.
4. Verify a real SDL3 window appears.
5. Insert ASCII and CJK text.
6. Split and resize windows.
7. Scroll long text.
8. Change faces and fonts.
9. Use keyboard, mouse, wheel, clipboard, IME, menu, dialog, tooltip, and scrollbar.
10. Create and delete multiple frames.
11. Move across monitors or change scale where available.
12. Disconnect and reconnect frontend.
13. Delete all proto frames and exit cleanly.

Final evidence:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-live-smoke
zig build -Dproto-ui=true proto-ui-replay-test
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-bench
zig build check
```

All commands must pass with artifacts retained.

The final evidence must also include the adapter-boundary audit from
[`adapter-boundary.md`](adapter-boundary.md): no new inherited-C Proto-UI
edits, default-build isolation, and a documented rollback path.

## W17 — Pure SDL3 PGTK parity

Status: normative target documented; runtime and parity not implemented.

W17 corrects the end-state interpretation.  SDL3 is the final UI backend for
`output_proto`; PGTK is only the offline reference implementation used for
semantic and visual comparison.  A Proto frame must never silently fall back to
PGTK or TTY.  Emacs remains authoritative for buffer, command, window-layout,
redisplay, face, font, image, and input-interpretation state; the adapter
translates terminal/frame/input/resource facts across EUP.  The normative
ownership model, responsibility matrix, protocol gaps, milestone sequence,
differential gates, and final acceptance rules are in
[`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md).

Non-goals:

1. Expanding PGTK-backed diagnostic smokes and calling them pure SDL3 parity.
2. Letting SDL evaluate Elisp or own buffer/window/redisplay truth.
3. Adding scattered Proto-UI branches to inherited Emacs C/H/Lisp.
4. Registering `output_proto` before the R7 host contract is explicitly approved.

P11 image presentation adds complete RGBA8 resource rendering to the SDL
diagnostic bridge.  It uses nearest scaling, rejects incomplete resources, and
does not implement production image decoding, animation, cache eviction, or
redisplay-owned placement.
P11 image presentation adds complete RGBA8 resource rendering to the SDL
diagnostic bridge.  It uses nearest scaling, rejects incomplete resources, and
does not implement production image decoding, animation, cache eviction, or
redisplay-owned placement.
P11 window-tree preparation adds a strict `WINDOW_TREE_SNAPSHOT` v1 codec and
Scene-owned complete-tree validation for hierarchy, selected/visible state,
depth, and bounds. Window-management commands and rendering parity remain
pending.
P10 preparation adds face-bound `GLYPH_RUN` v2: the frontend validates a live
face generation, removes dependent runs on face replacement/delete, and renders
bounded ASCII text with face foreground/background in the diagnostic SDL path.
Production redisplay, shaping, fonts, and atlas rendering remain pending.
P9 geometry preparation adds `refreshFrameGeometry`, authoritative frame
bounds, and observation validation in `runtime_bridge`; real monitor and scale
events remain pending.
P29 protocol coverage remains source-authoritative for every assigned EUP ID;
current counts are 164 implemented codecs, 0 partial, and 0 planned.
P12 session-setup preparation adds concrete standard EUP HELLO, HELLO_ACK,
SESSION_READY, and READY_ACK codecs with a bounded frontend state machine.  The
authenticated EPXL handshake remains the current transport path.
P12 session-control preparation adds concrete suspend/resume/close/liveness,
error, and version-mismatch codecs plus a bounded control state machine.  The
state machine enforces ordered suspend/resume and fatal close/error states, but
`Scene` now rejects frame traffic while suspended and restores it only after
`SESSION_RESUMED`.  The SDL bridge proves that blocking and recovery sequence;
`sdl3-live-smoke` carries that sequence, PING/PONG, a recoverable ERROR, and
normal SESSION_CLOSE over authenticated EPXL frames and ACKs each control like
ordinary EUP traffic.  The frontend asserts liveness resolution, error
recovery, and clean closed state.  It also automatically replies to PING with
a reverse-direction PONG.  Standard-control smoke requires
`session.control_v1` on both sides before carrying a control frame.
A fresh authenticated connection then proves fatal `VERSION_MISMATCH`
transport.
P12 title preparation adds `FRAME_TITLE` v1: a 16-byte, generation-qualified
reference to a live string resource.  The Scene resolves and owns the title and
the diagnostic SDL bridge applies it to its window; this does not register a
terminal or publish Emacs title parameters.
P12 alpha preparation adds `FRAME_ALPHA` v1 for active, inactive, and
background opacity.  The Scene validates the generation-qualified triple and
the diagnostic SDL bridge probes platform opacity with explicit opaque
fallback; focus events and PGTK visual parity remain pending.
P12 decoration preparation adds `FRAME_DECORATIONS` v1.  The Scene stores the
decorated/undecorated policy and the diagnostic SDL bridge verifies the
border flag with a restore; parent, tooltip, override-redirect, and full WM
policy parity remain pending.
P12 scale preparation adds `FRAME_SCALE` v1 for generation-qualified scale and
X/Y DPI state.  The diagnostic SDL bridge reads per-window display scale;
monitor migration, live scale events, and redisplay adaptation remain pending.
P12 fullscreen preparation adds `FRAME_FULLSCREEN` v1 for none, fullboth,
fullwidth, fullheight, and maximized modes.  The diagnostic SDL bridge applies
and restores fullboth; the remaining modes are state-only until platform and
redisplay mapping land.
P12 monitor preparation adds `FRAME_MONITOR` v1 for generation-qualified
monitor identity, primary flag, and logical bounds.  The diagnostic SDL bridge
queries real display geometry; change events and frame migration remain
pending.
P12 presentation-feedback preparation adds little-endian `FRAME_PRESENTED` and
`FRAME_DROPPED` payloads.  The SDL bridge encodes and validates real
presented-frame counter data and a deterministic superseded-frame drop record.
Core consumption, adaptive pacing, and GPU timestamps remain pending.
P12 geometry preparation adds `FRAME_GEOMETRY` v1 for outer, content, text,
window, and body rectangles.  The Scene validates containment and the SDL
bridge queries real border sizes; core-owned resize migration remains pending.
P12 icon preparation adds `FRAME_ICON` v1 for a nullable, generation-qualified
RGBA icon reference.  The Scene validates the live complete image and hotspot;
the SDL bridge creates a surface and applies it to the diagnostic window.
Multi-resolution and animated icons remain pending.
P12 size-hint preparation adds `FRAME_SIZE_HINTS` v1 for min/max size,
increment, and aspect constraints.  The Scene owns the hints and the SDL bridge
applies min/max and aspect constraints; size increments and redisplay geometry
adaptation remain pending.
P12 z-order preparation adds `FRAME_Z_ORDER` v1 for raise, lower, top, bottom,
above, and below requests.  The Scene validates relative targets, and the SDL
bridge probes and restores always-on-top state; portable bottom and relative
stacking remain pending.
P12 parent preparation adds `FRAME_PARENT` v1 for a nullable parent relation
with modal policy.  The Scene validates child and active-parent identity before
storing relation policy, and the SDL bridge proves the unparent path; linked
child windows and modal propagation remain pending.
P12 window-patch preparation adds a bounded `WINDOW_PATCH` record for geometry,
parent, visibility, default-face, and depth changes.  The Scene rejects cycles,
missing parents, invalid depth, and out-of-order lifecycle transitions; window
zones, faces, scroll state, and mouse-highlight records remain pending.
P12 cursor-update preparation adds a dedicated `CURSOR_UPDATE` record with
owner/geometry validation and SDL rendering evidence.  Cursor styles,
IME-coupled caret behavior, and redisplay-owned cursor semantics remain
pending.
P13 render-control preparation adds strict fixed-width `FLUSH` and
`RENDER_HINT` codecs.  The runtime bridge emits `FLUSH` only for the latest
captured frame sequence and emits the configured hint through the same EUP
stream.  The Scene validates active frame identity, stores the present boundary
and renderer preference, and the SDL runtime-bridge smoke proves acceptance
after a real frame update.  Core redisplay emission, adaptive pacing, and
guaranteed renderer-mode switching remain pending.
P14 continuous-capture preparation lets a committed `captured` bridge begin a
strictly newer redisplay generation without rebuilding the terminal or frame.
The host callback must succeed before the bridge swaps the capture identity,
resets bounded observation tables, invalidates the prior frame sequence/flush,
and accepts the next authoritative update.  An update is encoded and then
explicitly accepted before `FLUSH`; a rejected encode is never flushed.  A
successful `FLUSH` first invokes the host flush callback, then emits the EUP
boundary.  A render hint remains policy for the EUP frame generation across
capture generations.  This remains fake-host adapter preparation; redisplay
capture and `output_proto` registration remain pending.
P15 terminal-service preparation binds `PureRuntimeHostV1` terminal callbacks
to the bounded no-reuse terminal registry.  The fake-host service covers
create, activate, host-delete drain with retry, rollback-pending cleanup, and
strict host identity validation.  This is orchestration readiness only; no R7
approval, Emacs terminal selection, registration, or runtime enablement exists.
The `proto-ui-terminal-service` gate emits deterministic machine-readable
evidence and is part of `proto-ui-boundary`; its report still records
`emacs_registered=false` and `runtime_available=false`.
P16 host-adapter selection preparation names the pure-SDL3 `output_proto`
candidate and records its policy in one versioned manifest.  The candidate must
use ABI v1, modify no inherited source, forbid PGTK/TTY runtime fallback and
frontend Elisp/layout ownership, and require every callback group.  While R7 is
pending it remains `unselected`; an approved decision also requires complete
review metadata before selection can be marked selected.  Selection never
implies activation: the current source and gate remain registered=false and
runtime_available=false.
P17 activation preparation adds a selection-gated controller and an explicit
seven-step activation sequence with the reverse rollback order.  While R7 is
pending, the controller rejects activation before any host callback and the
manifest reports `blocked_by_r7`.  Unit conformance uses an approved fake-host
decision to prove activate, rollback-on-failure, and drain paths; no real Emacs
terminal is registered and runtime remains unavailable.
P18 damage-array preparation adds a bounded `DAMAGE_RECTS` codec and bridge
emission.  The Scene validates every rectangle against the accepted
`FRAME_UPDATE` before atomically replacing its damage set.  The SDL smoke proves
the observed array reaches Scene and drives a bounded retained-target clip with
explicit-present counters.  Redisplay-owned incremental damage, dirty-texture
upload, and GPU timestamps remain pending.
P19 clear-area preparation adds an exact 40-byte `CLEAR_AREA` payload.  `Scene`
validates active frame and window-relative bounds, requires a live generation-
qualified face with a background color, and retains at most 64 areas until the
next authoritative `FRAME_UPDATE`.  The SDL draw list renders the validated face
background.  This is a bounded render-control subset, not redisplay-owned
capture.
P20 scroll-copy preparation adds a 32-byte `SCROLL_RUN` payload for
full-window-width vertical bands.  `Scene` validates source and destination
bands against the active owner and retains at most 32 runs until the next
authoritative update.  `renderer.planScrollCopy` computes overlap and estimated
RGBA upload bytes; actual SDL copy execution and redisplay-owned scroll capture
remain pending.
The SDL runtime smoke executes the planned copy by snapshotting the source band
into a scratch target and drawing that snapshot to the destination.  It records
planned bytes, submitted copy commands, and presents the retained output without
sample-sampling the active render target.  Redisplay-owned scroll capture and
general GPU batching remain pending.
P21 border-style preparation adds `BORDER_UPDATE` v1.  `Scene` validates the
schema, known side mask, bounded thickness, opaque RGBA color, and active frame
generation.  The SDL draw list renders only the requested edges with the
requested thickness/color.  This is bounded visual styling; core-owned border
geometry and window-manager parity remain pending.
P22 divider preparation adds `DIVIDER_UPDATE` v1 for bounded vertical or
horizontal dividers.  `Scene` validates active frame/window bounds and replaces
a divider only with a strictly newer generation.  The SDL draw list renders the
validated fixed-color geometry.  Draggable divider semantics and redisplay-owned
layout remain pending.
P25 row-lifecycle preparation adds granular `ROW_SNAPSHOT`, `ROW_UPDATE`, and `ROW_DELETE` v1 codecs.  `Scene` validates active generation, owner window, logical bounds, flags, and metric non-negativity; snapshots upsert rows, updates require existing rows, and deletes remove dependent row text while rejecting live glyph runs.  This advances the bounded row model; redisplay-owned capture remains pending.
P26 font-metrics preparation adds `FONT_METRICS` v1, a bounded metrics patch that updates ascent, descent, line height, average advance, and max advance with strict expected/new generation checks.  This improves resource evolution; real font metrics and shaped rendering remain pending.
P27 update-boundary preparation adds strict `BEGIN_UPDATE`/`END_UPDATE` v1 codecs with active-frame checks, non-nested IDs, and deterministic close validation.  Redisplay wiring remains pending.
P28 scrollbar-state preparation adds `WINDOW_SCROLL_STATE` v1 with content/viewport/position validation and one upsert per window.  The SDL draw list renders a proportional vertical track/thumb; drag requests and core-owned scroll semantics remain pending.
P29 scroll-request preparation adds a bounded absolute/relative reverse intent for vertical or horizontal scrolling, negotiated queue delivery, and EPXL encoding/acknowledgement.  Actual core application of the intent remains pending.
P24 face-decoration preparation converts face underline, overline,
strike-through, and box policies into bounded bars in the SDL debug glyph path.
Style-color variants use their dedicated RGBA colors, while single styles use
the face foreground.  These are conservative approximation bars, not shaped-text
metrics or full Emacs face rendering.
P30 window-face preparation adds `WINDOW_FACE` v1 with active-frame/window checks, exact live-face generation validation, a bounded per-window upsert table, lifecycle invalidation, and an SDL owner-background render probe.  This is bounded evidence, not core-owned face capture or PGTK face parity.
P31 window-geometry preparation adds `WINDOW_GEOMETRY` v1 with strict content/body containment, active owner validation, one bounded upsert per window, authoritative-update and window-lifecycle invalidation, and an SDL body-boundary render probe.  Redisplay-owned layout, zones, and complete PGTK window parity remain pending.
P32 window-zone preparation adds `WINDOW_ZONES` v1 with nine fixed region slots, strict presence/rect validation, disjoint owner containment, body-conflict checks, bounded per-window upsert, lifecycle invalidation, and SDL top-boundary evidence.  Redisplay-owned zones and complete PGTK layout parity remain pending.
P33 window-position preparation adds `WINDOW_POSITION` v1 as an exact 40-byte diagnostic buffer identity/start/point fact with active-frame/window validation, bounded per-window upsert, and authoritative cleanup.  It does not transport text or implement complete point/viewport semantics.
P34 runtime-face preparation adds a 96-byte `FaceRecord` observation to the PureRuntimeHostV1 redisplay ABI, bounded `FACE_DEFINE` emission, duplicate-face rejection, and strict face-generation checks before captured runs.  Real Emacs redisplay attachment and complete face parity remain pending.
P35 runtime-font preparation adds a 224-byte `FontRecord` observation to the PureRuntimeHostV1 redisplay ABI, bounded `FONT_DEFINE` emission, duplicate-font rejection, and strict live-font checks for font-backed faces.  Real font rasterization, shaped text, and PGTK parity remain pending.
P36 runtime-image preparation adds a 72-byte `ImageDefineRecord` and bounded 1,044-byte `ImageFragmentRecord` to the redisplay ABI, with ordered fragments, total-length checks, duplicate-image rejection, and existing `IMAGE_DEFINE`/`IMAGE_DATA` emission.  The seam currently accepts at most four 1 KiB fragments per image; full-size capture and PGTK parity remain pending.
P37 atlas preparation implements `ATLAS_DEFINE`, `ATLAS_PAGE_UPDATE`, `ATLAS_GLYPH_ADD`, and `ATLAS_INVALIDATE` with bounded RGBA8 page bytes, atlas-contained glyph rectangles, unique font/glyph keys, and invalidation of pages, glyphs, or the full atlas.  GPU texture upload, rasterization, shaping, and replacement policy remain pending.
P38 atlas-render preparation adds an SDL `image_region` draw command, a per-frame texture cache keyed by source page, and ASCII atlas-glyph rendering with debug-text fallback.  Persistent textures, shaping, eviction, and PGTK parity remain pending.
P39 shaped-atlas-run preparation adds `GLYPH_RUN` schema 3 with fixed glyph ID/cluster/offset/advance records, live face-font validation, atlas-entry checks, and SDL atlas-backed drawing.  It is bounded to seven glyphs and does not claim complete shaping, BiDi, or PGTK parity.
P40 runtime shaped-run capture preparation adds a 176-byte `ShapedRunRecord` observation to the PureRuntimeHostV1 redisplay ABI, with seven bounded glyph records, duplicate-run rejection, live face/font linkage, and schema-3 EUP emission.  Real Emacs redisplay capture, BiDi reordering, and full shaping parity remain pending.
P41 R7-readiness audit synchronizes the runtime callback inventory with the PureRuntimeHostV1 redisplay ABI and adds implemented prerequisite records for resource, shaped-run, face, font, and image capture.  The R7 decision itself remains pending and fail-closed.
P42 mouse-highlight preparation adds `WINDOW_MOUSE_HIGHLIGHT` v1 as an exact 48-byte visible face rectangle.  The Scene validates active frame/header identity, owner containment, and exact live face generation, upserts one bounded state per window, clears it on authoritative updates, and invalidates dependent states on window/face lifecycle changes.  SDL rendering proves the bounded rect only; pointer motion, Emacs mouse-face resolution, overlays, and PGTK parity remain pending.
P43 font-patch preparation adds `FONT_PATCH` v1 as an exact 44-byte scalar descriptor evolution contract.  The Scene requires exact expected generation, preserves retained metadata/metrics, revalidates the complete font, advances generation, and removes stale shaped runs.  Runtime smoke proves generation and weight evolution; real font objects, metadata/metric patching, frame font changes, and PGTK parity remain pending.
P44 fringe-bitmap preparation adds `FRINGE_BITMAP_DEFINE`/`DELETE` v1 with bounded 1..32 monochrome MSB-first bitmaps, strict generation lifecycle, shared registry integration, snapshot restore, stale placement removal, and SDL cell expansion with color-band fallback.  Color/alpha bitmaps, authoring and scaling policy, draggable semantics, and PGTK parity remain pending.
P45 bounded-tooltip preparation adds `TOOLTIP_SHOW`, `MOVE`, and `HIDE` v1.  The Scene validates active frame/window identity, owner bounds, exact generations, and strict UTF-8 text; authoritative updates clear state.  SDL proves box and ASCII-text rendering.  Tooltip delay/dismiss policy, platform positioning, Unicode glyph rendering, hit testing, accessibility, and PGTK parity remain pending.
P46 menu-model preparation adds `MENU_MODEL` v1 as a bounded authoritative complete tree with fixed UTF-8 label/help/key fields, strict hierarchy/generation validation, Scene ownership, and SDL diagnostic menu-bar rendering.  Menu patches, open state, navigation, result dispatch, native menus, and full menu parity remain pending.
P47 menu-open preparation adds `MENU_OPEN`/`CLOSE` v1 for one live popup tied to an enabled visible submenu, exact model generation, owner containment, and authoritative cleanup.  SDL proves child-row rendering; keyboard navigation, hover, selection results, and native menus remain pending.
P48 menu-result preparation adds `MENU_RESULT` and `MENU_CANCEL` as exact bounded reverse intents with validated menu/window/frame fields and a negotiated acknowledged DeliveryJournal queue.  SDL hit testing, keyboard navigation, core keymap execution, and PGTK menu parity remain pending.
P49 frame-patch preparation adds `FRAME_PATCH` v1 as an exact 40-byte atomic batch for selected visibility, focus, opacity, decoration, and scale state.  The Scene validates active-frame identity and lifecycle consistency before applying any field.  SDL runtime smoke proves alpha/decoration/scale application.  Title, geometry, monitor, z-order, and redisplay adaptation remain pending.
P50 frame-snapshot preparation adds `FRAME_SNAPSHOT` v1 as an exact 128-byte atomic core presentation snapshot with complete presence validation, strict geometry containment, lifecycle consistency, and Scene restoration.  SDL runtime smoke applies/restores opacity, decoration, renderer scale, fullscreen absence, both-axis maximize, and bounded probe-window geometry; title, icon, monitor, z-order, parent, full frame parameters, and redisplay adaptation remain pending.
P52 menu-patch preparation adds `MENU_PATCH` v1 with 1..32 ordered upsert/delete operations, strict expected/new generation validation, parent/hierarchy checks, atomic model replacement, popup invalidation, and SDL render evidence.  Dedicated move semantics, conflict policy, and full menu parity remain pending.
P51 menu-hover preparation adds `MENU_HOVER` v1 as an exact 40-byte enter/move/leave reverse intent with phase-specific item/coordinate validation and a negotiated acknowledged DeliveryJournal queue.  SDL hit testing, submenu policy, visual highlighting, and Emacs dispatch remain pending.
P53 tool-bar preparation adds `TOOLBAR_MODEL` v1 with 1..16 bounded UTF-8 button/toggle/separator/space items and `TOOLBAR_CLICK` v1 as a negotiated press/release reverse intent carrying toolbar/item/window/frame identity, click count, button, modifiers, and coordinates.  SDL renders a diagnostic row.  Icons, overflow, orientation, hit testing, keymap execution, and PGTK parity remain pending.
P54 tool-bar patch preparation adds `TOOLBAR_PATCH` v1 with ordered upsert/delete operations, strict toolbar generations, atomic Scene evolution, and SDL render evidence.  Dedicated moves, icon rendering, overflow policy, and full toolbar parity remain pending.
P55 bounded-dialog preparation adds the four dialog v1 codecs as an adapter-owned slice: bounded model/open/update/close state, owner containment, exact generations, negotiated result queue, EPXL admission/artifact decoding, and SDL box evidence.  Full Emacs callback behavior, native/file/color/font dialogs, and PGTK parity remain explicitly pending.
P56 dedicated-scrollbar preparation adds `SCROLLBAR_STATE`/`SCROLLBAR_EVENT` v1 as bounded aliases over proven state/request payloads with Scene dispatch, separate capability negotiation, DeliveryJournal ordering, and live EPXL wire ACK evidence.  Full scrollbar semantics and Emacs dispatch remain pending.
P58 multi-window content preparation publishes bounded `WINDOW_STATE` observations for every live window through the snapshot JSON and projects them as window-owned `TEXT_LINE_V2` rows.  A state carries `id`, `lines`, `window_start_line`, `window_visible_lines`, an optional bounded public cursor with `cursor_active`, optional bounded public mode line with height, and optional bounded public header/tab lines with heights; publisher text and these lines are UTF-8 byte-bounded to 120 bytes and visible text is capped to eight lines.  There is one state per live window in `window-list` order, and EUP carries up to one bounded cursor per live window with exactly one active selected-window cursor.  Full per-window scroll, redisplay cursor semantics, hierarchy, faces, and command semantics remain pending.
P59 standalone icon-resource preparation adds `ICON_DEFINE`/`ICON_DELETE` v1 with complete bounded RGBA8 payloads, hotspot and dimension validation, Scene image-resource ownership, frame-icon compatibility, generation-aware deletion, and stale-resource rejection.  Multi-resolution bundles, animation, masks, and taskbar parity remain pending.
P60 drag-and-drop preparation adds bounded DND enter/position/leave/drop/cancel/reply/data wire codecs with action masks, nonzero drag identities, bounded offers and payloads, and strict boundary validation.  SDL event mapping, Scene/core dispatch, platform ownership, and rich MIME conversion remain pending.
P61 diagnostics preparation adds bounded EUP codecs for performance counters, frame timing, bandwidth, resource/damage statistics, input latency, desynchronization reports, trace begin/end, and replay checkpoints.  These are wire codecs only; producer/consumer integration, storage, dashboards, and core-side collection remain pending.
P62 extended-input preparation adds all remaining planned concrete codecs for multi-contact touch, pan/pinch/rotate/long-press gestures, monitor and DPI changes, theme/accessibility preference, input-device arrival/removal, and bounded ordered input batches.  The manifest no longer has planned IDs; SDL/backend application and the three partial resync IDs remain pending.
P63 IME-preedit preparation integrates `IME_PREEDIT_START`, `IME_PREEDIT_UPDATE`, and `IME_PREEDIT_END` into `Scene`.  A live IME context stores bounded UTF-8 preedit bytes, cursor offset, and selected length; update requires an active preedit and end/reset/detach clear it atomically.  The SDL diagnostic renderer draws a bounded ASCII overlay for a focused context; platform composition, Unicode/font rendering, commit application, and candidates remain pending.
P64 IME-candidate preparation integrates `IME_CANDIDATE_UPDATE` and `IME_CANCEL` into `Scene`.  A focused live context stores selected index, candidate/page counts, owner-relative placement, and a bounded selected label; zero-count updates and cancel clear state atomically.  The SDL diagnostic overlay renders selected metadata and ASCII labels only.  Full candidate lists, Unicode label rendering, platform IME, selection input, and commit application remain pending.
P57 real-window snapshot preparation projects bounded public `proto-ui-window-facts` into the `FRAME_UPDATE` window section.  Observed windows become Scene windows with authoritative frame-relative geometry and may carry bounded public point cursors; the selected window is the active EUP cursor.  IDs are adapter-owned process-lifetime identities, not cross-restart identities; redisplay-owned cursors, buffers, rows, faces, hierarchy, and command dispatch remain pending.
P39 atlas-cache preparation adds a persistent SDL page-texture cache keyed by atlas/page identity, generation, and revision.  Runtime smoke proves one upload plus at least four hits; smoke-level renderer-loss clearing is wired; production-wide integration and replacement/eviction policy remain pending.
P23 fringe preparation adds a 40-byte `FRINGE_UPDATE` v1 color-band subset with
left/right placement, strict generation replacement, active-frame/window bounds,
and a bounded Scene table.  The SDL draw list renders validated bands.  Bitmap
patterns and redisplay-owned fringe capture remain pending.
P12 maximize preparation adds `FRAME_MAXIMIZE` v1 for horizontal and vertical
axis flags.  The diagnostic SDL bridge applies and restores both-axis
maximization; single-axis mapping and redisplay adaptation remain pending.
P8 lifecycle preparation binds heartbeat, flush, diagnostics, and
cancel-all-pending-work into `runtime_bridge`, with safe cancellation of
accepted but incomplete input transactions.
P9 geometry preparation adds `refreshFrameGeometry`, authoritative frame bounds,
and observation validation in `runtime_bridge`; real monitor and scale events
remain pending.
P7 lifecycle-state preparation adds host-driven visibility/focus caching and
deterministic EUP state encoders to `runtime_bridge`; no real host or platform
source is attached.
P6 reverse-input preparation adds bounded key/text intents, delivery ACKs, host
results, and completion tracking through `runtime_bridge`.  This is intent
transport only; keymaps, commands, IME, modifiers coverage, and full input parity
remain pending.
P5 presentation preparation adds `sdl3-runtime-bridge-smoke`: a fake-host bridge
scene now reaches `frontend.Scene` and SDL3 presentation without Emacs
registration or output_proto ownership.
P5 run-payload preparation extends `PureRuntimeHostV1.RunRecord` and lets
`runtime_bridge` emit bounded debug `GLYPH_RUN` messages from fake-host runs.
Redisplay-owned capture and production runs remain pending.
P4 bridge preparation adds `runtime_bridge`: a validated pure host table can now
emit bounded EUP frame lifecycle/update messages in fake-host tests, while
terminal registration remains absent.
P3 C projection adds `proto-ui-runtime-host-abi`: the generated C header and
translation unit compile, but remain build artifacts outside inherited Emacs.
P3 runtime-ABI preparation adds `proto-ui-runtime-host`: the five required
callback groups now have a versioned C-ABI table and fake-host conformance, but
no Emacs host is selected and runtime remains fail-closed.
P1 readiness adds `proto-ui-pgtk-parity-plan`: all 48 differential cases remain
planned and the aggregate parity status remains `not_implemented`.
P2 readiness adds `proto-ui-r7-proposal`: the generated proposal is
`ready_for_review`, but its decision remains pending and the runtime remains
fail-closed.  Acceptance is defined by the P0-P10 milestones in the parity
document and by the W16 final scenario.  The distinguishing R8 evidence is a real frame whose
`window-system` is `proto`, whose visible surface is SDL3-owned, and whose
frame, redisplay, resource, input, and desktop-integration paths require no
GDK/GTK initialization.

## 4. Build/test surface

Build options:

```sh
-Dproto-ui=true
-Dsdl3-frontend=true
```

Current steps:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-abi
zig build -Dproto-ui=true proto-ui-conformance
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true proto-ui-boundary-audit
zig build -Dproto-ui=true -Dmodules=true proto-ui-module-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-live-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-facts-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-input-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-edit-smoke
zig build -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke
```

Planned steps:

```sh
zig build -Dproto-ui=true proto-ui-roundtrip
zig build -Dproto-ui=true proto-ui-replay-test
zig build -Dproto-ui=true proto-ui-diff
zig build -Dproto-ui=true proto-ui-live-recovery-test
```

Step names may be adjusted during W1/W2, but each listed verification must have a final equivalent.

## 5. Documentation tasks

| Task | Status |
|---|---|
| Architecture ownership model | Done |
| Emacs integration seams | Done |
| EUP envelope and message table | Done |
| Capability tables | Done |
| PGTK parity matrix | Done |
| Pure SDL3 PGTK-parity architecture | Done as normative target; implementation pending |
| SDL3 frontend architecture | Done |
| Performance baseline | Done |
| Workstream plan | Done |
| Protocol schema examples | Done (adapter-only) |
| User runbook | Done for current bounded smoke scope; update with each runtime milestone |
| Output-proto runtime bridge and first-frame task split | Done as normative design; implementation gated by the host extension contract |
| Troubleshooting guide | Pending final runtime/interactive milestone |
| Final capability status report | Pending W12/W16 |

## 6. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Emacs terminal ABI is broader than expected | Integration churn | Implement in stages; keep stubs explicit; differential tests |
| Zig/C ABI mapping is error-prone | Crash/security | Opaque pointers, minimal seam, fuzzing, three-pass review |
| Redisplay hook capture misses state | Wrong UI | Full hook inventory and PGTK/TTY differential tests |
| Font/shaping ownership becomes blurred | Incompatible rendering | Core metrics authoritative; frontend never reflow |
| Slow frontend stalls Emacs | Unusable editor | Coalescable frames and nonblocking transport |
| GPU device loss | Frontend crash | Rebuild renderer, full resync, software fallback |
| Resource cache divergence | Missing/stale UI | Generation checks, resource requests, snapshot fallback |
| Widget semantics leak into frontend | Compatibility break | Core owns model; frontend only renders/results |
| Performance work changes semantics | Hidden bugs | Correctness tests gate every optimization |

## 7. Definition of done

The overall objective is done only when:

1. All W0–W16 acceptance gates pass.
2. Every code workstream has completed a three-pass review cycle.
3. Real SDL3 opens and operates an Emacs frame.
4. Existing default and PGTK builds remain green.
5. EUP interface/protocol tables match implementation.
6. Capability matrix matches implementation.
7. Performance targets have machine-readable evidence.
8. Replay, conformance, fuzz, and smoke tests pass.
9. Documentation includes final status and known limitations.
10. No known path allows frontend failure to crash or stall Emacs.
