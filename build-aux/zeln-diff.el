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

;; Each entry: (NAME FORM INPUTS BIND [HELPERS])
;;   NAME    symbol naming the fn (-> <dir>/<name>.zunit etc.)
;;   FORM    the lambda form to byte-compile (the reference closure), OR a
;;           symbol whose `symbol-function' is an already-compiled closure
;;   INPUTS  list of strings; each is an Elisp list of args to `apply'
;;   BIND    nil, or a symbol whose function slot is fset to the closure
;;           under test before each call (for self-recursive fns whose
;;           recursive call resolves through the symbol's function slot).
;;   HELPERS optional alist of (SYM . LAMBDA-FORM); each is byte-compiled
;;           and fset to SYM before the entry runs, so the fn under test
;;           can funcall a separately-compiled closure (e.g. a thrower
;;           that crosses a native catch frame).  (nth 4 entry) -> nil.
;;
;; Edge cases the corpus MUST include (plan M1 DIFF TEST): fixnum-overflow
;; (-> bignum), &rest args, nil/empty-list, nested recursion, backward-
;; branch loops (stack-depth-at-loop-header), constant indices >=64
;; (Bconstant2), and a fn with >5 args (Bcall6/Bcall7 FETCH2).
;;
;; M2 coverage (plan M2): the appended entries exercise every new opcode
;; group — dynamic var bind/set/ref/unbind, save-excursion/restriction/
;; current-buffer, unwind-protect (normal + error paths), condition-case
;; catching a signaled error, catch/throw (same-frame AND cross-frame via
;; a helper), aref/aset/substring/concat, the list primitives, and the
;; buffer/point primitive families.  Any fn whose bytecode leaves the
;; supported subset is REJECTed by the emitter at compile time (failing
;; the build), so coverage is honestly bounded to proven fns.
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
     nil)
    ;; ===== M2: real constructs, one+ fn per new opcode group. =====
    ;; (a) dynamic special-var let -> Bvarbind / Bvarset / Bvarref / Bunbind.
    (dynvar
     (lambda (x)
       (let ((inhibit-read-only t))
         (setq case-fold-search nil)
         (cons x inhibit-read-only)))
     ("(3)" "(0)")
     nil nil)
    ;; (b1) Bsave_excursion + Bgoto_char + Binsert + Bpoint + Bbuffer_substring.
    (saveex
     (lambda ()
       (with-temp-buffer
         (insert "hello")
         (save-excursion
           (goto-char 2)
           (point))
         (cons (point) (buffer-substring 1 4))))
     ("()") nil nil)
    ;; (b2) Bsave_restriction + Bnarrow_to_region + Bpoint_min/max.
    (saverest
     (lambda ()
       (with-temp-buffer
         (insert "abcdef")
         (save-restriction
           (narrow-to-region 2 5)
           (cons (point-min) (point-max)))
         (point-max)))
     ("()") nil nil)
    ;; (b3) Bsave_current_buffer + Bset_buffer (point-max is deterministic).
    (savebuf
     (lambda ()
       (with-temp-buffer
         (insert "abc")
         (save-current-buffer (set-buffer (other-buffer)))
         (point-max)))
     ("()") nil nil)
    ;; (c) Bunwind_protect cleanup runs on BOTH normal and error paths.
    (unwind
     (lambda (x)
       (let ((flag 'clean))
         (unwind-protect
             (if x (error "boom") 'ok)
           (setq flag 'ran))
         flag))
     ("(nil)" "(t)") nil nil)
    ;; (d1) Bpushconditioncase catching args-out-of-range signaled by Baref.
    (condcase
     (lambda (vec)
       (condition-case err
           (aref vec 10)
         (args-out-of-range (cdr err))))
     ("([1 2 3])" "(\"ab\")") nil nil)
    ;; (d2) Bpushcatch + throw landing in the SAME native frame.
    (catchself
     (lambda (x)
       (catch 'done
         (if x (throw 'done 'caught) 'not-thrown)))
     ("(nil)" "(t)") nil nil)
    ;; (d3) Bpushcatch + throw originating in a CALLED closure (cross-frame).
    (catchcross
     (lambda ()
       (catch 'done
         (zeln-diff-thrower)      ; fset to a compiled thrower by HELPERS
         'not-thrown))
     ("()") nil
     ((zeln-diff-thrower . (lambda () (throw 'done 'cross-caught)))))
    ;; (e1) Baref / Bsubstring.
    (vecstr
     (lambda (v s)
       (cons (aref v 1) (substring s 0 2)))
     ("([10 20 30] \"hello\")" "(\"abc\" \"xyz\")") nil nil)
    ;; (e2) Baset.
    (asetop
     (lambda (v)
       (aset v 0 99)
       (aref v 0))
     ("([1 2 3])") nil nil)
    ;; (e3) Bconcat3 / BconcatN.
    (concatn
     (lambda (a b c d e)
       (concat (concat a b c) (concat a b c d e)))
     ("(\"a\" \"b\" \"c\" \"d\" \"e\")") nil nil)
    ;; (f1) Bnth / Bnthcdr / Bmember / Bassq / Blength / BlistN.
    (listops
     (lambda (lst)
       (list (nth 1 lst) (nthcdr 2 lst)
             (member 3 lst) (assq 'a lst) (length lst)))
     ("((1 2 3 4))" "((a . 1) (b . 2))") nil nil)
    ;; (f2) Bnreverse / Bsetcar / Bcar_safe / Bcdr_safe.
    (consmut
     (lambda (lst)
       (let ((c (nreverse (copy-sequence lst))))
         (setcar c 99)
         (cons (car-safe c) (cdr-safe c))))
     ("((1 2 3))") nil nil)
    ;; (f3) Bnconc / Bsetcdr.
    (nconcop
     (lambda (lst)
       (let ((x (nconc (copy-sequence lst) '(9))))
         (setcdr x 7)
         x))
     ("((1 2))") nil nil)
    ;; (g1) buffer range primitives in a temp buffer.
    (bufrange
     (lambda ()
       (with-temp-buffer
         (insert "ab\nc")
         (goto-char 2)
         (list (point) (point-min) (point-max)
               (following-char) (preceding-char)
               (char-after (point)) (current-column))))
     ("()") nil nil)
    ;; (g2) buffer movement: Bforward_line, Bbuffer_substring, Bend_of_line,
    ;; Bskip_chars_forward, Bdelete_region.
    (bufmove
     (lambda ()
       (with-temp-buffer
         (insert "hello\nworld")
         (goto-char 1)
         (forward-line 1)            ; point -> 6 (start of "world")
         (prog1 (buffer-substring 1 5)   ; "hell"
           (end-of-line)             ; point -> 11
           (skip-chars-forward "wo") ; point -> 8
           (delete-region 6 8))))    ; delete "wo" -> "hello\nrld"
     ("()") nil nil)
    ;; (g3) Bmatch_beginning/end + Bchar_syntax after a (funcall) re-search.
    (matchops
     (lambda ()
       (with-temp-buffer
         (insert "(foo)")
         (goto-char 1)
         (if (re-search-forward "[a-z]+" nil t)
             (list (match-beginning 0) (match-end 0)
                   (char-syntax (char-after 2)))
           'no-match)))
     ("()") nil nil)
    ;; (g4) Bstring= / Bstring-lessp / Bupcase / Bdowncase.
    (strcase
     (lambda (a b)
       (list (string-equal a b) (string-lessp a b)
             (upcase a) (downcase b)))
     ("(\"abc\" \"abd\")" "(\"xyz\" \"abc\")") nil nil)
    ;; (g5) Bquo / Brem.
    (arith2
     (lambda (x y)
       (list (/ x y) (% x y)))
     ("(20 6)" "(100 7)") nil nil)
    ;; (g6) Bset / Bsymbol_value / Bget (self-contained, value cell).
    (symfns
     (lambda ()
       (set 'zeln-diff-vg 7)
       (cons (symbol-value 'zeln-diff-vg)
             (get 'zeln-diff-vg 'zeln-diff-prop)))
     ("()") nil nil)
    ;; (g7) Bfset / Bsymbol_function (function cell, returns 5).
    (fnsym
     (lambda ()
       (fset 'zeln-diff-fs (lambda (x) x))
       (funcall (symbol-function 'zeln-diff-fs) 5))
     ("()") nil nil)
    ;; (g8) Bset_marker (3-ary) + marker ops.
    (markerop
     (lambda ()
       (with-temp-buffer
         (let ((m (make-marker)))
           (set-marker m 3 (current-buffer))
           (set-marker m 5 (current-buffer))
           (marker-position m))))
     ("()") nil nil)
    ;; (g9) Beolp/Beobp/Bbolp/Bbobp + Bskip_chars_backward + Bwiden
    ;; (the remaining 0-arg PUSH predicates + skip-backward + widen).
    (bufpred
     (lambda ()
       (with-temp-buffer
         (insert "line1\nline2")
         (goto-char 1)
         (prog1
             (list (bolp) (eolp) (bobp) (eobp))
           (skip-chars-backward "l")
           (widen))))
     ("()") nil nil))
  "The differential-test corpus (M1 edges + M2 opcode-group coverage).
See plan M1 DIFF TEST and M2 for the edges/groups.  Any fn whose
bytecode leaves the supported opcode subset is REJECTed by the emitter.")

(defun zeln-diff-byte-compile (form)
  "Byte-compile FORM under `lexical-binding' so it yields a real lexical
closure (CLOSUREP with a fixnum args-template), the exact shape
`comp-z-write-zunit' accepts and `exec_byte_code' consumes."
  (let ((lexical-binding t))
    (byte-compile form)))

(defun zeln-diff-closure (form)
  "Resolve a corpus FORM into the closure to test.
FORM is either a lambda form (byte-compiled here) or a symbol whose
`symbol-function' is an already-compiled closure (real built-in fn)."
  (if (symbolp form)
      (symbol-function form)
    (zeln-diff-byte-compile form)))

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
           (closure (zeln-diff-closure form)))
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
             (helpers (nth 4 entry))
             ;; Byte-compile + fset any helpers so the fn under test can
             ;; funcall a separately-compiled closure (e.g. a thrower).
             ;; Done once here; both baseline and native runs see the same
             ;; helper closures (the helpers are NOT the fn under test).
             (baseline (progn
                         (dolist (h helpers)
                           (fset (car h) (zeln-diff-byte-compile (cdr h))))
                         (zeln-diff-closure form)))
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
        (message "zeln differential: %d/%d functions identical (%d/%d calls)"
                 n-fns (length zeln-diff-corpus) zeln-diff--n zeln-diff--n)
      (message "zeln differential: FAILED %d function(s), %d/%d calls ok"
               (length zeln-diff--fails) (- zeln-diff--n
                                            (apply #'+ (mapcar #'cdr zeln-diff--fails)))
               zeln-diff--n)
      (kill-emacs 1))))

;;; zeln-diff.el ends here
