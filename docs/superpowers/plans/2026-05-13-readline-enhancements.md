# Readline 增强 实现计划

> **面向 AI 代理的工作者：** 必需子技能：`superpowers-zh:serial-executing-plans`。所有任务共享同一组文件（`tg-mode.el` + `tg-parser.el` + `test/tg-mode-test.el`），无法分 wave 并行，使用串行执行。

**目标：** 为 tg-mode 的命令输入区域增加 4 项 readline 风格的增强功能：↑↓箭头翻历史、C-r 搜索历史、对象/creature 双名称补全、方向词补全。

**架构：** 修改 `tg-mode.el`（补全逻辑 + 历史搜索 + keybinding）和 `tg-parser.el`（词汇表添加 symbol 名）。新增 buffer-local 变量和交互函数，修改现有补全函数的候选来源。

**技术栈：** Emacs Lisp, ERT 测试框架

---

### 任务 1：↑↓ 箭头翻历史

**依赖：** 无
**文件集：** `tg-mode.el`, `test/tg-mode-test.el`
**导出/变更接口：** 无（仅 keybinding）
**消费接口：** `tg-mode.el::tg-history-prev`, `tg-mode.el::tg-history-next`
**复杂度：** quick

**文件：**
- 修改：`tg-mode.el:64-68`（keybinding 区域）
- 测试：`test/tg-mode-test.el`

- [ ] **步骤 1：编写测试**

在 `test/tg-mode-test.el` 的 `;;; 命令历史测试` 之前添加：

```elisp
(ert-deftest test-tg-arrow-keys-bound ()
  "↑↓ 箭头应绑定到 tg-history-prev/next。"
  (with-temp-buffer
    (tg-mode)
    (should (eq (key-binding (kbd "<up>")) #'tg-history-prev))
    (should (eq (key-binding (kbd "<down>")) #'tg-history-next))))
```

- [ ] **步骤 2：运行测试验证失败**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：`test-tg-arrow-keys-bound` FAIL（`<up>` 未绑定）

- [ ] **步骤 3：添加 keybinding**

在 `tg-mode.el` 的 `define-derived-mode` 键绑定区域，`(local-set-key (kbd "M-n") #'tg-history-next)` 之后添加：

```elisp
(local-set-key (kbd "<up>") #'tg-history-prev)
(local-set-key (kbd "<down>") #'tg-history-next)
```

- [ ] **步骤 4：运行测试验证通过**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 5：Commit**

```bash
git add tg-mode.el test/tg-mode-test.el
git commit -m "feat: bind ↑↓ arrow keys to history navigation"
```

---

### 任务 2：C-r 搜索历史

**依赖：** 任务 1
**文件集：** `tg-mode.el`, `test/tg-mode-test.el`
**导出/变更接口：** `tg-mode.el::tg-history-isearch`
**消费接口：** `tg-mode.el::tg-command-history`, `tg-mode.el::tg-message`
**复杂度：** standard

**文件：**
- 修改：`tg-mode.el`（新增 1 个函数 + keybinding）
- 测试：`test/tg-mode-test.el`

**设计决策：** C-r 每次都弹出 mini-buffer 输入搜索词，不记住上次搜索词，不做循环。单条匹配直接填入；多条匹配填入最近一条并列出候选；无匹配提示。

- [ ] **步骤 1：编写失败的测试**

在 `test/tg-mode-test.el` 添加 `;;; C-r 搜索历史测试` 区域：

```elisp
;;; ============================================================
;;; C-r 搜索历史测试
;;; ============================================================

(ert-deftest test-tg-isearch-key-binding ()
  "C-r 应绑定到 tg-history-isearch。"
  (with-temp-buffer
    (tg-mode)
    (should (eq (key-binding (kbd "C-r")) #'tg-history-isearch))))

(ert-deftest test-tg-isearch-single-match ()
  "C-r 单条匹配直接填入命令行。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    (setq tg-command-history '("look" "go north" "take key"))
    ;; 模拟搜索逻辑：单条匹配
    (let* ((term "go")
           (matches (cl-remove-if-not
                     (lambda (s) (string-match-p term s))
                     tg-command-history)))
      (should (= (length matches) 1))
      (should (equal (car matches) "go north"))
      ;; 填入
      (let ((inhibit-read-only t))
        (delete-region tg-prompt-marker (point-max)))
      (insert (car matches))
      (should (string-match-p "go north$" (buffer-string))))))

(ert-deftest test-tg-isearch-no-match ()
  "C-r 无匹配时返回空列表。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-command-history '("look" "take key"))
    (let ((matches (cl-remove-if-not
                    (lambda (s) (string-match-p "xyz" s))
                    tg-command-history)))
      (should (null matches)))))

(ert-deftest test-tg-isearch-multiple-matches ()
  "C-r 多条匹配：填入最近一条，候选列表包含全部匹配。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-command-history '("look" "look at key" "go north"))
    (let* ((term "look")
           (matches (cl-remove-if-not
                     (lambda (s) (string-match-p term s))
                     tg-command-history)))
      (should (equal (length matches) 2))
      ;; 最近一条（第一个元素）填入
      (should (equal (car matches) "look"))
      ;; 候选列表包含全部
      (should (equal matches '("look" "look at key"))))))
```

- [ ] **步骤 2：运行测试验证失败**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：`test-tg-isearch-key-binding` FAIL（函数未定义）

- [ ] **步骤 3：实现 C-r 搜索**

在 `tg-mode.el` 中：

**3a. 新增 `tg-history-isearch` 函数**（在 `tg-history-next` 之后，`;;; TAB 补全` 之前）：

```elisp
(defun tg-history-isearch ()
  "C-r 搜索历史。用 mini-buffer 输入搜索词。
单条匹配直接填入；多条匹配填入最近一条并列出候选；无匹配提示。"
  (interactive)
  (let ((term (read-string "搜索历史: ")))
    (unless (string-empty-p term)
      (let ((matches (cl-remove-if-not
                      (lambda (s) (string-match-p term s))
                      tg-command-history)))
        (cond
         ((null matches)
          (tg-message "无匹配历史"))
         ((= (length matches) 1)
          (let ((inhibit-read-only t))
            (delete-region tg-prompt-marker (point-max)))
          (insert (car matches))
          (goto-char (point-max)))
         (t
          (let ((inhibit-read-only t))
            (delete-region tg-prompt-marker (point-max)))
          (insert (car matches))
          (goto-char (point-max))
          (tg-message "候选: %s" (string-join matches ", "))))))))
```

**3b. 添加 keybinding**：在 `define-derived-mode` 键绑定区域添加：

```elisp
(local-set-key (kbd "C-r") #'tg-history-isearch)
```

- [ ] **步骤 4：运行测试验证通过**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 5：Commit**

```bash
git add tg-mode.el test/tg-mode-test.el
git commit -m "feat: add C-r history search"
```

---

### 任务 3：对象/creature 双名称补全 + 解析器同步

**依赖：** 任务 2
**文件集：** `tg-mode.el`, `tg-parser.el`, `test/tg-mode-test.el`
**导出/变更接口：** `tg-mode.el::tg-complete-object`（行为变更）, `tg-parser.el::tg-parser-add-object-vocab`（行为变更）
**消费接口：** `tg-room.el::tg-room-all-visible-objects`, `tg-room.el::tg-room-creatures`, `tg-creature.el::tg-creature-inventory`, `tg-creature.el::tg-get-creature`, `tg-object.el::tg-get-object`, `tg-object.el::tg-object-name`
**复杂度：** standard

**文件：**
- 修改：`tg-mode.el`（`tg-complete-object` 函数，第 279-316 行）
- 修改：`tg-parser.el`（`tg-parser-add-object-vocab` 函数，第 95-101 行）
- 测试：`test/tg-mode-test.el`

**设计决策：**
- 补全候选同时包含中文名和 symbol 名（对象和 creature 都是）
- 解析器词汇表也同步添加 symbol 名，确保补全后的输入能被解析
- 用户打"火把"或"torch"都能补全到同一个对象

- [ ] **步骤 1：编写失败的测试**

**1a. 修改 `tg-mode-test-setup`**：在 `(setq tg-message-hook nil))` 之前添加 creature 和第二个对象：

```elisp
  ;; 创建测试 creature
  (let ((goblin (make-tg-creature
                 :symbol 'test-goblin
                 :name "Goblin"
                 :attr '((hp 50))
                 :inventory nil
                 :equipment nil
                 :exp-reward nil
                 :behaviors nil
                 :death-trigger nil
                 :shopkeeper nil
                 :handler nil)))
    (tg-register-creature 'test-goblin goblin)
    (let ((room (tg-get-room 'test-room)))
      (setf (tg-room-creatures room) '(test-goblin))))

  ;; 创建第二个测试对象
  (let ((torch (make-tg-object
                :symbol 'test-torch
                :name "torch"
                :synonyms nil
                :contents nil
                :supports nil
                :props nil
                :state nil
                :key nil
                :effects nil
                :handler nil)))
    (tg-register-object 'test-torch torch)
    (let ((room (tg-get-room 'test-room)))
      (tg-room-add-object room 'test-torch)))
```

**1b. 在 `;;; TAB 补全测试` 区域添加测试**：

```elisp
(ert-deftest test-tg-complete-object-symbol-name ()
  "对象补全应支持 symbol 名前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents '(my-sword)
                     :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (let ((sword (make-tg-object
                      :symbol 'my-sword
                      :name "长剑"
                      :synonyms nil :contents nil :supports nil
                      :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-sword sword))
        (tg-render-prompt)
        (insert "take my-")
        (tg-complete-command)
        (should (string-match-p "my-sword$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-chinese-name ()
  "对象补全应支持中文名前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents '(my-sword)
                     :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (let ((sword (make-tg-object
                      :symbol 'my-sword
                      :name "长剑"
                      :synonyms nil :contents nil :supports nil
                      :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-sword sword))
        (tg-render-prompt)
        (insert "take 长")
        (tg-complete-command)
        (should (string-match-p "长剑$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-creature-symbol ()
  "对象补全应包含房间内 creature 的 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil
                     :creatures '(test-goblin)
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "attack test-")
        (tg-complete-command)
        (should (string-match-p "test-goblin$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-creature-name ()
  "对象补全应包含房间内 creature 的显示名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil
                     :creatures '(test-goblin)
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "attack gob")
        (tg-complete-command)
        (should (string-match-p "Goblin$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-inventory-symbol ()
  "对象补全应包含背包物品 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (let ((potion (make-tg-object
                       :symbol 'my-potion
                       :name "药水"
                       :synonyms nil :contents nil :supports nil
                       :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-potion potion)
          (let* ((player-sym (tg-game-get tg-game :player))
                 (player (tg-get-creature player-sym)))
            (setf (tg-creature-inventory player) '(my-potion))))
        (tg-render-prompt)
        (insert "drop my-")
        (tg-complete-command)
        (should (string-match-p "my-potion$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-parser-recognizes-symbol-name ()
  "解析器应能识别对象的 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (progn
        (tg-register-builtins)
        (let ((ast (tg-parse "take test-key")))
          ;; 解析器词汇表应包含 symbol 名，能解析成功
          (should (eq (plist-get ast :action) 'take))
          (should (eq (plist-get ast :do-key) 'test-key))))
    (tg-mode-test-teardown)))
```

- [ ] **步骤 2：运行测试验证失败**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：新增测试 FAIL（当前 `tg-complete-object` 只用中文名匹配，解析器词汇表不含 symbol 名）

- [ ] **步骤 3：修改 `tg-complete-object`**

替换 `tg-mode.el` 中的 `tg-complete-object` 函数（第 279-316 行）。新实现同时提供中文名和 symbol 名作为候选：

```elisp
(defun tg-complete-object (prefix)
  "补全对象名。PREFIX 为当前输入的对象前缀。
候选同时包含中文名和 symbol 名。
来源：房间可见对象 + 背包物品 + 房间内 creature。"
  (when (and tg-game (tg-game-get tg-game :location))
    (let* ((location (tg-game-get tg-game :location))
           (room (tg-get-room location))
           (candidates '())
           (lower-prefix (downcase prefix)))
      (when room
        ;; 房间可见对象 → 中文名 + symbol 名
        (dolist (obj-sym (tg-room-all-visible-objects room))
          (let ((obj (tg-get-object obj-sym)))
            (when obj
              (let ((name (tg-object-name obj))
                    (sym-name (symbol-name obj-sym)))
                (when (and name (string-prefix-p lower-prefix (downcase name)))
                  (push name candidates))
                (when (string-prefix-p lower-prefix (downcase sym-name))
                  (push sym-name candidates))))))
        ;; 房间 creature → 显示名 + symbol 名
        (dolist (creature-sym (tg-room-creatures room))
          (let ((creature (tg-get-creature creature-sym)))
            (when creature
              (let ((name (tg-creature-name creature))
                    (sym-name (symbol-name creature-sym)))
                (when (and name (string-prefix-p lower-prefix (downcase name)))
                  (push name candidates))
                (when (string-prefix-p lower-prefix (downcase sym-name))
                  (push sym-name candidates)))))))
      ;; 背包物品 → 中文名 + symbol 名
      (let* ((player-sym (tg-game-get tg-game :player))
             (player (when player-sym (tg-get-creature player-sym))))
        (when player
          (dolist (obj-sym (tg-creature-inventory player))
            (let ((obj (tg-get-object obj-sym)))
              (when obj
                (let ((name (tg-object-name obj))
                      (sym-name (symbol-name obj-sym)))
                  (when (and name (string-prefix-p lower-prefix (downcase name)))
                    (push name candidates))
                  (when (string-prefix-p lower-prefix (downcase sym-name))
                    (push sym-name candidates))))))))
      ;; 去重
      (setq candidates (delete-dups candidates))
      (when candidates
        (let ((completion (try-completion lower-prefix candidates)))
          (cond
           ((null completion) nil)
           ((eq completion t) nil)
           ((string= (downcase completion) lower-prefix)
            (let ((matches (all-completions lower-prefix candidates)))
              (when (> (length matches) 1)
                (tg-message "候选对象: %s" (string-join matches ", ")))))
           ((stringp completion)
            (let ((inhibit-read-only t))
              (delete-region (- (point) (length prefix)) (point)))
            (insert completion))))))))
```

- [ ] **步骤 4：修改 `tg-parser-add-object-vocab`**

在 `tg-parser.el` 的 `tg-parser-add-object-vocab` 函数（第 95-101 行）中，添加 symbol 名到词汇表。在现有 `(puthash (downcase (tg-object-name obj)) obj-sym vocab)` 之后添加：

```elisp
;; symbol 名也加入词汇表
(puthash (downcase (symbol-name obj-sym)) obj-sym vocab)
```

完整的 `tg-parser-add-object-vocab` 变为：

```elisp
(defun tg-parser-add-object-vocab (vocab obj-sym)
  "将对象的名称、同义词和 symbol 名添加到词汇表。"
  (let ((obj (tg-get-object obj-sym)))
    (when obj
      (puthash (downcase (tg-object-name obj)) obj-sym vocab)
      (dolist (syn (tg-object-synonyms obj))
        (puthash (downcase (format "%s" syn)) obj-sym vocab))
      (puthash (downcase (symbol-name obj-sym)) obj-sym vocab))))
```

- [ ] **步骤 5：运行测试验证通过**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 6：运行解析器相关测试确认不破坏**

```sh
emacs -batch -L . -l test/tg-parser-test.el -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 7：Commit**

```bash
git add tg-mode.el tg-parser.el test/tg-mode-test.el
git commit -m "feat: dual-name completion (Chinese + symbol) for objects and creatures, add symbol to parser vocab"
```

---

### 任务 4：方向词补全

**依赖：** 任务 3
**文件集：** `tg-mode.el`, `test/tg-mode-test.el`
**导出/变更接口：** `tg-mode.el::tg-complete-command`（行为变更）, `tg-mode.el::tg-complete-direction`
**消费接口：** `tg-parser.el::tg-parser-direction-map`, `tg-parser.el::tg-parser-normalize-verb`, `tg-action.el::tg-find-action`
**复杂度：** standard

**文件：**
- 修改：`tg-mode.el:231-252`（`tg-complete-command` 函数）
- 新增：`tg-complete-direction` 函数
- 测试：`test/tg-mode-test.el`

**设计决策：**
- 单词输入时方向词优先于动词补全（与解析器行为一致：单独输入方向词等同于 go）
- 动词 + 参数时，如果动词归一化为 `go`，走方向词补全
- 使用标准 `try-completion` 行为：有歧义时扩展到公共前缀

- [ ] **步骤 1：编写失败的测试**

在 `test/tg-mode-test.el` 的 `;;; TAB 补全测试` 区域添加：

```elisp
(ert-deftest test-tg-complete-direction-with-go ()
  "go 动词后 TAB 应补全方向词。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "go nor")
        (tg-complete-command)
        (should (string-match-p "go north$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-direction-with-move ()
  "move 动词后 TAB 也应补全方向词。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "move sou")
        (tg-complete-command)
        (should (string-match-p "move south$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-direction-standalone ()
  "单独输入方向缩写时 TAB 应补全方向词（优先于动词补全）。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "east")
        (tg-complete-command)
        (should (string-match-p "east$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-direction-ambiguous ()
  "方向词有歧义时扩展到公共前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "go n")
        (tg-complete-command)
        ;; "n" 匹配 north/northeast/northwest，公共前缀为 "nor"
        (should (string-match-p "go nor$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-direction-fallback-to-verb ()
  "非方向词的单字输入应走动词补全。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "lo")
        (tg-complete-command)
        ;; "lo" 不是方向词前缀，走动词补全 → "look"
        (should (string-match-p "look$" (buffer-string))))
    (tg-mode-test-teardown)))
```

- [ ] **步骤 2：运行测试验证失败**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：方向词测试 FAIL

- [ ] **步骤 3：实现方向词补全**

**3a. 新增 `tg-complete-direction` 函数**（在 `tg-complete-object` 之后）：

```elisp
(defun tg-complete-direction (prefix)
  "补全方向词。PREFIX 为当前输入的方向前缀。
候选为所有长形式方向词（去重），使用标准 try-completion。"
  (let* ((lower-prefix (downcase prefix))
         ;; 收集去重的长形式方向词
         (candidates (delete-dups
                      (mapcar (lambda (entry)
                                (symbol-name (cdr entry)))
                              tg-parser-direction-map))))
    (let ((filtered (cl-remove-if-not
                     (lambda (c) (string-prefix-p lower-prefix (downcase c)))
                     candidates)))
      (when filtered
        (let ((completion (try-completion lower-prefix filtered)))
          (cond
           ((null completion) nil)
           ((eq completion t) nil)
           ((string= (downcase completion) lower-prefix)
            (let ((matches (all-completions lower-prefix filtered)))
              (when (> (length matches) 1)
                (tg-message "候选方向: %s" (string-join matches ", ")))))
           ((stringp completion)
            (let ((inhibit-read-only t))
              (delete-region (- (point) (length prefix)) (point)))
            (insert completion))))))))
```

**3b. 新增 `tg-complete-direction-p` 辅助函数**（在 `tg-complete-direction` 之前）：

```elisp
(defun tg-complete-direction-p (prefix)
  "检查 PREFIX 是否匹配任何方向词。"
  (let ((lower-prefix (downcase prefix))
        (directions (delete-dups
                     (mapcar (lambda (entry) (symbol-name (cdr entry)))
                             tg-parser-direction-map))))
    (cl-some (lambda (d) (string-prefix-p lower-prefix (downcase d))) directions)))
```

**3c. 修改 `tg-complete-command`**（替换第 231-252 行）：

```elisp
(defun tg-complete-command ()
  "TAB 补全。

空输入 → 补全动词。
单字输入 → 方向词优先，无方向匹配再走动词补全。
动词 + 参数 → go 走方向词补全，其他走对象补全。"
  (interactive)
  (when (and tg-prompt-marker
             (>= (point) tg-prompt-marker))
    (let* ((input (buffer-substring-no-properties tg-prompt-marker (point-max)))
           (tokens (tg-parser-tokenize input)))
      (if (or (null tokens) (string-empty-p (string-trim input)))
          (tg-complete-verb "")
        (let* ((words (split-string input "[ \t]+" t))
               (verb (car words))
               (rest (cdr words)))
          (if rest
              ;; 动词后有内容
              (let ((action-id (tg-find-action (tg-parser-normalize-verb verb))))
                (if (eq action-id 'go)
                    (tg-complete-direction (car (last words)))
                  (tg-complete-object (car (last words)))))
            ;; 单字输入：方向词优先
            (if (tg-complete-direction-p verb)
                (tg-complete-direction verb)
              (tg-complete-verb verb))))))))
```

- [ ] **步骤 4：运行测试验证通过**

```sh
emacs -batch -L . -l test/tg-mode-test.el -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 5：运行完整测试套件**

```sh
emacs -batch -L . \
  -l test/tg-registry-test.el -l test/tg-game-test.el \
  -l test/tg-object-test.el -l test/tg-creature-test.el \
  -l test/tg-room-test.el -l test/tg-action-test.el \
  -l test/tg-parser-test.el -l test/tg-commands-test.el \
  -l test/tg-dialog-test.el -l test/tg-npc-test.el \
  -l test/tg-quest-test.el -l test/tg-shop-test.el \
  -l test/tg-level-test.el -l test/tg-builtin-test.el \
  -l test/tg-config-test.el -l test/tg-config-gen-test.el \
  -l test/tg-save-test.el -l test/tg-mode-test.el \
  -l test/tg-integration-test.el \
  -f ert-run-tests-batch-and-exit
```

预期：全部 PASS

- [ ] **步骤 6：Commit**

```bash
git add tg-mode.el test/tg-mode-test.el
git commit -m "feat: add direction word completion with go detection and standalone support"
```

---

## 并行执行图

> 仅 `parallel-executing-plans` 使用；`serial-executing-plans` 忽略本节。

**Critical Path:** 任务 1 → 任务 2 → 任务 3 → 任务 4

- Wave 1（无依赖）：任务 1
- Wave 2（依赖 Wave 1）：任务 2
- Wave 3（依赖 Wave 2）：任务 3
- Wave 4（依赖 Wave 3）：任务 4

注意：所有任务共享 `tg-mode.el` + `test/tg-mode-test.el`，任务 3 额外修改 `tg-parser.el`。无法并行，必须串行执行。使用 `superpowers-zh:serial-executing-plans`。
