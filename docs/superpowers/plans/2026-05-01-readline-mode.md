# Readline Editing Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add command history browsing (up/down/M-p/M-n) and Tab completion to tg-mode.

**Architecture:** All changes in `tg-mode.el`. Four new functions (`tg-history-prev`, `tg-history-next`, `tg-record-history`, `tg-complete-command`) plus four new global variables. `tg-parse` modified to record successful commands. New key bindings in `tg-mode` definition.

**Tech Stack:** Emacs Lisp, ERT testing, `try-completion` / `all-completions` for completion.

---

### Task 1: Add command history browsing and recording

**Files:**
- Modify: `tg-mode.el` (add variables, `tg-history-prev`, `tg-history-next`, `tg-record-history`, modify `tg-parse`)
- Modify: `test/test-tg-mode.el` (add history tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-tg-mode.el` before `(provide 'test-tg-mode)`:

```elisp
;; --- Command history ---

(ert-deftest test-tg-history-prev-replaces-input ()
  "tg-history-prev should replace input with previous history entry."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (tg-history-prev)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (should (equal tg-current-input "test"))
      (should (= tg-history-index 0)))))

(ert-deftest test-tg-history-prev-saves-current-input ()
  "tg-history-prev should save current input before entering history."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">my input")
      (goto-char (point-max))
      (tg-history-prev)
      (should (equal tg-current-input "my input")))))

(ert-deftest test-tg-history-prev-no-history ()
  "tg-history-prev should do nothing when history is empty."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history nil)
    (setq tg-history-index -1)
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-history-prev)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-history-prev-cycles-through ()
  "tg-history-prev should cycle through all history entries."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up" "take sword"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">")
      (goto-char (point-max))
      (tg-history-prev)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (tg-history-prev)
      (should (string-match-p ">move up$" (buffer-string)))
      (tg-history-prev)
      (should (string-match-p ">take sword$" (buffer-string)))
      ;; At end of history, should stay on last entry
      (tg-history-prev)
      (should (string-match-p ">take sword$" (buffer-string))))))

(ert-deftest test-tg-history-next-restores-input ()
  "tg-history-next should restore saved input when returning to present."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">my text")
      (goto-char (point-max))
      (tg-history-prev)
      (tg-history-prev)
      (should (= tg-history-index 1))
      (tg-history-next)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (should (= tg-history-index 0))
      (tg-history-next)
      (should (string-match-p ">my text$" (buffer-string)))
      (should (= tg-history-index -1)))))

(ert-deftest test-tg-history-next-at-present ()
  "tg-history-next at present should do nothing."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat"))
    (setq tg-history-index -1)
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-history-next)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-record-history-success ()
  "tg-record-history should add command to front of history."
  (test-with-globals-saved (tg-command-history tg-history-index)
    (setq tg-command-history nil)
    (setq tg-history-index -1)
    (tg-record-history "attack rat")
    (should (equal tg-command-history '("attack rat")))
    (tg-record-history "move up")
    (should (equal tg-command-history '("move up" "attack rat")))))

(ert-deftest test-tg-record-history-dedup ()
  "tg-record-history should skip duplicate of most recent entry."
  (test-with-globals-saved (tg-command-history)
    (setq tg-command-history '("attack rat"))
    (tg-record-history "attack rat")
    (should (equal tg-command-history '("attack rat")))))

(ert-deftest test-tg-record-history-empty ()
  "tg-record-history should not record empty strings."
  (test-with-globals-saved (tg-command-history)
    (setq tg-command-history nil)
    (tg-record-history "")
    (should (equal tg-command-history nil))))

(ert-deftest test-tg-record-history-max ()
  "tg-record-history should trim history beyond max size."
  (test-with-globals-saved (tg-command-history tg-command-history-max)
    (setq tg-command-history-max 3)
    (setq tg-command-history nil)
    (tg-record-history "a")
    (tg-record-history "b")
    (tg-record-history "c")
    (tg-record-history "d")
    (should (= (length tg-command-history) 3))
    (should (equal (car tg-command-history) "d"))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-tg-mode.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: Some tests FAIL (functions don't exist yet).

- [ ] **Step 3: Implement history variables and functions in `tg-mode.el`**

Add these after the `(defvar tg-over-p ...)` block (after line 8):

```elisp
(defvar tg-command-history nil
  "命令历史列表，最新的在前面")

(defvar tg-command-history-max 50
  "命令历史最大条数")

(defvar tg-history-index -1
  "当前浏览的历史索引，-1 表示不在浏览历史")

(defvar tg-current-input ""
  "浏览历史前保存的当前输入")
```

Add `tg-record-history` function before `tg-mprinc`:

```elisp
(defun tg-record-history (cmd)
  "Record CMD to command history."
  (when (and (stringp cmd) (not (string-empty-p cmd)))
    (unless (and tg-command-history (string= cmd (car tg-command-history)))
      (push cmd tg-command-history)
      (when (> (length tg-command-history) tg-command-history-max)
        (setf (nthcdr tg-command-history-max tg-command-history) nil)))
    (setq tg-history-index -1)))
```

Add `tg-history-prev` and `tg-history-next` after `tg-record-history`:

```elisp
(defun tg-history-prev ()
  "Show previous command from history."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t)))))
    (when (and prompt-end tg-command-history)
      (when (= tg-history-index -1)
        (setq tg-current-input
              (buffer-substring-no-properties prompt-end (line-end-position))))
      (let ((next-index (1+ tg-history-index)))
        (when (< next-index (length tg-command-history))
          (setq tg-history-index next-index)
          (delete-region prompt-end (line-end-position))
          (insert (nth tg-history-index tg-command-history))
          (end-of-line))))))

(defun tg-history-next ()
  "Show next command from history."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t)))))
    (when (and prompt-end (>= tg-history-index 0))
      (cl-decf tg-history-index)
      (delete-region prompt-end (line-end-position))
      (insert (if (= tg-history-index -1)
                  tg-current-input
                (nth tg-history-index tg-command-history)))
      (end-of-line))))
```

- [ ] **Step 4: Modify `tg-parse` to record history**

In the `tg-parse` function, find the `else` branch of `(if dialog-pending ...)`. The current code is:

```elisp
          (let (action-result action things)
            (setq action-result (catch 'exception
                                  (setq action (car (split-string line)))
                                  (setq things (cdr (split-string line)))
                                  (setq action (intern (format "tg-%s" action)))
                                  (unless (member action tg-valid-actions)
                                    (throw 'exception "未知的命令"))
                                  (apply action things)))
            (when action-result
              (tg-mprinc action-result))
            (npc-run-behaviors))
```

Replace with (adds `success` flag and `tg-record-history` call):

```elisp
          (let (action-result action things (success nil))
            (setq action-result (catch 'exception
                                  (setq action (car (split-string line)))
                                  (setq things (cdr (split-string line)))
                                  (setq action (intern (format "tg-%s" action)))
                                  (unless (member action tg-valid-actions)
                                    (throw 'exception "未知的命令"))
                                  (apply action things)
                                  (setq success t)))
            (when success
              (tg-record-history line))
            (when action-result
              (tg-mprinc action-result))
            (npc-run-behaviors))
```

- [ ] **Step 5: Add key bindings in `tg-mode` definition**

In the `define-derived-mode tg-mode` block, add after the existing `(local-set-key ...)` line:

```elisp
  (local-set-key (kbd "<up>") #'tg-history-prev)
  (local-set-key (kbd "<down>") #'tg-history-next)
  (local-set-key (kbd "M-p") #'tg-history-prev)
  (local-set-key (kbd "M-n") #'tg-history-next)
```

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (230 existing + 10 new = 240).

- [ ] **Step 7: Commit**

```bash
git add tg-mode.el test/test-tg-mode.el
git commit -m "feat: add command history browsing (up/down, M-p/M-n)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add Tab completion for command names

**Files:**
- Modify: `tg-mode.el` (add `tg-complete-command`, bind TAB)
- Modify: `test/test-tg-mode.el` (add completion tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-tg-mode.el` before `(provide 'test-tg-mode)`:

```elisp
;; --- Tab completion ---

(ert-deftest test-tg-complete-unique-prefix ()
  "tg-complete-command should complete unique prefix."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">at")
      (goto-char (point-max))
      (tg-complete-command)
      (should (string-match-p ">attack$" (buffer-string))))))

(ert-deftest test-tg-complete-no-match ()
  "tg-complete-command should do nothing with no match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move))
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-complete-command)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-complete-already-complete ()
  "tg-complete-command should do nothing when already complete."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move))
    (with-temp-buffer
      (tg-mode)
      (insert ">attack")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-complete-command)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-complete-ambiguous-shows-candidates ()
  "tg-complete-command on ambiguous prefix should show candidates via tg-display."
  (test-with-globals-saved (tg-valid-actions display-fn)
    (setq tg-valid-actions '(tg-attack tg-talk))
    (let (output)
      (setq display-fn (lambda (&rest args) (push args output)))
      (with-temp-buffer
        (tg-mode)
        (insert ">ta")
        (goto-char (point-max))
        (tg-complete-command)
        (should (cl-some (lambda (s) (string-match-p "attack" s)) (mapcar #'car output)))
        (should (cl-some (lambda (s) (string-match-p "talk" s)) (mapcar #'car output)))))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-tg-mode.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: Some tests FAIL (function doesn't exist yet).

- [ ] **Step 3: Implement `tg-complete-command` in `tg-mode.el`**

Add before `tg-mprinc` (or after `tg-history-next`):

```elisp
(defun tg-complete-command ()
  "Complete command name after prompt."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t)))))
    (when prompt-end
      (let* ((input (buffer-substring-no-properties prompt-end (line-end-position)))
             (candidates (mapcar (lambda (sym)
                                   (substring (symbol-name sym) 3))
                                 tg-valid-actions))
             (completion (try-completion input candidates)))
        (cond
         ((null completion) nil)
         ((eq completion t) nil)
         ((string= completion input)
          (let ((matches (all-completions input candidates)))
            (when (> (length matches) 1)
              (tg-display (format "候选命令: %s" (string-join matches ", "))))))
         ((stringp completion)
          (delete-region prompt-end (line-end-position))
          (insert completion)))))))
```

- [ ] **Step 4: Add TAB key binding in `tg-mode` definition**

Add to the `define-derived-mode tg-mode` block:

```elisp
  (local-set-key (kbd "TAB") #'tg-complete-command)
```

- [ ] **Step 5: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (240 existing + 4 new = 244).

- [ ] **Step 6: Commit**

```bash
git add tg-mode.el test/test-tg-mode.el
git commit -m "feat: add Tab completion for command names

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
