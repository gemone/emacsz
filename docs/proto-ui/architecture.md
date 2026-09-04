# Proto-UI Architecture

Status: normative design baseline
Protocol: EUP v1
Implementation status: specification complete; W1 protocol/transport skeleton complete; W2 registration seam complete

## 1. Purpose

Proto-UI is an optional Emacs terminal backend that exports redisplay semantics to an external UI frontend. It is not a window toolkit and not a replacement for PGTK.

Its responsibilities are deliberately narrow:

1. Register an Emacs terminal type.
2. Capture terminal and redisplay-interface events.
3. Translate display state into EUP messages.
4. Publish resources needed to render the display.
5. Translate frontend input intent into Emacs input.
6. Maintain protocol sessions, resources, damage, and replay state.

## 2. Component map

```text
GNU Emacs core
  Buffer/window/frame/face/font/redisplay truth
        |
        v
output_proto backend
  Terminal capture, protocol session, resource mapping, damage model
        |
        v
EUP transport
  Shared memory, Unix socket, pipe, memory sink, or replay file
        |
        v
SDL3 frontend
  Real windows, input, renderer, platform integration
        |
        v
OS display
```

## 3. Ownership

### 3.1 Emacs core owns

| Domain | Authoritative state |
|---|---|
| Buffers | Text, point, mark, narrowing, overlays, text properties |
| Windows | Window tree, splits, selection, start position, scroll, margins, fringes |
| Frames | Existence, parameters, visibility, focus, geometry semantics, parent/child frames |
| Redisplay | Glyph matrices, rows, runs, cursor, damage, truncation, continuation, BiDi visual order |
| Faces and fonts | Face merging, face IDs, font selection, fontsets, shaping metrics |
| Commands | Key and mouse bindings, command execution |
| Selection semantics | Ownership intent, target policy, accepted formats |
| Widget semantics | Menu model, enabled state, dialog handling, tooltip content |
| Desktop policy | Clipboard intent, DND acceptance, security decisions |

### 3.2 Proto-UI backend owns

| Domain | Responsibility |
|---|---|
| Session | Session ID, generations, sequence numbers, lifecycle |
| Object mapping | Stable Emacs frame/window/resource to EUP ID mapping |
| Redisplay capture | Translation of terminal and redisplay hooks into EUP updates |
| Resources | Publication and versioning of faces, fonts, images, bitmaps, icons, atlas pages |
| Damage | Accumulation and coalescing |
| Transport | Reliable control/resource delivery and coalescable frame delivery |
| Recovery | Replay, snapshot fallback, resynchronization |
| Input translation | Frontend intent to Emacs input events |

The backend must not reinterpret Elisp, perform independent layout, own visible truth, or draw final pixels.

### 3.3 SDL3 frontend owns

| Domain | Responsibility |
|---|---|
| Window system | Window creation, destruction, move, resize, fullscreen, maximize, iconify |
| Displays | Monitor enumeration, workarea, scale, DPI, refresh rate |
| Presentation | Renderer selection, GPU/CPU drawing, present mode, pacing |
| Input capture | Keyboard, text, mouse, wheel, touch, gesture, focus |
| IME bridge | Platform IME activation, preedit display, commit forwarding |
| Clipboard | OS clipboard and selection access |
| DND | OS drag-and-drop negotiation and transfer |
| Widget presentation | Menu, dialog, tooltip, scrollbar, tool bar, tab bar rendering |
| Renderer cache | Textures, glyph atlas, image cache, GPU memory |

The frontend may cache rendered state but never owns semantic UI state.

## 4. Emacs integration contract

### 4.1 Terminal identity

Proto-UI adds a new terminal type:

```text
output_proto
```

A proto frame is a real graphic Emacs frame:

```elisp
(make-frame '((window-system . proto)))
(framep frame) => proto
(window-system frame) => proto
(display-graphic-p frame) => t
```

### 4.2 Existing-file seams

No new C source file is added. Changes to existing C code are limited to generic registration and dispatch seams.

| File | Required change |
|---|---|
| `src/termhooks.h` | Add `output_proto` to `enum output_method` |
| `src/frame.h` | Add proto frame storage, `FRAME_PROTO_P`, and include it in `FRAME_WINDOW_P` |
| `src/frame.c` | Map proto frames and terminals to the `proto` Lisp symbol |
| `src/terminal.c` | Recognize `output_proto` in terminal type conversion |
| `src/dispnew.c` | Allow proto as an initial graphic window system |
| `src/xdisp.c` | Avoid assumptions that every graphic frame owns a native toolkit widget |
| `build.zig` | Add option, macro, Zig object linkage, and test steps |
| `lisp/term/proto-win.el` | Standard initialization and frame creation methods |

### 4.3 Redisplay interface coverage

The backend must implement every graphic-terminal redisplay hook or explicitly mark safe degradation:

* Frame parameter handlers.
* Glyph production, writing, insertion, and clearing.
* Row scrolling and after-update hooks.
* Window update begin/end.
* Frame/window flush.
* Mouse-face clearing.
* Glyph overhang computation and repair of overlapping rows.
* Fringe bitmap definition, destruction, and drawing.
* Glyph string overhang and drawing.
* Frame cursor definition.
* Frame/window area clearing.
* Internal border clearing.
* Window cursor drawing.
* Vertical border and window divider drawing.
* Hourglass show/hide.
* Default font parameter selection.

### 4.4 Terminal hook coverage

The backend must cover terminal hooks for:

* Input polling.
* Update begin/end and frame-up-to-date notification.
* Frame clearing and bell.
* Mouse position.
* Focus and rehighlighting.
* Raise/lower, visibility, iconification, and fullscreen.
* Menu, menubar activation, and dialogs.
* Tab-bar and tool-bar height.
* Vertical and horizontal scrollbars.
* Scrollbar condemnation, redemption, and judgment.
* Resource queries and color definition.
* Frame and terminal deletion.
* Font, bitmap icon, implicit name, size, offset, and alpha.
* Focus query and pixmap release.

## 5. Process model

### 5.1 Embedded backend

The backend runs inside the Emacs process for redisplay capture. A separate transport thread may serialize updates.

Rules:

1. Only the Emacs thread mutates authoritative frame/session capture state.
2. Redisplay never blocks on frontend rendering.
3. The transport thread receives an already coherent update snapshot.
4. Shared state is protected by short critical sections.
5. Frontend slowness causes frame coalescing or backpressure, never Emacs deadlock.

### 5.2 External frontend

The SDL3 frontend is a separate process. It communicates only through EUP. There is no shared mutable Emacs object state.

## 6. Frame and window mapping

Each Emacs frame maps to one stable EUP frame ID. Each Emacs window maps to one stable EUP window ID. IDs remain stable across redisplay updates and are recycled only after deletion and generation advance.

The backend maintains:

```text
Emacs frame -> EUP frame ID -> frontend surface
Emacs window -> EUP window ID -> render region
Emacs face -> EUP face resource
Emacs font -> EUP font resource
Emacs image -> EUP image resource
Emacs fringe bitmap -> EUP fringe resource
```

The frontend maps these IDs to internal window, surface, texture, and atlas state.

## 7. Redisplay capture flow

```text
Emacs redisplay begins
  -> backend emits update-begin context
  -> redisplay calls draw/clear/scroll/cursor/fringe/divider hooks
  -> backend records semantic render items and damage
  -> Emacs requests frame flush
  -> backend encodes one composite FRAME_UPDATE
  -> transport writes or coalesces the update
  -> frontend applies it atomically
  -> frontend presents and reports feedback
```

The preferred production hot path is one composite `FRAME_UPDATE` per frame. Granular render messages are debug, fallback, or replay paths.

## 8. Resource model

Resources are versioned by generation.

| Resource | Purpose |
|---|---|
| Face | Colors, underline, overline, strike-through, box, font reference |
| Font | Family, size, metrics, shaping metadata, fallback chain |
| Image | Pixel payload, dimensions, format, scaling, cache policy |
| Fringe bitmap | Bitmap geometry and pixels |
| Icon | Frame, menu, dialog, or tool-bar icon |
| String | Repeated UTF-8 text resource |
| Glyph atlas | Cached rasterized glyphs |

Rules:

1. A render item references resources by ID and generation.
2. Resource publication is reliable and ordered.
3. A frontend missing a resource pauses affected rendering and requests it.
4. Stale generations are invalid.
5. Resource cache pressure is reported through diagnostics.

## 9. Damage model

Damage is conservative. A frontend may redraw more than requested, never less.

Damage sources include:

* Row insertion or replacement.
* Glyph run change.
* Cursor movement or blink state.
* Face or font change.
* Image readiness.
* Fringe or divider update.
* Scroll operation.
* Window geometry change.
* Frame geometry, scale, or monitor change.
* Resource invalidation.

The backend merges adjacent or overlapping rectangles and emits a damage mode:

```text
NONE
PARTIAL
FULL
STATE_ONLY
RESOURCE_ONLY
```

## 10. Input model

The frontend sends structured intent, not Lisp commands.

Examples:

```text
KEY_EVENT
TEXT_INPUT
POINTER_EVENT
WHEEL_EVENT
FOCUS_EVENT
WINDOW_REQUEST
MONITOR_EVENT
IME_COMMIT
MENU_RESULT
DIALOG_RESULT
SCROLLBAR_EVENT
DND_DROP
```

The backend converts these to Emacs input events or desktop callbacks. Emacs remains responsible for bindings, commands, and policy.

## 11. Transport model

Supported transports:

| Transport | Use |
|---|---|
| Memory ring | Headless tests and protocol capture |
| Replay file | Deterministic replay and debugging |
| Unix socket | Local separate frontend process |
| Pipe | Portable local frontend |
| Shared memory ring | Lowest-latency local mode |

Message classes:

| Class | Reliability | Overflow behavior |
|---|---|---|
| Control | Reliable ordered | Never dropped |
| Resource | Reliable ordered | Never dropped |
| Frame update | Best effort, coherent | Coalesce superseded updates |
| Input | Reliable low latency | Never dropped |
| Diagnostics | Best effort | May drop |

## 12. Session lifecycle

```text
DISCONNECTED
  -> CONNECTING
  -> NEGOTIATING
  -> READY
  -> SUSPENDED or RESYNCING
  -> CLOSED
```

Initialization:

1. Frontend connects.
2. Both sides exchange protocol versions and capabilities.
3. Backend sends initial resources.
4. Backend sends frame and window-tree snapshots.
5. Backend sends `SESSION_READY`.
6. Frontend acknowledges.
7. Normal frame updates begin.

Reconnect uses replay if possible and snapshot fallback otherwise.

## 13. Failure containment

| Failure | Required behavior |
|---|---|
| Frontend disconnect | Emacs continues; proto frames remain alive unless deleted |
| Frontend slow | Intermediate coalescable frames collapse; resources and input remain reliable |
| Corrupt frame update | Drop frame and request resync |
| Missing resource | Frontend pauses affected drawing and requests it |
| Transport corruption | Resync or close frontend session; Emacs survives |
| Renderer crash | Emacs survives; frontend may reconnect |
| Backend initialization failure | Lisp frame creation signals a normal error |

## 14. GPU acceleration placement

GPU acceleration belongs to the frontend renderer, not the Emacs core or mandatory protocol semantics.

The protocol exposes:

* Render items.
* Resource and atlas hints.
* Damage.
* Renderer capabilities.
* Present preferences.
* Performance feedback.

The protocol does not expose:

* Shader source.
* GPU command buffers.
* Pipeline state.
* Renderer-specific APIs.

A conformant system must support a software fallback. GPU acceleration is negotiated and may be unavailable.

## 15. Compatibility invariants

1. Default builds are unchanged when proto-ui is disabled.
2. PGTK remains the reference graphic backend.
3. Proto-UI is opt-in.
4. New Lisp functions are unavailable unless compiled in.
5. Unknown optional protocol capabilities are ignored.
6. Missing optional capabilities trigger deterministic fallback.
7. Frontend failure cannot crash Emacs.
8. Existing Emacs tests must remain green.

## 16. Architecture acceptance

The architecture is accepted when all are true:

1. A proto frame is a real graphic Emacs frame.
2. Redisplay state reaches the protocol.
3. A frontend can recreate the display.
4. Input reaches Emacs commands.
5. Frontend reconnect restores a coherent display.
6. A slow or crashing frontend cannot stall Emacs.
7. Existing backends and CI remain green.
