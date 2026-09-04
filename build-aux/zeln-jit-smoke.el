;;; zeln-jit-smoke.el --- executable gate for the in-process JIT -*- lexical-binding: t; -*-

;; Exercise common ways for a JIT cache to look "working" while running
;; the wrong object: a rebuilt closure with fresh constants, a freloc
;; error path, a jump table, and a cons-slot fast path.  Every check
;; must agree with the interpreter before the gate passes.

(defun zeln-jit-smoke-make (limit)
  "Return a fixed-arity lexical closure comparing X with LIMIT."
  (byte-compile (lambda (x) (> x limit))))

(defun zeln-jit-smoke-switch (which)
  "Return a small fixed-arity closure containing a byte-switch."
  (byte-compile
   (lambda (which)
     (pcase which
       (:one 1)
       (:two 2)
       (:three 3)
       (_ 0)))))

(defun zeln-jit-smoke-car-make ()
  "Return a tiny bytecode closure that reads a cons cell's car."
  (byte-compile (lambda (cell) (car cell))))

(defun zeln-jit-smoke-identity-make ()
  "Return a short fixed-arity bytecode closure for cache-dump bounds."
  (byte-compile (lambda (x) x)))

(defun zeln-jit-smoke-closure-caller-make ()
  "Return a caller that invokes a closure received as its first argument."
  (byte-compile (lambda (square n) (funcall square n))))

(defun zeln-jit-smoke-square-make ()
  "Return a tiny fixed-arity square bytecode closure."
  (byte-compile (lambda (n) (* n n))))

(defun zeln-jit-smoke-aot-callee (n)
  "Tiny fixed-arity callee used by the AOT-to-JIT smoke caller."
  (* n n))

(defvar zeln-jit-smoke-zc nil
  "Path to zeln-compile, supplied by the build step.")

(defun zeln-jit-smoke-aot-compile (caller dir)
  "Serialize and AOT-compile CALLER into temporary DIR."
  (unless (and zeln-jit-smoke-zc (file-executable-p zeln-jit-smoke-zc))
    (error "zeln-jit-smoke: ZELN_COMPILE is unavailable"))
  (let* ((prefix (expand-file-name "aot-jit-caller" dir))
         (zunit (concat prefix ".zunit"))
         (manifest (concat prefix ".manifest"))
         (zelnfile (concat prefix ".zeln"))
         (rc (progn
               (comp-z-write-zunit caller prefix)
               (call-process zeln-jit-smoke-zc nil nil nil
                             zunit manifest zelnfile))))
    (unless (and (numberp rc) (= rc 0))
      (error "zeln-jit-smoke: AOT caller compile failed: %S" rc))
    (comp-z-load-zeln zelnfile)))

(defvar zeln-jit-smoke-fib)

(defun zeln-jit-smoke-fib-make ()
  "Return a symbol-dispatched Fibonacci bytecode closure."
  (byte-compile
   (lambda (n)
     (if (< n 2) n
       (+ (zeln-jit-smoke-fib (1- n))
          (zeln-jit-smoke-fib (- n 2)))))))

(defun zeln-jit-smoke-run ()
  "Compile and execute two closures sharing one bytecode string."
  (unless (zeln-jit-supported-p)
    (message "zeln-jit-smoke: SKIP (unsupported CPU)")
    (kill-emacs 0))
  (setq zeln-jit-smoke-zc
        (expand-file-name (or (getenv "ZELN_COMPILE") "zeln-compile")))
  (let* ((hot (zeln-jit-smoke-make 1))
         (rebuilt (zeln-jit-smoke-make 100))
         (car-hot (zeln-jit-smoke-car-make))
         (cells (mapcar (lambda (n) (cons n (* n 10))) (number-sequence 0 299)))
         (error-seen nil))
    ;; Cross the hotness threshold and force a compile.  The exact
    ;; predicate (not just a correct result) proves the machine-code
    ;; dispatch really took over.
    ;; Threshold 1 also proves the runtime tuning variable reaches the
    ;; C hotness gate rather than only existing as Lisp documentation.
    (let ((zeln-jit-threshold 1)
          (i 0))
      (while (< i 300)
        (unless (funcall hot (+ i 2))
          (error "zeln-jit-smoke: hot closure returned nil at %d" i))
        (setq i (1+ i))))
    (unless (eq (zeln-jit-compiled-p hot) t)
      (error "zeln-jit-smoke: hot closure did not compile"))

    ;; Same bytecode, fresh constants.  The cache must not expose the
    ;; hot closure's stale constants before this closure has adopted a
    ;; shared entry.
    (unless (null (zeln-jit-compiled-p rebuilt))
      (error "zeln-jit-smoke: rebuilt closure saw a stale JIT entry"))

    ;; One invocation compiles the rebuilt closure against its own fresh
    ;; constants vector and executes it.
    (unless (and (funcall rebuilt 101)
                 (not (funcall rebuilt 1))
                 (eq (zeln-jit-compiled-p rebuilt) t))
      (error "zeln-jit-smoke: rebuilt closure did not adopt/use JIT"))

    ;; A freloc helper legitimately signals for a non-number.  Surviving
    ;; this condition-case exercises non-local exit out of generated
    ;; code and back into the Lisp handler.
    (condition-case err
        (funcall rebuilt 'not-a-number)
      (wrong-type-argument (setq error-seen err)))
    (unless error-seen
      (error "zeln-jit-smoke: expected wrong-type-argument"))

    ;; pcase lowers to Bswitch.  Accepting this closure proves that the
    ;; JIT follows the same AOT jump-table helper rather than silently
    ;; rejecting a common modern-bytecode construct.
    (let ((zeln-jit-threshold 1))
      (let* ((switched (zeln-jit-smoke-switch :three))
             (results (list (funcall switched :one)
                            (funcall switched :three)
                            (funcall switched 'other))))
        (unless (and (eq (zeln-jit-compiled-p switched) t)
                     (equal results '(1 3 0)))
          (error "zeln-jit-smoke: switch closure rejected/wrong: %S" results))))

    ;; A car closure must accept Bcar instead of staying on the generic
    ;; freloc dispatch.  Repeated calls execute the cons-slot fast path;
    ;; result comparison catches either an incorrect untag or a stale top.
    (let ((zeln-jit-threshold 1)
          (i 0))
      (while (< i 300)
        (unless (eq (funcall car-hot (nth i cells)) i)
          (error "zeln-jit-smoke: car closure returned wrong value at %d" i))
        (setq i (1+ i))))
    (unless (eq (zeln-jit-compiled-p car-hot) t)
      (error "zeln-jit-smoke: car closure did not compile"))

    ;; `zeln-jit-dump' must consult each cache entry's bytecode length.
    ;; This short identity closure catches out-of-bounds fixed-window reads.
    (let ((zeln-jit-threshold 1)
          (identity (zeln-jit-smoke-identity-make))
          (i 0))
      (while (< i 2)
        (unless (eq (funcall identity i) i)
          (error "zeln-jit-smoke: identity closure returned wrong value at %d" i))
        (setq i (1+ i)))
      (unless (eq (zeln-jit-compiled-p identity) t)
        (error "zeln-jit-smoke: identity closure did not compile"))
      (let ((dump (zeln-jit-dump)))
        (unless (listp dump)
          (error "zeln-jit-smoke: JIT dump is not a list: %S" dump))
        (dolist (bytes dump)
          (unless (and (vectorp bytes) (<= (length bytes) 64))
            (error "zeln-jit-smoke: invalid JIT dump entry: %S" bytes)))))

    ;; Recursive symbol dispatch is the principal JIT->JIT hot path.
    ;; After the outer call compiles, every inner symbol call must find
    ;; the same validated entry without changing the result.
    (fset 'zeln-jit-smoke-fib (zeln-jit-smoke-fib-make))
    (let ((zeln-jit-threshold 1)
          (fib (symbol-function 'zeln-jit-smoke-fib)))
      (unless (and (eq (funcall fib 20) 6765)
                   (eq (zeln-jit-compiled-p fib) t))
        (error "zeln-jit-smoke: recursive JIT dispatch failed")))

    ;; Lexically/functionally passed closure objects use a different Bcall
    ;; shape from symbol dispatch.  Force both caller and callee through
    ;; the JIT, then prove the second call's closure-object fast path runs
    ;; while retaining the generic fallback on the first cold callee call.
    (let ((zeln-jit-threshold 1)
          (square (zeln-jit-smoke-square-make))
          (caller (zeln-jit-smoke-closure-caller-make)))
    (unless (and (eq (funcall caller square 12) 144)
                   (eq (funcall caller square 13) 169)
                   (eq (zeln-jit-compiled-p caller) t)
                   (eq (zeln-jit-compiled-p square) t))
        (error "zeln-jit-smoke: closure-object JIT call failed")))

    ;; AOT-to-JIT seam: load a native .zeln caller and bind its symbol
    ;; call to a JIT callee.  Generated calls intentionally use the full
    ;; Ffuncall boundary, so assert the guarded direct fast-call counter
    ;; remains unchanged and the callee still enters the same JIT entry.
    (let ((zeln-jit-threshold 1)
          (dir (make-temp-file "zeln-jit-smoke-aot-" t))
          (fast0 (nth 4 (zeln-jit-stats)))
          native caller)
      (unwind-protect
          (progn
            (fset 'zeln-jit-smoke-aot-callee
                  (byte-compile (lambda (n) (* n 2))))
            (setq caller (zeln-jit-smoke-aot-compile
                          (byte-compile
                           (lambda (n)
                             (zeln-jit-smoke-aot-callee (+ n 1))))
                          dir))
            (unless (subrp caller)
              (error "zeln-jit-smoke: AOT caller did not load as subr"))
            (let ((callee (symbol-function 'zeln-jit-smoke-aot-callee)))
              (unless (eq (funcall callee 7) 14)
                (error "zeln-jit-smoke: AOT callee failed to JIT"))
              (unless (eq (zeln-jit-compiled-p callee) t)
                (error "zeln-jit-smoke: AOT callee is not JIT-compiled")))
            (setq native caller)
            (unless (eq (funcall native 8) 18)
              (error "zeln-jit-smoke: AOT-to-JIT result mismatch"))
            (unless (= (nth 4 (zeln-jit-stats)) fast0)
              (error "zeln-jit-smoke: unsafe AOT-to-JIT fast call ran")))
      ;; On combined eln+zeln builds, .zeln must be introspectable through
      ;; the same native-comp metadata as .eln.  On zeln-only builds the
      ;; data.c accessors are unavailable, so this check is conditional.
      (when (and native (fboundp 'native-comp-function-p)
                 (fboundp 'subr-native-comp-unit)
                 (fboundp 'native-comp-unit-file))
        (unless (eq (native-comp-function-p native) t)
          (error "zeln-jit-smoke: AOT subr lacks native-comp-function metadata"))
        (unless (string-suffix-p
                 ".zeln"
                 (expand-file-name
                  (native-comp-unit-file (subr-native-comp-unit native))))
          (error "zeln-jit-smoke: AOT native-comp-unit file is not .zeln")))
        (fmakunbound 'zeln-jit-smoke-aot-callee)
        (when (and dir (file-directory-p dir))
          ;; Windows: the .zeln is dlopen'd and the OS file lock prevents
          ;; deletion while loaded.  Best-effort cleanup: ignore the error.
          (condition-case nil
              (delete-directory dir t)
            (file-error nil)))))

    (message "zeln-jit-smoke: PASS")))

(provide 'zeln-jit-smoke)
;;; zeln-jit-smoke.el ends here
