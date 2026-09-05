# Proto-UI Implementation Plan

Status: active planning baseline
Goal: implement a real SDL3-backed Emacs UI through EUP without breaking existing Emacs behavior

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

## 2. Current status

| Area | Status |
|---|---|
| Architecture specification | Documented |
| EUP protocol specification | Documented |
| Capability/PGTK parity matrix | Documented |
| EUP envelope/resource/FRAME_UPDATE skeleton | Partial |
| Memory sink and replay-file transport | Partial |
| SDL3 frontend design | Documented |
| Performance baseline | Documented |
| Build option `-Dproto-ui` | W2 registration, W3a lifecycle identity, W3b terminal lifecycle |
| W2 registration seam | Approved |
| W3a lifecycle identity | Approved |
| W3b terminal lifecycle | Approved |
| W3c lifecycle-only frame objects | Approved |
| Automated W3c frame smoke | Implemented |
| `output_proto` terminal | Approved |
| Redisplay capture | Not implemented |
| Resource model | Not implemented |
| SDL3 frontend | Not implemented |
| Real SDL3 Emacs smoke test | Not achieved |

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

Status: approved. The W1 protocol/transport skeleton is complete.

Implemented W1 evidence:

1. `src/proto-ui/protocol.zig` encodes/decodes the 62-byte envelope, capability name/value table, resource identity, and the `FRAME_UPDATE` concrete header/section envelope.
2. `src/proto-ui/transport.zig` implements ordered memory-sink and bounded replay-file primitives.
3. `zig build -Dproto-ui=true proto-ui-unit --summary all` passes.
4. The dedicated reviewer completed three-plus passes and approved the W1 skeleton on commit `9548f0a6a4d`.
5. Native, foreign-target host-runner, clean-export, and default-build gates were reproduced by the reviewer.

### W1 — Protocol implementation skeleton

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

### W4 — Redisplay capture foundation

Goal: make normal redisplay visible in EUP.

Tasks:

1. Implement update begin/end capture.
2. Implement window geometry and zone capture.
3. Implement row creation/update/deletion.
4. Implement clear-area damage.
5. Implement cursor capture.
6. Implement frame flush boundary.
7. Encode these into composite `FRAME_UPDATE`.
8. Add redisplay replay fixtures.

Deliverables:

* Backend redisplay interface.
* Damage accumulator.
* `FRAME_UPDATE` encoder integration.

Acceptance:

A headless test inserts text, runs redisplay, and asserts:

```text
update begin
window patch
row update
glyph run
cursor update
damage
flush
```

Review gates:

1. Redisplay hook coverage.
2. Atomic update correctness.
3. Absence of buffer text layout in frontend.

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

### W9 — SDL3 frontend skeleton

Goal: open a real window from a live proto frame.

Tasks:

1. Add SDL3 frontend build option.
2. Add frontend process entry point.
3. Implement EUP client negotiation.
4. Implement SDL window lifecycle.
5. Implement software renderer fallback.
6. Apply frame/window/row updates.
7. Render cursor and basic faces.
8. Present initial frame.

Acceptance:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
```

The smoke test must show a real SDL3 window with visible Emacs text and cursor.

Review gates:

1. SDL lifecycle correctness.
2. Protocol client safety.
3. Process isolation from Emacs.

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
zig build -Dproto-ui=true proto-ui-replay-test
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-bench
zig build check
```

All commands must pass with artifacts retained.

## 4. Build/test surface to implement

Planned build options:

```sh
-Dproto-ui=true
-Dsdl3-frontend=true
```

Planned steps:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-roundtrip
zig build -Dproto-ui=true proto-ui-smoke
zig build -Dproto-ui=true proto-ui-replay-test
zig build -Dproto-ui=true proto-ui-conformance
zig build -Dproto-ui=true proto-ui-fuzz
zig build -Dproto-ui=true proto-ui-bench
zig build -Dproto-ui=true proto-ui-diff
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
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
| Protocol schema examples | Pending W1 |
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
