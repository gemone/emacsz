# Zig Build Adapter Runtime

Status: normative design
Protocol: EUP v1
Boundary rule: adapter-first; no intrusive edits to inherited GNU Emacs C files

## 1. Purpose

This document defines how Proto-UI is embedded through `zig build` without
turning GNU Emacs into a Proto-UI implementation.  Emacs remains authoritative
for buffers, windows, frames, faces, fonts, input semantics, and redisplay.
The adapter observes or delegates through a versioned boundary, translates
state into EUP, and hands presentation to the independent SDL3 frontend.

This design supersedes the intrusive normal-RIF prototype.  That prototype was
quarantined because it modified inherited display files.  Future work must use
the build-owned adapter model described here.

## 2. Non-negotiable rules

1. **No tracked inherited-C edits.**  `zig build` must not rewrite, patch, or
   generate replacements inside tracked GNU Emacs C source files.
2. **Adapter-first.**  Protocol, session, damage, resource, transport, replay,
   diagnostics, frontend policy, and state-machine logic belong to
   Proto-UI-owned Zig code.
3. **Thin seam only.**  If C ABI glue is required, it lives in a Proto-UI-owned
   adapter and contains type conversion plus delegation only.
4. **Versioned ABI.**  Every host/adapter interface has a major version, an
   ABI size table, explicit ownership, and a compatibility check.
5. **Opaque boundaries.**  GNU Emacs data structures are not exposed to SDL3
   and are not manipulated by frontend code.
6. **Fail closed.**  A missing, incompatible, or failed adapter disables
   Proto-UI; it never degrades TTY, PGTK, Windows, macOS, Haiku, or Android
   behavior.
7. **Deterministic build.**  Generated adapter artifacts live in the Zig build
   cache/output tree, have stable paths, and record their source manifest and
   content digest.

## 3. Runtime shape

```text
GNU Emacs process
  inherited Emacs core
    |
    | versioned host adapter seam
    v
Proto-UI adapter runtime
  capture translator, session, damage/resource model, EUP encoder
    |
    | EUP transport
    v
SDL3 frontend process
  scene model, input bridge, renderer, GPU/software presentation
```

The adapter runtime is a Proto-UI-owned component.  It may execute in the
Emacs process only for time-sensitive capture and dispatch.  All protocol,
frontend, rendering, and transport policy remains owned by the adapter or
frontend.

## 4. Build-owned embedding model

`zig build` is the integration control plane.  It never patches tracked
inherited Emacs C files in place.

### 4.1 Source layout

```text
src/proto-ui/
  adapter.zig           authoritative ABI/ownership manifest and runtime
  protocol.zig          EUP codec and assigned message tables
  transport.zig         bounded memory sink and ERP1 replay codec
  conformance.zig       fake-host ABI conformance
  abi_gen.zig           generated C header and ABI summary
  boundary_audit.zig    changed-path boundary classifier
  root.zig              module/test aggregator

tools/proto-ui-sdl3/
  main.zig              independent window/renderer lifecycle smoke
  fixture.zig           deterministic FRAME_CREATE/FRAME_UPDATE ERP1 writer
```

Generated content is written only to:

```text
.zig-cache/o/<hash>/
zig-out/lib/
zig-out/bin/
zig-out/include/proto-ui/
```

### 4.2 Build phases

1. **Manifest selection.**  `zig build` selects the adapter profile declared by
   `-Dproto-ui` and future frontend options.
2. **ABI generation.**  Emit `proto-ui/abi_v1.h`, symbol tables, and a JSON or
   Zig manifest describing sizes, ownership, and version requirements.
3. **Shim generation.**  Generate a thin C shim from a Proto-UI-owned template.
   The shim converts ABI arguments and immediately calls Zig adapter entry
   points.
4. **Compile/link.**  Compile the shim and link the Zig adapter library.
5. **Boundary audit.**  Validate paths, symbols, exported ABI, and feature
   isolation.
6. **Conformance gate.**  Run adapter contract tests against a fake host.
7. **Optional integration.**  Attach the adapter to an existing stable Emacs
   extension point.  If no stable point exists, mark the feature unavailable.

### 4.3 Generated shim rules

The generated shim may:

* receive arguments from a host call,
* validate ABI version and pointer/null contracts,
* convert C integer and byte-slice types,
* acquire a short-lived lock required by the adapter,
* call one Zig adapter function,
* return a status code or an adapter-allocated result.

The generated shim must not:

* own redisplay decisions,
* modify buffer text,
* encode EUP payloads,
* allocate Lisp objects,
* call frontend-specific APIs,
* contain transport policy,
* depend on a particular GUI toolkit.

### 4.4 Manifest example

```json
{
  "abi_version": 1,
  "eup_major": 1,
  "eup_minor": 0,
  "adapter": "proto-ui",
  "sources": [
    "src/proto-ui/adapter.zig"
  ],
  "generated": [
    "proto-ui/abi_v1.h",
    "proto-ui/shim.c"
  ],
  "symbols": [
    "proto_ui_adapter_abi_version",
    "proto_ui_adapter_session_create",
    "proto_ui_adapter_capture_begin",
    "proto_ui_adapter_capture_row",
    "proto_ui_adapter_capture_damage",
    "proto_ui_adapter_capture_flush"
  ],
}
```

## 5. Versioned host/adapter ABI

The adapter is invoked through two versioned tables rather than scattered
global symbols.

### 5.1 Host table

The host exposes opaque capabilities to the adapter:

| Field | Meaning |
|---|---|
| `abi_version` | Host ABI major version |
| `host_size` | Size of host table for compatibility |
| `frame_get_geometry` | Query authoritative frame geometry |
| `window_get_geometry` | Query authoritative window geometry |
| `buffer_get_display_facts` | Query display-safe row facts |
| `face_get_public_facts` | Query face ID and public visual facts |
| `font_get_public_metrics` | Query public font metrics |
| `input_inject` | Translate frontend intent into Emacs input |
| `timer_schedule` | Schedule adapter work |
| `diagnostic_log` | Emit adapter diagnostics |

Every object is represented by a generation-qualified opaque handle.  The host
table never exposes raw internal matrices or frontend-owned memory.

### 5.2 Adapter table

The adapter exposes capture and lifecycle services:

| Field | Meaning |
|---|---|
| `abi_version` | Adapter ABI major version |
| `adapter_size` | Size of adapter table for compatibility |
| `session_create` | Create EUP session |
| `frame_create` | Register frame identity |
| `frame_destroy` | Tear down frame identity |
| `capture_begin` | Begin an atomic capture generation |
| `capture_window` | Observe window metadata |
| `capture_row` | Observe row metadata |
| `capture_cursor` | Observe cursor metadata |
| `capture_damage` | Observe damage |
| `capture_flush` | Encode and publish atomically |
| `input_dispatch_result` | Accept frontend input result |

### 5.3 Ownership and lifetime

| Data | Owner | Borrow rules |
|---|---|---|
| Buffers, rows, frames, windows | Emacs | Host reads facts during callback |
| EUP payload | Adapter | Adapter allocates, encodes, and frees |
| Scene model | Frontend | Built exclusively from EUP |
| Transport socket/pipe | Adapter/frontend endpoint | Explicit handoff only |
| Texture and atlas memory | Frontend | Generation-qualified cache |

Callbacks must not block.  Long work is queued to the adapter transport thread.

## 6. Capture model

Normal display capture is split into three phases.

### 6.1 Observation

A thin shim forwards only the event required by an existing Emacs extension
point.  The adapter converts the observation into an adapter-owned record:

```text
event kind
frame/window opaque handle
generation
logical rectangle
row identity
safe public metrics
damage rectangle
sequence timestamp
```

The adapter does not retain borrowed internal pointers.

### 6.2 Translation

The adapter maps observed facts to EUP records.  It resolves stable IDs,
applies damage coalescing, marks missing resources, and assigns the update to
an atomic generation.

### 6.3 Publication

The adapter validates the complete update and writes it to EUP transport.  A
partial update is cancelled.  Frame updates may coalesce; control and resource
messages remain reliable and ordered.

## 7. Workstream split

### W4c-b1-b0 — ABI summary and fake-host conformance

1. Add versioned host and adapter table descriptions.
2. Generate ABI headers and a non-normative ABI summary from `zig build`.
3. Implement a fake host conformance harness.
4. Test success, bad ABI, bad generation, null callback, partial update, and
   cancellation paths.

Acceptance: all generated files are outside tracked inherited C sources; fake
host and adapter conformance tests pass.

### W4c-b1-b1 — Thin shim and symbol isolation

1. Generate a shim that only converts and delegates.
2. Link it through `zig build`.
3. Export only the declared adapter table.
4. Verify no inherited C source changes and no new default-build symbols.

Acceptance: default `-Dproto-ui=false` link graph has no Proto-UI symbols;
optional build passes ABI and symbol isolation tests.

### W4c-b1-c — Adapter-owned normal-RIF streaming

1. Register a normal-RIF capture route through the versioned adapter table.
2. Capture rows, cursor, damage, clear events, and update boundaries.
3. Coalesce compatible updates and reject incomplete generations.
4. Preserve row order, window ownership, cursor state, scrolling, truncation,
   continuation, and BiDi visual-order facts needed by later rendering.
5. Add replay captures and synthetic-versus-real comparisons.

Acceptance: real-frame redisplay emits coherent atomic `FRAME_UPDATE` metadata
without rendering; glyph, face, font, and image resource capture remain W5.

### W4c-b1-d — Replay and differential validation

1. Persist ordered real-frame captures to replay files.
2. Decode and compare synthetic, historical, and real-frame fixtures.
3. Verify sequence, generation, row, damage, cursor, and resource-reference
   consistency.
4. Add malformed-capture fuzz fixtures.

Acceptance: replay round trips remain byte-identical; malformed inputs never
crash Emacs or the frontend.

## 8. Failure model

| Failure | Required behavior |
|---|---|
| ABI mismatch | Adapter unavailable; diagnostic emitted |
| Capture overflow | Cancel current update; retain prior coherent state |
| Transport backpressure | Coalesce frame updates; never block Emacs |
| Frontend disconnect | Emacs continues; adapter resynchronizes on reconnect |
| Generated shim failure | Proto-UI disabled; existing backends unchanged |
| Renderer device loss | Frontend rebuilds or falls back to software |

Every failure path must identify the last committed generation and prove that
no partial EUP state was committed.

## 9. Validation gates

Required gates:

```sh
zig fmt --check src/proto-ui build.zig
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true proto-ui-conformance --summary all
zig build --summary all
```

The boundary report must show:

1. Manifest schema and ABI version are valid.
2. All integration owners are adapter, protocol, frontend, or build.
3. No normal-RIF integration point is implemented inside Emacs core.
4. No generated file is written into tracked inherited C source paths.
5. Default-build symbol and behavior isolation remain clean.

## 10. Definition of done

The Zig-build adapter runtime is complete when:

1. A fake host and real adapter satisfy ABI conformance.
2. A generated thin shim links through `zig build` without inherited-C edits.
3. Real-frame normal-RIF capture runs through the versioned adapter table.
4. Rows, cursor, damage, clear events, and flush boundaries are captured
   atomically.
5. Replay and conformance fixtures pass.
6. SDL3 can consume the resulting EUP stream and present a frame.
7. Existing Emacs builds and behavior remain unchanged when Proto-UI is
   disabled.
