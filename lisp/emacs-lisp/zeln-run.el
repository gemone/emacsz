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

(defun zeln--target-path (src)
  "Return the .zeln cache path SRC (.el) maps to."
  (let* ((rel (comp-z-el-to-zeln-rel-filename src))
         (ver (comp-z-compute-version-dir))
         ;; In combined eln+zeln builds both variables are normally bound.
         ;; Prefer the explicit zeln cache so a combined fixture cannot
         ;; accidentally write .zeln artifacts into the gccjit cache.
         (dirs (append (bound-and-true-p native-comp-zeln-load-path)
                       (bound-and-true-p native-comp-eln-load-path))))
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
                      (let ((exit (apply #'call-process exe nil t nil
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
    ;; 4. optional immediate reload through the zeln load path
    (when (and load result (file-exists-p result))
      (load file nil t))
    result))

;;;###autoload
(defun zeln-compile-async (files &optional recursively _load)
  "Native-compile FILES via the zeln backend (zeln-compile-file each).
FILES is a file, a list of files, or a directory (recurse into
subdirectories when RECURSIVELY is non-nil).  This is the zeln
counterpart of `native-compile-async'; compilation runs
synchronously per file but is fault-tolerant: failures are
reported and skipped, never signaled."
  (interactive "fFile/directory to zeln-compile: ")
  (when (stringp files)
    (setq files (if (and recursively (file-directory-p files))
                    (directory-files-recursively files "\\.el\\'")
                  (list files))))
  (dolist (f files)
    (message "zeln compiling %s" f)
    (ignore-errors (zeln-compile-file f))))

(provide 'zeln-run)

;;; zeln-run.el ends here
