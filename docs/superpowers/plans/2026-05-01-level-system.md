# Level System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add experience, level, and skill-point allocation to Text-Game-Maker, triggered by defeating monsters in combat.

**Architecture:** New `level-system.el` module manages level config and upgrade logic. Creature struct gains an `exp-reward` slot. The `tg-attack` action calls `add-exp-to-creature` after a kill. A new `tg-upgrade` action lets players spend bonus points on attributes.

**Tech Stack:** Emacs Lisp, cl-defstruct, ERT testing, existing `read-from-whole-string` config parser pattern.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `level-system.el` | Create | Level config loading, exp/level management, upgrade logic |
| `test/test-level-system.el` | Create | Tests for level-system module |
| `creature-maker.el` | Modify | Add `exp-reward` slot to Creature struct, update `build-creature` |
| `action.el` | Modify | Add exp reward to `tg-attack`, add `tg-upgrade` action |
| `text-game-maker.el` | Modify | Add `(require 'level-system)` |
| `sample/level-config.el` | Create | Level config for sample game |
| `sample/creature-config.el` | Modify | Add exp-reward field to each creature |
| `sample/sample-game.el` | Modify | Add `level-init` call |

---

### Task 1: Add `exp-reward` slot to Creature struct

**Files:**
- Modify: `creature-maker.el`
- Test: `test/test-creature-maker.el`

- [ ] **Step 1: Write the failing test**

Add to `test/test-creature-maker.el` before `(provide 'test-creature-maker)`:

```elisp
;; --- exp-reward slot ---

(ert-deftest test-creature-exp-reward-slot-default-nil ()
  "Creature exp-reward slot should default to nil."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin")))
    (should (null (Creature-exp-reward cr)))))

(ert-deftest test-creature-exp-reward-slot-set ()
  "Creature exp-reward slot should be settable."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin" :exp-reward 15)))
    (should (= (Creature-exp-reward cr) 15))))

(ert-deftest test-build-creature-with-exp-reward ()
  "build-creature should parse 7-element tuple with exp-reward."
  (let* ((result (build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15)))
         (cr (cdr result)))
    (should (= (Creature-exp-reward cr) 15))))

(ert-deftest test-build-creature-without-exp-reward ()
  "build-creature should default exp-reward to nil for 6-element tuple."
  (let* ((result (build-creature '(goblin "A goblin" ((hp . 25)) () () nil)))
         (cr (cdr result)))
    (should (null (Creature-exp-reward cr)))))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-creature-maker) (ert-run-tests-batch-and-exit))" 2>&1 | grep -E "FAILED|passed|unexpected"`
Expected: `test-creature-exp-reward-slot-default-nil` and others FAIL (slot doesn't exist)

- [ ] **Step 3: Write minimal implementation**

In `creature-maker.el`, add `exp-reward` slot to the Creature struct (after `death-trigger`):

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
  (death-trigger nil :documentation "该CREATURE被击败后触发的事件")
  (exp-reward nil :documentation "击败该CREATURE获得的经验值"))
```

Update `build-creature` to parse the 7th element:

```elisp
(defun build-creature (creature-entity)
  "根据creature-entity创建creature,并将creature存入creatures-alist中"
  (cl-multiple-value-bind (symbol description attr inventory equipment death-trigger exp-reward) creature-entity
    (cons symbol (make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr :death-trigger death-trigger :exp-reward exp-reward))))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-creature-maker) (ert-run-tests-batch-and-exit))" 2>&1 | tail -5`
Expected: All tests pass, 0 unexpected

- [ ] **Step 5: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-tg-mode) (require 'test-action) (require 'test-room-maker) (require 'test-creature-maker) (require 'test-inventory-maker) (require 'test-tg-config-generator) (ert-run-tests-batch-and-exit))" 2>&1 | tail -3`
Expected: All 143+ tests pass, 0 unexpected

- [ ] **Step 6: Commit**

```bash
git add creature-maker.el test/test-creature-maker.el
git commit -m "feat: add exp-reward slot to Creature struct"
```

---

### Task 2: Create `level-system.el` with `level-init`, `get-exp-reward`, `add-exp-to-creature`

**Files:**
- Create: `level-system.el`
- Test: `test/test-level-system.el`

- [ ] **Step 1: Write the failing tests**

Create `test/test-level-system.el`:

```elisp
;;; test-level-system.el --- Tests for level-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'level-system)

;; --- level-init ---

(ert-deftest test-level-init-loads-config ()
  "level-init should load level config from file."
  (test-with-temp-file "(level-exp-table 0 100 250 500)
                         (level-up-bonus-points 3)
                         (auto-upgrade-attrs ((hp . 5)))"
    (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs)
      (level-init temp-file)
      (should (equal level-exp-table '(0 100 250 500)))
      (should (= level-up-bonus-points 3))
      (should (equal auto-upgrade-attrs '((hp . 5)))))))

;; --- get-exp-reward ---

(ert-deftest test-get-exp-reward-explicit ()
  "get-exp-reward should return explicit exp-reward value."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6) (defense . 2)) :exp-reward 15)))
    (should (= (get-exp-reward cr) 15))))

(ert-deftest test-get-exp-reward-auto-calculate ()
  "get-exp-reward should auto-calculate from hp+attack+defense when exp-reward is nil."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6) (defense . 2)) :exp-reward nil)))
    (should (= (get-exp-reward cr) 33))))

(ert-deftest test-get-exp-reward-auto-missing-attrs ()
  "get-exp-reward should treat missing attrs as 0."
  (let ((cr (make-Creature :symbol 'blob :attr '((hp . 10)) :exp-reward nil)))
    (should (= (get-exp-reward cr) 10))))

;; --- add-exp-to-creature ---

(ert-deftest test-add-exp-accumulates ()
  "add-exp-to-creature should add exp to creature's attr."
  (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (add-exp-to-creature cr 50)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 1)))))

(ert-deftest test-add-exp-triggers-level-up ()
  "add-exp-to-creature should level up when exp reaches threshold."
  (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs display-fn)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (add-exp-to-creature cr 120)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 120))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 2))
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 105))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 3)))))

(ert-deftest test-add-exp-multi-level-up ()
  "add-exp-to-creature should handle multiple level ups at once."
  (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs display-fn)
    (setq level-exp-table '(0 100 250 500))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (add-exp-to-creature cr 300)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 300))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 3))
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 6)))))

(ert-deftest test-add-exp-max-level ()
  "add-exp-to-creature should not level up beyond exp-table range."
  (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs display-fn)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 200) (level . 2) (bonus-points . 3))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (add-exp-to-creature cr 500)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 700))
      ;; Already at max level (2), exp-table has entries for 1->2 only
      (should (= (cdr (assoc 'level (Creature-attr cr))) 2)))))

(ert-deftest test-add-exp-no-level-attrs ()
  "add-exp-to-creature should do nothing special when creature has no level/exp attrs."
  (test-with-globals-saved (level-exp-table level-up-bonus-points auto-upgrade-attrs display-fn)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (add-exp-to-creature cr 50)
      ;; exp not in attr, so no effect
      (should (null (assoc 'exp (Creature-attr cr)))))))

(provide 'test-level-system)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | head -5`
Expected: FAIL with "Cannot open load file" or "function not defined"

- [ ] **Step 3: Write minimal implementation**

Create `level-system.el`:

```elisp
;;; level-system.el --- Level and experience system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'creature-maker)

(defvar level-exp-table nil
  "每级所需累计经验值列表。索引0=1→2级所需经验100, 索引1=2→3级所需250...")

(defvar level-up-bonus-points 0
  "每次升级获得的可分配技能点数")

(defvar auto-upgrade-attrs nil
  "升级时自动提升的属性列表, 如 ((hp . 5))")

(defun level-init (config-file)
  "从 CONFIG-FILE 加载升级配置。"
  (let ((config (read-from-whole-string (with-temp-buffer
                                           (insert-file-contents config-file)
                                           (buffer-string)))))
    (setq level-exp-table (cadr (assoc 'level-exp-table config)))
    (setq level-up-bonus-points (cadr (assoc 'level-up-bonus-points config)))
    (setq auto-upgrade-attrs (cadr (assoc 'auto-upgrade-attrs config)))))

(defun get-exp-reward (creature)
  "获取 CREATURE 的经验奖励值。优先使用 exp-reward slot，否则按 hp+attack+defense 计算。"
  (or (Creature-exp-reward creature)
      (let ((attr (Creature-attr creature)))
        (+ (or (cdr (assoc 'hp attr)) 0)
           (or (cdr (assoc 'attack attr)) 0)
           (or (cdr (assoc 'defense attr)) 0)))))

(defun add-exp-to-creature (creature exp)
  "给 CREATURE 增加 EXP 经验值，自动检查并处理升级。"
  (when (assoc 'exp (Creature-attr creature))
    (cl-incf (cdr (assoc 'exp (Creature-attr creature))) exp)
    (while (and level-exp-table
                (let ((current-level (cdr (assoc 'level (Creature-attr creature))))
                      (current-exp (cdr (assoc 'exp (Creature-attr creature)))))
                  (and (<= current-level (length level-exp-table))
                       (>= current-exp (nth (1- current-level) level-exp-table))))
      ;; Level up
      (cl-incf (cdr (assoc 'level (Creature-attr creature))))
      ;; Apply auto-upgrade-attrs
      (dolist (effect auto-upgrade-attrs)
        (take-effect-to-creature creature effect))
      ;; Add bonus points
      (when (assoc 'bonus-points (Creature-attr creature))
        (cl-incf (cdr (assoc 'bonus-points (Creature-attr creature))) level-up-bonus-points))
      ;; Display level up message
      (tg-display (format "恭喜升级！当前等级: %d" (cdr (assoc 'level (Creature-attr creature)))))))))

(provide 'level-system)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add level-system.el test/test-level-system.el
git commit -m "feat: add level-system module with exp, level-up, and skill points"
```

---

### Task 3: Add `tg-upgrade` action

**Files:**
- Modify: `action.el`
- Test: `test/test-action.el`

- [ ] **Step 1: Write the failing tests**

Add to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-upgrade ---

(ert-deftest test-tg-upgrade-allocates-points ()
  "tg-upgrade should increase target attr and decrease bonus-points."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 5) (defense . 3) (bonus-points . 3)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (tg-upgrade "attack" "2")
      (should (= (cdr (assoc 'attack (Creature-attr cr))) 7))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 1)))))

(ert-deftest test-tg-upgrade-insufficient-points ()
  "tg-upgrade should throw when not enough bonus-points."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 5) (bonus-points . 1)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "attack" "3"))
                     "技能点不足")))))

(ert-deftest test-tg-upgrade-invalid-attr ()
  "tg-upgrade should throw when attr does not exist."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 3)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "magic" "1"))
                     "没有magic属性，无法分配")))))

(ert-deftest test-tg-upgrade-no-bonus-attr ()
  "tg-upgrade should throw when creature has no bonus-points attr."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6)))))
      (setq creatures-alist (list (cons 'goblin cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "attack" "1"))
                     "没有bonus-points属性")))))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-action) (ert-run-tests-batch-and-exit 'test-tg-upgrade-allocates-points))" 2>&1 | head -10`
Expected: FAIL — `tg-upgrade` not defined yet

- [ ] **Step 3: Write minimal implementation**

Add to `action.el` before the `(tg-defaction tg-status ...)` block. Also add `(require 'level-system)` at the top of `action.el` after existing requires:

After line `(require 'inventory-maker)` in `action.el`, add:

```elisp
(require 'level-system)
```

Add `tg-upgrade` action before `tg-status`:

```elisp
(tg-defaction tg-upgrade (attr points)
  "使用'upgrade <属性> <点数>'消耗技能点提升指定属性"
  (when (stringp attr)
    (setq attr (intern attr)))
  (unless (assoc 'bonus-points (Creature-attr myself))
    (throw 'exception "没有bonus-points属性"))
  (unless (assoc attr (Creature-attr myself))
    (throw 'exception (format "没有%s属性，无法分配" attr)))
  (let ((pts (string-to-number (or points "0")))
        (available (cdr (assoc 'bonus-points (Creature-attr myself)))))
    (unless (> pts 0)
      (throw 'exception "请输入有效的点数"))
    (unless (>= available pts)
      (throw 'exception "技能点不足"))
    (cl-incf (cdr (assoc attr (Creature-attr myself))) pts)
    (cl-decf (cdr (assoc 'bonus-points (Creature-attr myself))) pts)
    (tg-display (format "分配 %d 点到 %s，剩余技能点: %d" pts attr (cdr (assoc 'bonus-points (Creature-attr myself)))))))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-action) (ert-run-tests-batch-and-exit 'test-tg-upgrade))" 2>&1 | tail -5`
Expected: All 4 tg-upgrade tests pass

- [ ] **Step 5: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-tg-mode) (require 'test-action) (require 'test-room-maker) (require 'test-creature-maker) (require 'test-inventory-maker) (require 'test-tg-config-generator) (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | tail -3`
Expected: All tests pass, 0 unexpected

- [ ] **Step 6: Commit**

```bash
git add action.el test/test-action.el
git commit -m "feat: add tg-upgrade action for skill point allocation"
```

---

### Task 4: Add exp reward to `tg-attack`

**Files:**
- Modify: `action.el`
- Test: `test/test-action.el`

- [ ] **Step 1: Write the failing test**

Add to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-attack exp reward ---

(ert-deftest test-tg-attack-gives-exp-on-kill ()
  "tg-attack should add exp to player when target is killed."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (rat (make-Creature :symbol 'rat :description "A rat"
                               :attr '((hp . 5) (attack . 1) (defense . 0)) :exp-reward 10)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0))))
      (setq creatures-alist (list (cons 'rat rat) (cons 'hero myself)))
      (tg-attack 'rat)
      ;; hero should gain 10 exp from killing rat
      (should (= (cdr (assoc 'exp (Creature-attr myself))) 10)))))

(ert-deftest test-tg-attack-exp-triggers-level-up ()
  "tg-attack exp gain should trigger level up when threshold reached."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (rat (make-Creature :symbol 'rat :description "A rat"
                               :attr '((hp . 5) (attack . 1) (defense . 0)) :exp-reward 150)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0))))
      (setq creatures-alist (list (cons 'rat rat) (cons 'hero myself)))
      (tg-attack 'rat)
      (should (= (cdr (assoc 'exp (Creature-attr myself))) 150))
      (should (= (cdr (assoc 'level (Creature-attr myself))) 2))
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 105))
      (should (= (cdr (assoc 'bonus-points (Creature-attr myself))) 3)))))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-action) (ert-run-tests-batch-and-exit 'test-tg-attack-gives-exp-on-kill))" 2>&1 | head -10`
Expected: FAIL — exp stays at 0 (no exp reward logic yet)

- [ ] **Step 3: Write minimal implementation**

In `action.el`, modify the `tg-attack` action. In the block where target is killed (after `(tg-display (format "%s被击败了！" target))`), add exp reward logic:

Change the killed-target block from:

```elisp
          (tg-display (format "%s被击败了！" target)))
```

To:

```elisp
          (tg-display (format "%s被击败了！" target))
          (let ((exp-gained (get-exp-reward target-creature)))
            (tg-display (format "获得 %d 点经验值！" exp-gained))
            (add-exp-to-creature myself exp-gained))))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-action) (ert-run-tests-batch-and-exit 'test-tg-attack-exp))" 2>&1 | tail -5`
Expected: Both new tests pass

- [ ] **Step 5: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-tg-mode) (require 'test-action) (require 'test-room-maker) (require 'test-creature-maker) (require 'test-inventory-maker) (require 'test-tg-config-generator) (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | tail -3`
Expected: All tests pass, 0 unexpected

- [ ] **Step 6: Commit**

```bash
git add action.el test/test-action.el
git commit -m "feat: add exp reward to tg-attack on monster kill"
```

---

### Task 5: Wire up `level-system` in `text-game-maker.el`

**Files:**
- Modify: `text-game-maker.el`

- [ ] **Step 1: Add require**

In `text-game-maker.el`, add `(require 'level-system)` after the existing `(require 'tg-config-generator)` line:

The file currently has these requires:

```elisp
(require 'tg-mode)
;; ...
(require 'room-maker)
(require 'inventory-maker)
(require 'creature-maker)
(require 'action)
(require 'tg-config-generator)
```

Add after `(require 'tg-config-generator)`:

```elisp
(require 'level-system)
```

- [ ] **Step 2: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-tg-mode) (require 'test-action) (require 'test-room-maker) (require 'test-creature-maker) (require 'test-inventory-maker) (require 'test-tg-config-generator) (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | tail -3`
Expected: All tests pass, 0 unexpected

- [ ] **Step 3: Commit**

```bash
git add text-game-maker.el
git commit -m "feat: wire up level-system in text-game-maker"
```

---

### Task 6: Update sample game

**Files:**
- Create: `sample/level-config.el`
- Modify: `sample/creature-config.el`
- Modify: `sample/sample-game.el`

- [ ] **Step 1: Create `sample/level-config.el`**

```elisp
(level-exp-table 0 50 120 220 350 500 700 950 1300 1700)
(level-up-bonus-points 3)
(auto-upgrade-attrs ((hp . 10)))
```

- [ ] **Step 2: Update `sample/creature-config.el`**

Add exp-reward as 7th field to each creature. Current content has 6 fields per creature; add a 7th:

```elisp
(hero "一位勇敢的冒险者，被困在了地牢之中" ((hp . 100) (attack . 5) (defense . 3) (exp . 0) (level . 1) (bonus-points . 0)) () () nil 0)
(guard "地牢守卫，身穿破旧的盔甲" ((hp . 40) (attack . 8) (defense . 4)) () () nil 30)
(goblin "一只狡猾的哥布林，手持匕首" ((hp . 25) (attack . 6) (defense . 2)) () () nil 18)
(bat "一只巨大的蝙蝠，发出刺耳的尖叫" ((hp . 15) (attack . 4) (defense . 1)) () () nil 10)
(skeleton-king "骷髅王，地下城的统治者。它的眼中燃烧着幽蓝色的火焰" ((hp . 80) (attack . 15) (defense . 8)) () () nil 120)
(skeleton-minion "骷髅王的仆从，一具行走的骷髅士兵" ((hp . 35) (attack . 9) (defense . 5)) () () nil 25)
(rat "一只肥大的老鼠，警惕地看着你" ((hp . 10) (attack . 2) (defense . 0)) () () nil 5)
(prisoner "一个虚弱的囚犯，蜷缩在角落里" ((hp . 20) (attack . 1) (defense . 0)) () () nil 8)
(spider "一只巨大的蜘蛛，从天花板上垂下" ((hp . 20) (attack . 7) (defense . 1)) () () nil 15)
(slime "一团粘稠的绿色史莱姆，缓慢地蠕动着" ((hp . 30) (attack . 3) (defense . 6)) () () nil 20)
(golem "一尊石像鬼，守护着武器库的入口" ((hp . 60) (attack . 12) (defense . 10)) () () nil 50)
```

- [ ] **Step 3: Update `sample/sample-game.el`**

Add `level-init` call. Change `play-sample-game` to:

```elisp
(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((sample-dir sample-game-dir))
    (map-init (expand-file-name "room-config.el" sample-dir)
              (expand-file-name "map-config.el" sample-dir))
    (inventorys-init (expand-file-name "inventory-config.el" sample-dir))
    (creatures-init (expand-file-name "creature-config.el" sample-dir))
    (level-init (expand-file-name "level-config.el" sample-dir))
    (tg-mode)
    (tg-display (tg-prompt-string))
    (tg-display (describe current-room))
    (tg-display "\n=== 地牢冒险 ===")
    (tg-display "你被困在了地下城中！探索房间，收集装备，击败怪物，找到出口！")
    (tg-display "输入 help 查看可用命令。")
    (tg-display "战斗提示: 先去走廊和武器库收集装备，再去挑战骷髅王！")
    (tg-display "升级提示: 击败怪物获得经验值，升级后用 upgrade <属性> <点数> 分配技能点！")
    (tg-display "")))
```

- [ ] **Step 4: Verify sample game loads**

Run: `emacs --batch -L . --load sample/sample-game.el --eval "(play-sample-game)" --eval "(princ (buffer-string))" 2>&1 | head -20`
Expected: Game output with room description and intro text, no errors

- [ ] **Step 5: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(progn (require 'test-tg-mode) (require 'test-action) (require 'test-room-maker) (require 'test-creature-maker) (require 'test-inventory-maker) (require 'test-tg-config-generator) (require 'test-level-system) (ert-run-tests-batch-and-exit))" 2>&1 | tail -3`
Expected: All tests pass, 0 unexpected

- [ ] **Step 6: Commit**

```bash
git add sample/level-config.el sample/creature-config.el sample/sample-game.el
git commit -m "feat: add level system to sample game"
```
