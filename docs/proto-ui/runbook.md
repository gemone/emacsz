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
4. SDL3 and `pkg-config` for `-Dsdl3-frontend=true`.
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

These tests may briefly open an SDL window by design.  They render bounded
fixtures; they do not prove a complete Emacs editor frame.

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
gate checks scene bytes only; the current bitmap renderer has no CJK shaping or
font fallback.  They do not provide a full Emacs keyboard/keymap/IME input
stack.

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

Green smoke commands prove only their documented bounded scope.  The final
system requires the W16 gates in
[`implementation-plan.md`](implementation-plan.md): an `output_proto` real
graphic frame, redisplay-owned rendering, full input/platform coverage,
resource/widget behavior, performance evidence, and unchanged default Emacs
builds.
