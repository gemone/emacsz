;;; proto-win.el --- Terminal provider input device support -*- lexical-binding: t; -*-

(defun proto-device-class (name)
  "Return the class of terminal provider device NAME."
  (cond
   ((not name) nil)
   ((string= name "proto:keyboard") 'keyboard)
   ((string= name "proto:mouse") 'mouse)
   ((string= name "proto:touchscreen") 'touchscreen)
   (t 'core-pointer)))

(provide 'proto-win)
(provide 'term/proto-win)

;;; proto-win.el ends here
