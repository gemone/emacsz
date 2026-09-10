;;; facts_publisher.el --- adapter-owned Emacs facts publisher -*- lexical-binding: t; no-native-compile: t; -*-

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
(defvar proto-ui--focus-observed nil)
(defvar proto-ui--theme-observed nil)
(defvar proto-ui--monitor-observed nil)
(defvar proto-ui--dpi-observed nil)
(defvar proto-ui--window-resize-observed nil)
(defvar proto-ui--window-move-observed nil)
(defvar proto-ui--window-maximize-observed nil)
(defvar proto-ui--window-fullscreen-observed nil)
(defvar proto-ui--window-minimize-observed nil)
(defvar proto-ui--window-restore-observed nil)

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
                      :cursor_active (if (eq window (selected-window))
                                         t
                                       :json-false))))
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
  ;; Native adapter facts are expected to be valid, but a torn or malformed
  ;; artifact must not kill the publisher loop.  The caller skips this cycle.
  (condition-case nil
      (json-parse-string text :object-type 'plist :array-type 'array
                         :false-object :json-false :null-object :json-null)
    (error nil)))

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

(defun proto-ui--bounded-title (frame)
  (let* ((raw (frame-parameter frame 'title))
         (decoded (condition-case nil
                      (decode-coding-string raw 'utf-8)
                    (error nil)))
         (encoded (and decoded
                       (encode-coding-string decoded 'utf-8)))
         (valid (and (stringp raw) (stringp decoded) (stringp encoded)
                     (string= raw encoded)
                     (> (length raw) 0)
                     (<= (string-bytes raw) 120))))
    (when valid
      (let ((index 0))
        (while (and valid (< index (length raw)))
          (let ((char (aref raw index)))
            (when (or (< char 32) (= char 127)
                      (and (>= char 128) (<= char 159)))
              (setq valid nil)))
          (setq index (1+ index)))))
    (and valid decoded)))

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
           copy-text)))))))

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
      (redisplay))))

(defun proto-ui--key-v2-action (value)
  (let* ((event (condition-case nil
                   (json-parse-string value :object-type 'plist)
                 (error nil)))
         (state (plist-get event :state))
         (raw-command-key (plist-get event :command_key))
         (execution (plist-get event :execution)))
    (when (and (eql (plist-get event :schema) 2)
               (memq state '(1 3))
               (equal execution "command")
               (stringp raw-command-key)
               (> (length raw-command-key) 0)
               (<= (length raw-command-key) 32))
      (let ((command-key
             (condition-case nil
                 (decode-coding-string
                  (base64-decode-string raw-command-key) 'utf-8)
               (error nil))))
        (when (and (stringp command-key) (> (length command-key) 0))
          (let ((valid-command-key t)
                (index 0))
            (while (and valid-command-key (< index (length command-key)))
              (let ((char (aref command-key index)))
                (setq valid-command-key
                      (or (and (>= char ?a) (<= char ?z))
                          (and (>= char ?A) (<= char ?Z))
                          (and (>= char ?0) (<= char ?9))
                          (= char ?-) (= char ?<) (= char ?>)
                          (= char ?\s)))
                (setq index (1+ index))))
            (when valid-command-key
              (condition-case nil
                  (with-current-buffer (window-buffer (selected-window))
                    (let ((key-sequence (kbd command-key)))
                      ;; Accept only the single-key subset or the exact,
                      ;; whitelisted two-key C-x window commands.
                      (when (or (= (length key-sequence) 1)
                                (and (= (length key-sequence) 2)
                                     (member command-key
                                             '("C-x 1" "C-x 2" "C-x 3" "C-x o"))))
                        (execute-kbd-macro key-sequence)))
                    (set-window-point (selected-window) (point))
                    (redisplay))
                (error nil)))))))))

(defun proto-ui--pointer-window-at (frame x y)
  "Return the live FRAME window covering pixel X,Y and its local coordinates."
  (catch 'proto-ui-window
    (dolist (window (window-list frame))
      (let* ((edges (window-pixel-edges window))
             (left (nth 0 edges))
             (top (nth 1 edges))
             (right (nth 2 edges))
             (bottom (nth 3 edges)))
        (when (and (numberp left) (numberp top) (numberp right) (numberp bottom)
                   (>= x left) (< x right) (>= y top) (< y bottom))
          (throw 'proto-ui-window
                 (cons window (cons (- x left) (- y top)))))))))

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
         (frame (selected-frame))
         (target (and proto-ui--pointer-generic (numberp x) (numberp y)
                      (proto-ui--pointer-window-at frame x y)))
         (window (car target))
         (window-x (if target (car (cdr target)) x))
         (window-y (if target (cdr (cdr target)) y))
         (buffer (if window (window-buffer window)
                   (window-buffer (selected-window))))
         (left-action-p (and (member phase '("press" "drag" "release"))
                             (eql buttons 1) (eql clicks 1) (eql modifiers 0))))
    (when (and window proto-ui--pointer-generic left-action-p target
               (not (eq window (selected-window))))
      (select-window window 'norecord))
    (when (and left-action-p
               (or (and proto-ui--pointer-generic target)
                   (and (not proto-ui--pointer-generic)
                        proto-ui--pointer-selection))
               (numberp window-x) (numberp window-y))
      (condition-case nil
          (let ((point (posn-point (posn-at-x-y window-x window-y window))))
            (when point
              (with-current-buffer buffer
                (goto-char point)
                (set-window-point window point)
                (redisplay))))
      (error nil)))
    (when (and proto-ui--pointer-selection
               (member phase '("press" "drag" "release"))
               (eql buttons 1) (eql clicks 1) (eql modifiers 0)
               (numberp window-x) (numberp window-y))
      (condition-case nil
          (let ((point (posn-point (posn-at-x-y window-x window-y window))))
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

(defun proto-ui--theme-action (value)
  (let* ((event (condition-case nil
                    (json-parse-string value :object-type 'plist)
                  (error nil)))
         (appearance (plist-get event :appearance)))
    (when (member appearance '("dark" "light"))
      (setq proto-ui--theme-observed appearance))))

(defun proto-ui--monitor-action (value)
  (let ((event (condition-case nil
                  (json-parse-string value :object-type 'plist)
                (error nil))))
    (when (and (plist-get event :current) (numberp (plist-get event :monitor_id)))
      (setq proto-ui--monitor-observed event))))

(defun proto-ui--focus-action (value)
  (let* ((event (condition-case nil
                  (proto-ui--json-plist value)
                (error nil)))
         (phase (plist-get event :phase))
         (frame (selected-frame)))
    (when (member phase '("focus-gained" "focus-lost"))
      (setq proto-ui--focus-observed (string= phase "focus-gained"))
      (when (and (string= phase "focus-gained") (frame-live-p frame))
        (condition-case nil
            (select-frame frame 'norecord)
          (error nil))))))

(defun proto-ui--dpi-action (value)
  (let ((event (condition-case nil
                  (json-parse-string value :object-type 'plist)
                (error nil))))
    (when (and (numberp (plist-get event :frame_id))
               (> (plist-get event :scale) 0))
      (setq proto-ui--dpi-observed event))))

(defun proto-ui--window-action (value)
  (let* ((event (condition-case nil
                  (proto-ui--json-plist value)
                (error nil)))
         (request (plist-get event :request))
         (frame (selected-frame))
         (window (selected-window)))
    (cond
     ((and (string= request "resize") (frame-live-p frame)
           (numberp (plist-get event :width))
           (numberp (plist-get event :height))
           (> (plist-get event :width) 0)
           (> (plist-get event :height) 0)
           (<= (plist-get event :width) 16384)
           (<= (plist-get event :height) 16384))
      (condition-case err
          (let ((frame-resize-pixelwise t))
            (set-frame-size frame
                            (plist-get event :width)
                            (plist-get event :height)
                            t)
            (with-current-buffer (window-buffer window)
              (goto-char (point-min))
              (unless (looking-at-p "ResizeApplied")
                (insert "ResizeApplied "))
              (set-window-point window (point)))
            (setq proto-ui--window-resize-observed event)
            (redisplay frame))
        (error nil)))
     ((and (string= request "move") (frame-live-p frame)
           (numberp (plist-get event :x))
           (numberp (plist-get event :y)))
      (condition-case nil
          (progn
            (set-frame-position frame
                                (plist-get event :x)
                                (plist-get event :y))
            (with-current-buffer (window-buffer window)
              (goto-char (point-min))
              (unless (looking-at-p "MoveApplied")
                (insert "MoveApplied "))
              (set-window-point window (point)))
            (setq proto-ui--window-move-observed event)
            (redisplay frame))
        (error nil)))
     ((and (string= request "maximize") (frame-live-p frame))
      (condition-case nil
          (progn
            (set-frame-parameter frame 'fullscreen 'maximized)
            (redisplay frame)
            (when (eq (frame-parameter frame 'fullscreen) 'maximized)
              (with-current-buffer (window-buffer window)
                (goto-char (point-min))
                (unless (looking-at-p "MaximizeApplied")
                  (insert "MaximizeApplied "))
                (set-window-point window (point)))
              (setq proto-ui--window-maximize-observed event)))
        (error nil)))
     ((and (string= request "fullscreen") (frame-live-p frame))
      (condition-case nil
          (progn
            (set-frame-parameter frame 'fullscreen 'fullboth)
            (redisplay frame)
            (when (eq (frame-parameter frame 'fullscreen) 'fullboth)
              (with-current-buffer (window-buffer window)
                (goto-char (point-min))
                (unless (looking-at-p "FullscreenApplied")
                  (insert "FullscreenApplied "))
                (set-window-point window (point)))
              (setq proto-ui--window-fullscreen-observed event)))
        (error nil)))
     ((and (string= request "minimize") (frame-live-p frame))
      (condition-case nil
          (progn
            (iconify-frame frame)
            (redisplay frame)
            (with-current-buffer (window-buffer window)
              (goto-char (point-min))
              (unless (looking-at-p "MinimizeApplied")
                (insert "MinimizeApplied "))
              (set-window-point window (point)))
            (setq proto-ui--window-minimize-observed event))
        (error nil)))
     ((and (string= request "restore") (frame-live-p frame))
      (condition-case nil
          (progn
            (make-frame-visible frame)
            (redisplay frame)
            (with-current-buffer (window-buffer window)
              (goto-char (point-min))
              (unless (looking-at-p "RestoreApplied")
                (insert "RestoreApplied "))
              (set-window-point window (point)))
            (setq proto-ui--window-restore-observed event))
        (error nil))))))

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
       ((and (= (length action) 3) (string= kind "theme"))
        (proto-ui--theme-action value))
       ((and (= (length action) 3) (string= kind "monitor"))
        (proto-ui--monitor-action value))
       ((and (= (length action) 3) (string= kind "dpi"))
        (proto-ui--dpi-action value))
       ((and (= (length action) 3) (string= kind "platform-focus"))
        (proto-ui--focus-action value))
       ((and (= (length action) 3) (string= kind "platform-window"))
        (proto-ui--window-action value))
       ((and (= (length action) 3) (string= kind "wheel"))
        (proto-ui--wheel-action value))
       ((and (= (length action) 3) (string= kind "pointer-v2"))
	(proto-ui--pointer-v2-action value)))
      (when action
	(let ((coding-system-for-write 'utf-8))
	  (with-temp-file (concat proto-ui--input-path ".ack")
	    (insert (nth 0 action))))
	(delete-file proto-ui--input-path)))))

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
         (title (proto-ui--bounded-title frame))
         (temporary-path (concat proto-ui--facts-path ".tmp"))
         (coding-system-for-write 'utf-8))
    (when (and facts windows)
      (let ((wire (list :identity "process_lifetime"
		      :frame_width (plist-get facts :frame_width)
                      :frame_height (plist-get facts :frame_height)
                      :window_width (plist-get facts :window_width)
                      :window_height (plist-get facts :window_height)
                      :windows windows
                      :window_states window-states
                      :text (vconcat lines)
                      :cursor cursor
                      :window_start_line start-line
                      :window_visible_lines (length lines)
		      :focused (if proto-ui--focus-observed t :json-false))))
	(when title (plist-put wire :title title))
	(with-temp-file temporary-path
	  (insert (json-encode wire))))
      (rename-file temporary-path proto-ui--facts-path t))))

(module-load proto-ui--module-path)

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
  (when (equal (getenv "PROTO_UI_TITLE_SMOKE") "1")
    (set-frame-parameter frame 'title "Emacs Proto-UI Title"))
  (while t
    (setq window (frame-selected-window frame)
          buffer (window-buffer window))
    (proto-ui--consume-input)
    (proto-ui--publish-facts frame)
    (sit-for 0.1)))

(provide 'proto-ui-facts-publisher)
;;; facts_publisher.el ends here
