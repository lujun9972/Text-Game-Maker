# Prompt Room Symbol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 tg-mode prompt 中显示当前房间 symbol，格式 `[symbol]>`

**Architecture:** 在 `tg-mode.el` 新增 `tg-prompt-string` 函数动态生成 prompt，修改 `tg-messages` 使用它，修改 `tg-parse` 通过查找行内最后一个 `>` 来定位用户输入。

**Tech Stack:** Emacs Lisp, ERT

---

### Task 1: 新增 tg-prompt-string 函数 + 测试

**Files:**
- Modify: `tg-mode.el`
- Modify: `test/test-tg-mode.el`

- [ ] **Step 1: 在 test-tg-mode.el 的 `(provide 'test-tg-mode)` 之前添加 tg-prompt-string 测试**

```elisp
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
```

- [ ] **Step 2: 在 tg-mode.el 的 `tg-messages` 函数之前（第 6 行）添加 tg-prompt-string**

```elisp
(defun tg-prompt-string ()
  "Return the prompt string showing current room symbol."
  (if (and current-room (Room-p current-room))
      (format "[%s]>" (Room-symbol current-room))
    ">"))
```

注意：`tg-mode.el` 不 require `room-maker`，但 `Room-p` 和 `Room-symbol` 由 `room-maker.el` 通过 `cl-defstruct` 定义。`tg-mode.el` 运行时 `room-maker` 已加载（由 `text-game-maker.el` 加载），所以无需新增 require。

- [ ] **Step 3: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'cl-generic)
    (require 'thingatpt)
    (require 'room-maker)
    (require 'tg-mode))"
```
Expected: no errors.

Run tests:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  -l test/test-helper.el -l test/test-tg-mode.el \
  --eval "(ert-run-tests-batch-and-exit '(or \"test-tg-prompt-string\" t))"
```
Expected: 2 new tests pass.

---

### Task 2: 修改 tg-messages 使用动态 prompt

**Files:**
- Modify: `tg-mode.el`

- [ ] **Step 1: 修改 tg-messages 中的硬编码 prompt**

改前（`tg-mode.el` 第 10 行）：
```elisp
(tg-mprinc ">" 'no-newline)
```

改后：
```elisp
(tg-mprinc (tg-prompt-string) 'no-newline)
```

- [ ] **Step 2: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'cl-generic)
    (require 'thingatpt)
    (require 'room-maker)
    (load-file \"tg-mode.el\"))"
```
Expected: no errors.

---

### Task 3: 修改 tg-parse 支持 [room]> prompt 格式

**Files:**
- Modify: `tg-mode.el`
- Modify: `test/test-tg-mode.el`

**问题分析：** 当前 `tg-parse` 检查行首第一个字符是否为 `>`：
```elisp
(string= ">" (buffer-substring (- beg 1) beg))
```
其中 `beg = (1+ (point))`，`point` 在 `beginning-of-line` 之后。对于 `>help`，第一个字符是 `>`，检测通过。但对于 `[living-room]>help`，第一个字符是 `[`，检测失败。

**解决方案：** 在行内查找最后一个 `>` 字符，取其之后的内容作为用户输入。

- [ ] **Step 1: 在 test-tg-mode.el 的 `(provide 'test-tg-mode)` 之前添加 prompt 解析测试**

在已有的 `test-tg-parse-no-prompt` 测试之后添加：

```elisp
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
        ;; Should not throw "未知的命令"; should parse help command
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
```

- [ ] **Step 2: 修改 tg-parse 的 prompt 检测逻辑**

改前（`tg-mode.el` 第 38-60 行）：
```elisp
(defun tg-parse (arg)
  "Function called when return is pressed in interactive mode to parse line."
  (interactive "*p")
  (beginning-of-line)
  (let ((beg (1+ (point)))
        line)
    (end-of-line)
    (when (and (not (= beg (point)))
		   (not (< (point) beg))
		   (string= ">" (buffer-substring (- beg 1) beg)))
	  (setq line (downcase (buffer-substring beg (point))))
	  (princ line)
	  (tg-mprinc "\n")
	  (let (action-result action things)
		(setq action-result (catch 'exception
							  (setq action (car (split-string line)))
							  (setq things (cdr (split-string line)))
								(setq action (intern (format "tg-%s" action)))
								(unless (member action tg-valid-actions)
									(throw 'exception "未知的命令"))
								  (apply action things)))
		(when action-result
		  (tg-mprinc action-result)))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))
```

改后：
```elisp
(defun tg-parse (arg)
  "Function called when return is pressed in interactive mode to parse line."
  (interactive "*p")
  (beginning-of-line)
  (let ((line-start (1+ (point)))
        line prompt-end)
    (end-of-line)
    (when (and (not (= line-start (point)))
               (not (< (point) line-start)))
      ;; Find the last '>' on this line to locate end of prompt
      (save-excursion
        (let ((line-end (point)))
          (end-of-line)
          (setq prompt-end (search-backward ">" line-start t))))
      (when prompt-end
        (setq line (downcase (buffer-substring (1+ prompt-end) (point))))
        (princ line)
        (tg-mprinc "\n")
        (let (action-result action things)
	      (setq action-result (catch 'exception
							    (setq action (car (split-string line)))
							    (setq things (cdr (split-string line)))
								(setq action (intern (format "tg-%s" action)))
								(unless (member action tg-valid-actions)
									(throw 'exception "未知的命令"))
								  (apply action things)))
	      (when action-result
	        (tg-mprinc action-result))))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))
```

关键变化：
- `line-start` 替代原来的 `beg`（语义更清晰）
- 用 `search-backward ">"` 从行尾向前查找最后一个 `>`，定位 prompt 结束位置
- 用户输入从 `(1+ prompt-end)` 开始（即 `>` 之后）
- 兼容旧格式 `>help`（唯一的 `>` 被找到）和新格式 `[living-room]>help`（最后一个 `>` 被找到）
- 无 `>` 的行（如 `hello world`）不会被解析

- [ ] **Step 3: 运行全量测试**

Run:
```bash
bash /home/lujun9972/github/Text-Game-Maker/run-tests.sh
```
Expected: All tests passed (should be 105 original + 4 new = 109 tests).

---

### Task 4: 提交

- [ ] **Step 1: 提交所有更改**

```bash
git add tg-mode.el test/test-tg-mode.el
git commit -m "$(cat <<'EOF'
feat: prompt 显示当前房间 symbol

- 新增 tg-prompt-string 函数动态生成 prompt
- prompt 格式: [room-symbol]> 或 >(无房间时)
- tg-parse 使用 search-backward 定位 prompt
- 新增 4 个测试覆盖 prompt 功能

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```
