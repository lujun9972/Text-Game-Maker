# Attack Combat System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Text-Game-Maker 添加 attack 战斗命令，支持攻防交替、伤害计算、死亡触发器、玩家死亡

**Architecture:** 在 Creature 结构体中新增 `death-trigger` slot，在 action.el 中新增 `tg-attack` action。伤害公式 max(1, attack - defense)，目标存活则反击，双方 HP 归零触发死亡逻辑。

**Tech Stack:** Emacs Lisp, cl-defstruct, tg-defaction macro, ERT

---

### Task 1: Creature 新增 death-trigger slot

**Files:**
- Modify: `creature-maker.el`

- [ ] **Step 1: 在 Creature cl-defstruct 中新增 death-trigger slot**

改前第 12-20 行：
```elisp
(cl-defstruct Creature
  "Creature structure"
  (symbol nil :documentation "CREATURE标志")
  (description "" :documentation "CREATURE描述")
  (occupation 'human :documentation "CREATURE的职业")
  (attr nil :documentation "CREATURE的属性")
  (inventory nil :documentation "CREATURE所拥有的物品")
  (equipment nil :documentation "CREATURE装备的装备")
  (watch-trigger nil :documentation "查看该CREATURE后触发的事件"))
```

改后：
```elisp
(cl-defstruct Creature
  "Creature structure"
  (symbol nil :documentation "CREATURE标志")
  (description "" :documentation "CREATURE描述")
  (occupation 'human :documentation "CREATURE的职业")
  (attr nil :documentation "CREATURE的属性")
  (inventory nil :documentation "CREATURE所拥有的物品")
  (equipment nil :documentation "CREATURE装备的装备")
  (watch-trigger nil :documentation "查看该CREATURE后触发的事件")
  (death-trigger nil :documentation "该CREATURE被击败后触发的事件"))
```

- [ ] **Step 2: 更新 build-creature 解构新增第 6 个参数**

改前第 30-33 行：
```elisp
(defun build-creature (creature-entity)
  "根据`text'创建creature,并将creature存入`creatures-alist'中"
  (cl-multiple-value-bind (symbol description attr inventory equipment ) creature-entity
	(cons symbol (make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr))))
```

改后：
```elisp
(defun build-creature (creature-entity)
  "根据creature-entity创建creature,并将creature存入creatures-alist中"
  (cl-multiple-value-bind (symbol description attr inventory equipment death-trigger) creature-entity
	(cons symbol (make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr :death-trigger death-trigger))))
```

- [ ] **Step 3: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'cl-generic)
    (require 'thingatpt)
    (require 'room-maker)
    (load-file \"creature-maker.el\"))"
```
Expected: no errors.

---

### Task 2: 新增 tg-attack action

**Files:**
- Modify: `action.el`

- [ ] **Step 1: 在 action.el 的 tg-wear 之后、tg-status 之前添加 tg-attack**

在 `action.el` 第 108 行（tg-wear 的 `tg-display` 结束括号）之后，第 110 行（tg-status）之前，插入：

```elisp
(tg-defaction tg-attack (target)
  "使用'attack <target>'攻击当前房间中的生物"
  (when (stringp target)
    (setq target (intern target)))
  (unless (creature-exist-in-room-p current-room target)
    (throw 'exception (format "房间中没有%s" target)))
  (let* ((target-creature (get-creature-by-symbol target))
         (my-attack (or (cdr (assoc 'attack (Creature-attr myself))) 0))
         (my-defense (or (cdr (assoc 'defense (Creature-attr myself))) 0))
         (target-attack (or (cdr (assoc 'attack (Creature-attr target-creature))) 0))
         (target-defense (or (cdr (assoc 'defense (Creature-attr target-creature))) 0))
         (damage (max 1 (- my-attack target-defense))))
    (take-effect-to-creature target-creature (cons 'hp (- damage)))
    (tg-display (format "你攻击了%s，造成 %d 点伤害！" target damage))
    (if (<= (cdr (assoc 'hp (Creature-attr target-creature))) 0)
        (progn
          (remove-creature-from-room current-room target)
          (when-let* ((trig (Creature-death-trigger target-creature)))
            (funcall trig))
          (tg-display (format "%s被击败了！" target)))
      (let* ((counter-damage (max 1 (- target-attack my-defense))))
        (take-effect-to-creature myself (cons 'hp (- counter-damage)))
        (tg-display (format "%s反击，造成 %d 点伤害！" target counter-damage))
        (if (<= (cdr (assoc 'hp (Creature-attr myself))) 0)
            (progn
              (tg-display "你被击败了！游戏结束！")
              (setq tg-over-p t))
          (tg-display (format "你的HP: %d | %s的HP: %d"
                              (cdr (assoc 'hp (Creature-attr myself)))
                              target
                              (cdr (assoc 'hp (Creature-attr target-creature))))))))))
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
    (require 'inventory-maker)
    (require 'creature-maker)
    (load-file \"action.el\"))"
```
Expected: no errors.

---

### Task 3: 新增测试

**Files:**
- Modify: `test/test-creature-maker.el`
- Modify: `test/test-action.el`

- [ ] **Step 1: 在 test-creature-maker.el 末尾 (provide 之前) 添加 death-trigger 测试**

```elisp
;; --- death-trigger ---

(ert-deftest test-build-creature-with-death-trigger ()
  "build-creature should parse death-trigger from config."
  (let* ((result (build-creature '(dragon "火龙" ((hp . 50)) () () (lambda () (tg-display "龙死了")))))
         (cr (cdr result)))
    (should (equal (car result) 'dragon))
    (should (functionp (Creature-death-trigger cr)))))

(ert-deftest test-build-creature-without-death-trigger ()
  "build-creature should set death-trigger to nil when not provided."
  (let* ((result (build-creature '(goblin "哥布林" ((hp . 30)) () ())))
         (cr (cdr result)))
    (should (null (Creature-death-trigger cr)))))
```

- [ ] **Step 2: 在 test-action.el 末尾 (provide 之前) 添加 tg-attack 测试**

在 `(defvar test-trigger-called nil)` 下方已有的位置添加一个动态变量，然后在测试区添加：

```elisp
;; --- tg-attack ---

(ert-deftest test-tg-attack-target-in-room ()
  "tg-attack should deal damage to target creature."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(goblin)))
           (cr (make-Creature :symbol 'goblin :description "A goblin"
                              :attr '((hp . 30) (attack . 6) (defense . 2))))
           (output nil))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'goblin cr)
                                  (cons 'hero myself)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (tg-attack 'goblin)
      ;; damage = max(1, 10 - 2) = 8, goblin hp: 30 - 8 = 22
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 22))
      ;; counter damage = max(1, 6 - 5) = 1, hero hp: 100 - 1 = 99
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 99)))))

(ert-deftest test-tg-attack-target-not-in-room ()
  "tg-attack should throw exception when target not in room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'hero myself)))
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-attack 'ghost))
                     "房间中没有ghost")))))

(ert-deftest test-tg-attack-kills-target ()
  "tg-attack should remove target from room when HP drops to 0."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (cr (make-Creature :symbol 'rat :description "A rat"
                              :attr '((hp . 5) (attack . 1) (defense . 0)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'rat cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'rat)
      (should-not (creature-exist-in-room-p room 'rat)))))

(ert-deftest test-tg-attack-triggers-death-trigger ()
  "tg-attack should call death-trigger when target is killed."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (cr (make-Creature :symbol 'rat :description "A rat"
                              :attr '((hp . 5) (attack . 1) (defense . 0))
                              :death-trigger (lambda () (setq test-trigger-called t)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'rat cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-attack 'rat)
      (should test-trigger-called))))

(ert-deftest test-tg-attack-counter-attack ()
  "tg-attack should trigger counter-attack when target survives."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(orc)))
           (cr (make-Creature :symbol 'orc :description "An orc"
                              :attr '((hp . 50) (attack . 8) (defense . 3)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 2))))
      (setq creatures-alist (list (cons 'orc cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'orc)
      ;; damage to orc = max(1, 10-3) = 7, orc hp: 50-7 = 43
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 43))
      ;; counter = max(1, 8-2) = 6, hero hp: 100-6 = 94
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 94)))))

(ert-deftest test-tg-attack-player-death ()
  "tg-attack should end game when player HP drops to 0."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself tg-over-p)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(dragon)))
           (cr (make-Creature :symbol 'dragon :description "Dragon"
                              :attr '((hp . 100) (attack . 50) (defense . 20)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 5) (attack . 10) (defense . 0))))
      (setq creatures-alist (list (cons 'dragon cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (setq tg-over-p nil)
      (tg-attack 'dragon)
      ;; hero hp: 5 - max(1, 50-0) = 5-50 = -45, dead
      (should tg-over-p))))

(ert-deftest test-tg-attack-no-attack-attr-defaults-zero ()
  "tg-attack should default attack/defense to 0 when not in attr."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(slime)))
           (cr (make-Creature :symbol 'slime :description "A slime"
                              :attr '((hp . 10)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'slime cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'slime)
      ;; damage = max(1, 0-0) = 1, slime hp: 10-1 = 9
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 9))
      ;; counter = max(1, 0-0) = 1, hero hp: 100-1 = 99
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 99)))))

(ert-deftest test-tg-attack-string-target ()
  "tg-attack should accept string target and convert to symbol."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(goblin)))
           (cr (make-Creature :symbol 'goblin :description "A goblin"
                              :attr '((hp . 30) (attack . 0) (defense . 0)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'goblin cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack "goblin")
      ;; Should work same as symbol
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 20)))))
```

- [ ] **Step 3: 运行全量测试**

Run:
```bash
bash /home/lujun9972/github/Text-Game-Maker/run-tests.sh
```
Expected: All tests passed (should be 95 original + 2 creature + 8 attack = 105 tests).

---

### Task 4: 提交

- [ ] **Step 1: 提交所有更改**

```bash
git add creature-maker.el action.el test/test-creature-maker.el test/test-action.el
git commit -m "$(cat <<'EOF'
feat: 添加 attack 战斗系统

- Creature 新增 death-trigger slot
- 新增 tg-attack 命令：攻防交替战斗
- 伤害公式: max(1, attack - defense)
- 目标死亡触发 death-trigger
- 反击机制 + 玩家死亡游戏结束
- 新增 10 个测试覆盖所有战斗场景

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```
