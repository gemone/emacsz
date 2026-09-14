;;; tpe-frame-visibility.el --- Proto-UI frame visibility smoke -*- lexical-binding: t; -*-

(defun proto-ui-tpe-frame-visibility--wait (predicate timeout)
  "Wait until PREDICATE returns non-nil or TIMEOUT seconds elapse."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (read-event nil nil 0.2))
    (funcall predicate)))

(defun proto-ui-tpe-frame-visibility ()
  "Verify SDL minimize and restore map to Emacs frame visibility."
  (let* ((initial-frame (selected-frame))
         (terms (terminal-list))
         (terminal (car (last terms)))
         (frame (make-terminal-frame (list (cons 'terminal terminal))))
         (old-iconify (lookup-key special-event-map [iconify-frame]))
         (old-restore (lookup-key special-event-map [make-frame-visible]))
         (icon-events nil)
         (restore-events nil))
    (unless (and (frame-live-p frame) (terminal-provider-frame-p frame))
      (error "proto-ui-tpe-frame-visibility failed: attach=%S provider=%S"
             (frame-live-p frame) (terminal-provider-frame-p frame)))
    (select-frame frame)
    (unless (redisplay t)
      (error "proto-ui-tpe-frame-visibility failed: initial display"))
    (select-frame initial-frame)
    (define-key special-event-map [iconify-frame]
                (lambda (event)
                  (interactive "e")
                  (push event icon-events)))
    (define-key special-event-map [make-frame-visible]
                (lambda (event)
                  (interactive "e")
                  (push event restore-events)))
    (proto-ui-tpe-frame-visibility--wait
     (lambda ()
       (and (= (length icon-events) 1) (= (length restore-events) 1)))
     4)
    (define-key special-event-map [iconify-frame] old-iconify)
    (define-key special-event-map [make-frame-visible] old-restore)
    (unless (and
             (equal icon-events (list (list 'iconify-frame (list frame))))
             (equal restore-events
                    (list (list 'make-frame-visible (list frame))))
             (eq (frame-visible-p frame) t)
             (eq (frame-visible-p initial-frame) t))
      (error "proto-ui-tpe-frame-visibility failed: icon=%S restore=%S visible=%S initial=%S"
             icon-events restore-events
             (frame-visible-p frame) (frame-visible-p initial-frame)))
    (princ "proto-ui-tpe-frame-visibility: pass\n")))

;;; tpe-frame-visibility.el ends here
