# Text-Game-Maker 2.0 重构实现计划

> **面向 AI 代理的工作者：** 必需子技能：平台支持子代理且计划较大/可安全分 wave 时使用 superpowers:parallel-executing-plans；计划较小、任务强耦合或平台不支持子代理时使用 superpowers:serial-executing-plans。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 基于 ifgame 架构思想全量重写 Text-Game-Maker，将命令解析改为 PEG 自然语言、动作分发改为 handler chain、对象模型改为属性驱动、地图改为方向出口，同时保留并重写任务/商店/对话/NPC AI/等级/存档等周边系统。

**架构：** 18 个模块位于项目根目录，单向无环依赖。底层 tg-registry 提供数据基础，tg-object → tg-creature → tg-game 构成实体链（creature 的 effective-attr 需要 object，game 的 buffs-apply 需要 creature），tg-room 依赖 object（all-visible-objects），tg-action + tg-parser + tg-commands 构成核心引擎，上层 tg-dialog/tg-npc/tg-quest/tg-shop/tg-level 提供周边功能，tg-config/tg-save 处理持久化（config 先于 save），tg-mode 提供 UI。

**技术栈：** Emacs Lisp，peg.el（内置），ERT 测试框架，Org-mode 配置格式

---

### 任务 1：tg-registry.el — 全局注册表

**依赖：** 无
**文件集：** `tg-registry.el`, `test/tg-registry-test.el`
**导出/变更接口：** `tg-registry.el::tg--rooms`, `tg-registry.el::tg--objects`, `tg-registry.el::tg--creatures`, `tg-registry.el::tg--actions`, `tg-registry.el::tg--dialogs`, `tg-registry.el::tg--shops`, `tg-registry.el::tg--quests`, `tg-registry.el::tg--action-words`, `tg-registry.el::tg-get-room`, `tg-registry.el::tg-get-object`, `tg-registry.el::tg-get-creature`, `tg-registry.el::tg-get-action`, `tg-registry.el::tg-get-dialog`, `tg-registry.el::tg-get-shop`, `tg-registry.el::tg-get-quest`, `tg-registry.el::tg-register-room`, `tg-registry.el::tg-register-object`, `tg-registry.el::tg-register-creature`, `tg-registry.el::tg-register-action`, `tg-registry.el::tg-register-dialog`, `tg-registry.el::tg-register-shop`, `tg-registry.el::tg-register-quest`, `tg-registry.el::tg-registry-clear`
**消费接口：** 无
**复杂度：** quick

**文件：**
- 创建：`tg-registry.el`
- 创建：`test/tg-registry-test.el`

- [ ] **步骤 1：编写测试**

```elisp
;; test/tg-registry-test.el
(require 'ert)
(require 'tg-registry)

(ert-deftest test-tg-registry-register-and-get ()
  (tg-registry-clear)
  ;; 使用 cons cell 代替 struct（struct 由各模块定义）
  (tg-register-room 'courtyard '(room . "庭院"))
  (tg-register-object 'key '(object . "钥匙"))
  (tg-register-creature 'goblin '(creature . "哥布林"))
  (should (equal (tg-get-room 'courtyard) '(room . "庭院")))
  (should (null (tg-get-room 'nonexistent)))
  (should (equal (tg-get-object 'key) '(object . "钥匙")))
  (should (equal (tg-get-creature 'goblin) '(creature . "哥布林"))))

(ert-deftest test-tg-registry-clear ()
  (tg-registry-clear)
  (tg-register-room 'r1 '(room))
  (tg-registry-clear)
  (should (null (tg-get-room 'r1))))

(ert-deftest test-tg-registry-action-words ()
  (tg-registry-clear)
  (puthash "take" 'take tg--action-words)
  (should (eq (gethash "take" tg--action-words) 'take))
  (should (null (gethash "nonexistent" tg--action-words))))
```

- [ ] **步骤 2：运行测试确认失败**

`emacs -batch -L . -l test/tg-registry-test.el -f ert-run-tests-batch-and-exit` → FAIL（struct 未定义）

- [ ] **步骤 3：实现 tg-registry.el**

```elisp
;;; tg-registry.el --- 全局注册表容器  -*- lexical-binding: t; -*-

(require 'cl-lib)

;; 各模块通过 hash table 注册实体，不在此定义 struct
(defvar tg--rooms (make-hash-table :test 'eq))
(defvar tg--objects (make-hash-table :test 'eq))
(defvar tg--creatures (make-hash-table :test 'eq))
(defvar tg--actions (make-hash-table :test 'eq))
(defvar tg--dialogs (make-hash-table :test 'eq))
(defvar tg--shops (make-hash-table :test 'eq))
(defvar tg--quests (make-hash-table :test 'eq))
(defvar tg--action-words (make-hash-table :test 'equal))

(defun tg-get-room (sym)         (gethash sym tg--rooms))
(defun tg-get-object (sym)       (gethash sym tg--objects))
(defun tg-get-creature (sym)     (gethash sym tg--creatures))
(defun tg-get-action (sym)       (gethash sym tg--actions))
(defun tg-get-dialog (sym)       (gethash sym tg--dialogs))
(defun tg-get-shop (sym)         (gethash sym tg--shops))
(defun tg-get-quest (sym)        (gethash sym tg--quests))

(defun tg-register-room (sym r)     (puthash sym r tg--rooms))
(defun tg-register-object (sym o)   (puthash sym o tg--objects))
(defun tg-register-creature (sym c) (puthash sym c tg--creatures))
(defun tg-register-action (sym a)   (puthash sym a tg--actions))
(defun tg-register-dialog (sym d)   (puthash sym d tg--dialogs))
(defun tg-register-shop (sym s)     (puthash sym s tg--shops))
(defun tg-register-quest (sym q)    (puthash sym q tg--quests))

(defun tg-registry-clear ()
  (clrhash tg--rooms)    (clrhash tg--objects)
  (clrhash tg--creatures) (clrhash tg--actions)
  (clrhash tg--dialogs)  (clrhash tg--shops)
  (clrhash tg--quests)   (clrhash tg--action-words))

(provide 'tg-registry)
;;; tg-registry.el ends here
```

- [ ] **步骤 4：运行测试确认通过**

`emacs -batch -L . -l test/tg-registry-test.el -f ert-run-tests-batch-and-exit` → PASS

- [ ] **步骤 5：Commit**

### 任务 2：tg-object.el — 对象属性系统

**依赖：** 任务 1
**文件集：** `tg-object.el`, `test/tg-object-test.el`
**导出/变更接口：** `tg-object.el::tg-object-symbol`, `tg-object.el::tg-object-name`, `tg-object.el::tg-object-synonyms`, `tg-object.el::tg-object-contents`, `tg-object.el::tg-object-supports`, `tg-object.el::tg-object-props`, `tg-object.el::tg-object-state`, `tg-object.el::tg-object-key`, `tg-object.el::tg-object-effects`, `tg-object.el::tg-object-handler`, `tg-object.el::tg-object-takeable-p`, `tg-object.el::tg-object-container-p`, `tg-object.el::tg-object-supporter-p`, `tg-object.el::tg-object-open-p`, `tg-object.el::tg-object-locked-p`, `tg-object.el::tg-object-wearable-p`, `tg-object.el::tg-object-accessible-p`, `tg-object.el::tg-object-find`, `tg-object.el::tg-object-find-parent`, `tg-object.el::tg-object-find-in-room`, `tg-object.el::tg-object-find-in-inventory`, `tg-object.el::tg-object-move`
**消费接口：** `tg-registry.el::tg-get-object`, `tg-registry.el::tg-register-object`, `tg-registry.el::tg--objects`
**复杂度：** deep

**文件：**
- 创建：`tg-object.el`
- 创建：`test/tg-object-test.el`

- [ ] **步骤 1：编写测试**

覆盖：对象创建及属性检查（container/supporter/scenery/static/wearable/edible/readable）、takeable-p 判定（scenery 不可取、supporter 不可取、static 不可取）、容器状态机转换（open→close→lock→unlock→open）、accessible-p 判定（open 容器可访问内容、closed/locked 不可访问）、find-parent（在房间/背包中找父容器）、effects 解析（永久 vs 临时 duration）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-object.el**

覆盖 `cl-defstruct tg-object`（移除前向声明），核心谓词 `tg-object-takeable-p`（非 scenery/supporter/static）、`tg-object-container-p`、`tg-object-supporter-p`、`tg-object-open-p`、`tg-object-locked-p`、`tg-object-wearable-p`、`tg-object-accessible-p`（可见 + 非容器内 或 容器状态为 open 或 在 supporter 上），容器状态机：`tg-object-set-state` 遵循 `open↔closed↔locked`、`tg-object-can-open-p`、`tg-object-can-close-p`，查找函数 `tg-object-find-parent`、`tg-object-find-in-room`（接收 room 参数而非 game）、`tg-object-find-in-inventory`（接收 inventory 列表参数而非 game），移动 `tg-object-move`。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 3：tg-creature.el — 生物系统

**依赖：** 任务 1, 任务 2
**文件集：** `tg-creature.el`, `test/tg-creature-test.el`
**导出/变更接口：** `tg-creature.el::tg-creature-symbol`, `tg-creature.el::tg-creature-name`, `tg-creature.el::tg-creature-attr`, `tg-creature.el::tg-creature-inventory`, `tg-creature.el::tg-creature-equipment`, `tg-creature.el::tg-creature-exp-reward`, `tg-creature.el::tg-creature-behaviors`, `tg-creature.el::tg-creature-death-trigger`, `tg-creature.el::tg-creature-shopkeeper`, `tg-creature.el::tg-creature-handler`, `tg-creature.el::tg-creature-dead-p`, `tg-creature.el::tg-creature-take-effect`, `tg-creature.el::tg-creature-add-item`, `tg-creature.el::tg-creature-remove-item`, `tg-creature.el::tg-creature-has-item`, `tg-creature.el::tg-creature-attr-get`, `tg-creature.el::tg-creature-effective-attr`
**消费接口：** `tg-registry.el::tg-get-creature`, `tg-registry.el::tg-get-object`, `tg-registry.el::tg-register-creature`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：creature 创建（attr 初始值）、attr-get（按键值查找）、dead-p（hp≤0）、take-effect（写入/修改 attr、支持新属性、hp 不低于 0）、add/remove/has-item、effective-attr（基础 attr + equipment 遍历叠加 effects（需 tg-object-effects）+ active-buffs 参数叠加，由调用方传入）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-creature.el**

覆盖 `cl-defstruct tg-creature`，`tg-creature-attr-get`（从 attr alist 中按 key 查值）、`tg-creature-dead-p`（hp ≤ 0）、`tg-creature-take-effect`（attr alist 操作，有则改、无则 push，hp 不低于 0）、`tg-creature-add-item`/`tg-creature-remove-item`/`tg-creature-has-item`、`tg-creature-effective-attr`（接收 creature、attr-key、active-buffs 三个参数；遍历 equipment，通过 `tg-get-object` + `tg-object-effects` 动态叠加，再加上 active-buffs 叠加）。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 4：tg-game.el — 游戏动态状态

**依赖：** 任务 1, 任务 3
**文件集：** `tg-game.el`, `test/tg-game-test.el`
**导出/变更接口：** `tg-game.el::tg-game`, `tg-game.el::tg-new-game`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game-put`, `tg-game.el::tg-game-incf`, `tg-game.el::tg-player`, `tg-game.el::tg-buffs-tick`, `tg-game.el::tg-buffs-apply`
**消费接口：** `tg-registry.el::tg-get-creature`, `tg-creature.el::tg-creature-take-effect`
**复杂度：** quick

**文件：**
- 创建：`tg-game.el`
- 创建：`test/tg-game-test.el`

- [ ] **步骤 1：编写测试**

```elisp
;; test/tg-game-test.el
(require 'ert)
(require 'tg-game)

(ert-deftest test-tg-new-game ()
  (let ((g (tg-new-game "测试" "作者")))
    (should (equal (tg-game-get g :title) "测试"))
    (should (equal (tg-game-get g :author) "作者"))
    (should (eq (tg-game-get g :state) 'starting))
    (should (= (tg-game-get g :turns) 0))
    (should (null (tg-game-get g :location)))
    (should (null (tg-game-get g :active-buffs)))))

(ert-deftest test-tg-game-incf ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-incf g :turns)
    (should (= (tg-game-get g :turns) 1))))

(ert-deftest test-tg-buffs-apply-permanent ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :player 'test-player)
    (tg-register-creature 'test-player
      (make-tg-creature :symbol 'test-player :attr '((hp . 50))))
    (tg-buffs-apply g '((hp 20)))
    (should (= (tg-creature-attr-get (tg-get-creature 'test-player) 'hp) 70))))

(ert-deftest test-tg-buffs-tick ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :active-buffs
                 '((attack (:delta 3 :remaining 2 :duration 2))
                   (hp (:delta 20 :remaining 0 :duration 1))))
    (tg-buffs-tick g)
    (let ((buffs (tg-game-get g :active-buffs)))
      ;; attack buff 剩余 1 回合，hp buff（remaining 0）已移除
      (should (= (length buffs) 1))
      (should (eq (caar buffs) 'attack))
      (should (= (plist-get (cdar buffs) :remaining) 1)))))
```

- [ ] **步骤 2：运行测试确认失败**

`emacs -batch -L . -l test/tg-game-test.el -f ert-run-tests-batch-and-exit` → FAIL

- [ ] **步骤 3：实现 tg-game.el**

```elisp
;;; tg-game.el --- 游戏动态状态管理  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)

(defvar tg-game nil "当前游戏动态状态哈希表")

(defun tg-new-game (title &optional author)
  (let ((g (make-hash-table :test 'eq)))
    (puthash :title     title g)
    (puthash :author    author g)
    (puthash :state     'starting g)
    (puthash :turns     0 g)
    (puthash :location  nil g)
    (puthash :player    nil g)
    (puthash :active-buffs nil g)
    g))

(defun tg-game-get (game key)     (gethash key game))
(defun tg-game-put (game key val) (puthash key val game))
(defun tg-game-incf (game key)    (cl-incf (gethash key game 0)))

(defun tg-player ()
  (tg-get-creature (tg-game-get tg-game :player)))

(defun tg-buffs-tick (game)
  "回合结束时递减所有临时效果的剩余回合，移除过期效果。"
  (let ((buffs (tg-game-get game :active-buffs)))
    (dolist (buff buffs)
      (cl-decf (plist-get (cdr buff) :remaining)))
    (tg-game-put game :active-buffs
                 (cl-remove-if (lambda (b) (<= (plist-get (cdr b) :remaining) 0))
                               buffs))))

(defun tg-buffs-apply (game effects)
  "应用效果。永久效果直接写 player attr，临时效果进入 :active-buffs。"
  (let ((player (tg-player)))
    (dolist (eff effects)
      (let ((attr (car eff))
            (delta (cadr eff))
            (duration (plist-get (cddr eff) :duration)))
        (if duration
            (tg-game-put game :active-buffs
                         (cons (cons attr (list :delta delta :remaining duration :duration duration))
                               (tg-game-get game :active-buffs)))
          ;; 永久效果写法用 tg-creature-take-effect（Task 3 定义）
          (tg-creature-take-effect player (cons attr delta)))))))

(provide 'tg-game)
;;; tg-game.el ends here
```

- [ ] **步骤 4：运行测试确认通过**

`emacs -batch -L . -l test/tg-game-test.el -f ert-run-tests-batch-and-exit` → PASS

- [ ] **步骤 5：Commit**

### 任务 5：tg-room.el — 房间与地图

**依赖：** 任务 1, 任务 2
**文件集：** `tg-room.el`, `test/tg-room-test.el`
**导出/变更接口：** `tg-room.el::tg-room-symbol`, `tg-room.el::tg-room-name`, `tg-room.el::tg-room-desc`, `tg-room.el::tg-room-exits`, `tg-room.el::tg-room-contents`, `tg-room.el::tg-room-creatures`, `tg-room.el::tg-room-before-handler`, `tg-room.el::tg-room-after-handler`, `tg-room.el::tg-room-visit-count`, `tg-room.el::tg-room-visit`, `tg-room.el::tg-room-exit`, `tg-room.el::tg-room-all-visible-objects`, `tg-room.el::tg-room-describe`, `tg-room.el::tg-room-add-object`, `tg-room.el::tg-room-remove-object`, `tg-room.el::tg-room-add-creature`, `tg-room.el::tg-room-remove-creature`, `tg-room.el::tg-directions`
**消费接口：** `tg-registry.el::tg-get-room`, `tg-registry.el::tg-get-object`, `tg-registry.el::tg-register-room`
**复杂度：** standard

**文件：**
- 创建：`tg-room.el`
- 创建：`test/tg-room-test.el`

- [ ] **步骤 1：编写测试**

```elisp
;; test/tg-room-test.el
(require 'ert)
(require 'tg-registry)
(require 'tg-room)

(ert-deftest test-tg-room-create-and-exit ()
  (tg-registry-clear)
  (let ((room (make-tg-room :symbol 'garden
                           :name "花园"
                           :desc "一个美丽的花园。"
                           :exits '((north . hall)))))
    (tg-register-room 'garden room)
    (should (equal (tg-room-name room) "花园"))
    (should (eq (tg-room-exit room 'north) 'hall))
    (should (null (tg-room-exit room 'south)))))

(ert-deftest test-tg-room-visit-count ()
  (let ((room (make-tg-room :symbol 'r1 :name "R1" :desc "Test" :visit-count 0)))
    (should (= (tg-room-visit-count room) 0))
    (tg-room-visit room)
    (should (= (tg-room-visit-count room) 1))))

(ert-deftest test-tg-room-all-visible-objects ()
  (tg-registry-clear)
  (let ((room (make-tg-room :symbol 'r :name "R" :desc "D" :contents '(key coin))))
    ;; 测试基本内容查找 —— 无嵌套
    (should (equal (tg-room-all-visible-objects room) '(key coin))))
  ;; 测试容器嵌套
  (let* ((open-box (make-tg-object :symbol 'box :name "盒子" :props '(container) :state 'open :contents '(gem)))
         (closed-box (make-tg-object :symbol 'cbox :name "箱子" :props '(container) :state 'closed :contents '(gold)))
         (room (make-tg-room :symbol 'r2 :name "R2" :desc "D" :contents '(box cbox))))
    (tg-register-object 'box open-box)
    (tg-register-object 'cbox closed-box)
    (tg-register-object 'gem (make-tg-object :symbol 'gem :name "宝石"))
    (tg-register-object 'gold (make-tg-object :symbol 'gold :name "金币"))
    (let ((visible (tg-room-all-visible-objects room)))
      (should (memq 'box visible))
      (should (memq 'gem visible))      ;; open container 内容可见
      (should (memq 'cbox visible))
      (should (not (memq 'gold visible)))))) ;; closed container 内容不可见
```

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-room.el**

覆盖：`cl-defstruct tg-room`（移除前向声明）、`tg-directions` 常量、`tg-room-exit`、`tg-room-visit`、`tg-room-visit-count` setter、`tg-room-all-visible-objects`（含递归展开 open 容器和 supporter）、`tg-room-describe`（首次完整描述 vs 重复简短描述 + 可见物品列表 + creature 列表）、`tg-room-add-object`/`tg-room-remove-object`、`tg-room-add-creature`/`tg-room-remove-creature`。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 6：tg-action.el — 动词注册

**依赖：** 任务 1
**文件集：** `tg-action.el`, `test/tg-action-test.el`
**导出/变更接口：** `tg-action.el::tg-action-id`, `tg-action.el::tg-action-synonyms`, `tg-action.el::tg-action-handler`, `tg-action.el::tg-register-action`, `tg-action.el::tg-find-action`, `tg-action.el::tg-verb-aliases`, `tg-action.el::tg-passive-actions`
**消费接口：** `tg-registry.el::tg--action-words`, `tg-registry.el::tg-register-action`
**复杂度：** quick

- [ ] **步骤 1：编写测试**

验证 `tg-register-action` 注册动词及同义词映射，`tg-find-action` 通过同义词查找到对应 action，`tg-verb-aliases` 标准化（get→take, l→look, x→examine, i→inventory, pick up→take, put down→drop, equip→wear, consume→eat, hit→attack, fight→attack, speak→talk）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-action.el**

覆盖 `cl-defstruct tg-action`、`tg-register-action`（遍历 synonyms puthash 到 `tg--action-words`）、`tg-find-action`（gethash from `tg--action-words`）、`tg-verb-aliases` alist、`tg-passive-actions` 列表。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 7：tg-parser.el — PEG 自然语言解析

**依赖：** 任务 1, 任务 4, 任务 5, 任务 6
**文件集：** `tg-parser.el`, `test/tg-parser-test.el`
**导出/变更接口：** `tg-parser.el::tg-parse`, `tg-parser.el::tg-grammar`, `tg-parser.el::tg-build-vocabulary`
**消费接口：** `tg-registry.el::tg-get-room`, `tg-registry.el::tg-get-object`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game`, `tg-action.el::tg-verb-aliases`, `tg-action.el::tg-find-action`, `tg-room.el::tg-room-all-visible-objects`
**复杂度：** deep

- [ ] **步骤 1：编写测试**

覆盖：基本动词解析（`take key` → `(:action take :do-key :key)`），带冠词（`take the rusty key` → `(:action take :do-key :rusty-key :do-adj ("rusty"))`），介词短语（`put bird in nest` → `(:action place :do-key :bird :prep "in" :io-key :nest)`），方向词（`north` → `(:action go :direction north)`, `n` → `(:action go :direction north)`），不及物动词（`look` → `(:action look :do-key nil)`），`all`（`take all` → `(:action take :do-key :all)`），动词标准化（`get key` → take, `x bird` → examine, `walk north` → + direction detection），未知动词（`xyzzy` → `(:error :unknown-action :verb "xyzzy")`），未知名词（`take foobar` → `(:error :unknown-noun :word "foobar")`），空输入（→ error）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-parser.el**

PEG 语法定义（注意：规格中用 `+` 但实际需要 `*` 以支持 `look`/`inventory`/`quit` 等无宾语命令，以计划为准）：
```elisp
(defvar tg-grammar
  (peg-parse
   ((S            verb (* (and ws-word (opt (and preposition (+ ws-word))))))
    (verb         (or (string "pick up") (string "put down")
                      (string "look at") (string "listen to")
                      (regexp "[a-z]+")))
    (ws-word      (opt (and article (string " "))) (regexp "[a-z]+"))
    (preposition  (or (string " on ") (string " with ") (string " to ")
                      (string " in ") (string " by ") (string " under ")))
    (article      (or (string "the ") (string "a ") (string "an "))))))
```

解析流水线：
1. 方向词快速检测（输入整体匹配 north/s/n/ne/sw 等 → 直接返回 go AST）
2. 否则 `peg-run` 匹配 PEG 语法
3. `tg-parse-normalize-verb`：通过 `tg-verb-aliases` 标准化，结果查 `tg-find-action` 得 action-id
4. `tg-parse-build-vocabulary`：当前房间 + 背包 + 嵌套内容的名称/同义词 + 方向词 + all/everything
5. `tg-parse-classify`：将 ws-words 分为形容词和名词（最后一个匹配名词为中心词，之前的为形容词）
6. `tg-parse-resolve`：名词/同义词 → object symbol
7. 构建最终 AST plist

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 8：tg-commands.el — Handler Chain 调度引擎

**依赖：** 任务 1, 任务 4, 任务 5, 任务 2, 任务 3, 任务 6, 任务 7
**文件集：** `tg-commands.el`, `test/tg-commands-test.el`
**导出/变更接口：** `tg-commands.el::tg-dispatch`, `tg-commands.el::tg-message`
**消费接口：** `tg-parser.el::tg-parse`, `tg-action.el::tg-find-action`, `tg-action.el::tg-passive-actions`, `tg-room.el::tg-room-before-handler`, `tg-room.el::tg-room-after-handler`, `tg-object.el::tg-object-handler`, `tg-creature.el::tg-creature-handler`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game-incf`, `tg-game.el::tg-game`
**复杂度：** deep

- [ ] **步骤 1：编写测试**

覆盖：handler chain 顺序（error→before→io→do→action→after）、before-handler 返回 t 则停止（不执行后续 handler 也不执行 after）、io-handler 返回 t 则停止、do-handler 返回 t 则停止、action handler 成功执行后 after-handler 才执行（action 抛 tg-action-abort 则跳过 after）、被动命令不触发 NPC 行为不计回合、`take all` 展开（收集所有 takeable 对象逐个 dispatch）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-commands.el**

```elisp
(defun tg-dispatch (ast game)
  (cond
   ((tg-handle-error ast game) nil)
   ((tg-run-room-before ast game) nil)
   ((tg-run-io-handler ast game) nil)
   ((tg-run-do-handler ast game) nil)
   (t
    (catch 'tg-action-abort
      (tg-run-action ast game)
      (tg-run-room-after ast game))))
  (unless (member (plist-get ast :action) tg-passive-actions)
    (tg-npc-run-behaviors game)
    (tg-buffs-tick game)
    (tg-game-incf game :turns)))
```

实现各 run 函数：`tg-handle-error`（解析错误类型→显示消息）、`tg-run-room-before`（取 room 的 before-handler 调用）、`tg-run-io-handler`（取间接宾语的 handler 调用）、`tg-run-do-handler`（取直接宾语的 handler 调用，可能是 object 或 creature）、`tg-run-action`（find-action → 调用其 handler）、`tg-run-room-after`（取 room 的 after-handler 调用）。`all` 展开：收集目标列表（takeable/room contents），逐个构建子 AST dispatch。

`tg-message`：全局输出函数，向 `(tg-get-buffer)` 插入文本字符串。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 9：内置动词 action handlers

**依赖：** 任务 8
**文件集：** `tg-action.el`（追加）
**导出/变更接口：** `tg-action.el::tg-action--handler-go`, `tg-action.el::tg-action--handler-look`, `tg-action.el::tg-action--handler-examine`, `tg-action.el::tg-action--handler-take`, `tg-action.el::tg-action--handler-drop`, `tg-action.el::tg-action--handler-place`, `tg-action.el::tg-action--handler-open`, `tg-action.el::tg-action--handler-close`, `tg-action.el::tg-action--handler-unlock`, `tg-action.el::tg-action--handler-wear`, `tg-action.el::tg-action--handler-eat`, `tg-action.el::tg-action--handler-read`, `tg-action.el::tg-action--handler-inventory`, `tg-action.el::tg-action--handler-attack`, `tg-action.el::tg-action--handler-talk`, `tg-action.el::tg-action--handler-buy`, `tg-action.el::tg-action--handler-sell`, `tg-action.el::tg-action--handler-shop`, `tg-action.el::tg-action--handler-status`, `tg-action.el::tg-action--handler-upgrade`, `tg-action.el::tg-action--handler-quests`, `tg-action.el::tg-action--handler-quest`, `tg-action.el::tg-action--handler-accept`, `tg-action.el::tg-action--handler-save`, `tg-action.el::tg-action--handler-load`, `tg-action.el::tg-action--handler-help`, `tg-action.el::tg-action--handler-quit`, `tg-action.el::tg-register-builtins`
**消费接口：** `tg-action.el::tg-register-action`, `tg-game.el::tg-game`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game-put`, `tg-game.el::tg-player`, `tg-room.el::tg-room-exit`, `tg-registry.el::tg-get-room`, `tg-room.el::tg-room-all-visible-objects`, `tg-room.el::tg-room-contents`, `tg-object.el::tg-object-takeable-p`, `tg-object.el::tg-object-accessible-p`, `tg-object.el::tg-object-open-p`, `tg-object.el::tg-object-locked-p`, `tg-object.el::tg-object-move`, `tg-creature.el::tg-creature-dead-p`, `tg-creature.el::tg-creature-take-effect`, `tg-creature.el::tg-creature-attr-get`, `tg-creature.el::tg-creature-add-item`, `tg-creature.el::tg-creature-remove-item`, `tg-creature.el::tg-creature-has-item`, `tg-creature.el::tg-creature-effective-attr`
**复杂度：** deep

- [ ] **步骤 1：编写测试**

覆盖每个内置动词的 handler 行为：
- go：有出口→移动，无出口→提示
- take：普通物品→移入背包，static→不可取，container→不可取，`take all` 逐个取
- drop：背包→房间
- place：验证目标 container/supporter → 放入
- open：closed→open，locked→提示需解锁
- unlock：locked + 匹配 key→closed，key 不匹配→提示
- attack：动态计算 effective_attack/defense → 伤害 → 死亡（掉落/exp/track-quest，`tg-track-quest` 使用全局 `tg-game`）→ 反击
- eat：消耗物品 → 永久 effects 写 attr / 临时 effects 入 buffs
- wear：wearable→移入 equipment
- talk：启动 dialog 状态机
- inventory：显示背包物品

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现内置动词 handler**

在 tg-action.el 中追加所有内置 handler 函数和 `tg-register-builtins`（调用 `tg-register-action` 注册全部 27 个动词）。

**go handler**：从 AST 取 direction，查找 room exit，更新 `:location`，触发房间描述。

**take handler**：包括 `take all` 展开逻辑。
```elisp
(defun tg-action--handler-take (ast game)
  (let ((do-key (plist-get ast :do-key)))
    (if (eq do-key 'all)
        (let ((room (tg-get-room (tg-game-get game :location))))
          (dolist (sym (tg-room-all-visible-objects room))
            (when (tg-object-takeable-p (tg-get-object sym))
              (tg-action--handler-take `(:action take :do-key ,sym) game)))
          t)
      ;; 单个对象 take
      (let* ((room (tg-get-room (tg-game-get game :location)))
             (obj (tg-object-find-in-room do-key room)))
        (if obj
            (if (tg-object-takeable-p obj)
                (let ((player (tg-player)))
                  (setf (tg-room-contents room) (remove do-key (tg-room-contents room)))
                  (tg-creature-add-item player do-key)
                  (tg-message (format "拾取了%s。" (tg-object-name obj)))
                  (tg-track-quest 'collect do-key)
                  t)
              (tg-message "你拿不起来。"))
          (tg-message "这里没有这个东西。"))))))
```

**attack handler**：
```elisp
(defun tg-action--handler-attack (ast game)
  (let* ((target (plist-get ast :do-key))
         (room (tg-get-room (tg-game-get game :location)))
         (player (tg-player))
         (npc (tg-get-creature target)))
    (unless (member target (tg-room-creatures room))
      (tg-message "这里没有可以攻击的目标。")
      (throw 'tg-action-abort nil))
    (let* ((p-attack (or (tg-creature-effective-attr player 'attack (tg-game-get game :active-buffs)) 0))
           (n-defense (or (tg-creature-attr-get npc 'defense) 0))
           (damage (max 1 (- p-attack n-defense))))
      (tg-creature-take-effect npc (cons 'hp (- damage)))
      (tg-message (format "你攻击了%s，造成%d点伤害。" (tg-creature-name npc) damage))
      (if (tg-creature-dead-p npc)
          (progn
            ;; 掉落物品
            (dolist (item (tg-creature-inventory npc))
              (push item (tg-room-contents room)))
            (dolist (item (tg-creature-equipment npc))
              (push item (tg-room-contents room)))
            ;; 从房间移除
            (setf (tg-room-creatures room)
                  (remove target (tg-room-creatures room)))
            ;; death-trigger + exp + quest
            (when (tg-creature-death-trigger npc)
              (funcall (tg-creature-death-trigger npc) game))
            (let ((exp (or (tg-creature-exp-reward npc)
                           (* 10 (or (tg-creature-attr-get npc 'level) 1)))))
              (tg-creature-take-effect player (cons 'exp exp))
              (tg-message (format "%s被击败了！获得%d经验。" (tg-creature-name npc) exp)))
            (tg-track-quest 'kill target))
        ;; 反击
        (let* ((n-attack (or (tg-creature-attr-get npc 'attack) 0))
               (p-defense (or (tg-creature-effective-attr player 'defense (tg-game-get game :active-buffs)) 0))
               (counter (max 1 (- n-attack p-defense))))
          (tg-creature-take-effect player (cons 'hp (- counter)))
          (tg-message (format "%s反击造成%d点伤害。" (tg-creature-name npc) counter))
          (when (tg-creature-dead-p player)
            (tg-game-put game :state 'dead)
            (tg-message "你被击败了！游戏结束。")))))
    t))
```

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 10：tg-dialog.el — 状态机对话

**依赖：** 任务 1, 任务 3, 任务 4
**文件集：** `tg-dialog.el`, `test/tg-dialog-test.el`
**导出/变更接口：** `tg-dialog.el::tg-dialog-state-node-id`, `tg-dialog.el::tg-dialog-state-npc-symbol`, `tg-dialog.el::tg-dialog-state-greeting`, `tg-dialog.el::tg-dialog-state-options`, `tg-dialog.el::tg-dialog-option-text`, `tg-dialog.el::tg-dialog-option-response`, `tg-dialog.el::tg-dialog-option-condition`, `tg-dialog.el::tg-dialog-option-effects`, `tg-dialog.el::tg-dialog-option-next-node`, `tg-dialog.el::tg-dialog-pending`, `tg-dialog.el::tg-dialog-start`, `tg-dialog.el::tg-dialog-handle-choice`, `tg-dialog.el::tg-dialog-eval-condition`, `tg-dialog.el::tg-dialog-apply-effects`
**消费接口：** `tg-registry.el::tg-get-dialog`, `tg-registry.el::tg-get-creature`, `tg-registry.el::tg-get-quest`, `tg-creature.el::tg-creature-has-item`, `tg-creature.el::tg-creature-add-item`, `tg-creature.el::tg-creature-take-effect`, `tg-game.el::tg-player`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：`tg-dialog-start` 设置 pending 状态、`tg-dialog-handle-choice` 选择有效选项→显示 response 应用 effects→跳转 next-node、选择无效编号→提示、condition 过滤（quest-active/quest-completed/has-item/and/or/not）、effects 执行（exp/item/gold/bonus-points/quest-activate/trigger）、对话结束（next-node nil）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-dialog.el**

实现 `cl-defstruct tg-dialog-state`、`cl-defstruct tg-dialog-option`、`tg-dialog-start`（查找 NPC 入口节点，设 pending，显示 greeting + 选项编号）、`tg-dialog-handle-choice`（解析编号→过滤可见→显示 response→apply effects→跳转或结束）、`tg-dialog-eval-condition`（pcase 递归求值）、`tg-dialog-apply-effects`（pcase 执行各类 effect）。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 11：tg-npc.el — NPC 行为引擎

**依赖：** 任务 1, 任务 3, 任务 4, 任务 5
**文件集：** `tg-npc.el`, `test/tg-npc-test.el`
**导出/变更接口：** `tg-npc.el::tg-npc-run-behaviors`, `tg-npc.el::tg-npc-eval-condition`, `tg-npc.el::tg-npc-execute-action`
**消费接口：** `tg-registry.el::tg-get-creature`, `tg-registry.el::tg-get-room`, `tg-creature.el::tg-creature-dead-p`, `tg-creature.el::tg-creature-take-effect`, `tg-creature.el::tg-creature-behaviors`, `tg-creature.el::tg-creature-attr`, `tg-room.el::tg-room-creatures`, `tg-room.el::tg-room-exit`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game`, `tg-game.el::tg-player`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：condition 求值（always/hp-below/hp-above/player-in-room/and/or/not）、action 执行（attack 伤害/移动 npc 到相邻房间/say 输出/buff 增属性/debuff 减玩家属性）、`tg-npc-run-behaviors`（只跑当前房间活 NPC、每 NPC 最多匹配一条规则、死亡 NPC 不执行）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-npc.el**

实现 `tg-npc-eval-condition`（pcase 分派各条件类型）、`tg-npc-execute-action`（pcase 分派 attack/say/move/buff/debuff）、`tg-npc-run-behaviors`（遍历当前 room creatures，排除玩家和死亡 NPC，每 creature 找第一条匹配规则执行，cl-block 中断）。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 12：tg-quest.el — 任务系统

**依赖：** 任务 1, 任务 3, 任务 4
**文件集：** `tg-quest.el`, `test/tg-quest-test.el`
**导出/变更接口：** `tg-quest.el::tg-quest-symbol`, `tg-quest.el::tg-quest-type`, `tg-quest.el::tg-quest-target`, `tg-quest.el::tg-quest-count`, `tg-quest.el::tg-quest-progress`, `tg-quest.el::tg-quest-status`, `tg-quest.el::tg-quest-rewards`, `tg-quest.el::tg-track-quest`, `tg-quest.el::tg-quest-activate`
**消费接口：** `tg-registry.el::tg-get-quest`, `tg-registry.el::tg--quests`, `tg-creature.el::tg-creature-take-effect`, `tg-creature.el::tg-creature-add-item`, `tg-game.el::tg-player`
**复杂度：** quick

- [ ] **步骤 1：编写测试**

覆盖：`tg-quest-activate`（inactive→active）、`tg-track-quest`（kill/collect/explore/talk 各类型进度增加）、进度达标自动完成、rewards 发放（exp/item/bonus-points/trigger）、已完成 quest 不重复追踪。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-quest.el**

实现 `cl-defstruct tg-quest`、`tg-quest-activate`、`tg-track-quest (type target-symbol)`（使用全局 `tg-game`，按 type 匹配目标，incf progress，达标则 set status completed + 发放 rewards）、rewards 发放逻辑。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 13：tg-shop.el — 商店

**依赖：** 任务 1, 任务 3, 任务 4
**文件集：** `tg-shop.el`, `test/tg-shop-test.el`
**导出/变更接口：** `tg-shop.el::tg-shop-npc-symbol`, `tg-shop.el::tg-shop-sell-rate`, `tg-shop.el::tg-shop-goods`, `tg-shop.el::tg-shop-buy`, `tg-shop.el::tg-shop-sell`
**消费接口：** `tg-registry.el::tg-get-shop`, `tg-registry.el::tg-get-object`, `tg-creature.el::tg-creature-attr-get`, `tg-creature.el::tg-creature-take-effect`, `tg-creature.el::tg-creature-add-item`, `tg-creature.el::tg-creature-remove-item`, `tg-game.el::tg-player`
**复杂度：** quick

- [ ] **步骤 1：编写测试**

```elisp
;; test/tg-shop-test.el
(require 'ert)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-shop)

(ert-deftest test-tg-shop-buy-success ()
  (tg-registry-clear)
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30) (sword . 100))))
        (player (make-tg-creature :symbol 'hero :attr '((gold . 200)))))
    (tg-register-shop 'merchant shop)
    (tg-register-creature 'hero player)
    (tg-shop-buy 'potion (tg-get-shop 'merchant) player)
    (should (tg-creature-has-item player 'potion))
    (should (= (tg-creature-attr-get player 'gold) 170))))

(ert-deftest test-tg-shop-buy-insufficient-gold ()
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((sword . 100))))
        (player (make-tg-creature :symbol 'hero :attr '((gold . 50)))))
    (should-error (tg-shop-buy 'sword shop player))))

(ert-deftest test-tg-shop-sell ()
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30))))
        (player (make-tg-creature :symbol 'hero
                                   :inventory '(potion)
                                   :attr '((gold . 10)))))
    (tg-shop-sell 'potion shop player)
    (should (not (tg-creature-has-item player 'potion)))
    (should (= (tg-creature-attr-get player 'gold) 25))))
```

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现**

```elisp
(defun tg-shop-buy (item-sym shop player)
  (let ((price (cdr (assoc item-sym (tg-shop-goods shop))))
        (gold (tg-creature-attr-get player 'gold)))
    (unless price
      (error "商店不卖 %s" item-sym))
    (when (< gold price)
      (error "金币不足"))
    (tg-creature-take-effect player (cons 'gold (- price)))
    (tg-creature-add-item player item-sym)))

(defun tg-shop-sell (item-sym shop player)
  (unless (tg-creature-has-item player item-sym)
    (error "你没有 %s" item-sym))
  (let ((price (floor (* (or (cdr (assoc item-sym (tg-shop-goods shop))) 0)
                         (tg-shop-sell-rate shop)))))
    (tg-creature-remove-item player item-sym)
    (tg-creature-take-effect player (cons 'gold price))))
```

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 14：tg-level.el — 经验等级

**依赖：** 任务 3, 任务 4
**文件集：** `tg-level.el`, `test/tg-level-test.el`
**导出/变更接口：** `tg-level.el::tg-level-exp-table`, `tg-level.el::tg-level-bonus-points-per-level`, `tg-level.el::tg-level-auto-upgrade-attrs`, `tg-level.el::tg-level-check`, `tg-level.el::tg-level-upgrade`
**消费接口：** `tg-creature.el::tg-creature-attr`, `tg-creature.el::tg-creature-take-effect`, `tg-game.el::tg-player`
**复杂度：** quick

- [ ] **步骤 1：编写测试**

```elisp
;; test/tg-level-test.el
(require 'ert)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-level)

(ert-deftest test-tg-level-check-level-up ()
  (tg-registry-clear)
  (let* ((tg-level-exp-table '(0 100 250 500))
         (tg-level-bonus-points-per-level 3)
         (tg-level-auto-upgrade-attrs '((hp . 5)))
         (player (make-tg-creature :symbol 'hero
                                    :attr '((hp . 50) (attack . 5) (exp . 150) (level . 1) (bonus-points . 0)))))
    (tg-register-creature 'hero player)
    (tg-level-check player)
    (should (= (tg-creature-attr-get player 'level) 2))
    (should (= (tg-creature-attr-get player 'hp) 55))
    (should (= (tg-creature-attr-get player 'bonus-points) 3))))

(ert-deftest test-tg-level-no-level-up ()
  (let ((tg-level-exp-table '(0 100 250))
        (tg-level-bonus-points-per-level 3)
        (tg-level-auto-upgrade-attrs '((hp . 5)))
        (player (make-tg-creature :symbol 'hero
                                   :attr '((hp . 50) (exp . 50) (level . 1) (bonus-points . 0)))))
    (tg-level-check player)
    (should (= (tg-creature-attr-get player 'level) 1))))
```

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现**

```elisp
(defvar tg-level-exp-table '(0 100 250 500 850 1300 1900 2700 3800 5000))
(defvar tg-level-bonus-points-per-level 3)
(defvar tg-level-auto-upgrade-attrs '((hp . 5)))

(defun tg-level-check (creature)
  (let ((level (tg-creature-attr-get creature 'level))
        (exp (tg-creature-attr-get creature 'exp)))
    (while (and (< level (length tg-level-exp-table))
                (>= exp (nth level tg-level-exp-table)))
      (cl-incf level)
      (tg-creature-take-effect creature (cons 'level 1))
      (tg-creature-take-effect creature (cons 'bonus-points tg-level-bonus-points-per-level))
      (dolist (upgrade tg-level-auto-upgrade-attrs)
        (tg-creature-take-effect creature upgrade)))))

```

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 15：tg-config.el — Org 配置解析

**依赖：** 任务 1, 任务 4, 任务 5, 任务 2, 任务 3, 任务 10, 任务 12, 任务 13, 任务 14
**文件集：** `tg-config.el`, `test/tg-config-test.el`
**导出/变更接口：** `tg-config.el::tg-config-load`
**消费接口：** `tg-registry.el::tg-register-room`, `tg-registry.el::tg-register-object`, `tg-registry.el::tg-register-creature`, `tg-registry.el::tg-register-dialog`, `tg-registry.el::tg-register-shop`, `tg-registry.el::tg-register-quest`, `tg-game.el::tg-new-game`, `tg-room.el::make-tg-room`, `tg-object.el::make-tg-object`, `tg-creature.el::make-tg-creature`, `tg-dialog.el::make-tg-dialog-state`, `tg-dialog.el::make-tg-dialog-option`
**复杂度：** deep

- [ ] **步骤 1：编写测试**

覆盖：Org 文件解析（`#+TITLE`/`#+AUTHOR`/`#+START` 全局属性读取）、Rooms section 解析（name/desc/exits/contents/creatures 属性 → make-tg-room → tg-register-room）、Objects section 解析（name/synonyms/props/state/effects 属性 → make-tg-object → tg-register-object）、Creatures section 解析（name/attr/inventory/behaviors → make-tg-creature → tg-register-creature）、Dialog section 解析（内联 DSL `text :: response → effects → next-node`）、Shops/Quests/Levels section 解析、handler 符号解析（intern + fboundp）、同目录 handlers.el 自动加载。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-config.el**

`tg-config-load (org-file)`：加载同目录 `handlers.el`（若存在）→ `org-element-parse-buffer` 解析 Org → 读取 `#+TITLE`/`#+AUTHOR`/`#+START` → 按一级标题分派到各 section 解析器 → 每个 section 遍历二级标题，从 PROPERTIES drawer 读取字段 → 构造 struct 调用 `tg-register-*` → Dialog 的 Org body 用 `tg-config-parse-dialog-option` 解析内联 DSL。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 16：tg-save.el — 存档

**依赖：** 任务 1, 任务 4, 任务 5, 任务 2, 任务 3, 任务 12, 任务 13, 任务 15
**文件集：** `tg-save.el`, `test/tg-save-test.el`
**导出/变更接口：** `tg-save.el::tg-save-game`, `tg-save.el::tg-load-game`
**消费接口：** `tg-game.el::tg-game`, `tg-game.el::tg-game-get`, `tg-game.el::tg-game-put`, `tg-game.el::tg-new-game`, `tg-registry.el::tg--rooms`, `tg-registry.el::tg--objects`, `tg-registry.el::tg--creatures`, `tg-registry.el::tg--quests`, `tg-registry.el::tg--shops`, `tg-config.el::tg-config-load`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：保存→文件存在且格式正确（prin1 可读）、加载→动态状态恢复（location/turns/state/active-buffs）、room visit-count 恢复、object state/contents 恢复、creature attr 恢复、round-trip（save→load→save 一致）。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-save.el**

`tg-save-game`：收集 game 动态字段 + rooms 动态字段（visit-count/contents/creatures）+ objects 动态字段（state/contents/supports）+ creatures 动态字段（attr/inventory/equipment）+ quests 动态字段（status/progress）+ shops 动态字段 + active-buffs → `prin1` 写入。

`tg-load-game`：`read` 存档 → 从 `:config-dir` 调 `tg-config-load` 重载配置 → 用存档数据覆盖动态字段。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 17：tg-config-gen.el — 配置生成器

**依赖：** 任务 15
**文件集：** `tg-config-gen.el`, `test/tg-config-gen-test.el`
**导出/变更接口：** `tg-config-gen.el::tg-gen-game`, `tg-config-gen.el::tg-gen-room`, `tg-config-gen.el::tg-gen-object`, `tg-config-gen.el::tg-gen-creature`, `tg-config-gen.el::tg-gen-dialog`, `tg-config-gen.el::tg-gen-shop`, `tg-config-gen.el::tg-gen-quest`, `tg-config-gen.el::tg-validate-config`
**消费接口：** `tg-config.el::tg-config-load`, `tg-registry.el::tg--rooms`, `tg-registry.el::tg--objects`, `tg-registry.el::tg--creatures`, `tg-registry.el::tg--dialogs`, `tg-registry.el::tg--shops`, `tg-registry.el::tg--quests`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：`tg-gen-game` 输出含 `#+TITLE:` 等模板头 + 示例 section、`tg-gen-room` 在 cursor 位置插入 Room 模板、`tg-gen-object` 插入 Object 模板、`tg-validate-config` 检测 exit 引用不存在的房间、container contents 中未定义对象、dialog next-node 不存在。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现**

每个 gen 命令：`(interactive)` + `completing-read` 收集字段 → 构造 Org 字符串 → `insert`。`tg-validate-config`：遍历各注册表做交叉引用检查 → 输出警告列表。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 18：tg-mode.el — UI 主模式

**依赖：** 任务 7, 任务 8, 任务 10, 任务 15, 任务 16
**文件集：** `tg-mode.el`, `test/tg-mode-test.el`
**导出/变更接口：** `tg-mode.el::tg-mode`, `tg-mode.el::tg-start-game`, `tg-mode.el::tg-get-buffer`
**消费接口：** `tg-parser.el::tg-parse`, `tg-commands.el::tg-dispatch`, `tg-commands.el::tg-message`, `tg-dialog.el::tg-dialog-pending`, `tg-dialog.el::tg-dialog-handle-choice`, `tg-save.el::tg-save-game`, `tg-save.el::tg-load-game`, `tg-game.el::tg-game`, `tg-game.el::tg-game-get`
**复杂度：** standard

- [ ] **步骤 1：编写测试**

覆盖：`tg-mode` 激活后设置 major-mode、RET 触发 `tg-send-command`、prompt 保护（read-only+rear-nonsticky）、TAB 补全（空输入补全动词、动词后补全可见对象）、M-p/M-n 历史导航、`tg-mode` 的 buffer name 格式。

- [ ] **步骤 2：运行测试确认失败**

- [ ] **步骤 3：实现 tg-mode.el**

单 buffer 模式：上半只读输出区 + 下半 prompt 输入区。

```elisp
(define-derived-mode tg-mode text-mode "TG"
  "Text Game Maker 游戏模式。"
  (setq-local tg-prompt-marker (point-max-marker))
  (local-set-key (kbd "RET") #'tg-send-command)
  (local-set-key (kbd "TAB") #'tg-complete-command)
  (local-set-key (kbd "M-p") #'tg-history-prev)
  (local-set-key (kbd "M-n") #'tg-history-next)
  (setq-local eldoc-documentation-function #'tg-eldoc)
  (eldoc-mode 1))
```

`tg-send-command`：读 prompt 后文本 → `tg-parse` → `tg-dispatch` → `tg-render-prompt`。

`tg-complete-command`：prompt 后为空补全动词名，动词后补全可见对象名，介词后补全间接宾语。

命令历史：`tg-command-history` list，`M-p`/`M-n` 浏览。

输出函数：`tg-message` 在 buffer 末尾插入文本（`inhibit-read-only` t）。

`tg-render-prompt`：显示 `[房间名]> ` 格式 prompt。

- [ ] **步骤 4：运行测试确认通过**

- [ ] **步骤 5：Commit**

### 任务 19：tg.el — 入口 + 集成测试

**依赖：** 任务 1-18 全部
**文件集：** `tg.el`, `test/tg-integration-test.el`
**导出/变更接口：** `tg.el::tg-init`, `tg.el::tg-start`
**消费接口：** 所有模块
**复杂度：** deep

- [ ] **步骤 1：创建集成测试**

一个最小可玩游戏（3 个房间、5 个物品含 container/supporter、1 个战斗 NPC、1 个对话 NPC、1 个商店 NPC）的 Org 配置文件，覆盖完整流程：启动→移动→检查→拾取→开箱→对话→战斗→购买→存档→读档→验证状态一致。

```elisp
;; test/tg-integration-test.el
(ert-deftest test-tg-full-game-loop ()
  (let ((config-dir (expand-file-name "test/fixtures/mini-game/")))
    (tg-config-load (expand-file-name "game.org" config-dir))
    (tg-start-game)
    ;; 移动
    (tg-simulate-command "north")
    (should (eq (tg-game-get tg-game :location) 'forest-path))
    ;; 拾取
    (tg-simulate-command "take key")
    (should (tg-creature-has-item (tg-player) 'rusty-key))
    ;; 对话
    (tg-simulate-command "talk old-man")
    (should tg-dialog-pending)
    ;; ... more steps
    ;; 存档 + 读档
    (tg-save-game "/tmp/test-tgm.sav")
    (tg-load-game "/tmp/test-tgm.sav")
    (should (eq (tg-game-get tg-game :location) 'forest-path))))
```

- [ ] **步骤 2：运行集成测试确认失败**

- [ ] **步骤 3：实现 tg.el**

```elisp
;;; tg.el --- Text Game Maker 2.0 入口  -*- lexical-binding: t; -*-

(require 'tg-registry)
(require 'tg-game)
(require 'tg-parser)
(require 'tg-action)
(require 'tg-commands)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-dialog)
(require 'tg-npc)
(require 'tg-quest)
(require 'tg-shop)
(require 'tg-level)
(require 'tg-save)
(require 'tg-config)
(require 'tg-config-gen)

(defun tg-init (org-config-file)
  "从 ORG-CONFIG-FILE 加载游戏配置并初始化。"
  (tg-config-load org-config-file))

;;;###autoload
(defun tg-start (org-config-file)
  "加载配置并启动游戏。"
  (interactive "f游戏配置 (Org 文件): ")
  (tg-init org-config-file)
  (switch-to-buffer (get-buffer-create (format "*TG: %s*" (tg-game-get tg-game :title))))
  (tg-mode)
  (tg-game-put tg-game :state 'in-progress)
  (tg-game-put tg-game :location (tg-game-get tg-game :start-room))
  (tg-room-visit (tg-get-room (tg-game-get tg-game :location)))
  (tg-render-room-description)
  (tg-render-prompt))

(provide 'tg)
;;; tg.el ends here
```

- [ ] **步骤 4：运行集成测试确认通过**

全部测试：`emacs -batch -L . -l test/tg-registry-test.el -l test/tg-game-test.el -l test/tg-room-test.el -l test/tg-object-test.el -l test/tg-creature-test.el -l test/tg-action-test.el -l test/tg-parser-test.el -l test/tg-commands-test.el -l test/tg-dialog-test.el -l test/tg-npc-test.el -l test/tg-quest-test.el -l test/tg-shop-test.el -l test/tg-level-test.el -l test/tg-save-test.el -l test/tg-config-test.el -l test/tg-config-gen-test.el -l test/tg-mode-test.el -l test/tg-integration-test.el -f ert-run-tests-batch-and-exit`

- [ ] **步骤 5：Commit**

### 任务 20：清理旧文件

**依赖：** 任务 19
**文件集：** `action.el`, `creature-maker.el`, `dialog-system.el`, `inventory-maker.el`, `level-system.el`, `npc-behavior.el`, `quest-system.el`, `room-maker.el`, `save-system.el`, `shop-system.el`, `text-game-maker.el`, `tg-config-generator.el`, `tg-mode.el`, `test/test-action.el`, `test/test-creature-maker.el`, `test/test-dialog-system.el`, `test/test-inventory-maker.el`, `test/test-level-system.el`, `test/test-npc-behavior.el`, `test/test-quest-system.el`, `test/test-room-maker.el`, `test/test-save-system.el`, `test/test-shop-system.el`, `test/test-text-game-maker.el`, `test/test-tg-config-generator.el`, `test/test-tg-mode.el`
**导出/变更接口：** 无（只删不改）
**消费接口：** 无
**复杂度：** quick

- [ ] **步骤 1：删除旧源文件**

```bash
rm action.el creature-maker.el dialog-system.el inventory-maker.el \
   level-system.el npc-behavior.el quest-system.el room-maker.el \
   save-system.el shop-system.el text-game-maker.el \
   tg-config-generator.el tg-mode.el
```

- [ ] **步骤 2：删除旧测试文件**

```bash
rm test/test-action.el test/test-creature-maker.el test/test-dialog-system.el \
   test/test-inventory-maker.el test/test-level-system.el \
   test/test-npc-behavior.el test/test-quest-system.el \
   test/test-room-maker.el test/test-save-system.el \
   test/test-shop-system.el test/test-text-game-maker.el \
   test/test-tg-config-generator.el test/test-tg-mode.el
```

- [ ] **步骤 3：验证全部新测试通过**

- [ ] **步骤 4：Commit**

---

## 并行执行图

> 仅 `parallel-executing-plans` 使用；`serial-executing-plans` 忽略本节。

**Critical Path:** 任务 1 → 任务 2 → 任务 3 → 任务 4 → 任务 7 → 任务 8 → 任务 9 → 任务 15 → 任务 16 → 任务 18 → 任务 19 → 任务 20

依赖链说明：registry(1) → object(2) → creature(3, 需要 object 做 effective-attr) → game(4, 需要 creature 做 buffs-apply) → room(5) → parser(7, 需要 game+action+room) → commands(8) → builtins(9) → config(15) → save(16) → mode(18) → integration(19) → cleanup(20)

- Wave 1（无依赖）：任务 1
- Wave 2（依赖 Wave 1）：任务 2（依赖 1）, 任务 6（依赖 1）
- Wave 3（依赖 Wave 2）：任务 3（依赖 1, 2）, 任务 5（依赖 1, 2）
- Wave 4（依赖 Wave 3）：任务 4（依赖 1, 3）
- Wave 5（依赖 Wave 4）：任务 7（依赖 1, 4, 5, 6）, 任务 10（依赖 1, 3, 4）, 任务 11（依赖 1, 3, 4, 5）, 任务 12（依赖 1, 3, 4）, 任务 13（依赖 1, 3, 4）, 任务 14（依赖 3, 4）
- Wave 6（依赖 Wave 5）：任务 8（依赖 1, 2, 3, 4, 5, 6, 7）, 任务 15（依赖 1, 2, 3, 4, 5, 10, 12, 13, 14）
- Wave 7（依赖 Wave 6）：任务 9（依赖 8）
- Wave 8（依赖 Wave 6）：任务 16（依赖 1, 2, 3, 4, 5, 12, 13, 15）, 任务 17（依赖 15）
- Wave 9（依赖 Wave 7+8）：任务 18（依赖 7, 8, 10, 15, 16）
- Wave 10（依赖 Wave 9）：任务 19（依赖 1-18）
- Wave 11（依赖 Wave 10）：任务 20（依赖 19）
- Wave FINAL（所有任务完成后）：F1 规格合规、F2 代码质量、F3 真实手测、F4 范围保真
