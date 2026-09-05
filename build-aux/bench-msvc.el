;;; bench-msvc.el --- Windows performance baseline benchmark -*- lexical-binding: t; -*-

;; Comprehensive performance benchmark for comparing GNU vs MSVC builds.
;; Run with: emacs --batch -l build-aux/bench-msvc.el

(message "=== Emacs Performance Benchmark ===")
(message "system-type: %S" system-type)
(message "system-configuration: %S" system-configuration)
(message "emacs-version: %S" emacs-version)

;; --- 1. Startup (implicit: time from process start to this point) ---

;; --- 2. Pure Lisp arithmetic (JIT/AOT hot path) ---
(defun bench-arithmetic (n)
  (let ((s 0))
    (dotimes (i n) (setq s (+ s (* i 3) (1+ i))))
    s))
(let ((t0 (float-time)))
  (bench-arithmetic 500000)
  (message "BM arithmetic-500k: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 3. Recursion (function call overhead) ---
(defun bench-fib (n) (if (< n 2) n (+ (bench-fib (1- n)) (bench-fib (- n 2)))))
(let ((t0 (float-time)))
  (bench-fib 22)
  (message "BM fib22: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 4. List operations ---
(let ((t0 (float-time)))
  (let ((l (number-sequence 1 100000)))
    (length (sort l #'<)))
  (message "BM sort-100k: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 5. String operations ---
(let ((t0 (float-time)))
  (let ((s (make-string 10000 ?a)))
    (dotimes (i 1000)
      (setq s (concat s "b")))
    (length s))
  (message "BM concat-1k: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 6. Buffer operations ---
(let ((t0 (float-time)))
  (with-temp-buffer
    (dotimes (i 10000) (insert "hello world test\n"))
    (goto-char (point-min))
    (let ((count 0))
      (while (search-forward "test" nil t) (setq count (1+ count)))
      count))
  (message "BM buffer-search-10k: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 7. Hash table ---
(let ((t0 (float-time)))
  (let ((h (make-hash-table :test #'eq :size 100000)))
    (dotimes (i 100000) (puthash i (* i 2) h))
    (let ((s 0)) (maphash (lambda (k v) (setq s (+ s v))) h) s))
  (message "BM hash-100k: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 8. Regexp matching ---
(let ((t0 (float-time)))
  (with-temp-buffer
    (insert (make-string 10000 ?x))
    (goto-char (point-min))
    (dotimes (i 100) (string-match "x+" (buffer-string)))
    t)
  (message "BM regexp-100: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 9. GC performance ---
(let ((t0 (float-time)))
  (garbage-collect)
  (message "BM gc: %.1f ms" (* 1000 (- (float-time) t0))))

;; --- 10. Symbol operations ---
(let ((t0 (float-time)))
  (let ((count 0))
    (mapatoms (lambda (s) (setq count (1+ count))) obarray)
    count)
  (message "BM mapatoms: %.1f ms" (* 1000 (- (float-time) t0))))

(message "=== Benchmark Complete ===")
