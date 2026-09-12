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
(defconst proto-ui--visible-edit
  (equal (getenv "PROTO_UI_VISIBLE_EDIT") "1"))
(defconst proto-ui--dnd-text
  (equal (getenv "PROTO_UI_DND_TEXT") "1"))
(defconst proto-ui--face-smoke
  (equal (getenv "PROTO_UI_FACE_SMOKE") "1"))
(defconst proto-ui--cursor-smoke
  (equal (getenv "PROTO_UI_CURSOR_SMOKE") "1"))
(defconst proto-ui--scrollbar-smoke
  (equal (getenv "PROTO_UI_SCROLLBAR_SMOKE") "1"))
(defconst proto-ui--hscroll-smoke
  (equal (getenv "PROTO_UI_HSCROLL_SMOKE") "1"))
(defconst proto-ui--region-smoke
  (equal (getenv "PROTO_UI_REGION_SMOKE") "1"))
(defconst proto-ui--runs-smoke
  (equal (getenv "PROTO_UI_RUNS_SMOKE") "1"))
(defconst proto-ui--header-smoke
  (equal (getenv "PROTO_UI_HEADER_SMOKE") "1"))
(defconst proto-ui--mouse-smoke
  (equal (getenv "PROTO_UI_MOUSE_SMOKE") "1"))
(defconst proto-ui--echo-smoke
  (equal (getenv "PROTO_UI_ECHO_SMOKE") "1"))
(defconst proto-ui--menu-icon-smoke
  (equal (getenv "PROTO_UI_MENU_ICON_TEST") "1"))
(defvar proto-ui--menu-open nil
  "Bounded open-menu state published while a live menu-bar item is open.")
(defvar proto-ui--pointer-position nil
  "Last observed pointer position as (X . Y) in frame pixels, or nil.")
(defvar proto-ui--menu-open-commands nil
  "Adapter-local command names for the open menu's published rows.")
(defvar proto-ui--menu-open-keymaps nil
  "Adapter-local submenu keymaps for the open menu's published rows.")
(defvar proto-ui--menu-open-path nil
  "Selected submenu identities from the menu bar to the open popup's parent.")
(defvar proto-ui--keymap-pending nil
  "Canonical key events accumulated until Emacs resolves a complete keymap.")

(defun proto-ui--printable-ascii (text)
  "Where TEXT is a bounded printable-ASCII string.

The bounded run wire carries only printable ASCII, so a line with any other
character keeps its plain-text path instead of publishing a run the adapter
would reject."
  (and (stringp text) (string-match-p "\\`[\x20-\x7e]*\\'" text)))

(defun proto-ui--visual-line-spans (window start)
  "Return bounded (BEG . END) spans of WINDOW's displayed lines from START.

Each span is one screen line, so a wrapped logical line yields several spans;
the span ends before its newline, because that is exactly what the display
draws on the row.  nil means the bounded display walk is unavailable, and the
caller falls back to logical lines."
  (let ((spans nil)
        (done nil))
    (condition-case nil
        (save-excursion
          (goto-char start)
          (let ((visible-end (window-end window t)))
            (while (and (not done) (< (length spans) 32) (< (point) visible-end))
              (let* ((beg (point))
                     ;; WINDOW keeps the walk on this window's geometry, so an
                     ;; unbalanced split wraps where that window really wraps.
                     (moved (vertical-motion 1 window))
                     (fin (point)))
                (if (or (= beg fin) (<= moved 0))
                    (setq done t)
                  (when (and (> fin beg) (= (char-before fin) ?\n))
                    (setq fin (1- fin)))
                  (push (cons beg (min fin visible-end)) spans))))))
      (error (setq spans nil)))
    (nreverse spans)))

(defun proto-ui--display-lines (window start raw)
  "Return WINDOW's displayed line texts, wrapped rows and all.

Each displayed (possibly wrapped) row becomes one bounded line; RAW is the
logical region text, used to fall back to logical lines when the bounded
display walk is unavailable."
  (let ((spans (proto-ui--visual-line-spans window start))
        (buffer (window-buffer window)))
    (if spans
        (mapcar (lambda (span)
                  (proto-ui--bounded-line
                   (with-current-buffer buffer
                     (buffer-substring-no-properties (car span) (cdr span)))))
                spans)
      (proto-ui--bounded-lines raw))))

(defun proto-ui--column-index (line columns)
  "Return the character index in LINE where display COLUMNS have elapsed.

A wide character advances by its own display width, so this is the character
boundary the horizontally scrolled display starts at, not a raw column count."
  (if (<= columns 0)
      0
    (let ((index 0)
          (width 0)
          (length (length line)))
      (while (and (< index length) (< width columns))
        (setq width (+ width (string-width (substring line index (1+ index)))))
        (setq index (1+ index)))
      index)))

(defun proto-ui--hscroll-trim (line columns)
  "Return LINE with the first COLUMNS display columns removed."
  (if (<= columns 0)
      line
    (substring line (proto-ui--column-index line columns))))

(defun proto-ui--bounded-line (line)
  "Return LINE truncated to the row wire bound at a character boundary.

A line past the bound is truncated rather than dropped, because dropping it
would shift every following mirrored row out of display alignment."
  (if (<= (string-bytes line) 256)
      line
    (let ((end (length line)))
      (while (and (> end 0) (> (string-bytes (substring line 0 end)) 256))
        (setq end (1- end)))
      (substring line 0 end))))

(defun proto-ui--bounded-lines (text)
  (let* ((lines (split-string text "\n"))
         ;; A region ending on a newline yields a trailing empty element that
         ;; is not a displayed row, but interior empty lines are real rows and
         ;; must be kept so the mirrored rows stay aligned with the display.
         (lines (if (and lines (equal (car (last lines)) ""))
                    (butlast lines)
                  lines))
         (bounded (mapcar #'proto-ui--bounded-line lines)))
    (if (> (length bounded) 32)
        (butlast bounded (- (length bounded) 32))
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
         (scroll-width (if proto-ui--scrollbar-smoke
                           (if (eq window (selected-window)) 12 0)
                         (or (window-scroll-bar-width window) 0)))
         (scroll-width (min scroll-width 256))
         (scroll-height (if proto-ui--hscroll-smoke
                            (if (eq window (selected-window)) 8 0)
                          (or (window-scroll-bar-height window) 0)))
         (scroll-height (min scroll-height 256))
         (hscroll (max 0 (window-hscroll window)))
         (hviewport (max 1 (window-body-width window)))
         (fringes (let ((widths (ignore-errors (window-fringes window))))
                    (when (and (consp widths) (integerp (nth 0 widths))
                               (integerp (nth 1 widths)))
                      (cons (max 0 (min 64 (nth 0 widths)))
                            (max 0 (min 64 (nth 1 widths)))))))
         (fringe-left (car fringes))
         (fringe-right (cdr fringes))
         (buffer-lines (with-current-buffer buffer
                         (min (line-number-at-pos (point-max)) 1000000)))
         (raw (with-current-buffer buffer
                (buffer-substring-no-properties start end)))
         ;; The mirror shows what the display shows: one row per displayed
         ;; (possibly wrapped) line, with the horizontally scrolled-off
         ;; columns dropped from every row.
         (lines (mapcar (lambda (line) (proto-ui--hscroll-trim line hscroll))
                        (proto-ui--display-lines window start raw)))
         (point (window-point window))
         (start-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char start)
                         (line-number-at-pos))))
         (point-line (with-current-buffer buffer
                       (save-excursion
                         (goto-char point)
                         (line-number-at-pos))))
         (scroll-top (max 0 (1- start-line)))
         (hcontent (let ((widest hviewport)
                         (visible-end (window-end window t)))
                     (save-excursion
                       (goto-char (window-start window))
                       (while (< (point) visible-end)
                         (setq widest (max widest
                                           (- (line-end-position)
                                              (line-beginning-position))))
                         (forward-line 1))
                       widest)))
        (cursor-line (min 8 (max 1 (1+ (- point-line start-line)))))
         (cursor-column
          (min 9 (max 0 (- (with-current-buffer buffer
                             (save-excursion
                               (goto-char point)
                               (current-column)))
                           hscroll))))
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
    (when (> scroll-width 0)
      (setq state
            (append state
                    (list :scroll_width scroll-width
                          :buffer_lines buffer-lines
                          :scroll_top scroll-top))))
    (when (> scroll-height 0)
      (setq state
            (append state
                    (list :scroll_height scroll-height
                          :hscroll hscroll
                          :hviewport hviewport
                          :hcontent hcontent))))
    (when (and fringes (> (+ fringe-left fringe-right) 0))
      (setq state
            (append state
                    (list :fringe_left (or fringe-left 0)
                          :fringe_right (or fringe-right 0)))))
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
    (cond
     ;; Benchmark/local edit profile: apply text at point so an alternating
     ;; insert/backspace stream produces a distinct fact change every step.
     (proto-ui--visible-edit (goto-char (window-point (selected-window))))
     (proto-ui--local-compat
      (goto-char (point-min)) (forward-line 1) (end-of-line))
     (t (goto-char (point-min))))
    (insert (if proto-ui--local-compat
                value
              (decode-coding-string
               (base64-decode-string value) 'utf-8)))
    (set-window-point (selected-window) (point))
    (redisplay)))

(defun proto-ui--dnd-action (value)
  "Apply one bounded dropped payload for the drag-and-drop smoke profile.

Only the smoke profile sets `proto-ui--dnd-text'.  A drop is accepted only when
the offer target is plain text and the decoded payload is a bounded printable
string; anything else is ignored rather than acted on."
  (when proto-ui--dnd-text
    (let* ((event (condition-case nil
                      (json-parse-string value :object-type 'plist)
                    (error nil)))
           (target (plist-get event :target))
           (raw (plist-get event :payload))
           (decoded (and (stringp raw)
                         (> (length raw) 0)
                         (<= (length raw) 352)
                         (condition-case nil
                             (base64-decode-string raw)
                           (error nil)))))
      (when (and (stringp target)
                 (string= target "text/plain")
                 (stringp decoded)
                 (> (length decoded) 0)
                 (<= (length decoded) 120)
                 (string-match-p "\\`[[:print:]]+\\'" decoded))
        (with-current-buffer (window-buffer (selected-window))
          (goto-char (window-point (selected-window)))
          (insert decoded)
          (set-window-point (selected-window) (point))
          (redisplay))))))

(defconst proto-ui--max-line-runs 8
  "Most font-lock runs published for one visible line.")
(defconst proto-ui--max-run-rows 8
  "Most visible lines whose font-lock runs are published.")
(defconst proto-ui--max-total-runs 32
  "Most font-lock runs published in one snapshot.")
(defconst proto-ui--max-run-windows 2
  "Most visible windows whose font-lock runs are published.")

(defun proto-ui--face-attr-color (face attribute)
  "Return FACE's ATTRIBUTE as a bounded #rrggbb string, or nil.

A face that leaves the attribute unspecified falls back to the default face, so
a background-only face still contributes its own foreground."
  (let ((value (and face (ignore-errors (face-attribute face attribute nil t)))))
    (when (or (null value) (eq value 'unspecified))
      (setq value (ignore-errors (face-attribute 'default attribute nil t))))
    (proto-ui--bounded-color value)))

(defun proto-ui--face-flag (face attribute)
  "Return non-nil when FACE's ATTRIBUTE is a real decoration."
  (let ((value (and face (ignore-errors (face-attribute face attribute nil t)))))
    (when (or (null value) (eq value 'unspecified))
      (setq value (ignore-errors (face-attribute 'default attribute nil t))))
    (and value (not (eq value 'unspecified)) (not (eq value 'off)) t)))

(defun proto-ui--face-bold-p (face)
  "Return non-nil when FACE is heavier than normal."
  (let ((weight (and face (ignore-errors (face-attribute face :weight nil t)))))
    (and (memq weight '(semi-bold bold extra-bold heavy black ultra-heavy)) t)))

(defun proto-ui--face-italic-p (face)
  "Return non-nil when FACE is slanted."
  (let ((slant (and face (ignore-errors (face-attribute face :slant nil t)))))
    (and (memq slant '(italic oblique reverse-italic reverse-oblique)) t)))

(defun proto-ui--decoration-color (face attribute)
  "Return FACE's ATTRIBUTE color when the decoration names one.

Emacs allows a decoration value of t, a color string, or a plist such as
(:color \"red\" :style wave); only the named color is published."
  (let ((value (and face (ignore-errors (face-attribute face attribute nil t)))))
    (when (or (null value) (eq value 'unspecified))
      (setq value (ignore-errors (face-attribute 'default attribute nil t))))
    (cond
     ((stringp value) (proto-ui--bounded-color value))
     ((and (listp value) (plist-member value :color))
      (proto-ui--bounded-color (plist-get value :color)))
     (t nil))))

(defun proto-ui--face-font-file (face)
  "Return FACE's file-backed font path, or nil.

Like `proto-ui--default-font', this accepts only bounded, readable TTF/OTF/TTC
files so an unusable symbolic font keeps the frontend's default rather than
propagating a guess."
  (let* ((font (and face (ignore-errors (face-attribute face :font nil))))
         (info (and font (not (eq font 'unspecified))
                    (ignore-errors (font-info font))))
         (file nil)
         (index 0))
    (when (vectorp info)
      (while (and (< index (length info)) (null file))
        (let ((value (aref info index)))
          (when (and (stringp value)
                     (string-match-p "\\.\\(ttf\\|otf\\|ttc\\)\\'" value)
                     (file-readable-p value)
                     (> (length value) 0) (<= (length value) 120))
            (setq file value)))
        (setq index (1+ index))))
    (when (and file
               (not (string-match-p "[\x00-\x1f\x7f]" file)))
      file)))

(defun proto-ui--box-style (value)
  "Return the bounded box style name for a face :box VALUE.

nil, `unspecified', and `off' are `none'; a released/pressed button style keeps
that style; anything else that names a box is the bounded `simple' box."
  (cond
   ((or (null value) (eq value 'unspecified) (eq value 'off)) "none")
   ((and (consp value) (eq (plist-get value :style) 'released-button)) "released")
   ((and (consp value) (eq (plist-get value :style) 'pressed-button)) "pressed")
   (t "simple")))

(defun proto-ui--bounded-box-width (width)
  "Clamp WIDTH to the bounded 1..8 pixel box range."
  (let ((magnitude (abs width)))
    (cond ((<= magnitude 0) 1)
          ((> magnitude 8) 8)
          (t magnitude))))

(defun proto-ui--box-width (value)
  "Return the bounded `:box' border width of VALUE in pixels, or 0 for no box.

Emacs spells the width as `:line-width' inside the box plist (an integer or a
horizontal/vertical cons), and a negative width means \"relative to the frame's
own border\", so its magnitude is the bounded stand-in.  A box that names no
width is one pixel."
  (cond
   ((or (null value) (eq value 'unspecified) (eq value 'off)) 0)
   ((integerp value) (proto-ui--bounded-box-width value))
   ((and (consp value) (plist-member value :line-width))
    (let ((line-width (plist-get value :line-width)))
      (proto-ui--bounded-box-width
       (cond ((integerp line-width) line-width)
             ((and (consp line-width) (integerp (car line-width))) (car line-width))
             (t 1)))))
   ((and (consp value) (integerp (car value)))
    (proto-ui--bounded-box-width (car value)))
   (t 1)))

(defun proto-ui--face-colors (face default-background default-font-file)
  "Return FACE's resolved line run colors.

The list is (FOREGROUND BACKGROUND UNDERLINE STRIKE-THROUGH OVERLINE
UNDERLINE-COLOR STRIKE-COLOR OVERLINE-COLOR INVERSE-VIDEO BOLD ITALIC
VARIABLE-PITCH).  The background is nil when it matches DEFAULT-BACKGROUND;
VARIABLE-PITCH is non-nil only when FACE resolves to a distinct file-backed
font."
  (let ((foreground (proto-ui--face-attr-color face :foreground))
        (resolved (proto-ui--face-attr-color face :background))
        (font-file (proto-ui--face-font-file face)))
    (list foreground
          (and resolved (not (equal resolved default-background)) resolved)
          (proto-ui--face-flag face :underline)
          (proto-ui--face-flag face :strike-through)
          (proto-ui--face-flag face :overline)
          (proto-ui--decoration-color face :underline)
          (proto-ui--decoration-color face :strike-through)
          (proto-ui--decoration-color face :overline)
          (proto-ui--face-flag face :inverse-video)
          (proto-ui--face-bold-p face)
          (proto-ui--face-italic-p face)
          font-file
          (and font-file default-font-file
               (not (equal font-file default-font-file))))))

(defun proto-ui--line-colors (buffer position default-background default-font-file)
  "Return POSITION's resolved line run in BUFFER."
  ;; Resolve the overlay-aware face: get-char-property sees the same text
  ;; properties plus the highest-priority overlay face, which is what drives
  ;; hl-line, isearch, and spell-check highlighting.
  (proto-ui--face-colors
   (with-current-buffer buffer (get-char-property position 'face))
   default-background default-font-file))

(defun proto-ui--append-run (runs window-id chrome row index text colors)
  "Append or extend one run in RUNS, returning the updated list.

CHROME is nil for a body run or :mode_line/:header_line/:tab_line for a chrome
run.  COLORS is the list proto-ui--face-colors returns; a run is only appended
when it differs from the head of RUNS."
  (let ((foreground (nth 0 colors))
        (background (nth 1 colors))
        (underline (nth 2 colors))
        (strike (nth 3 colors))
        (overline (nth 4 colors))
        (underline-color (nth 5 colors))
        (strike-color (nth 6 colors))
        (overline-color (nth 7 colors))
        (inverse (nth 8 colors))
        (bold (nth 9 colors))
        (italic (nth 10 colors))
        (font-file (nth 11 colors))
        (variable-pitch (nth 12 colors)))
    (cond
     ((null foreground) nil)
     ((and runs
           (equal (plist-get (car runs) :foreground) foreground)
           (equal (plist-get (car runs) :background) background)
           (equal (plist-get (car runs) :underline) underline)
           (equal (plist-get (car runs) :strike-through) strike)
           (equal (plist-get (car runs) :overline) overline)
           (equal (plist-get (car runs) :underline_color) underline-color)
           (equal (plist-get (car runs) :strike_color) strike-color)
           (equal (plist-get (car runs) :overline_color) overline-color)
           (equal (plist-get (car runs) :inverse_video) inverse)
           (equal (plist-get (car runs) :bold) bold)
           (equal (plist-get (car runs) :italic) italic)
           (equal (plist-get (car runs) :font_file) font-file))
      (setcar runs (plist-put (car runs) :text
                              (concat (plist-get (car runs) :text) text)))
      runs)
     (t (let ((run (list :window_id window-id :row row :column index
                         :text text :foreground foreground)))
          (when font-file (setq run (plist-put run :font_file font-file)))
          (when chrome (setq run (plist-put run chrome t)))
          (when background (setq run (plist-put run :background background)))
          (when underline (setq run (plist-put run :underline t)))
          (when strike (setq run (plist-put run :strike-through t)))
          (when overline (setq run (plist-put run :overline t)))
          (when underline-color
            (setq run (plist-put run :underline_color underline-color)))
          (when strike-color
            (setq run (plist-put run :strike_color strike-color)))
          (when overline-color
            (setq run (plist-put run :overline_color overline-color)))
          (when inverse (setq run (plist-put run :inverse_video t)))
          (when bold (setq run (plist-put run :bold t)))
          (when italic (setq run (plist-put run :italic t)))
          (when variable-pitch (setq run (plist-put run :variable_pitch t)))
          (push run runs))))))

(defun proto-ui--put-run-metrics (runs char-width pixel-x)
  "Merge CHAR-WIDTH at PIXEL-X into the head of RUNS.

CHAR-WIDTH comes from `string-pixel-width' when Emacs provides it; nil keeps
the adapter's character-cell fallback for the whole run."
  (when (and runs (integerp char-width) (> char-width 0))
    (let ((run (car runs)))
      (setcar runs (plist-put run :pixel_x pixel-x))
      (setcar runs (plist-put run :pixel_width
                              (+ char-width
                                 (or (plist-get run :pixel_width) 0))))))
  runs)

(defun proto-ui--chrome-runs (window default-background kind)
  "Return the bounded per-segment runs of WINDOW's KIND line, or nil.

KIND is :mode_line, :header_line, or :tab_line.  format-mode-line returns the
line string with its own face properties, so the bold buffer id and any other
emphasized segment keep their faces."
  (let* ((default-font (proto-ui--default-font (window-frame window)))
         (default-font-file (and default-font (car default-font)))
         (format (pcase kind
                   (:mode_line mode-line-format)
                   (:header_line header-line-format)
                   (:tab_line tab-line-format)))
         (height (pcase kind
                   (:mode_line (window-mode-line-height window))
                   (:header_line (window-header-line-height window))
                   (:tab_line (window-tab-line-height window))))
         (text (and (> height 0)
                    (ignore-errors (format-mode-line format nil window))))
         (length (and (stringp text) (length text))))
    (when (and length (> length 0) (<= (string-bytes text) 120)
               (proto-ui--printable-ascii text))
      (let ((runs nil)
            (index 0)
            (pixel-x 0)
            (valid t))
        (while (and valid (< index length))
          (let* ((face (get-text-property index 'face text))
                 (char-width (ignore-errors
                               (string-pixel-width
                                (propertize (substring text index (1+ index))
                                            'face face))))
                 (colors (proto-ui--face-colors
                          face default-background default-font-file)))
            (unless (nth 0 colors) (setq valid nil))
            (when valid
              (setq runs (proto-ui--append-run
                          runs (proto-ui-window-id window) kind 0 index
                          (substring text index (1+ index)) colors))
              (setq runs (proto-ui--put-run-metrics runs char-width pixel-x))
              (setq pixel-x (+ pixel-x (or char-width 0)))))
          (setq index (1+ index)))
        (when (and valid runs (<= (length runs) proto-ui--max-line-runs))
          (nreverse runs))))))

(defun proto-ui--line-runs (frame)
  "Return bounded font-lock runs for FRAME's visible windows, or nil.

Each run is (:window_id N :row N :column N :text STRING :foreground #rrggbb)
with an optional :background when a face sets one different from the frame
default and optional :underline/:strike-through/:overline flags plus
:inverse_video/:bold/:italic.  A row's runs must cover that visible line's
whole text, so the frontend can replace the row's plain text without hiding
anything; a row with no colors, more runs than the bound, or an unresolvable
color simply keeps its single-face text.  At most two windows share the
bounded run budget, so a split frame colors both windows."
  (when (frame-live-p frame)
    (let* ((default-background (proto-ui--face-color :background))
           (default-font (proto-ui--default-font frame))
           (default-font-file (and default-font (car default-font)))
           (result nil)
           (windows 0))
      (dolist (window (window-list frame))
        (when (and (< windows proto-ui--max-run-windows)
                   (< (length result) proto-ui--max-total-runs))
          (setq windows (1+ windows))
          (let* ((buffer (window-buffer window))
                 (start (window-start window))
                 (end (window-end window t))
                 (hscroll (window-hscroll window))
                 (window-id (proto-ui-window-id window))
                 (row 0))
            (with-current-buffer buffer
              (save-excursion
                (goto-char start)
                (while (and (< row proto-ui--max-run-rows)
                            (< (length result) proto-ui--max-total-runs)
                            (< (point) end))
                  ;; Each iteration is one displayed (possibly wrapped) row, so
                  ;; the runs line up with the mirrored rows.
                  (let* ((line-start (point))
                         (line-fin (progn (vertical-motion 1 window) (min (point) end)))
                         (line (buffer-substring-no-properties
                                line-start
                                (if (and (> line-fin line-start)
                                         (= (char-before line-fin) ?\n))
                                    (1- line-fin)
                                  line-fin)))
                         (length (length line))
                         (hstart (proto-ui--column-index line hscroll))
                         (partial (not (proto-ui--printable-ascii line)))
                         (runs nil)
                         (index hstart)
                         (col 0)
                         (pixel-x 0)
                         (break-run nil)
                         (row-valid (and (> length hstart) (<= (string-bytes line) 256))))
                    (while (and row-valid (< index length))
                      (let* ((char (substring line index (1+ index)))
                             (ascii (string-match-p "\\`[\x20-\x7e]\\'" char))
                             (face (and ascii
                                        (get-char-property (+ line-start index) 'face)))
                             (char-width (and ascii
                                              (ignore-errors
                                                (string-pixel-width
                                                 (propertize char 'face face)))))
                             (colors (and ascii
                                          (proto-ui--face-colors
                                           face default-background default-font-file)))
                             (foreground (nth 0 colors))
                             (background (nth 1 colors))
                             (underline (nth 2 colors))
                             (strike (nth 3 colors))
                             (overline (nth 4 colors))
                             (underline-color (nth 5 colors))
                             (strike-color (nth 6 colors))
                             (overline-color (nth 7 colors))
                             (inverse (nth 8 colors))
                             (bold (nth 9 colors))
                             (italic (nth 10 colors))
                             (font-file (nth 11 colors))
                             (variable-pitch (nth 12 colors)))
                        (cond
                         ((null foreground)
                          (if ascii
                              (setq row-valid nil)
                            (setq partial t
                                  break-run t)))
                         ((and runs (not break-run)
                               (equal (plist-get (car runs) :foreground) foreground)
                               (equal (plist-get (car runs) :background) background)
                               (equal (plist-get (car runs) :underline) underline)
                               (equal (plist-get (car runs) :strike-through) strike)
                               (equal (plist-get (car runs) :overline) overline)
                               (equal (plist-get (car runs) :underline_color) underline-color)
                               (equal (plist-get (car runs) :strike_color) strike-color)
                               (equal (plist-get (car runs) :overline_color) overline-color)
                               (equal (plist-get (car runs) :inverse_video) inverse)
                               (equal (plist-get (car runs) :bold) bold)
                               (equal (plist-get (car runs) :italic) italic)
                               (equal (plist-get (car runs) :font_file) font-file))
                          (setcar runs (plist-put (car runs) :text
                                                  (concat (plist-get (car runs) :text)
                                                          char))))
                         (t (let ((run (list :window_id window-id :row row :column col
                                             :text char
                                             :foreground foreground)))
                              (when partial (setq run (plist-put run :partial t)))
                              (when font-file (setq run (plist-put run :font_file font-file)))
                              (when background (setq run (plist-put run :background background)))
                              (when underline (setq run (plist-put run :underline t)))
                              (when strike (setq run (plist-put run :strike-through t)))
                              (when overline (setq run (plist-put run :overline t)))
                              (when underline-color (setq run (plist-put run :underline_color underline-color)))
                              (when strike-color (setq run (plist-put run :strike_color strike-color)))
                              (when overline-color (setq run (plist-put run :overline_color overline-color)))
                              (when inverse (setq run (plist-put run :inverse_video t)))
                              (when bold (setq run (plist-put run :bold t)))
                              (when italic (setq run (plist-put run :italic t)))
                              (when variable-pitch (setq run (plist-put run :variable_pitch t)))
                              (push run runs))))
                        (setq runs (proto-ui--put-run-metrics runs char-width pixel-x))
                        (setq pixel-x (+ pixel-x (or char-width 0)))
                      (setq break-run nil)
                      (setq col (+ col (string-width (substring line index (1+ index)))))
                      (setq index (1+ index))))
                    (when (and row-valid runs
                               (<= (length runs) proto-ui--max-line-runs)
                               (<= (+ (length result) (length runs)) proto-ui--max-total-runs))
                      (setq result (append result (nreverse runs)))))
                  (setq row (1+ row))))
              ;; The window's chrome lines keep their own per-segment faces.
              (dolist (kind '(:mode_line :header_line :tab_line))
                (when (< (length result) proto-ui--max-total-runs)
                  (let ((chrome-runs (proto-ui--chrome-runs
                                      window default-background kind)))
                    (when (and chrome-runs
                               (<= (+ (length result) (length chrome-runs))
                                   proto-ui--max-total-runs))
                      (setq result (append result chrome-runs))))))))))
      (when result (vconcat result)))))

(defun proto-ui--region-highlights (frame)
  "Return bounded per-row active-region rectangles as a vector, or nil.

The region is applied by redisplay rather than by a property, and a multi-line
region is not a rectangle, so each visible displayed row the region touches gets
its own rectangle covering exactly the selected part of that row; the frontend
draws one bounded highlight record per rectangle."
  (when (and (frame-live-p frame) transient-mark-mode mark-active (mark t))
    (let* ((window (selected-window))
           (start (min (mark t) (point)))
           (end (max (mark t) (point)))
           (char-width (max 1 (frame-char-width frame)))
           (char-height (max 1 (frame-char-height frame)))
           (rects nil))
      (with-selected-window window
        (save-excursion
          (goto-char start)
          (while (and (< (length rects) 8) (< (point) end))
            (let* ((row-start (point))
                   (row-end (progn (end-of-visual-line) (point)))
                   (seg-start (max row-start start))
                   (seg-end (min row-end end))
                   (last (max seg-start (1- (max seg-end (1+ seg-start)))))
                   (first (ignore-errors (posn-at-point seg-start)))
                   (second (ignore-errors (posn-at-point last)))
                   (xy1 (and first (ignore-errors (posn-x-y first))))
                   (xy2 (and second (ignore-errors (posn-x-y second)))))
              (when (and (consp xy1) (consp xy2))
                (let ((x (car xy1))
                      (width (+ (- (car xy2) (car xy1)) char-width))
                      (y (cdr xy1)))
                  (when (and (>= x 0) (> width 0) (<= width 4096)
                             (>= y 0) (<= y 4096))
                    (push (list :x x :y y :width width :height char-height) rects))))
              (if (= row-end row-start)
                  (goto-char (point-max))
                (goto-char (if (and (< row-end (point-max))
                                    (= (char-after row-end) ?\n))
                               (1+ row-end)
                             row-end)))))))
      (vconcat (nreverse rects)))))

(defun proto-ui--bounded-echo (frame)
  "Return FRAME's current echo-area text as a bounded string, or nil."
  (when (frame-live-p frame)
    (let ((message (ignore-errors (current-message))))
      (when (and (stringp message) (> (length message) 0)
                 (<= (string-bytes message) 120))
        message))))

(defun proto-ui--mouse-face-span (point mouse-face)
  "Return the (START . END) positions of POINT's contiguous MOUSE-FACE span.

The walk is bounded to 400 characters in each direction so a whole-buffer
mouse-face overlay cannot make one publish scan unbounded."
  (let ((start point) (end (1+ point)) (limit 400) (steps 0))
    (while (and (> start (point-min)) (< steps limit)
                (eq (get-char-property (1- start) 'mouse-face) mouse-face))
      (setq start (1- start))
      (setq steps (1+ steps)))
    (setq steps 0)
    (while (and (< end (point-max)) (< steps limit)
                (eq (get-char-property end 'mouse-face) mouse-face))
      (setq end (1+ end))
      (setq steps (1+ steps)))
    (cons start end)))

(defun proto-ui--mouse-face-highlight (frame)
  "Return the mouse-face highlight under the pointer as a plist, or nil.

The pointer position comes from the last observed pointer sample (the mirror's
own hover motion), so this is the text the real frame would highlight under the
mouse.  A mouse-face span can cover several displayed rows (a button, a link, or
any multi-line overlay), so it is reported as one bounded rectangle per
displayed row, exactly like the active region."
  (when (and (frame-live-p frame) (consp proto-ui--pointer-position))
    (let* ((x (car proto-ui--pointer-position))
           (y (cdr proto-ui--pointer-position))
           (target (proto-ui--pointer-window-at frame x y))
           (window (car target))
           (window-x (car (cdr target)))
           (window-y (cdr (cdr target))))
      (when (and window (numberp window-x) (numberp window-y))
        (condition-case nil
            (let* ((posn (posn-at-x-y window-x window-y window))
                   (point (posn-point posn))
                   (buffer (window-buffer window))
                   (mouse-face (and (integerp point)
                                    (with-current-buffer buffer
                                      (get-char-property point 'mouse-face)))))
              (when mouse-face
                (let* ((char-width (max 1 (frame-char-width frame)))
                       (char-height (max 1 (frame-char-height frame)))
                       (background
                        (proto-ui--bounded-color
                         (ignore-errors (face-attribute mouse-face :background nil t))))
                       (span (with-current-buffer buffer
                               (proto-ui--mouse-face-span point mouse-face)))
                       (rects (proto-ui--mouse-face-rects
                               window (car span) (cdr span) char-width char-height)))
                  (when (> (length rects) 0)
                    (append (list :rects rects)
                            (when background (list :background background)))))))
          (error nil))))))

(defun proto-ui--mouse-face-rects (window start end char-width char-height)
  "Return bounded per-row rectangles for the mouse-face span START..END.

Each displayed row the span touches yields one rectangle covering exactly the
highlighted part of that row, matching `proto-ui--region-highlights'.  A real
display reports exact pixels through `posn-at-point'; a batch/TTY frame has no
posn, so the rect falls back to the frame's character cell."
  (let ((rects nil)
        (row-base (ignore-errors (count-screen-lines (window-start window) start)))
        (row 0))
    (setq row-base (or row-base 0))
    (with-selected-window window
      (save-excursion
        (goto-char start)
        (while (and (< (length rects) 8) (< (point) end))
          (let* ((row-start (point))
                 ;; A batch/TTY frame has no visual-line layout, so
                 ;; `end-of-visual-line' does not move; fall back to the
                 ;; logical line end, which is the displayed row there.
                 (row-end (progn (end-of-visual-line)
                                 (if (> (point) row-start)
                                     (point)
                                   (line-end-position))))
                 (seg-start (max row-start start))
                 (seg-end (min row-end end))
                 (last (max seg-start (1- (max seg-end (1+ seg-start)))))
                 (first (ignore-errors (posn-at-point seg-start)))
                 (second (ignore-errors (posn-at-point last)))
                 (xy1 (and first (ignore-errors (posn-x-y first))))
                 (xy2 (and second (ignore-errors (posn-x-y second))))
                 (col (max 0 (- seg-start row-start)))
                 (chars (max 1 (- seg-end seg-start)))
                 (x (if (consp xy1) (car xy1) (* col char-width)))
                 (width (if (and (consp xy1) (consp xy2))
                            (+ (- (car xy2) (car xy1)) char-width)
                          (* chars char-width)))
                 (y (if (consp xy1) (cdr xy1) (* (+ row-base row) char-height))))
            (when (and (>= x 0) (> width 0) (<= width 4096)
                       (>= y 0) (<= y 4096))
              (push (list :x x :y y :width width :height char-height) rects))
            (setq row (1+ row))
            (let ((next (if (and (< row-end (point-max))
                                 (= (char-after row-end) ?\n))
                            (1+ row-end)
                          row-end)))
              (if (> next row-start)
                  (goto-char next)
                (forward-char 1))))))
    (vconcat (nreverse rects)))))

(defun proto-ui--default-font (frame)
  "Return FRAME's real default font as a bounded (FILE . PIXEL-SIZE) cons.

A display-backed frame resolves its font through fontconfig, and `font-info'
reports both the font file and its pixel size for that resolution; a frame whose
font is not file-backed (or a batch frame) yields nil so the frontend keeps its
own bundled fallback font."
  (let* ((font (and (frame-live-p frame)
                    (ignore-errors (face-attribute 'default :font frame t))))
         (info (and font (ignore-errors (font-info font))))
         (size (and (vectorp info) (> (length info) 2)
                    (integerp (aref info 2)) (aref info 2)))
         (file nil)
         (index 0))
    ;; The file element's position varies between Emacs builds, so take the
    ;; first existing font file the info vector names.
    (when (vectorp info)
      (while (and (< index (length info)) (null file))
        (let ((value (aref info index)))
          (when (and (stringp value)
                     (string-match-p "\\.\\(ttf\\|otf\\|ttc\\)\\'" value)
                     (file-readable-p value))
            (setq file value)))
        (setq index (1+ index))))
    (when (and file size (> (length file) 0) (<= (string-bytes file) 120)
               (>= size 1) (<= size 512)
               (not (string-match-p "[\x00-\x1f\x7f]" file)))
      (cons file size))))

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
         (if proto-ui--visible-edit
             (let ((point (window-point (selected-window))))
               (when (> point (point-min))
                 (goto-char point)
                 (delete-char -1)))
           (goto-char (point-max))
           (delete-char -1)))
        ("cursor-left" (backward-char 1))
        ("cursor-right" (forward-char 1))
        ("cursor-up" (forward-line -1))
        ("cursor-down" (forward-line 1))
        ("copy" (proto-ui--copy-first-line))
        (_ nil))
      (set-window-point (selected-window) (point))
      (redisplay))))

(defun proto-ui--resolve-keymap-pending ()
  (when proto-ui--keymap-pending
    (let* ((keys (vconcat proto-ui--keymap-pending))
           (binding (key-binding keys)))
      (unless (keymapp (indirect-function binding))
        (setq proto-ui--keymap-pending nil)
        (when binding
          (execute-kbd-macro keys))))))

(when (equal (getenv "PROTO_UI_KEYMAP_SELF_TEST") "1")
  (let ((command-ran nil)
        (prefix-key (vconcat (kbd "C-c z"))))
    (define-key global-map prefix-key
                (lambda ()
                  (interactive)
                  (setq command-ran t)))
    (setq proto-ui--keymap-pending prefix-key)
    (proto-ui--resolve-keymap-pending)
    (unless (and command-ran (null proto-ui--keymap-pending))
      (kill-emacs 1))
    (setq proto-ui--keymap-pending (vconcat (kbd "C-c M-m")))
    (proto-ui--resolve-keymap-pending)
    (unless (null proto-ui--keymap-pending)
      (kill-emacs 2))
    (message "proto-ui-keymap-self-test: pass")
    (kill-emacs 0)))

(defun proto-ui--key-v2-action (value)
  (let* ((event (condition-case nil
                    (json-parse-string value :object-type 'plist)
                  (error nil)))
         (state (plist-get event :state))
         (raw-command-key (plist-get event :command_key))
         (execution (plist-get event :execution)))
    (when (and (eql (plist-get event :schema) 2)
               (memq state '(1 3))
               (member execution '("command" "keymap"))
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
                  (let ((key-sequence (kbd command-key)))
                    (with-current-buffer (window-buffer (selected-window))
                      (if (equal execution "keymap")
                          ;; The display command loop is already blocked in
                          ;; read-char when a timer adds unread events.  Keep
                          ;; prefix state across timer ticks; Emacs's active
                          ;; keymaps resolve each complete sequence.
                          (when (<= (+ (length proto-ui--keymap-pending)
                                       (length key-sequence))
                                    64)
                            (setq proto-ui--keymap-pending
                                  (append proto-ui--keymap-pending
                                          (append key-sequence nil))))
                        ;; Rollback path for batch smoke drivers only.
                        (when (or (= (length key-sequence) 1)
                                  (and (= (length key-sequence) 2)
                                       (member command-key
                                               '("C-x 1" "C-x 2" "C-x 3" "C-x o"))))
                          (execute-kbd-macro key-sequence)))
                      (set-window-point (selected-window) (point))
                      (unless proto-ui--keymap-pending (redisplay))))
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
         ;; Pointer intents arrive in frame-logical coordinates, so map them
         ;; through the owning window the same way for every pointer path; the
         ;; generic flag only decides whether the dragged window is selected.
         (target (and (numberp x) (numberp y)
                      (proto-ui--pointer-window-at frame x y)))
         (window (car target))
         (window-x (if target (car (cdr target)) x))
         (window-y (if target (cdr (cdr target)) y))
         (buffer (if window (window-buffer window)
                   (window-buffer (selected-window))))
         (left-action-p (and (member phase '("press" "drag" "release"))
                             (eql buttons 1) (eql clicks 1) (eql modifiers 0))))
    ;; Any pointer sample (including idle hover motion) updates the position the
    ;; mouse-face highlight is resolved at.
    (when (and (numberp x) (numberp y))
      (setq proto-ui--pointer-position (cons x y)))
    (when (and window proto-ui--pointer-generic left-action-p target
               (not (eq window (selected-window))))
      (select-window window 'norecord))
    (when (and left-action-p target
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

(defun proto-ui--bounded-int (value limit)
  "Return VALUE truncated to an integer when it is a bounded number, else nil."
  (and (numberp value) (<= (- limit) value limit) (truncate value)))

(defun proto-ui--scroll-action (value)
  "Apply one bounded scroll intent to the window the intent names.

The live publisher reports scroll state in lines, so a relative delta is a
line count and the frontend's one-viewport trough page scrolls one screen.
On the horizontal axis the same bounded fields are columns, so a relative delta
adjusts `window-hscroll` and an absolute position sets it.
Unknown kinds, axes, windows, and unbounded numbers are ignored rather than
guessed."
  (let* ((event (proto-ui--json-plist value))
         (window_id (and event (plist-get event :window_id)))
         (axis (and event (plist-get event :axis)))
         (kind (and event (plist-get event :kind)))
         (position (and event (proto-ui--bounded-int (plist-get event :position) 1000000)))
         (delta (and event (proto-ui--bounded-int (plist-get event :delta) 1000)))
         (line (cond ((equal kind "absolute") position)
                     ((equal kind "relative") delta)
                     (t nil)))
         (horizontal (equal axis "horizontal"))
         (window (and (integerp window_id)
                      (seq-find (lambda (candidate)
                                  (eql (proto-ui-window-id candidate) window_id))
                                (window-list (selected-frame))))))
    (when (and window line (or (equal axis "vertical") horizontal))
      (if horizontal
          (condition-case nil
              (set-window-hscroll
               window
               (max 0 (if (equal kind "absolute")
                          line
                        (+ (window-hscroll window) line))))
            (error nil))
        (condition-case nil
            (progn
              (with-current-buffer (window-buffer window)
                (save-excursion
                  (goto-char (if (equal kind "absolute")
                                 (point-min)
                               (window-start window)))
                  (forward-line line)
                  (set-window-start window (point))))
              (when (or (< (window-point window) (window-start window))
                        (> (window-point window) (window-end window t)))
                (set-window-point window (window-start window))))
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
       ((and (= (length action) 3)
             (or (string= kind "scroll-request") (string= kind "scrollbar-event")))
        (proto-ui--scroll-action value))
       ((and (= (length action) 3) (string= kind "menu-open-request"))
        (proto-ui--menu-open-action value))
       ((and (= (length action) 3) (string= kind "menu-result"))
        (proto-ui--menu-result-action value))
       ((and (= (length action) 3) (string= kind "menu-cancel"))
        ;; The user dismissed the published popup, so it closes.
        (setq proto-ui--menu-open nil
              proto-ui--menu-open-commands nil
              proto-ui--menu-open-keymaps nil
              proto-ui--menu-open-path nil))
       ((and (= (length action) 3) (string= kind "pointer-v2"))
	(proto-ui--pointer-v2-action value))
       ((and (= (length action) 3) (string= kind "dnd-data"))
        (proto-ui--dnd-action value)))
      (when action
	(let ((coding-system-for-write 'utf-8))
	  (with-temp-file (concat proto-ui--input-path ".ack")
	    (insert (nth 0 action))))
	(delete-file proto-ui--input-path)))))

(defun proto-ui--face-color (attribute &optional face)
  "Return FACE's ATTRIBUTE as a bounded #rrggbb string.

The smoke profile pins deterministic colors so the SDL frontend face path can
be asserted end to end; otherwise the frame's real face attribute is used, and
an unusable or unspecified value yields nil so the frontend keeps its own draw
default.  A literal #rrggbb value is passed through unchanged: the terminal
color model must not remap a value the frame already stated exactly."
  (let ((value (if (and proto-ui--face-smoke (not face))
                   (if (eq attribute :foreground) "#102030" "#d0e0f0")
                 (condition-case nil
                     (face-attribute (or face 'default) attribute nil t)
                   (error nil)))))
    (proto-ui--bounded-color value)))

(defun proto-ui--bounded-color (value)
  "Return VALUE as a bounded #rrggbb string, or nil."
  (when (stringp value)
    (if (string-match-p "\\`#[0-9a-fA-F]\\{6\\}\\'" value)
        (downcase value)
      (let ((rgb (condition-case nil (color-values value) (error nil))))
        (when (and (listp rgb) (= (length rgb) 3)
                   (numberp (nth 0 rgb)) (numberp (nth 1 rgb)) (numberp (nth 2 rgb)))
          (format "#%02x%02x%02x"
                  (logand (ash (nth 0 rgb) -8) 255)
                  (logand (ash (nth 1 rgb) -8) 255)
                  (logand (ash (nth 2 rgb) -8) 255)))))))

(defun proto-ui--bounded-cursor-kind (frame)
  "Return the bounded EUP cursor kind for FRAME's cursor.

Kind 1 is the solid box, 2 the vertical bar, 3 the horizontal bar, 4 the hollow
box, and 5 the bottom-edge underline; anything Emacs reports that this bounded
set cannot express keeps the solid box.  The smoke profile pins a horizontal bar
so the SDL frontend face path can be asserted deterministically."
  (if proto-ui--cursor-smoke
      3
    (let* ((window (selected-window))
           (buffer (window-buffer window))
           (type (or (with-current-buffer buffer cursor-type)
                     (frame-parameter frame 'cursor-type))))
      (cond
       ((or (eq type t) (eq type 'box)
            (and (consp type) (eq (car type) 'box))) 1)
       ((or (eq type 'bar) (and (consp type) (eq (car type) 'bar))) 2)
       ((or (eq type 'hbar) (and (consp type) (eq (car type) 'hbar))) 3)
       ((or (eq type 'hollow) (and (consp type) (eq (car type) 'hollow))) 4)
       (t 1)))))

(defun proto-ui--menu-item-label (value)
  "Return the bounded label of a menu binding VALUE, or nil."
  (cond ((and (consp value) (stringp (car value))) (car value))
        ((and (consp value) (eq (car value) 'menu-item) (stringp (nth 1 value)))
         (nth 1 value))
        (t nil)))

(defun proto-ui--printable-menu-label (label)
  "Where LABEL is a bounded printable menu label."
  (and (stringp label) (> (length label) 0) (<= (string-bytes label) 64)
       (not (string-match-p "[\x00-\x1f\x7f]" label))))

(defun proto-ui--separator-label (label)
  "Where LABEL is an Emacs menu separator."
  (and (stringp label) (string-match-p "\\`-+\\'" label)))

(defun proto-ui--menu-bar-entries (frame)
  "Return FRAME's real top-level menu-bar entries as (LABEL . VALUE) conses.

A menu-bar row is reserved above the window, and `menu-bar-keymap' enumerates
its items in display order after the menu filters ran.  Items this bounded
publisher cannot express (the fallback click handler, non-string labels,
unbounded or non-printable labels) are skipped rather than guessed, so the
published position of an entry is its bounded menu id."
  (let ((entries nil))
    (when (and (frame-live-p frame)
               (> (or (frame-parameter frame 'menu-bar-lines) 0) 0))
      (let ((keymap (ignore-errors (menu-bar-keymap))))
        (when (keymapp keymap)
          (map-keymap
           (lambda (_key value)
             (let ((label (proto-ui--menu-item-label value)))
               (when (and (proto-ui--printable-menu-label label)
                          (< (length entries) 8))
                 (setq entries (cons (cons label value) entries)))))
           keymap))))
    (vconcat (nreverse entries))))

(defun proto-ui--menu-bar-labels (frame)
  "Return FRAME's bounded top-level menu-bar labels in display order."
  (let ((labels nil))
    (mapc (lambda (entry) (setq labels (cons (car entry) labels)))
          (proto-ui--menu-bar-entries frame))
    (vconcat (nreverse labels))))

(defun proto-ui--tool-bar-form (frame props key)
  "Return PROPS's KEY form evaluated for FRAME, or nil when absent.

The real tool bar evaluates its :enable/:visible forms in the selected window,
so this does the same and treats an absent form as nil; an erroring form keeps
nil rather than being guessed."
  (let ((form (plist-get props key)))
    (cond ((null form) nil)
          ((eq form t) t)
          (t (condition-case nil
                 (with-selected-window (frame-selected-window frame)
                   (eval form t))
               (error nil))))))

(defun proto-ui--tool-bar-items (frame)
  "Return FRAME's bounded tool-bar items in display order, or nil.

A menu-bar row is reserved above the window; the tool bar is the next strip.
Only the bounded subset this publisher can express is published: a separator,
a space, or a menu-item with a printable string name, a bounded command name,
and its :help.  The real :enable/:visible forms decide the flags, and :button
`:toggle' decides the toggle kind and selection, exactly as the frame's own
tool bar does; anything else is skipped rather than guessed."
  (when (and (frame-live-p frame)
             (> (or (frame-parameter frame 'tool-bar-lines) 0) 0))
    (let ((items nil))
      (map-keymap
       (lambda (_key value)
         (when (< (length items) 16)
           (let* ((separator (and (listp value) (equal value '("--"))))
                  (space (and (listp value) (equal value '(":space"))))
                  (props (and (consp value) (eq (car value) 'menu-item)
                              (nthcdr 3 value)))
                  (name (proto-ui--menu-item-label value))
                  (label (cond ((proto-ui--printable-menu-label name) name)
                               ((proto-ui--printable-menu-label (plist-get props :label))
                                (plist-get props :label)))))
             (cond
              (separator (setq items (cons (list :kind "separator"
                                                 :enabled :json-false)
                                           items)))
              (space (setq items (cons (list :kind "space"
                                             :enabled :json-false)
                                       items)))
              ((and (proto-ui--printable-menu-label label)
                    (not (proto-ui--separator-label label))
                    (or (null (plist-get props :visible)) visible))
               (let* ((command (and (consp value) (eq (car value) 'menu-item)
                                    (nth 2 value)))
                      (key (and (symbolp command)
                                (let ((name (symbol-name command)))
                                  (and (<= (length name) 16)
                                       (string-match-p "\\`[[:alnum:]-]+\\'" name)
                                       name))))
                      (help (plist-get props :help))
                      (visible (proto-ui--tool-bar-form frame props :visible))
                      (enabled (proto-ui--tool-bar-form frame props :enable))
                      (button (plist-get props :button))
                      (toggle (and (consp button) (eq (car button) :toggle)))
                      (selected (and toggle
                                     (let ((form (cdr button)))
                                       (and form
                                            (condition-case nil
                                                (with-selected-window
                                                    (frame-selected-window frame)
                                                  (eval form t))
                                              (error nil)))))))
                 (setq items
                       (cons (list :kind (if toggle "toggle" "button")
                                   :label label
                                   :key (or key "")
                                   :help (if (proto-ui--printable-menu-label help)
                                             help "")
                                   :enabled (if (null (plist-get props :enable))
                                                t
                                              (if enabled t :json-false))
                                   :selected (if selected t :json-false))
                             items))))))))
       tool-bar-map)
      (vconcat (nreverse items)))))

(defun proto-ui--menu-child-props (child)
  "Return the properties of a raw or normalized menu binding CHILD."
  (cond ((and (consp child) (eq (car child) 'menu-item))
         (nthcdr 3 child))
        ((and (consp child) (stringp (car child)) (consp (cdr child)))
         (nthcdr 2 child))
        (t nil)))

(defun proto-ui--menu-child-binding (child)
  "Return the binding CHILD contributes after applying its menu :filter.

A `menu-item' filter receives its current binding and may replace it or return
nil to remove the item.  This follows Emacs's own menu-item evaluation order;
an erroring filter removes the row rather than guessing a binding."
  (let* ((binding (cond ((and (consp child) (eq (car child) 'menu-item))
                         (nth 2 child))
                        ((and (consp child) (stringp (car child))
                              (consp (cdr child)))
                         (if (consp (cdr child)) (cadr child) (cdr child)))
                        ((vectorp child)
                         (and (> (length child) 1) (aref child 1)))
                        (t child)))
         (filter (plist-get (proto-ui--menu-child-props child) :filter)))
    (if filter
        (condition-case nil (funcall filter binding) (error nil))
      binding)))

(defun proto-ui--menu-child-command (child &optional binding)
  "Return the bounded command name of CHILD after its :filter, or nil."
  (let ((command (or binding (proto-ui--menu-child-binding child))))
    (and (symbolp command)
         (let ((name (symbol-name command)))
           (and (<= (length name) 64)
                (string-match-p "\\`[[:alnum:]-]+\\'" name)
                name)))))

(defun proto-ui--menu-child-keys (child &optional binding)
  "Return the bounded key hint CHILD's menu row shows, or nil.

Emacs shows a row's `:keys' string when it names one, and otherwise the first
real binding of its command (`where-is-internal'), which is what the frame's own
menu displays even for the stock items that set no `:keys'.  Anything not
expressible as a short printable string is dropped rather than guessed."
  (let* ((binding (or binding (proto-ui--menu-child-binding child)))
         (props (proto-ui--menu-child-props child))
         (raw (cond
               ((and props (stringp (plist-get props :keys)))
                (plist-get props :keys))
               ((and (symbolp binding) (not (eq binding 'undefined)))
                (let ((keys (ignore-errors (where-is-internal binding nil t))))
                  (and keys (ignore-errors (key-description keys))))))))
    (when (and (stringp raw) (> (length raw) 0)
               (<= (string-bytes raw) 32)
               (not (string-match-p "[\x00-\x1f\x7f]" raw)))
      raw)))

(defun proto-ui--menu-child-keymap (child &optional binding)
  "Return CHILD's resolved submenu keymap, or nil for a command row."
  (let ((binding (or binding (proto-ui--menu-child-binding child))))
    (and (keymapp binding) binding)))

(defun proto-ui--menu-child-visible-p (child binding)
  "Return whether CHILD's resolved BINDING should appear in its menu.

An absent :visible property is visible; a present property is evaluated in the
selected window exactly like Emacs's own menu.  A nil binding (including one
produced by :filter) is omitted."
  (let ((props (proto-ui--menu-child-props child)))
    (and (or (not (plist-member props :visible))
             (proto-ui--tool-bar-form (selected-frame) props :visible))
         (or (and binding (not (eq binding 'ignore)))
             (and (null (plist-get props :filter))
                  (proto-ui--separator-label
                   (proto-ui--menu-item-label child)))))))

(defun proto-ui--menu-icon-reference (image)
  "Return the bounded adapter-local ID for a valid IMAGE spec, or nil.

The ID is derived from the real image spec so equal specs share one resource.
Resource bytes are published separately; a missing or stale reference falls
back to the label."
  (and (consp image) (eq (car image) (quote image))
       (let ((id (logand (sxhash image) 4294967295)))
         (if (zerop id) 4294967295 id))))

;; P182 captures only tiny printable-ASCII XBM payloads.  Other real image
;; types remain label fallback until the frontend has a bounded decoder.
(defun proto-ui--menu-icon-payload (image)
  "Return base64 XBM bytes for a bounded file-backed IMAGE spec, or nil."
  (let ((file (and (consp image)
                   (eq (plist-get (cdr image) :type) 'xbm)
                   (plist-get (cdr image) :file))))
    (when-let* (((stringp file))
                (attributes (file-attributes file))
                ((<= (file-attribute-size attributes) 4096)))
      (ignore-errors
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (insert-file-contents-literally file)
          (base64-encode-string (buffer-string) t))))))

(defun proto-ui--menu-children (entry)
  "Return bounded child rows for the menu-bar ENTRY.

The value is a list of eleven parallel vectors: labels, bounded command names,
real `:enable' state, key hints, bounded `:help' text, adapter-local submenu
keymaps, stateful row kinds, real selection state, generation-qualified
icon references, and bounded XBM payload bytes.  Menu-item `:filter' and `:visible' are applied
in Emacs's order before enumeration; `:button' `:toggle'/`:radio' forms are
evaluated in the selected window.  Separators become \"--\" with no command and
a false enable flag.  Anything this bounded publisher cannot express is skipped
rather than guessed.  At most 24 rows are published."
  (let* ((value (cdr entry))
         (keymap (if (keymapp value)
                     value
                   (and (consp value) (keymapp (cdr value)) (cdr value))))
         (labels nil)
         (commands nil)
         (enabled nil)
         (keys nil)
         (helps nil)
         (submaps nil)
         (kinds nil)
         (selected nil)
         (icon-ids nil)
         (icon-generations nil)
         (icon-payloads nil))
    (when (keymapp keymap)
      (map-keymap
       (lambda (_key child)
         (let ((label (proto-ui--menu-item-label child))
               (binding (proto-ui--menu-child-binding child)))
           (when (and (< (length labels) 24)
                      (proto-ui--menu-child-visible-p child binding))
             (cond ((proto-ui--separator-label label)
                    (setq labels (cons "--" labels)
                          commands (cons "" commands)
                          enabled (cons :json-false enabled)
                          keys (cons "" keys)
                          helps (cons "" helps)
                          submaps (cons nil submaps)
                          kinds (cons "command" kinds)
                          selected (cons :json-false selected)
                          icon-ids (cons 0 icon-ids)
                          icon-generations (cons 0 icon-generations)
                          icon-payloads (cons "" icon-payloads)))
                   ((proto-ui--printable-menu-label label)
                    (let* ((props (proto-ui--menu-child-props child))
                           (button (plist-get props :button))
                           (kind (and (consp button)
                                      (cond ((eq (car button) :toggle) "toggle")
                                            ((eq (car button) :radio) "radio"))))
                           (help (plist-get props :help))
                           (icon-id (proto-ui--menu-icon-reference
                                     (plist-get props :image)))
                           (icon-payload (and icon-id
                                              (proto-ui--menu-icon-payload
                                               (plist-get props :image))))
                           (chosen (and kind
                                        (let ((form (cdr button)))
                                          (and form
                                               (condition-case nil
                                                   (with-selected-window
                                                       (frame-selected-window
                                                        (selected-frame))
                                                     (eval form t))
                                                 (error nil)))))))
                      (setq labels (cons label labels)
                            commands (cons (or (proto-ui--menu-child-command child binding) "")
                                           commands)
                            enabled (cons (if (null (plist-get props :enable))
                                              t
                                            (if (proto-ui--tool-bar-form (selected-frame) props :enable)
                                                t
                                              :json-false))
                                          enabled)
                            keys (cons (or (proto-ui--menu-child-keys child binding) "")
                                       keys)
                            helps (cons (if (proto-ui--printable-menu-label help)
                                            help
                                          "")
                                        helps)
                            submaps (cons (and (keymapp binding) binding)
                                          submaps)
                            kinds (cons (or kind "command") kinds)
                            selected (cons (if chosen t :json-false)
                                           selected)
                          icon-ids (cons (or icon-id 0) icon-ids)
                          icon-generations (cons (if icon-id 1 0)
                                                 icon-generations)
                          icon-payloads (cons (or icon-payload "")
                                              icon-payloads))))))))
       keymap))
    (list (vconcat (nreverse labels))
          (vconcat (nreverse commands))
          (vconcat (nreverse enabled))
          (vconcat (nreverse keys))
          (vconcat (nreverse helps))
          (vconcat (nreverse submaps))
          (vconcat (nreverse kinds))
          (vconcat (nreverse selected))
          (vconcat (nreverse icon-ids))
          (vconcat (nreverse icon-generations))
          (vconcat (nreverse icon-payloads)))))

(defconst proto-ui--menu-safe-commands
  '("undo" "undo-redo" "mark-whole-buffer" "keyboard-quit"
    "menu-bar--display-line-numbers-mode-visual"
    "menu-bar--display-line-numbers-mode-relative"
    "menu-bar--display-line-numbers-mode-absolute"
    "menu-bar--display-line-numbers-mode-none"
    "menu-bar--visual-line-mode-enable"
    "menu-bar--toggle-truncate-long-lines"
    "menu-bar--wrap-long-lines-window-edge")
  "Menu commands this bounded publisher may run from the live frontend.

Anything outside this closed set is resolved and recorded but never executed,
so an unattended publisher can never prompt for input or run an arbitrary
command.")

(defun proto-ui--menu-child-id-base (open)
  "Return the row ID base for OPEN's bounded popup depth."
  (+ 1000 (* 100 (length (plist-get open :path)))))

(defun proto-ui--menu-result-action (value)
  "Apply the bounded menu row choice in VALUE to the open menu.

The chosen wire id maps back to the published child row; its real command runs
only when it is in `proto-ui--menu-safe-commands', and the open menu closes
either way."
  (let* ((event (proto-ui--json-plist value))
         (item_id (and event (proto-ui--bounded-int (plist-get event :item_id) 2000)))
         (open proto-ui--menu-open)
         (base (and open (proto-ui--menu-child-id-base open)))
         (index (and open base
                     (let ((offset (- item_id base)))
                       (and (>= offset 0)
                            (< offset (length proto-ui--menu-open-commands))
                            offset))))
         (command (and index (aref proto-ui--menu-open-commands index))))
    (when (and command (member command proto-ui--menu-safe-commands))
      (condition-case nil
          (call-interactively (intern command))
        (error nil)))
    (setq proto-ui--menu-open nil
          proto-ui--menu-open-commands nil
          proto-ui--menu-open-keymaps nil
          proto-ui--menu-open-path nil)))
(defun proto-ui--menu-open-action (value)
  "Open the bounded menu-bar or nested submenu item named by VALUE.

The published popup carries real child rows from that item's keymap with a
bounded logical rectangle; the frontend draws and navigates it and reports the
chosen row, which closes the popup again."
  (let* ((event (proto-ui--json-plist value))
         (item_id (and event (proto-ui--bounded-int (plist-get event :item_id) 2000)))
         (window_id (and event (proto-ui--bounded-int (plist-get event :window_id) 100000)))
         (slot_x (and event (proto-ui--bounded-int (plist-get event :x) 10000)))
         (slot_y (and event (proto-ui--bounded-int (plist-get event :y) 10000)))
         (open proto-ui--menu-open)
         (child-base (and open (proto-ui--menu-child-id-base open)))
         (nested (and open child-base (integerp item_id)
                      (>= item_id child-base)
                      (< item_id (+ child-base 24))
                      (< (length proto-ui--menu-open-path) 3)))
         (entries (proto-ui--menu-bar-entries (selected-frame)))
         (root-entry (and (integerp item_id) (>= item_id 1)
                          (<= item_id (length entries))
                          (aref entries (1- item_id))))
         (nested-index (and nested
                             (let ((offset (- item_id child-base)))
                               (and (>= offset 0)
                                    (< offset (length proto-ui--menu-open-keymaps))
                                    offset))))
         (nested-keymap (and nested-index
                             (aref proto-ui--menu-open-keymaps nested-index)))
         (nested-label (and nested-index open
                            (> (length (plist-get open :items)) nested-index)
                            (aref (plist-get open :items) nested-index)))
         (entry (cond ((and nested (keymapp nested-keymap) (stringp nested-label))
                       (cons nested-label nested-keymap))
                      (root-entry root-entry))))
    (unless nested (setq proto-ui--menu-open-path nil))
    (if (and entry (integerp window_id))
        (let* ((children (proto-ui--menu-children entry))
               (items (nth 0 children))
               (keys (nth 3 children))
               (helps (nth 4 children))
               (submaps (nth 5 children))
               (submenus (vconcat (mapcar (lambda (submap)
                                            (if submap t :json-false))
                                          submaps)))
               (widest 8))
          (dotimes (index (length items))
            (setq widest (max widest
                              (+ (length (aref items index))
                                 (if (> (length (aref keys index)) 0)
                                     (+ 2 (length (aref keys index)))
                                   0)))))
          (setq proto-ui--menu-open
                (append
                 (list :item_id item_id
                       :window_id window_id
                       :x (max 0 (or slot_x 0))
                       :y (if nested (max 1 (or slot_y 0)) 1)
                       :width (min 48 (+ widest 2))
                       :height (max 1 (length items))
                       :items items
                       :enabled (nth 2 children)
                       :keys keys
                       :helps helps
                       :submenu submenus
                       :kind (nth 6 children)
                       :selected (nth 7 children)
                       :icon_ids (nth 8 children)
               :icon_generations (nth 9 children)
               :icon_payloads (nth 10 children))
                 (when nested
                   (list :parent_id (or (plist-get open :parent_id)
                                        (plist-get open :item_id))
                         :parent_label nested-label)))
                proto-ui--menu-open-commands (nth 1 children)
                proto-ui--menu-open-keymaps (nth 5 children))
          (when nested
            (setq proto-ui--menu-open-path
                  (append proto-ui--menu-open-path
                          (list (list :id item_id :label nested-label))))
            (setq proto-ui--menu-open
                  (plist-put proto-ui--menu-open :path
                             (apply #'vector proto-ui--menu-open-path)))))
      (setq proto-ui--menu-open nil
            proto-ui--menu-open-commands nil
            proto-ui--menu-open-keymaps nil
            proto-ui--menu-open-path nil))))

(defun proto-ui--publish-facts (frame)
  (let* ((window (selected-window))
         (buffer (window-buffer window))
         (start (window-start window))
         (end (window-end window t))
        (text (with-current-buffer buffer
                (buffer-substring-no-properties start end)))
         (flat-hscroll (window-hscroll window))
         (lines (mapcar (lambda (line) (proto-ui--hscroll-trim line flat-hscroll))
                        (proto-ui--display-lines window start text)))
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
          (min 9 (max 0 (- (with-current-buffer buffer
                             (save-excursion
                               (goto-char point)
                               (current-column)))
                           flat-hscroll))))
         (facts (proto-ui--json-plist
                 (proto-ui-frame-facts frame)))
         (windows (plist-get
                   (proto-ui--json-plist
                    (proto-ui-window-facts frame))
                   :windows))
         (window-states (proto-ui--window-states frame))
         (cursor (list :line cursor-line :column cursor-column))
         (title (proto-ui--bounded-title frame))
         (foreground (proto-ui--face-color :foreground))
         (background (proto-ui--face-color :background))
         (mode-line-foreground (proto-ui--face-color :foreground 'mode-line))
         (mode-line-background (proto-ui--face-color :background 'mode-line))
         (mode-line-inactive-foreground
          (proto-ui--face-color :foreground 'mode-line-inactive))
         (mode-line-inactive-background
          (proto-ui--face-color :background 'mode-line-inactive))
         (header-line-foreground (proto-ui--face-color :foreground 'header-line))
         (header-line-background (proto-ui--face-color :background 'header-line))
         (tab-line-foreground (proto-ui--face-color :foreground 'tab-line))
         (tab-line-background (proto-ui--face-color :background 'tab-line))
         (has-tool-bar (> (or (frame-parameter frame 'tool-bar-lines) 0) 0))
         (tool-bar-foreground (and has-tool-bar
                                   (proto-ui--face-color :foreground 'tool-bar)))
         (tool-bar-background (and has-tool-bar
                                   (proto-ui--face-color :background 'tool-bar)))
         (mode-line-box (proto-ui--box-style (face-attribute 'mode-line :box nil t)))
         (mode-line-box-width (proto-ui--box-width (face-attribute 'mode-line :box nil t)))
         (tool-bar-box (and has-tool-bar
                (proto-ui--box-style (face-attribute 'tool-bar :box nil t))))
         (tool-bar-box-width (and has-tool-bar
                (proto-ui--box-width (face-attribute 'tool-bar :box nil t))))
         (cursor-background (proto-ui--face-color :background 'cursor))
         (fringe-background (proto-ui--face-color :background 'fringe))
         (default-font (proto-ui--default-font frame))
         (regions (proto-ui--region-highlights frame))
         (mouse (proto-ui--mouse-face-highlight frame))
         (echo (proto-ui--bounded-echo frame))
         (line-runs (proto-ui--line-runs frame))
         (variable-font-file
          (let ((fonts (delq nil (mapcar
                                  (lambda (run) (plist-get run :font_file))
                                  (append line-runs nil)))))
            (car fonts)))
         (region-background (and (> (length regions) 0)
                                 (proto-ui--face-color :background 'region)))
         (cursor-kind (proto-ui--bounded-cursor-kind frame))
         (menu-bar (proto-ui--menu-bar-labels frame))
         (tool-bar (proto-ui--tool-bar-items frame))
         (line-height (let ((height (and (frame-live-p frame)
                                         (ignore-errors (frame-char-height frame)))))
                        (and (integerp height) (> height 1) (<= height 512)
                             height)))
         (char-width (let ((width (and (frame-live-p frame)
                                       (ignore-errors (frame-char-width frame)))))
                       (and (integerp width) (> width 0) (<= width 256)
                            width)))
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
	(when foreground (plist-put wire :foreground foreground))
	(when background (plist-put wire :background background))
	(when mode-line-foreground
	  (plist-put wire :mode_line_foreground mode-line-foreground))
	(when mode-line-background
	  (plist-put wire :mode_line_background mode-line-background))
	(when mode-line-inactive-foreground
	  (plist-put wire :mode_line_inactive_foreground mode-line-inactive-foreground))
	(when mode-line-inactive-background
	  (plist-put wire :mode_line_inactive_background mode-line-inactive-background))
	(when header-line-foreground
	  (plist-put wire :header_line_foreground header-line-foreground))
	(when header-line-background
	  (plist-put wire :header_line_background header-line-background))
	(when tab-line-foreground
	  (plist-put wire :tab_line_foreground tab-line-foreground))
	(when tab-line-background
	  (plist-put wire :tab_line_background tab-line-background))
	(when cursor-background
	  (plist-put wire :cursor_background cursor-background))
	(when fringe-background
	  (plist-put wire :fringe_background fringe-background))
	(when default-font
	  (plist-put wire :font_file (car default-font))
	  (plist-put wire :font_pixel_size (cdr default-font)))
	(when line-runs
	  (plist-put wire :line_runs line-runs))
	(when (> (length regions) 0)
	  (plist-put wire :regions regions)
	  (when region-background
	    (plist-put wire :region_background region-background)))
	(when echo
	  (plist-put wire :echo echo))
	(when mouse
	  (plist-put wire :mouse_rects (plist-get mouse :rects))
	  (when (plist-get mouse :background)
	    (plist-put wire :mouse_background (plist-get mouse :background))))
	(plist-put wire :cursor_kind cursor-kind)
	(when (> (length menu-bar) 0)
	  (plist-put wire :menu_bar menu-bar))
	(when (> (length tool-bar) 0)
	  (plist-put wire :tool_bar tool-bar))
	(when tool-bar-foreground
	  (plist-put wire :tool_bar_foreground tool-bar-foreground))
	(when tool-bar-background
	  (plist-put wire :tool_bar_background tool-bar-background))
	(when (and mode-line-box (not (equal mode-line-box "none")))
	  (plist-put wire :mode_line_box mode-line-box)
	  (when (> mode-line-box-width 0)
	    (plist-put wire :mode_line_box_width mode-line-box-width)))
	(when (and tool-bar-box (not (equal tool-bar-box "none")))
	  (plist-put wire :tool_bar_box tool-bar-box)
	  (when (> (or tool-bar-box-width 0) 0)
	    (plist-put wire :tool_bar_box_width tool-bar-box-width)))
	(when proto-ui--menu-open
	  (plist-put wire :menu_open proto-ui--menu-open))
	(when variable-font-file
	  (plist-put wire :variable_font_file variable-font-file))
	(when line-height
	  (plist-put wire :line_height line-height))
	(when char-width
	  (plist-put wire :char_width char-width))
	(with-temp-file temporary-path
	  (insert (json-encode wire))))
      (rename-file temporary-path proto-ui--facts-path t))))

(defun proto-ui--menu-filter-self-test ()
  "Prove bounded menu enumeration filters visibility and bindings."
  (let* ((keymap
          (list 'keymap
                '(menu-item "Visible" undo :visible t)
                '(menu-item "--" nil)
                '(menu-item "Hidden" undo :visible nil)
                '(menu-item "Filtered" undo
                            :filter (lambda (_) 'undo))
                '(menu-item "Filtered Away" undo
                            :filter (lambda (_) nil))
                '(menu-item "Erroring" undo
                            :filter (lambda (_) (error "omit")))))
         (children (proto-ui--menu-children (cons "Probe" keymap))))
    (unless (and (equal (aref (nth 0 children) 0) "Visible")
                 (equal (aref (nth 0 children) 1) "--")
                 (equal (aref (nth 0 children) 2) "Filtered")
                 (= (length (nth 0 children)) 3)
                 (equal (aref (nth 1 children) 0) "undo")
                 (equal (aref (nth 1 children) 2) "undo")
                 (eq (aref (nth 2 children) 0) t)
                 (eq (aref (nth 2 children) 2) t)
                 (equal (aref (nth 3 children) 2) "C-x u")
                 (null (aref (nth 5 children) 2)))
      (kill-emacs 1))
    (message "proto-ui-menu-filter-unit: pass")))

(defun proto-ui--menu-icon-self-test ()
  "Prove bounded popup rows carry real generation-qualified icon references."
  (let* ((icon (list 'image :type 'xbm
                     :file "etc/images/gnus/preview.xbm"))
         (other-icon (list 'image :type 'xpm :file "proto-ui-other.xpm"))
         (children (proto-ui--menu-children
                    (cons "Probe"
                          (list 'keymap
                                (list 'menu-item "Icon" 'undo :image icon)
                                (list 'menu-item "Other" 'undo :image other-icon)
                                '(menu-item "Plain" undo))))))
    (unless (and (= (length children) 11)
	                 (equal (aref (nth 8 children) 0)
	                        (logand (sxhash icon) 4294967295))
                 (equal (aref (nth 9 children) 0) 1)
	                 (equal (aref (nth 8 children) 1)
	                        (logand (sxhash other-icon) 4294967295))
                 (equal (aref (nth 9 children) 1) 1)
                 (zerop (aref (nth 8 children) 2))
                 (zerop (aref (nth 9 children) 2))
                 (> (length (aref (nth 10 children) 0)) 0)
                 (string-match-p "_width 24"
                                 (base64-decode-string
                                  (aref (nth 10 children) 0)))
                 (zerop (length (aref (nth 10 children) 1)))
                 (zerop (length (aref (nth 10 children) 2))))
      (kill-emacs 1))
    (message "proto-ui-menu-icon-unit: pass")))

(defun proto-ui--menu-radio-self-test ()
  "Prove bounded popup rows carry real toggle and radio state."
  (let* ((keymap
          (list 'keymap
                '(menu-item "Toggle On" undo
                            :help "Undo last change"
                            :button (:toggle . t))
                '(menu-item "Radio Off" undo
                            :button (:radio . nil))
                '(menu-item "Radio On" undo
                            :button (:radio . t))
                '(menu-item "--" nil)
                '(menu-item "Group Two Off" undo
                            :button (:radio . nil))
                '(menu-item "Group Two On" undo
                            :button (:radio . t))))
         (children (proto-ui--menu-children (cons "Probe" keymap))))
    (unless (and (= (length children) 11)
                 (equal (aref (nth 4 children) 0) "Undo last change")
                 (equal (aref (nth 4 children) 1) "")
                 (equal (aref (nth 6 children) 0) "toggle")
                 (equal (aref (nth 6 children) 1) "radio")
                 (equal (aref (nth 6 children) 2) "radio")
                 (equal (aref (nth 6 children) 3) "command")
                 (equal (aref (nth 6 children) 4) "radio")
                 (equal (aref (nth 6 children) 5) "radio")
                 (eq (aref (nth 7 children) 0) t)
                 (eq (aref (nth 7 children) 1) :json-false)
                 (eq (aref (nth 7 children) 2) t)
                 (eq (aref (nth 7 children) 3) :json-false)
                 (eq (aref (nth 7 children) 4) :json-false)
                 (eq (aref (nth 7 children) 5) t))
      (kill-emacs 1))
    (message "proto-ui-menu-radio-unit: pass")))

(defun proto-ui--menu-submenu-self-test ()
  "Prove the bounded publisher can replace a popup through two submenu levels."
  (let ((child (list 'keymap '(menu-item "Inside" undo))))
    (setq proto-ui--menu-open
          (list :item_id 1 :items ["Sub"] :enabled [t] :keys [""])
          proto-ui--menu-open-commands [""]
          proto-ui--menu-open-keymaps (vector child)
          proto-ui--menu-open-path nil)
    (proto-ui--menu-open-action
     "{\"item_id\":1000,\"window_id\":1,\"x\":12,\"y\":4}")
    (unless (and proto-ui--menu-open
                 (= (plist-get proto-ui--menu-open :item_id) 1000)
                 (= (plist-get proto-ui--menu-open :parent_id) 1)
                 (equal (plist-get proto-ui--menu-open :parent_label) "Sub")
                 (equal (aref (plist-get proto-ui--menu-open :items) 0) "Inside")
                 (equal (aref (plist-get proto-ui--menu-open :submenu) 0) :json-false)
                 (= (length (plist-get proto-ui--menu-open :path)) 1))
      (kill-emacs 1))
    (setq proto-ui--menu-open
          (list :item_id 1000 :parent_id 1
                :items ["Nested"] :enabled [t] :keys [""]
                :submenu [t]
                :path (vector (list :id 1000 :label "Sub")))
          proto-ui--menu-open-commands [""]
          proto-ui--menu-open-keymaps
          (vector (list 'keymap '(menu-item "Deepest" undo)))
          proto-ui--menu-open-path
          (list (list :id 1000 :label "Sub")))
    (proto-ui--menu-open-action
     "{\"item_id\":1100,\"window_id\":1,\"x\":52,\"y\":6}")
    (unless (and proto-ui--menu-open
                 (= (plist-get proto-ui--menu-open :item_id) 1100)
                 (= (plist-get proto-ui--menu-open :parent_id) 1)
                 (equal (plist-get proto-ui--menu-open :items) ["Deepest"])
                 (= (length (plist-get proto-ui--menu-open :path)) 2)
                 (equal (plist-get (aref (plist-get proto-ui--menu-open :path) 1)
                                   :label)
                        "Nested"))
      (kill-emacs 1))
    (setq proto-ui--menu-open nil
          proto-ui--menu-open-commands nil
          proto-ui--menu-open-keymaps nil
          proto-ui--menu-open-path nil)
    (message "proto-ui-menu-submenu-unit: pass")))

(when (getenv "PROTO_UI_MENU_FILTER_TEST")
  (proto-ui--menu-filter-self-test)
  (proto-ui--menu-submenu-self-test)
  (kill-emacs 0))

(when (getenv "PROTO_UI_MENU_RADIO_TEST")
  (proto-ui--menu-icon-self-test)
  (proto-ui--menu-radio-self-test)
  (kill-emacs 0))

(defun proto-ui--menu-radio-apply-self-test ()
  "Prove an allowlisted radio command owns its group's next publication."
  (let* ((entry (cons "Line Numbers" menu-bar-showhide-line-numbers-menu))
         (choose (lambda (menu-entry command-name expected)
                   (let* ((children (proto-ui--menu-children menu-entry))
                          (commands (nth 1 children))
                          (index (catch 'found
                                   (dotimes (index (length commands))
                                     (when (equal (aref commands index) command-name)
                                       (throw 'found index)))
                                   nil)))
                     (unless (and (integerp index)
                                  (< index (length (nth 0 children))))
                       (kill-emacs 1))
                     (setq proto-ui--menu-open
                           (list :item_id 1 :window_id 1 :x 0 :y 1
                                 :width 24 :height (length (nth 0 children))
                                 :items (nth 0 children)
                                 :enabled (nth 2 children)
                                 :keys (nth 3 children)
                                 :helps (nth 4 children)
                                 :submenu (nth 5 children)
                                 :kind (nth 6 children)
                                 :selected (nth 7 children))
                           proto-ui--menu-open-commands commands
                           proto-ui--menu-open-keymaps (nth 5 children)
                           proto-ui--menu-open-path nil)
                     (proto-ui--menu-result-action
                      (format "{\"item_id\":%d,\"window_id\":1}"
                              (+ 1000 index)))
                     (unless (null proto-ui--menu-open)
                       (kill-emacs 1))
                     (let ((next (proto-ui--menu-children menu-entry)))
                       (unless (eq expected
                                   (catch 'found
                                     (dotimes (index (length (nth 6 next)))
                                       (when (and (equal (aref (nth 6 next) index) "radio")
                                                  (eq (aref (nth 7 next) index) t))
                                         (throw 'found (equal
                                                        (aref (nth 1 next) index)
                                                        command-name))))
                                     nil))
                         (kill-emacs 1)))))))
    (display-line-numbers-mode -1)
    (setq display-line-numbers-type nil)
    (funcall choose entry "menu-bar--display-line-numbers-mode-absolute" t)
    (funcall choose entry "menu-bar--display-line-numbers-mode-relative" t)
    (display-line-numbers-mode -1)
    (setq display-line-numbers-type nil)
    (let ((wrapping (cons "Line Wrapping" menu-bar-line-wrapping-menu)))
      (setq truncate-lines nil word-wrap nil)
      (when (bound-and-true-p visual-line-mode) (visual-line-mode -1))
      (funcall choose wrapping "menu-bar--visual-line-mode-enable" t)
      (funcall choose wrapping "menu-bar--toggle-truncate-long-lines" t)
      (setq truncate-lines nil word-wrap nil)
      (when (bound-and-true-p visual-line-mode) (visual-line-mode -1)))
    (message "proto-ui-menu-radio-apply-unit: pass")))

(when (getenv "PROTO_UI_MENU_RADIO_APPLY_TEST")
  (proto-ui--menu-radio-apply-self-test)
  (kill-emacs 0))

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
  (when proto-ui--menu-icon-smoke
    ;; The fixture row is appended after the stock rows so the existing
    ;; Undo-first selectable assertion remains the live smoke's target.
    (let* ((icon (list 'image
                       :type 'xbm
                       :file (expand-file-name
                              "images/gnus/gnus-pointer.xbm" data-directory)))
           (keymap (cddr (aref (proto-ui--menu-bar-entries
                                (selected-frame))
                               1))))
      (define-key-after keymap [proto-ui-icon]
        (list 'menu-item "Proto Icon" 'undo :image icon))))
  (when proto-ui--scrollbar-smoke
    ;; A batch frame never scrolls on its own, so the profile puts the window
    ;; on a known line and the publisher reads the real window-start back.
    ;; The buffer is extended well past the mirror's line cap so the
    ;; diagnostic scrollbar has real page/drag room at a fixed position.
    (with-current-buffer buffer
      (goto-char (point-max))
      (dotimes (index 170) (insert (format "\nmore %03d" index)))
      (goto-char (point-min))
      (forward-line 10)
      (set-window-start window (point))
      (set-window-point window (point))))
  (when proto-ui--hscroll-smoke
    ;; A batch frame has no horizontal scroll bar and no truncated line, so the
    ;; profile puts one long line at the top and a known horizontal offset.
    (goto-char (point-min))
    (insert (concat (make-string 100 ?x) "\n"))
    (set-window-start window (point-min))
    (goto-char (point-min))
    (set-window-point window (point-min))
    (set-window-hscroll window 5))
  (when proto-ui--runs-smoke
    ;; Font-lock only fontifies a display-backed frame, so the profile puts
    ;; three Lisp lines first: their string and comment runs are the live
    ;; material, and three rows prove the multi-row publication.
    (with-current-buffer buffer
      (goto-char (point-min))
      (unless (looking-at-p "(message")
        (insert (concat "(message \"proto\") ; note\n"
                        "(message \"second\") ; note2\n"
                        "(message \"third\") ; note3\n")))
      ;; A mixed ASCII/non-ASCII line keeps its plain text (the bounded run wire
      ;; is ASCII-only, so a run for the CJK part would reject the snapshot)
      ;; while its ASCII span still gets the keyword face as a partial run.
      (unless (save-excursion (goto-char (point-min))
                              (search-forward "你好" nil t))
        (goto-char (point-min))
        (search-forward "Emacs Proto-UI")
        (end-of-line)
        (insert "\n你好 note4"))
      ;; A blank line and the row after it prove that a blank row keeps its
      ;; index instead of shifting the rows after it.  The over-long lines come
      ;; last so they never move the coloured rows out of the bounded run
      ;; budget, whatever display width wraps them into.
      (unless (save-excursion (goto-char (point-min))
                              (search-forward "BLANKMARK" nil t))
        (goto-char (point-min))
        (search-forward "visible ASCII textZ")
        (end-of-line)
        (insert (concat "\nBLANKMARK\n\nALIGNMARK\n"
                        (make-string 200 ?x) "\n\n"
                        (make-string 4000 ?x))))
      ;; One span carries a real face background so the mirror's run-background
      ;; fill is proven from live facts, not just foreground colors.
      (defface proto-ui-runs-background-face
        '((t :foreground "#000000" :background "#204060"))
        "Deterministic background face for the font-lock run smoke.")
      (defface proto-ui-runs-underline-face
        '((t :foreground "#a00000" :underline (:color "#00a0a0")))
        "Deterministic underlined face for the font-lock run smoke.")
      (defface proto-ui-runs-inverse-face
        '((t :foreground "#1188cc" :background "#e0f0ff" :inverse-video t))
        "Deterministic inverse-video face for the font-lock run smoke.")
      (defface proto-ui-runs-style-face
        '((t :foreground "#335577" :weight bold :slant italic))
        "Deterministic bold-italic face for the font-lock run smoke.")
      (defface proto-ui-runs-overlay-face
        '((t :foreground "#cc5500"))
        "Deterministic overlay face for the font-lock run smoke.")
      (defface proto-ui-runs-variable-face
        '((t :foreground "#007700" :font "DejaVu Serif-13"))
        "Deterministic distinct file-backed face for variable-pitch runs.")
      ;; An overlay face outranks the text property, so this proves the
      ;; publisher resolves overlay-aware faces.
      (when proto-ui--runs-smoke
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-min))
            (forward-line 3)
            (let ((overlay (make-overlay (point) (+ (point) 7) nil t)))
              (overlay-put overlay 'face 'proto-ui-runs-overlay-face)))))
      ;; The face is applied by font-lock itself (not a manual text property),
      ;; so refontification keeps it instead of overwriting it.
      (font-lock-add-keywords
       nil '(("note[0-9]*" (0 'proto-ui-runs-background-face t))
             ("\"second\"" (0 'proto-ui-runs-underline-face t))
             ("\"proto\"" (0 'proto-ui-runs-inverse-face t))
             ("\"third\"" (0 'proto-ui-runs-style-face t))))
      (font-lock-ensure)
      ;; Put the variable-pitch pin on after font-lock so redisplay does not
      ;; rewrite the face property before the publisher samples it.
      (let (start end)
          (goto-char (point-min))
          (search-forward "ASCII")
          (setq start (match-beginning 0) end (match-end 0))
        (let ((overlay (make-overlay start end nil t)))
          (overlay-put overlay 'face 'proto-ui-runs-variable-face)
))))
  (when proto-ui--region-smoke
    ;; A batch-free profile pins a multi-line active region so the per-row
    ;; highlight path can be asserted deterministically; real sessions report
    ;; their own (a single-line region simply yields one rectangle).  It sits
    ;; on plain rows so it cannot disturb the font-lock pins above it.
    (with-current-buffer buffer
      (goto-char (point-min))
      (forward-line 9)
      (forward-char 2)
      (push-mark (point) t)
      (forward-line 2)
      (forward-char 3)
      (activate-mark)))
  (when proto-ui--header-smoke
    ;; The mirror draws header/tab aux lines only when the real frame has
    ;; them, and the chrome runs must carry their segment faces; the profile
    ;; pins both with a deterministic accent face so the run path is asserted
    ;; (its color can only come from the run, not the plain aux-text fallback).
    (defface proto-ui-header-accent-face
      '((t :foreground "#0e6b3a"))
      "Deterministic header-line segment face for the chrome run smoke.")
    (defface proto-ui-tab-accent-face
      '((t :foreground "#7a2ca0"))
      "Deterministic tab-line segment face for the chrome run smoke.")
    (setq header-line-format
          (propertize "ProtoHeader" 'face 'proto-ui-header-accent-face))
    (setq tab-line-format
          (propertize "ProtoTab" 'face 'proto-ui-tab-accent-face))
    (redisplay))
  (when proto-ui--mouse-smoke
    ;; Pin a mouse-face overlay that spans several displayed rows.  Redisplay
    ;; removes mouse-face *text* properties after drawing, so the span must
    ;; live on an overlay, which is also how real buttons and links carry it.
    ;; The smoke drives a real pointer sample at (2 . 1); with no header line
    ;; that lands on the first row, so the mouse-face highlight path has a
    ;; live, deterministic source, and the span's newlines force the per-row
    ;; rectangle path.
    (defface proto-ui-mouse-face
      '((t :background "#33aa77"))
      "Deterministic mouse-face for the pointer highlight smoke.")
    (with-current-buffer buffer
      (goto-char (point-min))
      (make-overlay (point-min) (min (point-max) (+ (point-min) 40)))
      (overlay-put (car (overlays-at (point-min))) 'mouse-face 'proto-ui-mouse-face)))
  (when proto-ui--echo-smoke
    ;; The echo area is the frame's bottom strip; pin a deterministic message.
    (message "ProtoEcho"))
  ;; The smoke setup is not user state: only edits the frontend itself sends
  ;; (and therefore may ask the real Edit->Undo row to undo) stay undoable.
  (with-current-buffer buffer (setq buffer-undo-list nil))
  (when (equal (getenv "PROTO_UI_TITLE_SMOKE") "1")
    (set-frame-parameter frame 'title "Emacs Proto-UI Title"))
  (if (display-graphic-p)
      (let ((proto-ui--publish-tick
             (lambda ()
               (proto-ui--consume-input)
               (proto-ui--resolve-keymap-pending)
               (proto-ui--publish-facts frame))))
        ;; A real frame returns to Emacs's top-level command loop.  The timer
        ;; publishes observations and queues reverse input; Emacs itself reads
        ;; queued key events and owns all keymap/prefix semantics.
        (run-with-timer 0 0.05 proto-ui--publish-tick))
    (while t
      (setq window (frame-selected-window frame)
            buffer (window-buffer window))
      (proto-ui--consume-input)
      (proto-ui--resolve-keymap-pending)
      (proto-ui--publish-facts frame)
      (sit-for 0.1))))

(provide 'proto-ui-facts-publisher)
;;; facts_publisher.el ends here
