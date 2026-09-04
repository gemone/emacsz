;;; proto-win.el --- EUP proto-ui terminal registration -*- lexical-binding: t -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; W2 registration support for the opt-in headless EUP backend.  Frame
;; creation is intentionally not implemented until the terminal lifecycle
;; workstream lands.

;;; Code:

(eval-when-compile (require 'cl-lib))

(unless (featurep 'proto)
  (error "%s: Loading proto-win.el but not compiled with proto-ui"
         invocation-name))

(require 'frame)

(defvar proto-initialized nil
  "Non-nil after the EUP backend registration has been checked.")

(cl-defmethod window-system-initialization
  (&context (window-system proto) &optional _display)
  "Initialize the registration-only proto-ui backend.
Terminal lifecycle and transport activation arrive with W3."
  (cl-assert (not proto-initialized))
  (setq proto-initialized t))

(cl-defmethod frame-creation-function
  (params &context (window-system proto))
  "Reject frame creation until W3 implements the proto terminal lifecycle."
  (error "proto-ui frame creation is not implemented yet (parameters %S)"
         params))

(provide 'proto-win)
;;; proto-win.el ends here
