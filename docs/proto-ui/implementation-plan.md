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
| Resource model | Bounded identity, payload-cache/eviction, request/evict, string/face/font/image define-data-delete, snapshot restore, and bounded live file-backed XBM menu payload; redisplay-owned capture, recovery activation, and full resource parity pending |
| SDL3 frontend | Partial: EUP replay/live rendering, renderer tiers, damage classes, bounded facts, ASCII/key-v2/text/pointer/wheel/clipboard/selection/DND bridges, Unicode font cache, face/font/image resources, menu/toolbar/dialog/scrollbar state and bounded interactions, and EPXL recovery; no redisplay streaming, full keyboard/keymap/IME input, production frame ownership, or PGTK parity |
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
| Protocol coverage manifest | Implemented for all 165 assigned EUP IDs: 165 implemented codecs, 0 partial, and 0 planned; prevents an unclassified or overclaimed protocol table |
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
| P12-prep cursor update | Implemented dedicated cursor codec, Scene owner/geometry validation, bounded cursor styles, and SDL render evidence; IME-coupled caret and redisplay cursor semantics pending |
| P14-prep continuous capture generations | Implemented monotonic host-capture reuse from `captured` to `capturing`, atomic observation reset, stale-generation rejection, monotonic encoded/accepted `FRAME_UPDATE` identity, host-flush-bound `FLUSH` emission, and frame-lifetime render hints; no real Emacs host |
| P15-prep terminal runtime service | Implemented `proto-ui-terminal-service` for fake-host create/activate/drain/delete orchestration with no-reuse registry IDs, drain retry, rollback-pending cleanup, and strict identity validation; no Emacs terminal linkage/registration |
| P16-prep host adapter selection | Implemented the versioned pure-SDL3 `output_proto` candidate as selected by the approved, metadata-complete R7 decision; machine-readable gate records no activation, linkage, registration, or runtime |
| P17-prep runtime activation contract | Implemented a selection-gated controller plus explicit activation/rollback sequences; current gate is blocked without linkage/registration; no registration or runtime |
| P21-prep R8 entry readiness | Implemented a machine-readable blocked-entry manifest with eight readiness requirements, state-aware linkage/registration evidence, inherited-source audit, rollback-order audit, and opt-in negative launch gate |
| P22-prep R8 adapter linkage | Implemented a fail-closed host-audit candidate shared library, exported-ABI probe, canonical ABI/table inventory hash, build artifact provenance, planned default injection, opt-in target-specific static temacs linkage, deterministic ELF symbol audit, and `linked_not_registered` state |
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












| P2 R7 registration proposal | Implemented as ready-for-review policy artifact; R7 decision is approved, while terminal registration and runtime remain blocked |


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
| W8h-h SDL3 committed Unicode input lifecycle | Approved |
| W18 SDL3 interactive completion | In progress; current bridge aggregate gate passes, manual usable-session and pure-runtime gates pending |
| W9g2 bounded viewport facts | Approved |
| W10b-b2a bounded glyph-atlas policy | Approved |
| W10c-a damage classification baseline | Approved |
| W10c-b cursor-only clipped redraw | Approved |
| W10c-c bounded text-region clipping | Approved |
| W10d bounded GLYPH_RUN debug fallback | Approved |
| W10e real-frame public-facts glyph marker | Approved |
| W10f explicit bounded glyph-run delete | Approved |
| W10g bounded UTF-8 SDL_ttf presentation | Reviewed |
| W10h bounded Unicode texture cache | Reviewed |
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
| W12l-a R7 reviewer packet | Approved; policy-only approval is recorded, without runtime |
| W12m R8 entry-readiness manifest and negative gate | Approved; R8 entry remains blocked |
| W12n-a R8 target-specific adapter link | Approved; native-glibc opt-in link is audited as `linked_not_registered` |
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
zig build -Dproto-ui=true -Dproto-ui-runtime=true -Dsdl3-frontend=true proto-ui-tpe-input
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
3. A canonical-table test pins the 165 assigned IDs from the normative
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
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-key-modifier-smoke --summary all
```

`sdl3-key-modifier-smoke` extends the observed subset to Ctrl-F, Alt-F, and
Ctrl-B.  The Emacs-owned publisher maps these exact modifier/scancode records to
public motion commands and the smoke asserts the final public cursor fact.  This
is still a bounded compatibility subset, not general keymap execution.

### W8h-c — Bounded canonical key command execution (reviewed)

Goal: replace the hardcoded modifier/scancode command cases with bounded
canonical Emacs key descriptions on the same negotiated full-key v2 transport
without claiming full keyboard compatibility or runtime activation.

Implemented:

1. `input.key_command_v1` is a separate optional capability. The wire codec
   remains `KEY_EVENT` v2; the command field is an adapter-owned JSON
   extension and no command descriptor is emitted unless the effective set
   contains both `input.key_full_v2` and `input.key_command_v1`.
2. Zig maps only a closed SDL whitelist to bounded Emacs key descriptions:
   letter/digit scancodes, Return, Escape, Backspace, Tab, Space, arrows,
   Home/End, PageUp/PageDown, Insert/Delete, and F1-F24. Unknown logical
   names, non-ASCII text, lock-only behavior, release, likely text-producing
   shifted/unmodified printable events, and events with `TEXT_INPUT` bytes
   remain observation-only. This slice leaves quit/prefix entry points (`ESC`,
   `C-g`, `C-]`, `C-u`, `C-x`, `M-x`) observation-only so it cannot enter an
   interactive prefix sequence while a publisher loop is waiting.
3. Command descriptions fold C/M/s/H modifiers into canonical prefixes,
   cap descriptions at 32 bytes, and base64-encode them in JSON. The Zig side
   does not evaluate Elisp.
4. Emacs validates JSON schema/state, execution marker, base64/UTF-8, length,
   and a conservative key-description character set, then parses exactly one
   key event before `execute-kbd-macro`. Execution failures are contained and
   do not become arbitrary Elisp evaluation.
5. This is degraded bounded keyboard-command compatibility. Full keymap,
   minor-mode, prefix, keyboard-quit, session, IME, and `output_proto`/runtime
   registration parity remain pending. Evidence is `sdl3-key-modifier-smoke`;
   both required smokes fail closed when the capability is absent.

### W8h-d — Bounded `C-x` window commands and split observation (approved)

Goal: exercise a real Emacs window-layout command from the SDL3 bridge without
forwarding arbitrary prefix sequences or claiming general keymap parity.

1. Add optional `input.composite_key_command_v1`.  It is negotiated only when
   the effective set also contains `input.key_full_v2` and
   `input.key_command_v1`.
2. Recognize `C-x` locally as a pending prefix and translate only the next
   press if it is one of the closed suffix whitelist `1`, `2`, `3`, or `o`.
   Emit one bounded canonical description (`C-x 1`, `C-x 2`, `C-x 3`, or
   `C-x o`); never send a bare `C-x` command to Emacs.
3. Let Emacs validate the descriptor, parse at most two key events, enforce the
   same four-command whitelist, and execute it with `execute-kbd-macro`.
4. Fix the public-facts JSON bridge to preserve non-selected window booleans as
   JSON `false` and use `json-encode` for adapter-produced false values; parsed
   native facts and malformed input artifacts fail closed without killing the
   publisher loop.
5. Clip the facts fallback row layout and per-window text rows to the emitted
   window height so a short split window has only positive-height rows that fit
   its owner.
6. Add `sdl3-emacs-window-split-smoke`: require both capabilities, send
   `C-x` then `2`, fail closed unless a subsequent authoritative frame exposes
   at least two live windows and rows, and render the split scene.

Non-goals: no arbitrary two-key sequences, interactive prefix state, keyboard
quit, minor-mode or keymap parity, IME, hierarchical redisplay window trees, or
`output_proto` runtime activation.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-split-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-key-modifier-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-key-v2-smoke --summary all
```

### W8h-e — Horizontal split navigation and queued command drain (in review)

Goal: prove that two side-by-side live Emacs windows can be selected and edited
through the bounded command bridge while preserving one-in-flight wire order.

1. Add `sdl3-emacs-window-navigation-smoke` using only the existing exact
   `C-x 3` and `C-x o` whitelist entries followed by bounded ASCII `Z`.
2. Require ASCII text, full-key, single-command, and composite-command
   capabilities before queuing any navigation intent.
3. Assert a two-window horizontal layout with one window at x=0, one at x>0,
   equal heights, and positive widths.
4. Assert the active cursor is in the right window at column 8 after `C-x o`
   and insertion, and that the selected window's first visible line begins with
   `Z`. Both windows share the same buffer, so both observe the inserted text.
5. In this smoke only, drain queued intents after the preceding intent's ACK
   when a frame update arrives, even when a suppressed prefix causes no Emacs
   fact change. This prevents a local `C-x` half-command from stalling the next
   whitelisted suffix while preserving one-in-flight EPXL ordering. ACK-loss
   retry still keeps the pending intent and remaining queue in order.

Non-goals: no arbitrary prefix chains, keyboard quit, window deletion in this
smoke, general keymap execution, IME, redisplay-owned hierarchy, or
`output_proto` activation.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-navigation-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-split-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-key-modifier-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-key-v2-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

### W8h-f — Split-edit-restore lifecycle (approved)

Goal: prove that a selected split window can be edited and then restored to a
single live window while retaining the selected buffer and point.

1. Add `sdl3-emacs-window-restore-smoke` using the existing exact whitelist:
   `C-x 3`, `C-x o`, bounded ASCII `Z`, then `C-x 1`.
2. Require the same bounded ASCII/full-key/single-command/composite-command
   capability set as navigation.
3. After the split/select/edit sequence, execute `C-x 1` and fail closed unless
   exactly one live window remains.
4. Assert that the remaining window is at x=0 with positive width, remains the
   selected cursor owner at column 8, and still renders the inserted `Z`.
5. First observe the intermediate two-window evidence: side-by-side live
   windows, the selected right-window cursor at column 8, and visible `Z`.
   Queue `C-x 1` only after that observation. Reuse the bounded queued-intent
   drain for the two prefix commands; no arbitrary prefix, keymap, or runtime
   activation support is introduced.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-navigation-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-restore-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-key-modifier-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

### W8h-g — Split-window pointer selection (approved)

Goal: make bounded left-click behavior window-aware in split Emacs frames
without allowing the frontend to select windows or own pointer semantics.

1. Add a publisher-owned pixel hit test over `window-pixel-edges` for live
   windows. A bounded left press/drag/release maps frame-relative SDL
   coordinates to the clicked Emacs window and window-local coordinates.
2. Select only the clicked live window with `norecord`; never let frontend
   state directly choose the Emacs window.
3. Keep the exact accepted input subset: left button, single click, no
   modifiers, and press/drag/release. Other buttons, modifier combinations,
   and out-of-frame coordinates remain outside this slice.
4. Add `sdl3-emacs-window-pointer-select-smoke`: split with `C-x 3`, click the
   right window, insert bounded ASCII `Z`, and fail closed unless both live
   windows, right-window selection, cursor column 8, and shared-buffer text are
   observed.

Non-goals: no general mouse model, right-button support, X-button support,
modifier combinations, popup menus, drag replacement, arbitrary keymaps, or
`output_proto` activation.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-pointer-select-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-navigation-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-v2-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

### W8h-h — SDL3 committed Unicode input lifecycle (approved)

Goal: prove that one smoke-seeded SDL committed-text event reaches Emacs through
the existing authenticated Unicode path without adding an IME stack or
transport.

1. Start SDL text input for the interactive real window and stop it on focus
   loss and shutdown. Focus gain restarts it.
2. Project the active Scene cursor owner into an SDL text-input area. Refresh
   the area when authoritative cursor/window geometry changes.
3. Poll one bounded UTF-8 `SDL_EVENT_TEXT_INPUT` commit (`你好`) through the
   SDL event queue—never `pushText` directly—validate it with the existing
   negotiated text policy, and enqueue it in the existing `DeliveryJournal`.
   Reuse `TEXT_INPUT`, one-in-flight EPXL ACKs, Emacs application, facts
   refresh, and Unicode rendering.
4. Add `sdl3-ime-commit-smoke`. It requires all three capabilities, exact
   committed text visibility, refreshed frame evidence, cursor-anchored input
   area refresh, and visible Unicode draws. Do not seed the smoke payload by
   calling `pushText` directly.

Non-goals: no OS-generated or IME-backend-acquired commit, composition,
candidates, preedit, surrounding-text deletion, complete IME lifecycle,
preedit UI change, runtime registration, `output_proto`, TP1, inherited
C/Lisp edits, or default build behavior change.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-ime-commit-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-window-pointer-select-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
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

### W9q — Bounded touch contact (approved)

Goal: add the smallest SDL3 platform-input slice for touch without a new wire
record or any multi-touch, gesture, pressure, or pen claim.

1. Add optional, negotiable, degraded `input.touch_bounded_v1`, evidenced by
   `sdl3-touch-tap-smoke`; it requires `input.pointer_v2` and the negotiation
   drops it from the effective set when that transport is absent.
2. Reuse the strict Pointer Event v2 record, delivery journal, EPXL ACK flow,
   and the existing public `posn-at-x-y` / `posn-point` mapping. Add no wire
   record and no new reverse-intent kind.
3. Convert one real `SDL_EVENT_FINGER_DOWN` / `FINGER_MOTION` / `FINGER_UP` /
   `FINGER_CANCELED` contact from SDL's window-normalized coordinates to a
   pixel and emit `press` / `drag` (left mask) / `release` / `cancel`; press
   and release carry `clicks=1`.
4. Reject non-finite or out-of-window normalized coordinates, a zero-sized
   window, unknown event types, and any modifier state before queue mutation.
   A second concurrent contact or an out-of-order phase is dropped because the
   journal admits exactly one active pointer session.
5. Wire the same translation into the live interactive EPXL event loop so a
   real contact reaches Emacs, not only the smoke harness.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-touch-tap-smoke --summary all
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

#### W10g — Bounded UTF-8 SDL_ttf presentation (reviewed)

Goal: make bounded non-ASCII public facts visible in SDL3 instead of silently
skipping them, while keeping the production glyph atlas/shaping path separate.

1. Add `render.unicode_text_v1` as an optional degraded capability and a
   renderer `UNICODE_TEXT` draw command with exact UTF-8 validation and the same
   120-byte text bound as the diagnostic ASCII path.
2. Build non-ASCII public-fact lines as Unicode draw commands; ASCII lines keep
   the existing debug renderer and explicit glyph runs keep priority.
3. Execute Unicode commands with SDL_ttf `TTF_RenderText_Blended`, create a
   blended SDL texture, honor its intrinsic texture size, and scale from logical
   scene coordinates to output pixels.
4. Select a font through `PROTO_UI_FONT`, bound `PROTO_UI_FONT_SIZE` to 8..72,
   and fall back to a small platform discovery list. Record executed Unicode
   draw counts separately from ASCII debug-text counters.
5. Extend the Unicode EPXL smoke to require the capability and fail closed when
   no font is available or the first full-frame presentation does not execute a
   Unicode draw.

Non-goals: no HarfBuzz shaping, BiDi reordering, Emacs font metrics, glyph
atlas integration, fallback chain parity, face/font resources, redisplay
ownership, inherited Emacs changes, or `output_proto` activation.

Acceptance:

```sh
zig fmt --check build.zig src/proto-ui/capability.zig src/proto-ui/renderer.zig tools/proto-ui-sdl3/main.zig
git diff --check
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

#### W10h — Bounded Unicode texture cache (reviewed)

Goal: remove repeated SDL_ttf rasterization and texture creation for unchanged
Unicode facts lines while keeping ownership strict and bounded.

1. Add a backend-neutral, bounded LRU text-texture cache keyed by renderer
   device identity, RGBA color, and up to 120 bytes of UTF-8 content.
2. Store opaque backend texture IDs and their intrinsic sizes; the SDL frontend
   supplies the texture destroyer. Matching-key replacement, eviction, and clear
   immediately destroy the replaced or evicted texture.
3. Reuse a texture when the next frame draws the same Unicode bytes and color to
   the same renderer; otherwise rasterize once, validate texture size, and insert
   it into the 64-entry cache.
4. Clear cached textures when a renderer is destroyed or SDL reports render
   target/device reset or loss.
5. Record lookups, hits, misses, inserts, updates, evictions, and destroys, and
   add cumulative `unicode_text_commands_total` renderer counters.
6. Make the Unicode smoke force one repeated full-frame presentation, require at
   least one miss and one hit, reject evictions in the bounded scenario, and
   emit machine-readable cache counters.

Non-goals: this is not a shaped glyph atlas, does not cache partial runs or font
fallback chains, does not use Emacs font metrics, and does not imply
`output_proto` or redisplay ownership.

Acceptance:

```sh
zig fmt --check src/proto-ui/root.zig src/proto-ui/text_cache.zig src/proto-ui/renderer.zig tools/proto-ui-sdl3/main.zig
git diff --check
test -z "$(git diff --name-only | grep -E '^src/.*\.c$|^lisp/.*\.el$' || true)"
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

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
and the approved policy-only host-registration decision contract; R8-R9 remain
unimplemented.  The boundary gate and documentation links remain green.

##### R2 evidence

R2 adds `src/proto-ui/runtime.zig` as the source-authoritative state,
`proto-ui-runtime-manifest` as the deterministic manifest step, and a required
nonzero boundary gate with reason
`runtime_host_linkage_or_registration_missing`.  The generated manifest records all five
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
evaluates Elisp or owns layout.  The source decision is `approved` with reviewer `Proto-UI Dedicated Review
Agent`, decision ID `R7:pure-sdl3-output-proto-terminal:2026-09-10`, timestamp
`2026-09-10T09:49:41Z`, and scope `policy_and_candidate_selection_only`.  The
runtime manifest remains fail closed with reason
`runtime_host_linkage_or_registration_missing`.  The default build has neither
linkage nor registration.  The explicit native-glibc link option provides the
first condition only; registration remains absent, so activation is still
forbidden.

##### R8 entry-readiness evidence

R8 readiness is machine-readable in `src/proto-ui/r8_readiness.zig` and
`zig-out/proto-ui/r8_readiness.json`.  The source records eight required
conditions: approved R7, target-specific linkage, explicit registration,
isolation, callback conformance, crash containment, fail-closed runtime, and
rollback/disable.  It records the approved R7 policy decision, asserts an empty
inherited-source edit set, keeps activation/runtime/default enablement false,
and validates the rollback order.  `proto-ui-r8-readiness` accepts the blocked
state as a valid audit result.

W12n adds `r8_adapter_linkage.zig`, the host-audit candidate shared artifact
`proto-ui-runtime-host-adapter`, and `r8_adapter_linkage.json`, pinning the
PureRuntimeHostV1 ABI/table inventory.  Default manifests say
`prepared_not_linked`.  W12n-a adds the explicit
`-Dproto-ui-runtime=true` native Linux glibc path: build.zig creates a separate
target-specific static candidate, links it into temacs, forces the adapter ABI
symbol so the linker includes the selected archive member, and
`proto-ui-r8-link` proves that symbol in the resulting ELF.  The state becomes
`linked_not_registered`; R8 remains blocked because the adapter is never called,
never initialized at load time, and no `output_proto` terminal is registered.
The opt-in `-Dr8-entry-gate=true proto-ui-r8-readiness` form is the negative
launch gate: it fails with `r8_first_frame_and_redisplay_missing`
until registration and all remaining source conditions are ready.

##### R8-b registration-seam design and opt-in headless TPE slice

R8-b defines the Terminal Provider Extension (TPE) in
[`registration-seam.md`](registration-seam.md).  TPE separates one generic
core-side provider contract from all Proto-UI terminal behavior in a
provider-owned adapter.  It specifies a linked provider manifest,
provider/core ABI tables, GC-safe opaque provider storage, exact activation
and reverse rollback order, first real `window-system=proto` frame checks,
performance budgets, and the TP0-TP10 work split.

Production TPE now has one narrow opt-in exception under
`-Dproto-ui-runtime=true`: a generic `output_provider` terminal classification,
opaque provider slots, and explicit environment-selected headless registration.
It adds no per-backend `output_proto` cases, does not alias PGTK/TTY, does not
initialize at load time, and is absent from default builds.  The default/default
symbol audit and `proto-ui-tpe-headless` live gate are the isolation and
behavior evidence.  `proto-ui-tpe-core` separately pins the owned registry ABI
and lifecycle mechanics.  Output-method aliasing, startup constructors,
dynamic-module access to internal symbols, and symbol interposition remain
forbidden.

##### R8-c TP2 registration-policy conformance (adapter-only)

`proto-ui-tpe-registration` adds `src/proto-ui/tpe_registration.zig` and a
deterministic `tpe_registration_policy.json` gate.  The fake-core policy
witness validates immutable provider identity `proto`, the six required capability
flags, an empty inherited-source edit set, exact PureRuntimeHostV1 ABI v1
shape (64-byte aggregate table, five groups, 27 operations), explicit forward
registration states, duplicate/invalid-transition rejection, failure
quarantine, generation retention, and idempotent reverse rollback order.

The TP2 policy manifest itself remains adapter-only and reports
`runtime_available=false`; it does not describe the separate live TP1 slice.
The default build remains disabled.  With explicit
`-Dproto-ui-runtime=true`, `proto-ui-tpe-headless` registers one generic
`output_provider` terminal, verifies `(terminal-live-p ...)=proto`, and cleans
it up.  This is not an SDL frame: R8 remains blocked until TP4/TP5 provide the
real frame and redisplay-owned capture.

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

Goal: measure the documented adapter and renderer baselines; performance
improvement requires a separate end-to-end comparison.

Status: W14-a, W14-b, W14-c renderer-proxy, and W14-d EPXL round-trip work are
complete; full W14
parity remains partial.  `proto-ui-bench` is an opt-in, adapter-only
ReleaseFast baseline that installs `zig-out/proto-ui/benchmark.json`.
It covers EUP `FRAME_UPDATE` encoding, envelope/payload decode and validation,
fresh `frontend.Scene.apply`, atomic `CaptureService` encoding, and bounded
memory-sink sending on deterministic 960x600, 30-row fixtures. It reports
monotonic latency percentiles, throughput, byte volume, allocation counts,
iteration/warmup counts, build mode, and EUP version as machine-readable JSON.
It intentionally remains outside `proto-ui-boundary` so timing cannot make the
compatibility gate flaky.  W14-b adds `sdl3-renderer-bench`, a host-side SDL3
renderer-call benchmark for the real draw list plus `SDL_RenderPresent`: a
deterministic 960x600 replay scene measures bounded full-draw and unchanged-
skip CPU wall-clock latency, FPS, commands/frame, and presented/skipped frames.
It records the selected renderer and build mode and is opt-in; its result only
proves the run/report, not a host-independent regression threshold.  W14-c keeps
those baselines and adds three deterministic renderer calls with schema v2:
`typing_proxy` alternates the visible replay cursor, `scroll_proxy` alternates a
visible replay row offset, and `resize_proxy` synchronously alternates two
hidden-window sizes with forced geometry invalidation.  Each phase has bounded
iterations, nearest-rank latency, FPS, command/frame totals, and explicit
`workload_kind:"renderer_proxy"` evidence; the benchmark restores the scene and
original window state afterward.  These are frontend renderer-call workload
proxies only, not real typing/scroll/resize, Emacs input, core redisplay,
end-to-end Emacs work, GPU timestamps, PGTK comparison, or host-independent
regression evidence.  W14-d adds `sdl3-epxl-roundtrip-bench`: it starts the
owned public-facts publisher, moves the point off `point-min`, then alternates
one backspace and one bounded ASCII insertion at window point, one intent in
flight per step, and installs
`zig-out/proto-ui/sdl3-epxl-roundtrip-benchmark.json` with nearest-rank
intent-to-control-ACK and intent-to-next-`FRAME_UPDATE` latency percentiles,
submitted/acked counts, and `input_lost`.  Its `--visible-edit-publisher`
profile (enabled only by `--emacs-epxl-bench`) applies both actions at window
point so every step produces a real fact change and frame update.  It is a
Debug-build, local-socket bounded public-facts-bridge diagnostic: it does not
run core redisplay, renderer present, real typing in a normal buffer, GPU
timestamps, PGTK comparison, end-to-end latency, or host-independent
regression.  Frame creation, real typing,
scroll, resize, faces, fonts, images, widgets, multi-frame, comprehensive
renderer tiers, and optimization work remain W14 follow-up work.

Tasks:

1. Add machine-readable benchmark harness. *(W14-a covers the adapter memory-transport baseline.)*
2. Benchmark frame creation, typing, scroll, resize, faces, fonts, images, widgets, and multi-frame. *(W14-b covers a bounded SDL3 full-draw/unchanged-skip renderer baseline; W14-c covers deterministic renderer-call typing/scroll/resize proxies; full backend workloads remain pending, and resize geometry setup is outside the timed renderer call.)*
3. Add allocation counters. *(W14-a records measurable per-operation allocation counts.)*
4. Add bandwidth counters. *(W14-a records bytes/op and MiB/s for adapter paths.)*
5. Add latency percentiles. *(W14-a records p50/p95/p99 and mean; W14-b/W14-c reuse nearest-rank summaries for SDL renderer-call paths; W14-d records nearest-rank ACK and next-frame-update percentiles for the bounded EPXL edit path.)*
6. Tune damage merging.
7. Tune glyph atlas.
8. Tune transport slab reuse.
9. Compare software, GPU basic, and GPU advanced tiers. *(W14-b records the selected tier/name for the real SDL3 path; full tier comparison pending.)*

Acceptance:

```sh
zig build -Doptimize=ReleaseFast -Dproto-ui=true proto-ui-bench --summary all
cat zig-out/proto-ui/benchmark.json
zig build -Doptimize=ReleaseFast -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-bench --summary all
cat zig-out/proto-ui/sdl3-renderer-benchmark.json
```

The W14-a baseline acceptance is the first command; W14-b adds the SDL3
renderer command.  Each `result` proves only that the requested operations
completed and the report values validated. Full W14 acceptance additionally
requires the remaining workloads to meet `performance.md` targets and retain
comparative evidence.

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
current counts are 165 implemented codecs, 0 partial, and 0 planned.

W8h-i advances keyboard compatibility with `input.keymap_loop_v1`: reverse input
is serialized, Emacs accumulates bounded canonical prefix sequences, active
keymaps resolve commands, and unknown complete sequences clear pending state.
This is compatibility progress through the current diagnostic bridge, not pure
`output_proto` runtime parity.
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
strict host identity validation.  This is orchestration readiness only; adapter
linkage, Emacs terminal registration, and runtime enablement remain absent.
The `proto-ui-terminal-service` gate emits deterministic machine-readable
evidence and is part of `proto-ui-boundary`; its report still records
`emacs_registered=false` and `runtime_available=false`.
P16 host-adapter selection preparation names the pure-SDL3 `output_proto`
candidate and records its policy in one versioned manifest.  The candidate must
use ABI v1, modify no inherited source, forbid PGTK/TTY runtime fallback and
frontend Elisp/layout ownership, and require every callback group.  The approved
metadata-complete R7 decision marks the candidate selected.  Selection never
implies activation: the current source and gate remain unlinked, registered=false, and
runtime_available=false.
P17 activation preparation adds a selection-gated controller and an explicit
seven-step activation sequence with the reverse rollback order.  The selected
repository candidate is unlinked, so the controller rejects activation before
any Emacs host callback and the manifest reports
`blocked_by_linkage_or_registration`.  Unit conformance uses a linked fake-host
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
RGBA upload bytes; redisplay-owned scroll capture remains pending.
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
P64 IME-candidate preparation integrates `IME_CANDIDATE_UPDATE` and `IME_CANCEL` into `Scene`.  A focused live context stores selected index, candidate/page counts, owner-relative placement, and a bounded selected label; zero-count updates and cancel clear state atomically.  The SDL diagnostic overlay renders selected metadata and ASCII labels only.  Full candidate lists, Unicode label rendering, platform IME, selection input, and commit application remain pending.  P65 IME-commit preparation adds bounded `IME_COMMIT` Scene state for focused live contexts; a valid commit records UTF-8 text, clears preedit/candidates, and reset/detach remove it.  Platform IME input and core buffer application remain pending.  P66 Emacs title publication adds a bounded public `title` fact to the authenticated publisher snapshot.  When present, the adapter emits a generation-qualified string resource plus `FRAME_TITLE`, the frontend applies contiguous sequencing, and SDL sets its diagnostic window title.  A later snapshot that omits `title` suppresses title transport and leaves the prior diagnostic title unchanged.  This is public title observation only; complete `frame-parameter` semantics, renaming, icon titles, and PGTK parity remain pending.  P68 selection-ownership preparation adds bounded primary owner set/clear/lost Scene state with deep-copied target offers, strict newer-generation replacement, and generation-matched clear/lost cleanup.  Platform selection ownership and request/data/error transfer remain pending.  P69 selection-transfer preparation adds bounded request/data/error Scene state: a request must match the live primary generation and an offered target; data/error must match its request ID and generation, storing up to 4096 bytes or a bounded UTF-8 failure.  Platform negotiation and Emacs/core transfer application remain pending.  P70 monitor-change preparation maps SDL display/scale changes to frontend-local `FRAME_MONITOR` state, querying real display bounds and asserting the refresh in `sdl3-monitor-change-smoke`.  EUP event streaming, redisplay adaptation, and Emacs frame migration remain pending.  P71 system-theme preparation adds negotiated `platform.theme_events`, SDL theme capture, bounded `THEME_EVENT` EPXL delivery, and Emacs-owned recording of delivered dark/light appearance.  Full theme refresh, accessibility preferences, and face remapping remain pending.  P72 monitor/DPI transport preparation adds negotiated `platform.monitor_events` and `platform.dpi_events`: real SDL current-display changes encode current monitor geometry/content scale and window DPI observations, deliver `MONITOR_EVENT` and `DPI_EVENT` over bounded EPXL, and the publisher records the bounded observations.  Monitor migration, frame geometry/redisplay adaptation, and complete display parity remain pending.  P73 primary-selection preparation negotiates bounded `clipboard.primary_selection_bounded`, captures bounded UTF-8 text through SDL PRIMARY, proves an Emacs publisher-to-SDL-to-Emacs round trip via Shift+Insert, and keeps selection ownership/target negotiation/multi-format transfer pending.  P74 focus-roundtrip preparation carries negotiated SDL focus gain/loss through EPXL, records the public focused fact on one Emacs frame, emits `FRAME_FOCUS` when it changes, and exercises gain-then-loss in `sdl3-focus-roundtrip-smoke`; OS focus control and multi-frame focus parity remain pending.  P75 bounded-resize roundtrip applies negotiated SDL resize intents through public `set-frame-size` in the owned publisher and verifies ordered request delivery plus publisher acknowledgement in `sdl3-window-resize-roundtrip-smoke`; exact WM geometry, other window requests, and multi-frame runtime control remain pending.  P76 bounded-move roundtrip applies negotiated SDL move intents through public `set-frame-position` in the owned publisher and verifies ordered request delivery plus acknowledgement in `sdl3-window-move-roundtrip-smoke`; exact WM placement, other window requests, and multi-frame runtime control remain pending.  P77 bounded-maximize roundtrip applies negotiated SDL maximize intents through Emacs's public `fullscreen` frame parameter, verifies parameter acceptance before acknowledgement evidence, binds delivery to the smoke SDL window, and exercises delivery in `sdl3-window-maximize-roundtrip-smoke`; exact geometry, actual WM completion, other window requests, and multi-frame runtime control remain pending.  P78 bounded-fullscreen roundtrip injects a validated `WINDOW_REQUEST.fullscreen`, binds it to the smoke SDL window, applies Emacs's public `fullscreen fullboth` parameter, verifies parameter acceptance and acknowledgement evidence in `sdl3-window-fullscreen-roundtrip-smoke`; exact geometry, actual WM completion, other window requests, and multi-frame runtime control remain pending.  P79 primary-ownership preparation negotiates `selection.primary_ownership_v1`, sends a bounded primary `SELECTION_OWNER_SET` with UTF8_STRING/STRING offers, clears the same generation, and verifies both Scene transitions in `sdl3-selection-owner-smoke`; platform ownership, target conversion, and Emacs/core transfer application remain pending.  P80 selection-transfer preparation negotiates `selection.primary_transfer_v1` (requiring ownership), sends a bounded UTF8_STRING request and completed data record for request 9001, verifies waiting/completed Scene states, publishes that data through SDL PRIMARY only when the owner has `export_to_platform`, adds a STRING request 9002 and matched `conversion_failed` error transition, then releases PRIMARY and clears generation 1 in `sdl3-selection-transfer-smoke`; external request service, target conversion, and Emacs/core application remain pending.  P81 platform-ownership binding extends the same smoke so an `export_to_platform` owner claims bounded text through SDL PRIMARY, verifies ownership, then releases it on matching clear; external target requests, conversion, and Emacs/core application remain pending.  P82 owner-loss/replacement preparation transports `owner_cancelled` loss for generation 1, claims a replacement generation 2 through SDL PRIMARY, clears generation 2, and verifies every Scene/platform transition in `sdl3-selection-owner-smoke`; asynchronous external ownership races and full replacement parity remain pending.  P83 minimize/restore roundtrip delivers ordered `WINDOW_REQUEST` intents through negotiated EPXL, invokes public `iconify-frame` / `make-frame-visible` in the owned publisher, inserts acknowledgement markers, and verifies ordered request delivery plus markers in `sdl3-window-minimize-restore-smoke`; actual WM minimization and complete frame-visibility parity remain pending.
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
the selected Emacs host adapter is not linked and runtime remains fail-closed.
P1 readiness adds `proto-ui-pgtk-parity-plan`: all 48 differential cases remain
planned and the aggregate parity status remains `not_implemented`.
P2 readiness adds `proto-ui-r7-proposal`: the generated proposal is
`approved` for policy and candidate selection only, while the runtime remains
fail-closed without linkage/registration.  Acceptance is defined by the P0-P10 milestones in the parity
document and by the W16 final scenario.  The distinguishing R8 evidence is a real frame whose
`window-system` is `proto`, whose visible surface is SDL3-owned, and whose
frame, redisplay, resource, input, and desktop-integration paths require no
GDK/GTK initialization.

P84 popup-menu interaction preparation adds `Scene.menuPopupBounds` as the single geometry source shared by the SDL popup draw path and a new pointer hit test, plus `Scene.hitTestOpenMenu`.  While a popup is open and `widget.menu_result_v1` is negotiated, a primary press on a selectable command/checkbox/radio row reports `MENU_RESULT` with the exact menu/generation/item/window/frame identity, a press outside the popup reports `MENU_CANCEL(user)`, and `Escape` reports `MENU_CANCEL(escape)`; separator, submenu, disabled, and padding rows report nothing, and the matching release is consumed so the click never also becomes a text pointer press.  `sdl3-menu-hit-smoke` drives one open model through the shared geometry and proves the selected identity, the outside dismissal, the Escape cancellation, and the inert separator.  The frontend never enables, disables, reorders, reflows, or executes an item, and no keyboard menu navigation, streaming hover highlight, submenu traversal, or Emacs command execution is claimed.
P85 tool-bar interaction preparation adds `Scene.toolbarLayout` as the single geometry source shared by the SDL tool-bar draw path and `Scene.hitTestToolbar`, which also fixes tool-bar items being drawn at an absolute x that ignored the owning window origin.  Visible button and toggle items occupy slots (separators advance 2 logical pixels, spaces 12); only a visible enabled button or toggle is selectable.  With `widget.toolbar_click_v1` negotiated, a primary press on a selectable item reports `TOOLBAR_CLICK(press)` and is consumed, the matching release reports `TOOLBAR_CLICK(release)` for the same item while its toolbar generation is still live, and a press whose generation was replaced is dropped; presses on a separator, a space, a disabled item, or outside the row fall through to the ordinary pointer path.  `sdl3-toolbar-hit-smoke` drives one model through the shared layout and proves the press/release pair, the item identity, the inert separator, and the stale-generation drop.  The frontend never executes an item or mutates the model, and no icon rendering, overflow policy, orientation, keyboard activation, or Emacs command execution is claimed.
P86 dialog-interaction preparation adds `Scene.dialogLayout` as the single geometry source shared by the SDL dialog draw path and `Scene.hitTestDialog`.  The backend-owned `buttons` policy mask is presented in a canonical order (OK, Cancel, Yes, No, Retry, Close), right-aligned inside the box and shrunk uniformly when a wide policy would otherwise overflow so every presented button stays inside the box and remains clickable; the draw path now renders that button row.  With `widget.dialog_result_v1` negotiated, a press on a standard button reports `DIALOG_RESULT` with the exact dialog/generation/window/frame identity and no input text, a press elsewhere inside the box is consumed without a result, a press outside the box falls through to the ordinary pointer path, and `Escape` reports cancel when the policy offers one (otherwise close).  `sdl3-dialog-hit-smoke` drives one dialog through the shared layout and proves the button identity, the consumed body click, the outside fall-through, and the Escape dismissal.  Text input fields, custom or unicode button labels, file/color/font dialogs, and Emacs callback dispatch are not claimed.
P87 bounded drag-and-drop receive preparation adds negotiable degraded `dnd.bounded_v1` and the first SDL drop mapping.  A bounded frontend tracker follows SDL's ordered begin/position/file-or-text/complete sequence, accumulates one offer (`text/plain` for `SDL_EVENT_DROP_TEXT`, `text/uri-list` for `SDL_EVENT_DROP_FILE`) plus at most 256 payload bytes, and on completion enqueues the exact `DND_ENTER`/`DND_DROP`/`DND_DATA` triple through the authenticated EPXL journal with a synthesized copy action, because SDL does not expose the drag source's action policy.  The frontend reports only; the owned publisher validates and applies the bounded payload, and the runner never opens a dropped file.  An oversized payload, an unnegotiated peer, and an event for another window produce no intent.  `sdl3-dnd-drop-smoke` seeds one real SDL drop sequence, requires the negotiated capability, and requires the republished facts to show the applied bounded text.  Drag-out, MIME negotiation, multiple offers or files, drag positions, drag cancel, and any general DND parity are not claimed.
P88 popup-navigation preparation adds `Scene.menuRows`, `Scene.menuMoveHighlight`, and `Scene.menuHighlightSlot` over the existing single popup geometry source, plus a frontend-owned highlight cursor `Scene.menu_highlight_item` that is presentation state only, is never encoded into EUP, and is cleared whenever the popup opens or closes.  Pointer motion moves the cursor to the selectable row under the pointer and is consumed so it cannot become a text hover/drag sample; Up/Down move the cursor to the previous/next selectable row without wrapping, skipping separators, submenus, and disabled rows; Enter chooses the highlighted row as `MENU_RESULT`.  Every cursor change is reported as exactly one `MENU_HOVER` transition — a `leave` with no item identity followed by an `enter` for the new row, carrying the pointer position for hover and the row origin for the keyboard — and the draw path renders the highlighted row.  `sdl3-menu-hit-smoke` proves the three-step hover sequence, the separator skip, the keyboard walk, and the Enter selection.  Streaming `move` phases, submenu traversal, backend-driven highlight dispatch, and Emacs command execution are not claimed.
P89 vertical-scrollbar interaction preparation adds `Scene.scrollbarLayout` and `Scene.hitTestScrollbar` as the single geometry source shared by the SDL track/thumb draw path and pointer hit testing, and fixes the previous session leak in which a touched scrollbar kept treating every later motion as a drag.  A primary press on the thumb opens a relative drag session that reports pointer deltas; a press on the trough above or below the thumb reports one relative page (`delta = ∓viewport`) without opening a session; a press outside the track falls through to the ordinary pointer path; the matching release ends an active session, and a motion sample whose primary button is no longer held also ends it.  A scrollbar with nothing to scroll is not interactive, and the hit test resolves the owning window from the scroll state instead of assuming the first window.  `sdl3-scrollbar-smoke` drives one state through the shared geometry and proves the thumb rectangle, the drag delta, the session lifecycle, both page directions, and the outside fall-through.  Horizontal state, arrow-step geometry, dedicated `SCROLLBAR_EVENT` routing for these interactions, and Emacs dispatch are not claimed.
P90 bounded pen preparation adds negotiable degraded `input.pen_bounded_v1`, gated on `input.pointer_v2` and adding no wire record.  SDL reports pen positions in window coordinates (not normalized), so the frontend bounds the point directly and maps the pen tip to the strict Pointer v2 payload: `SDL_EVENT_PEN_DOWN` to `press`, a motion with the tip down to `drag`, a motion with the tip up to `motion` (the same air hover a mouse reports), and `SDL_EVENT_PEN_UP` to `release`, with `clicks=1` on press and release.  The eraser tip, barrel buttons, pressure/tilt axes, proximity events, out-of-window coordinates, and unknown event types produce no intent, and the same translation is wired into the live interactive EPXL loop.  `sdl3-pen-tap-smoke` seeds one synthetic sequence and proves the hover/press/drag/release order, the eraser rejection, and the bounded journal ordering.  Pressure, tilt, barrel buttons, drawing surfaces, and Emacs command dispatch are not claimed.
P91 popup item-state rendering makes the SDL popup row draw reflect the backend-owned menu model.  A checkbox or radio row reserves a leading marker slot, draws the selection marker only when the model's `selected` flag is set, and shifts its label past that slot; a row the model does not mark `enabled` is drawn with a dimmer label color; and a separator row draws no label at all, which also fixed a latent crash in which an open popup containing a separator failed the whole render pass because the draw list rejects empty text.  The frontend only reflects those flags and never enables, disables, or toggles an item.  `sdl3-menu-hit-smoke` now asserts the marker rectangle, the shifted checkbox label, the dimmed disabled label, and the bright enabled label alongside its hit-test, hover, keyboard-navigation, and Enter-selection evidence.  Submenu traversal, radio grouping semantics, item icons, and Emacs command execution are not claimed.
P92 tool-bar icon rendering makes a tool-bar slot draw the backend-owned image resource.  When an item references an `icon_image_id`/`icon_image_generation` pair that resolves to a complete image resource of exactly that generation, the slot draws that image through the existing draw-list image command; a missing, incomplete, or stale generation falls back to the text label rather than drawing a guessed icon, so the frontend never invents an icon, never substitutes a different generation, and never keeps a deleted resource alive for the toolbar.  `sdl3-toolbar-hit-smoke` defines one 2x2 icon resource, asserts the exact icon rectangle and pixels for the live item, asserts the icon replaces that item's label, and asserts that an item referencing a stale generation still draws its text label.  Overflow, orientation, item text beside an icon, multi-resolution icon bundles, and Emacs command execution are not claimed.
P93 bounded prompt-field preparation adds `Scene.dialogAppendInput`, `Scene.dialogBackspace`, `Scene.dialogInput`, and `Scene.dialogFieldRect` plus the frontend-local field state `Scene.dialog_text`/`dialog_text_len`, which is presentation/input state never encoded into EUP except inside the bounded `DIALOG_RESULT` text tail the user submits.  A prompt dialog whose box is tall enough shows a bounded ASCII field: while it is open the field owns SDL text input and Backspace, so those bytes never reach Emacs as buffer input; accepted bytes are limited to printable ASCII and to the 128-byte capacity that matches the result tail, and the field is cleared whenever the dialog opens, closes, or loses its owner window.  Both the standard-button press and the Escape dismissal carry the current field text in that tail.  `sdl3-dialog-hit-smoke` proves the field rectangle, the accepted text, the control/non-ASCII rejection, the rendered typed text, the capacity bound, and the text tail on the button and Escape paths.  Unicode field input, an explicit caret, custom or unicode button labels, file/color/font dialogs, and Emacs callback dispatch are not claimed.
P94 bounded drag-position feedback and idle-journal coalescing adds `DndPositionEvent` plus the `DND_POSITION` wire path (input event, `sendDeliveryEvent` encoding, publisher acceptance, and a bounded `dnd-position` artifact), and introduces a single `journalIdle` boundary used by every best-effort observation: idle v2 pointer hover, pen air hover, and drag position feedback are enqueued only when the bounded delivery journal has no in-flight intent and an empty queue, so continuous observation can never fill the queue and turn a fast pointer, pen hover, or a slow backend into a session failure.  Ordered press/drag/release and every payload report stay exact, while the previously rejected `DND_POSITION` message type is now accepted by the publisher instead of failing the session.  `sdl3-dnd-drop-smoke` seeds two positions and proves exactly one bounded position report is delivered (the later one is coalesced away while the journal is busy) while the drop payload still reaches Emacs and the republished facts show the applied text.  Drag-out, MIME negotiation, multiple offers or files, drag leave/cancel, and a request/data handshake are not claimed.
P95 window default-face text preparation makes the live text honor the face a window is bound to.  The bounded facts rows carry no per-line or per-run face, so a window with a live `WINDOW_FACE` binding draws its body text with that face's foreground, and falls back to the draw default when there is no binding, the generation is stale, or the face carries no foreground; the unicode text path uses the same color instead of its former hardcoded value.  A single `windowFaceForeground` helper resolves the binding so the fallback rule lives in one place.  `sdl3-face-text-smoke` builds one live frame with a body text line plus an explicit `FACE_DEFINE`/`WINDOW_FACE` pair and proves the default fallback, the face foreground, and that a replacement generation is honoured on the next frame.  Per-line faces, face merging, overlays, derived faces, shaped-text faces, and PGTK face parity are not claimed.
P96 live default-face publication extends the public-facts snapshot with optional bounded `foreground`/`background` `#rrggbb` values taken from the frame's real default face.  A literal `#rrggbb` attribute is passed through unchanged so the terminal color model cannot remap a color the frame already stated exactly, while a named attribute still resolves through `color-values`; an unusable or unspecified value is omitted so the frontend keeps its own draw default.  The adapter parses the pair, projects a generation-qualified `FACE_DEFINE` whose generation only advances when the reported colors change, and re-sends the per-window `WINDOW_FACE` binding after every `FRAME_UPDATE`, because an update is authoritative window state that replaces that binding.  Publisher shutdown is also made tolerant of a read-side close at the interactive smoke deadline, which previously surfaced as `PublisherFailed` when the extra face traffic shifted the close timing.  `sdl3-emacs-face-smoke` runs the owned publisher and requires the live SDL scene to own the reported face, bind the live window to it, and draw the body text with that foreground, sampling the binding while it holds.  Per-line faces, face merging, overlays, derived faces, shaped-text faces, and PGTK face parity are not claimed.
P97 bounded cursor-style preparation gives the opaque `CURSOR_UPDATE` v1 `cursor_kind` a frontend rendering interpretation through a single `drawCursor` helper.  Kinds 1/2/3 (and any unrecognised value, preserving the pre-style behaviour) draw the solid box/bar/horizontal bar whose shape already comes from the published cursor geometry; kind 4 draws a four-edge hollow outline; kind 5 draws a bottom-edge underline.  Every shape is emitted inside the cursor rectangle the backend validated, so a style can never widen the work beyond the validated cursor geometry, and the fill uses the owning window's live default-face foreground through the existing `windowFaceForeground` helper, falling back to the previous cursor color when no face is bound.  `sdl3-cursor-style-smoke` drives one `CURSOR_UPDATE` per kind and proves the fill counts per shape, the unknown-kind fallback, and the face-derived color.  Publishing Emacs's real `cursor-type`, blink state, per-window cursor faces, IME-coupled caret behavior, and redisplay-owned cursor semantics are not claimed.
P98 live cursor-type publication extends the public-facts snapshot with a bounded `cursor_kind` taken from the selected window's real `cursor-type` (`t`/`box`→1, `bar`→2, `hbar`→3, `hollow`→4, and any other value, including an unspecified one,→1) and threads it through `FrameFacts`/`SnapshotWire` into both cursor encoders, which previously hardcoded the solid box.  The publisher pins `hbar` under the smoke profile so the value is deterministic, and `sdl3-emacs-cursor-smoke` runs the owned publisher and requires the live SDL scene to own `cursor_kind` 3 and render the horizontal-bar shape alongside the ongoing frame updates.  Blink state, per-window cursor faces, IME-coupled caret behavior, and redisplay-owned cursor semantics are not claimed.
P99 live window scroll-state publication extends the public-facts snapshot with an optional bounded scroll-bar width, total buffer line count, and lines-above-window-start count per window state.  When the reported width is nonzero the adapter projects one `WINDOW_SCROLL_STATE` per such window, clamps the position into `content - viewport` so a window start past the bounded text can never produce an out-of-range record, and re-sends the state after every `FRAME_UPDATE` because an authoritative update replaces the table.  The publisher takes the content size and position from the real `(point-max)` line number and the real `window-start`, and only pins the track width under the smoke profile because a batch Emacs frame reports no scroll bars; `sdl3-emacs-scrollbar-smoke` requires the live SDL scene to sample a proportional thumb for a real 30-line buffer scrolled to line 11.  Horizontal state, arrow-step geometry, and core-owned scroll dispatch are not claimed.
P100 closes the live scrollbar loop in both directions.  The frontend's scrollbar policy previously compared raw SDL window coordinates against frame-logical geometry, so a scaled live window (a TTY frame's character grid scaled up to the SDL window) could hit the thumb but never open a drag session; it now converts once to frame-logical units before the hit test and before the drag tracker, and the motion path converts the same way so a drag delta is a logical unit.  On the producer side the publisher consumes a delivered `scroll-request`/`scrollbar-event` artifact and moves the named window's real `window-start` by the bounded line count (relative) or to the bounded line offset (absolute), keeping point inside the window afterwards; unknown kinds, axes, windows, and unbounded numbers are ignored rather than guessed.  `sdl3-emacs-scrollbar-interaction-smoke` presses the trough below the thumb and then drags the thumb through that path; the republished facts must show the real window scrolled from position 10 to 18 (one 8-line page) and then to 22 (a 4-unit drag clamped at the scroll range end).  Horizontal scroll, arrow-step geometry, non-line scroll units, and full core dispatch are not claimed.
P101 adds the horizontal scrollbar as a bounded mirror of the vertical one.  `WINDOW_SCROLL_STATE`'s second flag is `horizontal_visible`; the state's sizes are columns and its `track_width` is the bar thickness, `Scene` upserts one state per window *and orientation* so both bars coexist, and `horizontalScrollbarLayout`/`hitTestHorizontalScrollbar` mirror the vertical geometry source, with the track stopping where the window's vertical bar column begins so the corner stays unambiguous.  The drag tracker records its axis and reports `axis = horizontal` deltas; a horizontal trough press pages one viewport sideways.  The publisher reports the widest visible line and the real `window-hscroll` as that state and applies a delivered horizontal intent with `set-window-hscroll` (absolute position or bounded relative delta), while unknown kinds/axes/windows and unbounded numbers are still ignored.  `sdl3-scrollbar-smoke` proves both orientations' geometry, hit tests, drag deltas, page deltas, and the drawn thumb rectangles, and `sdl3-emacs-hscroll-smoke` drags the live thumb ten columns and requires the republished state to show the offset moving from 5 to 15.  Arrow-step geometry, sub-cell or pixel scroll units, and redisplay-owned scroll semantics are not claimed.
P102 publishes the real menu bar.  The owned publisher enumerates the frame's live `menu-bar-keymap` (the post-filter, display-ordered keymap), reads each item's label from its `menu-item` or prompt string, skips the fallback click handler and any label this bounded publisher cannot express (non-string, empty, over 64 bytes, non-printable, or beyond eight items), and reports the labels as a bounded facts array.  The adapter validates and owns that array and projects it as a `MENU_MODEL` whose depth-0 nodes are those items, sent only when the labels differ from the model already in the scene because the model survives an authoritative `FRAME_UPDATE`; the generation advances only on a real change.  The SDL draw path anchors that model as a menu-bar row at the frame origin, sizes each slot from its own label, and takes the strip height from the row the frame reserves above its window, so the backend keeps owning the labels and their order while the frontend only lays them out.  `sdl3-emacs-menu-bar-smoke` requires the live scene to own the real labels in order (File, Edit, Options, Buffers, Tools, Help) and the draw list to render each of them.  Menu opening, submenus, item enabling/filters, `MENU_RESULT` dispatch, and command execution are not claimed: there is no reverse menu-open intent yet.
P103 adds a bounded reverse menu-open intent.  `MENU_OPEN_REQUEST` v1 is an exact 40-byte message sharing the menu-hover layout without its phase: schema, reserved bytes, menu id, menu generation, the pressed item id, the owning window id, the active frame generation, and the logical origin of the pressed slot.  Validation requires nonzero identity and generation fields and nonnegative coordinates, and the message travels in the negotiated acknowledged `DeliveryJournal` queue with EPXL admission on the publisher side, exactly like the other widget intents.  `frontend.menuBarLayout` (which the draw path already used) became the shared menu-bar geometry source, so the new `hitTestMenuBar` and the rendered row cannot drift apart; with `widget.menu_open_request_v1` negotiated a primary press on a visible slot is consumed and reported, and the frontend still never opens, reorders, relabels, or executes an item.  `sdl3-emacs-menu-open-smoke` presses the real "Edit" slot of a live Emacs menu bar and requires exactly one delivered request naming that item, its slot origin, and the owning window with an empty journal.  The publisher only records the request today, so opening a backend menu, publishing its popup, submenus, item enabling, and command dispatch are not claimed.
P104 makes that reverse intent open a real menu.  The publisher keeps a bounded open-menu state: on a valid request it resolves the menu id back to the same display-ordered `menu-bar-keymap` entry list the bar labels come from, walks that entry's keymap into at most 24 child rows (real labels, separators reduced to the bounded `--` marker, anything unexpressible skipped), computes a popup rectangle whose width fits its widest row and whose origin is the requested slot, and reports the rows and rectangle in the public facts snapshot; consuming a `menu-result` or `menu-cancel` artifact clears that state again.  The adapter validates the open state (bounded id, window, geometry, and rows), projects it as child nodes under the pressed item in the same `MENU_MODEL` the bar uses — regenerated only when the nodes actually differ, because the model survives a `FRAME_UPDATE` — and then sends a `MENU_OPEN` naming that generation with the rectangle clamped inside the owning window; when the producer reports no open menu it sends `MENU_CLOSE` with the live model identity instead.  `sdl3-emacs-menu-open-smoke` presses the real "Edit" slot, requires the live scene to own real child rows (including "Undo"), chooses the first selectable row so the frontend reports `MENU_RESULT`, and requires the popup to close again.  Subsequent milestones close item enabling and `:keys` publication; submenu traversal, filters, and command execution are not claimed at P104.
P105 applies the chosen row.  `proto-ui--menu-children` now also returns a parallel vector of bounded command names (taken from each row's `menu-item` command or vector command slot, and skipped when the name is not a plain symbol), kept adapter-local so it is never published; when the publisher consumes a `MENU_RESULT` it maps the chosen wire id back to that row and runs the command only when it is a member of the closed `proto-ui--menu-safe-commands` set (`undo`, `undo-redo`, `mark-whole-buffer`, `keyboard-quit`), wrapped so a failing command cannot kill the publisher loop.  Anything outside the set is resolved and recorded but never executed, so an unattended publisher can never prompt for input or run an arbitrary command.  The publisher's own probe setup is also placed outside the undo history, so the real Edit→Undo row can only undo what the frontend actually sent.  `sdl3-emacs-menu-apply-smoke` seeds one bounded edit, opens the real "Edit" menu, chooses the first selectable row, and requires the edit to disappear from the republished facts because the real `undo` command ran.  Submenu traversal and non-allowlisted commands are not claimed; the live rows' real `:enable` state is carried by P162 and their `:keys` hints by P165.
P106 adds a display-backed publisher profile.  A new `--graphic-frame-publisher` switch makes the publisher start Emacs without `--batch` (keeping `-Q`) so it opens its own PGTK/X frame from the inherited display; the frontend forwards a display/locale environment map to the publisher process, which previously ran with an empty environment and therefore could not pass a display on to Emacs at all, and the batch publisher also gained `-Q` now that HOME is forwarded.  The real frame is what makes `format-mode-line` (always empty in a batch frame), the real scroll-bar width, and other display-only facts observable, so the diagnostic mode-line draw threshold drops from sixteen to eight pixels: a real fifteen-pixel mode line draws its text while one- and two-pixel diagnostic bars stay textless.  `sdl3-emacs-graphic-smoke` requires the live scene to own the real mode line (text, height, and a text draw command) and a real scroll-bar width, and prints a bounded `skipped` result when no DISPLAY/WAYLAND_DISPLAY exists so headless jobs do not fail.  Fringe, divider, mouse-face, and font publication from the graphic frame are not claimed.
P107 unifies the pointer coordinate space.  The frontend now converts SDL window coordinates to frame-logical units before building a pointer or pointer-v2 press/motion/release intent, matching the geometry facts and the scrollbar and menu-bar hit tests, and the publisher maps every pointer path through `proto-ui--pointer-window-at` (only the generic profile did before), using window-relative coordinates for `posn-at-x-y`.  Without the mapping a press below the reserved menu-bar row was read as a window-space row count, and with the P103 menu-bar press handler a synthetic press at the frame origin was consumed by the menu bar instead of reaching the pointer path.  The pointer smokes now click inside the window body (`y = 12` window pixels, one logical row) with logical columns, and the middle-click-paste evidence accepts a window manager's own point-min markers instead of requiring an exact first line.  Touch and pen coordinate spaces, pixel-accurate sub-cell pointers, and non-TTY geometry parity are not claimed.
P108 uses the display-backed frame's real line metrics.  The publisher reports the frame's character height as a bounded frame fact (omitted when the frame reports one unit, which is what a batch TTY frame does), the adapter validates it, and row layout now goes through `visibleRowCount`/`visibleRowHeight`/`cursorFitsVertical` with that height: a real line height drives row spacing, cursor placement, cursor fit validation, and the visible-row cap, while a height of zero or one keeps the previous bounded fifteen-row guess unchanged.  The row count stays capped at fifteen, so the bounded row model does not grow, and `sdl3-emacs-graphic-smoke` now also requires the live rows to be spaced by the frame's own line height (the real 15-pixel mode line and the rows share one rhythm) with a `row_height` field in its evidence.  Batch frames, real font families, face-specific line heights, variable-pitch rows, and non-TTY geometry parity are not claimed.
P109 draws the real fringes.  The publisher reads each window's `window-fringes` widths, bounds them to 64 units, and reports them as `fringe_left`/`fringe_right` window facts only when either is nonzero, so a batch TTY frame (zero-width fringes) publishes nothing new; the adapter validates the pair and, for each nonzero side, appends a `FRINGE_UPDATE` message naming a snapshot-stable bounded id (`200 + window_index * 2 + side`), the whole window height, and the frame's real default background color as the fringe color.  Those records go through the same `Scene` validation and draw path the synthetic fringe slice already used, so a drawn fringe bar and a validated fringe record cannot disagree, and `sdl3-emacs-graphic-smoke` now samples the records while they hold (an authoritative `FRAME_UPDATE` clears them) and requires both sides plus the matching draw commands, reporting `fringe:[8,8]` and `fringe_drawn:true`; the reserved columns also inset the layout, because rows now start at the left fringe and are narrowed by both fringes (and the cursor is offset the same way), so body text and the cursor sit in the text area instead of under a fringe.  Fringe bitmaps, glyphs inside the fringe, face-specific fringe colors, and draggable fringe semantics are not claimed.  P111 uses the real mode-line face colors.  The publisher reports the frame's `mode-line` face `:foreground`/`:background` through the same `proto-ui--face-color` helper (now taking an optional face) and the adapter validates them as `mode_line_foreground`/`mode_line_background`; when either is present it publishes a generation-qualified `FACE_DEFINE` under the reserved `mode_line_face_id` (the generation only advances on a real color change, exactly like the default face).  The diagnostic mode-line draw path resolves that face and uses its background for the bar and its foreground for the text when the corresponding half is present, keeping the bounded diagnostic colors otherwise, so a real PGTK frame's `grey75`-on-`black` mode line reaches the SDL bar.  `sdl3-emacs-graphic-smoke` requires the published mode-line face and a bar fill whose color matches it (`mode_line_face_colors:true`).  Per-face text attributes, multiple faces inside one line, user themes, face merging, and full PGTK face parity are not claimed.  P112 sizes the diagnostic text from the real frame: the text renderer gained a `point_size` field with `adoptLineHeight`/`activePointSize` helpers, the graphic path adopts the published line height whenever it is a plausible font size (8..72) and reopens the font (dropping cached textures) when the size actually changes, and `PROTO_UI_FONT_SIZE` still overrides the adopted value.  `sdl3-emacs-graphic-smoke` requires the renderer's active point size to equal the live row height and reports it as `text_font_size` (15 for the default PGTK frame, matching the 15-pixel rows).  Real font families, font files, per-face sizes, variable-pitch rows, and shaped text are not claimed.  P113 uses the frame's real font file.  The publisher resolves the default face's font object through `font-info`, scans the info vector for the first existing font file (its position varies between builds) and its pixel size, and reports bounded `font_file`/`font_pixel_size` facts; the adapter validates them and publishes the file as a bounded string resource under the reserved `default_font_string_id`, regenerating only when the path changes.  The frontend's text renderer gained `adoptFontFile`/`activeFontFile`: it copies the path, closes the current font, and prefers the published file when opening, falling back to `PROTO_UI_FONT`, then its bundled candidates, so a missing or unopenable file never breaks text.  `sdl3-emacs-graphic-smoke` requires the active font file to equal the published resource and to end in `.ttf`, reporting `font_file` in its evidence.  Per-face fonts and sizes, variable-pitch rows, and shaped text are not claimed.  P114 gives the cursor the frame's real character cell: the publisher reports `frame-char-width` as a bounded `char_width` fact, the adapter validates it and funnels every cursor width through a `cursor_width` helper (the real cell, capped at 64, and never thinner than the two-unit diagnostic bar), and the cursor-fit validation measures the real width so a wide cell cannot push the cursor outside its window.  `sdl3-emacs-graphic-smoke` requires the live cursor to be wider than the diagnostic bar, at most one real cell, and exactly one line tall, reporting `cursor:[8,15]`.  Per-face fonts and sizes, variable-pitch rows, shaped text, and cursor blinking are not claimed.  P115 extends the reserved live-face table: the mode-line publication was refactored into a single `appendReservedFace` helper, and the publisher now also reports the frame's real `cursor` and `fringe` face backgrounds, each projected under its own reserved face id (`cursor_face_id`, `fringe_face_id`) with the same generation-qualified `FACE_DEFINE`.  The cursor fill prefers the published cursor face and falls back to the window's default-face foreground, and the fringe records take the real fringe face background when present (falling back to the default background), so both match what the real frame draws.  `sdl3-emacs-graphic-smoke` requires both reserved faces plus the matching cursor and fringe draw colors.  Per-face fonts and sizes, the scroll-bar face (unspecified in this theme), variable-pitch rows, and shaped text are not claimed.  P117 gives the split mirror its inactive mode line: the publisher reports the frame's `mode-line-inactive` face colors, the adapter publishes them under the reserved `mode_line_inactive_face_id` through the same `appendReservedFace` helper, and `drawDiagnosticWindowLine` selects the face by the record's `mode_line_active` flag (falling back to the active face, then the bounded diagnostic colors).  `sdl3-emacs-graphic-smoke` now pushes a real `C-x 2` key sequence, waits for two mode lines, and requires the inactive window's bar fill to match the published inactive color while the active one still matches the active face, reporting `mode_line_inactive_face_colors`.  Per-face fonts and sizes, header/tab face distinctions, variable-pitch rows, and shaped text are not claimed.  P118 puts the live active region in the mirror: the publisher maps the region's two endpoints through `posn-at-point`/`posn-x-y` (window pixels), requires an active transient mark and visible endpoints, bounds the rectangle, and reports it plus the frame's real `region` face background; the adapter validates the rect, publishes the region face under the reserved `region_face_id`, and reuses the frontend's bounded visible-highlight record (rect plus a live face), so the region travels the same validation, ownership, and draw path as the synthetic mouse highlight, re-sent after each authoritative `FRAME_UPDATE` because that clears the highlight table.  `sdl3-emacs-graphic-smoke` pins one active region in the publisher profile and requires the highlight record and its draw color (`region_highlight:true`).  Mouse-face capture, multi-rectangle or per-line region shapes, and shaped text are not claimed.  P119 adds the manual graphic mirror target: `sdl3-emacs-graphic-interactive` runs the ordinary interactive EPXL session with `--graphic-frame-publisher=true`, so an operator can see the display-backed frame's real mode line and mode-line faces, fonts, fringes, cursor cell, active region, menu bar, and scroll bar mirrored into SDL until the window is closed.  It adds no new protocol surface and no automated assertion; `sdl3-emacs-graphic-smoke` stays the CI-checked proof of the same facts.  P120 colors the visible lines: the publisher resolves each character's face foreground (`get-text-property` plus `face-attribute`, normalized by a shared `proto-ui--bounded-color` helper that `proto-ui--face-color` now shares), groups adjacent equal colors into at most six bounded runs per row, and publishes a row only when its runs cover the whole line, because a row with glyph runs stops drawing its plain text.  Each run carries its row through the wire (P122 raises the bound to eight visible rows and twenty-four runs), the adapter validates it, publishes each color under a reserved run face id, and emits schema-2 face-bound `GLYPH_RUN` records at the row's geometry, so the mirror shows real font-lock colors for those lines.  `sdl3-emacs-graphic-smoke` pins three Lisp lines in the publisher profile and requires at least two distinct run colors to reach the draw list and at least three rows with two or more distinct colors, reporting `line_font_lock_runs` and `line_font_lock_row_count`.  P122 then raises the run bound from two rows/six runs to eight rows/twenty-four runs, so the whole eight-line window the publisher reads can carry font-lock colors.  Per-run fonts, bold/italic/underline faces, face merging, and shaped text are not claimed.  P116 reserves the whole text area: rows are now narrowed by the frame's real scroll-bar width as well as both fringes (so body text cannot run under the scroll bar), and the mode-line, header-line, and tab-line records span only that text area, matching where the real frame draws them.  `sdl3-emacs-graphic-smoke` requires the row and mode-line widths to exclude the scroll bar it already checks, reporting `row_width` in its evidence (2556 minus 8/8 fringes and 16 scroll bar).  The bounded status-manifest test's runaway guard also moves from 24 KiB to 32 KiB, because the manifest had grown with the feature set and the old bound forced evidence trimming on every slice.  Per-face fonts and sizes, the scroll-bar face (unspecified in this theme), variable-pitch rows, and shaped text are not claimed.

P139 falls back for scripts the adopted font lacks.  Emacs picks a covering font per character, but the mirror opened only the frame's own font file, so CJK rendered as tofu.  The renderer now opens the first available system fallback (WenQuanYi, Sarasa Gothic, Noto CJK, Unifont, PingFang, Microsoft YaHei/SimSun), attaches it to the adopted font and each styled variant with TTF_AddFallbackFont, and closes it with the font set on size/file change.  `sdl3-emacs-graphic-smoke` requires an installed fallback and that CJK codepoints resolve through it (cjk_fallback, checked with TTF_FontHasGlyph).  Per-character font selection, shaping/BiDi, variable-pitch rows, and shaped text are not claimed.
P140 opens the first bounded variable-pitch path. The publisher resolves a face's file-backed font, compares it with the frame default, and reports one alternate font resource plus variable_pitch on each run that uses it; the adapter carries a reserved glyph-run flag, and the renderer opens that real SDL_ttf font separately from the default and styled variants while keying its texture cache by the flag. `sdl3-emacs-graphic-smoke` pins DejaVu Serif beside the default Liberation Mono and requires the run to reach the draw list with the alternate-font flag (variable_pitch_font). Per-character font fallback within a run, exact variable metrics/hit testing, shaping/BiDi, and shaped text are not claimed.
P141 gives the header line and tab line their own segment faces.  Emacs returns those lines from `format-mode-line` with their own face properties too, but the mirror drew one face for each.  The publisher now derives bounded per-segment runs for the mode line, header line, and tab line through one `proto-ui--chrome-runs` helper, marking each run `:mode_line`, `:header_line`, or `:tab_line`; the adapter anchors every chrome run to the window's first row but positions it at that aux row's geometry (header at the window top, tab below the header, mode line at the bottom) and carries a distinct bounded glyph-run flag.  A plain chrome line is only suppressed by runs of its own kind, which also fixes the P138 regression where a mode-line run hid the header and tab text.  `sdl3-emacs-graphic-smoke` pins an accent face on the header and tab lines and requires each run to reach the draw list in its face color (header_line_face_runs, tab_line_face_runs), sampled per applied message because the next authoritative `FRAME_UPDATE` clears the glyph-run table; `proto-ui-unit` pins the wire flags, the mutual exclusivity, and the flat-row chrome anchor.  Mixed chrome kinds on one run are rejected, and per-character header/tab font selection and non-ASCII segments are not claimed.
P142 mirrors the real tool bar.  Emacs reserves a strip below the menu bar for the frame's `tool-bar-map`, but the mirror only had a synthetic tool-bar model.  The publisher now enumerates the real keymap with `map-keymap` in display order and reports one bounded item per binding: a separator or space, or a button/toggle carrying its printable name, a bounded command key, its `:help` text, and the item's real `:visible`/`:enable`/`:button` state evaluated in the selected window exactly as the frame's own tool bar evaluates them (so the bounded publisher never guesses a hidden or disabled item).  The adapter validates the items (bounded label/help/key, the tool-bar kind/flags invariants), publishes them through the existing `TOOLBAR_MODEL` under one adapter-owned id whose generation only advances when the items change, and the SDL draw path renders the real labels; a batch frame with no tool-bar lines publishes nothing.  `sdl3-emacs-graphic-smoke` requires the live bounded model (thirteen items for the stock `-Q` tool bar) and that at least four of its labels reach the draw list (tool_bar, tool_bar_items), and `proto-ui-unit` pins the bounded parse and the separator-label rejection.  Real tool-bar icons, overflow, orientation, and exact PGTK tool-bar geometry (the mirror still draws the strip through the diagnostic toolbar layout) are not claimed.
P143 puts the tool bar on the frame's real colors.  The mirror drew the tool-bar strip with bounded diagnostic colors, but Emacs's `tool-bar` face is a real `black`-on-`grey75` released-button face.  The publisher reports the frame's `tool-bar` face `:foreground`/`:background` (only while the frame has tool-bar lines), the adapter validates them and publishes a generation-qualified `FACE_DEFINE` under a reserved `tool_bar_face_id` through the same `appendReservedFace` helper the other live faces use, and the SDL draw path uses the background for the strip and its buttons and the foreground for the labels, keeping the bounded diagnostic colors otherwise.  `sdl3-emacs-graphic-smoke` requires the published face and a strip/slot fill in its real color (tool_bar_face_colors), and `proto-ui-unit` pins the bounded color parse.  The diagnostic tool-bar placement (the strip still overlaps the window's top strip because the mirror has no per-chrome geometry), box/border styles, icons, and exact PGTK tool-bar parity are not claimed.
P144 carries the real `:box` face decoration.  Emacs gives the default mode-line face a `(:line-width -1 :style released-button)` box (and the tool-bar face a `(:line-width 1 :style released-button)` one), but the run publisher only resolved underline/strike-through/overline and inverse-video, so the mirror drew no box at all.  The publisher now resolves a face's `:box` (with its color when it names one) and folds it into the run grouping key, and reports the mode-line and tool-bar faces' bounded box style; the adapter validates both (the wire requires a box color whenever a box is present, and a box that names no color falls back to the face foreground exactly as Emacs draws it) and publishes them through the existing `FaceDecorations`/`appendReservedFace` path onto the reserved run faces and the reserved mode-line/tool-bar faces, and the SDL draw path renders them through the existing `faceDecorationBars` box approximation on the run rects, the mode-line/header/tab bars, and the tool-bar buttons.  `sdl3-emacs-graphic-smoke` requires the real released-button box on the mode-line and tool-bar faces and a drawn tool-bar button border (mode_line_box, tool_bar_box), and `proto-ui-unit` pins the bounded parse and both rejections.  Full PGTK box parity is not claimed.
P145 stops a non-ASCII line from breaking the whole mirror.  The bounded run wire carries only printable ASCII (`validGlyphRunText` and the adapter's `isPrintableAscii` gate), but the publisher emitted a run for every character, so a single non-ASCII character in any visible line (CJK, accented letters, smart quotes, emoji) produced a non-ASCII run that the adapter rejected, failing the whole snapshot parse, which the live bridge reports as `NoEmacsFacts` and leaves the mirror blank (this turn reproduces that exact failure in `sdl3-emacs-graphic-smoke` before the fix).  The publisher now requires a printable-ASCII row and chrome line before publishing runs, so a line with any other character keeps its plain-text path — which the mirror already draws through SDL_ttf with the system font fallback (P129/P139) — instead of failing.  `sdl3-emacs-graphic-smoke` pins a CJK line among the visible font-lock rows and requires the mirror to still publish and draw that line as plain text (non_ascii_text), and `proto-ui-unit` pins the ASCII-only run contract.  Runs for mixed-ASCII lines (ASCII spans keep colors while non-ASCII falls back), shaping/BiDi, and per-character fonts are not claimed.
P146 stops a long line from breaking a narrow mirror.  The adapter emits glyph runs in window-relative coordinates (the draw path adds the window origin), but the scene validated a run's `x + width` against the whole frame's logical width.  A line wider than the window (a URL, minified code, or any long line in a frame narrower than the run's pixel width, with the publisher's line cap at 120 bytes ≈ 960 px) therefore failed that bounds check and rejected the entire snapshot, blanking the mirror exactly like P145's non-ASCII run (this turn reproduces it in `proto-ui-unit` with a 120-column run in a 600-pixel frame).  The adapter now clamps each run to the owning window: it skips a run whose origin is past the window edge and caps the emitted width so `x + width` never exceeds the window, which also keeps the fill, box, and damage geometry inside the window.  `proto-ui-unit` pins the clamped result, and the full smoke sweep stays green.  Truncation versus continuation of the overflowing text (the mirror still draws the full run text, which can overflow the window edge) and per-window clipping of the drawn glyphs are not claimed.
P147 hardens the cursor the same way.  The adapter used to reject the whole snapshot when a cursor did not fit its window (`fringe_left + column * 8 + cursor_width > window.width`, or a cursor line past the visible rows, which also failed `cursorFitsVertical`), the same fail-blank mode as P146's long line.  It now clamps the cursor's line and column into the owning window instead of failing, so a short window or a far-right column keeps the snapshot alive and the mirror shows a bounded cursor; the parse-level contract checks (line >= 1, column <= 120) are unchanged.  `proto-ui-unit` pins both a narrow window (the previous `InvalidCursorFacts` expectation becomes a clamped column-0 cursor) and a real column reaching the cursor rect.  The publisher still bounds the per-window cursor column at nine — raising that bounded diagnostic cap changed the pointer/menu/scrollbar interaction smokes' behaviour, so it is left as-is and recorded as a limitation rather than a fix — so exact cursor column, `window-hscroll`-adjusted cursor placement, and cursor blinking are not claimed.
P148 tracks the right cursor.  `applyCursorUpdate` set the scene's single "current" cursor on every update, so in a split frame it ended up as whichever window was emitted last — often an inactive one — and the presentation gate (`gate.observeScene`), scene hash, and cursor evidence all described the wrong caret; the graphic smoke only passed because its size/color assertions happened to hold for either window.  The scene now sets `self.cursor` only for the active cursor, and the SDL draw path draws a non-selected window's caret hollow (the four one-unit edge bars) exactly as Emacs draws an inactive cursor while the selected window keeps its real kind, and it skips an invisible cursor.  `sdl3-emacs-graphic-smoke` splits the frame and requires the tracked cursor to be the active one with a solid rect plus a hollow inactive caret (inactive_cursor_hollow).  Smoke-side, this also confirmed that the publisher's per-window cursor column cap cannot be raised without perturbing the pointer/menu/scrollbar interaction smokes (retested after this fix), so it stays at nine.  Per-window inactive cursor shapes beyond the hollow box, cursor blinking, and `cursor-in-non-selected-windows` policy are not claimed.
P149 keeps the mirrored rows aligned.  The publisher built its line list with `split-string ... t`, which drops empty elements, and additionally dropped any line past the 120-byte wire bound, so a blank line or an over-long line vanished from the list and every following row shifted up out of alignment with the real display (and the cursor's line index moved with them, because the cursor line is derived from logical line numbers while the row list lost an entry).  The publisher now keeps interior blank lines — dropping only a trailing empty element that a region-final newline produces — and truncates an over-long line to the wire bound at a character boundary instead of dropping it.  The adapter, in turn, must skip emitting a `TEXT_LINE_V2` record for a blank row because `validBoundedUtf8Text` rejects empty text, while still advancing the row index for every later line, so a blank line leaves a blank row rather than a gap.  `sdl3-emacs-graphic-smoke` pins an over-long line and a blank line in the runs profile and requires both the truncated row and the row that follows the blank to stay aligned (row_alignment).  Wrapped (visual-line) rows, and mirroring a line past the 120-byte bound in full rather than truncating it, are not claimed.
P150 mirrors horizontal scrolling.  The mirror only reflected `window-hscroll` in the scrollbar state; the row text and font-lock runs always started at display column zero, so whenever Emacs auto-scrolled a long line (`auto-hscroll-mode` is on by default) the mirror showed the wrong part of the line — a common case given a long URL or log line.  The publisher now drops each row's scrolled-off display columns before emitting its text and starts each row's runs after the scrolled-off prefix (a wide-character-aware `proto-ui--column-index` finds the character boundary, since a wide character advances by its own display width), and it subtracts the hscroll amount from the cursor column before the existing nine-column cap.  `sdl3-emacs-hscroll-smoke` drags the real horizontal bar to `window-hscroll` 15 and requires the base `visible ASCII textZ` line to be mirrored as its remaining `extZ` (text_trimmed), proving both the row trim and that short rows shift with the display.  Wrapped (visual-line) rows, hscroll-aware cursor placement beyond the bounded column cap, and mirroring a line past the 120-byte bound in full are not claimed.
P151 mirrors displayed rows, wrapping included.  The mirror's rows were the buffer's logical lines, but with `truncate-lines` off (the default) Emacs wraps a long line across several display rows, so a wrapped line appeared as one mirrored row carrying only its first 120 bytes and the mirror's rows no longer matched the display.  The publisher now walks the window's displayed rows with `vertical-motion` inside the window (`proto-ui--visual-line-spans`, bounded to 32 rows, stopping before each newline so a row's text is exactly what the display draws) and emits one mirrored row per display row; `proto-ui--display-lines` feeds both the flat text and each window's rows, and the font-lock run walk uses the same `vertical-motion` step so the runs line up with the rows they color.  `sdl3-emacs-graphic-smoke` pins a 1000-character line (wider than the frame's window) and requires the mirror to hold several rows of its wrapped text (wrapped_rows), while the over-long-line and blank-line pins keep their alignment.  The cursor's row still comes from the logical line delta rather than the display walk — switching it to `count-screen-lines` moved the caret onto a wrapped continuation row and broke the interactive window-navigation/window-restore smokes, so it was reverted and recorded as a limitation — and mirroring a displayed row past the 120-byte bound in full is likewise not claimed.
P152 colours mixed ASCII/non-ASCII lines.  The bounded run wire carries only printable ASCII, so a row with any non-ASCII character kept no font-lock colours at all (P145 made it fall back to plain text).  A run can now mark itself *partial* (`glyph_partial_body`): it colours an ASCII span of a row without replacing that row's plain text, so the draw path keeps the plain text (which carries the characters the run wire cannot) and draws the partial runs over it.  The publisher emits partial runs for a mixed row's ASCII spans, positioned by display column (a wide character advances the column by two, and the run-tracking accumulates `string-width` per character), and only a row with no resolvable colour still fails back to plain text; the adapter carries the bounded partial bit and keeps `covers_row` false for it.  `sdl3-emacs-graphic-smoke` pins `你好 note4` (a non-ASCII span plus a keyword-coloured ASCII span) and requires both the plain text and a partial run (line_font_lock_run_mixed).  Shaped text/BiDi, runs spanning a substitution, and per-character fonts are not claimed.
P153 mirrors a full wide row.  The bounded row text was capped at 120 bytes, a bound shared with the mode line, echo, title, and cursor, so on a wide frame — a maximized window on a large display with a small font is easily 200+ columns, and this container's frame is 315 columns — the mirror showed only the first 120 cells of every (wrapped or not) row.  The row text and the runs over it now share a separate, larger `max_row_columns` (256 bytes) bound: the publisher truncates at 256, the facts validators accept rows and runs up to 256, the `TEXT_LINE_V2` codec encodes/decodes 256, the SDL_ttf draw path accepts 256 bytes, and the text-texture cache key holds 256 (its length field moved from u8 to u16 — a 256-byte key would otherwise panic).  The chrome/echo/title/cursor bound stays at 120, so those stay small.  `sdl3-emacs-graphic-smoke` requires a mirrored row longer than 120 bytes (row_bound_256) when the window is wider than 120 cells, and its over-long-line pin still truncates rows past the new bound; the pins are ordered so that wrapping cannot push the coloured rows out of the bounded run budget on a narrow display.  Rows wider than 256 cells, the display-row cursor on wrapped rows, and shaped text/BiDi are not claimed.
P155 corrects two placement details.  The run walk advanced the display row with `(vertical-motion 1)`, which always uses the SELECTED window's geometry, while the mirrored-row walk passed the window; in an unbalanced split the runs would wrap at the selected window's width and drift out of alignment with the rows they colour, so both walks now pass the window (`(vertical-motion 1 window)`).  Second, the adapter placed a cursor column on a hardcoded eight-unit cell (`fringe + column * 8`) even when the frame reported a different `char_width`, so a wider cell misplaced the caret; the placement and fit arithmetic now use the frame's real cell (`cursorCellWidth`), with `proto-ui-unit` pinning a ten-unit cell (column twenty -> x 200).  The window split smokes also asserted the caret's absolute `x == 8`, which is the frame's fringe width and so display-dependent (this environment's frame reports a one-pixel fringe); they now require the caret at the start of the selected window's first line (`x <= 16`, `y == 0`) with the window and text checks unchanged, so the smoke sweep stays green on any display.
P156 puts the echo area on the frame's real colors.  The mirror reserved the frame's bottom strip for `current-message` but painted it with bounded diagnostic colors (a dark strip and yellow text), so a message on a light PGTK frame was drawn in colors the real frame never uses.  The echo strip now fills with the frame's published default face background and draws the message with its default face foreground (falling back to the diagnostic pair when no default face is live), which is what the real minibuffer/echo area shows for a plain message.  `sdl3-emacs-graphic-smoke` requires the drawn echo text to carry that default-face color (`echo_face_color`).  The active minibuffer prompt's own face, completion UI, multi-line echo, and message-specific faces are not claimed.
P157 makes a multi-line region a set of rows instead of one box.  The active region is applied by redisplay rather than by a property (a probe shows `get-char-property` returns nil for marked text), and the publisher reported its two endpoints as a single bounding rectangle, so a region spanning several lines collapsed to a narrow band that matches neither the first line nor the last.  The publisher now walks the displayed rows the region touches (`end-of-visual-line` per row) and reports one bounded rectangle per row covering exactly the selected part of that row; the adapter validates up to eight of them, publishes the region color under a bounded block of reserved face ids (the first keeps `region_face_id`), and emits one bounded highlight record per row, which is what the frontend's `(window, face)`-keyed highlight table draws.  `sdl3-emacs-graphic-smoke` pins a three-line region on plain rows (so it cannot disturb the font-lock pins) and requires more than one region record plus the region color in the draw list (region_rects).  Per-line region shapes beyond one rectangle per displayed row, the inactive-region face, and shaped text are not claimed.
P158 fixes the EPXL ACK-loss recovery handshake.  The recovery smoke's first session deliberately discards the reverse-input ACK, so session one's reconnect re-sends the still-pending input with its original wire sequence; `awaitFrameAck` recognised that retransmission, ACKed it, and then `return`ed from the whole wait instead of `continue`ing, leaving the frontend's separate frame ACK unread.  The next snapshot message then read that stale ACK, failed its sequence match with `ExpectedAck`, and aborted the publisher, which surfaced on the frontend as `EndOfStream` inside `recoverLiveScene` (the registered `sdl3-epxl-recovery-smoke` step failed deterministically with exactly that pair).  The dedup branch now `continue`s, exactly like the new-input branch a few lines below, so the frame ACK is still consumed and the recovered session applies the retried `X` (`XEmacs Proto-UI`).  `sdl3-epxl-recovery-smoke` now passes instead of failing; the resync, gap-recovery, facts, and live smokes are unaffected because a single session never retransmits an input.
P159 carries more than one alternate font family per snapshot.  The publisher already named each run's file-backed font (`:font_file`), but the adapter dropped it while parsing and kept only the single negotiated `variable_font_file`, so a second distinct family (a serif run beside a sans run, or any face that names its own font) was drawn with family 1's file.  The adapter now groups the distinct run font files that are neither the frame default nor the negotiated variable-pitch file into a bounded pair of extra families (`max_alt_font_families`), publishes each as a reserved string resource (`variable_font_string_id + 1`, `+ 2`), and sets a two-bit glyph-run family field (`glyph_font_family_shift`) where family 1 keeps the existing `glyph_variable_font` flag, so a publisher that only sends `variable_pitch` still resolves to family 1.  The frontend stores the family on the scene run, and the renderer keeps one alternate font handle per family, keying its texture cache by the full style/family byte so two families never share a texture; a family beyond the bound stays family 1 rather than failing the snapshot (the same never-blank-the-mirror rule as P145/P146).  `proto-ui-unit` pins two distinct alternate files as families `0/1/2/3` with three published resources, and `sdl3-emacs-graphic-smoke` reports the live `font_families` count (one on this theme, where only the serif variable-pitch face differs from the default).  Per-character selection *within* a run, a family reachable only through an unresolvable symbolic font, exact variable metrics, and shaping/BiDi are not claimed.
P138 keeps the mode line's own segment faces.  format-mode-line returns the mode-line string with its face properties (the default frame's buffer id carries mode-line-buffer-id, bold) but the mirror drew one face.  The publisher resolves those per-segment faces into bounded runs marked :mode_line, the adapter emits them as glyph runs anchored to the window's first row but positioned at the mode-line geometry, and a new bounded glyph-run flag keeps them from suppressing the row's plain text.  The frontend skips the single-face mode-line text when runs exist and the bounded run total moves from 24 to 32.  `sdl3-emacs-graphic-smoke` requires a bold mode-line run (mode_line_face_runs).  Header/tab-line segments, variable-pitch rows, per-character font selection within a run, and shaped text are not claimed.
P137 mirrors the echo area.  The real frame reserves a bottom strip for the minibuffer (the root window's bottom 15 pixels) that the mirror left empty.  The publisher reports current-message as a bounded :echo string, the adapter publishes it as a reserved string resource (echo_string_id), and the frontend draws it in that strip with the frame font.  The graphic smoke pins a deterministic message and requires the resource and its drawn text (echo_area) and proto-ui-unit covers the parse and resource publication.  The active minibuffer prompt face, completion UI, multi-line echo, and shaped text are not claimed.
P136 resolves the live mouse-face highlight.  The publisher records the last pointer sample the frontend sends, resolves get-char-property point mouse-face at that glyph, and reports a bounded highlight plus the face's real background; the adapter publishes it under a reserved mouse-face face id and the frontend keys highlights by (window, face) so the region and mouse-face highlights coexist.  A new `sdl3-emacs-mouse-smoke` drives a real synthetic pointer motion at the first body row and requires the highlight (mouse_face).  mouse-face text properties do not survive redisplay, so the smoke pins an overlay (as buttons/links do), and the highlight arrives as its own message so the smoke samples it per applied message.
P135 colors every visible window.  The publisher only resolved runs for the selected window, so after C-x 2 the other window stayed plain.  Each run now names its window, the publisher emits runs for up to two windows inside the same bounded budget, and the adapter maps each window's rows into the scene's flat row table (base row plus local row) so the glyph runs validate against the right window.  `sdl3-emacs-graphic-smoke` requires a run for the non-first window after the split (line_font_lock_multi_window) and `proto-ui-unit` pins the flat-row mapping.  More than two windows, variable-pitch rows, and shaped text are not claimed.
P134 positions font-lock runs on the frame's real character cell.  The run x and width used a hardcoded eight-unit cell, which only matches the default theme; the adapter now uses the published char_width (falling back to eight), so a frame with a different cell width keeps its runs aligned.  `proto-ui-unit` pins a ten-unit cell and requires the emitted glyph run to start at column x 10 with the matching width.  Variable-pitch rows, per-character font selection within a run, and shaped text are not claimed.
P133 resolves overlay-aware faces.  The run publisher read the face text property, which misses overlays; it now uses get-char-property, so the highest-priority overlay face wins.  That picks up hl-line, isearch, and spell-check (the active region is NOT a text/overlay property — `get-char-property` returns nil for marked text — so the region is carried by the bounded highlight rectangle instead).  Because a row can carry more distinct faces, the bounded runs-per-line cap moves from six to eight, still inside the twenty-four-run snapshot bound.  `sdl3-emacs-graphic-smoke` pins an overlay face and requires its color to reach a run (line_font_lock_run_overlay).  Face merging beyond Emacs's own resolved face, mouse-face, and shaped text are not claimed.
P132 puts the remaining chrome on the real font.  Dialogs, the tool-bar strip, tooltips, and the IME preedit/candidate boxes now draw through a shared drawLabel helper that centres the frame font in the widget band, so the mirror no longer emits SDL eight-pixel debug text at all.  The synthetic widget smokes were updated to the font-backed command, keeping the suppression and non-ASCII-filter assertions.
P131 renders per-run bold and italic.  The publisher resolves :weight (semi-bold and heavier) and :slant (italic/oblique) per character and folds both into the run key; the adapter carries the style as two bounded glyph-run flag bits, the frontend keeps them on the scene run, and the text renderer opens and caches a styled variant of the adopted font with TTF_SetFontStyle and keys the text cache by style so a bold glyph never reuses a plain texture.  `sdl3-emacs-graphic-smoke` pins a bold-italic span and requires the run to reach the draw list with style bits set (line_font_lock_run_style).  Variable-pitch rows, per-character font selection within a run, and shaped text are not claimed.
P130 puts the menu chrome on the real font.  The real menu-bar labels and the bounded popup rows draw through the adopted SDL_ttf font, centred in their strip/row, instead of the eight-pixel debug font; `sdl3-emacs-menu-bar-smoke` requires each real label to reach the draw list as font-backed text (font_backed) and the runtime-bridge menu/patch scans were updated.  Dialogs, the tool bar, and tooltips still use the bounded debug font.
P129 draws the mirror text with the frame's real font.  Body rows, fontified runs, the mode line, and header/tab lines now emit font-backed text vertically centred in the row with the adopted font's real height (TTF_GetFontHeight), instead of SDL's eight-pixel debug font; the non-ASCII path is unchanged.  `sdl3-emacs-graphic-smoke` requires a plain body row to reach the draw list as font-backed text (body_text_font).  The menu bar, dialogs, tool bar, and tooltips still use the bounded debug font, and bold/italic weight and slant, variable-pitch rows, shaping, and the real tool bar are not claimed.
P128 sizes the mirror text from the frame's real font pixel size.  The publisher already reported font_pixel_size but the adapter only validated it; the renderer sized text from the line height, so glyphs were one size too large for the row.  The adapter now publishes the size as a second bounded string resource beside the font file (default_font_size_string_id), the frontend parses and adopts it as the text point size, and the line height remains the fallback.  `sdl3-emacs-graphic-smoke` requires the active point size to equal the published pixel size and not exceed the row height (text_font_size 13 with row_height 15).
P127 honours :inverse-video.  The publisher resolves the flag per character and folds it into the run key; the adapter validates it and publishes it on the reserved run face, and the glyph-run draw path swaps the fill and text halves (fill with the face foreground, draw the text with the face background).  `sdl3-emacs-graphic-smoke` pins an :inverse-video span and requires the swapped foreground fill (`line_font_lock_run_inverse`).  Bold/italic weight and slant, wave/dotted underline styles, face merging, and shaped text are not claimed.
P126 carries the real decoration colors.  The publisher resolves a face's :underline/:strike-through/:overline color (a plain #rrggbb or the :color of a spec such as (:color "red" :style wave)) and folds it into the run key; the adapter validates the three colors and publishes FaceStyle.color with an explicit underline_color/strike_color/overline_color, so the existing faceDecorationBars path draws each bar in the face's own color instead of the run foreground.  `sdl3-emacs-graphic-smoke` pins a #00a0a0 underline and requires the matching bar fill.  Bold/italic weight and slant, wave/dotted underline styles, face merging, and shaped text are not claimed.
P125 mirrors a real screenful of window text.  The publisher sends up to thirty-two lines per window (each still capped at 120 bytes) and the adapter accepts the same bound; the viewport check no longer couples the window's absolute start line to the line table, so a deeply scrolled window still validates.  The diagnostic scrollbar keeps its line-derived viewport, and the scrollbar/interaction smokes pin a 200-line buffer with a 32-line viewport (page 10 to 42, drag 42 to 46).  `sdl3-emacs-graphic-smoke` requires at least twenty-four mirrored lines and reports `mirrored_lines` (30).  Full-screen redisplay capture, variable-height rows, and folding are not claimed.
P124 carries per-run face decorations.  The publisher resolves each character's :underline, :strike-through, and :overline (with the default-face fallback) and folds them into the run grouping key, so a decorated span splits a run; the adapter validates the three flags and publishes them as FaceStyle.single on the same reserved run face.  The renderer's existing faceDecorationBars path already drew those styles for glyph runs, so no draw or protocol change was needed.  `sdl3-emacs-graphic-smoke` pins an underlined span and requires a matching bar fill (`line_font_lock_run_decorations`).  Bold/italic weight and slant, face merging, and shaped text are not claimed.
P123 carries per-run face backgrounds.  A run background is published only when it differs from the frame default, so a plain line keeps its single-face text; the adapter validates the extra background half, publishes it on the same reserved run face, and the existing glyph-run draw path fills that rect before the text.  The shared resolver also falls back to the default face for an unspecified foreground/background, so a background-only face still contributes its own foreground.  `sdl3-emacs-graphic-smoke` pins a `#204060` background on the runs-smoke comment spans and requires the matching fill (`line_font_lock_run_backgrounds`).  Bold/italic/underline, face merging, and shaped text are not claimed.
P121 gives the aux lines their own faces.  The mirror already drew the header line and tab line, but both used the mode-line face colors.  The publisher now reports the frame's real `header-line` and `tab-line` face foreground/background through the same `proto-ui--face-color` helper, the adapter validates them and publishes each under its own reserved face id (`header_line_face_id`, `tab_line_face_id`), and `drawDiagnosticWindowLine` picks the face from the record kind bits (header / tab / active-inactive mode line) with the mode-line face as the fallback.  `sdl3-emacs-graphic-smoke` pins a header line and a tab line in the publisher profile and requires both aux records plus their own face-colored bars, reporting `header_line_face_colors` and `tab_line_face_colors`.  Header/tab items, mouse faces, and PGTK parity are not claimed.

P160 makes the mouse-face highlight a set of rows instead of one cell.  The publisher reported only the character cell under the mirror's pointer, so a `mouse-face` span covering several displayed rows (a button, a link, or any multi-line overlay) drew a single rect that matched neither end.  The publisher now finds the contiguous `mouse-face` span around the pointer (bounded to 400 characters each way), walks the displayed rows it touches, and reports one bounded rectangle per row — the same shape as the P157 region — falling back to the frame's character cell when a batch/TTY frame has no `posn-at-point` and no visual-line layout; the adapter validates up to eight rectangles, publishes the background under a reserved mouse-rect face block (`mouse_rect_face_base_id`, keeping `mouse_face_id` for the first), and emits one bounded highlight record per rectangle.  `sdl3-emacs-mouse-smoke` now pins a mouse-face overlay that spans three displayed rows and requires three highlight records (`mouse_rects`:3).  Arbitrary region/mouse-face shapes (a rect that is not the union of whole-row slices), the inactive-region face, and shaped text are not claimed.

P161 draws the real `:box` bevel and thickness.  The protocol's face payload already carried a bounded `box_line_width`, but the adapter never set it (the wire requires a box color whenever the width is non-zero) and `faceDecorationBars` drew all four border bars in one color at a guessed `height * 0.08` thickness, so the released-button mode-line/tool-bar border was a flat hairline.  The publisher now resolves each face's `:box` `:line-width` (an integer or a horizontal/vertical cons; a negative width is relative to the frame's own border, so its magnitude is the bounded stand-in) into a 1..8 pixel width, the adapter publishes it on the face payload (defaulting the box color to the face foreground when the box names none, which the wire already required) and folds it into the generation check, and the renderer uses that width and draws a bevel — top/left lightened by 96, bottom/right darkened by 64 for `released`, the inverse for `pressed`, flat for `simple` — derived from the box color so a black box still shows a readable edge.  `sdl3-emacs-graphic-smoke` requires a real box width on both chrome faces and two distinct tool-bar border colors (`tool_bar_box_bevel`, `tool_bar_box_width`:1).  Exact PGTK bevel geometry (Emacs's own highlight/shadow faces, rounded corners) remains pending.

P162 carries each live menu row's real `:enable` state.  The publisher resolved a menu item's label and command but never its `:enable` form, so the mirror drew every popup row enabled — Cut/Copy/Clear appeared available with no active mark.  `proto-ui--menu-children` now also returns a parallel enable vector, evaluating each item's `:enable` form in the selected window through the same safe evaluator the tool bar uses (an absent form means enabled, an erroring form stays disabled), and the open-menu facts carry it; the adapter validates the parallel vector (absent means every row enabled, a mismatched length is rejected), projects a disabled row as a `MENU_MODEL` node without `MenuNodeFlags.enabled`, and the existing popup draw path dims it while `menuRows` skips it as non-selectable.  `sdl3-emacs-menu-open-smoke` requires the real Edit menu's mark-dependent rows to arrive disabled (`popup_enable_state`:true), and the apply smoke still chooses "Undo" when the seeded edit makes it enabled.  Subsequent milestones close `:filter`/`:visible`; submenu traversal remains pending.

P163 gives line runs face-aware pixel advances.  The adapter previously derived every run origin and width from the frame's character cell, so a variable-pitch run had the right font but the wrong geometry.  The publisher now measures each printable ASCII character with `string-pixel-width` against its resolved face and accumulates bounded text-relative `pixel_x` and `pixel_width` for body and chrome runs; the adapter validates the fields as a pair, prefers them after the left fringe, and retains the cell calculation when absent.  `sdl3-emacs-graphic-smoke` requires the variable run's drawn rectangle to equal the published metrics (`variable_pitch_metrics:true`).  These are unshaped, per-character advances; kerning, BiDi, complete glyph runs, and exact hit testing are not claimed.

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

P165 publishes and renders real menu key hints.  The publisher resolves each
popup row's explicit string `:keys` property, falling back to the first
`where-is-internal` binding for the row's command, then keeps only a bounded
printable key description.  The open-menu facts carry the parallel vector, the
adapter validates a non-empty vector against the row count and stores each key
on its `MENU_MODEL` node, and the popup draw path right-aligns the hint with the
row label.  `proto-ui-unit` pins the real Edit-menu keys and rejects a
mismatched vector; `sdl3-emacs-menu-open-smoke` requires a key in the live model
and its matching command in the popup draw list (`popup_key_hint`:true).
Subsequent milestones close `:filter`/`:visible`; submenu traversal remains pending.

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
wire bound and full PGTK popup parity remain pending.  P170 publishes real
stateful row state: the producer evaluates `:button` `:toggle`/`:radio` forms
for both raw and normalized menu rows, sends bounded parallel `kind` and
`selected` vectors, and the adapter validates mismatched/unknown values before
projecting checkbox/radio kinds and selected flags; separators project as
visible-only.  `proto-ui-menu-radio-unit`
covers on/off producer state; the facts/model unit covers checkbox, selected and
unselected radio, an unaffected command row, and vector rejection.  P171 adds
Emacs's line-number radio commands to the closed result allowlist and
`proto-ui-menu-radio-apply-unit` proves that choosing Absolute closes the
popup, runs the backend command, and republishes the same group with Relative
selected on the next choice.  The frontend still never mutates selection.
General radio grouping, icons, and full PGTK popup parity remain pending.
P172 refreshes the authoritative current-step list, records that bounded cursor
styles are now implemented, and replaces stale absolute-pixel input/edit gate
assertions with semantic text/row checks so they remain valid across real frame
character cells.  This is documentation/gate consistency; no producer or
frontend state semantics changed.

P173 extends stateful popup coverage to independent radio groups and gives the
SDL draw path a distinct radio indicator.  The producer self-test now covers a
selected toggle, two on/off radio groups, and a normalized separator in the same
bounded `kind`/`selected` vectors; the smoke walks through a radio row and still
proves both Enter-on-command and Enter-on-submenu behavior.  Popup rows now use
the shared geometry for stable origins: checkboxes keep their 4x4 square, while
a selected radio row draws a 2x2 dot.  The frontend continues to publish only
backend-owned state and never derives or mutates group selection.  Icons and
full PGTK popup parity remain pending.  P174 adds Emacs's line-wrapping radio commands to the closed result
allowlist and extends `proto-ui-menu-radio-apply-unit` to choose Visual Wrap,
then Truncate, proving that two independent radio groups apply through the same
bounded path and republish their backend-owned selections.  Arbitrary commands
remain rejected.  P175 adds bounded menu icon references to `MENU_MODEL` and `MENU_PATCH`
schema 2.  Each non-separator node may name one generation-qualified existing
image resource; partial references and separator icons are rejected, and patch
delete operations must clear both fields.  The SDL popup draw path
draws a complete live resource in the leading slot, shifts its label, and falls
back to the label for missing/stale resources.  The menu smoke now carries a
2x2 resource and requires the exact pixels (`menu_icon`:true).  Live producer
extraction from Emacs `:image` forms and full icon parity remain pending.  P176 is documentation/gate consistency: it refreshes the runbook's menu
evidence to P168-P175, removes stale popup claims, and updates the capability
summary for distinct markers and icon fallback.  P177 publishes each row's bounded printable `:help` as an eighth parallel
producer vector, owns and validates it in the adapter facts, and stores it on
`MENU_NODE.help`; the live Edit-menu smoke requires help on the Undo row
(`popup_help`:true).  Help rendering/tooltip policy is not claimed.  P178 extracts two more parallel vectors from real menu `:image` specs: the bounded resource id is the spec hash normalized to a nonzero `u32` and its generation is 1; invalid or absent images are empty references.  Facts validates the parallel vectors, rejects length mismatches, and projects both fields onto `MENU_NODE`; `proto-ui-menu-icon-unit` pins two distinct specs plus a plain row.  This is reference extraction only—live `IMAGE_DEFINE` payload capture remains pending, so real menus safely fall back to labels until that resource arrives.  P179 initially rendered the highlighted row's already-validated help as a bounded frontend tip.  A shared `menuHelpTip` source placed a one-row panel above the popup when the owner has room, otherwise below it, and suppresses it when neither fits; it reuses popup geometry rather than inventing a second hit/render rectangle.  Its frontend unit pinned text and containment, `sdl3-menu-hit-smoke` proves the drawn tip, and the live Edit-menu smoke then required the drawn Undo help (`popup_help` plus rendered text).  Hover timing, wrapping, and platform tooltip parity were pending.

P180 wraps already-validated popup help greedily at ASCII whitespace into at
most three rows within the owner-derived safe width.  Non-printable, non-ASCII,
and oversized-word help is suppressed, and the tip's above/below fit uses the
actual row count.  The frontend unit pins multi-row wrap and containment, while
`sdl3-menu-hit-smoke` proves multiline rendering and the live smoke proves the
representation; a live popup with no help that fits is correctly suppressed.
Hover timing and platform tooltip parity remain pending.

P181 is documentation/gate consistency for that rendering change.  The
synthetic menu fixture remains the proof that wrapped help reaches the draw
list; the live gate proves the producer published bounded help and no longer
claims a rendered tip when P180 correctly suppresses it.  The capability
manifest now names fixture-proven wrapping separately from live payload
capture and pending hover timing.  No EUP schema, producer vector, or frontend
state semantics changed.

P182 captures bounded live menu icon payloads for real file-backed XBM specs
only.  The producer sends base64 bytes up to the 4096-byte resource bound,
facts validates base64/XBM structure and dimensions, decodes it to RGBA8, and
emits the existing generation-qualified `IMAGE_DEFINE`/`IMAGE_DATA` pair before
the menu model.  Well-encoded malformed or oversized payloads safely fall back
to labels.  The
live Edit-menu smoke appends one structurally valid `gnus-pointer.xbm` row
after the stock rows and
requires a nonzero icon reference backed by a complete, generation-correct
resource.  Other image formats, generated icons, and full image parity remain
pending.

P183 is documentation/gate consistency for that payload capture.  It places
P182 in the milestone sequence, keeps renderer evidence in the synthetic
`sdl3-menu-hit-smoke`, and scopes the live gate to a complete generation-matched
scene resource rather than a separate live draw assertion.  It also rechecks
that the appended fixture does not disturb the Undo-first apply path, and
refreshes the authoritative status rows that still denied bounded faces, fonts,
images, and widgets.  No EUP schema, producer vector, parser, or frontend state
semantics changed.

P184 pins the malformed-XBM fallback boundary.  A well-encoded payload that
passes the bounded facts wire but fails XBM structure validation produces only
the menu model/open pair: no partial image resource is emitted, the
generation-qualified row reference remains intact, and the absent resource
drives the existing frontend label fallback.  Base64-invalid and length-mismatch
inputs remain hard wire errors.

P185 extends that boundary to the payload-size trust boundary.  A well-encoded
payload larger than 4096 decoded bytes is now dropped per row instead of failing
the whole menu snapshot; its nonzero generation-qualified reference survives and
the absent resource selects the existing label fallback.  Invalid base64 and
mismatched producer vectors remain hard errors.  This makes the documented
oversized-payload behavior true at the adapter trust boundary.

P186 is the protocol-accounting companion to P184/P185: the normative EPXL
public-facts wording now names the bounded `icon_payloads` vector, its exact
length/base64 requirements, the per-row malformed-XBM and oversized-payload
fallbacks, and the emitted image-resource pair.  No runtime behavior changed.

P187 rebasines full-Emacs compatibility away from command whitelists.  The
transitional `C-x` whitelist remains rollback-only; the forward path is a
display-frame keymap loop in which SDL emits canonical key events, Emacs's own
command loop consumes `unread-command-events`, and keymaps, prefix arguments,
recursive commands, and mode-specific bindings remain owned by Emacs.

P188 lands the first R8c slice over Terminal Provider Extension.  A selected
provider frame now enters redisplay, realizes TTY-compatible default faces,
captures its desired glyph matrix, and sends one bounded EUP frame update to
SDL3.  The `proto-ui-tpe-frame` gate requires a nonempty row/run snapshot and
SDL3 reports one applied frame update and returns the provider capture acknowledgement.  This is display capture only:
general keymaps, shaped Unicode, faces beyond the default matrix transport,
BiDi, images, resource lifecycle, and full input remain open.  The legacy
`C-x` command translator is not on the provider path and is not compatibility
evidence.

P190 expands the R8d packet from keyboard-only to a fixed 48-byte surface input
envelope with release state and frame pixel coordinates.  SDL mouse buttons map
to standard down/up mouse events, vertical and horizontal motion maps to wheel
events, focus transitions map to focus events, close requests map to
`delete-frame`, and motion updates provider pointer state through the standard
`mouse_position_hook`.  ACK multiplexing now stores input packets encountered
while waiting for a frame acknowledgement instead of rejecting the frame.  The
provider closes quietly when the Emacs side drops the socket.  The
`proto-ui-tpe-input` gate now checks a physical key, mouse press/release, and
vertical wheel through normal `read-event`.

P191 adds native window resize to the same real input path.  SDL sends input
kind 10 with pixel geometry; the adapter-owned `read_socket_hook` invokes
standard delayed `change_frame_size` path.  TPE snapshots now maintain one monotonic provider-session sequence and emit frame creation only for the first redisplay.
The gate verifies a 1200×760 SDL resize through the resulting Emacs frame
geometry and then redraws through the provider snapshot path.  Provider
mouse-face/highlight, IME, and scrollbar routing remain separate work.

P192 upgrades ACK multiplexing from one deferred packet to a bounded 16-packet
queue and makes SDL text-input commit iterate every validated UTF-8 scalar.  The
provider sends each non-ASCII scalar as a standard multibyte keystroke; no
intermediate command table filters the result.  The input gate now proves an
`é` plus CJK `中` commit both reach normal `read-event` after resize packets.
Composed preedit rendering, candidate windows, dead-key state, and full IME
platform integration remain separate work.  Provider mouse-face/highlight and
scrollbar routing also remain separate work.

P189 starts R8d with a real provider input loop, not a command whitelist.  SDL3
remains alive after the first frame and emits fixed `TPEINP1` packets; the
adapter-owned provider terminal installs `read_socket_hook`, registers the
surface fd with the keyboard waiter, parses packets nonblockingly, and stores
standard `input_event`s for Emacs's normal command loop.  The first slice covers
printable keys, Unicode text codepoints, navigation/editing keys, and Shift,
Control, Alt, Super, and Meta state.  Mouse, wheel, focus, resize, drop,
multi-chord completion, IME composition, and provider shutdown/error cleanup are
still open; this does not claim full compatibility.

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
zig build -Dproto-ui=true proto-ui-status
zig build -Dproto-ui=true proto-ui-protocol-coverage
zig build -Dproto-ui=true proto-ui-conformance
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-boundary
zig build -Dproto-ui=true proto-ui-boundary-audit
zig build -Dproto-ui=true proto-ui-recovery-diff
zig build -Dproto-ui=true proto-ui-compat
zig build -Dproto-ui=true proto-ui-isolation-audit
zig build -Dproto-ui=true -Dmodules=true proto-ui-module-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-live-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-facts-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-resync-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-unicode-input-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-menu-open-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-menu-apply-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-cursor-smoke
zig build -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke
```

Future workstreams may name acceptance commands before those commands exist
(as W15/W16 already do).  Such names are design placeholders, not current
gates; when a workstream lands, either implement that exact step or replace it
with a concrete equivalent and move it into the current step list.

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
| Troubleshooting guide | Done for current bounded smokes; final runtime/interactive troubleshooting pending |
| Final capability status report | Current bounded manifest and matrix are done; final W12/W16 report pending |

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

## W18 — SDL3 interactive completion

Status: in progress.  This milestone turns the many bounded proofs into one
usable acceptance path while keeping the pure-runtime boundary explicit.

### W18.1 — Usable diagnostic bridge

`zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true
sdl3-emacs-graphic-interactive --auto-quit-ms=0` must remain open for ordinary
interaction against one display-backed Emacs frame.  The acceptance pass is:

1. ASCII and CJK text insertion through the keyboard/IME commit paths.
2. General prefix commands through `input.keymap_loop_v1`, not a frontend
   command whitelist.
3. Split, navigate, resize, scroll, and delete windows.
4. Pointer selection, wheel scrolling, menu selection, and clipboard paste.
5. Focus, resize, title, mode line, cursor, face, font, and CJK rendering
   remain synchronized until frontend shutdown.

The existing external PGTK/display-backed bridge is diagnostic evidence only;
it does **not** satisfy the pure-runtime completion rule.

### W18.2 — Pure `output_proto` gate (current target)

This milestone is implementation-first: bounded bridge coverage is evidence, not
progress by itself.  The opt-in TPE slice now clears TP1/TP3 at headless
terminal scope: `proto-ui-tpe-headless` creates, identifies, and cleans a real
generic terminal in Emacs.  W18.2 is now blocked specifically at TP4/TP5: one
SDL3-owned `window-system = proto` frame and redisplay-owned capture.  The
remaining order is TP4 real frame lifecycle, TP5 redisplay capture, TP6
returned input, then TP7-TP10 resource/platform/parity/performance completion.  No PGTK fallback, whitelist,
symbol wrapping, or scattered inherited-C policy edits are allowed; any TP1 core
seam must be generic, opt-in, reviewed, and rollback-safe.

### W18.3 — Aggregate gate

Current minimum aggregate:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-graphic-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-emacs-acceptance --summary all
```

`sdl3-emacs-acceptance` currently composes window split, navigation, restore,
and pointer selection.  Expand it to include the Unicode/IME, scrolling, and
menu gates as their build-graph scopes permit.  Passing this slice proves the
current bridge only; W18.1 manual interaction and W18.2 pure runtime remain
required for the final goal.
P193 preserves provider mouse button identity through the standard input event.
SDL3 physical button IDs map to normal Emacs `mouse-1`, `mouse-2`, and `mouse-3`
symbols; the input gate exercises middle and right press/release through
`read-event` with the same keymap and command-loop ownership as the existing
left-button slice.  Extra provider buttons remain separate compatibility work.
P194 carries SDL3 horizontal wheel ticks through the same canonical TPE input
packet path.  Provider `wheel.x` maps to standard Emacs `wheel-left` and
`wheel-right` events without a provider-side command table; the input gate now
exercises both directions after vertical wheel delivery.  Momentum, high-
resolution wheel deltas, and platform-specific acceleration remain separate work.
