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
| SDL3 frontend | Partial: continuous real Emacs public-fact stream validated as EUP snapshots and rendered; no EPXL streaming, input, faces, or complete live recovery |
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
| Build option `-Dsdl3-frontend` | EUP replay, local live, and opt-in continuous Emacs public-fact modes; the Emacs mode is process/public-API observation, not EUP transport or redisplay-hook streaming |

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

### W10 — GPU renderer path

Goal: add optional acceleration without making it required.

Tasks:

1. Add renderer tier negotiation.
2. Add software-to-GPU renderer abstraction.
3. Implement glyph atlas.
4. Implement image texture cache.
5. Implement blend/scissor drawing.
6. Implement damage-aware redraw.
7. Implement vsync/adaptive present.
8. Implement atlas miss fallback.
9. Add GPU performance counters.

Acceptance:

1. GPU unavailable -> software fallback.
2. GPU available -> renderer reports actual tier.
3. Typing/scroll meet Tier 1 performance baseline.
4. No stale pixels after damage.

Review gates:

1. Renderer fallback correctness.
2. GPU lifecycle/device-loss safety.
3. Performance evidence.

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

### W12 — Complete EUP feature surface

Goal: close PGTK parity gaps.

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
zig build -Dsdl3-frontend=true sdl3-ui-smoke
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
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
