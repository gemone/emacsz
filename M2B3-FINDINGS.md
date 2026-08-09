# M2b.3 residual: execution-time corruption in cl-print native fns

Status of the M2b.3 goal (check-zeln 582/582) as of this note:

## DONE (committed by the parallel workflow agent)

- Load-time corruption FIXED: commit `e96311510ea` "build: print-circle the
  top_level_blob serialization (M2b.3 partial)".  The top_level_blob was
  Fprin1'd without print-circle, so shared/circular top-level forms (e.g.
  cl-print's cl-defgeneric machinery) printed as corrupt read-syntax, Fread
  back as garbage, and Feval corrupted the heap (GC reached an invalid-tag
  object via initial_obarray).  Verified: with the rebuilt temacs + cache,
  `(load "cl-seq")` + 2 GCs and `cl-macs + cl-seq + cl-extra + GC` repros pass.

## RESIDUAL (the remaining M2b.3 work): execution-time corruption

When cl-print's NATIVE fns actually run (not load), memory is corrupted.

### Minimal repro (deterministic, ~1s)

```elisp
;; /tmp/rQ.el
(setq gc-cons-threshold most-positive-fixnum)
(setq native-comp-zeln-load-path (list (expand-file-name "zig-out/zeln-cache")))
(load "cl-macs") (load "cl-seq") (load "cl-extra") (load "cl-print")
(let ((fn (symbol-function 'cl-print--vector-contents)))
  (dotimes (i 200) (funcall fn (make-vector 30 'z) 0 (current-buffer))))
(garbage-collect)
(type-of (symbol-function 'cl-print--vector-contents))  ; crashes here
```

Crashes with SIGABRT at `Fcl_type_of` (data.c:301) because
`(symbol-function 'cl-print--vector-contents)` is no longer a subr.

### Evidence gathered

1. **Corrupted value is DETERMINISTIC across runs**:
   `0x7ffff62edccd` (tag 5) = dump_base (0x7ffff619c000) + 0x151cc8.
2. **0x151cc8 points INTO a dumped cons chain** (the pdmp at 0x151cc0-0x151ce8
   is a chain of conses: car=0x3f0xxx, cdr=0x151cd0/0x151ce0/...).  The
   corrupted value is the RUNTIME ADDRESS of a dumped cons's **cdr field**.
3. The write lands in `cl-print--vector-contents`'s SYMBOL function slot
   (symbol found at 0x1a4660, slot at 0x1a4678 in the then-current binary).
4. Trigger: the native fn's own call tree (cl-print-object generic dispatch
   → symbol/vector methods → cl-print-insert-ellipsis etc.).  Calling
   cl-print--vector-contents directly 200x + GC corrupts it.
5. NOT the blob path (top_level_blob len=0 still crashed); NOT the d_reloc
   rooting (M2b.1 fixed that); fn-table layout is correct (64/64 elements);
   Bstack_ref semantics match the interpreter; fn's own freloc calls are all
   bounds-checked C shims; the alloca (stack_depth+2) sizing is correct.
6. gc-cons-threshold=most-positive-fixnum still crashes → NOT a dangling
   pointer from a sweep; it is a direct WRITE of a dump-relative pointer
   into the heap.
7. ASAN on the .zeln did not fire (Emacs heap is mmap chunks, no redzones).
8. The gdb layout differs (rH/rQ pass under gdb) — hardware-watchpoint runs
   must use the value-stable corruption (watch the fn slot).

### Most likely mechanism (unverified)

A native fn (or its freloc path) computes `dump_base + <field_offset>` and
stores it as a Lisp_Object.  Suspects in order:

1. An emitter translation that produces a field ADDRESS instead of the field
   VALUE for one opcode (getelementptr without a following load), combined
   with a dumped cons constant.  Check `Bcdr`/`Bcar`/`Belt`/`Baref`
   translations against a DUMPED cons argument.
2. A pdumper relocation of a dumped cons whose cdr field was mis-relocated
   (field address vs content) — but relocation only writes to dump memory,
   so this would need the VALUE to leak via a constant.
3. cl-print-object's generic dispatch: `cl--generic` method dispatch
   conses/closure machinery interacting with a native callee.

### Next steps (blocked on a stable binary)

1. Build a stable `-Dnative-comp-zig=true` binary + repopulate the cache
   (the parallel agent's `zig build -Dnative-comp=true` keeps overwriting
   zig-out; do this when its build finishes).
2. Re-find the fn-slot address (it shifts per build), set a hardware
   watchpoint, run rQ, and catch the exact writing instruction (it will be
   in the .zeln's native code or a C shim).
3. Or: bisect the cl-print-object method dispatch by calling each native
   method directly (cl-print--cons-tail, cl-print--struct-contents,
   cl-print--find-sharing, cl-print--preprocess, cl-print-insert-ellipsis)
   to find the corrupting fn, then diff its emitted IR against the
   interpreter semantics.
