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
| Resource model | Not implemented |
| SDL3 frontend | Partial: token-authenticated EPXL facts streaming with producer coalescing and initial-session resync; bounded ASCII input bridge only; no redisplay streaming, keyboard/keymap/IME input, faces, or full recovery |
| Real SDL3 Emacs smoke test | Not achieved |
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
| W9g2 bounded viewport facts | Approved |
| W10b-b2a bounded glyph-atlas policy | Approved |
| W10c-a damage classification baseline | Approved |
| W10c-b cursor-only clipped redraw | Approved |
| W10c-c bounded text-region clipping | Approved |
| W12a EPXL capability/status manifest | Approved |
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
5. Implement icon/string resources.
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

Implemented limits: only vertical line ticks are supported; horizontal scroll,
pixel/page units, momentum/touchpad phase, smooth deltas, precise scroll
position, and full window-scroll state remain pending.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-wheel-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-pointer-smoke
```

Status: approved. The dedicated reviewer completed correctness, integration/build, and boundary/docs/status passes; approved fixes rejected zero/horizontal/diagonal, flipped-direction, and fractional/mismatched wheel deltas, and corrected reverse-input idempotence docs. Final checks verified wheel smoke, pointer/interactive regressions, boundary and inherited-C audits, and the full built-in check run.

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
4. `proto-ui-module` builds the adapter-owned artifact; a batch gate loads it
   through `module-load` and verifies `proto-ui-echo`.

The seam is intentionally public-API-only.  It does not expose redisplay
internals, input, resources, fonts, text content, or a complete Proto-UI frame.

Acceptance:

```sh
zig build -Dproto-ui=true -Dmodules=true proto-ui-module-smoke --summary all
```

The gate builds a modules-enabled Emacs and loads the adapter module in the same
batch process.

On a display-capable host, `proto-ui-frame-fact-smoke` opens Emacs briefly,
observes public frame/window dimensions, validates the JSON fields, and exits:

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

### W9j — Public ASCII text observation (approved)

Goal: move the first real visible-window text from public Emacs APIs through
EPXL into the SDL3 renderer, while keeping the full glyph/face/font model
adapter-first and explicitly future work.

Implemented:

1. The facts smoke observes visible window text with public
   `window-buffer`, `window-start`, `window-end`, and
   `buffer-substring-no-properties` calls.
2. `facts.parseText` bounds text to 32 lines and 120 printable-ASCII columns per
   line and owns decoded line storage.
3. `appendWireSnapshot` emits adapter-owned extension section `0x8000`; each
   record maps one text line to an existing row index and is length bounded.
4. `frontend.Scene` decodes text atomically with the rest of `FRAME_UPDATE`,
   validates row mapping, uniqueness, ordering limits, and printable ASCII, and
   owns the null-terminated line storage.
5. SDL3 renders each line with its debug text facility at the mapped row.  The
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


Tasks:

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

Tasks:

1. Add envelope fuzzing.
2. Add payload-table fuzzing.
3. Add sequence-gap tests.
4. Add stale-generation tests.
5. Add missing-resource tests.
6. Add reconnect/replay tests.
7. Add frontend crash isolation tests.
8. Add deterministic snapshot comparison.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-conformance
zig build -Dproto-ui=true proto-ui-replay-test
zig build -Dproto-ui=true proto-ui-fuzz
```

No malformed input may crash Emacs.

Review gates:

1. Parser safety.
2. Recovery correctness.
3. Resource bounds.

### W14 — Performance hardening

Goal: prove the documented performance improvement.

Tasks:

1. Add machine-readable benchmark harness.
2. Benchmark frame creation, typing, scroll, resize, faces, fonts, images, widgets, and multi-frame.
3. Add allocation counters.
4. Add bandwidth counters.
5. Add latency percentiles.
6. Tune damage merging.
7. Tune glyph atlas.
8. Tune transport slab reuse.
9. Compare software, GPU basic, and GPU advanced tiers.

Acceptance:

```sh
zig build -Dproto-ui=true proto-ui-bench
```

The benchmark must meet `performance.md` targets and preserve results as evidence.

Review gates:

1. Measurement correctness.
2. Hot-path efficiency.
3. Correctness under optimization.

### W15 — Emacs compatibility validation

Goal: prove “fully compatible with existing Emacs capabilities” within the declared capability matrix.

Tasks:

1. Run default build and existing tests.
2. Run PGTK build and GUI smoke tests.
3. Run proto UI differential smoke suite.
4. Compare TTY/PGTK/proto redisplay semantics for text, windows, faces, cursor, scroll, and frames.
5. Verify existing Lisp APIs on proto frames.
6. Verify proto removal/disabled state leaves no runtime trace.
7. Document every deliberate degradation.

Acceptance:

```sh
zig build check
zig build -Dpgtk=true check
zig build -Dproto-ui=true check
zig build -Dproto-ui=true proto-ui-diff
```

Existing capabilities must remain green. Proto-specific gaps must be explicit and non-breaking.

Review gates:

1. Default-build compatibility.
2. Existing backend isolation.
3. Emacs semantic correctness.

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
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-bench
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
| SDL3 frontend architecture | Done |
| Performance baseline | Done |
| Workstream plan | Done |
| Protocol schema examples | Done (adapter-only) |
| User runbook | Pending W9 |
| Troubleshooting guide | Pending W13 |
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
