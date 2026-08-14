;;; zeln-bench.el --- Tier-1 perf benchmark: .zeln native vs interpreter  -*- lexical-binding: t; -*-

;; The M3a perf gate:
;; for each workload closure, byte-compile it (the reference interpreter
;; path, exec_byte_code), serialize it to a zunit, compile to a .zeln
;; via the `zeln-compile' tool (located via ZELN_COMPILE), load it via
;; `comp-z-load-zeln', then time both implementations over the same
;; inputs (best-of-N) and report native/interp per workload + geomean.
;;
;; Ratio convention: native_time / interp_time.  LOWER is better
;; (native is faster).  < 1.0 means the .zeln beats the interpreter.
;; With a non-nil arg, `zeln-bench-run' also compiles each workload to
;; an .eln (gccjit native-comp) and reports native/eln — the M3+ perf
;; gate (zeln must beat gccjit).
;;
;; Invoked from the build root (a -Dnative-comp-zig=true emacs):
;;   ZELN_COMPILE=<path-to-zeln-compile> \
;;     ./zig-out/bin/emacs --batch -l build-aux/zeln-bench.el \
;;     --eval '(zeln-bench-run)'          ; zeln vs interpreter
;;     --eval '(zeln-bench-run t)'        ; + zeln vs eln (gccjit)
;;
;; The workloads use ONLY the M2 opcode subset (any out-of-subset opcode
;; is REJECTed by the emitter at compile time, failing the run).  They
;; span the categories the M3a baseline measured: dispatch-bound loops
;; (sum/count/compare), recursion (fib/fact), list ops (build/sum),
;; bignum (overflow), and the dense-arithmetic no-loop case whose
;; per-arith-op freloc+Fprimitive cost is exposed with no dispatch
;; savings to offset it (the prime target for fixnum inlining).

(defvar zeln-bench-zc nil
  "Path to the zeln-compile tool.  Set from ZELN_COMPILE before running.")

;; Each entry: (NAME LAMBDA INPUTS ITERS [BIND])
;;   NAME    symbol naming the workload (-> temp <name>.zunit/.zeln).
;;   LAMBDA the lambda form to byte-compile (the reference closure).
;;   INPUTS list of strings; each is an Elisp list of args to `apply'.
;;           The FIRST input is the one timed (others are correctness
;;           spot-checks asserting native == interpreter).
;;   ITERS  repeat count for the timed call (best-of-3).
;;   BIND   nil, or a symbol whose function slot is fset to the closure
;;           under test before each timed run (self-recursive fns whose
;;           recursive call resolves through the symbol's function slot).
(defconst zeln-bench-workloads
  '((sum-loop
     (lambda (n) (let ((s 0)) (while (> n 0) (setq s (+ s n)) (setq n (- n 1))) s))
     ("(1000)") 1000 nil)
    (count-up
     (lambda (n) (let ((s 0) (i 0)) (while (< i n) (setq s (+ s 1)) (setq i (+ i 1))) s))
     ("(1000)") 1000 nil)
    (prod-loop
     (lambda (n) (let ((p 1)) (while (> n 0) (setq p (* p n)) (setq n (- n 1))) p))
     ("(12)") 100000 nil)
    ;; sum-loop-ovf: each addend is most-positive-fixnum, so every other
    ;; + overflows to a bignum (exercises the inline fallback block).
    (sum-loop-ovf
     (lambda (n) (let ((s 0))
                   (while (> n 0)
                     (setq s (+ s 2305843009213693951))
                     (setq n (- n 1)))
                   s))
     ("(200)") 5000 nil)
    (fib-rec
     (lambda (n) (if (< n 2) n (+ (zeln-bench-fib (1- n)) (zeln-bench-fib (- n 2)))))
     ("(20)") 50 zeln-bench-fib)
    (fact-rec
     (lambda (n) (if (= n 0) 1 (* n (zeln-bench-fact (1- n)))))
     ("(15)") 500 zeln-bench-fact)
    (list-build
     (lambda (n) (let ((l nil) (i 0))
                   (while (< i n) (setq l (cons i l)) (setq i (+ i 1)))
                   l))
     ("(500)") 2000 nil)
    (list-sum
     (lambda (lst) (let ((s 0))
                     (while (consp lst)
                       (setq s (+ s (car lst)))
                       (setq lst (cdr lst)))
                     s))
     ("((1 2 3 4 5 6 7 8 9 10))") 2000 nil)
    (compare-loop
     (lambda (n) (let ((c 0) (i 0))
                   (while (< i n)
                     (when (> i 0) (setq c (+ c 1)))
                     (setq i (+ i 1)))
                   c))
     ("(1000)") 1000 nil)
    ;; dense-arith: no loop, 3 arith ops per call (Bmult, Bdiff, Bplus).
    ;; The freloc+Fprimitive cost is fully exposed (no dispatch amortization).
    (dense-arith
     (lambda (a b c) (+ (* a b) (- a c)))
     ("(3 5 2)") 2000000 nil))
  "The 10 M3a benchmark workloads.  See header for the ratio convention.")

(defun zeln-bench-byte-compile (form)
  "Byte-compile FORM under `lexical-binding' so it yields a real lexical
closure (CLOSUREP), the shape `comp-z-write-zunit' accepts."
  (let ((lexical-binding t))
    (byte-compile form)))

(defun zeln-bench--time (fn args iters bind target)
  "Apply FN to ARGS ITERS times, return elapsed seconds.  BIND's
function slot is fset to TARGET (so recursive calls resolve correctly).
GC is suppressed (high threshold) so pauses do not skew either side."
  (when bind (fset bind target))
  (let ((start (float-time)))
    (dotimes (_ iters)
      (apply fn args))
    (- (float-time) start)))

(defun zeln-bench--best-of-3 (fn args iters bind target)
  "Run the timed loop 3 times; return the minimum (least noisy) elapsed
seconds.  A 2-iteration warmup primes the cache before the 3 measured
runs."
  ;; Warmup (untimed): prime icache / branch predictors / the .zeln.
  (zeln-bench--time fn args (min 1000 iters) bind target)
  (let ((best nil))
    (dotimes (_ 3 best)
      (let ((dt (zeln-bench--time fn args iters bind target)))
        (setq best (if (or (null best) (< dt best)) dt best))))))

(defun zeln-bench-native-compile-eln (form)
  "Native-compile (gccjit) the lambda FORM to an .eln subr.
`native-compile' on a lambda FORM dispatches comp--spill-lap-function
((form list)) in this tree (no byte-code-function method), so pass the
raw form, not a byte-compiled closure."
  (require 'comp)
  (native-compile form))

(defun zeln-bench-run (&optional with-eln)
  "Run every workload; WITH-ELN non-nil also compiles .eln (gccjit) and
reports the zeln/eln ratio (THE M3+ perf gate: lower = zeln faster).

Always prints per-workload native/interp ratio + geomean.  With WITH-ELN
it additionally prints eln/interp (gccjit reference) and native/eln
(zeln vs gccjit), the objective metric.

Exits non-zero if the tool/serialization/load fails or if any native
result mismatches the interpreter on the spot-check inputs.  Returns
the geomean ratio (also printed)."
  (unless (fboundp 'comp-z-write-zunit)
    (message "zeln-bench: comp-z-write-zunit not bound (build without \
-Dnative-comp-zig=true?)")
    (kill-emacs 1))
  (let ((envzc (getenv "ZELN_COMPILE")))
    (setq zeln-bench-zc
          (if (and envzc (not (string= envzc "")))
              envzc
            ;; Auto-discover: pick the NEWEST zeln-compile under .zig-cache by
            ;; mtime.  directory-files-recursively returns traversal (not mtime)
            ;; order, and .zig-cache accumulates stale pre-inline binaries from
            ;; prior builds -- picking by traversal order silently measured a
            ;; no-inline binary and reported a false baseline.  Sort newest-first
            ;; so the just-built binary (with the current inline fast paths) wins.
            (let* ((cands (directory-files-recursively
                           (expand-file-name ".zig-cache") "^zeln-compile$" nil))
                   (sorted (sort cands
                                 (lambda (a b)
                                   (> (float-time (file-attribute-modification-time
                                                   (file-attributes a)))
                                      (float-time (file-attribute-modification-time
                                                   (file-attributes b))))))))
              (car sorted)))))
  (unless (and zeln-bench-zc (stringp zeln-bench-zc)
               (not (string= zeln-bench-zc ""))
               (file-executable-p zeln-bench-zc))
    (message "zeln-bench: zeln-compile not found (set ZELN_COMPILE)")
    (kill-emacs 1))
  (let* ((dir (make-temp-file "zeln-bench-" t))
         (gc-cons-threshold most-positive-fixnum) ; suppress GC during timing
         (log-ration 0.0)
         (log-eln 0.0)
         (log-zeln-eln 0.0)
         (nwork 0)
         (failures 0))
    (unwind-protect
        ;; `dolist' without a result form does NOT establish a cl-block, so
        ;; abort via catch/throw (a cl-return-from nil would signal
        ;; void-variable --cl-block-nil-- on the failure path).
        (catch 'zeln-bench-abort
          (dolist (entry zeln-bench-workloads)
            (let* ((name (car entry))
                   (form (cadr entry))
                   (inputs (nth 2 entry))
                   (iters (nth 3 entry))
                   (bind (nth 4 entry))
                   (baseline (zeln-bench-byte-compile form))
                   (prefix (expand-file-name (symbol-name name) dir))
                   (zelnfile (concat prefix ".zeln"))
                   rc native eln)
              ;; Serialize + compile + load (.zeln).
              (comp-z-write-zunit baseline prefix)
              (setq rc (call-process zeln-bench-zc nil (list (concat prefix ".log")) nil
                                     (concat prefix ".zunit")
                                     (concat prefix ".manifest")
                                     zelnfile))
              (unless (and (numberp rc) (= rc 0))
                (message "zeln-bench: %s zeln-compile exit %S" name rc)
                (setq failures (1+ failures))
                (throw 'zeln-bench-abort nil))
              (setq native (comp-z-load-zeln zelnfile))
              ;; Optional .eln (gccjit) reference: native-compile the RAW form.
              (when with-eln
                (setq eln (condition-case e (zeln-bench-native-compile-eln form)
                            (error (message "zeln-bench: %s eln compile failed: %S" name e)
                                   (setq failures (1+ failures))
                                   nil)))
                (when (and eln (not (functionp eln))) (setq eln nil)))
              ;; Correctness spot-check on every input (zeln == eln == interp).
              (dolist (in inputs)
                (let* ((args (read in))
                       (r0 (condition-case e (apply baseline args) (error (cons 'error e))))
                       (r1 (condition-case e (apply native args) (error (cons 'error e))))
                       (r2 (when eln (condition-case e (apply eln args) (error (cons 'error e))))))
                  ;; fset bind for recursive resolution during spot-check.
                  (when bind (fset bind baseline)
                    (let ((rb (condition-case e (apply baseline args) (error (cons 'error e))))
                          (rn (condition-case e
                                 (progn (fset bind native) (apply native args))
                               (error (cons 'error e))))
                          (re (when eln
                                (condition-case e
                                    (progn (fset bind eln) (apply eln args))
                                  (error (cons 'error e))))))
                      (setq r0 rb r1 rn r2 re)))
                  (unless (equal r0 r1)
                    (message "zeln-bench MISMATCH: %s input=%S interp=%S native=%S"
                             name args r0 r1)
                    (setq failures (1+ failures)))
                  (when (and eln (not (equal r0 r2)))
                    (message "zeln-bench ELN-MISMATCH: %s input=%S interp=%S eln=%S"
                             name args r0 r2)
                    (setq failures (1+ failures)))))
              (when (> failures 0) (throw 'zeln-bench-abort nil))
              ;; Time all three on the FIRST input.
              (let* ((args (read (car inputs)))
                     (t-int (zeln-bench--best-of-3 baseline args iters bind baseline))
                     (t-nat (zeln-bench--best-of-3 native    args iters bind native))
                     (t-eln (when eln (zeln-bench--best-of-3 eln args iters bind eln)))
                     (ration (if (> t-int 0) (/ t-nat t-int) 0.0)))
                (setq log-ration (+ log-ration (log ration))
                      nwork (1+ nwork))
                (when t-eln
                  (setq log-eln (+ log-eln (log (/ t-eln t-int)))
                        log-zeln-eln (+ log-zeln-eln (log (/ t-nat t-eln))))
                  (message "zeln-bench: %-14s interp=%7.4fs native=%7.4fs eln=%7.4fs  native/interp=%.3f  eln/interp=%.3f  native/eln=%.3f"
                           name t-int t-nat t-eln ration (/ t-eln t-int) (/ t-nat t-eln)))
                (message "zeln-bench: %-14s interp=%7.4fs native=%7.4fs  native/interp=%.3f"
                         name t-int t-nat ration))))
          ;; Summary -- still inside the catch; a throw aborts here.
          (if (> nwork 0)
              (let ((geo (exp (/ log-ration nwork))))
                (message "zeln-bench: GEOMEAN native/interp = %.3f across %d workloads (lower=faster)"
                         geo nwork)
                (when (and with-eln (> nwork 0))
                  (message "zeln-bench: GEOMEAN eln/interp = %.3f (gccjit reference)" (exp (/ log-eln nwork)))
                  (message "zeln-bench: GEOMEAN native/eln = %.3f across %d workloads (zeln vs gccjit; <1 = zeln faster)"
                           (exp (/ log-zeln-eln nwork)) nwork))
                geo)
            (message "zeln-bench: no workloads measured")
            (kill-emacs 1)))
      (when (and dir (file-directory-p dir))
        (delete-directory dir t)))))
;;; zeln-bench.el ends here
