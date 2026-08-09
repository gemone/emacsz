;;; zeln-populate.el --- walk lisp/**/*.elc, serialize zabi=3 zunits. -*- lexical-binding: t; -*-

;; The serialize half of the M2b cache-population step (plan M2b
;; deliverable 1).  Runs in the dumped emacs (built with
;; -Dnative-comp-zig=true).  For each lisp/**/*.elc:
;;   - derive the .el source (strip 'c', fallback .gz); skip if absent
;;     (no content_hash possible, matching maybe_swap_for_zeln);
;;   - compute the .zeln rel-filename via `comp-z-el-to-zeln-rel-filename'
;;     (the SAME call the load side uses, so write/read agree);
;;   - call `comp-z-write-file-zunit' (src/compz.c) which Floads the .elc
;;     with a capturing reader, walks its defun closures + collects its
;;     non-defun top-level forms, and writes one zabi=3 zunit + manifest.
;; Per-file fault tolerance: every file is wrapped in condition-case; a
;; signal (unserializable closure / load error / no defuns) is recorded
;; as a SKIP, not a failure.  The build-aux/populate-zeln-cache.zig
;; driver consumes JOBS (files to compile) + SKIPS-LISP and runs
;; zeln-compile per job, classifying emitter rejects (Bswitch / obsolete
;; opcodes) into skips too.  Exits 0 unconditionally.

(defvar zeln-pop--cache-root nil
  "Absolute cache root (set in `zeln-populate-run').")
(defvar zeln-pop--staging nil
  "Staging dir for .zunit/.manifest files (set in `zeln-populate-run').")
(defvar zeln-pop--jobs nil
  "Accumulated JOBS lines (reversed): \"zunit\tmanifest\tzeln\telc\".")
(defvar zeln-pop--skips nil
  "Accumulated serialize-phase SKIP lines (reversed): \"elc\treason\".")
(defvar zeln-pop--nfiles 0)

(defun zeln-pop--source (elc)
  "Return the .el (or .el.gz) source path for ELC, or nil if absent."
  (let ((el (substring elc 0 -1)))	; strip the trailing 'c'
    (cond ((file-exists-p el) el)
	  ((file-exists-p (concat el ".gz")) (concat el ".gz"))
	  (t nil))))

(defun zeln-pop--handle (elc)
  "Serialize one ELC; record a JOBS line or a SKIPS-LISP line."
  (setq zeln-pop--nfiles (1+ zeln-pop--nfiles))
  (let ((src (zeln-pop--source elc)))
    (if (not src)
	(push (format "%s\tno-source" elc) zeln-pop--skips)
      (condition-case err
	  (let* ((rel (comp-z-el-to-zeln-rel-filename src))
		 (ver (comp-z-compute-version-dir))
		 (zeln-path (expand-file-name
			     rel (expand-file-name ver zeln-pop--cache-root)))
		 ;; Stable staging prefix keyed by the .elc path so reruns
		 ;; overwrite cleanly (no stale zunits accumulate).
		 (prefix (expand-file-name
			  (secure-hash 'md5 elc) zeln-pop--staging)))
	    (make-directory (file-name-directory zeln-path) t)
	    (let ((n (comp-z-write-file-zunit elc prefix)))
	      (if (numberp n)
		  (push (format "%s.zunit\t%s.manifest\t%s\t%s"
				prefix prefix zeln-path elc)
			zeln-pop--jobs)
		;; nil: the file defines no defuns -> nothing to native-compile.
		(push (format "%s\tno-defuns" elc) zeln-pop--skips))))
	(error
	 (push (format "%s\tserialize-error: %S" elc err) zeln-pop--skips))))))

(defun zeln-populate-run ()
  "Walk lisp/**/*.elc and serialize each to a zabi=3 zunit.
Writes <cache-root>/JOBS and <cache-root>/SKIPS-LISP.  Exits 0."
  (unless (fboundp 'comp-z-write-file-zunit)
    (message "zeln-populate: comp-z-write-file-zunit not bound \
(build without -Dnative-comp-zig=true?)")
    (kill-emacs 1))
  (setq zeln-pop--cache-root (expand-file-name "zig-out/zeln-cache")
	zeln-pop--staging (expand-file-name "staging" "zig-out/zeln-cache"))
  (make-directory zeln-pop--staging t)
  (let ((n 0))
    (dolist (elc (directory-files-recursively "lisp" "\\.elc\\'"))
      (zeln-pop--handle elc)
      (setq n (1+ n)))
    (with-temp-file (expand-file-name "JOBS" zeln-pop--cache-root)
      (insert (mapconcat #'identity (nreverse zeln-pop--jobs) "\n"))
      (unless (null zeln-pop--jobs) (insert "\n")))
    (with-temp-file (expand-file-name "SKIPS-LISP" zeln-pop--cache-root)
      (insert (mapconcat #'identity (nreverse zeln-pop--skips) "\n"))
      (unless (null zeln-pop--skips) (insert "\n")))
    (message "zeln-populate: %d .elc walked, %d jobs, %d skips"
	     n (length zeln-pop--jobs) (length zeln-pop--skips))))

(when noninteractive
  (zeln-populate-run)
  (kill-emacs 0))

;;; zeln-populate.el ends here
