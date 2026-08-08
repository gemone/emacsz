;;; zeln-diff.el --- M1 differential test harness (Zig native-comp path)  -*- lexical-binding: t; -*-

;; The M1 correctness gate (plan .omc/plans/native-comp-zig-zeln.md M1):
;; for each corpus fn, byte-compile it with the standard bytecomp.el
;; (untouched), serialize it to a zunit via `comp-z-write-zunit', and
;; compare funcalling the resulting .zeln native fn against the reference
;; bytecode closure (exec_byte_code) on a shared set of inputs.  Behavioral
;; IDENTITY is the only gate; speed is not measured (Tier-0; M3 is the perf
;; gate).
;;
;; Invoked from build.zig's `zeln-diff' step:
;;   emacs --batch -l build-aux/zeln-diff.el --eval '(zeln-diff-run-serialize)'
;;   ... zeln-compile per fn ...
;;   emacs --batch -l build-aux/zeln-diff.el --eval '(zeln-diff-run-harness)'
;;
;; The corpus is hand-written so its bytecode uses ONLY the M1 opcode
;; subset (any out-of-subset opcode is rejected by the emitter at compile
;; time, failing the build).

(defvar zeln-diff-dir "zig-out/bin/zeln-diff/"
  "Where .zunit/.manifest/.zeln artifacts land (under the build root).")

;; Each entry: (NAME FORM INPUTS BIND)
;;   NAME    symbol naming the fn (-> <dir>/<name>.zunit etc.)
;;   FORM    the lambda form to byte-compile (the reference closure)
;;   INPUTS  list of strings; each is an Elisp list of args to `apply'
;;   BIND    nil, or a symbol whose function slot is fset to the closure
;;           under test before each call (for self-recursive fns whose
;;           recursive call resolves through the symbol's function slot).
;;
;; Edge cases the corpus MUST include (plan M1 DIFF TEST): fixnum-overflow
;; (-> bignum), &rest args, nil/empty-list, nested recursion, backward-
;; branch loops (stack-depth-at-loop-header), constant indices >=64
;; (Bconstant2), and a fn with >5 args (Bcall6/Bcall7 FETCH2).
(defvar zeln-diff-corpus
  '((inc
     (lambda (x) (+ x 1))
     ("(0)" "(41)" "(2305843009213693951)") ; last = most-positive-fixnum -> bignum
     nil)
    (arith
     (lambda (x y) (* (+ x 1) (- y 2)))
     ("(3 5)" "(10 1)" "(2305843009213693951 2)")
     nil)
    (abs
     (lambda (x) (if (> x 0) x (- x)))
     ("(5)" "(-3)" "(0)")
     nil)
    (cadr
     (lambda (lst) (car (cdr lst)))
     ("((1 2 3))" "((10))")
     nil)
    (conslist
     (lambda (a b) (cons a (list b)))
     ("(1 2)" "(x y)")
     nil)
    (loop                              ; backward-branch loop, Bstack_set
     (lambda (n) (let ((s 0))
                   (while (> n 0)
                     (setq s (+ s n))
                     (setq n (- n 1)))
                   s))
     ("(10)" "(100)" "(0)")
     nil)
    (rec                               ; recursion via Bcall on a symbol
     (lambda (n) (if (= n 0) 1 (* n (zeln-diff-fact (1- n)))))
     ("(5)" "(0)" "(10)")
     zeln-diff-fact)
    (fmt                               ; Bcall to a subr (format)
     (lambda (n) (format "<%d>" n))
     ("(5)" "(0)" "(2305843009213693951)")
     nil)
    (list3
     (lambda (a b c) (list a b c))
     ("(1 2 3)")
     nil)
    (strpred
     (lambda (x) (stringp (car x)))
     ("((\"hi\"))" "((5))" "(nil)")
     nil)
    (rest                              ; &rest args (zeln_setup_args rest branch)
     (lambda (&rest xs) xs)
     ("(1 2 3)" "()")
     nil)
    (list6                             ; >5 args -> BlistN(6) / Bcall6 FETCH
     (lambda (a b c d e f) (list a b c d e f))
     ("(1 2 3 4 5 6)")
     nil)
    (list7                             ; >5 args -> BlistN(7) / Bcall7 FETCH2
     (lambda (a b c d e f g) (list a b c d e f g))
     ("(1 2 3 4 5 6 7)")
     nil)
    (const2                            ; 65 distinct constants -> Bconstant2
     (lambda () (list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
                     20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36
                     37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53
                     54 55 56 57 58 59 60 61 62 63 64))
     ("()")
     nil))
  "The M1 differential-test corpus.  See plan M1 DIFF TEST for the edges.")

(defun zeln-diff-byte-compile (form)
  "Byte-compile FORM under `lexical-binding' so it yields a real lexical
closure (CLOSUREP with a fixnum args-template), the exact shape
`comp-z-write-zunit' accepts and `exec_byte_code' consumes."
  (let ((lexical-binding t))
    (byte-compile form)))

;; ---- Serialize phase: write <dir>/<name>.zunit + .manifest per fn. ----
(defun zeln-diff-run-serialize ()
  "Byte-compile each corpus fn and serialize it via `comp-z-write-zunit'."
  (unless (fboundp 'comp-z-write-zunit)
    (message "zeln-diff: comp-z-write-zunit not bound (build without \
-Dnative-comp-zig=true?)")
    (kill-emacs 1))
  (make-directory zeln-diff-dir t)
  (dolist (entry zeln-diff-corpus)
    (let* ((name (car entry))
           (form (cadr entry))
           (closure (zeln-diff-byte-compile form)))
      (unless (closurep closure)
        (message "zeln-diff: %s did not compile to a lexical closure" name)
        (kill-emacs 1))
      (let ((prefix (expand-file-name (symbol-name name) zeln-diff-dir)))
        (comp-z-write-zunit closure prefix)
        (message "zeln-diff: serialized %s -> %s.zunit" name prefix)))))

;; ---- Harness phase: load each .zeln, funcall baseline vs native. ----
(defvar zeln-diff--n nil "Total calls checked.")
(defvar zeln-diff--fails nil "Alist of (name . n-failed-calls).")

(defun zeln-diff--apply (fn args bind target)
  "Apply FN to ARGS, with BIND's function slot fset to TARGET for any
recursive resolution.  Errors are returned as `(error . ,e) for comparison."
  (when bind (fset bind target))
  (condition-case err
      (apply fn args)
    (error (cons 'error err))))

(defun zeln-diff-run-harness ()
  "Load each .zeln and assert baseline == native on every input.
Exits non-zero on the first mismatch (printing name/input/both values)."
  (setq zeln-diff--n 0
        zeln-diff--fails nil)
  (let ((n-fns 0))
    (dolist (entry zeln-diff-corpus)
      (let* ((name (car entry))
             (form (cadr entry))
             (inputs (nth 2 entry))
             (bind (nth 3 entry))
             (baseline (zeln-diff-byte-compile form))
             (zeln-path (expand-file-name
                         (concat (symbol-name name) ".zeln") zeln-diff-dir))
             (native (comp-z-load-zeln zeln-path))
             (fn-failed 0))
        (dolist (in inputs)
          (let* ((args (read in))
                 (r0 (zeln-diff--apply baseline args bind baseline))
                 (r1 (zeln-diff--apply native args bind native)))
            (setq zeln-diff--n (1+ zeln-diff--n))
            (unless (equal r0 r1)
              (setq fn-failed (1+ fn-failed))
              (message "zeln-diff MISMATCH: %s input=%S\n  baseline=%S\n  native =%S"
                       name args r0 r1))))
        (if (zerop fn-failed)
            (setq n-fns (1+ n-fns))
          (push (cons name fn-failed) zeln-diff--fails))))
    (if (null zeln-diff--fails)
        (message "M1 differential: %d/%d functions identical (%d/%d calls)"
                 n-fns n-fns zeln-diff--n zeln-diff--n)
      (message "M1 differential: FAILED %d function(s), %d/%d calls ok"
               (length zeln-diff--fails) (- zeln-diff--n
                                            (apply #'+ (mapcar #'cdr zeln-diff--fails)))
               zeln-diff--n)
      (kill-emacs 1))))

;;; zeln-diff.el ends here
