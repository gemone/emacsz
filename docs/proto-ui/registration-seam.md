# Proto-UI Terminal Registration Seam

Status: TP2 adapter policy implemented; TP1 opt-in generic headless terminal implemented; SDL frame, redisplay, and full runtime remain absent
Protocol: EUP v1
R8 runtime state: fail closed
Date: 2026-09-10

## 1. Purpose

This document defines the only acceptable way to turn the selected pure-SDL3
adapter from `linked_not_registered` into a real `output_proto` terminal.  It
is a design contract, not an implementation claim.  GNU Emacs has no public
dynamic-module API that can add a terminal type, install a graphic redisplay
interface, create a graphic frame owned by that terminal type, or make
`(window-system . proto)` true.

Consequently, a no-core-change registration route is impossible under this
contract.  The choice is not “extension versus core change”; it is a generic,
reviewed core extension versus unsafe aliasing, interposition, or patching.

The design is a **Terminal Provider Extension (TPE) v1**: one reviewed generic
extension contract in Emacs core, plus all terminal behavior in a Proto-UI-owned
provider adapter.  Subsystems that consume terminal capabilities may require
small, mechanical dispatch through that contract; this remains distinct from
scattered Proto-UI feature branches.  TPE replaces the rolled-back historical
patches that placed `output_proto` policy through inherited core files.

Until TPE exists and is explicitly enabled, the candidate adapter remains a
linked but uncalled object.  It must not initialize at load time, register a
terminal, masquerade as PGTK/TTY, or change default Emacs behavior.

## 2. Non-negotiable boundaries

### 2.1 Ownership

| Truth | Owner |
|---|---|
| Buffer text, undo, markers, overlays | Emacs |
| Command loop, keymaps, input interpretation | Emacs |
| Frame, window, face, font, and image policy | Emacs |
| Redisplay timing, layout, rows, cursor truth, damage decisions | Emacs |
| Terminal identity and lifetime | Emacs |
| Provider registry and dispatch | Emacs core extension |
| Terminal-provider implementation | Proto-UI adapter |
| EUP encoding, session, recovery, resource identity | Proto-UI adapter |
| SDL windows, GPU/software rendering, platform input capture | SDL3 frontend |

The provider may cache observations for one atomic EUP update, but it must not
become a second layout engine.  The frontend must not mutate Emacs state except
by returning validated intents through the adapter.

### 2.2 Forbidden integration mechanisms

TPE must not be implemented by:

1. `LD_PRELOAD`, symbol wrapping, symbol interposition, or linker `--wrap`.
2. A replacement `main`, startup constructor, or load-time initialization.
3. Binary patching or runtime mutation of Emacs data structures.
4. Generated replacement or in-place patching of a tracked inherited C file.
5. Reusing `output_pgtk`, TTY, Android, or another output-method value while
   relabeling it as `proto`.
6. Initializing GDK/GTK and then capturing or replacing its rendered output.
7. Calling undocumented internal Emacs entry points from a dynamic module.
8. Moving redisplay, window layout, face merging, or buffer mutation to SDL3.

These mechanisms may appear to work in a smoke test, but they cannot provide a
safe disable path, GC-safe identity, backend dispatch, or upstream
maintainability.

## 3. TPE v1 architecture

```text
Emacs core
  generic Terminal Provider dispatch
        |  provider table + opaque core handles
        v
Proto-UI provider adapter
  terminal/frame/redisplay/input translation
        |  PureRuntimeHostV1 / EUP
        v
SDL3 frontend
```

Emacs gains one generic provider concept.  All Proto-UI policy remains outside
inherited files.  The inherited core change is a platform extension point, not
an `output_proto` feature branch.

`output_proto` is the external compatibility name for the selected SDL3
provider.  The terminal's internal classification is generic
`output_provider`; provider behavior and the `proto` Lisp identity come from
the registered provider table.

### 3.1 Core-owned registry

Emacs owns a bounded registry of registered providers.  Registration is an
explicit opt-in startup operation, never an ELF constructor or implicit
provider discovery.  `zig build` links one adapter-owned provider manifest
object for the selected provider.  The core reads only the stable manifest
symbol declared by TPE; adding a provider does not add provider-specific core
references.  A provider entry contains:

1. stable provider name (`proto`);
2. Lisp identity symbol (`proto`);
3. ABI major version and exact table size;
4. provider capability flags;
5. provider callback table;
6. provider-owned state pointer, allocated only after validation;
7. monotonic registration generation;
8. optional feature-negotiation manifest.

Names and Lisp identity symbols are immutable after registration.  Duplicate
names or symbols fail closed.  Unregistration is allowed only when the provider
has no live terminal and no pending input transaction.

### 3.2 Generic output method

TPE adds one generic `output_provider` terminal classification to Emacs.  It
does not add an `output_proto` case to every backend switch.  Core dispatch
asks the selected provider for backend behavior; the provider symbol supplies
the user-visible identity:

```elisp
(terminal-live-p terminal)             => 'proto
(framep frame)                         => 'proto
(frame-parameter frame 'window-system) => 'proto
```

Internal code asks the provider for graphic capability, pixel geometry, event
delivery, and resource behavior.  A provider that does not declare a required
capability receives conservative TTY behavior rather than inheriting another
graphic backend.

Capability fallback is per operation, not per backend.  A provider without
graphic capability may register headlessly but cannot create a proto graphic
frame.  A provider without input capability may not activate an interactive
terminal.  Selection, menus, dialogs, tooltips, images, or fonts are optional
only when the capability manifest says so; calls to unsupported operations
return an explicit unsupported status or a conservative TTY equivalent.  They
never transparently create a GDK/GTK, X, Windows, NS, Haiku, or Android
backend.

### 3.3 Provider-owned storage

TPE reserves generic provider slots in terminal and frame storage.  The slots
are opaque to core and are allocated on behalf of the selected provider:

```c
/* Shape shown for design only; ownership and GC rooting are normative. */
void *terminal_provider_data;
void *frame_provider_data;
uint32_t provider_generation;
```

Core never dereferences these slots.  The adapter allocates and frees them
through provider callbacks.  Lisp objects exposed through provider data are
registered as GC roots for exactly the lifetime of the owning terminal or frame.

This replaces the historical `struct proto_output`, scattered `FRAME_PROTO_P`
branches, and direct `output_proto` fields.

## 4. C ABI contract

The seam is two versioned tables.  Core-to-provider operations are supplied by
the adapter.  Provider-to-core operations are supplied by Emacs so the adapter
never reaches into private globals.

### 4.1 Provider table

| Field/group | Requirement |
|---|---|
| `table_size` / `abi_version` | Exact ABI v1 size and version; mismatch fails closed |
| `name` / `identity_symbol` | Stable UTF-8 name `proto` and rooted Lisp symbol `proto` |
| `flags` | Explicit graphic, input, selection, tooltip, menu, and image capability bits |
| terminal lifecycle | create, activate, delete; exactly-once teardown and ID retention |
| frame lifecycle | register, unregister, read state/geometry; generation-qualified mapping |
| redisplay capture | begin/commit/cancel plus window, row, run, cursor, and damage observation |
| resource capture | resolved face, font, image metadata and bounded fragments |
| input delivery | key/text/pointer/wheel/event result and completion status |
| lifecycle | heartbeat, flush, diagnostic, and cancellation of pending work |
| `provider_state` | Adapter-owned context, allocated only after table validation |

Missing required callbacks or a size/version mismatch prevents registration.
Optional callbacks are published in a capability manifest.  A missing optional
callback yields an explicit unsupported status, never a fallback to another GUI.

### 4.2 Core host table

The core host table gives the adapter only allocation, rooting, terminal/frame
query, event enqueue, safe logging, and lifecycle operations.  It does not expose
raw buffer editing, redisplay traversal, or command interpretation.

| Group | Core operations |
|---|---|
| Memory/root | allocate/free provider data; register/unregister GC roots |
| Terminal | validate handle; terminal identity and live/deleted state |
| Frame | validate handle; geometry, visibility, focus, selected window |
| Event | enqueue validated key/text/pointer/wheel intents |
| Lifecycle | nonblocking diagnostics, deadline scheduling, safe cancellation |

Every function returns a bounded status code.  Each callback is callable only
from its documented thread.  Long work is scheduled; it never blocks the Emacs
main loop.

The v1 provider table wraps the existing `PureRuntimeHostV1` callback groups
rather than inventing a second adapter ABI.  Terminal, frame, redisplay,
input, and lifecycle group versions, sizes, non-null callbacks, contexts, and
the aggregate table hash must match the R8-linked adapter provenance.  TPE
adds registration and provider-selection metadata around those groups; it does
not widen their wire or callback semantics in this design.

### 4.3 Calling, GC, and lifetime rules

Core-to-provider lifecycle, frame, redisplay, and input callbacks run only on
the Emacs main thread.  Provider transport work runs on adapter-owned threads
and reaches core only through main-thread-safe enqueue/scheduling callbacks.
No provider thread may read Emacs objects, evaluate Lisp, install input, or
block waiting for the main loop.  Reentrancy is explicit: a callback must not
re-enter the same operation while that operation is active.

Core host callbacks are borrowed-pointer calls.  A provider may retain only
generation-qualified handles and adapter-owned copies of bounded display
facts.  It must not retain raw terminal, frame, window, buffer, face, font, or
image pointers beyond the callback.

Provider data slots are stable C allocations owned by the provider.  Core
never moves or scans them.  A provider must not store a raw pointer to a
relocatable Lisp object.  Every Lisp value retained across callback return is
registered through the core root API and unregistered in reverse acquisition
order before its owning terminal/frame or provider state is freed.  Root
registration fails closed on a dead owner, duplicate root, or callback error.
GC may run only at core-designated safepoints; it never calls into provider
transport threads.

## 5. Registration and rollback

### 5.1 Registration sequence

```text
disabled
  -> provider_table_validated
  -> provider_registered
  -> terminal_provider_selected
  -> terminal_created
  -> terminal_activated
  -> transport_ready
  -> frame_capability_ready
```

The activation sequence is intentional and auditable:

1. Build links the adapter under explicit opt-in flags.
2. A user starts Emacs with the provider enabled.
3. Core validates table version, size, name, symbols, flags, and callbacks.
4. Core roots provider identity and allocates provider state.
5. Provider creates an inactive terminal record.
6. Provider opens the authenticated local EUP transport.
7. Core accepts the terminal only after transport readiness.
8. Proto frame creation becomes available.

No step starts SDL3 itself.  The frontend connects as a separate process.  If no
frontend connects, an inactive proto terminal may exist only when its lifecycle
contract permits it; it must not create an OS window or GDK/GTK dependency.

### 5.2 Failure rollback

Reverse order is mandatory:

```text
frontend.transport_stopped
  -> redisplay.capture_cancelled
  -> frames.unregistered
  -> terminal.drained
  -> terminal.deleted
  -> provider_state.freed
  -> gc_roots.released
  -> provider.unregistered
```

Failure at any step quarantines the affected provider but preserves the Emacs
process.  IDs and generations of deleted or failed objects are never reused.
The default build and a provider-disabled build must not contain the runtime
initialization path.

Every rollback step is idempotent and has a finite deadline.  A missing
frontend connection makes transport stop a successful no-op; a failed callback
is logged, bounded, and retried only when the lifecycle contract says the retry
is safe.  After terminal deletion and root release complete, core marks the
provider quarantined and refuses reactivation in that Emacs session.  A
separate frontend or process may retry by explicit user action, but a
quarantined provider table is never re-registered implicitly.

## 6. First-frame acceptance contract

The first TPE-backed frame is accepted only when all checks pass in one Emacs
process:

```elisp
(setq frame (make-frame
             '((window-system . proto)
               (width . 100)
               (height . 40))))
(frame-live-p frame)                       => t
(frame-parameter frame 'window-system)     => 'proto
(terminal-live-p (frame-terminal frame))   => 'proto
```

The SDL3 frontend must present the frame and pass:

1. initial geometry equals Emacs's authoritative values;
2. one coherent initial `FRAME_UPDATE`;
3. ASCII insertion updates point, cursor, and visible rows;
4. `delete-frame` closes the SDL window and destroys adapter mappings;
5. terminal delete drains the transport and releases provider data;
6. no GDK/GTK initialization occurs in the proto process;
7. non-proto behavior in the same process is unchanged;
8. frontend crash does not crash Emacs.

This is still not PGTK parity.  It is only the first real-frame gate.

The graphic-frame acceptance build must not create a PGTK initial frame.  Run
it as a provider-only TTY/daemon initial session, then create the proto frame
in that same process.  This proves that pure SDL3 owns the first graphic frame
without GDK/GTK initialization.  A PGTK-enabled process that already created a
PGTK frame may test coexistence later, but it cannot satisfy the pure-first-
frame gate.

First-frame evidence records the binary and feature flags, startup output
method, provider registration generation, terminal/frame IDs and generations,
all eight checks, cleanup status, and the frontend-crash containment result.
Any missing evidence, failed reverse rollback, retained root, leaked provider
slot, or reused generation fails the gate.

## 7. Work split after the seam exists

| Task | Result | Completion evidence |
|---|---|---|
| TP0 | Freeze TPE v1 design | This document plus review manifest |
| TP1 | Generic core provider extension | Opt-in generic `output_provider` headless dispatch passes live Emacs gate; upstream proposal and broader rollback patch remain |
| TP2 | Proto-UI provider adapter | Table validation and fake-core conformance |
| TP3 | Headless terminal lifecycle | Explicit opt-in create/activate/cleanup gate passes; multi-terminal batch and direct recreate dispatch remain |
| TP4 | Real proto frame lifecycle | `window-system=proto` and SDL frame create/delete |
| TP5 | Redisplay-owned updates | Atomic rows/cursor/damage EUP updates |
| TP6 | Input return path | Keyboard/pointer/wheel intents interpreted by Emacs |
| TP7 | Resource streaming | Faces, fonts, images, cache and eviction |
| TP8 | Platform integration | Focus, resize, DPI, selection, menus, dialogs, tooltips |
| TP9 | PGTK differential matrix | All 48 planned cases have implemented/degraded/unsupported status |
| TP10 | Performance acceptance | Reference-host latency/FPS/CPU/bandwidth budgets pass |

TP1 production integration is not authorized by the current adapter-first
default.  It requires a separate reviewed exception or acceptance as an
upstream extension.  `proto-ui-tpe-core` is only an owned host-test reference
slice and does not link into Emacs or alter inherited behavior.  TP2 has a
bounded adapter-side witness in `proto-ui-tpe-registration`: it validates the
canonical `proto` descriptor, exact PureRuntimeHostV1 inventory, explicit
fake-core registration states, quarantine, generation retention, and reverse
rollback.  It is not a core extension, Emacs registration, or runtime.  Until
TP1 exists, R8 remains `linked_not_registered` and fail closed.

## 8. Performance contract

TPE itself adds only provider dispatch and bounded observation.  The measured
targets remain in [`performance.md`](performance.md):

1. input-to-Emacs ACK p95 below 8 ms on the reference host;
2. committed update-to-present p95 below 8 ms for bounded text scenes;
3. unchanged-frame presentation skipped with CPU below 0.3 ms p95;
4. no allocation on the steady-state unchanged-frame path;
5. adapter payload bandwidth reported in bytes/frame and MiB/s;
6. explicit GPU/software renderer tier and fallback counters.

Provider dispatch must be O(1) for terminal/frame lookup.  Capture iteration is
linear in observed windows and rows and bounded by the active capability
manifest.  No lock is held across provider callback and frontend transport.

## 9. Documentation and evidence gates

TP1 through TP10 may not claim completion without:

1. `proto-ui-unit` and `proto-ui-boundary`;
2. ABI/table negative tests;
3. default-build isolation audit;
4. linked/registered state provenance;
5. terminal/frame lifecycle smoke;
6. EUP replay and recovery equality;
7. frontend crash containment;
8. PGTK differential results;
9. machine-readable benchmark JSON;
10. adapter-boundary audit proving no scattered inherited-C Proto-UI logic.

Generated JSON is evidence, not the source of truth.  Proto-UI Zig and the
reviewed TPE specification are authoritative.

## 10. Current completion boundary

Implemented today:

* reviewed R7 policy approval;
* selected pure-SDL3 provider candidate;
* adapter-only TP2 registration-policy conformance against a fake core;
* an owned `proto-ui-tpe-core` registry/lifecycle conformance slice;
* an opt-in generic `output_provider` headless terminal under the runtime build (default-off);
* opt-in native-glibc target linkage audited as `linked_not_registered`;
* complete EUP codec/transport/frontend design and bounded bridges.

Not implemented:

* full TPE frame/redisplay/input production dispatch;
* default runtime registration;
* a real SDL3-owned `window-system=proto` frame;
* redisplay-owned EUP streaming;
* PGTK parity;
* final performance acceptance.

Green bounded bridges do not change this boundary.
