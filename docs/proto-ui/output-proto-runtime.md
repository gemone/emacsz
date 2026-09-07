# `output_proto` Runtime Bridge Design

Status: normative design; R1 terminal lifecycle core, R2 fail-closed runtime manifest, R3 generated thin C adapter, R4 shared host-observation library, R5 frame service mapping, R6 atomic capture batches, and R7 pending host-decision infrastructure are implemented; runtime is not implemented
Protocol: EUP v1
Boundary rule: no intrusive edits to inherited GNU Emacs C files

## 1. Purpose

This document defines how Proto-UI reaches the final runtime shape:

```text
GNU Emacs terminal/frame/redisplay truth
  -> Proto-UI-owned output_proto host adapter
  -> versioned host/adapter seam
  -> EUP transport
  -> SDL3 frontend
```

It separates the work that can proceed today in Proto-UI-owned code from the
integration points that require an explicit host extension decision.  It does
not declare `output_proto` implemented and does not treat the existing PGTK
frame smoke as production frame ownership.  The normative pure-SDL3 target and
PGTK responsibility/parity matrix are defined in
[`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md).

## 2. Feasibility decision

GNU Emacs has no public dynamic-module API to register a new terminal type,
install a graphic terminal, or replace a terminal's redisplay interface.  A
real `output_proto` terminal therefore cannot be created by protocol code
alone.

The project consequently uses a three-part rule:

1. **Build the adapter without inheriting core policy.**  Terminal lifecycle,
   frame mapping, capture translation, damage policy, protocol encoding,
   recovery, transport, and diagnostics live in Proto-UI-owned Zig or generated
   adapter artifacts.
2. **Keep the runtime option fail closed.**  Until a versioned host extension
   contract supplies the required callbacks, `-Dproto-ui-runtime=true` builds
   only the adapter and explicitly reports that runtime registration is
   unavailable.  It must not silently fall back to PGTK or TTY frames.
3. **Do not scatter edits through inherited core files.**  If upstream-style
   registration is later approved, it must be represented by a reviewed
   integration manifest, a separate Proto-UI-owned C adapter, generated thin
   glue, and a compatibility gate.  Logic must remain outside inherited Emacs
   C files.

The existing dynamic-module bridge and PGTK frame smoke are compatibility
evidence and diagnostic fixtures.  They are not `output_proto`.

## 3. Runtime components

| Component | Owner | Responsibility | Explicitly excluded |
|---|---|---|---|
| Host extension adapter | Proto-UI-owned C/ABI adapter | Convert opaque host objects and events to adapter records; enforce ABI size/version | Redisplay policy, buffer mutation, protocol encoding |
| Terminal lifecycle | Zig adapter | Terminal create/activate/destroy generations and failure cleanup | Buffer, window, or frame semantics |
| Frame manager | Zig adapter | Stable frame IDs, generations, visibility/focus, geometry facts | Window-tree layout |
| Window/row capture | Zig adapter | Translate authoritative host observations into atomic EUP updates | Reflow, glyph shaping, face merging |
| Resource manager | Zig adapter | Face/font/image/string identity, payload versions, eviction, requests | Font fallback policy or image decoding policy |
| Damage/pacing | Zig adapter | Conservative and exact damage, coalescing, update cause, backpressure | Presentation scheduling |
| EUP codec/session | Zig protocol | Canonical envelope, payload tables, sequencing, resync | Frontend scene policy |
| Transport | Adapter/frontend endpoints | Local authenticated framing, ACK, recovery | Untrusted remote transport in v1 |
| SDL3 frontend | Separate process | Window, input, GPU/software render, IME/desktop integration | Emacs state authority |

## 4. Host extension contract

The host adapter must be registered through one versioned table, not global
scattered symbols.  The current `HostV1` observation seam is retained.  The
runtime contract adds these callback groups:

| Group | Required operations | Ownership rule |
|---|---|---|
| Terminal | create terminal, activate terminal, delete terminal | Emacs owns terminal truth; adapter owns protocol identity |
| Frame | register frame, unregister frame, read frame state, read geometry | Emacs owns frame truth; adapter maps identity/generation |
| Window/redisplay | begin capture, observe window/row/run/cursor/damage, commit/cancel | Emacs owns display truth; adapter owns EUP translation |
| Input | deliver decoded event/result and completion status | Emacs owns command interpretation |
| Lifecycle | heartbeat, flush, diagnostic, cancel all pending work | Adapter owns protocol/session state |

Every callback contract has:

1. A stable ABI major version and table size.
2. Generation-qualified opaque IDs; raw internal pointers never cross the seam.
3. A bounded result/status code.
4. Explicit allocation and borrow lifetimes.
5. A documented nonblocking guarantee.
6. A fake-host conformance test and a negative malformed-table test.

Missing optional callbacks degrade only capabilities that can be represented
correctly without them.  Missing required callbacks disable Proto-UI runtime.

## 5. Terminal lifecycle

### States

```text
registering
  -> active
  -> draining
  -> deleted

registering | active | draining
  -> failed
  -> deleted
```

### Transition rules

| Transition | Requirement | Failure behavior |
|---|---|---|
| `detached -> registering` | Host accepts terminal registration and supplies terminal generation | Remain detached |
| `registering -> active` | Required callbacks validated; frontend session authenticated and ready | Cancel frontend and destroy partial terminal |
| `active -> draining` | Last EUP sequence and resource state committed; no partial frame in flight | Continue draining, then report cleanup result |
| `draining -> deleted` | Terminal deleted, adapter session closed, frontend socket drained | Kill frontend endpoint without killing Emacs |
| any `-> failed` | ABI mismatch, callback failure, protocol resource exhaustion, or internal adapter error | Quarantine terminal, preserve Emacs process, emit diagnostics |

`deleted` is the retained record that represents the externally detached
terminal.  The registry retains deleted and failed records so their IDs and
latest generations can never be reused.

Terminal and frame IDs are never reused.  Terminal deletion invalidates all
frame mappings and wakes or closes every owned transport endpoint.

## 6. Frame and redisplay path

### Frame creation

1. Host asks for a `proto` graphic frame.
2. Host adapter registers a nonzero frame ID and first generation.
3. Adapter emits `FRAME_CREATE`.
4. Host reports geometry and visibility.
5. Adapter emits a coherent initial `FRAME_UPDATE`.
6. SDL3 acknowledges presentation and platform state.
7. Only a fully initialized frame enters the active map.

### Redisplay update

1. Host begins an atomic capture generation.
2. Adapter records window, row, run, cursor, damage, and flush observations.
3. Host commits only when its display state is coherent.
4. Adapter resolves resources and validates every reference before encoding.
5. Adapter emits one composite `FRAME_UPDATE`.
6. A failure after encoding cancels the update and never publishes partial
   scene state.

### Frame state changes

Visibility, focus, geometry, title, icon, monitor, scale, and z-order are host
observations or frontend requests translated by the adapter.  The frontend
never changes Emacs state directly.

## 7. Input path

1. SDL translates a platform event into a bounded EUP intent.
2. The adapter validates class, frame/window identity, modifiers, text, and
   sequence.
3. The host adapter converts the intent into host input primitives.
4. Emacs performs all command, keymap, selection, scrolling, and focus
   decisions.
5. The next redisplay observation becomes authoritative feedback.

The frontend may cache key names and device IDs, but it never invents commands,
mutates buffers, selects frames, or assumes command results.

## 8. Session, recovery, and failure containment

* Frontend disconnect marks the session disconnected but must not terminate
  Emacs.
* Adapter failure disables the terminal and cleans up through host callbacks.
* Protocol sequence loss triggers `RESYNC_REQUEST` and a coherent snapshot.
* Missing resources are requested by identity/generation; rendering waits or
  falls back according to negotiated policy.
* Transport pressure may coalesce frame updates but never control, input, or
  required resource messages.
* All owned endpoints and temporaries have bounded cleanup deadlines.
* A crash of SDL, the transport thread, or a frontend renderer cannot corrupt
  Emacs Lisp objects.

## 9. Build model

Current and target options:

| Option | Meaning | Status |
|---|---|---|
| `-Dproto-ui=true` | Adapter protocol/ABI, conformance, replay, and optional frontend smokes | Implemented in bounded slices |
| `proto-ui-host-contract` step | Generate and audit the source-authoritative registration decision | Implemented; decision is pending and runtime unavailable |
| `proto-ui-r7-proposal` step | Generate and audit the pure-SDL3 R7 registration proposal | Implemented; proposal is ready for review, decision remains pending, and runtime is unavailable |
| `proto-ui-pgtk-parity-plan` step | Generate and audit the planned PGTK-to-Proto differential matrix | Implemented as planning policy; all 48 cases remain planned and parity is not implemented |
| `proto-ui-protocol-coverage` step | Audit every assigned EUP message ID against its implementation status | Implemented; 39 codecs implemented, 3 partial, and 122 planned |
| `session` module | Standard EUP HELLO/HELLO_ACK/SESSION_READY/READY_ACK codecs and setup state machine | Implemented as protocol preparation; not yet wired to EPXL transport |
| `proto-ui-runtime-host` step | Validate the five-group versioned `PureRuntimeHostV1` ABI with a fake host | ABI conformance implemented; registration is absent and runtime remains fail closed |
| `proto-ui-runtime-host-abi` step | Generate, compile, and conformance-test the C projection of `PureRuntimeHostV1` | Implemented; generated header is installed under `zig-out/include/proto-ui` and remains unlinked from Emacs |
| `runtime_bridge` module | Drive the pure host ABI in both directions: frames, runs, input lifecycle, visibility/focus state, host lifecycle operations, and authoritative geometry | Fake-host unit and SDL3 presentation conformance implemented; no Emacs host, transport, or registration |
| `-Dmodules=true` | Public dynamic-module observation bridge | Implemented in bounded slices |
| `-Dproto-ui-runtime=true` | Require the future host extension contract; without it the boundary fails with `host_registration_contract_missing` | Fail-closed audit/gate implemented; runtime absent |
| `-Dproto-ui-frontend=true` | Install and smoke the independent SDL3 frontend | Design for final name; current SDL option remains opt-in |

Build artifacts must live in `zig-out` or cache output.  Generated adapters and
shims are never written into tracked inherited source paths.  A runtime build
manifest must record:

1. ABI version and table sizes.
2. Required versus optional callbacks.
3. Adapter source and generated artifacts.
4. Terminal registration contract and its owner.
5. Feature status and evidence gates.
6. A machine-readable reason when runtime registration is unavailable.

## 10. Work split to the first real frame

| Task | Output | Complete when |
|---|---|---|
| R1. Terminal lifecycle core | Zig terminal state machine, IDs, generations, failure cleanup | Fake-host tests cover every transition and cleanup path |
| R2. Runtime manifest | Machine-readable runtime contract and unavailable reason | Build fails closed with an explicit diagnostic without host callbacks |
| R3. Generated thin C adapter | Minimal conversion shim, no policy | Implemented as generated `shim.c` plus `proto-ui-shim-conformance` |
| R4. Host adapter library | Linkable read-only host-observation library | Exported ABI conformance and symbol isolation pass |
| R5. Frame service | Frame create/state/delete mapping | Implemented with bounded host-handle to EUP-frame mapping and fake-host coverage |
| R6. Capture service | Window/row/cursor/damage atomic batches | Implemented with fake, Scene-apply, and replay byte-stability tests |
| R7. Host registration contract | Explicit reviewed extension decision | Infrastructure implemented; decision remains pending and registration is forbidden |
| R8. First terminal smoke | Real `window-system . proto` frame | Emacs creates, displays, operates, and deletes one SDL3 frame |
| R9. Differential compatibility | PGTK vs Proto-UI behavior suite | Frame, text, cursor, input, scroll, resize, and lifecycle baselines pass |

P5 preparation extends `PureRuntimeHostV1.RunRecord` with a bounded
printable-ASCII payload and geometry so `runtime_bridge` can project host runs
into existing debug `GLYPH_RUN` messages.  Production shaped runs remain pending.
A P4-preparation `runtime_bridge` now drives validated `PureRuntimeHostV1`
callbacks and emits bounded frame lifecycle/update messages for fake-host
conformance.  It is not linked to an Emacs host and does not authorize terminal
registration.
P3 also projects `PureRuntimeHostV1` to C through
`proto-ui-runtime-host-abi`.  The generated `pure_runtime_host_v1.h` and C
conformance translation unit are build artifacts outside inherited source; they
prove the future host adapter shape without attaching one to Emacs.
P3 preparation adds `PureRuntimeHostV1` in `src/proto-ui/runtime_host.zig`.
Its five required nested callback groups now have an executable adapter-owned
ABI, validators, and a fake-host conformance fixture.  This is review and
integration preparation only; no Emacs host adapter is selected, linked into a
frame path, or called by terminal registration.

R7 is the policy gate.  It must not be bypassed by hidden binary patching,
symbol interposition, generated replacement of tracked C files, or runtime
mutation of Emacs data structures.

Implemented progress: **R1-R7 infrastructure is implemented**.  R1 is the adapter-owned
terminal lifecycle in `src/proto-ui/terminal.zig`; R2 is
`src/proto-ui/runtime.zig`, the generated
`zig-out/proto-ui/runtime_manifest.json`, and the nonzero
`-Dproto-ui-runtime=true` boundary gate.  R3 is the generated `shim.c` and
`proto-ui-shim-conformance` gate.  R4 installs that exact generated artifact
as `zig-out/lib/libproto-ui-shim.so` and proves dynamic ABI conformance plus
symbol isolation.  R5 adds `FrameService` for bounded host-handle to EUP-frame
mapping, generation/visibility/focus refresh, delete-once teardown, and terminal
drain.  R6 adds deterministic window/row/cursor/damage `FRAME_UPDATE` encoding,
stale-generation commit guards, and replay byte-stability evidence.  R7 adds
the deterministic `host_registration_contract.json`, contract gate,
runtime-manifest reference, and capability descriptor.  Its decision is
`pending` with `host_registration_contract_missing`; approved decisions will
require complete review metadata and every policy/evidence field before the
gate passes.  R8-R9 remain not implemented; in particular, there is no terminal
registration, redisplay-owned EUP generation, transport, or real
`output_proto` frame.

## 11. Acceptance for the first real SDL3 frame

The milestone is complete only when all of the following are true from one
local command sequence:

1. Default builds without Proto-UI remain byte-for-byte behavior-compatible at
   the user-visible level.
2. `output_proto` appears as a real terminal type and creates a real Emacs
   graphic frame.
3. SDL3 opens the visible surface for that frame.
4. Buffer text, point, cursor, resize, visibility, focus, keyboard, mouse,
   wheel, clipboard, and frame deletion work through the documented protocol.
5. No command path lets the frontend evaluate Elisp or own layout.
6. Session replay, malformed protocol input, frontend disconnect, GPU loss, and
   adapter restart tests pass without crashing Emacs.
7. Capability status, protocol table, ABI manifest, and implementation evidence
   agree.
8. Frame creation, typing, scrolling, and resize meet the performance baselines
   in [`performance.md`](performance.md).

Until R8, all status documents must continue to describe this work as adapter
groundwork rather than a real `output_proto` runtime.

## 12. Non-goals

This design does not:

* make SDL3 a core Emacs dependency;
* move buffers, windows, faces, fonts, redisplay, or commands to the frontend;
* replace PGTK or TTY;
* expose raw GPU command buffers or untrusted remote transport in v1;
* use the PGTK bridge as fake evidence of `output_proto` ownership;
* permit scattered or hidden modifications to inherited Emacs source.
