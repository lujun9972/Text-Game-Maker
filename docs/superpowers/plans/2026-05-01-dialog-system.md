# Dialog System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an NPC dialog system with single-layer branching, condition-based option visibility, and effect execution on player choice.

**Architecture:** New module `dialog-system.el` with Dialog/DialogOption structs, config loader, condition evaluator (quests, items), and effect executor. Two-phase input: `talk <NPC>` shows options via `dialog-pending` state, next `tg-parse` call processes the choice. Integration: new `tg-talk` action + `dialog-pending` check in `tg-parse`.

**Tech Stack:** Emacs Lisp, cl-defstruct, ERT testing, existing `read-from-whole-string` / `file-content` for config parsing.

---

### Task 1: Create `dialog-system.el` — Dialog structs, config loader, conditions, effects, and state

**Files:**
- Create: `dialog-system.el`
- Create: `test/test-dialog-system.el`
- Modify: `text-game-maker.el:21` (add `(require 'dialog-system)`)
- Modify: `run-tests.sh:24` (add `(require 'test-dialog-system)`)

- [ ] **Step 1: Write the failing tests**

Create `test/test-dialog-system.el`:

```elisp
;;; test-dialog-system.el --- Tests for dialog-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'dialog-system)

;; --- dialog-init ---

(ert-deftest test-dialog-init-loads-config ()
  "dialog-init should load dialogs from config file."
  (test-with-temp-file "(prisoner \"请救救我\" ((\"你是谁？\" \"探险者\" nil nil)))"
    (test-with-globals-saved (dialogs-alist)
      (dialog-init temp-file)
      (should (= (length dialogs-alist) 1))
      (should (eq (Dialog-npc (cdr (assoc 'prisoner dialogs-alist))) 'prisoner))
      (should (equal (Dialog-greeting (cdr (assoc 'prisoner dialogs-alist))) "请救救我"))
      (should (= (length (Dialog-options (cdr (assoc 'prisoner dialogs-alist)))) 1)))))

;; --- dialog-evaluate-condition ---

(ert-deftest test-dialog-evaluate-condition-nil ()
  "nil condition should always be true."
  (should (dialog-evaluate-condition nil)))

(ert-deftest test-dialog-evaluate-condition-quest-active ()
  "quest-active should match active quests."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'active)))
      (setq quests-alist (list (cons 'test-q q)))
      (should (dialog-evaluate-condition '(quest-active test-q)))
      (should-not (dialog-evaluate-condition '(quest-active other-q))))))

(ert-deftest test-dialog-evaluate-condition-quest-completed ()
  "quest-completed should match completed quests."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'completed)))
      (setq quests-alist (list (cons 'test-q q)))
      (should (dialog-evaluate-condition '(quest-completed test-q)))
      (should-not (dialog-evaluate-condition '(quest-completed other-q))))))

(ert-deftest test-dialog-evaluate-condition-has-item ()
  "has-item should check player inventory."
  (test-with-globals-saved (myself)
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword potion))))
      (setq myself cr)
      (should (dialog-evaluate-condition '(has-item sword)))
      (should (dialog-evaluate-condition '(has-item potion)))
      (should-not (dialog-evaluate-condition '(has-item shield))))))

(ert-deftest test-dialog-evaluate-condition-and ()
  "and should require all conditions true."
  (test-with-globals-saved (quests-alist myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq quests-alist (list (cons 'test-q q)))
      (setq myself cr)
      (should (dialog-evaluate-condition '(and (quest-active test-q) (has-item sword))))
      (should-not (dialog-evaluate-condition '(and (quest-active test-q) (has-item shield)))))))

(ert-deftest test-dialog-evaluate-condition-or ()
  "or should require at least one condition true."
  (test-with-globals-saved (quests-alist myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq quests-alist (list (cons 'test-q q)))
      (setq myself cr)
      (should (dialog-evaluate-condition '(or (quest-active test-q) (has-item shield))))
      (should-not (dialog-evaluate-condition '(or (quest-active other-q) (has-item shield)))))))

;; --- dialog-get-visible-options ---

(ert-deftest test-dialog-get-visible-options ()
  "Should filter options by condition."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'find-key :status 'active)))
      (setq quests-alist (list (cons 'find-key q)))
      (let* ((opt1 (make-DialogOption :text "A" :response "R1" :condition nil))
             (opt2 (make-DialogOption :text "B" :response "R2" :condition '(quest-active find-key)))
             (opt3 (make-DialogOption :text "C" :response "R3" :condition '(quest-completed find-key)))
             (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt1 opt2 opt3))))
        (let ((visible (dialog-get-visible-options dialog)))
          (should (= (length visible) 2))
          (should (equal (DialogOption-text (nth 0 visible)) "A"))
          (should (equal (DialogOption-text (nth 1 visible)) "B")))))))

;; --- dialog-apply-effects ---

(ert-deftest test-dialog-apply-effects-exp ()
  "dialog-apply-effects should grant exp."
  (test-with-globals-saved (display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :effects '((exp . 50))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-item ()
  "dialog-apply-effects should add item to player inventory."
  (test-with-globals-saved (display-fn creatures-alist inventorys-alist)
    (let* ((opt (make-DialogOption :effects '((item . potion))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq display-fn #'ignore)
      (setq inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (member 'potion (Creature-inventory cr)))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-bonus-points ()
  "dialog-apply-effects should grant bonus-points."
  (test-with-globals-saved (display-fn)
    (let* ((opt (make-DialogOption :effects '((bonus-points . 2))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-trigger ()
  "dialog-apply-effects should call trigger function."
  (test-with-globals-saved (display-fn)
    (let (trigger-called)
      (let ((trigger-fn (lambda () (setq trigger-called t))))
        (let ((opt (make-DialogOption :effects `((trigger . ,trigger-fn)))))
          (setq display-fn #'ignore)
          (dialog-apply-effects opt)
          (should trigger-called))))))

;; --- dialog-start ---

(ert-deftest test-dialog-start-success ()
  "dialog-start should display greeting and options, set dialog-pending."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending)
    (let* ((opt (make-DialogOption :text "Hello" :response "Hi" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "What?" :options (list opt)))
           (output nil))
      (setq dialogs-alist (list (cons 'guard dialog)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-start 'guard)
      (should (eq dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "What?" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-start-no-dialog ()
  "dialog-start should throw when NPC has no dialog."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending)
    (setq dialogs-alist nil)
    (setq display-fn #'ignore)
    (should (equal (catch 'exception (dialog-start 'nobody)) "无法与nobody对话"))))

(ert-deftest test-dialog-start-no-visible-options ()
  "dialog-start should show message when no options are visible."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending quests-alist)
    (let* ((opt (make-DialogOption :text "Hidden" :response "R" :condition '(quest-active missing)))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialogs-alist (list (cons 'guard dialog)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq quests-alist nil)
      (dialog-start 'guard)
      (should (null dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "没有可用的对话选项" s)) (mapcar #'car output))))))

;; --- dialog-handle-choice ---

(ert-deftest test-dialog-handle-choice-valid ()
  "dialog-handle-choice should process valid choice and clear dialog-pending."
  (test-with-globals-saved (dialog-pending display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "Response A" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialog-pending dialog)
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-handle-choice "1")
      (should (null dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "Response A" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-handle-choice-invalid ()
  "dialog-handle-choice should keep dialog-pending on invalid input."
  (test-with-globals-saved (dialog-pending display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialog-pending dialog)
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-handle-choice "5")
      (should (eq dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "请输入有效的选项编号" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-handle-choice-applies-effects ()
  "dialog-handle-choice should apply effects on valid choice."
  (test-with-globals-saved (dialog-pending display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil :effects '((exp . 30))))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq dialog-pending dialog)
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-handle-choice "1")
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 30))
        (should (null dialog-pending))
        (setq myself old-myself)))))

(provide 'test-dialog-system)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-dialog-system.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -5`
Expected: Tests FAIL (module doesn't exist yet).

- [ ] **Step 3: Create `dialog-system.el`**

```elisp
;;; dialog-system.el --- Dialog system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)
(require 'quest-system)

(defvar dialogs-alist nil
  "NPC symbol到Dialog对象的映射")

(defvar dialog-pending nil
  "当前等待选择的Dialog对象（nil表示无待处理对话）")

(cl-defstruct Dialog
  "Dialog structure"
  (npc nil :documentation "关联的 NPC symbol")
  (greeting "" :documentation "NPC 开场白")
  (options nil :documentation "DialogOption 列表"))

(cl-defstruct DialogOption
  "Dialog option structure"
  (text "" :documentation "玩家看到的选项文本")
  (response "" :documentation "NPC 的回应文本")
  (condition nil :documentation "显示条件（nil 表示总是显示）")
  (effects nil :documentation "效果列表"))

;; --- Config loading ---

(defun build-option (option-data)
  "根据OPTION-DATA创建DialogOption对象."
  (make-DialogOption
   :text (nth 0 option-data)
   :response (nth 1 option-data)
   :condition (nth 2 option-data)
   :effects (nth 3 option-data)))

(defun build-dialog (dialog-entity)
  "根据DIALOG-ENTITY创建Dialog对象."
  (let ((npc (nth 0 dialog-entity))
        (greeting (nth 1 dialog-entity))
        (options-data (nth 2 dialog-entity)))
    (cons npc (make-Dialog
               :npc npc
               :greeting greeting
               :options (mapcar #'build-option options-data)))))

(defun dialog-init (config-file)
  "从CONFIG-FILE加载对话配置."
  (let ((dialog-entities (read-from-whole-string (file-content config-file))))
    (setq dialogs-alist (mapcar #'build-dialog dialog-entities))))

;; --- Condition evaluation ---

(defun dialog-evaluate-condition (cond-expr)
  "评估条件表达式COND-EXPR."
  (cond
   ((null cond-expr) t)
   ((eq (car cond-expr) 'quest-active)
    (let ((q (cdr (assoc (cadr cond-expr) quests-alist))))
      (and q (eq (Quest-status q) 'active))))
   ((eq (car cond-expr) 'quest-completed)
    (let ((q (cdr (assoc (cadr cond-expr) quests-alist))))
      (and q (eq (Quest-status q) 'completed))))
   ((eq (car cond-expr) 'has-item)
    (and myself (member (cadr cond-expr) (Creature-inventory myself))))
   ((eq (car cond-expr) 'and)
    (cl-every #'dialog-evaluate-condition (cdr cond-expr)))
   ((eq (car cond-expr) 'or)
    (cl-some #'dialog-evaluate-condition (cdr cond-expr)))
   (t nil)))

(defun dialog-get-visible-options (dialog)
  "返回DIALOG中满足条件的选项列表."
  (cl-remove-if-not
   (lambda (opt) (dialog-evaluate-condition (DialogOption-condition opt)))
   (Dialog-options dialog)))

;; --- Effect execution ---

(defun dialog-apply-effects (option)
  "执行OPTION的效果."
  (dolist (effect (DialogOption-effects option))
    (let ((key (car effect))
          (value (cdr effect)))
      (pcase key
        ('exp (add-exp-to-creature myself value))
        ('item (add-inventory-to-creature myself value))
        ('bonus-points (take-effect-to-creature myself (cons 'bonus-points value)))
        ('trigger (when (functionp value) (funcall value)))))))

;; --- Dialog interaction ---

(defun dialog-start (npc-symbol)
  "开始与NPC-SYMBOL的对话."
  (let ((dialog (cdr (assoc npc-symbol dialogs-alist))))
    (unless dialog
      (throw 'exception (format "无法与%s对话" npc-symbol)))
    (let ((visible-options (dialog-get-visible-options dialog)))
      (tg-display (format "%s说：%s" npc-symbol (Dialog-greeting dialog)))
      (if (null visible-options)
          (tg-display "没有可用的对话选项")
        (setq dialog-pending dialog)
        (dotimes (i (length visible-options))
          (tg-display (format "  %d. %s" (1+ i) (DialogOption-text (nth i visible-options)))))
        (tg-display "请输入选项编号:")))))

(defun dialog-handle-choice (input)
  "处理玩家对话选择INPUT."
  (let* ((visible-options (dialog-get-visible-options dialog-pending))
         (choice (string-to-number input))
         (npc (Dialog-npc dialog-pending)))
    (if (and (> choice 0) (<= choice (length visible-options)))
        (let ((option (nth (1- choice) visible-options)))
          (tg-display (format "%s说：%s" npc (DialogOption-response option)))
          (dialog-apply-effects option)
          (setq dialog-pending nil))
      (tg-display "请输入有效的选项编号"))))

(provide 'dialog-system)
```

- [ ] **Step 4: Add `(require 'dialog-system)` to `text-game-maker.el`**

After line 21 (`(require 'quest-system)`), add:

```elisp
(require 'dialog-system)
```

- [ ] **Step 5: Add `(require 'test-dialog-system)` to `run-tests.sh`**

After the `(require 'test-quest-system)` line (line 24), add:

```elisp
    (require 'test-dialog-system)
```

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (210 existing + 20 new = 230).

- [ ] **Step 7: Commit**

```bash
git add dialog-system.el test/test-dialog-system.el text-game-maker.el run-tests.sh
git commit -m "feat: create dialog-system.el with dialog structs, conditions, and effects

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add `tg-talk` command and integrate `dialog-pending` in `tg-parse`

**Files:**
- Modify: `action.el` (add `tg-talk` command + `(require 'dialog-system)`)
- Modify: `tg-mode.el` (replace `tg-parse` with `dialog-pending` check + `(require 'dialog-system)`)
- Modify: `test/test-action.el` (add integration tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-talk command ---

(ert-deftest test-tg-talk-starts-dialog ()
  "tg-talk should start dialog with NPC in room."
  (test-with-globals-saved (tg-valid-actions display-fn rooms-alist room-map current-room
                              creatures-alist dialogs-alist dialog-pending)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "Room" :creature '(guard)))
           (guard-cr (make-Creature :symbol 'guard :description "Guard" :attr '((hp . 50))))
           (opt (make-DialogOption :text "Hi" :response "Hello" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "What?" :options (list opt)))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'guard guard-cr)))
      (setq dialogs-alist (list (cons 'guard dialog)))
      (tg-talk 'guard)
      (should (eq dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "What?" s)) (mapcar #'car output))))))

(ert-deftest test-tg-talk-npc-not-in-room ()
  "tg-talk should throw when NPC is not in room."
  (test-with-globals-saved (tg-valid-actions display-fn rooms-alist room-map current-room
                              creatures-alist dialogs-alist dialog-pending)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "Room" :creature nil))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist nil)
      (setq dialogs-alist nil)
      (let ((result (catch 'exception (tg-talk 'nobody))))
        (should (string-match-p "没有" result))))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-action.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -E "test-tg-talk"`
Expected: New tests FAIL (tg-talk doesn't exist yet).

- [ ] **Step 3: Add `(require 'dialog-system)` and `tg-talk` to `action.el`**

Add `(require 'dialog-system)` after `(require 'quest-system)` (after line 10).

Add the `tg-talk` action before `tg-quests` (before line 183):

```elisp
(tg-defaction tg-talk (npc-name)
  "使用'talk <NPC>'与NPC对话"
  (when (stringp npc-name)
    (setq npc-name (intern npc-name)))
  (unless (creature-exist-in-room-p current-room npc-name)
    (throw 'exception (format "房间中没有%s" npc-name)))
  (dialog-start npc-name))

```

- [ ] **Step 4: Modify `tg-mode.el` to add `dialog-pending` check**

Add `(require 'dialog-system)` after `(require 'npc-behavior)` (after line 4).

Replace the entire `tg-parse` function (lines 82-110) with this version that wraps the command parsing in an `if dialog-pending` check:

```elisp
(defun tg-parse (arg)
  "Function called when return is pressed in interactive mode to parse line."
  (interactive "*p")
  (beginning-of-line)
  (let ((line-start (point))
        line prompt-end)
    (end-of-line)
    (when (and (not (= line-start (point)))
               (not (< (point) line-start)))
      (save-excursion
        (setq prompt-end (search-backward ">" (line-beginning-position) t)))
      (when prompt-end
        (setq line (downcase (buffer-substring (1+ prompt-end) (point))))
        (tg-mprinc "\n")
        (if dialog-pending
            (progn
              (dialog-handle-choice line)
              (npc-run-behaviors))
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
            (npc-run-behaviors))))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))
```

Key change: the original `(let (action-result ...) ...)` block is wrapped inside the `else` branch of `(if dialog-pending ...)`. When `dialog-pending` is set, the input is passed to `dialog-handle-choice` instead of being parsed as a command.

- [ ] **Step 5: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (230 existing + 2 new = 232).

- [ ] **Step 6: Commit**

```bash
git add action.el tg-mode.el test/test-action.el
git commit -m "feat: add tg-talk command and integrate dialog-pending in tg-parse

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add sample dialog config and update sample game

**Files:**
- Create: `sample/dialog-config.el`
- Modify: `sample/sample-game.el`

- [ ] **Step 1: Create `sample/dialog-config.el`**

Based on the sample game's NPCs and quests:

```elisp
(prisoner "请救救我...你能帮帮我吗？"
  (("你是谁？" "我是被骷髅王关押的探险者。如果你能救我出去，我会报答你的！" nil nil)
   ("有什么线索吗？" "听说武器库里有把好剑！从走廊往右就能到。还有...地牢入口的守卫身上可能有钥匙。"
    nil ((exp . 15)))
   ("给你点面包" "谢谢你！这个给你，是我在牢房角落找到的。"
    (has-item bread) ((exp . 10)))))
(guard "哼，你想干什么？"
  (("你是谁？" "我是骷髅王的手下，负责看守地牢入口。" nil nil)
   ("关于骷髅王..." "骷髅王？他在王座间等着呢。不过你得先通过走廊里的那些怪物才行。"
    nil ((exp . 10)))))
(goblin "嘿嘿嘿...你想跟哥布林做什么？"
  (("交出你的宝物！" "好吧好吧...拿去！" nil ((exp . 5)))))
(golem "......"
  (("（沉默注视）" "......你可不像其他入侵者。" nil nil)))
```

- [ ] **Step 2: Update `sample/sample-game.el`**

Add `(dialog-init ...)` call after `(quest-init ...)` (after line 21):

```elisp
    (dialog-init (expand-file-name "dialog-config.el" sample-dir))
```

Add a dialog hint after the quest hint line:

```elisp
    (tg-display "对话提示: 输入 talk <NPC名称> 与NPC对话！")
```

- [ ] **Step 3: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All 232 tests pass.

- [ ] **Step 4: Commit**

```bash
git add sample/dialog-config.el sample/sample-game.el
git commit -m "feat: add dialog config and integrate into sample game

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
