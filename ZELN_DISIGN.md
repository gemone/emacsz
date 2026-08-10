# ZELN_DESIGN.md — The `.zeln` Native-Compilation Path (Zig / LLVM AOT)

This document is the complete design for the Emacs native-compilation path
that replaces gccjit with a Zig/LLVM AOT pipeline producing `.zeln` artifacts.
It is the authoritative reference for the `HAVE_NATIVE_COMP_ZIG` subsystem
(the C side lives in `src/compz.[ch]`, the compiler in
`tools/zeln-compile/`, the harness in `build-aux/zeln-diff.el`, and the
cache/load drivers in `build-aux/{populate-zeln-cache,run-check}.zig`).

The gccjit path (`src/comp.c` / `comp.h`, `.eln` / `eln-cache/`) is **never
modified** — the two paths are physically isolated and may coexist.

---

## 1. Goals

1. **Usable** — the default `emacs` is fully usable; the `.zeln` path is
   opt-in (`-Dnative-comp-zig=true`) and has **zero footprint** when off.
2. **Behaviorally identical** — every `.zeln` native function returns the
   exact same value as the bytecode interpreter (`exec_byte_code`) on every
   input, including non-local control (throw / condition-case / unwind) and
   error inputs. The differential gate enforces this.
3. **Artifacts independent** — `.zeln` / `.zeln-cache/` are distinct from
   gccjit's `.eln` / `eln-cache/`; the two never collide on disk.
4. **Faster than the interpreter** — Tier-1 specialization (M3) must beat
   `exec_byte_code`.
5. **Cross-platform, native linking** — Zig drives all compile/link; targets
   Linux (glibc + musl), macOS, Windows (TTY).

---

## 2. Locked Design Decisions

- **gccjit untouched.** `src/comp.c` / `comp.h` compile only under
  `HAVE_NATIVE_COMP` and are never edited, linked, or referenced by the
  `.zeln` path.
- **Parallel switch.** `HAVE_NATIVE_COMP_ZIG` (build option
  `-Dnative-comp-zig=true`, default **off**). `compz.c` is compiled only when
  the switch is on (conditional `addCSourceFile` in `build.zig`).
- **AOT, not JIT.** `.zeln` are ELF/Mach-O/PE shared objects produced ahead of
  time by `zig cc -shared`, loaded via `dlopen`, relocated via the freloc
  table, and called. No runtime IR generation.
- **Compiler in Zig.** `tools/zeln-compile` (a Zig package) consumes a
  `zunit`, emits LLVM IR, and drives `zig cc -shared`.
- **C↔Zig boundary = the zunit.** The dumped `temacs` serializes each lexical
  closure to a `zunit` (Lisp-aware: it never parses `.elc` read-syntax or
  `Lisp_Object` tag bits). Zig consumes the zunit. Lisp_Object tagging never
  leaks across the boundary.
- **Tiered emitter.** Tier-0 (current): a memory virtual stack + decode-at-
  compile-time unfold — *correctness first*. Tier-1 (M3): virtual stack → SSA
  + specialization — *speed*.
- **Modules independent.** `HAVE_MODULES` (upstream dynamic modules,
  `-Dmodules=true`) and `HAVE_MODULES_ZIG` (the Zig module subsystem,
  `-Dmodules-zig=true`) are separate, independent switches (Track B).

---

## 3. Architecture — the Compilation Chain

```
        dumped temacs                     tools/zeln-compile (Zig)            loader (src/compz.c)
        ------------                      --------------------------          --------------------
.elc ──▶ comp-z-write-zunit ──▶ .zunit ──▶ parse zunit ──▶ emit LLVM IR ──▶ zig cc -shared ──▶ .zeln ──▶ Fcomp_z_load_zeln
        (or comp-z-write-                (bytecode + arity +              (one native fn per defun,     (dlopen + freloc
         file-zunit for a whole            constants + stack-depth +        + the .elc's top-level        patch + per-fn
         .elc → multi-fn zunit)           args_template, as a binary       forms as a read-syntax        const scatter +
                                            blob; Lisp read-syntax           blob)                        top_level replay)
                                            for constants only)
```

The chain is **AOT and off-path by default**: nothing above runs unless
`-Dnative-comp-zig=true`. The default `zig build` produces an emacs with
`compz.c` not even compiled.

### Why a zunit (not direct .elc parsing in Zig)
Parsing Emacs byte-compile read-syntax (with `#[n]`, `#$`, deft-args, circular
`#N=`/`#N#`, `#$` patching, `#@N` skips) is intricate and version-sensitive.
Instead the dumped `temacs` — which already understands all of it — extracts
the *semantic* parts a compiler needs (opcode vector, constant vector,
stack-depth, lexical args template) into a trivial binary `zunit`. Zig reads
fixed fields; constants stay as Lisp read-syntax (Fread on the load side).
This keeps the C↔Zig ABI surface minimal and tag-bit-free.

---

## 4. The Contract — On-Disk Formats

All multi-byte fields are little-endian; every struct field is 8-byte aligned
(x86-64, no padding). The LLVM-IR struct types emitted by `zeln-compile` MUST
match the C layouts field-for-field.

### 4.1 The zunit (`comp-z-write-zunit` / `comp-z-write-file-zunit`)

A binary blob produced by temacs:

```
u32  magic = 0x5A554E54 ("ZUNT")
u8   zabi_version          # 1 = M0 spike, 2 = M1 single-fn, 3 = M2b multi-fn
# zabi=3 (multi-function) body:
u32  nfuncs
foreach fn:
    u32  bytecode_len ; u8[bytecode_len] opcodes
    u32  nconsts      ; <read-syntax const vector>
    u16  stack_depth
    u16  args_template (15-bit lexical arity encoding)
    u32  symbol_name_len ; u8[symbol_name_len] defun symbol
# the .elc's non-defun top-level forms as a single (progn ...) read-syntax
u32  top_level_blob_len ; u8[top_level_blob_len]
```

Constants are written/read with `print-circle`/`print-level`/`print-length`
relaxed (so shared/circular/deep constants round-trip — the fix that took
cache coverage from 46.6% to ~100%).

### 4.2 The freloc-manifest (per .zeln)

The fixed, closed set of C entry points every `.zeln` may call — the "freloc
surface". Each opcode the emitter translates maps to a stable `IDX_*`. The
manifest carries:

- the ordered list of imported runtime-fn names (the freloc signature),
- `freloc_hash_z` — an 8-hex ABI hash over `ZELN_ABI_VERSION ++ emacs-version
  ++ config ++ config-options ++ signature` (mirrors gccjit's
  `hash_native_abi` / `comp.c:782`),
- `ZELN_ABI_VERSION` ("Z4" at present — see §6).

The emitter's `IDX_*` constants (`tools/zeln-compile/src/main.zig`) mirror the
`IDX_*` enum in `src/compz.c` field-for-field; the hash fingerprints the
ordered name list so any drift between the two rejects the `.zeln` on load.

### 4.3 The `.zeln` (shared object) — `zeln_entry_t`

One `.zeln` mirrors one `.elc`: N native functions (one per defun) **plus** the
`.elc`'s non-defun top-level forms as a read-syntax blob, so loading one
`.zeln` is a faithful mirror of loading the whole `.elc` (defun-fset +
top-level replay) — exactly like gccjit's `.eln`.

```c
typedef struct {
  Lisp_Object (*native_fn)(ptrdiff_t, Lisp_Object *);  // MANY-convention
  ptrdiff_t   args_template;     // lexical arity (reference; prologue enforces)
  const char *symbol_name;       // &@sym_name_<i>: the defun symbol
  Lisp_Object *d_reloc;          // &@d_reloc_z_<i>[0]: THIS fn's const vector
  ptrdiff_t   n_d_reloc;         // == nconsts for this fn
  zeln_static_obj_t *d_reloc_blob; // &@d_reloc_blob_<i>: read-syntax const blob
} zeln_fn_entry_t;

typedef struct {
  void   **freloc_link_table_z;  // loader writes the live freloc base here
  const char *freloc_hash_z;     // 8-hex ABI hash; gate-checked on load
  ptrdiff_t n_fns;
  zeln_fn_entry_t *fns;          // &@zeln_fn_table: [n_fns] entries
  zeln_static_obj_t *top_level_blob; // (progn ...) of non-defun top-level forms
} zeln_entry_t;

zeln_entry_t *zeln_entry (void);  // the .zeln's exported symbol
```

The M0/M1 single-function `.zeln` is simply the `n_fns = 1` case (empty
`top_level_blob`). The loader has ONE entry layout for all `.zeln`.

### 4.4 Calling conventions through the freloc table

The `.ll` reaches every C entry point purely through the loader-patched freloc
pointer (`base -> base[IDX_*]`), so the `.zeln` needs **no extern symbol** and
the main executable needs **no `-rdynamic`** — exactly like gccjit's `.eln`.
Two conventions:

- `IDX_SETUP_ARGS`: `Lisp_Object *(*)(ptrdiff_t, ptrdiff_t, Lisp_Object *,
   Lisp_Object *)` — the native prologue (returns the new virtual-stack `top`).
- `IDX_NILP`: `ptrdiff_t (*)(ptrdiff_t, Lisp_Object *)` — a RAW 0/1 (not a
   tagged `Lisp_Object`), so the IR branches on `icmp eq i64 %ret, 0` without
   knowing `Lisp_Object` tag bits.
- every other IDX: `Lisp_Object (*)(ptrdiff_t, Lisp_Object *)` — the uniform
   MANY convention matching `struct Lisp_Subr aMANY`.

---

## 5. The Emitter (`tools/zeln-compile/src/main.zig`)

### Tier-0 model
Each native function:
1. `alloca [stack_depth x i64]` virtual stack (+ a `%top.slot` pointer cell +
   a `%zargs[3]` scratch).
2. `zeln_setup_args` binds the actuals into the virtual stack (mirrors
   `exec_byte_code`'s frame setup, including the `&rest` list case).
3. A straight-line unfold of the bytecode: each opcode lowers to loads/stores
   on the virtual stack + a freloc call. Decode happens at compile time; the
   IR is per-opcode.
4. `Breturn` restores the frame and returns `TOP`.

The whole virtual stack and `%zargs` are **zeroed with `llvm.memset` at
entry** (see §6).

### Opcode coverage
Tier-0 covers every practical bytecode opcode (the full `bytecode.c` DEFINE
table minus `Bswitch`, used only by large pcase/cond, and 6 obsolete forms
modern lexical bytecomp never emits). Family members (`Bvarref1..7`,
`Bstack_ref1..7`, `Bcall1..7`, `Blist1..4`, …) are decoded as base + low-bits.

### Non-local control (the hard case) — the setjmp pushhandler trampoline
`catch` / `condition-case` resume via `setjmp`/`longjmp`. The PROVEN-correct
translation mirrors gccjit (`comp.c:2196 emit_limple_push_handler`):

- The native function calls `_setjmp` on the handler's jmpbuf **directly in its
  own frame** (not in a returning helper), so a thrown `longjmp` lands inside
  the native frame and its `alloca` virtual stack survives (only C frames
  *above* are unwound).
- C-side helpers in `compz.c`:
  - `zeln_pushhandler(tag, type, &top_slot)` — `push_handler`, sets
    `bytecode_dest = 0` (sentinel: native resume, never the interpreter's dest
    path) and `bytecode_top = *top_slot`, returns the jmpbuf address as a raw
    `i64`.
  - `zeln_resume(&top_slot)` — the caught path: pops the handler, restores
    `*top_slot` to the pushtime top, PUSHes the caught value.
  - `zeln_pophandler` — normal-exit cleanup (`handlerlist = handlerlist->next`).
- specpdl-pure constructs (`let`/`let*` via `Bvarbind`/`Bvarset`/`Bvarref`/
  `Bunbind`, `save-excursion`/`save-restriction`/`save-current-buffer`,
  `unwind-protect`) lower to a single direct freloc call into the SAME C helper
  the interpreter calls — behavioral identity holds by construction.

---

## 6. GC Safety (the central correctness concern)

Emacs GC is **non-moving** and scans the C stack **conservatively**
(`mark_memory` over the thread stack, `src/alloc.c`). The native function's
`alloca` virtual stack lives on the C stack, so its contents are scanned —
*if* they are valid `Lisp_Object`s. Three independent requirements, each with
its own fix:

1. **Reconstructed constants must be rooted.** The loader scatters each
   function's Fread constant vector into its `.zeln`-static `d_reloc` array
   (GC-invisible). Without a root, GC would sweep any freshly-Fread heap
   object referenced *only* from `d_reloc` → dangling.
   → `zeln_loaded_const_vectors` (staticpro'd in `syms_of_compz`) conses every
   loaded constant vector so the objects stay reachable. Mirrors gccjit
   GC-tracing each native fn's data relocs through its compiled-function
   vector.

2. **Uninitialized stack slots must read as non-objects.** Conservative
   scanning of alloca garbage can misread a random word whose bits land in a
   swept heap block as a freed object → `PVEC_FREE` abort.
   → `llvm.memset` zeroes the whole virtual stack + `%zargs` at entry; zero
   words are not valid `Lisp_Object`s and are ignored by `mark_maybe_pointer`.

3. **Live values must be memory-resident at GC safepoints** (any freloc call
   that may GC). **HYPOTHESIS DISPROVEN at M2b.2**: this was theorized to be
   the gate-#2 crash (live `Lisp_Object`s held in LLVM SSA registers across a
   GC safepoint missed by the conservative scan). It was **disproven**: the
   crash is identical at `-O0` (where *all* values are stack-resident). The
   emitter's safepoint model (memset + `storeTop` before every top-moving
   freloc call) is sound; the residual crash is a *wrong write*, not a missed
   safepoint (see §11).

`ZELN_ABI_VERSION` is bumped whenever the `.zeln` layout or freloc surface
changes (Z1→Z2 M1 layout; Z2→Z3 M2 surface growth; Z3→Z4 M2b multi-fn
`zeln_entry_t`). The stale-`.zeln` guard is double: the version dir embeds the
abi_hash, **and** `Fcomp_z_load_zeln` calls `zeln_verify_hash` before any
native code runs.

---

## 7. Transparent Loading (`src/lread.c`)

`maybe_swap_for_zeln` / `maybe_swap_for_zeln1` (mirrors of gccjit's
`maybe_swap_for_eln`, ~`lread.c:1647`) intercept `Fload`: when
`HAVE_NATIVE_COMP_ZIG` is on **and** `native-comp-zeln-load-path` points at a
populated `.zeln-cache`, loading a `.elc` whose matching `.zeln` exists swaps
to the `.zeln` (transparent native load); otherwise it falls through to the
normal `.elc` (interpreter). Entirely under `#ifdef HAVE_NATIVE_COMP_ZIG` →
zero footprint off-path.

`comp_el_to_zeln_rel_filename` + `compute_z_version_dir` mirror gccjit's
filename/version-dir helpers (they cannot reuse them: those live under
`#ifdef HAVE_NATIVE_COMP`). The `.zeln` version dir is distinct from gccjit's
so the two caches never collide.

---

## 8. Cache Population (`build-aux/populate-zeln-cache.zig`)

The `populate-zeln-cache` build step walks `lisp/**/*.elc`, and for each:
serialize via `comp-z-write-file-zunit`, run `zeln-compile` → `.zeln` into
`.zeln-cache/<version>/<rel>.zeln`. **Per-file fault-tolerant:** a `.elc` whose
bytecode can't round-trip (or hits any error) is *skipped* and recorded in
`.zeln-cache/SKIP-LIST`; the step exits 0. Skipped files fall back to the
interpreter via the transparent-load fallthrough. Current coverage: 100% of
compilable files (the print-circle/level/length fix closed the serialization
gap that had limited it to 46.6%).

---

## 9. Acceptance Gates

Every milestone must pass all four:

| # | Step | Pass criterion |
|---|------|----------------|
| 1 | `zig build -Dnative-comp-zig=true populate-zeln-cache` | exits 0; compiles all compilable `.elc`; records skips |
| 2 | `zig build -Dnative-comp-zig=true check-zeln` | **582 tests, 0 unexpected**, via `.zeln` — and `.zeln` code must *genuinely run* (load/count instrumentation), not a silent interpreter fallback (which passes trivially) |
| 3 | `zig build check` (switch **off**) | 582/582, 0 unexpected — **zero footprint** (compz.c not compiled, lread branch `#ifdef`'d) |
| 4 | `zig build -Dnative-comp-zig=true zeln-diff` | 37/37 functions identical (62/62 calls), incl. the multi-fn differential fixture |

The harness (`build-aux/zeln-diff.el`) byte-compiles each corpus function,
serializes it, compiles to `.zeln`, and funcalls the reference closure
(`exec_byte_code`) vs the native fn on a shared input set, asserting `equal`
— including thrown/signaled-error inputs routed through a `condition-case`
comparator.

---

## 10. Milestone Roadmap

- **M0** — prove the chain end-to-end (one spike fn: zunit → .ll → .zeln →
  load → freloc → call → correct result). ✅
- **M1** — Tier-0 emitter for ~35 core opcodes; differential gate 14/14. ✅
- **M1.5** — transparent load + `.zeln-cache`. ✅
- **M2a** — full opcode coverage incl. non-local control (setjmp pushhandler
  trampoline); differential 37/37. ✅
- **M2b** — cache-population + **582-via-.zeln** (the acceptance gate).
  🚧 **in progress** — infrastructure landed; gate #2 blocked (see §11).
- **M2b.1** — GC-root + memset + serialization fixes (resolved the cl-remove
  crash; cache coverage → ~100%). ✅
- **M2b.2** — "GC safepoint / register-residence" hypothesis **disproven**
  (crash identical at -O0); no change. ✅ (ruled out)
- **M2b.3** (active) — pin and fix the residual cl-print.zeln heap-corruption
  write → gate #2 green.
- **M2.5** — coexistence with gccjit (both switches on; precedence via
  `native-comp-z-prefer`).
- **M3** — Tier-1 perf specialization (virtual stack → SSA + opcode
  specialization); **beat the interpreter**. The user's core perf goal.

---

## 11. Gate #2 — RESOLVED ✅ (M2b.4 + M3a–M3e)

**Gate #2 is GREEN**: 582 built-in ert tests run via `.zeln`, 0 unexpected.
The `cl-print.zeln` heap-corruption crash was the session's defining chase
(M2b.1→M2b.4, 6+ hypotheses, extensive gdb). **Root cause (finally pinned):**
the `.zeln` loader allocates native subrs on the GC heap
(`ALLOCATE_PLAIN_PSEUDOVECTOR`), but GC's `PVEC_SUBR` case only marked gccjit
native subrs → the `.zeln` native subrs were traced-but-unmarked → GC swept
them while symbols still referenced them → use-after-free → crash. **Fix
(`deca709247f`):** mark heap subrs in `PVEC_SUBR`, guarded by
`!pdumper_object_p(ptr) && mem_find(ptr) != MEM_NIL` (skip static `.rodata` +
dumped subrs → no read-only write → gate #3 stays green).

### M3 Performance (Tier-1 inline specialization) — SURPASSES gccjit

The Tier-0 emitter already beat the interpreter (~1.9× at baseline, because
the unfolded IR eliminates per-opcode dispatch + `-O2 mem2reg` promotes
`%top.slot` to SSA). M3a–M3e added inline fast paths:

| Milestone | Specialization | Result |
|---|---|---|
| M3a | fixnum arith inline (Bplus/Bdiff/Bmult + sub1/add1/negate) | 0.54→0.41× interp |
| M3b+M3c | cons/car/cdr slot + comparisons/predicates inline | 0.41→0.27× interp, **0.66× eln** |
| M3d | NILP inline in conditional branches | further |
| M3e | fixed-arity prologue arg-copy inline | further |

**Final perf**: geomean native/interp **0.265×** (3.77× faster than the
interpreter); geomean native/eln **0.662×** (1.51× faster than gccjit `.eln`);
**every one of the 10 benchmark workloads beats gccjit individually**.
Behavioral identity preserved throughout (gate #2 582/582 + zeln-diff 37/37).

**Symptom:** `check-zeln` SIGSEGV/SIGABRT during GC. `cl-print.zeln`'s
load-time top-level writes a **pure-garbage** `Lisp_Object`
`0x8000000000000004` (Lisp_String tag 4 + invalid pointer
`0x8000000000000000`, the bare sign bit) into the heap, reachable from
`initial_obarray`; GC's `string_marked_p` dereferences it → crash.

**Ruled out (gdb/lldb, exhaustive):**
- Not interpreter fallback (native cl-prin1 verified `subrp=t`).
- Not GC/opt flakiness (identical at -O0/-O1/-O2).
- Not GC safepoint / register residence (disproven at -O0).
- Not via `Fset`/`Ffset`/`set_internal` (conditional breakpoints never fired).
- Not via structure primitives `zeln_cons`/`list`/`aset`/`setcar`/`setcdr`/
  `nconc` (never fired).
- Not a wrong `d_reloc` pointer (all 14 cl-print fns' `d_reloc` are in the
  `.zeln` mmap region, non-overlapping).
- Not freloc/IDX mis-dispatch (`main.zig` IDX_* match `compz.c`; hash gate
  enforces it).

**Bisect:** cl-seq.zeln native is clean; removing cl-print.zeln (cl-print
byte-code) eliminates the crash → **cl-print.zeln load-time is the trigger**.

**Remaining hypothesis:** a raw emitter/loader write of `0x8000000000000004`
to the heap, not flowing through any tested primitive.

**M2b.3 plan (in flight):**
1. **ASAN** — plumb `-fsanitize=address -fno-omit-frame-pointer -g` through
   *both* `temacs` (`build.zig` base_flags) *and* the `.zeln` compilation
   (`zeln-compile`'s `zig cc -shared`); rebuild, repopulate, run the repro.
   Caveat: the Lisp heap may be mmap chunks ASAN does not redzone, so ASAN is
   most likely to catch a **stack-buffer-overflow** from a native fn writing
   past its alloca virtual stack.
2. **Heap-chunk-aware find → watchpoint** — `info proc mappings` to enumerate
   mapped Lisp-heap chunks, `find /g <chunk>, <chunk+len>,
   0x8000000000000004` to locate the holding address, then `watch *<addr>` in
   a fresh run (addresses are deterministic) to catch the write.
3. **Bytecode diff** — diff cl-print.elc vs the 37-fn corpus to find the
   failing opcode pattern, then read the emitter's `emit*` for it.

**Repro (deterministic):** native-comp `temacs` + populated cache, then load
cl-macs/cl-seq/cl-extra/cl-print with `native-comp-zeln-load-path` set to the
cache root, garbage-collect. gdb + lldb are available.

---

## 12. Track B — Dynamic Modules (independent)

- **B-C (`HAVE_MODULES`)** — the upstream dynamic-module subsystem, enabled
  with `-Dmodules=true`. Activates the `#ifdef HAVE_MODULES` blocks across
  `data.c`/`alloc.c`/`emacs.c`/`eval.c`/`lread.c`; `dynlib.c` (already compiled
  for treesit) provides `dlopen`; `emacs-module.c` is added; `emacs-module.h`
  is the frozen public ABI. ✅
- **B-Z (`HAVE_MODULES_ZIG`)** — the Zig dynamic-module subsystem
  (`-Dmodules-zig=true`), independent of B-C. (Future.)

The two are fully independent: either, both, or neither may be on.

---

## 13. Cross-Platform & Linking

- Zig drives all compile/link (`zig cc` for C, `zig build` for the graph).
- `.zeln` reach C only through the loader-patched freloc pointer → the main
  executable needs **no `-rdynamic`**, and `.zeln` need **no extern symbols**
  (same property as gccjit `.eln`).
- Targets: Linux glibc (full + 582 tests), Linux musl (static), macOS
  (system libs at link), Windows gnu (TTY/console; GUI out of scope). The
  freloc/IDX surface and the `.zeln` layout are target-independent.
- Zero off-path footprint: `-Dnative-comp-zig` off ⇒ `compz.c` is not
  compiled, the `lread.c` swap is `#ifdef`'d out, and the default build is
  byte-identical to a non-native-comp emacs (gate #3: 582/582).

---

## 14. Risks

- **Gate #2 residual** (§11): the one correctness blocker; deterministic and
  reproducible, so locatable, but has resisted multiple hypotheses — needs
  ASAN/watchpoint to pin the exact write. A correctness prerequisite for M3.
- **Conservative-GC interaction**: any native-frame state that isn't a valid
  `Lisp_Object` or properly rooted can corrupt GC. The memset + d_reloc-root +
  storeTop model addresses the known classes; gate #2 is the at-scale stress.
- **Opcode long tail**: `Bswitch` (large pcache/cond) is deferred; any `.elc`
  using it is skipped to the interpreter. Adding it is straightforward when
  needed.
- **Native-frame backtrace/debugger parity**: a `.zeln` fn appears in the
  backtrace as a single subr frame (same shape as gccjit); full debug-on-error
  parity into native frames is M2.5+.

---

## References

- Plan: `.omc/plans/native-comp-zig-zeln.md` (internal; detailed milestone
  specs, §0 acceptance pillars, §5 full contract, §6 milestones).
- C side: `src/compz.c`, `src/compz.h`.
- Compiler: `tools/zeln-compile/src/main.zig`, `tools/zeln-compile/build.zig.zon`.
- Harness: `build-aux/zeln-diff.el`.
- Drivers: `build-aux/populate-zeln-cache.zig`, `build-aux/run-check.zig`.
- Build wiring: `build.zig` (`-Dnative-comp-zig` switch ~line 69; the
  `zeln-diff` / `populate-zeln-cache` / `check-zeln` steps).
- gccjit reference (untouched): `src/comp.c`, `src/comp.h`.
