# Proto-UI Adapter Boundary

Status: normative constraint
Protocol: EUP v1
Effective immediately

## 1. Objective

Proto-UI and the SDL3 frontend must be built as an adapter around Emacs.
Emacs remains authoritative for buffers, windows, frames, faces, fonts,
input semantics, and redisplay.  The adapter observes and translates that
state through a stable boundary; it does not rewrite or redirect the core.

The implementation order is:

1. Zig adapter modules.
2. Independent SDL3 frontend process.
3. Stable protocol and replay tooling.
4. Existing, stable Emacs extension points.
5. A separately owned adapter shim only when another option is impossible.

Direct changes to GNU Emacs's inherited C implementation are not the default
and are prohibited without an explicit, documented exception.

## 2. Hard rules

1. **Adapter first.**  New display, input, transport, lifecycle, resource, and
   recovery logic belongs in the Zig adapter, SDL3 frontend, Lisp integration,
   protocol tooling, or build glue.
2. **No intrusive C edits.**  Do not modify inherited Emacs C source or
   headers to add Proto-UI state, calls, hooks, macros, fields, function
   parameters, static/global variables, or display-specific branches.
3. **Preserve upstream semantics.**  Existing backends must not acquire
   Proto-UI conditionals, different initialization order, or new coupling.
4. **No core ownership transfer.**  The adapter may observe and translate
   authoritative state; it must not duplicate layout or redisplay truth.
5. **Default isolation.**  With `-Dproto-ui=false`, the build graph, linked
   symbols, runtime behavior, and public C API must remain unchanged.
6. **Reversibility.**  It must be possible to identify and remove the Proto-UI
   adapter without reworking GNU Emacs.

## 3. Preferred implementation locations

| Concern | Preferred owner |
|---|---|
| EUP encoding, validation, resources, damage state | `src/proto-ui/*.zig` |
| Transport, replay, coalescing, diagnostics | `src/proto-ui/*.zig` and tools |
| SDL3 windows, rendering, input, GPU pipeline | Separate SDL3 frontend |
| Lisp-visible terminal behavior and fixture wrappers | Proto-UI Lisp integration |
| Build options, feature defines, ABI/link glue | `build.zig` |
| Tests and fixtures | Zig unit tests, ERT, replay fixtures, protocol tools |

## 4. Adapter rules

Prefer existing, stable Emacs extension points and public ABI.  If a new C
adapter seam is unavoidable, isolate it in a separate Proto-UI-owned adapter
file, not in inherited Emacs C source.  The adapter must:

1. Contain delegation and minimal type conversion only.
2. Immediately call into Zig or the Proto-UI session layer.
3. Contain no protocol encoding, damage policy, frontend policy, or display
   algorithm.
4. Be disabled and absent from behavior when Proto-UI is disabled.
5. Have an explicit owner, review record, rollback plan, and boundary test.

A shim is not a license to embed Proto-UI in Emacs.

## 5. Legacy transition status

Some earlier Proto-UI slices modified inherited C files to prove the terminal
and redisplay seam.  Those slices are historical transition work.  Under this
document they are frozen:

1. No new inherited-C modifications may be added on top of them.
2. They do not justify further direct-core coupling.
3. They must be replaced by the adapter design before Proto-UI can be declared
   complete.
4. Any direct-core behavior they introduce needs a compatibility test.

In particular, direct edits to `xdisp.c`, `dispnew.c`, `xfaces.c`, `frame.c`,
`frame.h`, `window.h`, or `terminal.c` for real-redisplay fixture work are
not an acceptable pattern going forward.

The intrusive normal-RIF fixture prototype that modified these boundaries was
quarantined rather than merged.  Normal-RIF streaming is blocked until an
adapter-owned redesign satisfies this document.

## 6. Review and acceptance gates

Every Proto-UI patch must document:

1. Which side owns each behavior: Emacs core, adapter, protocol, or frontend.
2. Why the chosen location is outside inherited Emacs C code.
3. Whether a diff touches an inherited C file.
4. How default-build behavior remains compatible at the API and behavior
   level.
5. How to disable, remove, or roll back the adapter.

A patch is rejected if it:

1. Adds Proto-UI logic to inherited Emacs C code.
2. Adds fields or branches to core structures only to support the adapter.
3. Changes core function signatures or static linkage for fixture convenience.
4. Makes another backend depend on Proto-UI state.
5. Lets the frontend mutate Emacs state directly.

## 7. Required evidence

Before merging a Proto-UI workstream, retain:

1. The C-boundary audit result.
2. Adapter unit-test output.
3. Default-build isolation evidence.
4. Optional Proto-UI build and smoke output.
5. Replay or protocol conformance evidence for the captured behavior.
6. A review record stating that the adapter-first rule was followed.

The final SDL3 acceptance test must demonstrate both the user-visible feature
and compliance with this boundary.

## 8. Zig-build embedding model

`zig build` is the control plane for embedding the adapter:

1. Compile and link `src/proto-ui/*.zig` as a subsystem-owned library.
2. Emit only feature defines and generated adapter declarations needed by a
   separately owned shim.
3. Attach the adapter through existing terminal ABI or a Proto-UI-owned shim.
4. Install frontend, replay, conformance, and smoke tooling as build steps.

The build system must not patch inherited Emacs C files in place.  Generated
content belongs in the cache/output directory or a Proto-UI-owned adapter
file.
