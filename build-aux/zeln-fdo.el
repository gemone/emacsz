;;; zeln-fdo.el --- Auto-FDO loop harness (Zig native-comp path)  -*- lexical-binding: t; -*-

;; The Z5 auto profile-guided recompilation gate.  Exercises the full
;; closed loop end-to-end on a SIMULATED .zeln:
;;
;;   1. build a small multi-fn .elc (one hot loop fn + one cold fn),
;;      serialize it to a zabi=3 zunit (comp-z-write-file-zunit),
;;      compile to a .zeln via the ZELN_COMPILE tool;
;;   2. load it with zeln-auto-fdo-path / zeln-auto-fdo-profile /
;;      zeln-auto-fdo-interval set (tiny interval, low threshold) so the
;;      loader registers the unit and flips its fdo_active flag;
;;   3. hammer the hot fn (counter climbs past the threshold);
;;   4. force GC -> zeln_fdo_gc_check flushes the profile, recompiles
;;      with --profile (round 1), hot-swaps the subr in place;
;;   5. hammer again + GC -> round 2 recompiles with --profile --final
;;      (counters dropped) and hot-swaps again;
;;   6. assert: profile file written under the fdo path, the hot fn
;;      still returns correct results after BOTH swaps (behavioral
;;      identity), the final .zeln has the hot-first layout.
;;
;; Exits 0 on success, non-zero on any failure.  The zeln-compile tool
;; is located via the ZELN_COMPILE env var (set by the build step),
;; defaulting to a .zig-cache probe like zeln-diff-multifn.

(defun zeln-fdo-run ()
  "Run the auto-FDO loop harness on a simulated .zeln."
  (unless (fboundp 'comp-z-write-file-zunit)
    (message "zeln-fdo: build without -Dnative-comp-zig=true")
    (kill-emacs 1))
  (unless (boundp 'zeln-auto-fdo-path)
    (message "zeln-fdo: zeln-auto-fdo-path not defined (old build?)")
    (kill-emacs 1))
  (let* ((dir (make-temp-file "zeln-fdo-" t))
         (fdo-dir (expand-file-name "cache" dir))
         (elfile (expand-file-name "fdo.el" dir))
         (elcfile (expand-file-name "fdo.elc" dir))
         (prefix (expand-file-name "fdo" dir))
         (zelnfile (expand-file-name "fdo.zeln" dir))
         (zc (let ((raw (or (getenv "ZELN_COMPILE")
                           (car (directory-files-recursively
                                 (expand-file-name ".zig-cache")
                                 "^zeln-compile$" nil)))))
               ;; call-process resolves the program via exec-path, not cwd:
               ;; expand a relative ZELN_COMPILE (e.g. zig-out/bin/zeln-compile
               ;; from the build step) against the invocation directory.
               (and raw (expand-file-name raw))))
         (fails 0))
    (unwind-protect
        (progn
          (unless (and zc (file-executable-p zc))
            (message "zeln-fdo: zeln-compile not found (set ZELN_COMPILE)")
            (kill-emacs 1))
          (make-directory fdo-dir t)
          ;; ---- 1. Build + serialize + compile a 2-fn .zeln. ----
          (let ((lexical-binding t))
            (with-temp-file elfile
              (insert ";;; fdo.el --- fdo fixture  -*- lexical-binding: t; -*-\n\n"
                      "(defun zeln-fdo-hot (n)\n"
                      "  (let ((s 0) (i 0))\n"
                      "    (while (< i n)\n"
                      "      (setq s (+ s i))\n"
                      "      (setq i (1+ i)))\n"
                      "    s))\n"
                      "(defun zeln-fdo-cold (n) (* n 2))\n"
                      "\n;;; fdo.el ends here\n"))
            (byte-compile-file elfile))
          (let ((nfuncs (comp-z-write-file-zunit elcfile prefix)))
            (unless (and (integerp nfuncs) (= nfuncs 2))
              (message "zeln-fdo: expected 2 defuns, got %S" nfuncs)
              (kill-emacs 1)))
          (let ((rc (call-process zc nil (list zelnfile) nil
                                  (concat prefix ".zunit")
                                  (concat prefix ".manifest")
                                  zelnfile)))
            (unless (and (numberp rc) (= rc 0))
              (message "zeln-fdo: zeln-compile exit %S" rc)
              (kill-emacs 1)))
          ;; Sanity: the instrumented .zeln carries a counter block.
          (unless (file-exists-p (concat zelnfile ".ll"))
            (message "zeln-fdo: no sibling .ll (zeln-compile wrote nothing?)")
            (kill-emacs 1))
          (let ((ll (with-temp-buffer
                      (insert-file-contents (concat zelnfile ".ll"))
                      (buffer-string))))
            (unless (string-match-p "zeln_fdo_active" ll)
              (message "zeln-fdo: instrumented .zeln lacks fdo_active (counter gate)")
              (setq fails (1+ fails))))

          ;; ---- 2. Load with auto-FDO configured. ----
          (setq zeln-auto-fdo-path fdo-dir
                zeln-auto-fdo-profile 50000
                zeln-auto-fdo-interval 0.0)
          (comp-z-load-zeln zelnfile)

          ;; ---- 3. Hammer the hot fn (last fset subr is zeln-fdo-cold;
          ;; call the HOT one by symbol for a fair loop). ----
          (dotimes (_ 200000)
            (zeln-fdo-hot 1000))

          ;; ---- 4. GC -> flush + recompile round 1 + hot-swap. ----
          (garbage-collect)

          ;; ---- 5. Hammer again + GC -> round 2 (--final) + swap. ----
          (dotimes (_ 200000)
            (zeln-fdo-hot 1000))
          (garbage-collect)

          ;; ---- 6. Assertions. ----
          ;; The recompiled (PGO) artifact lives under the FDO path, not
          ;; the original zelnfile (which stays the instrumented unit).
          (let ((cache-zeln (expand-file-name "fdo.zeln" fdo-dir))
                (cache-ll (expand-file-name "fdo.zeln.ll" fdo-dir)))
            ;; (a) profile file written under the fdo path.
            (let ((profs (directory-files fdo-dir t "\\.zprofile\\'")))
              (if profs
                  (message "zeln-fdo: profile written: %s"
                           (mapconcat #'file-name-nondirectory profs ", "))
                (message "zeln-fdo: NO profile file written (collection inactive?)")
                (setq fails (1+ fails))))
            ;; (b) the recompiled .zeln exists and has the hot-first layout:
            ;; zeln-fdo-hot (the hot fn) must be at fn-table slot 0.
            (if (not (file-exists-p cache-ll))
                (progn
                  (message "zeln-fdo: no recompiled .ll under fdo path (recompile didn't run?)")
                  (setq fails (1+ fails)))
              (let ((ll (with-temp-buffer
                          (insert-file-contents cache-ll)
                          (buffer-string))))
                (let ((hot-pos (string-match "zeln-fdo-hot" ll))
                      (cold-pos (string-match "zeln-fdo-cold" ll)))
                  (when (and hot-pos cold-pos (> hot-pos cold-pos))
                    (message "zeln-fdo: recompiled .zeln NOT hot-first (hot fn not at index 0)")
                    (setq fails (1+ fails))))
                ;; (c) the final round drops the counters (--final).
                (when (string-match-p "bb_fdo_" ll)
                  (message "zeln-fdo: final .zeln still has counter blocks (--final not applied)")
                  (setq fails (1+ fails))))
              (unless (file-exists-p cache-zeln)
                (message "zeln-fdo: no recompiled .zeln under fdo path")
                (setq fails (1+ fails)))))
          ;; (d) behavioral identity after both hot-swaps.
          (let ((got (zeln-fdo-hot 1000)))
            (if (= got 499500)
                (message "zeln-fdo: hot fn result after swaps: %d OK" got)
              (message "zeln-fdo: MISMATCH after hot-swap: got %d want 499500" got)
              (setq fails (1+ fails))))
          (if (zerop fails)
              (message "zeln-fdo: PASS (auto-collect + recompile + hot-swap + stop)")
            (message "zeln-fdo: FAILED (%d assertion(s))" fails)
            (kill-emacs 1)))
      (delete-directory dir t))))
