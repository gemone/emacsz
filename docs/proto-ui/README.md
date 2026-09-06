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

W10a adds adapter-owned SDL renderer negotiation: the frontend reports the actual renderer tier, supports explicit software/GPU/named-driver selection, and falls back from GPU to software when required. W10b-a adds change-aware full-frame presentation with frontend full-frame-path and present/skip counters. W10b-b1 adds a reusable backend-neutral clear/fill/text draw list executed by SDL software and GPU-backed renderers. It also adds bounded SDL key/text translation, cursor/backspace artifact actions, and explicit monotonic reverse-input sequencing with one in-flight EPXL intent, exact transport ACK matching, and an Emacs apply-ACK before that transport ACK. Glyph atlas, image cache, blend/scissor, rectangle damage, native GPU counters, and full interactive-frame compatibility remain pending; persistent EPXL input subsequently arrived through W8c/W8d and now supports bounded pointer sessions. W11a adds the first bounded desktop clipboard paste path: Ctrl+V captures printable SDL clipboard text through the same validated input queue. W11b adds the matching bounded copy path: Ctrl+C observes an Emacs smoke buffer, publishes the validated first line through a local artifact, and SDL3 installs it in the platform clipboard; Unicode, rich text, MIME negotiation, and selection ownership remain pending. W10b-b2a adds a bounded adapter-owned glyph-atlas placement/LRU policy with hit/miss/eviction counters. W10c-a adds conservative initial/cursor/viewport/unchanged damage classification and counters; unchanged scene states skip presentation. W10c-b uses a bounded old/new cursor clip for cursor-only changes to avoid a full clear/redraw, while text/viewport changes remain full-frame and GPU timestamps remain pending. Texture allocation and glyph-run rendering remain pending.

W4c-b1-p0 adds the executable EUP v1 codec, including envelope, capability, message-ID, and FRAME_UPDATE section conformance.  W4c-b1-t0 adds bounded memory-sink sequencing and ERP1 replay-file conformance.  W4c-b1-b0 adds the versioned adapter ABI, a fake-host conformance harness, and generated ABI artifacts under `zig-out/include/proto-ui`; none introduces runtime integration.  Inherited C/Lisp changes in the rollback patch are restoration-only and return Proto-UI runtime files to their pre-Proto-UI state.  The adapter source is the authoritative ownership manifest; generated JSON is only a non-normative ABI summary.

The documentation in this directory is the source of truth for the implementation workstreams.

## 3. Documents

Available:

| Document | Contents |
|---|---|
| [`architecture.md`](architecture.md) | System components, ownership model, backend integration, state model, failure rules, and compatibility contract |
| [`adapter-boundary.md`](adapter-boundary.md) | Normative adapter-first boundary, C-file restrictions, review gates, and rollback requirements |
| [`zig-build-adapter.md`](zig-build-adapter.md) | Normative Zig-build adapter runtime, versioned ABI, generated shim rules, and streaming redesign |
| [`protocol.md`](protocol.md) | Complete EUP v1 wire protocol, envelope, message IDs, payload semantics, and state machines |
| [`capabilities.md`](capabilities.md) | Backend, frontend, renderer, widget, and PGTK parity capability matrices |
| `sdl3-frontend.md` | SDL3 process model, window handling, input bridge, rendering pipeline, and platform integration |
| `performance.md` | Performance tiers, budgets, test scenarios, instrumentation, and regression gates |
| `implementation-plan.md` | Workstreams, concrete tasks, acceptance gates, and final definition of done |

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

# Run protocol, replay, and headless UI tests.
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true proto-ui-smoke
zig build -Dproto-ui=true proto-ui-replay-test

# Build the independent SDL3 frontend.
zig build -Dproto-ui=true -Dsdl3-frontend=true

# Run the real frontend acceptance test.
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke
```

Exact step names may be refined during implementation, but the final build must expose these capabilities.

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
