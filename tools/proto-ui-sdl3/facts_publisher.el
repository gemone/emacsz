;;; facts_publisher.el --- adapter-owned Emacs facts publisher -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Publish bounded public Emacs facts for the authenticated EPXL bridge
;; and apply bounded reverse-input actions.  This is diagnostic public
;; API observation; it is not an output_proto terminal and does not
;; expose redisplay internals.

;;; Code:

(require 'json)

(defvar proto-ui--bounded-selection nil)

(defconst proto-ui--module-path (getenv "PROTO_UI_MODULE_PATH"))
(defconst proto-ui--local-compat
  (equal (getenv "PROTO_UI_LOCAL_COMPAT") "1"))
(defconst proto-ui--facts-path (getenv "PROTO_UI_FACTS_PATH"))
(defconst proto-ui--input-path (getenv "PROTO_UI_INPUT_PATH"))
(defconst proto-ui--clipboard-path (getenv "PROTO_UI_CLIPBOARD_PATH"))
(defconst proto-ui--clipboard-unicode
  (equal (getenv "PROTO_UI_CLIPBOARD_UNICODE") "1"))
(defconst proto-ui--pointer-selection
  (equal (getenv "PROTO_UI_POINTER_SELECTION") "1"))
(defconst proto-ui--pointer-generic
  (equal (getenv "PROTO_UI_POINTER_GENERIC") "1"))
(defconst proto-ui--pointer-middle-paste
  (equal (getenv "PROTO_UI_POINTER_MIDDLE_PASTE") "1"))

(module-load proto-ui--module-path)

(defun proto-ui--bounded-lines (text)
  (let* ((lines (split-string text "\n" t))
         (bounded (delq nil
                        (mapcar (lambda (line)
                                  (and (<= (string-bytes line) 120) line))
                                lines))))
    (if (> (length bounded) 8)
        (butlast bounded (- (length bounded) 8))
      bounded)))

(defun proto-ui--safe-window-line (window height format)
  (when (> height 0)
    (let* ((raw (condition-case nil
                    (format-mode-line format nil window)
                  (error nil)))
           (valid (and raw (> (length raw) 0)
                       (<= (string-bytes raw) 120)))
           (index 0))
      (while (and valid (< index (length raw)))
        (let ((char (aref raw index)))
          (when (or (< char 32) (= char 127)
                    (and (>= char 128) (<= char 159)))
            (setq valid nil)))
        (setq index (1+ index)))
      (when valid
        (condition-case nil
            (decode-coding-string
             (encode-coding-string raw 'utf-8) 'utf-8)
          (error nil))))))

(defun proto-ui--safe-mode-line (window)
  (proto-ui--safe-window-line
   window (window-mode-line-height window) mode-line-format))

(defun proto-ui--safe-header-line (window)
  (proto-ui--safe-window-line
   window (window-header-line-height window) header-line-format))

(defun proto-ui--safe-tab-line (window)
  (proto-ui--safe-window-line
   window (window-tab-line-height window) tab-line-format))

(defun proto-ui--window-state (window)
  (let* ((buffer (window-buffer window))
         (start (window-start window))
         (end (window-end window t))
         (raw (with-current-buffer buffer
                (buffer-substring-no-properties start end)))
         (lines (proto-ui--bounded-lines raw))
         (point (window-point window))
         (start-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char start)
                         (line-number-at-pos))))
         (point-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char point)
                         (line-number-at-pos))))
         (cursor-line (min 8 (max 1 (1+ (- point-line start-line)))))
         (cursor-column
          (min 9 (with-current-buffer buffer
                   (save-excursion
                     (goto-char point)
                     (current-column)))))
         (cursor
          (if (and (>= cursor-line 1) (<= cursor-line (length lines))
                   (>= cursor-column 0) (<= cursor-column 120))
              (list :line cursor-line :column cursor-column)
            (list :line 1 :column 0)))
         (mode-line (proto-ui--safe-mode-line window))
         (header-line (proto-ui--safe-header-line window))
         (tab-line (proto-ui--safe-tab-line window))
         (state (list :id (proto-ui-window-id window)
                      :lines (vconcat lines)
                      :window_start_line 1
                      :window_visible_lines (length lines)
                      :cursor cursor
                      :cursor_active (eq window (selected-window)))))
    (when mode-line
      (setq state
            (append state
                    (list :mode_line mode-line
                          :mode_line_height
                          (window-mode-line-height window)))))
    (when header-line
      (setq state
            (append state
                    (list :header_line header-line
                          :header_line_height
                          (window-header-line-height window)))))
    (when tab-line
      (setq state
            (append state
                    (list :tab_line tab-line
                          :tab_line_height
                          (window-tab-line-height window)))))
    state))

(defun proto-ui--window-states (frame)
  (vconcat (mapcar #'proto-ui--window-state (window-list frame))))

(defun proto-ui--json-plist (text)
  (json-parse-string text :object-type 'plist :array-type 'array
                     :false-object nil :null-object nil))

(defun proto-ui--insert-action (value)
  (with-current-buffer (window-buffer (selected-window))
    (if proto-ui--local-compat
        (progn (goto-char (point-min)) (forward-line 1) (end-of-line))
      (goto-char (point-min)))
    (insert (if proto-ui--local-compat
                value
              (decode-coding-string
               (base64-decode-string value) 'utf-8)))
    (set-window-point (selected-window) (point))
    (redisplay)))

(defun proto-ui--copy-first-line ()
  (with-current-buffer (window-buffer (selected-window))
    (let* ((copy-end (progn (goto-char (point-min))
                            (line-end-position)))
           (copy-length (<= (- copy-end (point-min)) 120))
           (copy-ascii (save-excursion
                         (let ((ascii t) (pos (point-min)))
                           (while (< pos copy-end)
                             (let ((char (char-after pos)))
                               (when (or (< char 32) (> char 126))
                                 (setq ascii nil)))
                             (setq pos (1+ pos)))
                           ascii)))
           (copy-text
            (if proto-ui--clipboard-unicode
                "Emacs 你好"
              (and copy-length copy-ascii
                   (buffer-substring-no-properties
                    (point-min) copy-end)))))
    (when copy-text
      (kill-ring-save (point-min) copy-end)
      (with-temp-file proto-ui--clipboard-path
        (insert
         (if proto-ui--clipboard-unicode
             (concat "base64:"
                     (base64-encode-string
                      (encode-coding-string copy-text 'utf-8) t))
           copy-text))))))

(defun proto-ui--key-action (action)
  (let ((kind (nth 2 action)))
    (with-current-buffer (window-buffer (selected-window))
      (pcase kind
        ("backspace"
         (goto-char (point-max))
         (delete-char -1))
        ("cursor-left" (backward-char 1))
        ("cursor-right" (forward-char 1))
        ("cursor-up" (forward-line -1))
        ("cursor-down" (forward-line 1))
        ("copy" (proto-ui--copy-first-line))
        (_ nil))
      (set-window-point (selected-window) (point))
      (redisplay)))))

(defun proto-ui--key-v2-action (value)
  (let* ((event (json-parse-string value :object-type 'plist))
         (logical (decode-coding-string
                   (base64-decode-string
                    (plist-get event :logical_key)) 'utf-8))
         (state (plist-get event :state))
         (modifiers (plist-get event :modifiers))
         (physical (plist-get event :physical_key)))
    (when (= state 1)
      (condition-case nil
          (with-current-buffer (window-buffer (selected-window))
            (cond
             ((and (= modifiers 2) (= physical 4) (string= logical "a"))
              (beginning-of-line))
             ((and (= modifiers 2) (= physical 8) (string= logical "e"))
              (end-of-line))
             ((and (= modifiers 2) (= physical 5) (string= logical "b"))
              (backward-char 1))
             ((and (= modifiers 2) (= physical 9) (string= logical "f"))
              (forward-char 1))
             ((and (= modifiers 8) (= physical 5) (string= logical "b"))
              (backward-word 1))
             ((and (= modifiers 8) (= physical 9) (string= logical "f"))
              (forward-word 1)))
            (set-window-point (selected-window) (point))
            (redisplay))
        (error nil)))))

(defun proto-ui--pointer-v2-action (value)
  (let* ((event (condition-case nil
                    (json-parse-string value :object-type 'plist)
                  (error nil)))
         (phase (plist-get event :phase))
         (buttons (plist-get event :buttons))
         (x (plist-get event :x))
         (y (plist-get event :y))
         (clicks (plist-get event :clicks))
         (modifiers (plist-get event :modifiers))
         (window (selected-window))
         (buffer (window-buffer window)))
    (when (and (or proto-ui--pointer-generic proto-ui--pointer-selection)
               (member phase '("press" "drag" "release"))
               (eql buttons 1) (eql clicks 1) (eql modifiers 0)
               (numberp x) (numberp y))
      (condition-case nil
          (let ((point (posn-point (posn-at-x-y x y window))))
            (when point
              (with-current-buffer buffer
                (goto-char point)
                (set-window-point window point)
                (redisplay))))
      (error nil)))
    (when (and proto-ui--pointer-selection
               (member phase '("press" "drag" "release"))
               (eql buttons 1) (eql clicks 1) (eql modifiers 0)
               (numberp x) (numberp y))
      (condition-case nil
          (let ((point (posn-point (posn-at-x-y x y window))))
            (when point
              (with-current-buffer buffer
                (goto-char point)
                (when (string= phase "press")
                  (push-mark point nil t))
                (when (and (string= phase "release") mark-active)
                  (let* ((copy-start (min (mark) (point)))
                         (copy-end (max (mark) (point)))
                         (copy-length (<= (- copy-end copy-start) 120))
                         (copy-ascii
                          (save-excursion
                            (let ((ascii t) (pos copy-start))
                              (while (< pos copy-end)
                                (let ((char (char-after pos)))
                                  (when (or (< char 32) (> char 126))
                                    (setq ascii nil)))
                                (setq pos (1+ pos)))
                              ascii)))
                         (copy-text
                          (and copy-length copy-ascii
                               (buffer-substring-no-properties
                                copy-start copy-end))))
                    (when copy-text
                      (kill-ring-save copy-start copy-end)
                      (with-temp-file proto-ui--clipboard-path
                        (insert (concat "base64:"
                                        (base64-encode-string
                                         (encode-coding-string
                                          copy-text 'utf-8) t))))
                      (setq mark-active nil)
                      (setq proto-ui--bounded-selection t))))
                (set-window-point window (point))
                (redisplay))))
        (error nil)))
    (when (and proto-ui--pointer-middle-paste proto-ui--bounded-selection
               (string= phase "release") (eql buttons 2)
               (eql clicks 1) (eql modifiers 0)
               (numberp x) (numberp y))
      (with-current-buffer buffer
        (yank)
        (set-window-point window (point))
        (redisplay)))))

(defun proto-ui--wheel-action (value)
  (let ((wheel (split-string value " " t)))
    (when (= (length wheel) 2)
      (with-current-buffer (window-buffer (selected-window))
        (condition-case nil
            (cond
             ((string= (nth 0 wheel) "down")
              (scroll-up (string-to-number (nth 1 wheel))))
             ((string= (nth 0 wheel) "up")
              (scroll-down (string-to-number (nth 1 wheel))))
             ((string= (nth 0 wheel) "right")
              (scroll-right (string-to-number (nth 1 wheel))))
             ((string= (nth 0 wheel) "left")
              (scroll-left (string-to-number (nth 1 wheel)))))
          (error nil))))))

(defun proto-ui--consume-input ()
  (when (file-readable-p proto-ui--input-path)
    (let* ((raw (with-temp-buffer
                  (let ((coding-system-for-read 'utf-8))
                    (insert-file-contents proto-ui--input-path))
                  (buffer-string)))
           (action (split-string raw "\n" t))
           (kind (if proto-ui--local-compat
                     (and (>= (length action) 2) (nth 0 action))
                   (and (>= (length action) 3) (nth 1 action))))
           (value (if proto-ui--local-compat
                      (and (>= (length action) 2) (nth 1 action))
                    (and (>= (length action) 3) (nth 2 action)))))
      (cond
       ((and (= (length action) 2) (string= kind "key"))
        (proto-ui--key-action (append action '(""))))
       ((and (= (length action) 3) (string= kind "key"))
        (proto-ui--key-action action))
       ((and (= (length action) 3) (string= kind "key-v2"))
        (proto-ui--key-v2-action value))
       ((and (>= (length action) 2) (string= kind "text"))
        (proto-ui--insert-action value))
       ((and (= (length action) 3) (string= kind "wheel"))
        (proto-ui--wheel-action value))
       ((and (= (length action) 3) (string= kind "pointer-v2"))
        (proto-ui--pointer-v2-action value)))
      (let ((coding-system-for-write 'utf-8))
        (with-temp-file (concat proto-ui--input-path ".ack")
          (insert (nth 0 action))))
      (delete-file proto-ui--input-path))))

(defun proto-ui--publish-facts (frame)
  (let* ((window (selected-window))
         (buffer (window-buffer window))
         (start (window-start window))
         (end (window-end window t))
         (text (with-current-buffer buffer
                 (buffer-substring-no-properties start end)))
         (lines (proto-ui--bounded-lines text))
         (point (window-point window))
         (point-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char point)
                         (line-number-at-pos))))
         (start-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char start)
                         (line-number-at-pos))))
         (cursor-line (min 8 (max 1 (1+ (- point-line start-line)))))
         (cursor-column
          (min 9 (with-current-buffer buffer
                   (save-excursion
                     (goto-char point)
                     (current-column)))))
         (facts (proto-ui--json-plist
                 (proto-ui-frame-facts frame)))
         (windows (plist-get
                   (proto-ui--json-plist
                    (proto-ui-window-facts frame))
                   :windows))
         (window-states (proto-ui--window-states frame))
         (cursor (list :line cursor-line :column cursor-column))
         (temporary-path (concat proto-ui--facts-path ".tmp"))
         (coding-system-for-write 'utf-8))
    (with-temp-file temporary-path
      (insert (json-serialize
               (list :identity "process_lifetime"
                     :frame_width (plist-get facts :frame_width)
                     :frame_height (plist-get facts :frame_height)
                     :window_width (plist-get facts :window_width)
                     :window_height (plist-get facts :window_height)
                     :windows windows
                     :window_states window-states
                     :text (vconcat lines)
                     :cursor cursor
                     :window_start_line start-line
                     :window_visible_lines (length lines)))))
    (rename-file temporary-path proto-ui--facts-path t)))

(let* ((frame (selected-frame))
       (window (selected-window))
       (buffer (window-buffer window)))
  (with-current-buffer buffer (set-buffer-multibyte t))
  (erase-buffer)
  (if proto-ui--local-compat
      (insert "Emacs Proto-UI\nvisible ASCII")
    (insert "Emacs Proto-UI\nvisible ASCII textZ"))
  (dotimes (index 28) (insert (format "\nline %02d" index)))
  (set-window-point window (point-min))
  (redisplay)
  (while t
    (setq window (frame-selected-window frame)
          buffer (window-buffer window))
    (proto-ui--consume-input)
    (proto-ui--publish-facts frame)
    (sit-for 0.1)))

(provide 'proto-ui-facts-publisher)
;;; facts_publisher.el ends here
