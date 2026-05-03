# Quest System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a quest system with kill/collect/explore/talk quest types, auto-tracking via existing actions, reward distribution, and quest display commands.

**Architecture:** New module `quest-system.el` with Quest struct, config loader, tracking functions, and reward system. Integration points: insert `quest-track-*` calls into existing `tg-attack`, `tg-take`, `tg-move`, `tg-watch` actions in `action.el`. Two new `tg-defaction` commands: `quests` and `quest`.

**Tech Stack:** Emacs Lisp, cl-defstruct, ERT testing, existing `read-from-whole-string` / `file-content` for config parsing.

---

### Task 1: Create `quest-system.el` — Quest struct, config loader, and tracking

**Files:**
- Create: `quest-system.el`
- Create: `test/test-quest-system.el`
- Modify: `text-game-maker.el:20` (add `(require 'quest-system)`)
- Modify: `run-tests.sh` (add `(require 'test-quest-system)`)

- [ ] **Step 1: Write the failing tests**

Create `test/test-quest-system.el`:

```elisp
;;; test-quest-system.el --- Tests for quest-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'quest-system)

;; --- quest-init ---

(ert-deftest test-quest-init-loads-config ()
  "quest-init should load quests from config file."
  (test-with-temp-file "(kill-rats \"消灭老鼠\" kill rat 3 ((exp . 15)) inactive \"老鼠被消灭了！\")
                         (find-key \"找到钥匙\" collect key 1 ((exp . 20)) inactive \"你找到了钥匙！\")"
    (test-with-globals-saved (quests-alist)
      (quest-init temp-file)
      (should (= (length quests-alist) 2))
      (should (equal (Quest-type (cdr (assoc 'kill-rats quests-alist))) 'kill))
      (should (equal (Quest-type (cdr (assoc 'find-key quests-alist))) 'collect)))))

(ert-deftest test-quest-init-sets-active ()
  "quest-init should set all quests to active status."
  (test-with-temp-file "(test-quest \"Test\" kill rat 1 ((exp . 10)) inactive \"Done!\")"
    (test-with-globals-saved (quests-alist)
      (quest-init temp-file)
      (should (eq (Quest-status (cdr (assoc 'test-quest quests-alist))) 'active)))))

;; --- quest-track-kill ---

(ert-deftest test-quest-track-kill-updates-progress ()
  "quest-track-kill should increment progress for matching kill quests."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 3 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'kill-goblin q)))
      (setq display-fn #'ignore)
      (quest-track-kill 'goblin)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'active)))))

(ert-deftest test-quest-track-kill-completes ()
  "quest-track-kill should complete quest when progress reaches count."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 0
                          :status 'active :description "Kill rat" :description-complete "Done!"))
          (output nil))
      (setq quests-alist (list (cons 'kill-rat q)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (quest-track-kill 'rat)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

(ert-deftest test-quest-track-kill-skips-completed ()
  "quest-track-kill should not update completed quests."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 1
                          :status 'completed)))
      (setq quests-alist (list (cons 'kill-rat q)))
      (setq display-fn #'ignore)
      (quest-track-kill 'rat)
      (should (= (Quest-progress q) 1)))))

(ert-deftest test-quest-track-kill-no-match ()
  "quest-track-kill should do nothing when no matching quest."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'kill-goblin q)))
      (setq display-fn #'ignore)
      (quest-track-kill 'rat)
      (should (= (Quest-progress q) 0)))))

;; --- quest-track-collect ---

(ert-deftest test-quest-track-collect-updates-progress ()
  "quest-track-collect should increment progress for matching collect quests."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'find-key :type 'collect :target 'key :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'find-key q)))
      (setq display-fn #'ignore)
      (quest-track-collect 'key)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-track-explore ---

(ert-deftest test-quest-track-explore-updates-progress ()
  "quest-track-explore should increment progress for matching explore quests."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'reach-hall :type 'explore :target 'hall :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'reach-hall q)))
      (setq display-fn #'ignore)
      (quest-track-explore 'hall)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-track-talk ---

(ert-deftest test-quest-track-talk-updates-progress ()
  "quest-track-talk should increment progress for matching talk quests."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'talk-guard :type 'talk :target 'guard :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'talk-guard q)))
      (setq display-fn #'ignore)
      (quest-track-talk 'guard)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-apply-rewards ---

(ert-deftest test-quest-reward-exp ()
  "quest-apply-rewards should grant exp."
  (test-with-globals-saved (quests-alist display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let ((q (make-Quest :symbol 'test-q :rewards '((exp . 50)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      ;; Temporarily set myself for the reward function
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-item ()
  "quest-apply-rewards should add item to player inventory."
  (test-with-globals-saved (quests-alist display-fn creatures-alist inventorys-alist)
    (let ((q (make-Quest :symbol 'test-q :rewards '((item . potion)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq display-fn #'ignore)
      (setq inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (member 'potion (Creature-inventory cr)))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-bonus-points ()
  "quest-apply-rewards should grant bonus-points."
  (test-with-globals-saved (quests-alist display-fn)
    (let ((q (make-Quest :symbol 'test-q :rewards '((bonus-points . 2)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-trigger ()
  "quest-apply-rewards should call trigger function."
  (test-with-globals-saved (quests-alist display-fn)
    (let (trigger-called)
      (let ((q (make-Quest :symbol 'test-q :rewards `((trigger . (lambda () (setq trigger-called t)))) :status 'active)))
        (setq display-fn #'ignore)
        (quest-apply-rewards q)
        (should trigger-called)))))

(provide 'test-quest-system)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-quest-system.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -5`
Expected: Tests FAIL (module doesn't exist yet).

- [ ] **Step 3: Create `quest-system.el`**

```elisp
;;; quest-system.el --- Quest system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)

(defvar quests-alist nil
  "symbol到Quest对象的映射")

(cl-defstruct Quest
  "Quest structure"
  (symbol nil :documentation "任务唯一标识符")
  (description "" :documentation "任务描述")
  (type nil :documentation "任务类型: kill/collect/explore/talk")
  (target nil :documentation "任务目标 symbol")
  (count 1 :documentation "目标数量")
  (progress 0 :documentation "当前进度")
  (rewards nil :documentation "奖励列表")
  (status 'inactive :documentation "任务状态: inactive/active/completed/failed")
  (description-complete "" :documentation "完成时的提示文本"))

;; --- Config loading ---

(defun build-quest (quest-entity)
  "根据quest-entity创建Quest对象."
  (cl-multiple-value-bind (symbol description type target count rewards status description-complete) quest-entity
    (let ((q (make-Quest :symbol symbol :description description :type type :target target
                          :count count :rewards rewards :status 'active
                          :description-complete description-complete)))
      (cons symbol q))))

(defun quest-init (config-file)
  "从CONFIG-FILE加载任务配置."
  (let ((quest-entities (read-from-whole-string (file-content config-file))))
    (setq quests-alist (mapcar #'build-quest quest-entities))))

;; --- Reward distribution ---

(defun quest-apply-rewards (quest)
  "发放QUEST的奖励."
  (dolist (reward (Quest-rewards quest))
    (let ((key (car reward))
          (value (cdr reward)))
      (pcase key
        ('exp (add-exp-to-creature myself value))
        ('item (add-inventory-to-creature myself value))
        ('bonus-points (take-effect-to-creature myself (cons 'bonus-points value)))
        ('trigger (when (functionp value) (funcall value)))))))

;; --- Progress tracking ---

(defun quest-update-progress (quest)
  "Update quest progress and check completion."
  (cl-incf (Quest-progress quest))
  (when (>= (Quest-progress quest) (Quest-count quest))
    (setf (Quest-status quest) 'completed)
    (tg-display (format "任务完成：%s" (Quest-description quest)))
    (when (Quest-description-complete quest)
      (tg-display (Quest-description-complete quest)))
    (quest-apply-rewards quest)))

(defun quest-track-kill (target-symbol)
  "追踪击杀TARGET-SYMBOL的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) 'kill)
                 (eq (Quest-target q) target-symbol))
        (quest-update-progress q)))))

(defun quest-track-collect (item-symbol)
  "追踪收集ITEM-SYMBOL的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) 'collect)
                 (eq (Quest-target q) item-symbol))
        (quest-update-progress q)))))

(defun quest-track-explore (room-symbol)
  "追踪探索ROOM-SYMBOL的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) 'explore)
                 (eq (Quest-target q) room-symbol))
        (quest-update-progress q)))))

(defun quest-track-talk (npc-symbol)
  "追踪与NPC-SYMBOL对话的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) 'talk)
                 (eq (Quest-target q) npc-symbol))
        (quest-update-progress q)))))

;; --- Quest listing ---

(defun quest-list-active ()
  "列出所有活跃任务."
  (cl-remove-if-not (lambda (pair) (eq (Quest-status (cdr pair)) 'active)) quests-alist))

(defun quest-list-all ()
  "列出所有任务."
  quests-alist)

(provide 'quest-system)
```

- [ ] **Step 4: Add `(require 'quest-system)` to `text-game-maker.el`**

After line 20 (`(require 'save-system)`), add:

```elisp
(require 'quest-system)
```

- [ ] **Step 5: Add `(require 'test-quest-system)` to `run-tests.sh`**

After the `(require 'test-save-system)` line, add:

```elisp
    (require 'test-quest-system)
```

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (195 existing + 14 new = 209).

- [ ] **Step 7: Commit**

```bash
git add quest-system.el test/test-quest-system.el text-game-maker.el run-tests.sh
git commit -m "feat: create quest-system.el with quest struct, tracking, and rewards

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add `tg-quests`/`tg-quest` commands and integrate tracking into actions

**Files:**
- Modify: `action.el` (add quest tracking calls + new commands)
- Test: `test/test-action.el`

- [ ] **Step 1: Write the failing tests**

Append to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-attack quest tracking ---

(ert-deftest test-tg-attack-triggers-kill-quest ()
  "tg-attack should trigger kill quest progress when target is killed."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself quests-alist level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :creature '(rat)))
           (rat (make-Creature :symbol 'rat :description "A rat"
                                :attr '((hp . 5) (attack . 1) (defense . 0)) :exp-reward 5))
           (q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 0
                          :status 'active :description "Kill rat" :description-complete "Done!")))
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0))))
      (setq creatures-alist (list (cons 'rat rat) (cons 'hero myself)))
      (setq quests-alist (list (cons 'kill-rat q)))
      (tg-attack 'rat)
      (should (eq (Quest-status q) 'completed)))))

;; --- tg-quests command ---

(ert-deftest test-tg-quests-displays-active ()
  "tg-quests should display active quests."
  (test-with-globals-saved (tg-valid-actions display-fn quests-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((q (make-Quest :symbol 'test-q :description "Test quest" :type 'kill :target 'rat
                          :count 3 :progress 1 :status 'active))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq quests-alist (list (cons 'test-q q)))
      (tg-quests)
      (should (cl-some (lambda (s) (string-match-p "Test quest" s)) (mapcar #'car output))))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-action.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -E "test-tg-attack-triggers-kill|test-tg-quests"`
Expected: New tests FAIL.

- [ ] **Step 3: Add quest tracking calls and new commands to `action.el`**

Add `(require 'quest-system)` after `(require 'npc-behavior)` at the top of `action.el`.

**In `tg-attack`** (around line 130, after `(tg-display (format "%s被击败了！" target))`): add `(quest-track-kill target)` on the next line.

The killed block becomes:
```elisp
          (tg-display (format "%s被击败了！" target))
          (quest-track-kill target)
          (let ((exp-gained (get-exp-reward target-creature)))
```

**In `tg-take`** (around line 67, after `(remove-inventory-from-room current-room inventory)`): add `(quest-track-collect inventory)` on the next line.

The end of `tg-take` becomes:
```elisp
    (add-inventory-to-creature myself inventory)
    (remove-inventory-from-room current-room inventory)
    (quest-track-collect inventory)))
```

**In `tg-move`** (around line 34, after `(tg-display (describe current-room))`): add `(quest-track-explore new-room-symbol)` between the describe and the npc-run-behaviors calls.

The end of `tg-move` becomes:
```elisp
    (tg-display (describe current-room))
    (quest-track-explore new-room-symbol)
    (npc-run-behaviors)))
```

**In `tg-watch`** (around line 54, before `(describe object)`): after the trigger call, check if the object is a Creature and call quest-track-talk. Add `(when (and symbol (Creature-p object)) (quest-track-talk symbol))` before the final `(describe object)`.

The end of `tg-watch` becomes:
```elisp
      (when-let* ((trig (cond ((Inventory-p object) (Inventory-watch-trigger object))
                               ((Creature-p object) (Creature-watch-trigger object)))))
        (funcall trig))
    (when (and symbol (Creature-p object))
      (quest-track-talk symbol))
    (describe object)))
```

**Add new commands** before `tg-save`:

```elisp
(tg-defaction tg-quests ()
  "使用'quests'查看当前任务列表"
  (tg-display "=== 任务列表 ===")
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (cond ((eq (Quest-status q) 'active)
             (tg-display (format "[进行中] %s (%d/%d)" (Quest-description q) (Quest-progress q) (Quest-count q))))
            ((eq (Quest-status q) 'completed)
             (tg-display (format "[已完成] %s" (Quest-description q))))
            ((eq (Quest-status q) 'inactive)
             (tg-display (format "[未开始] %s" (Quest-description q))))))))

(tg-defaction tg-quest (name)
  "使用'quest <名称>'查看指定任务详情"
  (when (stringp name)
    (setq name (intern name)))
  (let ((q (cdr (assoc name quests-alist))))
    (unless q
      (throw 'exception (format "没有任务%s" name)))
    (tg-display (format "任务：%s" (Quest-description q)))
    (tg-display (format "类型：%s  目标：%s" (Quest-type q) (Quest-target q)))
    (tg-display (format "进度：%d/%d" (Quest-progress q) (Quest-count q)))
    (tg-display (format "状态：%s" (Quest-status q)))
    (when (Quest-rewards q)
      (tg-display (format "奖励：%s" (Quest-rewards q))))))
```

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (209 existing + 2 new = 211).

- [ ] **Step 5: Commit**

```bash
git add action.el test/test-action.el
git commit -m "feat: integrate quest tracking into actions and add quests/quest commands

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add sample quest config and update sample game

**Files:**
- Create: `sample/quest-config.el`
- Modify: `sample/sample-game.el`

- [ ] **Step 1: Create `sample/quest-config.el`**

Based on the sample game's rooms, creatures, and items:

```elisp
(kill-rats "消灭老鼠" kill rat 1 ((exp . 10)) inactive "你消灭了地牢中的老鼠！")
(kill-goblins "击败哥布林群" kill goblin 1 ((exp . 30)) inactive "哥布林群被消灭了！")
(talk-prisoner "与囚犯对话" talk prisoner 1 ((exp . 15) (item . map)) inactive "囚犯给了你一张地图，上面标记了隐藏的宝物！")
(collect-sword "获取铁剑" collect iron-sword 1 ((exp . 20)) inactive "你找到了一把铁剑！")
(explore-throne "探索王座间" explore throne 1 ((exp . 50)) inactive "你踏入了王座间，空气中弥漫着死亡的气息...")
(defeat-skeleton-king "击败骷髅王" kill skeleton-king 1 ((exp . 200) (bonus-points . 5)) inactive "骷髅王倒下了！你解放了这座地牢！")
```

- [ ] **Step 2: Update `sample/sample-game.el`**

Add `(quest-init ...)` call after `(level-init ...)` and add a quest hint:

After line 20 (`(level-init (expand-file-name "level-config.el" sample-dir))`), add:

```elisp
    (quest-init (expand-file-name "quest-config.el" sample-dir))
```

After the save hint line, add:

```elisp
    (tg-display "任务提示: 输入 quests 查看任务列表，quest <名称> 查看任务详情！")
```

- [ ] **Step 3: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All 211 tests pass.

- [ ] **Step 4: Commit**

```bash
git add sample/quest-config.el sample/sample-game.el
git commit -m "feat: add quest config and integrate into sample game

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
