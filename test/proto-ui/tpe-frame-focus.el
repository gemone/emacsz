;;; tpe-frame-focus.el --- Proto-UI frame focus smoke -*- lexical-binding: t; -*-

(defun proto-ui-tpe-frame-focus ()
  "Verify SDL focus changes update a real Proto-UI Emacs frame."
  (let* ((initial-frame (selected-frame))
         (terms (terminal-list))
         (terminal (car (last terms)))
         (frame (make-terminal-frame (list (cons 'terminal terminal))))
         (focus-states nil))
    (unless (and (frame-live-p frame) (terminal-provider-frame-p frame))
      (error "proto-ui-tpe-frame-focus failed: attach=%S provider=%S"
             (frame-live-p frame) (terminal-provider-frame-p frame)))
    (select-frame frame)
    (unless (redisplay t)
      (error "proto-ui-tpe-frame-focus failed: display"))
    (select-frame initial-frame)
    (let ((after-focus-change-function
           (lambda ()
             (push (frame-parameter frame 'last-focus-update)
                   focus-states)))
          (deadline (+ (float-time) 3)))
      (while (and (< (length focus-states) 2)
                  (< (float-time) deadline))
        (read-event nil nil 0.2)))
    (unless (and (frame-live-p frame)
                 (>= (length focus-states) 2)
                 (equal (list (nth 0 focus-states) (nth 1 focus-states)) '(nil t)))
      (error "proto-ui-tpe-frame-focus failed: states=%S live=%S"
             focus-states (frame-live-p frame)))
    (princ "proto-ui-tpe-frame-focus: pass\n")))

;;; tpe-frame-focus.el ends here
