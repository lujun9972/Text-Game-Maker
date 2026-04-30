;;; test-text-game-maker.el --- Tests for text-game-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)

(ert-deftest test-file-content-reads-file ()
  "file-content should return the content of a file."
  (test-with-temp-file "hello world"
    (should (equal (file-content temp-file) "hello world"))))

(ert-deftest test-file-content-nonexistent-file ()
  "file-content should signal error for nonexistent files."
  (should-error (file-content "/tmp/tg-nonexistent-file-test-12345.el")))

(ert-deftest test-file-content-preserves-newlines ()
  "file-content should preserve newline characters."
  (test-with-temp-file "line1\nline2\n"
    (should (equal (file-content temp-file) "line1\nline2\n"))))

(ert-deftest test-tg-display-calls-display-fn ()
  "tg-display should call display-fn with its arguments."
  (let ((called-with nil))
    (test-with-globals-saved (display-fn)
      (setq display-fn (lambda (&rest args) (setq called-with args)))
      (tg-display "test message")
      (should (equal called-with '("test message"))))))

(ert-deftest test-tg-display-multiple-args ()
  "tg-display should pass multiple arguments to display-fn."
  (let ((called-with nil))
    (test-with-globals-saved (display-fn)
      (setq display-fn (lambda (&rest args) (setq called-with args)))
      (tg-display "a" "b" "c")
      (should (equal called-with '("a" "b" "c"))))))

(provide 'test-text-game-maker)
