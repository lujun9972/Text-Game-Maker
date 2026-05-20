# Creature 刷新机制实现计划

> **面向 AI 代理的工作者：** 必需子技能：`superpowers:serial-executing-plans`（任务共享 tg-config.el 和 tg-creature.el，强耦合）。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现小兵死亡后按随机回合区间自动刷新，恢复初始状态。

**架构：** 新增 `tg-respawn.el` 模块负责 schedule/tick/restore。creature struct 加 4 字段（respawn-interval + 3 个 initial 快照）。tg-config 解析 RESPAWN 属性。tg-commands dispatch 中每回合调用 tick。tg-action attack 死亡时调用 schedule。tg-save 持久化刷新队列。

**技术栈：** Emacs Lisp, org-element, ERT

---

### 任务 1：tg-creature struct 加字段

**依赖：** 无
**文件集：** `tg-creature.el`, `test/tg-creature-test.el`
**导出/变更接口：** `tg-creature.el::tg-creature`
**消费接口：** 无
**复杂度：** quick

**文件：**
- 修改：`tg-creature.el:7-17`（struct 定义）
- 修改：`test/tg-creature-test.el`（追加测试）

- [ ] **步骤 1：在 struct 末尾新增 4 个字段**

在 `tg-creature.el:17` 的 `handler)` 之后添加：

```elisp
  (cl-defstruct tg-creature
    ...
    handler          ;; 自定义处理函数
    respawn-interval ;; 刷新区间 (min . max) cons 或 nil
    initial-attr     ;; 初始属性快照（解析时 copy-tree 保存）
    initial-inventory ;; 初始背包（解析时 copy-sequence 保存）
    initial-equipment) ;; 初始装备（解析时 copy-sequence 保存）
```

- [ ] **步骤 2：编写 struct 新字段测试**

在 `test/tg-creature-test.el` 末尾（provide 之前）追加：

```elisp
(ert-deftest test-tg-creature-respawn-fields ()
  "测试刷新相关字段"
  (let ((c (make-tg-creature :symbol 'goblin :name "哥布林"
                              :attr '((hp 30) (attack 5))
                              :inventory '(sword)
                              :equipment '(helmet)
                              :respawn-interval '(8 . 15)
                              :initial-attr '((hp 30) (attack 5))
                              :initial-inventory '(sword)
                              :initial-equipment '(helmet))))
    (should (equal (tg-creature-respawn-interval c) '(8 . 15)))
    (should (equal (tg-creature-initial-attr c) '((hp 30) (attack 5))))
    (should (equal (tg-creature-initial-inventory c) '(sword)))
    (should (equal (tg-creature-initial-equipment c) '(helmet)))
    ;; 不刷新生物这些字段为 nil
    (let ((c2 (make-tg-creature :symbol 'guard)))
      (should (null (tg-creature-respawn-interval c2)))
      (should (null (tg-creature-initial-attr c2))))))
```

- [ ] **步骤 3：运行测试验证通过**

```bash
emacs -batch -L . -l test/tg-creature-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 4：Commit**

```bash
git add tg-creature.el test/tg-creature-test.el
git commit -m "feat: add respawn fields to tg-creature struct"
```

---

### 任务 2：tg-respawn.el 核心模块

**依赖：** 任务 1
**文件集：** `tg-respawn.el`, `test/tg-respawn-test.el`
**导出/变更接口：** `tg-respawn.el::tg-respawn-schedule`, `tg-respawn.el::tg-respawn-tick`, `tg-respawn.el::tg-respawn-restore`, `tg-respawn.el::tg-respawn-default-interval`
**消费接口：** `tg-creature.el::tg-creature-dead-p`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game-put`, `tg-registry.el::tg-get-creature`, `tg-room.el::tg-room-creatures`
**复杂度：** standard

**文件：**
- 创建：`tg-respawn.el`
- 创建：`test/tg-respawn-test.el`

**关键约束：**
- `tg-respawn.el` 不 require `tg-commands`（避免循环依赖）
- `tg-message` 在运行时可用但不 require
- `tg-respawn-restore` 通过 `(tg-game-get tg-game :location)` 获取当前房间，`tg-get-room` + `tg-room-creatures` 判断 creature 是否与玩家同房间

- [ ] **步骤 1：编写失败的测试**

创建 `test/tg-respawn-test.el`：

```elisp
;;; test/tg-respawn-test.el --- tg-respawn 测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-creature)
(require 'tg-respawn)
(require 'tg-commands)                  ;; tg-message for notification mock

(ert-deftest test-tg-respawn-schedule-basic ()
  "测试死亡调度加入队列"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (let ((queue (tg-game-get tg-game :respawn-queue)))
    (should (= (length queue) 1))
    (should (eq (caar queue) 'goblin))
    (should (<= 15 (cdar queue)))  ;; 10 + [5,10]
    (should (>= 20 (cdar queue))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-no-interval ()
  "测试无 interval 时不调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'guard (make-tg-creature :symbol 'guard :name "守卫"
                                                   :attr '((hp 0))  ;; 已死亡
                                                   :respawn-interval nil))
  (tg-respawn-schedule 'guard)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-shopkeeper ()
  "测试 shopkeeper 不调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'merchant (make-tg-creature :symbol 'merchant :name "商人"
                                                      :attr '((hp 0))  ;; 已死亡
                                                      :respawn-interval '(5 . 10)
                                                      :shopkeeper t))
  (tg-respawn-schedule 'merchant)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-dedup ()
  "测试防重复调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (tg-respawn-schedule 'goblin)  ;; 第二次应跳过
  (should (= (length (tg-game-get tg-game :respawn-queue)) 1))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-tick-restore ()
  "测试 tick 到达时恢复 creature"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 20)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :inventory nil
                                                    :equipment nil
                                                    :respawn-interval '(5 . 10)
                                                    :initial-attr '((hp 30) (attack 5))
                                                    :initial-inventory '(sword)
                                                    :initial-equipment '(helmet)))
  ;; 手动加入队列，respawn-turn = 15（已过期）
  (tg-game-put tg-game :respawn-queue '((goblin . 15)))
  (tg-respawn-tick)
  ;; 队列应清空
  (should (null (tg-game-get tg-game :respawn-queue)))
  ;; creature 应恢复
  (let ((c (tg-get-creature 'goblin)))
    (should (= (tg-creature-attr-get c 'hp) 30))
    (should (= (tg-creature-attr-get c 'attack) 5))
    (should (equal (tg-creature-inventory c) '(sword)))
    (should (equal (tg-creature-equipment c) '(helmet))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-tick-not-yet ()
  "测试 tick 未到达时不恢复"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :attr '((hp 0))
                                                    :initial-attr '((hp 30))))
  (tg-game-put tg-game :respawn-queue '((goblin . 20)))
  (tg-respawn-tick)
  ;; 队列不变
  (should (equal (tg-game-get tg-game :respawn-queue) '((goblin . 20))))
  ;; creature 仍为死亡
  (should (tg-creature-dead-p (tg-get-creature 'goblin)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-restore-isolation ()
  "测试恢复后的 attr 与 initial-attr 独立"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin
                                                    :attr '((hp 0))
                                                    :initial-attr '((hp 30) (attack 5))))
  (tg-respawn-restore 'goblin)
  (let ((c (tg-get-creature 'goblin)))
    ;; 修改 attr 不影响 initial-attr
    (tg-creature-take-effect c '(hp -10))
    (should (= (tg-creature-attr-get c 'hp) 20))
    (should (= (tg-creature-attr-get c 'attack) 5))
    (should (equal (tg-creature-initial-attr c) '((hp 30) (attack 5)))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-alive ()
  "测试活着 creature 的 dead-p 守卫"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin
                                                    :attr '((hp 30))  ;; 还活着
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-restore-notification ()
  "测试同房间刷新有通知，异房间无通知"
  (require 'tg-room)
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  ;; 创建房间
  (tg-register-room 'forest (make-tg-room :symbol 'forest :name "森林" :creatures '(goblin)))
  (tg-register-room 'cave (make-tg-room :symbol 'cave :name "洞穴"))
  ;; 创建已死亡 creature
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))
                                                    :initial-attr '((hp 30))
                                                    :respawn-interval '(5 . 10)))
  ;; Mock tg-message 捕获输出
  (let ((captured-output nil))
    (cl-letf (((symbol-function 'tg-message)
               (lambda (fmt &rest args)
                 (setq captured-output (apply #'format fmt args)))))
      ;; 场景 1：玩家与 creature 同房间 — 应通知
      (tg-game-put tg-game :location 'forest)
      (tg-respawn-restore 'goblin)
      (should captured-output)
      (should (string-match "哥布林" captured-output))
      ;; 重置
      (setq captured-output nil)
      (setf (tg-creature-attr (tg-get-creature 'goblin)) '((hp 0)))
      ;; 场景 2：玩家在另一个房间 — 不通知
      (tg-game-put tg-game :location 'cave)
      (tg-respawn-restore 'goblin)
      (should (null captured-output))))
  (tg-registry-clear))

(provide 'tg-respawn-test)
```

- [ ] **步骤 2：运行测试验证失败**

```bash
emacs -batch -L . -l test/tg-respawn-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

预期：FAILED（tg-respawn.el 模块不存在）

- [ ] **步骤 3：创建 tg-respawn.el**

```elisp
;;; tg-respawn.el --- 生物刷新系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-creature)
(require 'tg-room)

(defvar tg-respawn-default-interval nil
  "默认刷新区间 (min . max) 或 nil（不刷新）")

(defun tg-respawn-schedule (creature-symbol)
  "死亡时调用，将 creature 加入刷新队列。
通过全局 tg-game 访问游戏状态。"
  (let ((creature (tg-get-creature creature-symbol)))
    (when (and creature
               (tg-creature-dead-p creature)  ;; 只调度已死亡的
               (tg-creature-respawn-interval creature)  ;; 有刷新配置
               (not (tg-creature-shopkeeper creature))   ;; 非 shopkeeper
               (not (assq creature-symbol (tg-game-get tg-game :respawn-queue)))) ;; 防重复
      (let* ((interval (tg-creature-respawn-interval creature))
             (min-val (car interval))
             (max-val (cdr interval))
             (random-offset (+ min-val (random (1+ (- max-val min-val)))))
             (current-turn (or (tg-game-get tg-game :turns) 0))
             (respawn-turn (+ current-turn random-offset))
             (queue (tg-game-get tg-game :respawn-queue)))
        (tg-game-put tg-game :respawn-queue
                     (append queue (list (cons creature-symbol respawn-turn)))))))))

(defun tg-respawn-tick ()
  "每回合调用，检查并执行到期的刷新。
通过全局 tg-game 访问游戏状态。"
  (let* ((current-turn (tg-game-get tg-game :turns))
         (queue (tg-game-get tg-game :respawn-queue))
         (remaining nil))
    (dolist (entry queue)
      (if (<= (cdr entry) current-turn)
          (tg-respawn-restore (car entry))
        (push entry remaining)))
    (tg-game-put tg-game :respawn-queue (nreverse remaining)))))

(defun tg-respawn-restore (creature-symbol)
  "恢复 creature 到初始状态。
通过全局 tg-game 访问游戏状态。
tg-message 运行时可用（不 require tg-commands 避免循环依赖）。"
  (let ((creature (tg-get-creature creature-symbol)))
    (when (and creature (tg-creature-p creature))  ;; 必须是 creature struct
      ;; 恢复 attr（copy-tree 深拷贝）
      (when (tg-creature-initial-attr creature)
        (setf (tg-creature-attr creature)
              (copy-tree (tg-creature-initial-attr creature))))
      ;; 恢复 inventory（copy-sequence，元素是 symbol/immutable；若变为 mutable struct 需升级为 copy-tree）
      (when (tg-creature-initial-inventory creature)
        (setf (tg-creature-inventory creature)
              (copy-sequence (tg-creature-initial-inventory creature))))
      ;; 恢复 equipment
      (when (tg-creature-initial-equipment creature)
        (setf (tg-creature-equipment creature)
              (copy-sequence (tg-creature-initial-equipment creature))))
      ;; 同房间通知
      (let ((current-room-sym (tg-game-get tg-game :location)))
        (when current-room-sym
          (let ((room (tg-get-room current-room-sym)))
            (when (and room (memq creature-symbol (tg-room-creatures room)))
              (tg-message "%s从地上爬了起来！" (tg-creature-name creature)))))))))

(provide 'tg-respawn)
;;; tg-respawn.el ends here
```

- [ ] **步骤 4：运行测试验证通过**

```bash
emacs -batch -L . -l tg-commands.el -l test/tg-respawn-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

注意：需要 `-l tg-commands.el` 使 `tg-message` 可用。

- [ ] **步骤 5：Commit**

```bash
git add tg-respawn.el test/tg-respawn-test.el
git commit -m "feat: add tg-respawn module with schedule/tick/restore"
```

---

### 任务 3：tg-config 解析 RESPAWN

**依赖：** 任务 1, 任务 2
**文件集：** `tg-config.el`, `test/tg-config-test.el`
**导出/变更接口：** `tg-config.el::tg-config--parse-respawn-interval`
**消费接口：** `tg-respawn.el::tg-respawn-default-interval`
**复杂度：** standard

**文件：**
- 修改：`tg-config.el:49-55`（辅助函数区域，新增 parse-respawn-interval）
- 修改：`tg-config.el:14`（添加 require tg-respawn）
- 修改：`tg-config.el:220-248`（creature 解析）
- 修改：`tg-config.el:355-394`（tg-config-load，重置+解析全局关键字）
- 修改：`test/tg-config-test.el`（追加测试）

- [ ] **步骤 1：编写失败的测试**

在 `test/tg-config-test.el` 末尾（provide 之前）追加：

```elisp
(ert-deftest test-tg-config-parse-respawn-interval ()
  "测试刷新区间解析"
  (should (equal (tg-config--parse-respawn-interval "8-15") '(8 . 15)))
  (should (equal (tg-config--parse-respawn-interval "10") '(10 . 10)))
  (should (null (tg-config--parse-respawn-interval nil)))
  (should (null (tg-config--parse-respawn-interval "")))
  (should (null (tg-config--parse-respawn-interval "15-8")))  ;; N > M → nil
  (should (null (tg-config--parse-respawn-interval "0")))     ;; 0 → nil（无效间隔）
  (should (null (tg-config--parse-respawn-interval "0-0")))   ;; 0-0 → nil
  (should (null (tg-config--parse-respawn-interval "0-5")))   ;; min < 1 → nil
```

- [ ] **步骤 2：运行测试验证失败**

```bash
emacs -batch -L . -l test/tg-config-test.el --eval '(ert-run-tests-batch "test-tg-config-parse-respawn-interval")' 2>&1 | tail -3
```

- [ ] **步骤 3：添加 require tg-respawn**

在 `tg-config.el:14`（`(require 'tg-level)` 之后）添加：
```elisp
(require 'tg-respawn)
```

- [ ] **步骤 4：新增 tg-config--parse-respawn-interval**

在 `tg-config.el` 的 `tg-config--parse-int-list` 之后（约第 55 行）插入：

```elisp
(defun tg-config--parse-respawn-interval (str)
  "解析刷新区间字符串。
str: \"8-15\" → (8 . 15), \"10\" → (10 . 10), nil/\"\" → nil"
  (when (and str (not (string-empty-p (string-trim str))))
    (cond
     ((string-match "^\\([0-9]+\\)-\\([0-9]+\\)$" str)
      (let ((min-val (string-to-number (match-string 1 str)))
            (max-val (string-to-number (match-string 2 str))))
        (when (<= 1 min-val max-val)  ;; min 至少为 1
          (cons min-val max-val))))
     ((string-match "^[0-9]+$" str)
      (let ((n (string-to-number str)))
        (when (>= n 1)
          (cons n n))))
     (t nil))))
```

- [ ] **步骤 5：运行解析测试验证通过**

```bash
emacs -batch -L . -l test/tg-config-test.el --eval '(ert-run-tests-batch "test-tg-config-parse-respawn-interval")' 2>&1 | tail -3
```

- [ ] **步骤 6：修改 tg-config--parse-creature-section**

在 `tg-config.el:236`（handler 之后）和 `:237`（make-tg-creature 之前）之间新增解析逻辑，并修改 make-tg-creature 调用：

将现有的 let*/make-tg-creature 块（约第 224-248 行）修改为：

```elisp
        (let* ((sym (intern (org-element-property :raw-value child)))
               (name (tg-config--read-property child "NAME"))
               (attr (tg-config--parse-attr (tg-config--read-property child "ATTR")))
               (inventory (tg-config--split-list (tg-config--read-property child "INVENTORY")))
               (equipment (tg-config--split-list (tg-config--read-property child "EQUIPMENT")))
               (exp-reward-str (tg-config--read-property child "EXP_REWARD"))
               (exp-reward (when exp-reward-str (string-to-number exp-reward-str)))
               (behaviors-str (tg-config--read-property child "BEHAVIORS"))
               (behaviors (tg-config--parse-behaviors behaviors-str))
               (death-trigger (tg-config--resolve-handler (tg-config--read-property child "DEATH_TRIGGER")))
               (shopkeeper-str (tg-config--read-property child "SHOPKEEPER"))
               (shopkeeper (when shopkeeper-str (not (string-equal shopkeeper-str "nil"))))
               (handler (tg-config--resolve-handler (tg-config--read-property child "HANDLER")))
               ;; 刷新配置
               (respawn-interval (tg-config--parse-respawn-interval (tg-config--read-property child "RESPAWN")))
               ;; 全局默认：仅当 per-creature 无配置、非 shopkeeper、全局默认存在时使用
               (respawn-interval (if (and (not respawn-interval)
                                          (not shopkeeper)
                                          tg-respawn-default-interval)
                                     tg-respawn-default-interval
                                   respawn-interval))
               ;; 初始快照：仅当有刷新配置时保存
               (initial-attr (when respawn-interval (copy-tree attr)))
               (initial-inventory (when respawn-interval (copy-sequence inventory)))
               (initial-equipment (when respawn-interval (copy-sequence equipment)))
               (creature (make-tg-creature
                          :symbol sym
                          :name name
                          :attr attr
                          :inventory inventory
                          :equipment equipment
                          :exp-reward exp-reward
                          :behaviors behaviors
                          :death-trigger death-trigger
                          :shopkeeper shopkeeper
                          :handler handler
                          :respawn-interval respawn-interval
                          :initial-attr initial-attr
                          :initial-inventory initial-inventory
                          :initial-equipment initial-equipment)))
          (tg-register-creature sym creature))))))
```

- [ ] **步骤 7：修改 tg-config-load**

1. 在 `tg-config-load` 函数体开头（第 379 行 `;; 加载 handlers.el` 之前）添加：

```elisp
  ;; 重置刷新全局默认，防止旧值残留
  (setq tg-respawn-default-interval nil)
```

2. 在提取全局属性的 let 绑定中（第 391-394 行），添加 respawn-default：

```elisp
      (let ((title (tg-config--parse-keyword content "TITLE"))
            (author (or (tg-config--parse-keyword content "AUTHOR") "Unknown"))
            (start-room (tg-config--parse-keyword content "START"))
            (player-name (tg-config--parse-keyword content "PLAYER"))
            (respawn-default-str (tg-config--parse-keyword content "RESPAWN_DEFAULT")))
        ;; 设置刷新全局默认（在 section 解析之前）
        (when respawn-default-str
          (setq tg-respawn-default-interval
                (tg-config--parse-respawn-interval respawn-default-str)))
```

- [ ] **步骤 8：运行全部 config 测试验证通过**

```bash
emacs -batch -L . -l test/tg-config-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 9：Commit**

```bash
git add tg-config.el test/tg-config-test.el
git commit -m "feat: parse RESPAWN interval from Org config"
```

---

### 任务 4：接入 dispatch 和 attack handler

**依赖：** 任务 2, 任务 3
**文件集：** `tg-commands.el`, `tg-action.el`, `tg.el`, `test/tg-builtin-test.el`
**导出/变更接口：** 无
**消费接口：** `tg-respawn.el::tg-respawn-tick`, `tg-respawn.el::tg-respawn-schedule`
**复杂度：** standard

**文件：**
- 修改：`tg-commands.el:214`（dispatch 中调用 tick）
- 修改：`tg-action.el:412-422`（死亡掉落逻辑，装备+no-drop）
- 修改：`tg-action.el:434`（death 后调用 schedule）
- 修改：`tg.el:27`（require tg-respawn）
- 修改：`test/tg-builtin-test.el`（fixture 加 equipment + 新测试）

- [ ] **步骤 1：tg-commands.el 添加 tg-respawn-tick 调用**

在 `tg-commands.el:214`（`(tg-game-incf game :turns)` 之后）添加：

```elisp
        (tg-npc-run-behaviors game)
        (tg-buffs-tick game)
        (tg-game-incf game :turns)
        (tg-respawn-tick))))
```

替换原三行。

- [ ] **步骤 2a：tg-action.el 装备掉落 + no-drop 检查**

修改 `tg-action--handler-attack` 的死亡掉落逻辑（当前约第 412-422 行）。原逻辑只遍历 `inventory` 全掉落。改为合并 inventory + equipment 遍历，按 `no-drop` prop 过滤：

```elisp
;; 掉落物品（背包 + 装备，含 no-drop 过滤）
(let ((all-items (append (tg-creature-inventory creature)
                         (tg-creature-equipment creature)))
      (remaining-items nil))
  (dolist (item-sym all-items)
    (let ((obj (tg-get-object item-sym)))
      (if (and obj (memq 'no-drop (tg-object-props obj)))
          (push item-sym remaining-items)  ;; no-drop：保留
        ;; 掉落
        (tg-room-add-object room item-sym)
        (tg-message "%s掉落了%s。"
                    (tg-creature-name creature)
                    (tg-object-name obj)))))
  ;; 清空并保留 no-drop 物品
  (setf (tg-creature-inventory creature)
        (cl-intersection (tg-creature-inventory creature) remaining-items))
  (setf (tg-creature-equipment creature)
        (cl-intersection (tg-creature-equipment creature) remaining-items)))
```

注意：`cl-intersection` 保留 equipment 和 inventory 中属于 `remaining-items` 的物品。

同步修改 `test/tg-builtin-test.el`：

1. 修改 fixture：goblin 加 `:equipment '(wearable-armor)`，新增 no-drop 物件注册：

```elisp
;; 在 tg-builtin-test-setup 的对象注册区域追加：
(tg-register-object 'cursed-ring
  (make-tg-object :symbol 'cursed-ring :name "诅咒之戒" :synonyms '(ring)
                  :contents nil :supports nil :props '(no-drop wearable)
                  :state nil :key nil :effects '((attack 3)) :handler nil))

;; goblin 改为：
(let ((goblin (make-tg-creature
               :symbol 'goblin :name "哥布林"
               :attr '((hp 30) (attack 8) (defense 2))
               :inventory '(sword) :equipment '(wearable-armor)
               :exp-reward 50
               :behaviors nil :death-trigger nil
               :shopkeeper nil :handler nil)))
  (tg-register-creature 'goblin goblin))
```

2. 修改现有 `test-builtin-attack-kill`（约第 355 行），补充装备掉落断言：

```elisp
;; 在 (should (string-match "击败" ...)) 之后追加：
;; 背包物品应掉落到房间
(should (member 'sword (tg-room-contents (tg-get-room 'room1))))
;; 装备物品应掉落到房间
(should (member 'wearable-armor (tg-room-contents (tg-get-room 'room1))))
;; goblin 背包和装备应清空
(should (null (tg-creature-inventory (tg-get-creature 'goblin))))
(should (null (tg-creature-equipment (tg-get-creature 'goblin))))
```

3. 新增 no-drop 测试（在 `test-builtin-attack-kill` 之后）：

```elisp
(ert-deftest test-builtin-attack-kill-no-drop ()
  "测试 no-drop 物品不掉落，保留在 creature 身上"
  (tg-builtin-with-env
   ;; 给 goblin 装备 no-drop 物品
   (let ((goblin (tg-get-creature 'goblin)))
     (setf (tg-creature-equipment goblin) '(cursed-ring)))
   ;; 击杀 goblin
   (dotimes (_i 5)
     (when (not (tg-creature-dead-p (tg-get-creature 'goblin)))
       (tg-action--handler-attack '(:action attack :do-key goblin) tg-game)))
   (should (tg-creature-dead-p (tg-get-creature 'goblin)))
   ;; no-drop 物品不应掉落到房间
   (should (not (member 'cursed-ring (tg-room-contents (tg-get-room 'room1)))))
   ;; no-drop 物品应保留在 creature equipment 中
   (should (member 'cursed-ring (tg-creature-equipment (tg-get-creature 'goblin))))))
```

- [ ] **步骤 2b：tg-action.el 添加 tg-respawn-schedule 调用**

在 then 分支的 `let ((room ...))` 体内、death-trigger 之后追加。将 `tg-action.el:434` 从：

```elisp
                      (funcall death-trigger creature game))))
```

改为：

```elisp
                      (funcall death-trigger creature game)))
                  ;; 触发刷新调度
                  (tg-respawn-schedule do-key))
```

说明：原 `))))` 的 4 个 `)` 分别关闭 funcall/when/let(death-trigger)/let(room)。改为 `)))` 关闭前 3 个，追加 `(tg-respawn-schedule do-key)`，最后 `)` 关闭 `let(room)`。`do-key` 是 attack handler 中 creature 的 symbol 变量。NPC 反击在 else 分支，不受影响。

- [ ] **步骤 3：tg.el 添加 require tg-respawn**

在 `tg.el:26`（`(require 'tg-level)` 之后）添加：

```elisp
(require 'tg-respawn)
```

- [ ] **步骤 4：运行全量测试确认无回归**

```bash
emacs -batch -L . -l test/tg-registry-test.el -l test/tg-game-test.el -l test/tg-object-test.el -l test/tg-creature-test.el -l test/tg-room-test.el -l test/tg-action-test.el -l test/tg-parser-test.el -l test/tg-commands-test.el -l test/tg-dialog-test.el -l test/tg-npc-test.el -l test/tg-quest-test.el -l test/tg-shop-test.el -l test/tg-level-test.el -l test/tg-builtin-test.el -l test/tg-config-test.el -l test/tg-config-gen-test.el -l test/tg-save-test.el -l test/tg-mode-test.el -l test/tg-integration-test.el -l test/tg-respawn-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -3
```

- [ ] **步骤 5：Commit**

```bash
git add tg-commands.el tg-action.el tg.el test/tg-builtin-test.el
git commit -m "feat: wire respawn into dispatch and attack handler"
```

---

### 任务 5：tg-save 持久化刷新队列

**依赖：** 任务 4
**文件集：** `tg-save.el`, `test/tg-save-test.el`
**导出/变更接口：** 无
**消费接口：** `tg-game.el::tg-game-get`, `tg-game.el::tg-game-put`
**复杂度：** quick

**文件：**
- 修改：`tg-save.el:14-20`（collect-game-state 新增 :respawn-queue）
- 修改：`tg-save.el:71-78`（restore-game-state 新增 :respawn-queue）
- 修改：`test/tg-save-test.el`（追加测试）

- [ ] **步骤 1：修改 tg-save--collect-game-state**

在 `tg-save.el:20`（`:player` 行之后）添加：

```elisp
        :player (tg-game-get tg-game :player)
        :respawn-queue (tg-game-get tg-game :respawn-queue)))
```

- [ ] **步骤 2：修改 tg-save--restore-game-state**

在 `tg-save.el:78`（`:player` 行之后）添加：

```elisp
    (tg-game-put tg-game :player (plist-get game-data :player))
    (tg-game-put tg-game :respawn-queue (plist-get game-data :respawn-queue))))
```

- [ ] **步骤 3：编写 save/load 测试**

在 `test/tg-save-test.el` 末尾追加：

```elisp
(ert-deftest test-tg-save-respawn-queue ()
  "测试刷新队列的保存和加载"
  (tg-save-test-setup)
  (tg-game-put tg-game :respawn-queue '((goblin . 20)))
  (let* ((save-file (make-temp-file "tg-save-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          ;; 清空队列验证加载能恢复
          (tg-game-put tg-game :respawn-queue nil)
          (should (null (tg-game-get tg-game :respawn-queue)))
          (tg-load-game save-file config-dir)
          (should (equal (tg-game-get tg-game :respawn-queue)
                         '((goblin . 20)))))
      (delete-file save-file)
      (delete-directory config-dir t))))
```

此测试使用现有的 `tg-save-test-setup` + `tg-save-test--make-config-dir` 模式，确保完整的 save→config-load→restore 周期。

- [ ] **步骤 4：运行 save 测试**

```bash
emacs -batch -L . -l tg-commands.el -l test/tg-save-test.el --eval '(ert-run-tests-batch "test-tg-save-respawn-queue")' 2>&1 | tail -5
```

- [ ] **步骤 5：Commit**

```bash
git add tg-save.el test/tg-save-test.el
git commit -m "feat: persist respawn queue in save/load"
```

---

### 任务 6：集成验证与 sample 更新

**依赖：** 任务 5
**文件集：** `sample/game.org`, `docs/manual.org`, `README.md`
**导出/变更接口：** 无
**消费接口：** 无
**复杂度：** quick

**文件：**
- 修改：`sample/game.org`（添加 #+RESPAWN_DEFAULT + 部分 creature RESPAWN）
- 修改：`docs/manual.org`（补充刷新机制文档）
- 修改：`README.md`（更新测试数量）

- [ ] **步骤 1：运行全量测试**

```bash
emacs -batch -L . -l test/tg-registry-test.el -l test/tg-game-test.el -l test/tg-object-test.el -l test/tg-creature-test.el -l test/tg-room-test.el -l test/tg-action-test.el -l test/tg-parser-test.el -l test/tg-commands-test.el -l test/tg-dialog-test.el -l test/tg-npc-test.el -l test/tg-quest-test.el -l test/tg-shop-test.el -l test/tg-level-test.el -l test/tg-builtin-test.el -l test/tg-config-test.el -l test/tg-config-gen-test.el -l test/tg-save-test.el -l test/tg-mode-test.el -l test/tg-integration-test.el -l test/tg-respawn-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -5
```

- [ ] **步骤 2：验证 sample 游戏加载**

```bash
emacs -batch -L . --eval '(progn (require (quote tg)) (tg-init "sample/game.org") (princ (format "location: %s\n" (tg-game-get tg-game :location))))' 2>&1 | grep location
```

- [ ] **步骤 3：更新 sample/game.org**

1. 在文件头 `#+PLAYER: hero` 之后添加：`#+RESPAWN_DEFAULT: 10-20`
2. 为 `rat` creature（第 274 行附近）添加 `:RESPAWN: 5-10`
3. 为 `goblin` creature 添加 `:RESPAWN: 8-15`
4. 为 `skeleton-minion` creature 添加 `:RESPAWN: 15-25`
5. skeleton-king 和 shopkeeper 不加 RESPAWN（boss 不刷新，商店不刷新）
6. 新增 object `cursed-sword`（暗黑之剑），`:PROPS: no-drop`，`:EFFECTS: (attack 10)`
7. skeleton-king 的 `:EQUIPMENT: cursed-sword`（演示 no-drop 机制）

- [ ] **步骤 4：更新 docs/manual.org**

1. 在 Creatures Section 的字段表中新增 `RESPAWN` 字段行
2. 在文件级关键字说明中新增 `#+RESPAWN_DEFAULT`
3. 新增 Respawn 段说明刷新机制（含默认值、per-creature 覆盖、shopkeeper 豁免）
4. 更新已知限制为"暂无"

- [ ] **步骤 5：更新 README.md 测试数量**

将 `266 个 ERT 测试` 更新为实际测试数量。

- [ ] **步骤 6：Commit**

```bash
git add sample/game.org docs/manual.org README.md
git commit -m "feat: add respawn config to sample game and update docs"
```

---

## 并行执行图

> 仅 `parallel-executing-plans` 使用；`serial-executing-plans` 忽略本节。

**Critical Path:** 任务 1 → 任务 2 → 任务 3 → 任务 4 → 任务 5 → 任务 6

- Wave 1（无依赖）：任务 1
- Wave 2（依赖任务 1）：任务 2
- Wave 3（依赖任务 1, 任务 2）：任务 3
- Wave 4（依赖任务 2, 任务 3）：任务 4
- Wave 5（依赖任务 4）：任务 5
- Wave 6（依赖任务 5）：任务 6
- Wave FINAL（所有任务完成后）：F1 规格合规、F2 代码质量、F3 真实手测、F4 范围保真

> **注：** 任务间共享 `tg-creature.el`、`tg-config.el`、`tg-game` hash table 等核心接口，强耦合线性依赖。6 个 wave 实际为串行执行，建议使用 `serial-executing-plans`。
