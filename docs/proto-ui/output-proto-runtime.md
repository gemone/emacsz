# `output_proto` Runtime Bridge Design

Status: normative design; R1 terminal lifecycle core, R2 fail-closed runtime manifest, R3 generated thin C adapter, R4 shared host-observation library, R5 frame service mapping, R6 atomic capture batches, and R7 approved policy/candidate-selection infrastructure is implemented; runtime is not implemented
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
   and, on a supported target, links only the adapter candidate.  Runtime-state
   gates require the ELF link audit and explicitly report that runtime
   registration is unavailable.  The option must not silently fall back to PGTK
   or TTY frames.
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

Widget reverse intents such as dialog results follow the same rule.  The v1
adapter can validate and transport a bounded button/text result only when the
capability is negotiated; host callbacks remain the sole authority for actual
dialog completion.

Dedicated scrollbar events follow the same bounded path: the frontend may send
only the negotiated absolute/relative payload and never applies scrolling
directly to Emacs state.

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
| `proto-ui-host-contract` step | Generate and audit the source-authoritative registration decision | Implemented; R7 is approved for policy/candidate selection only and runtime unavailable |
| `proto-ui-r7-proposal` step | Generate and audit the pure-SDL3 R7 registration proposal | Implemented; proposal records the approved policy decision and runtime is unavailable |
| `proto-ui-tpe-registration` step | Validate the canonical provider descriptor, exact `PureRuntimeHostV1` shape, fake-core state transitions, quarantine, retention, and rollback policy | Implemented as adapter-only TP2 policy; TP1 dispatch, production registration, and runtime remain absent |
| `proto-ui-pgtk-parity-plan` step | Generate and audit the planned PGTK-to-Proto differential matrix | Implemented as planning policy; all 48 cases remain planned and parity is not implemented |
| `proto-ui-protocol-coverage` step | Audit every assigned EUP message ID against its implementation status | Implemented; 164 codecs implemented, 0 partial, and 0 planned |
| `session` module | Standard EUP setup/control codecs, setup state machine, Scene control integration, automatic frontend PONG, and EPXL transport for every standard control | Implemented as bounded adapter-first protocol coverage; full Emacs runtime ownership remains pending |
| `proto-ui-runtime-host` step | Validate the five-group versioned `PureRuntimeHostV1` ABI with a fake host | ABI conformance implemented; registration is absent and runtime remains fail closed |
| `proto-ui-runtime-host-abi` step | Generate, compile, and conformance-test the C projection of `PureRuntimeHostV1` | Implemented; generated header is installed under `zig-out/include/proto-ui` and remains unlinked from Emacs |
| `runtime_bridge` module | Drive the pure host ABI in both directions: frames, runs, input lifecycle, visibility/focus state, host lifecycle operations, and authoritative geometry | Fake-host unit and SDL3 presentation conformance implemented; no Emacs host, transport, or registration |
| `-Dmodules=true` | Public dynamic-module observation bridge | Implemented in bounded slices |
| `-Dproto-ui-runtime=true` | Require the future host extension contract; without linked registration it fails with `runtime_host_linkage_or_registration_missing` | Fail-closed audit/gate implemented; runtime absent |
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
| R7. Host registration contract | Explicit reviewed extension decision | Infrastructure implemented; R7 is approved for policy/candidate selection only, registration remains forbidden until linkage |
| R8. First terminal smoke | Real `window-system . proto` frame | Emacs creates, displays, operates, and deletes one SDL3 frame |
| R9. Differential compatibility | PGTK vs Proto-UI behavior suite | Frame, text, cursor, input, scroll, resize, and lifecycle baselines pass |

### 10.1 R7 reviewer packet

The deterministic R7 review packet is source-authoritative and fail closed:

```sh
zig build -Dproto-ui=true proto-ui-r7-review-packet --summary all
cat zig-out/proto-ui/r7_review_packet.json
```

The packet embeds SHA-256 provenance for five generated review artifacts and
builds/validates each exact artifact: the approved registration proposal,
approved registration contract, selected host-adapter record, activation
contract blocked by missing linkage/registration, and R8 readiness record.  The
runtime design is carried as an explicit, unverified reference document.  The
packet records six approved reviewer checks:

1. pure-SDL3/`output_proto` boundary policy;
2. no edits, replacement, patching, or interposition in tracked inherited
   Emacs C/Lisp source;
3. complete versioned terminal/frame/redisplay/input/lifecycle callback table;
4. reproducible prerequisite, fail-closed, pure-frame, and differential
   evidence gates;
5. reverse rollback and default-build isolation;
6. complete reviewer metadata with the approved policy-only scope.

The gate compares every generated input byte-for-byte with the source-derived
artifact and records the completed R7 review, including reviewer, decision ID,
review time, and approval scope.  This approval selects only policy and the
host-adapter candidate.  It does not link Emacs, register a terminal, or enable
runtime; activation remains a separate explicit path and cannot happen
implicitly.

P5 preparation extends `PureRuntimeHostV1.RunRecord` with a bounded
printable-ASCII payload and geometry so `runtime_bridge` can project host runs
into existing debug `GLYPH_RUN` messages.  Production shaped runs remain pending.
It also adds `FaceRecord`, `FontRecord`, and `ShapedRunRecord` observations
plus bounded `FACE_DEFINE`, `FONT_DEFINE`, and schema-3 `GLYPH_RUN` emission.
Face captures may reference a live captured font; shaped runs must reference
that live face/font pair.
It also adds bounded RGBA8 `ImageDefineRecord`/`ImageFragmentRecord`
observations and `IMAGE_DEFINE`/`IMAGE_DATA` emission, currently capped at four
1 KiB fragments per image.
The fail-closed runtime contract now inventories the complete redisplay
callback set, including face, font, shaped-run, and image capture operations.
The R7 proposal records these as implemented adapter prerequisites while the
host-decision gate is approved; linkage and registration remain absent.
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
ABI, validators, and a fake-host conformance fixture.  This is integration
preparation only: no Emacs host adapter is linked into a frame path or called
by terminal registration.

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
`approved` with complete metadata and scope `policy_and_candidate_selection_only`.
The fail-closed reason is now
`runtime_host_linkage_or_registration_missing`; every policy/evidence field
continues to be gate-checked.  R8-R9 remain not implemented; in particular, there is no terminal
registration, redisplay-owned EUP generation, transport, or real
`output_proto` frame.
The newer terminal service additionally orchestrates fake-host
create/activate/drain/delete callbacks with generation-safe registry state and
drain retry/rollback handling; it still cannot register an Emacs
terminal.
The host-adapter selection manifest records the pure-SDL3 candidate as selected
by the approved, metadata-complete R7 decision, but it remains unlinked.
Selection never enables runtime automatically.
The activation contract records the approved-path order and reverse rollback
order.  Its current gate is blocked by missing linkage/registration and performs
no Emacs host callback.

## 11. R8 entry readiness gate

R8 may begin only after the selected adapter is linked under the approved
host-extension decision without touching tracked inherited C/Lisp source.  The
decision must be separate from the adapter code and must make the activation
path, ownership boundary, and disable path reproducible.

An R8-ready decision record contains:

1. the exact adapter-owned extension artifact and its ABI/table hash;
2. the build-graph injection point that links it without changing default
   behavior;
3. proof that no tracked inherited C/Lisp path is edited, replaced, patched, or
   symbol-interposed;
4. the reviewed terminal/frame/redisplay/input/lifecycle callback table;
5. a feature flag and activation manifest that remain off by default;
6. a reverse rollback order that restores terminal, frame, transport, and
   frontend state after any failure;
7. named review evidence for static isolation, fake-host conformance, process
   crash containment, and the fail-closed runtime manifest.

A fake-host smoke, public-fact stream, replay renderer, or PGTK diagnostic is
never sufficient to mark R8 ready.  R7 policy approval is complete, but the
transition additionally requires the selected adapter to be linked and a
reviewed, versioned registration contract to exist without implicit runtime.

`proto-ui-r8-readiness` makes this gate executable.  Its normal pass result
means the audit successfully proved that R8 is still blocked and no inherited
source edits are declared.  `-Dr8-entry-gate=true proto-ui-r8-readiness` is the
negative launch check: it returns `r8_host_adapter_linkage_or_registration_missing` until the
source-authoritative readiness record, approved R7 decision, selected host
adapter, linkage, and registration agree.

W12n now prepares the linkage evidence without activating it.
`src/proto-ui/runtime_host_adapter_lib.zig` builds a host-audit candidate shared
artifact, installed for the native host as
`zig-out/lib/libproto-ui-runtime-host-adapter.so` (Zig selects the host-platform
suffix and Windows DLL/import-library forms).  It validates a caller-supplied
`PureRuntimeHostV1` table, rejects a null table, and refuses adapter creation
with a fail-closed status.  The build probe verifies the exported ABI version,
table size, null-table rejection, and blocked creation.
`zig-out/proto-ui/r8_adapter_linkage.json` records the build artifact ID,
injection point, ABI version/table size, and a canonical SHA-256 inventory of
all five callback groups and 27 operations.  It also reports an empty
inherited-source edit list.  Default linkage is `prepared_not_linked`;
`proto-ui-r8-adapter-linkage` verifies the exact manifest and, on the host
target, the exported candidate ABI.

W12n-a adds a separate, opt-in target-specific path.  On a native Linux glibc
target only, `-Dproto-ui-runtime=true` builds the adapter source as a static
candidate, links it into temacs, forces
`proto_ui_runtime_host_adapter_abi_version`, and runs `proto-ui-r8-link`.
That gate parses the real ELF and records the symbol plus the adapter artifact
hash as `linked_not_registered`; runtime-state adapter-linkage and readiness
gates depend on that audit before they may use the linked state.  This remains
linkage evidence only: there is no inherited-source call, load-time
initialization, terminal registration, `output_proto` enablement, runtime
availability, performance claim, or change to PGTK/TTY.

The only selected path from `linked_not_registered` to a real terminal is the
generic Terminal Provider Extension defined in
[`registration-seam.md`](registration-seam.md).  TP2 provides adapter-side
fake-core policy conformance only; its TP1 core seam remains design-only until
a separate reviewed core-extension exception or upstream acceptance exists.
Output-method aliasing, startup interception, and inherited-symbol wrapping are
forbidden.

### 11.1 First-frame execution slices

When the entry gate is satisfied, implement R8 in these verifiable slices:

| Slice | Minimum evidence |
|---|---|
| R8a terminal registration | A reviewed terminal callback creates and deletes one `output_proto` terminal with no frame; cleanup is idempotent |
| R8b frame handoff | Emacs creates one real frame whose `window-system` reports `proto`; SDL3 owns the visible surface |
| R8c display capture | One authoritative buffer/window/frame update reaches EUP and renders; no frontend state authority |
| R8d input loop | Keyboard, pointer, wheel, focus, and resize round trips return completion through the host input callbacks |
| R8e lifecycle containment | Disconnect, malformed EUP, GPU loss, frontend exit, and explicit shutdown leave Emacs operable |

## 12. Acceptance for the first real SDL3 frame

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

## 13. Non-goals

This design does not:

* make SDL3 a core Emacs dependency;
* move buffers, windows, faces, fonts, redisplay, or commands to the frontend;
* replace PGTK or TTY;
* expose raw GPU command buffers or untrusted remote transport in v1;
* use the PGTK bridge as fake evidence of `output_proto` ownership;
* permit scattered or hidden modifications to inherited Emacs source.
