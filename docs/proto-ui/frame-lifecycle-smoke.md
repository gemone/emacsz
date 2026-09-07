# W12c — Real Emacs Frame Lifecycle Smoke

## 1. Purpose

W12b defined adapter-owned state machines for frame and resource generations.
This document defines the next, intentionally narrow runtime proof: create one
real display-backed Emacs frame, observe its public frame facts, transport a
bounded EUP create/update/destroy lifecycle, render the create and update states
with SDL3, and destroy both the Emacs frame and the SDL-backed Proto-UI frame in
a deterministic order.

This smoke is **not** the W16 completion target.  It does not claim PGTK parity,
redisplay ownership, full window trees, faces, fonts, resources, input
equivalence, or a production `output_proto` terminal.  It is the smallest
adapter-first bridge that proves Emacs frame lifetime and EUP frame lifetime can
remain synchronized.

## 2. Scope

### In scope

1. A private Emacs daemon and socket owned by the smoke process.
2. One real display-backed Emacs frame created by a lifecycle Lisp call through
   `emacsclient -e`.
3. Public Emacs observation only: frame size, selected-window size, bounded
   ASCII text, point/cursor position, and viewport metadata.
4. Adapter-owned EUP `FRAME_CREATE`, `FRAME_UPDATE`, and `FRAME_DESTROY`
   messages.
5. Adapter-owned `frontend.Scene` lifecycle state and SDL3 presentation.
6. Bounded cleanup of the Emacs client, daemon, socket, temporary facts, and
   private runtime directory on success and failure.

### Out of scope

1. `output_proto` terminal integration or changes to inherited Emacs C/Lisp.
2. Multiple simultaneous Emacs frames.
3. Redisplay-owned glyph rows, faces, fonts, overlays, fringe, scrollbars, or
   full window layout.
4. Resource payloads, deletion transport, snapshots, eviction, or missing
   resource requests.
5. General keyboard, mouse, IME, drag-and-drop, selection ownership, or widget
   behavior.
6. Untrusted or remote transports.

## 3. Process model

The smoke owns four process/storage scopes:

```text
Proto-UI smoke process
  |-- Emacs foreground daemon  (--fg-daemon=<runtime>/emacs.sock)
  |-- emacsclient control call (loads the adapter-owned module)
  |-- emacsclient lifecycle call (creates and owns the display-backed frame)
  `-- private runtime directory
      |-- emacs.sock
      |-- facts.json
      |-- created
      |-- delete
      `-- deleted
```

The runtime directory is created with mode 0700 before daemon startup.  The
daemon and every emacsclient call use the same absolute private socket path.
The smoke uses `-Q`, a unique runtime directory, and `--alternate-editor=` so it
cannot attach to a user daemon, race another smoke, or implicitly start a new
Emacs when the private daemon is unavailable.

## 4. Frame lifecycle

### 4.1 Create

1. Start the private daemon with `-Q` and the absolute private socket path.
2. Wait for that socket, then run an authenticated `(+ 1 1)` ping with a
   bounded deadline.
3. Load the adapter-owned dynamic module in the daemon Emacs and require a
   successful module smoke acknowledgement.
4. Run one `emacsclient -e` lifecycle program that calls
   `make-frame-on-display` with fixed bounded initial geometry.  The program
   retains the returned frame object, so `delete-frame` targets the exact frame
   under test.
5. Require `frame-live-p`, `frame-visible-p`, and three consecutive equal
   pixel-size samples separated by 150 ms.  A geometry change restarts the
   three-sample stability check; an eight-second settle deadline is explicit.
6. Observe public facts through the adapter-owned dynamic module.
7. Write `facts.json` atomically (temporary file plus rename), then write
   `lifecycle.created` atomically.
8. Encode EUP `FRAME_CREATE` sequence 5 and `FRAME_UPDATE` sequence 6 with a
   producer-owned scene.  Apply both messages to a separate frontend-owned
   scene to preserve the producer/frontend sequence boundary.
9. Render the explicit created state and then the active updated frame in
   SDL3.

The EUP frame uses frame id `1`, frame generation `1`, and a single active
frame.  The W12b registry rejects a second active frame and any frame id
reuse.

### 4.2 Update

The facts snapshot contains exactly one visible text line, one cursor, and one
bounded viewport declaration.  The EUP update is validated and committed
atomically by `frontend.Scene`.  The smoke requires exactly one accepted
`FRAME_UPDATE` and text marker `Emacs Proto-UI`.

### 4.3 Delete

1. The smoke atomically writes the private `delete` request marker.  The
   randomly selected 0700 runtime directory isolates this request per run.
2. The Emacs lifecycle program consumes the request and calls `delete-frame`
   on the exact stored frame object.
3. Only after `delete-frame` succeeds, the program writes the `deleted`
   marker atomically.
4. The smoke requires the client process to exit successfully.
5. The producer and frontend scenes both apply EUP `FRAME_DESTROY` sequence 7
   with the same frame id and generation.  This smoke uses local scene
   validation; a transported EPXL ACK remains future work.
6. `frontend.Scene` marks the frame destroyed, releases the bounded visual
   state, and refuses later updates for the destroyed generation.
7. SDL3 presents the destroyed state through an explicit renderer path: set the
   opaque background color, clear the renderer, and present.  It must not call
   normal scene rendering after `FRAME_DESTROY`.

On the success path, both create and update messages are validated by the
frontend scene before the delete request is written.  The marker and request
wait loops have bounded deadlines.  If Emacs does not delete the frame in time,
the smoke fails and its scoped failure path gives the client a brief exit
window before terminating owned processes and removing private state.

## 5. Environment contract

The smoke requires a graphical session:

```text
DISPLAY or WAYLAND_DISPLAY
XDG_RUNTIME_DIR
```

The smoke inherits the current environment and reads `DISPLAY` (with
`wayland-0` as the current fallback display identifier when `DISPLAY` is
absent).  A future gate must preserve the complete GTK/IME environment without
inventing a display value.

The gate currently assumes a graphical host; it does not yet perform an early
`NoGraphicalDisplay` check or provide a build-runner skip policy.  A later
runner-integration milestone must add both.

## 6. Cleanup and failure model

Cleanup is idempotent and bounded:

1. Write the delete request if the real frame may still exist.
2. On the success path, wait up to a deadline for the Emacs client to report
   `deleted`; on the failure path, allow a brief exit window before killing.
3. On the success path, ask the private daemon to run `(kill-emacs 0)`.
4. Wait briefly for the foreground daemon; otherwise terminate and then kill it.
5. Remove the private runtime directory.
6. Reap or kill all owned children on every return path.

An Emacs client error, timeout, malformed facts, EUP validation failure, SDL
failure, or extra active frame must fail the smoke.  Failure may leave no Emacs
server, frame, or smoke-owned temporary state behind.

## 7. Observability

Success must print a machine-greppable line:

```text
sdl3-frame-smoke: real Emacs frame WIDTHxHEIGHT created, rendered, and deleted through SDL3; lifecycle OK
```

The smoke also reports the actual SDL renderer name and tier through the
existing renderer diagnostics.  Zig error names currently identify failed
lifecycle stages; the later diagnostic workstream must map those errors to
stable stage labels:

```text
daemon-start
module-load
frame-create
facts-observe
scene-create
scene-update
frame-delete
scene-destroy
cleanup
```

## 8. Acceptance

Local acceptance on a graphical Linux host:

```sh
zig build -Dproto-ui=true proto-ui-unit
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-frame-smoke
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true sdl3-epxl-interactive-smoke
zig build check
```

Required assertions:

1. One real Emacs client frame was created and later deleted.
2. One EUP frame id/generation was created, updated, and destroyed.
3. SDL3 presented the active and destroyed lifecycle states.
4. The W12b registry ends with one destroyed frame and no active frame.
5. Visual allocations and temporary smoke state are released.
6. Existing replay, facts, input, and interactive smokes remain green.

## 9. Non-goals after W12c

This smoke is a lifecycle bridge, not production frame ownership.  W12d adds
strict visibility/focus wire state only.  A later `output_proto` milestone must
add real frame topology, redisplay-owned rows, resource payloads, runtime focus
and visibility events, and differential compatibility tests before claiming
PGTK parity.
