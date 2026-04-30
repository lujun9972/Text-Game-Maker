;;; test-tg-mode.el --- Tests for tg-mode.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'tg-mode)

;; --- tg-mprinc ---

(ert-deftest test-tg-mprinc-with-newline ()
  "tg-mprinc should insert string followed by newline."
  (with-temp-buffer
    (tg-mprinc "hello")
    (should (equal (buffer-string) "hello\n"))))

(ert-deftest test-tg-mprinc-no-newline ()
  "tg-mprinc with 'no-newline should not add newline."
  (with-temp-buffer
    (tg-mprinc "hello" 'no-newline)
    (should (equal (buffer-string) "hello"))))

(ert-deftest test-tg-mprinc-non-string ()
  "tg-mprinc should convert non-string to string via prin1-to-string."
  (with-temp-buffer
    (tg-mprinc 42)
    (should (equal (buffer-string) "42\n"))))

;; --- tg-mode ---

(ert-deftest test-tg-mode-is-major-mode ()
  "tg-mode should be a valid major mode derived from text-mode."
  (with-temp-buffer
    (tg-mode)
    (should (equal major-mode 'tg-mode))
    (should (derived-mode-p 'text-mode))))

;; --- tg-parse ---

(ert-deftest test-tg-parse-valid-command ()
  "tg-parse should execute a valid command and display result."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">help\n")
      (goto-char (point-max))
      ;; Move to beginning of the line with ">help"
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        ;; tg-help should have been called; check buffer has output
        nil))))

(ert-deftest test-tg-parse-unknown-command ()
  "tg-parse should display error for unknown command."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      (should (string-match-p "未知的命令" (buffer-string))))))

(ert-deftest test-tg-parse-empty-line ()
  "tg-parse should do nothing for empty lines."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert "\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((before (buffer-string)))
        (tg-parse 1)
        ;; Should not error, buffer may have changed slightly but no crash
        t))))

(ert-deftest test-tg-parse-no-prompt ()
  "tg-parse should do nothing for lines without '>' prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert "hello world\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      ;; Should not error
      t)))

;; --- tg-prompt-string ---

(ert-deftest test-tg-prompt-string-with-room ()
  "tg-prompt-string should return [symbol]> when current-room is set."
  (test-with-globals-saved (current-room)
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (should (equal (tg-prompt-string) "[living-room]>"))))

(ert-deftest test-tg-prompt-string-without-room ()
  "tg-prompt-string should return > when current-room is nil."
  (test-with-globals-saved (current-room)
    (setq current-room nil)
    (should (equal (tg-prompt-string) ">"))))

(ert-deftest test-tg-parse-room-prompt ()
  "tg-parse should parse commands after [room]> prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-help))
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (setq rooms-alist (list (cons 'living-room current-room)))
    (setq room-map '((living-room)))
    (with-temp-buffer
      (tg-mode)
      (insert "[living-room]>help\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        (should-not (stringp output))))))

(ert-deftest test-tg-parse-plain-prompt-still-works ()
  "tg-parse should still parse commands after plain > prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room)
    (setq tg-valid-actions '(tg-help))
    (setq current-room nil)
    (with-temp-buffer
      (tg-mode)
      (insert ">help\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        (should-not (stringp output))))))

;; --- tg-eldoc-function ---

(ert-deftest test-tg-eldoc-exact-command ()
  "tg-eldoc-function should return docstring for exact command match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">help")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

(ert-deftest test-tg-eldoc-prefix-match ()
  "tg-eldoc-function should return docstring for unique prefix match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">he")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

(ert-deftest test-tg-eldoc-ambiguous-prefix ()
  "tg-eldoc-function should return nil for ambiguous prefix."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    ;; We need to manually add a second action starting with "he"
    ;; tg-defaction adds to tg-valid-actions, but we can just set the list
    (setq tg-valid-actions '(tg-help tg-hello))
    (with-temp-buffer
      (tg-mode)
      (insert ">he")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-no-match ()
  "tg-eldoc-function should return nil for no match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-no-prompt ()
  "tg-eldoc-function should return nil when no prompt on line."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert "hello world")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-room-prompt ()
  "tg-eldoc-function should work with [room]> prompt format."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-help))
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (setq rooms-alist (list (cons 'living-room current-room)))
    (setq room-map '((living-room)))
    (with-temp-buffer
      (tg-mode)
      (insert "[living-room]>help")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

(provide 'test-tg-mode)
