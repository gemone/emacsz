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

The repository contains the complete English design baseline. W1-W3c add the approved EUP protocol/transport skeleton, opt-in Emacs registration, real terminal lifecycle, and lifecycle-only invisible frame objects. W4a adds a reviewed synthetic `FRAME_UPDATE` capture path. W4b adds reviewed real after-update window geometry and row metadata capture bounded to 256 rows. W4c-a adds reviewed bounded damage capture and safe redisplay-interface coverage. W4c-b0 adds reviewed headless frame visibility transitions and update-count observability. W4c-b1-a's direct-core real-row fixture was reverted and quarantined under the adapter-first rule. Glyph, face, font, and image resource capture, generic graphic frame creation, SDL3 windows, and the final objective remain pending adapter-first work.

The documentation in this directory is the source of truth for the implementation workstreams.

## 3. Documents

Available:

| Document | Contents |
|---|---|
| [`architecture.md`](architecture.md) | System components, ownership model, backend integration, state model, failure rules, and compatibility contract |
| [`adapter-boundary.md`](adapter-boundary.md) | Normative adapter-first boundary, C-file restrictions, review gates, and rollback requirements |
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

must add `output_proto` without removing or weakening any existing backend.

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
