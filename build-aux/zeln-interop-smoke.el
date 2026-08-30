;;; zeln-interop-smoke.el --- eln/zeln transparent selection gate -*- lexical-binding: t; -*-

;; Compile one fixture with both backends, then launch clean batch children
;; with each preference value.  The child's loaded native-comp unit must be
;; chosen exactly by `native-comp-z-prefer' (nil=.eln, t=.zeln).

(require 'comp)
(require 'zeln-run)

(defvar zeln-interop-smoke-zc nil
  "Path to zeln-compile, supplied by the build step.")

(defvar zeln-interop-smoke-emacs nil
  "Path to the Emacs wrapper, supplied by the build step.")

(defun zeln-interop-smoke--emacs ()
  "Return the batch Emacs executable used for clean preference probes."
  (expand-file-name
   (or zeln-interop-smoke-emacs
       (concat invocation-directory invocation-name))))

(defun zeln-interop-smoke--suffix ()
  "Compile fixture artifacts and verify both .eln/.zeln selection orders."
  (unless (and (fboundp 'comp-z-write-file-zunit)
               (native-comp-available-p))
    (error "combined eln+zeln support is unavailable"))
  (setq zeln-interop-smoke-zc
        (expand-file-name (or (getenv "ZELN_COMPILE") "zeln-compile"))
        zeln-interop-smoke-emacs (getenv "ZELN_EMACS"))
  (let* ((dir (make-temp-file "zeln-interop-smoke-" t))
         (eln-root (expand-file-name "eln" dir))
         (zeln-root (expand-file-name "zeln" dir))
         (source (expand-file-name "fixture.el" dir))
         (fixture
          (concat ";;; -*- lexical-binding: t; -*-\n"
                  "(defvar zeln-interop-smoke--loaded t)\n"
                  "(defun zeln-interop-smoke--fn (n) (* n 2))\n"
                  "(provide 'zeln-interop-smoke-fixture)\n"))
         expected
         (got nil))
    (unwind-protect
        (progn
          (with-temp-file source (insert fixture))
          (unless (zerop (call-process (zeln-interop-smoke--emacs) nil t nil
                                       "--batch" "-L" "." "-f"
                                       "batch-byte-compile" source))
            (error "fixture byte-compile failed"))
          (let* ((native-comp-eln-load-path (list eln-root))
                 (native-comp-zeln-load-path (list zeln-root))
                 (zeln-compile-executable zeln-interop-smoke-zc)
                 (eln (native-compile source))
                 (zeln (zeln-compile-file source)))
            (unless (and (stringp eln) (file-exists-p eln)
                         (string-suffix-p ".eln" eln))
              (error "eln fixture missing: %S" eln))
            (unless (and (stringp zeln) (file-exists-p zeln)
                         (string-suffix-p ".zeln" zeln))
              (error "zeln fixture missing: %S" zeln))
            (setq expected zeln)
            (set-file-times source)
            (set-file-times (concat source "c"))
            ;; The loader's native-artifact freshness gate compares each
            ;; native file against the .elc.  Resetting the bytecode above
            ;; would otherwise make both freshly compiled artifacts look
            ;; stale, so normalize their clocks too.
            (set-file-times eln)
            (set-file-times zeln)
            ;; `file-name-extension' does not include the delimiter.
            (dolist (probe '((nil . "eln") (t . "zeln")))
              (let* ((pref (car probe))
                     (want (cdr probe))
                     (child-source
                      (expand-file-name
                       (concat "probe-" (if pref "zeln" "eln") ".el") dir))
                     (child
                      (concat
                       ";;; -*- lexical-binding: t; -*-\n"
                       (prin1-to-string
                        `(progn
                          (setq native-comp-z-prefer
                                ,(if pref t nil))
                          (setq native-comp-eln-load-path
                                (list ,eln-root))
                          (setq native-comp-zeln-load-path
                                (list ,zeln-root))
                          ;; Deliberately omit the suffix: this goes through
                          ;; the same openp .elc selection path as ordinary
                          ;; `load' calls, where native artifacts replace it.
                          (load (file-name-sans-extension ,source) nil t)
                          (let* ((f (symbol-function
                                     'zeln-interop-smoke--fn))
                                 (cu (subr-native-comp-unit f)))
                            (unless (and (native-comp-function-p f) cu)
                              (error "fixture did not load native code"))
                            (princ (file-name-extension
                                    (native-comp-unit-file cu))))))))
                     (output (generate-new-buffer " *zeln-interop-probe*")))
                (with-temp-file child-source (insert child))
                (unwind-protect
                    (progn
                      (unless (zerop (call-process
                                            (zeln-interop-smoke--emacs)
                                            nil output nil "--batch"
                                            "-l" child-source))
                        (error "preference probe failed (%S): %s"
                               pref (with-current-buffer output
                                      (buffer-string))))
                      (with-current-buffer output
                        (setq got (string-trim (buffer-string)))))
                  (kill-buffer output))
                (unless (equal got want)
                  (error "preference %S loaded %s, wanted %s"
                         pref got want))))
            expected))
      (ignore-errors (delete-directory dir t)))))

(defun zeln-interop-smoke-run ()
  "Run the end-to-end combined native artifact selection gate."
  (let ((suffix (zeln-interop-smoke--suffix)))
    (unless (equal (file-name-extension suffix) "zeln")
      (error "zeln-interop-smoke: unexpected final suffix %S" suffix))
    (message "zeln-interop-smoke: PASS")))

(provide 'zeln-interop-smoke)
;;; zeln-interop-smoke.el ends here
