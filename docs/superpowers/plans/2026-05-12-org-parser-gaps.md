# Org 解析层补全实现计划

> **面向 AI 代理的工作者：** 必需子技能：`superpowers:serial-executing-plans`（任务间共享 tg-config.el，强耦合）。

**目标：** 补全 4 个 Org 解析缺口（对话条件、Level 段、任务描述、容器初始化），使所有已有功能均可通过 game.org 配置。

**架构：** 改动集中在 `tg-config.el` 解析层 + 各模块 struct/display 微调。功能代码已就位，只缺解析桥接。

**技术栈：** Emacs Lisp, Org-mode (org-element), ERT

---

## 文件结构

| 文件 | 职责 | 操作 |
|---|---|---|
| `tg-config.el` | Org 配置解析器（4 处解析逻辑修改 + 1 个新辅助函数 + 1 个新 section handler） | 修改 |
| `tg-quest.el` | 任务 struct 加 2 字段 + track-quest 输出 completion-text | 修改 |
| `tg-action.el` | quests/quest 命令显示描述 | 修改 |
| `sample/game.org` | 使用全部 4 个新特性 | 修改 |
| `sample/handlers.el` | 移除 Level setq | 修改 |
| `test/tg-config-test.el` | 4 组解析测试 | 修改 |
| `test/tg-dialog-test.el` | 条件过滤测试 | 修改 |
| `test/tg-quest-test.el` | 新字段测试 | 修改 |
| `test/tg-action-test.el` | 显示逻辑测试 | 修改 |
| `test/tg-object-test.el` | 容器初始化测试 | 修改 |

---

### 任务 1：对话选项条件解析

**依赖：** 无
**文件集：** `tg-config.el`, `test/tg-config-test.el`, `test/tg-dialog-test.el`, `sample/game.org`
**导出/变更接口：** `tg-config.el::tg-config--parse-dialog-option`
**消费接口：** `tg-dialog.el::tg-dialog-eval-condition`
**复杂度：** standard

**文件：**
- 修改：`tg-config.el:118-138`（`tg-config--parse-dialog-option` 函数）
- 修改：`sample/game.org:413`（prisoner 对话第三行）
- 修改：`test/tg-config-test.el`（末尾追加测试）
- 修改：`test/tg-dialog-test.el`（末尾追加测试）

- [ ] **步骤 1：编写条件解析测试**

在 `test/tg-config-test.el` 末尾添加：

```elisp
(ert-deftest test-tg-config-parse-dialog-option-with-condition ()
  "测试解析带条件的对话选项。"
  (let ((opt (tg-config--parse-dialog-option "[(has-item bread)] 给你面包 :: 谢谢！ → (exp 10)")))
    (should opt)
    (should (equal (tg-dialog-option-condition opt) '(has-item bread)))
    (should (string= (tg-dialog-option-text opt) "给你面包"))
    (should (string= (tg-dialog-option-response opt) "谢谢！"))
    (should (equal (tg-dialog-option-effects opt) '((exp 10))))))

(ert-deftest test-tg-config-parse-dialog-option-without-condition ()
  "测试无条件的对话选项仍然正常解析。"
  (let ((opt (tg-config--parse-dialog-option "你是谁？ :: 我是探险者。")))
    (should opt)
    (should (null (tg-dialog-option-condition opt)))
    (should (string= (tg-dialog-option-text opt) "你是谁？"))
    (should (string= (tg-dialog-option-response opt) "我是探险者。"))))
```

在 `test/tg-dialog-test.el` 末尾添加：

```elisp
(ert-deftest test-tg-dialog-filter-options-with-condition ()
  "测试条件过滤：无面包时条件选项不可见。"
  (let ((dialog (make-tg-dialog-state
                  :node-id 'test :npc-symbol 'test
                  :greeting "" :options
                  (list (make-tg-dialog-option :text "无条件的选项"
                                               :response "OK"
                                               :condition nil)
                        (make-tg-dialog-option :text "需要面包"
                                               :response "谢谢"
                                               :condition '(has-item bread))))))
    ;; 玩家没有面包时
    (let ((visible (tg-dialog-filter-options dialog)))
      (should (= (length visible) 1))
      (should (string= (tg-dialog-option-text (car visible)) "无条件的选项")))))
```

- [ ] **步骤 2：运行测试验证失败**

```bash
emacs -batch -L . -l test/tg-config-test.el --eval '(ert-run-tests-batch "test-tg-config-parse-dialog-option-with")' 2>&1 | tail -3
emacs -batch -L . -l test/tg-dialog-test.el -l test/tg-quest-test.el -l test/tg-creature-test.el -l test/tg-game-test.el --eval '(ert-run-tests-batch "test-tg-dialog-filter-options-with-condition")' 2>&1 | tail -3
```

预期：FAILED

- [ ] **步骤 3：修改 `tg-config--parse-dialog-option`**

在 `tg-config.el:118` 的 `tg-config--parse-dialog-option` 函数中，在解析 line 之前添加条件提取逻辑：

```elisp
(defun tg-config--parse-dialog-option (line)
  "解析对话选项行
line: 格式为 \"[条件] 选项文本 :: 响应文本 → effects → next-node-id\"
返回: tg-dialog-option 结构或 nil"
  (let ((condition nil)
        (remaining line))
    ;; 检测行首条件：[(condition)]
    (when (string-match "^\\[\\(.*?\\)\\]\s+" line)
      (setq condition (read (match-string 1 line)))
      (setq remaining (substring line (match-end 0))))
    ;; 原有解析逻辑，用 remaining 替代 line
    (let* ((parts (split-string remaining "→" t "[\s→]+"))
           ...原有逻辑...)
      (make-tg-dialog-option
       :text text
       :response response
       :condition condition    ;; 替代原来的 nil
       :effects effects
       :next-node next-node)))))
```

注意：只改两处——函数开头加 condition 提取，`:condition` 赋值从 `nil` 改为 `condition`。

- [ ] **步骤 4：运行测试验证通过**

```bash
emacs -batch -L . -l test/tg-config-test.el -l test/tg-dialog-test.el -l test/tg-quest-test.el -l test/tg-creature-test.el -l test/tg-game-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 5：更新 `sample/game.org`**

将 prisoner 对话第三行（约第 413 行）改为：

```org
[(has-item bread)] 给你点面包 :: 谢谢你！这个给你，是我在牢房角落找到的。 → (exp 10)
```

- [ ] **步骤 6：Commit**

```bash
git add tg-config.el test/tg-config-test.el test/tg-dialog-test.el sample/game.org
git commit -m "feat: parse dialog option conditions from Org config"
```

---

### 任务 2：Level Org 配置段

**依赖：** 无
**文件集：** `tg-config.el`, `test/tg-config-test.el`, `sample/game.org`, `sample/handlers.el`
**导出/变更接口：** `tg-config.el::tg-config--parse-level-section`, `tg-config.el::tg-config--parse-int-list`
**消费接口：** `tg-level.el::tg-level-exp-table`, `tg-level.el::tg-level-bonus-points-per-level`, `tg-level.el::tg-level-auto-upgrade-attrs`
**复杂度：** standard

**文件：**
- 修改：`tg-config.el:377-390`（section 分发）+ 新增函数
- 修改：`sample/game.org`（末尾追加 Level 段）
- 修改：`sample/handlers.el`（移除 Level setq）
- 修改：`test/tg-config-test.el`（追加测试）

- [ ] **步骤 1：编写 Level 段解析测试**

在 `test/tg-config-test.el` 末尾添加：

```elisp
(ert-deftest test-tg-config-parse-level-section ()
  "测试 Level 段解析设置全局变量。"
  (let ((default-table tg-level-exp-table)
        (default-bonus tg-level-bonus-points-per-level)
        (default-auto tg-level-auto-upgrade-attrs))
    (unwind-protect
        (progn
          (tg-config-load (expand-file-name "test/fixtures/mini-game/game.org"))
          ;; mini-game 没有 Level 段，应保持默认值
          (should (equal tg-level-exp-table default-table)))
      ;; 恢复默认值
      (setq tg-level-exp-table default-table
            tg-level-bonus-points-per-level default-bonus
            tg-level-auto-upgrade-attrs default-auto))))
```

同时需要一个带 Level 段的 fixture 来测试解析。在 `test/fixtures/` 下创建 `level-game.org`：

```org
#+TITLE: Level Test
#+START: room1
#+PLAYER: hero

* Rooms

** room1
:PROPERTIES:
:NAME: 测试房间
:DESC: 测试
:END:

* Creatures

** hero
:PROPERTIES:
:NAME: 英雄
:ATTR: hp 100 attack 5 defense 3 exp 0 level 1 bonus-points 0
:END:

* Level
:PROPERTIES:
:EXP_TABLE: 0,100,200,400
:BONUS_POINTS: 5
:AUTO_UPGRADE: hp 20 attack 1
:END:
```

添加带 Level 段的测试：

```elisp
(ert-deftest test-tg-config-parse-level-section-with-data ()
  "测试 Level 段解析设置全局变量。"
  (let ((default-table tg-level-exp-table)
        (default-bonus tg-level-bonus-points-per-level)
        (default-auto tg-level-auto-upgrade-attrs))
    (unwind-protect
        (progn
          (tg-config-load (expand-file-name "test/fixtures/level-game.org"))
          (should (equal tg-level-exp-table '(0 100 200 400)))
          (should (eq tg-level-bonus-points-per-level 5))
          (should (equal tg-level-auto-upgrade-attrs '((hp 20) (attack 1)))))
      (setq tg-level-exp-table default-table
            tg-level-bonus-points-per-level default-bonus
            tg-level-auto-upgrade-attrs default-auto)
      (tg-registry-clear))))
```

- [ ] **步骤 2：运行测试验证失败**

```bash
emacs -batch -L . -l test/tg-config-test.el --eval '(ert-run-tests-batch "test-tg-config-parse-level")' 2>&1 | tail -3
```

预期：FAILED（函数不存在）

- [ ] **步骤 3：实现解析逻辑**

在 `tg-config.el` 中：

1. 新增辅助函数 `tg-config--parse-int-list`（放在 `tg-config--split-list` 之后）：

```elisp
(defun tg-config--parse-int-list (str)
  "将逗号分隔的整数字符串转为整数列表。"
  (when (and str (not (string-empty-p (string-trim str))))
    (mapcar #'string-to-number (split-string str "," t "[\s]+"))))
```

2. 新增 `tg-config--parse-level-section`：

```elisp
(defun tg-config--parse-level-section (headline)
  "解析 Level section，设置全局升级变量。"
  (let ((exp-table (tg-config--parse-int-list (tg-config--read-property headline "EXP_TABLE")))
        (bonus (tg-config--read-property headline "BONUS_POINTS"))
        (auto-upgrade (tg-config--parse-attr (tg-config--read-property headline "AUTO_UPGRADE"))))
    (when exp-table (setq tg-level-exp-table exp-table))
    (when bonus (setq tg-level-bonus-points-per-level (string-to-number bonus)))
    (when auto-upgrade (setq tg-level-auto-upgrade-attrs auto-upgrade))))
```

3. 在 section 分发（约第 389 行 `quests` 之后）添加：

```elisp
     ((string-equal section-name "level")
      (tg-config--parse-level-section section))
```

4. 在文件顶部添加 `(require 'tg-level)`（确保 `tg-level-exp-table` 等变量可用）。

- [ ] **步骤 4：运行测试验证通过**

```bash
emacs -batch -L . -l test/tg-config-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 5：更新 sample**

在 `sample/game.org` 末尾（Quests 段之后）追加 Level 段：

```org

* Level
:PROPERTIES:
:EXP_TABLE: 0,50,120,220,350,500,700,950,1300,1700
:BONUS_POINTS: 3
:AUTO_UPGRADE: hp 10
:END:
```

将 `sample/handlers.el` 中的 Level 相关 setq 移除，只保留 `(provide 'handlers)` 骨架。

- [ ] **步骤 6：Commit**

```bash
git add tg-config.el test/tg-config-test.el test/fixtures/level-game.org sample/game.org sample/handlers.el
git commit -m "feat: parse Level section from Org config"
```

---

### 任务 3：任务描述/完成文本

**依赖：** 无
**文件集：** `tg-quest.el`, `tg-config.el`, `tg-action.el`, `test/tg-quest-test.el`, `test/tg-action-test.el`, `sample/game.org`
**导出/变更接口：** `tg-quest.el::tg-quest`（struct 加字段）, `tg-quest.el::tg-track-quest`, `tg-action.el::tg-action--handler-quests`, `tg-action.el::tg-action--handler-quest`
**消费接口：** 无
**复杂度：** standard

**文件：**
- 修改：`tg-quest.el:10-17`（struct）+ `tg-quest.el:47-51`（track-quest 完成逻辑）
- 修改：`tg-config.el:298-321`（quest 解析）
- 修改：`tg-action.el:642-685`（两个 handler）
- 修改：`test/tg-quest-test.el`, `test/tg-action-test.el`（追加测试）
- 修改：`sample/game.org`（6 个 quest 添加 DESCRIPTION/COMPLETION）

- [ ] **步骤 1：修改 `tg-quest` struct**

在 `tg-quest.el:17` 的 `rewards)` 之后添加 2 个字段：

```elisp
  (cl-defstruct tg-quest
    symbol type target count progress status rewards
    description      ;; 任务描述文本 (string or nil)
    completion-text) ;; 完成时显示文本 (string or nil)
```

- [ ] **步骤 2：修改 `tg-track-quest` 完成逻辑**

在 `tg-quest.el:47-51` 的 `when (>= new-progress ...)` 块中，在 `(setf (tg-quest-status quest) 'completed)` 之后、`(tg-quest--give-rewards ...)` 之前插入：

```elisp
(when (tg-quest-completion-text quest)
  (tg-message "%s" (tg-quest-completion-text quest)))
```

注意：`tg-message` 在运行时可用（通过 tg-commands.el），不需要 require。

- [ ] **步骤 3：修改 quest 解析器**

在 `tg-config.el` 的 `tg-config--parse-quest-section`（约第 314 行 `make-tg-quest` 调用）中，在 `:rewards rewards` 之后添加：

```elisp
:description (tg-config--read-property child "DESCRIPTION")
:completion-text (tg-config--read-property child "COMPLETION")
```

- [ ] **步骤 4：修改 quest 显示**

`tg-action--handler-quests`（约第 653 行）：将 `(symbol-name sym)` 替换为：

```elisp
(or (tg-quest-description quest) (symbol-name sym))
```

`tg-action--handler-quest`（约第 679 行）：将 `(tg-message "【%s】" do-key)` 替换为：

```elisp
(tg-message "【%s】" (or (tg-quest-description quest) (symbol-name do-key)))
```

- [ ] **步骤 5：编写测试**

在 `test/tg-quest-test.el` 末尾添加：

```elisp
(ert-deftest test-tg-quest-description-field ()
  "测试 quest struct 新字段。"
  (let ((q (make-tg-quest :symbol 'test :type 'kill :target 'rat
                          :count 1 :progress 0 :status 'active :rewards nil
                          :description "消灭老鼠" :completion-text "干得好！")))
    (should (string= (tg-quest-description q) "消灭老鼠"))
    (should (string= (tg-quest-completion-text q) "干得好！"))
    (should (null (tg-quest-description (make-tg-quest))))))

(ert-deftest test-tg-quest-completion-text-on-complete ()
  "测试任务完成时输出 completion-text。"
  (let ((output nil))
    (let ((tg-message-hook (list (lambda (text) (push text output)))))
      (tg-registry-clear)
      (tg-register-quest 'test-q (make-tg-quest :symbol 'test-q :type 'kill
                                                  :target 'rat :count 1 :progress 0
                                                  :status 'active :rewards nil
                                                  :completion-text "任务完成！"))
      (tg-register-creature 'hero (make-tg-creature :symbol 'hero :name "Hero"
                                                     :attr '((hp 100))))
      (let ((tg-game (tg-new-game "Test" "Author")))
        (tg-game-put tg-game :player 'hero)
        (tg-track-quest 'kill 'rat))
      (should (cl-member "任务完成！" output :test (lambda (s1 s2) (string-match s1 s2))))))
  (tg-registry-clear))
```

- [ ] **步骤 6：运行测试验证通过**

```bash
emacs -batch -L . -l test/tg-quest-test.el -l test/tg-action-test.el -l test/tg-registry-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 7：更新 `sample/game.org`**

为 6 个 quest 添加 DESCRIPTION 和 COMPLETION 字段。示例：

```org
** kill-rat
:PROPERTIES:
:TYPE: kill
:TARGET: rat
:COUNT: 1
:DESCRIPTION: 消灭地牢里的老鼠
:COMPLETION: 你消灭了那只老鼠！
:REWARDS: (exp 10)
:END:
```

6 个任务的描述/完成文本：

| quest | DESCRIPTION | COMPLETION |
|---|---|---|
| kill-rat | 消灭地牢里的老鼠 | 你消灭了那只老鼠！ |
| talk-prisoner | 与囚犯交谈 | 囚犯感谢你的帮助！ |
| collect-sword | 获得铁剑 | 你找到了一把铁剑！ |
| kill-goblin | 消灭狡猾的哥布林 | 哥布林被你击败了！ |
| explore-throne | 探索王座间 | 你踏入了王座间！ |
| defeat-skeleton-king | 击败骷髅王 | 骷髅王倒下了！你赢得了最终的胜利！ |

- [ ] **步骤 8：Commit**

```bash
git add tg-quest.el tg-config.el tg-action.el test/tg-quest-test.el sample/game.org
git commit -m "feat: add quest description and completion text"
```

---

### 任务 4：Object 容器初始化

**依赖：** 无
**文件集：** `tg-config.el`, `test/tg-config-test.el`, `test/tg-object-test.el`, `sample/game.org`
**导出/变更接口：** `tg-config.el::tg-config--parse-object-section`
**消费接口：** `tg-config.el::tg-config--split-list`
**复杂度：** quick

**文件：**
- 修改：`tg-config.el:192-193`（硬编码的 `:contents nil :supports nil`）
- 修改：`sample/game.org`（新增 chest/table 对象 + 修改 throne/hall CONTENTS）
- 修改：`test/tg-config-test.el`, `test/tg-object-test.el`（追加测试）

- [ ] **步骤 1：编写测试**

在 `test/tg-config-test.el` 末尾添加：

```elisp
(ert-deftest test-tg-config-parse-object-with-contents ()
  "测试解析容器对象的 CONTENTS 字段。"
  (tg-registry-clear)
  (let ((org-content "
* Objects
** chest
:PROPERTIES:
:NAME: 宝箱
:PROPS: container
:CONTENTS: coin,gem
:END:
"))
    (with-temp-buffer
      (insert org-content)
      (org-mode)
      (let* ((tree (org-element-parse-buffer))
             (objects-section (org-element-map tree 'headline
                               (lambda (h) (when (string= (downcase (org-element-property :raw-value h)) "objects") h))
                               nil t)))
        (tg-config--parse-object-section objects-section)
        (let ((chest (tg-get-object 'chest)))
          (should chest)
          (should (equal (tg-object-contents chest) '(coin gem)))))))
  (tg-registry-clear))

(ert-deftest test-tg-config-parse-object-with-supports ()
  "测试解析支撑物对象的 SUPPORTS 字段。"
  (tg-registry-clear)
  (let ((org-content "
* Objects
** table
:PROPERTIES:
:NAME: 木桌
:PROPS: supporter
:SUPPORTS: lamp,book
:END:
"))
    (with-temp-buffer
      (insert org-content)
      (org-mode)
      (let* ((tree (org-element-parse-buffer))
             (objects-section (org-element-map tree 'headline
                               (lambda (h) (when (string= (downcase (org-element-property :raw-value h)) "objects") h))
                               nil t)))
        (tg-config--parse-object-section objects-section)
        (let ((table (tg-get-object 'table)))
          (should table)
          (should (equal (tg-object-supports table) '(lamp book)))))))
  (tg-registry-clear))
```

- [ ] **步骤 2：运行测试验证失败**

```bash
emacs -batch -L . -l test/tg-config-test.el --eval '(ert-run-tests-batch "test-tg-config-parse-object-with")' 2>&1 | tail -3
```

- [ ] **步骤 3：修改 `tg-config--parse-object-section`**

在 `tg-config.el` 约 `tg-config--parse-object-section` 函数中，找到 `:contents nil :supports nil` 的 `make-tg-object` 调用，将其替换为：

```elisp
:contents (tg-config--split-list (tg-config--read-property child "CONTENTS"))
:supports (tg-config--split-list (tg-config--read-property child "SUPPORTS"))
```

- [ ] **步骤 4：运行测试验证通过**

```bash
emacs -batch -L . -l test/tg-config-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 5：更新 `sample/game.org`**

1. 在 Objects 段末尾（helmet 之后）追加两个新对象：

```org

** chest
:PROPERTIES:
:NAME: 宝箱
:SYNONYMS: chest
:PROPS: container,openable
:CONTENTS: gem
:STATE: closed
:KEY: rusty-key
:END:

** table
:PROPERTIES:
:NAME: 木桌
:SYNONYMS: table
:PROPS: supporter
:SUPPORTS: map
:END:
```

2. 修改 throne 房间 CONTENTS（约第 64 行）：`crown,gem,sword-of-king` → `crown,sword-of-king,chest`（gem 移入 chest，chest 放入 throne）

3. 修改 hall 房间 CONTENTS（约第 54 行）：`map,potion,gold` → `potion,gold,table`（map 移到 table 上，table 放入 hall）

- [ ] **步骤 6：Commit**

```bash
git add tg-config.el test/tg-config-test.el sample/game.org
git commit -m "feat: parse object contents/supports from Org config"
```

---

### 任务 5：集成验证与文档更新

**依赖：** 任务 1, 任务 2, 任务 3, 任务 4
**文件集：** `README.md`, `docs/manual.org`
**导出/变更接口：** 无
**消费接口：** 无
**复杂度：** quick

**文件：**
- 修改：`README.md`（TODO 段清除已完成项）
- 修改：`docs/manual.org`（补充 4 个新特性的文档）

- [ ] **步骤 1：运行全量测试确认无回归**

```bash
emacs -batch -L . -l test/tg-registry-test.el -l test/tg-game-test.el -l test/tg-object-test.el -l test/tg-creature-test.el -l test/tg-room-test.el -l test/tg-action-test.el -l test/tg-parser-test.el -l test/tg-commands-test.el -l test/tg-dialog-test.el -l test/tg-npc-test.el -l test/tg-quest-test.el -l test/tg-shop-test.el -l test/tg-level-test.el -l test/tg-builtin-test.el -l test/tg-config-test.el -l test/tg-config-gen-test.el -l test/tg-save-test.el -l test/tg-mode-test.el -l test/tg-integration-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 2：验证 sample 游戏加载**

```bash
emacs -batch -L . --eval '(progn (require (quote tg)) (tg-init "sample/game.org") (princ (format "location: %s\n" (tg-game-get tg-game :location))))' 2>&1 | grep location
```

- [ ] **步骤 3：更新 README.md TODO 段**

移除已完成的 4 条 TODO，替换为空表格或剩余 TODO。若无剩余 TODO，删除 TODO 章节。

- [ ] **步骤 4：更新 `docs/manual.org`**

补充 4 个新特性的文档：
- Dialogs Section：说明 `[条件]` 前缀语法和条件表达式
- Level Section：新增 Level 配置段说明
- Quests Section：新增 DESCRIPTION 和 COMPLETION 字段
- Objects Section：新增 CONTENTS 和 SUPPORTS 字段

- [ ] **步骤 5：Commit**

```bash
git add README.md docs/manual.org
git commit -m "docs: update README and manual for new Org config features"
```

---

## 并行执行图

> 仅 `parallel-executing-plans` 使用；`serial-executing-plans` 忽略本节。

**Critical Path:** 任务 1 → 任务 5（或任务 2/3/4 → 任务 5）

- Wave 1（无依赖）：任务 1, 任务 2, 任务 3, 任务 4
- Wave 2（依赖 Wave 1）：任务 5（依赖 1, 2, 3, 4）

---

## 执行交接

计划已完成并保存到 `docs/superpowers/plans/2026-05-12-org-parser-gaps.md`。两种执行方式：

**1. 子代理驱动（适合较大计划）** - 4 个 Wave 1 任务可并行（文件集互不相交），但 tg-config.el 被任务 1-4 共享，Wave 1 内 4 任务有文件集冲突。必须串行执行。

**2. 串行执行（推荐）** - 使用 `superpowers:serial-executing-plans` 按任务编号执行。任务 1-4 共享 tg-config.el 但改动不同函数，串行安全。
