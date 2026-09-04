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

;; W3 support for the opt-in headless EUP backend.  Real terminal lifecycle
;; is implemented.  Frame creation remains intentionally unimplemented until
;; the frame-lifecycle workstream lands.

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
  "Initialize the proto-ui backend with real terminal lifecycle support."
  (cl-assert (not proto-initialized))
  (setq proto-initialized t))

(cl-defmethod frame-creation-function
  (params &context (window-system proto))
  "Reject frame creation until the proto frame lifecycle is implemented."
  (error "proto-ui frame creation is not implemented yet (parameters %S)"
         params))

(provide 'proto-win)
;;; proto-win.el ends here
