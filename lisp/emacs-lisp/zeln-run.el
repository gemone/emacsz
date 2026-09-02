;;; zeln-run.el --- interactive zeln compilation entry points.  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Software: either version 3, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; The interactive native-compilation entry points for the Zig/LLVM
;; (.zeln) backend, substituting comp-run.el's gccjit pipeline when the
;; build chose zeln (HAVE_NATIVE_COMP_ZIG without HAVE_NATIVE_COMP).
;;
;; Pipeline per .el file (mirrors `zig build populate-zeln-cache' but
;; in-process and interactive):
;;   1. byte-compile the .el (unless a fresh .elc exists);
;;   2. serialize: `comp-z-write-file-zunit' (C, compz.c) Floads the
;;      .elc with a capturing reader and writes one zabi=3 zunit +
;;      manifest pair into a temp staging prefix;
;;   3. compile: spawn the zeln-compile tool (zig cc under the hood --
;;      NO gcc/libgccjit involved) turning the zunit into a .zeln;
;;   4. register: the .zeln lands at exactly the path the load side
;;      (`maybe_swap_for_zeln' via `comp-z-el-to-zeln-rel-filename')
;;      searches, so the NEXT `load'/`require' of the file (and, with
;;      LOAD non-nil, immediately) picks it up transparently.
;;
;; Skips are non-fatal: a file that cannot be serialized or compiled
;; simply keeps its interpreter/bytecode behavior.

;;; Code:

(require 'comp)                    ; comp-eln-load-path-eff, naming
(require 'subr-x)                  ; string-trim
(declare-function comp-z-write-file-zunit "compz.c" (file prefix))
(declare-function comp-z-el-to-zeln-rel-filename "compz.c" (filename))
(declare-function comp-z-compute-version-dir "compz.c" ())

(defgroup zeln nil
  "Interactive native compilation via the Zig/LLVM (zeln) backend."
  :group 'lisp)

(defcustom zeln-compile-executable nil
  "The zeln-compile tool executable.
When nil it is derived from `invocation-directory' (the zig build
installs it next to the emacs binary as zeln-compile)."
  :type '(choice (const :tag "Derive from invocation-directory" nil)
                 (file :tag "Executable")))

(defcustom zeln-compile-timeout 60
  "Per-file timeout (seconds) for one zeln-compile invocation."
  :type 'natnum)

(defvar zeln-async--queue nil
  "Internal queue of pending zeln asynchronous compilation jobs.")

(defvar zeln-async--processes nil
  "Internal list of live zeln asynchronous compilation processes.")

(defun zeln--executable ()
  "Return the zeln-compile tool path."
  (or zeln-compile-executable
      (expand-file-name "zeln-compile" invocation-directory)))

(defun zeln--staging-dir ()
  "Return (and create) the zeln staging directory."
  (let ((dir (expand-file-name "zeln-staging/"
                               temporary-file-directory)))
    (make-directory dir t)
    dir))

(defun zeln--call-compiler (exe args)
  "Run EXE with ARGS, honoring `zeln-compile-timeout'.
Return the process exit status and leave diagnostics in the current
buffer.  Signal `zeln-compile-timeout' when the worker must be killed."
  (let* ((buffer (generate-new-buffer " *zeln compiler*"))
         (process (apply #'make-process
                         (list :name "zeln-compile-tool"
                               :buffer buffer
                               :command (cons (expand-file-name exe)
                                              args))))
         (timeout zeln-compile-timeout)
         (deadline (when (and (numberp timeout) (> timeout 0))
                     (time-add (current-time) timeout))))
    (while (and (process-live-p process)
                (or (not deadline)
                    (time-less-p nil deadline)))
      (accept-process-output process 0.1))
    (when (process-live-p process)
      (delete-process process)
      (accept-process-output process 0.1)
      (kill-buffer buffer)
      (error "zeln-compile timed out after %s seconds" timeout))
    (let ((status (process-exit-status process)))
      (when (buffer-live-p buffer)
        (let ((text (with-current-buffer buffer (buffer-string))))
          (kill-buffer buffer)
          (insert text)))
      status)))

(defun zeln--target-path (src)
  "Return the .zeln cache path SRC (.el) maps to."
  (let* ((rel (comp-z-el-to-zeln-rel-filename src))
         (ver (comp-z-compute-version-dir))
         ;; Mirror maybe_swap_for_zeln exactly.  In a combined build the
         ;; zeln loader searches only `native-comp-zeln-load-path'; in a
         ;; zeln-only build the user-facing eln compatibility path comes
         ;; first, followed by the explicit zeln path.
         (dirs (if (fboundp 'comp--compile-ctxt-to-file0)
                   (bound-and-true-p native-comp-zeln-load-path)
                 (append (bound-and-true-p native-comp-eln-load-path)
                         (bound-and-true-p native-comp-zeln-load-path)))))
    (or (cl-loop for d in dirs
                 when (and (file-name-absolute-p d)
                           ;; The cache root need not exist yet; create it
                           ;; before treating it as a usable destination.
                           (ignore-errors (make-directory d t)
                                          (file-writable-p d)))
                 return (expand-file-name rel (expand-file-name ver d)))
        (expand-file-name rel (expand-file-name ver "~/.emacs.d/eln-cache/")))))

;;;###autoload
(defun zeln-compile-file (file &optional load)
  "Native-compile Lisp source FILE into a .zeln (Zig/LLVM backend).
Return the .zeln filename on success, nil when the file has nothing
to native-compile or is skipped.  With LOAD non-nil, reload FILE
afterwards so its functions run from the .zeln."
  (interactive "fFile to native-compile (zeln): ")
  (unless (fboundp 'comp-z-write-file-zunit)
    (error "zeln-compile-file: this Emacs lacks the zeln backend \
(rebuild with -Dnative-comp-zig=true)"))
  (setq file (expand-file-name file))
  (let* ((elc (concat file "c"))
         (zunit-prefix (expand-file-name (secure-hash 'md5 file)
                                         (zeln--staging-dir)))
         (zeln-path (zeln--target-path file))
         result)
    ;; 1. ensure a fresh .elc
    (unless (and (file-exists-p elc)
                 (not (file-newer-than-file-p file elc)))
      (byte-compile-file file))
    (unless (file-exists-p elc)
      (error "zeln-compile-file: no bytecode for %s" file))
    ;; 2. serialize (a signal here means unserializable -> nil)
    (setq result
          (condition-case err
              (let ((n (comp-z-write-file-zunit elc zunit-prefix)))
                (if (not (numberp n))
                    ;; no defuns: nothing to native-compile
                    nil
                  ;; 3. compile: zeln-compile zunit manifest zeln
                  (make-directory (file-name-directory zeln-path) t)
	                  (let ((exe (zeln--executable)))
	                    (unless (file-executable-p exe)
	                      (error "zeln-compile tool not found at %s" exe))
	                    (with-temp-buffer
	                      (let ((exit (zeln--call-compiler
	                                   exe
	                                   (list (concat zunit-prefix
	                                                 ".zunit")
	                                         (concat zunit-prefix
	                                                 ".manifest")
	                                         zeln-path))))
                        (unless (zerop exit)
                          (error "zeln-compile failed (%s): %s" exit
                                 (buffer-string))))))
                  zeln-path))
            (error
             (message "zeln-compile-file: skipping %s: %S" file err)
             nil)))
    ;; 4. optional immediate reload.  Load the concrete .zeln, not the
    ;; source: `load' on FILE would normally find and evaluate the .el.
    (when (and load result (file-exists-p result))
      (load result nil t))
    result))

;;;###autoload
(defun zeln--async-selector-skip-p (file selector)
  "Return non-nil if SELECTOR rejects FILE from zeln compilation."
  (cond
   ((null selector) nil)
   ((functionp selector) (not (funcall selector file)))
   ((stringp selector) (not (string-match-p selector file)))
   (t (error "SELECTOR must be nil, a function, or a regexp"))))

(defun zeln--async-max-jobs ()
  "Return the maximum number of concurrent zeln workers."
  (max 1 (min 8 (or (bound-and-true-p native-comp-async-jobs-number) 1))))

(defun zeln--async-emacs ()
  "Return the Emacs executable to use for batch zeln workers."
  (expand-file-name invocation-name invocation-directory))

(defun zeln--async-worker-command (file)
  "Return the batch Emacs command compiling FILE in a worker."
  (let ((library (or (locate-library "zeln-run")
                     (error "Cannot locate zeln-run.el"))))
    (list (zeln--async-emacs)
          "--batch" "-Q"
          "--load" library
          "--eval"
          (format "(let ((zeln-compile-executable %S) \
(zeln-compile-timeout %S)) (zeln-compile-file %S) (kill-emacs 0))"
                  zeln-compile-executable zeln-compile-timeout file))))

(defun zeln-async--start-next ()
  "Start queued zeln jobs while worker capacity remains."
  (while (and zeln-async--queue
              (< (length zeln-async--processes)
                 (zeln--async-max-jobs)))
    (let* ((item (pop zeln-async--queue))
           (file (plist-get item :file))
           (buffer (generate-new-buffer " *zeln async worker*"))
           (process (apply #'make-process
                           (list :name "zeln-compile"
                                 :buffer buffer
                                 :sentinel #'zeln-async--sentinel
                                 :command (zeln--async-worker-command file)))))
      (process-put process :zeln-item item)
      (process-put process :zeln-buffer buffer)
      (push process zeln-async--processes)
      (message "zeln compiling %s" file))))

(defun zeln-async--sentinel (process _event)
  "Finish PROCESS, report failures, load when requested, and start more work."
  (when (memq process zeln-async--processes)
    (setq zeln-async--processes (delq process zeln-async--processes))
    (let* ((item (process-get process :zeln-item))
           (buffer (process-get process :zeln-buffer))
           (file (plist-get item :file))
           (load (plist-get item :load))
           (zeln-path (plist-get item :zeln-path))
           (output (and (buffer-live-p buffer)
                        (with-current-buffer buffer
                          (buffer-string))))
           (ok (and (zerop (process-exit-status process))
                    zeln-path
                    (file-exists-p zeln-path)
                    (not (and output
                              (string-match-p
                               "zeln-compile-file: skipping" output)))))
           (load-too (and ok load)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (if ok
          (when load-too
            (condition-case err
                (load zeln-path nil t)
              (error (message "zeln async load failed for %s: %S"
                              zeln-path err))))
        (message "zeln async compilation failed for %s (%s): %s"
                 file (process-status process)
                 (or (and output (string-trim output))
                     "no diagnostics"))))
    (zeln-async--start-next)))

(defun zeln-compile-async (files &optional recursively load selector)
  "Native-compile FILES with the zeln backend without blocking Emacs.
FILES is a file, a list of files, or a directory.  Recurse into a
directory when RECURSIVELY is non-nil.  LOAD and SELECTOR have the
same meaning as in `native-compile-async'.  Each file is compiled by
a batch Emacs worker; failures are logged and compilation continues."
  (interactive "fFile/directory to zeln-compile: ")
  (setq load (not (not load)))
  (when (stringp files)
    (setq files (if (and recursively (file-directory-p files))
                    (directory-files-recursively
                     files "\\.el\\(?:\\.gz\\)?\\'")
                  (list files))))
  (setq files (delq nil (delete-dups
                         (mapcar
                          (lambda (f)
                            (setq f (expand-file-name f))
                            (unless (zeln--async-selector-skip-p f selector)
                              f))
                          (if (stringp files) (list files) files)))))
  (setq zeln-async--queue
        (append zeln-async--queue
                (mapcar (lambda (f)
                          (list :file f :load load
                                :zeln-path (zeln--target-path f)))
                        files)))
  (zeln-async--start-next)
  (length zeln-async--queue))

(provide 'zeln-run)

;;; zeln-run.el ends here
