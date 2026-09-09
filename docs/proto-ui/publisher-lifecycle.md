# Publisher lifecycle and bounded input gates

## Status

The authenticated EPXL publisher is a **bounded diagnostic bridge**.  It sends
public Emacs facts to the SDL3 frontend and forwards a negotiated subset of
frontend intents back to Emacs through local artifacts.  It is **not** an
`output_proto` terminal, does not stream redisplay internals, and does not
provide PGTK parity.

The current stable evidence is the real-frame lifecycle bridge:

```sh
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-frame-smoke --summary all
```

It creates and deletes one real PGTK observation frame while one SDL3 scene
renders the matching EUP frame lifecycle.  This is not the same contract as a
pure `output_proto` frame.

## Resource extraction requirement

The authenticated publisher Lisp must be moved from a long escaped `--eval`
string into a reviewable adapter-owned resource such as:

```text
tools/proto-ui-sdl3/facts_publisher.el
```

The migration must preserve the current bounded semantics before any UX change
is added.  In particular, top-level forms must be checked with the Emacs Lisp
reader and `byte-compile`; a paren that changes `let*`, `defun`, or `while`
scope can make the publisher exit successfully without publishing facts.

## Facts contract

The publisher snapshot must include:

1. Frame and selected-window geometry.
2. Public window identities and geometry.
3. Per-window bounded visible lines and cursor.
4. A `process_lifetime` identity when public windows are present.
5. Optional mode/header/tab lines only when Emacs supplies a safe string.

Snapshot serialization must be atomic from the reader's perspective.  The
required pattern is:

1. Write `facts.json.tmp`.
2. Flush and close the complete document.
3. Rename it to `facts.json`.

The frontend must never apply a truncated document.  A failed parse is a
publisher defect or a version mismatch; it must not be silently accepted as an
unchanged snapshot.

## Reverse input contract

Reverse input artifacts remain bounded and capability-gated.  The artifact is
an ordered local record with sequence, kind, and payload.  The publisher
applies it through public Emacs editing interfaces and returns an explicit ACK
artifact.

Allowed families are limited to the negotiated profile:

| Family | Required evidence |
|---|---|
| ASCII text | ASCII edit smoke |
| Unicode text | Unicode edit smoke |
| Bounded key | key/edit smoke |
| Pointer v2 selection | selection smoke |
| Pointer middle paste | middle-paste smoke |
| Wheel ticks | wheel/viewport smoke |

The frontend must not advertise a family merely because the EUP codec exists.

## Required acceptance gates

A publisher-resource slice is not complete unless all of the following pass on
a graphical Linux host:

```sh
zig build -Dproto-ui=true proto-ui-unit --summary all
zig build -Dproto-ui=true proto-ui-boundary --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-emacs-interactive-local-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-epxl-unicode-input-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-pointer-selection-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-pointer-middle-paste-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-wheel-smoke --summary all
zig build -Dproto-ui=true -Dmodules=true -Dsdl3-frontend=true \
  sdl3-frame-smoke --summary all
```

A smoke must assert both application in Emacs and visibility in the next EUP
snapshot.  A platform ACK alone is not sufficient.

## Shutdown requirements

Session cleanup must be ordered:

1. The frontend closes the transport.
2. The publisher observes closure and stops its read/heartbeat loop.
3. The publisher terminates and reaps its Emacs child.
4. The frontend waits for publisher exit.
5. Only then may the private facts, input, ACK, clipboard, socket, token, and
   directory artifacts be removed.

An error path must not SIGKILL an intermediate publisher in a way that strands
an Emacs child or permits writes into a deleted directory.

## Explicit non-goals

Green publisher smokes do not establish:

* an `output_proto` terminal;
* redisplay-owned capture;
* complete Emacs keyboard, keymap, or IME behavior;
* PGTK visual or behavioral parity;
* production process supervision;
* complete Emacs compatibility.
