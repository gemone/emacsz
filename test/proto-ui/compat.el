;;; compat.el --- Adapter-only Proto-UI Emacs compatibility gate -*- lexical-binding: t; -*-

;; This program runs a fixed, bounded set of base Emacs checks.  It is
;; deliberately independent of Proto-UI adapters, modules, terminals, and
;; output_proto.  Its only output is one JSON object on standard output.

(require 'json)

(defgroup proto-ui-compat nil
  "Base Emacs compatibility checks used by the Proto-UI gate."
  :group 'tools)

(defvar proto-ui-compat-face nil
  "Face used by the compatibility gate.")

(defface proto-ui-compat-face
  '((t :underline t))
  "Face used by the Proto-UI compatibility gate."
  :group 'proto-ui-compat)

(defvar proto-ui-compat-local-default nil
  "Default value checked by the buffer-local scenario.")

(defvar proto-ui-compat--details nil
  "Details returned by the currently running scenario.")

(defvar proto-ui-compat--load-file
  (or load-file-name buffer-file-name)
  "Path to this tracked compatibility program.")

(defun proto-ui-compat--json-string (value)
  "Return VALUE encoded as a JSON string by json.el."
  (json-encode (if (stringp value) value (format "%s" value))))

(defun proto-ui-compat--pass (details)
  "Record a successful scenario result with DETAILS."
  (setq proto-ui-compat--details details)
  t)

(defun proto-ui-compat--environment-display-p ()
  "Return non-nil when the environment names an available graphical display."
  (or (getenv "DISPLAY") (getenv "WAYLAND_DISPLAY")))

(defun proto-ui-compat--identity ()
  (proto-ui-compat--pass
   `((version . ,emacs-version)
     (system . ,system-configuration)
     (window_system . ,(symbol-name window-system))
     (selected_frame_type . ,(format "%S" (framep (selected-frame)))))))

(defun proto-ui-compat--buffer-undo ()
  (with-temp-buffer
    (setq buffer-undo-list nil)
    (insert "abc def")
    (delete-region 5 7)
    (let ((after-delete (buffer-string)))
      (let ((undo-entry (list (car buffer-undo-list)))
            (after-undo nil))
        (primitive-undo 1 undo-entry)
        (setq after-undo (buffer-string))
        (unless (string= after-undo "abc def")
          (error "undo produced %S" after-undo))
        (proto-ui-compat--pass
         `((deleted_text . ,after-delete)
           (undo_restored . ,(string= after-undo "abc def"))
           (undo_cleanup . t)))))))

(defun proto-ui-compat--point-mark-narrowing ()
  (with-temp-buffer
    (insert "abcdef")
    (goto-char 4)
    (set-mark 2)
    (let ((start-point (point)))
      (exchange-point-and-mark)
      (let ((exchanged-point (point))
            (mark-position (mark)))
        (narrow-to-region 2 5)
        (let ((narrow-min (point-min))
              (narrow-max (point-max))
              (narrow-point (point)))
          (widen)
          (unless (and (= exchanged-point 2) (= mark-position 4)
                       (= narrow-min 2) (= narrow-max 5)
                       (= narrow-point 2))
            (error "point, mark, or narrowing mismatch"))
          (proto-ui-compat--pass
           `((point . ,start-point)
             (exchanged_point . ,exchanged-point)
             (mark . ,mark-position)
             (narrow_min . ,narrow-min)
             (narrow_max . ,narrow-max)
             (widen_max . ,(point-max)))))))))

(defun proto-ui-compat--text-overlays ()
  (with-temp-buffer
    (insert "hello proto")
    (put-text-property 1 6 'face 'bold)
    (let ((overlay (make-overlay 7 11)))
      (overlay-put overlay 'face 'highlight)
      (let ((text-face (get-text-property 1 'face))
            (overlay-face (get-char-property 8 'face)))
        (unless (and (eq text-face 'bold) (eq overlay-face 'highlight))
          (error "text or overlay property mismatch"))
        (delete-overlay overlay)
        (proto-ui-compat--pass
         `((text_face . ,text-face)
           (overlay_face . ,overlay-face)
           (overlay_deleted . ,(null (overlays-at 8)))))))))

(defun proto-ui-compat--face-readback (&optional frame)
  (set-face-attribute 'proto-ui-compat-face frame :underline t)
  (let ((readback (face-attribute 'proto-ui-compat-face :underline frame)))
    (unless (eq readback t) (error "face attribute readback mismatch"))
    `((underline . ,readback))))

(defun proto-ui-compat--face ()
  (proto-ui-compat--pass (proto-ui-compat--face-readback nil)))

(defun proto-ui-compat--window-management ()
  (let ((result
         (with-temp-buffer
           (insert "one two three")
           (goto-char 5)
           (let ((old-window (selected-window))
                 (buffer (current-buffer))
                 (old-marker (copy-marker (point))))
             (let ((new-window (split-window-below)))
               (set-window-buffer new-window buffer)
               (select-window new-window)
               (goto-char 2)
               (set-window-point new-window (point))
               (let ((new-point (window-point)))
                 (delete-window new-window)
                 (select-window old-window)
                 (unless (and (buffer-live-p buffer)
                              (= (marker-position old-marker) 5)
                              (= new-point 2))
                   (error "window identity, point, or cleanup mismatch"))
                 `((new_window_point . ,new-point)
                   (old_window_point . ,(point))
                   (old_marker_position . ,(marker-position old-marker))
                   (buffer_live . ,(buffer-live-p buffer)))))))))
    (proto-ui-compat--pass result)))

(defun proto-ui-compat--window-scroll (&optional frame)
  (when (and frame (not (frame-live-p frame)))
    (error "target frame is not live"))
  (let ((original-frame (selected-frame))
        (original-window (selected-window))
        (original-buffer (window-buffer))
        (original-point (point))
        (original-start (window-start))
        (buffer nil))
    (unwind-protect
        (let ((result
               (with-temp-buffer
                 (setq buffer (current-buffer))
                 (dotimes (line-number 80)
                   (insert (format "line-%02d\n" (1+ line-number))))
                 (let ((new-window (split-window-below)))
                   (set-window-buffer new-window buffer)
                   (select-window new-window)
                   (unwind-protect
                       (progn
                         (goto-char (point-min))
                         (forward-line 30)
                         (recenter 0)
                         (let ((after-recenter-start (window-start)))
                           (set-window-start nil (point-min) t)
                           (forward-line 20)
                           (recenter 0)
                           (let ((scrolled-start (window-start))
                                 (resized nil))
                             (let ((old-height (window-height)))
                               (window-resize nil 2 nil nil)
                               (setq resized (= (window-height) (+ old-height 2)))
                               (window-resize nil -2 nil nil))
                             (unless (and resized
                                          (/= scrolled-start after-recenter-start))
                               (error "scroll mismatch old=%S new=%S resized=%S"
                                      after-recenter-start scrolled-start resized))
                             `((recenter_start . ,after-recenter-start)
                               (scrolled_start . ,scrolled-start)
                               (resize . ,resized)))))
                     (delete-window new-window)
                     (select-window original-window))))))
          result)
      (set-window-buffer original-window original-buffer)
      (set-window-point original-window original-point)
      (set-window-start original-window original-start t)
      (select-frame original-frame))))

(defun proto-ui-compat--scroll ()
  (proto-ui-compat--pass (proto-ui-compat--window-scroll nil)))

(defun proto-ui-compat--buffer-local ()
  (with-temp-buffer
    (make-local-variable 'proto-ui-compat-local-default)
    (setq proto-ui-compat-local-default :local)
    (let ((local-value proto-ui-compat-local-default)
          (default-value-value (default-value 'proto-ui-compat-local-default)))
      (kill-local-variable 'proto-ui-compat-local-default)
      (unless (and (eq local-value :local) (null default-value-value)
                   (null proto-ui-compat-local-default))
        (error "buffer-local value or cleanup mismatch"))
      (proto-ui-compat--pass
       `((local_value . ,local-value)
         (default_value . ,default-value-value)
         (cleanup_value . ,proto-ui-compat-local-default))))))

(defun proto-ui-compat--pgtk-frame (&optional run-scenarios)
  "Run one real PGTK frame in a clean GUI child of this batch gate.
Batch-mode Emacs intentionally keeps its initial terminal on the TTY;
the child initializes PGTK while the parent remains the isolated JSON
reporter."
  (if (not (proto-ui-compat--environment-display-p))
      nil
    (let ((emacs (expand-file-name "emacs" invocation-directory))
          (source (or (and (stringp proto-ui-compat--load-file)
                           (expand-file-name proto-ui-compat--load-file))
                      (expand-file-name "test/proto-ui/compat.el"))))
      (let ((exit-code
             (apply #'call-process emacs nil nil nil
                    (append
                     (list "-Q"
                           "-d" (or (getenv "DISPLAY")
                                    (getenv "WAYLAND_DISPLAY"))
                           "-l" source
                           "-f")
                     (list (if run-scenarios
                               "proto-ui-compat--pgtk-ui-child"
                             "proto-ui-compat--pgtk-frame-child"))))))
        (unless (eq exit-code 0)
          (error "PGTK child failed with exit status %S" exit-code)))
      (proto-ui-compat--pass
       `((mode . gui_child)
         (frame_type . pgtk)
         (window_system . pgtk)
         (live_after_create . t)
         (live_after_delete . t))))))

(defun proto-ui-compat--pgtk-frame-child ()
  "Create, verify, delete, and exit from one real PGTK frame."
  (proto-ui-compat--pgtk-child-frame nil))

(defun proto-ui-compat--pgtk-ui-child ()
  "Create one PGTK frame and run window, scroll, and face checks."
  (proto-ui-compat--pgtk-child-frame t))

(defun proto-ui-compat--pgtk-child-frame (&optional run-scenarios)
  (let ((frame nil)
        (original-frame (selected-frame)))
    (unwind-protect
        (progn
          (setq frame (make-frame
                       '((name . "proto-ui-compat")
                         (width . 80)
                         (height . 24)
                         (visibility . t)
                         (undecorated . t))))
          (unless (and (frame-live-p frame) (eq (framep frame) 'pgtk))
            (error "created frame is not a live PGTK frame"))
          (select-frame frame)
          (redisplay t)
          (when run-scenarios
            (proto-ui-compat--window-scroll frame)
            (proto-ui-compat--face-readback frame))
          (select-frame original-frame)
          (delete-frame frame nil)
          (setq frame nil)
          (unless (not (frame-live-p frame))
            (error "PGTK frame cleanup failed"))
          (kill-emacs 0))
      (when (frame-live-p frame)
        (select-frame original-frame)
        (delete-frame frame nil)))))

(defvar proto-ui-compat--scenarios
  '((identity . proto-ui-compat--identity)
    (buffer_undo . proto-ui-compat--buffer-undo)
    (point_mark_narrowing . proto-ui-compat--point-mark-narrowing)
    (text_overlay_properties . proto-ui-compat--text-overlays)
    (face_definition_readback . proto-ui-compat--face)
    (window_split_select_delete . proto-ui-compat--window-management)
    (window_resize_scroll_recenter . proto-ui-compat--scroll)
    (buffer_local_variables . proto-ui-compat--buffer-local)
    (pgtk_frame_lifecycle . proto-ui-compat--pgtk-frame)
    (pgtk_window_scroll_face
     . (lambda () (proto-ui-compat--pgtk-frame t)))))

(defun proto-ui-compat--metadata ()
  `((emacs_version . ,emacs-version)
    (system . ,system-configuration)
    (window_system . ,(symbol-name window-system))
    (selected_frame_type . ,(format "%S" (framep (selected-frame))))))

(defun proto-ui-compat-run ()
  "Run all compatibility scenarios and print one JSON report."
  (let ((scenario-json nil)
        (failed nil))
    (dolist (scenario proto-ui-compat--scenarios)
      (let ((name (car scenario))
            (function (cdr scenario)))
        (let ((status nil)
              (details nil)
              (proto-ui-compat--details nil))
          (condition-case error-data
              (progn
                (when (funcall function)
                  (setq status "pass" details proto-ui-compat--details))
                (unless status
                  (setq status "skip" details '((reason . no_graphical_display)))))
            (error
             (setq status "fail"
                   details `((error . ,(error-message-string error-data))))))
          (when (string= status "fail") (setq failed t))
          (push `((name . ,(symbol-name name))
                  (status . ,status)
                  (details . ,details))
                scenario-json))))
    (princ (concat (json-encode-alist
                    `((schema . "proto-ui-compat-report/v1")
                      (kind . "proto-ui-compat-report")
                      (version . 1)
                      (emacs . ,(proto-ui-compat--metadata))
                      (scenarios . ,(apply #'vector (nreverse scenario-json)))
                      (overall . ,(if failed "fail" "pass"))))
                   "\n"))
    (kill-emacs (if failed 1 0))))

;;; compat.el ends here
