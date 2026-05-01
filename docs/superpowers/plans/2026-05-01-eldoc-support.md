# tg-mode Eldoc Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 tg-mode 添加 eldoc 支持，在用户输入命令时实时显示匹配命令的文档

**Architecture:** 在 `tg-mode.el` 新增 `tg-eldoc-function`，用 `try-completion` 对用户输入与命令列表做前缀匹配，匹配到唯一命令时返回其 docstring。在 `tg-mode` 定义中注册此函数并启用 `eldoc-mode`。

**Tech Stack:** Emacs Lisp, ERT

---

### Task 1: 新增 tg-eldoc-function + 测试

**Files:**
- Modify: `tg-mode.el`
- Modify: `test/test-tg-mode.el`

- [ ] **Step 1: 在 test-tg-mode.el 的 `(provide 'test-tg-mode)` 之前添加 eldoc 测试**

```elisp
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
```

- [ ] **Step 2: 在 tg-mode.el 的 `tg-messages` 函数之前（第 12 行）添加 tg-eldoc-function**

在 `(defun tg-messages ()` 之前插入：

```elisp
(defun tg-eldoc-function ()
  "Eldoc function for tg-mode. Show docstring for matching command."
  (let* ((line-end (line-end-position))
         (prompt-pos (save-excursion
                       (beginning-of-line)
                       (search-forward ">" line-end t))))
    (when (and prompt-pos (<= (point) line-end))
      (let* ((input (buffer-substring-no-properties prompt-pos (point)))
             (input (string-trim input))
             (candidates (mapcar (lambda (sym)
                                   (substring (symbol-name sym) 3))
                                 tg-valid-actions))
             (match (try-completion input candidates)))
        (when (and (stringp match)
                   (member match candidates))
          (let ((fn (intern (concat "tg-" match))))
            (when (fboundp fn)
              (documentation fn))))))))
```

逻辑说明：
1. 在当前行查找 `>` 定位 prompt 结束位置
2. 取 `>` 之后到光标位置的内容作为用户输入
3. 将 `tg-valid-actions` 中的 symbol 去掉 `tg-` 前缀作为候选列表
4. `try-completion` 返回唯一匹配的完整字符串（`stringp`），或 `t`（多义）/ `nil`（无匹配）
5. 用 `(member match candidates)` 确认匹配是完整命令名
6. 返回该命令的 `documentation` 字符串

- [ ] **Step 3: 验证新测试通过**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  -l test/test-helper.el -l room-maker -l tg-mode -l test/test-tg-mode.el \
  --eval "(ert-run-tests-batch-and-exit '(or \"test-tg-eldoc\" t))"
```
Expected: 6 new tests pass.

---

### Task 2: 在 tg-mode 中注册 eldoc

**Files:**
- Modify: `tg-mode.el`

- [ ] **Step 1: 修改 tg-mode 的 define-derived-mode body**

改前（`tg-mode.el` 第 37-41 行）：
```elisp
(define-derived-mode tg-mode text-mode "TextGame"
  "Major mode for running text game."
  (make-local-variable 'scroll-step)
  (setq scroll-step 2)
  (local-set-key (kbd "<RET>") #'tg-parse))
```

改后：
```elisp
(define-derived-mode tg-mode text-mode "TextGame"
  "Major mode for running text game."
  (make-local-variable 'scroll-step)
  (setq scroll-step 2)
  (local-set-key (kbd "<RET>") #'tg-parse)
  (setq-local eldoc-documentation-function #'tg-eldoc-function)
  (eldoc-mode 1))
```

新增两行：
- `(setq-local eldoc-documentation-function #'tg-eldoc-function)` — 注册 eldoc 后端
- `(eldoc-mode 1)` — 启用 eldoc minor mode

注意：`eldoc-documentation-function` 是 eldoc.el 的变量，Emacs 25+ 内置。tg-mode 依赖 `text-mode`，text-mode buffer 中 eldoc 可用。

- [ ] **Step 2: 验证文件可加载**

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

---

### Task 3: 运行全量测试 + 提交

- [ ] **Step 1: 运行全量测试**

Run:
```bash
bash /home/lujun9972/github/Text-Game-Maker/run-tests.sh
```
Expected: All tests passed (should be 109 original + 6 new = 115 tests).

- [ ] **Step 2: 提交所有更改**

```bash
git add tg-mode.el test/test-tg-mode.el
git commit -m "$(cat <<'EOF'
feat: tg-mode 添加 eldoc 支持

- 新增 tg-eldoc-function 实时显示命令文档
- 使用 try-completion 前缀匹配命令
- 在 tg-mode 中注册 eldoc 并启用 eldoc-mode
- 新增 6 个测试覆盖 eldoc 功能

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```
