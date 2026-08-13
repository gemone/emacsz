;;; zeln-pgo.el --- Multi-fixture PGO closed-loop test (Zig native-comp path)  -*- lexical-binding: t; -*-
;; The Z7 PGO gate: the Z5 auto-FDO loop (build -> instrument -> load ->
;; hammer -> GC -> profile recompile -> hot-swap -> --final) run over a
;; CORPUS of workload-shaped fixtures instead of a single hot/cold pair.
;; Each fixture exercises a different code-shape class, so a regression in
;; profile collection, hot-first reordering, or hot-swap behavior that a
;; single loop fixture would miss shows up as a per-fixture FAIL.
;;
;; Fixture corpus (each = (NAME HOT-BODY COLD-BODY HAMMER-ARG EXPECTED)):
;;   loop-arith   - dispatch-bound loop (the classic Z5 shape)
;;   fib-rec      - recursion (hot fn calls itself via symbol)
;;   bignum-ovf   - fixnum overflow -> bignum (exercises the freloc
;;                  fallback counters + inline fallback block)
;;   list-ops     - cons/cdr list construction (alloc-heavy)
;;   dense-arith  - no loop, dense arith ops (freloc+Fprimitive cost,
;;                  no dispatch amortization)
;;   branchy      - hot loop with a hot/cold branch pair (branch weights)
;;
;; For each fixture the harness runs the FULL closed loop:
;;   1. byte-compile a 2-defun fixture .elc, serialize it to a zabi=3
;;      zunit, compile to an instrumented .zeln via ZELN_COMPILE;
;;   2. load it with zeln-auto-fdo-path / -profile / -interval set
;;      (tiny interval, per-fixture threshold);
;;   3. reverse check: GC with counters at 0 -> NO profile written
;;      (the loader must not write a profile below the hot threshold);
;;   4. hammer the HOT fn (call counter climbs past the threshold);
;;   5. GC -> zeln_fdo_gc_check flushes the profile, recompiles with
;;      --profile (round 1), hot-swaps the subr in place; assert the
;;      hot fn still returns the expected result after THIS swap;
;;   6. hammer again + GC -> round 2 recompiles with --profile --final
;;      (counters dropped) and hot-swaps again;
;;   7. assert per fixture: profile file written, the hot fn still
;;      returns the expected result after the FINAL swap (behavioral
;;      identity after BOTH swaps), the final .zeln is hot-first, its
;;      inline fast-path branches carry the real `!prof` branch
;;      weights from the profile (calls-vs-fallbacks), and its
;;      counters are dropped (--final).
;;
;; Speed: the hammer count is parameterized via the ZELN_PGO_HAMMER env
;; var (default 150000 calls per round).  CI and quick local checks can
;; set it lower (e.g. 30000); the per-fixture threshold scales with it.
;;
;; Exits 0 on success, non-zero on any failure.  The zeln-compile tool
;; is located via the ZELN_COMPILE env var (set by the build step),
;; defaulting to a .zig-cache probe like zeln-diff-multifn.

(defconst zeln-pgo-hammer
  (let ((raw (getenv "ZELN_PGO_HAMMER")))
    (if (and raw (> (length raw) 0))
        (string-to-number raw)
      150000))
  "Hammer calls per round per fixture (ZELN_PGO_HAMMER, default 150000).")

(defconst zeln-pgo-threshold-ratio 3
  "Hot threshold = hammer-count / this ratio, so a shorter hammer run
still reliably trips the profile threshold.")

;; Each fixture: (NAME HOT-BODY COLD-BODY HAMMER-ARG EXPECTED).
;; The defuns are emitted as (defun zeln-pgo-NAME-hot (n) BODY) and
;; (defun zeln-pgo-NAME-cold (n) BODY); the harness hammers the hot one.
;; EXPECTED is the hot fn's value at HAMMER-ARG.
(defconst zeln-pgo-fixtures
  '((loop-arith
     ";; dispatch-bound loop
      (let ((s 0) (i 0))
        (while (< i n)
          (setq s (+ s i))
          (setq i (1+ i)))
        s)"
     "(* n 2)"
     1000 499500)
    (fib-rec
     ";; recursion: hot fn recurses through its own symbol
      (if (< n 2) n (+ (zeln-pgo-fib-rec-hot (1- n))
                       (zeln-pgo-fib-rec-hot (- n 2))))"
     "(if (= n 0) 1 (* n (zeln-pgo-fib-rec-cold (1- n))))"
     20 6765)
    (bignum-ovf
     ";; every addend overflows fixnum -> bignum fallback block
      (let ((s 0) (i 0))
        (while (< i n)
          (setq s (+ s 2305843009213693951))
          (setq i (1+ i)))
        s)"
     "(* n 2)"
     200 461168601842738790200)
    (list-ops
     ";; alloc-heavy cons loop
      (let ((l nil) (i 0))
        (while (< i n)
          (setq l (cons i l))
          (setq i (1+ i)))
        (length l))"
     "(* n 2)"
     500 500)
    (dense-arith
     ";; no loop: 3 arith ops per call, freloc+Fprimitive exposed
      (+ (* n n) (- n 2))"
     "(* n 2)"
     3 10)
    (branchy
     ";; hot loop with an inner hot/cold branch pair
      (let ((c 0) (i 0))
        (while (< i n)
          (when (> i 0)
            (setq c (+ c 1)))
          (setq i (+ i 1)))
        c)"
     "(* n 2)"
     1000 999))
  "The PGO fixture corpus: (NAME HOT-BODY COLD-BODY HAMMER-ARG EXPECTED).")

(defun zeln-pgo--locate-zc ()
  "Return the zeln-compile path, or nil if not found."
  ;; call-process resolves the program via exec-path, not cwd: expand a
  ;; relative ZELN_COMPILE (e.g. zig-out/bin/zeln-compile from the build
  ;; step) against the invocation directory.
  (let ((raw (or (getenv "ZELN_COMPILE")
                 (car (directory-files-recursively
                       (expand-file-name ".zig-cache")
                       "^zeln-compile$" nil)))))
    (and raw (expand-file-name raw))))

(defun zeln-pgo--assert (name ok msg)
  "Print the outcome (prefixed by fixture NAME for CI log grepping)
and return 0 if OK, 1 if FAIL — a count directly addable to the
fixture's failure tally."
  (if ok
      (progn (message "  zeln-pgo[%s]: ok: %s" name msg) 0)
    (progn (message "  zeln-pgo[%s]: FAIL: %s" name msg) 1)))

(defun zeln-pgo--profile-written-p (name fdo-dir)
  "Non-nil if a .zprofile for fixture NAME exists under FDO-DIR.
Profiles accumulate across fixtures in the shared FDO dir, so the
match is by fixture name (names are pairwise disjoint)."
  (let ((profs (directory-files fdo-dir t "\\.zprofile\\'")))
    (and profs
         (catch 'found
           (dolist (p profs nil)
             (when (string-match-p (regexp-quote name) p)
               (throw 'found t)))))))

(defun zeln-pgo--run-fixture (name hot-body cold-body
                              hammer-arg expected
                              zc dir)
  "Run the full PGO closed loop for one fixture.  Returns the number
of assertions that failed."
  (let* ((fdo-dir (expand-file-name "cache" dir))
         (elfile (expand-file-name (concat name ".el") dir))
         (elcfile (expand-file-name (concat name ".elc") dir))
         (prefix (expand-file-name name dir))
         (zelnfile (expand-file-name (concat name ".zeln") dir))
         (hot-sym (intern (format "zeln-pgo-%s-hot" name)))
         (threshold (max 100 (/ zeln-pgo-hammer zeln-pgo-threshold-ratio)))
         (zeln-pgo--abort nil)
         (fails 0))
    (message "zeln-pgo[%s]: building fixture (hammer=%d threshold=%d)"
             name zeln-pgo-hammer threshold)
    (make-directory fdo-dir t)
    (let ((lexical-binding t))
      (with-temp-file elfile
        (insert (format
                 ";;; %s.el --- pgo fixture  -*- lexical-binding: t; -*-\n\n"
                 name)
                (format "(defun zeln-pgo-%s-hot (n) %s)\n" name hot-body)
                (format "(defun zeln-pgo-%s-cold (n) %s)\n" name cold-body)
                (format "\n;;; %s.el ends here\n" name))))
    (byte-compile-file elfile)
    (let ((nfuncs (comp-z-write-file-zunit elcfile prefix)))
      (unless (and (integerp nfuncs) (= nfuncs 2))
        (message "zeln-pgo[%s]: expected 2 defuns, got %S" name nfuncs)
        (setq fails (1+ fails))
        (setq zeln-pgo--abort t)))
    (unless zeln-pgo--abort
      (let ((rc (call-process zc nil (list zelnfile) nil
                              (concat prefix ".zunit")
                              (concat prefix ".manifest")
                              zelnfile)))
        (unless (and (numberp rc) (= rc 0))
          (message "zeln-pgo[%s]: zeln-compile exit %S" name rc)
          (setq fails (1+ fails))
          (setq zeln-pgo--abort t))))
    (unless zeln-pgo--abort
      ;; The instrumented .zeln must carry the fdo counter gate.
      (let ((ll (with-temp-buffer
                  (insert-file-contents (concat zelnfile ".ll"))
                  (buffer-string))))
        (unless (string-match-p "zeln_fdo_active" ll)
          (message "zeln-pgo[%s]: instrumented .zeln lacks fdo_active" name)
          (setq fails (1+ fails)))))

      ;; ---- Load with auto-FDO configured. ----
      (setq zeln-auto-fdo-path fdo-dir
            zeln-auto-fdo-profile threshold
            zeln-auto-fdo-interval 0.0)
      (comp-z-load-zeln zelnfile)

      ;; ---- Reverse check: counters at 0 must NOT write a profile. ----
      (garbage-collect)
      (setq fails
            (+ fails
               (zeln-pgo--assert
                name
                (not (zeln-pgo--profile-written-p name fdo-dir))
                (format "%s no profile below threshold (reverse check)" name))))

      ;; ---- Round 1: hammer + GC -> profile + recompile + hot-swap. ----
      (dotimes (_ zeln-pgo-hammer)
        (funcall hot-sym hammer-arg))
      (garbage-collect)
      (setq fails
            (+ fails
               (zeln-pgo--assert
                name
                (zeln-pgo--profile-written-p name fdo-dir)
                (format "profile written for %s" name))))
      (setq fails
            (+ fails
               (zeln-pgo--assert
                name
                (equal (funcall hot-sym hammer-arg) expected)
                (format "%s identity after round-1 swap: got %S want %S"
                        name (funcall hot-sym hammer-arg) expected))))

      ;; ---- Round 2: hammer + GC -> --final recompile + hot-swap. ----
      (dotimes (_ zeln-pgo-hammer)
        (funcall hot-sym hammer-arg))
      (garbage-collect)
      (setq fails
            (+ fails
               (zeln-pgo--assert
                name
                (equal (funcall hot-sym hammer-arg) expected)
                (format "%s identity after final swap: got %S want %S"
                        name (funcall hot-sym hammer-arg) expected))))

      ;; ---- Artifact assertions on the final (round-2) .zeln. ----
      (let ((cache-zeln (expand-file-name (concat name ".zeln") fdo-dir))
            (cache-ll (expand-file-name (concat name ".zeln.ll") fdo-dir)))
        (if (not (file-exists-p cache-ll))
            (progn
              (message "  zeln-pgo[%s]: FAIL: recompiled .ll not under fdo path"
                       name)
              (setq fails (1+ fails)))
          (let ((ll (with-temp-buffer
                      (insert-file-contents cache-ll)
                      (buffer-string))))
            (let ((hot-pos (string-match (format "zeln-pgo-%s-hot" name) ll))
                  (cold-pos (string-match (format "zeln-pgo-%s-cold" name) ll)))
              (setq fails
                    (+ fails
                       (zeln-pgo--assert
                        name
                        (and hot-pos cold-pos (<= hot-pos cold-pos))
                        (format "%s recompiled .zeln hot-first" name)))))
            (setq fails
                  (+ fails
                     (zeln-pgo--assert
                      name
                      (not (string-match-p "bb_fdo_" ll))
                      (format "%s final .zeln counters dropped" name))))
            (setq fails
                  (+ fails
                     (zeln-pgo--assert
                      name
                      (string-match-p "branch_weights" ll)
                      (format "%s final .zeln carries !prof branch weights"
                               name))))))
          (setq fails
                (+ fails
                   (zeln-pgo--assert
                    name
                    (file-exists-p cache-zeln)
                    (format "recompiled .zeln for %s"                        name)))))
    fails))

(defun zeln-pgo-run ()
  "Run the multi-fixture PGO closed-loop harness."
  (unless (fboundp 'comp-z-write-file-zunit)
    (message "zeln-pgo: build without -Dnative-comp-zig=true")
    (kill-emacs 1))
  (unless (boundp 'zeln-auto-fdo-path)
    (message "zeln-pgo: zeln-auto-fdo-path not defined (old build?)")
    (kill-emacs 1))
  (let ((zc (zeln-pgo--locate-zc))
        (dir (make-temp-file "zeln-pgo-" t))
        (fails 0))
    (unwind-protect
        (progn
          (unless (and zc (file-executable-p zc))
            (message "zeln-pgo: zeln-compile not found (set ZELN_COMPILE)")
            (kill-emacs 1))
          (dolist (fixture zeln-pgo-fixtures)
            (let ((name (symbol-name (nth 0 fixture)))
                  (hot (nth 1 fixture))
                  (cold (nth 2 fixture))
                  (harg (nth 3 fixture))
                  (expected (nth 4 fixture)))
              (setq fails
                    (+ fails
                       (zeln-pgo--run-fixture
                        name hot cold harg expected zc dir)))))
          (if (zerop fails)
              (message "zeln-pgo: PASS (%d fixtures, all green)"
                       (length zeln-pgo-fixtures))
            (message "zeln-pgo: FAILED (%d assertion(s) across %d fixtures)"
                     fails (length zeln-pgo-fixtures))
            (kill-emacs 1)))
      (delete-directory dir t))))
