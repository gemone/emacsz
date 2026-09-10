# Proto-UI Runbook

## 1. Audience and scope

This runbook builds and exercises the current adapter-first Proto-UI slices on
a graphical Linux host.  It is **not** a release guide for a production SDL3
Emacs backend: `output_proto`, redisplay-owned rows, complete input, faces,
fonts, images, widgets, and PGTK parity remain documented gaps in
[`capabilities.md`](capabilities.md).

## 2. Prerequisites

1. Zig 0.16.0.
2. A working graphical session (`DISPLAY` or `WAYLAND_DISPLAY` and
   `XDG_RUNTIME_DIR`).
3. GTK3 development files for the default Linux PGTK build.
4. SDL3, SDL3_ttf, and `pkg-config` for `-Dsdl3-frontend=true`.
5. No running Emacs daemon is required; lifecycle smoke tests create an
   isolated private daemon.

## 3. Adapter and protocol checks

Run from the repository root:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
```

Expected result: all adapter unit tests pass and the boundary audit reports
`boundary: OK`.  The generated ABI and capability summaries are installed under
`zig-out/include/proto-ui/` and `zig-out/proto-ui/`.

## 4. SDL3 rendering checks

Build and run the deterministic replay and renderer checks:

```sh
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-ui-smoke --summary all
zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-renderer-smoke --summary all
```

For an opt-in, host-dependent renderer timing report, use:

```sh
zig build -Doptimize=ReleaseFast -Dproto-ui=true -Dsdl3-frontend=true \
  sdl3-renderer-bench --summary all
cat zig-out/proto-ui/sdl3-renderer-benchmark.json
```

The smoke may briefly open an SDL window by design.  The benchmark uses a hidden
window and renders a bounded fixture; neither proves a complete Emacs editor
frame.  Benchmark numbers describe the local host and run only.

## 4.1 Current window command checks

The bounded command bridge can split, select, edit, and restore one live Emacs
window:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-split-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-navigation-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-window-restore-smoke --summary all
```

They exercise only the explicit `C-x 2`, `C-x 3`, `C-x o`, insertion, and
`C-x 1` whitelist entries.  They do not enable arbitrary keymaps or prefixes.

## 5. Real-frame lifecycle smoke

The current closest approximation to “open Emacs through SDL3” is the W12c
lifecycle bridge:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-frame-smoke --summary all
```

Success prints output similar to:

```text
sdl3-frame-smoke: renderer <name> tier=<tier>
sdl3-frame-smoke: real Emacs frame WIDTHxHEIGHT created, rendered, and deleted through SDL3; lifecycle OK
```

This smoke starts a private PGTK Emacs daemon, creates and deletes one real
display-backed Emacs frame, and applies the matching EUP frame lifecycle in an
SDL3 scene.  It deliberately closes quickly.  A brief window flash is expected
and is not a failure when the command exits zero.

The exact contract, limits, and cleanup behavior are in
[`frame-lifecycle-smoke.md`](frame-lifecycle-smoke.md).

## 6. Interactive bounded-input checks

Exercise the authenticated EPXL facts and input path:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-facts-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-interactive-smoke --summary all
```

These checks cover bounded ASCII text, negotiated bounded Unicode text, a few
key actions, pointer/wheel intents, and refreshed public facts.  The Unicode
gate also renders one bounded UTF-8 public-facts line with SDL_ttf; it has no
shaping, BiDi, Emacs font metrics, complete fallback, or IME support.  They do
not provide a full Emacs keyboard/keymap/IME input stack.

### 6.1 Manual authenticated session

Use this target when you want the bounded bridge to stay open instead of
running a timed smoke:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive
```

This starts a real Emacs publisher, one authenticated EPXL session, and an
SDL3 window.  `--auto-quit-ms=0` means “no smoke deadline”: closing the SDL
window closes the transport, lets the publisher terminate its Emacs child, and
then removes private artifacts.  The session remains a bounded public-facts
bridge, not an `output_proto` terminal or complete Emacs UI.

The target intentionally returns after closing that EPXL window; it does not
open the separate replay-only diagnostic window used by timed smokes.

## 7. Interpreting failures

| Symptom | First response |
|---|---|
| `NoGraphicalDisplay` or SDL video initialization fails | Confirm `DISPLAY`/`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and SDL3 availability. |
| `FrameLifecycleTimeout` | Ensure no test is waiting for a nonexistent display and that the graphical session allows GTK window creation. |
| GTK module warnings | Treat them as host-environment noise only if the smoke exits zero; investigate when the lifecycle fails. |
| `InvalidSequence` | Report it as a producer/frontend sequence-state bug; do not bypass scene validation. |
| Private daemon remains running | Check for an interrupted run; the smoke cleans its uniquely named `/tmp/proto-ui-frame-*` directory and owned children on normal/failure paths. |

Do not attach the lifecycle smoke to a user Emacs daemon and do not delete
another process’s `/tmp/proto-ui-frame-*` directory.

## 8. Current completion boundary

Green smoke commands prove only their documented bounded scope.  Candidate R8
adapter linkage is state-aware: it is unlinked by default, audited as
`linked_not_registered` only under explicit native Linux glibc runtime linking,
and never called or able to register a terminal.  The final system requires the W16 gates in
[`implementation-plan.md`](implementation-plan.md): an `output_proto` real
graphic frame, redisplay-owned rendering, full input/platform coverage,
resource/widget behavior, performance evidence, and unchanged default Emacs
builds.
