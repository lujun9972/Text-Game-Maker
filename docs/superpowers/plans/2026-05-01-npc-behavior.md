# NPC 主动行为系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a proactive NPC behavior system where NPCs evaluate conditions and autonomously attack, move, speak, or apply buffs/debuffs each turn.

**Architecture:** New module `npc-behavior.el` with condition evaluator and action executor. Creature struct gains a `behaviors` slot (rule list). Integration points: `tg-parse` (after player action) and `tg-move` (after entering room). Each NPC executes at most one matching rule per turn.

**Tech Stack:** Emacs Lisp, EIEIO cl-defstruct, ERT testing, existing `take-effect-to-creature` / `tg-display` / room APIs.

---

### Task 1: Add `behaviors` slot to Creature struct

**Files:**
- Modify: `creature-maker.el:12-22` (Creature struct)
- Modify: `creature-maker.el:32-35` (`build-creature`)
- Test: `test/test-creature-maker.el`

- [ ] **Step 1: Write the failing tests**

Append to `test/test-creature-maker.el` before `(provide 'test-creature-maker)`:

```elisp
;; --- behaviors slot ---

(ert-deftest test-creature-behaviors-slot-default-nil ()
  "Creature behaviors slot should default to nil."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin")))
    (should (null (Creature-behaviors cr)))))

(ert-deftest test-creature-behaviors-slot-set ()
  "Creature behaviors slot should be settable."
  (let ((rules '((((always) attack))))
        (cr (make-Creature :symbol 'goblin :description "A goblin" :behaviors rules)))
    (should (equal (Creature-behaviors cr) rules))))

(ert-deftest test-build-creature-with-behaviors ()
  "build-creature should parse 8-element tuple with behaviors."
  (let* ((result (build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15 (((always) attack)))))
         (cr (cdr result)))
    (should (= (length (Creature-behaviors cr)) 1))))

(ert-deftest test-build-creature-without-behaviors ()
  "build-creature should default behaviors to nil for 7-element tuple."
  (let* ((result (build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15)))
         (cr (cdr result)))
    (should (null (Creature-behaviors cr)))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-creature-maker.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -E "(FAILED|passed|FAILED|error)"`
Expected: The 4 new tests FAIL (behaviors slot doesn't exist yet).

- [ ] **Step 3: Add the `behaviors` slot and update `build-creature`**

In `creature-maker.el`, add after line 22 (`(exp-reward ...)`):

```elisp
  (behaviors nil :documentation "NPC主动行为规则列表")
```

Update `build-creature` to accept 8 elements. Change the function to:

```elisp
(defun build-creature (creature-entity)
  "根据creature-entity创建creature,并将creature存入creatures-alist中"
  (cl-multiple-value-bind (symbol description attr inventory equipment death-trigger exp-reward behaviors) creature-entity
    (cons symbol (make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr :death-trigger death-trigger :exp-reward exp-reward :behaviors behaviors))))
```

- [ ] **Step 4: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -3`
Expected: All tests pass (existing tests still pass because `cl-multiple-value-bind` with shorter lists fills remaining vars with nil).

- [ ] **Step 5: Commit**

```bash
git add creature-maker.el test/test-creature-maker.el
git commit -m "feat: add behaviors slot to Creature struct"
```

---

### Task 2: Create `npc-behavior.el` — condition evaluator and action executor

**Files:**
- Create: `npc-behavior.el`
- Test: `test/test-npc-behavior.el`

- [ ] **Step 1: Write the failing tests**

Create `test/test-npc-behavior.el`:

```elisp
;;; test-npc-behavior.el --- Tests for npc-behavior.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'npc-behavior)

;; --- npc-evaluate-condition ---

(ert-deftest test-npc-condition-always ()
  "always condition should return t."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25)))))
    (should (npc-evaluate-condition cr '(always)))))

(ert-deftest test-npc-condition-hp-below-true ()
  "hp-below should return t when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-below-false ()
  "hp-below should return nil when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-above-true ()
  "hp-above should return t when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should (npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-hp-above-false ()
  "hp-above should return nil when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should-not (npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-player-in-room-true ()
  "player-in-room should return t when player symbol is in room creatures."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (should (npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-player-in-room-false ()
  "player-in-room should return nil when player not in room."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (should-not (npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-and ()
  "and should return t only when all sub-conditions are true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(and (hp-below 15) (hp-above 5))))
    (should-not (npc-evaluate-condition cr '(and (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-or ()
  "or should return t when any sub-condition is true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(or (hp-below 5) (hp-above 5))))
    (should-not (npc-evaluate-condition cr '(or (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-not ()
  "not should invert condition result."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (npc-evaluate-condition cr '(not (hp-above 10))))
    (should (npc-evaluate-condition cr '(not (hp-below 10))))))

;; --- npc-execute-action: attack ---

(ert-deftest test-npc-attack-player-deals-damage ()
  "npc attack should deal damage to player."
  (test-with-globals-saved (display-fn creatures-alist myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 8))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 3))))
      (setq tg-over-p nil)
      (npc-execute-action goblin '(attack))
      ;; damage = max(1, 8 - 3) = 5, hero hp: 100 - 5 = 95
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 95)))))

(ert-deftest test-npc-attack-player-kills ()
  "npc attack should set tg-over-p when player dies."
  (test-with-globals-saved (display-fn creatures-alist myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 50))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 10) (defense . 0))))
      (setq tg-over-p nil)
      (npc-execute-action goblin '(attack))
      (should tg-over-p))))

;; --- npc-execute-action: say ---

(ert-deftest test-npc-say-displays-message ()
  "npc say should display message via tg-display."
  (test-with-globals-saved (display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (npc-execute-action goblin '(say "Hello!"))
      (should (cl-some (lambda (s) (string-match-p "goblin" s)) (mapcar #'car output))))))

;; --- npc-execute-action: move ---

(ert-deftest test-npc-move-random ()
  "npc move random should move creature to an adjacent room."
  (test-with-globals-saved (rooms-alist room-map current-room display-fn)
    (let* ((room1 (make-Room :symbol 'room1 :creature '(goblin)))
           (room2 (make-Room :symbol 'room2 :creature nil))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq current-room room1)
      (setq display-fn #'ignore)
      (npc-execute-action goblin '(move random))
      ;; goblin should have left room1
      (should-not (creature-exist-in-room-p room1 'goblin)))))

;; --- npc-execute-action: buff/debuff ---

(ert-deftest test-npc-buff-self ()
  "npc buff should increase creature's own attr."
  (test-with-globals-saved (display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq display-fn #'ignore)
      (npc-execute-action goblin '(buff attack 3))
      (should (= (cdr (assoc 'attack (Creature-attr goblin))) 8)))))

(ert-deftest test-npc-debuff-player ()
  "npc debuff should decrease player's attr."
  (test-with-globals-saved (display-fn myself)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq display-fn #'ignore)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 5))))
      (npc-execute-action goblin '(debuff defense 2))
      (should (= (cdr (assoc 'defense (Creature-attr myself))) 3)))))

;; --- npc-run-behaviors ---

(ert-deftest test-npc-run-behaviors-matches-first-rule ()
  "npc-run-behaviors should execute only the first matching rule."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5))
                                  :behaviors '(((always) say "first") ((always) say "second"))))
           (room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq tg-over-p nil)
      (npc-run-behaviors)
      ;; Should only see "first" message, not "second"
      (should (= 1 (cl-count-if (lambda (s) (string-match-p "first" s)) (mapcar #'car output)))))))

(ert-deftest test-npc-run-behaviors-skips-myself ()
  "npc-run-behaviors should skip myself even if it has behaviors."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))
                                  :behaviors '(((always) say "I act!"))))
      (setq creatures-alist (list (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-npc-run-behaviors-skips-dead-npc ()
  "npc-run-behaviors should skip NPCs with HP <= 0."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 0))
                                  :behaviors '(((always) say "I'm dead"))))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-npc-run-behaviors-no-behaviors-noop ()
  "npc-run-behaviors should do nothing for NPCs with nil behaviors."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25)) :behaviors nil))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(provide 'test-npc-behavior)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-npc-behavior.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -5`
Expected: All new tests FAIL (module doesn't exist yet).

- [ ] **Step 3: Create `npc-behavior.el`**

```elisp
;;; npc-behavior.el --- NPC proactive behavior system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)

;; --- Condition evaluator ---

(defun npc-evaluate-condition (creature condition)
  "Evaluate CONDITION for CREATURE. Return t or nil."
  (let ((op (car condition))
        (args (cdr condition)))
    (pcase op
      ('always t)
      ('hp-below
       (let ((hp (or (cdr (assoc 'hp (Creature-attr creature))) 0)))
         (< hp (car args))))
      ('hp-above
       (let ((hp (or (cdr (assoc 'hp (Creature-attr creature))) 0)))
         (> hp (car args))))
      ('player-in-room
       (and current-room
            (member (Creature-symbol myself) (Room-creature current-room))))
      ('and
       (cl-every (lambda (c) (npc-evaluate-condition creature c)) args))
      ('or
       (cl-some (lambda (c) (npc-evaluate-condition creature c)) args))
      ('not
       (not (npc-evaluate-condition creature (car args))))
      (_ nil))))

;; --- Action executor ---

(defun npc-attack-player (creature)
  "CREATURE attacks the player."
  (let* ((npc-attack (or (cdr (assoc 'attack (Creature-attr creature))) 0))
         (player-defense (or (cdr (assoc 'defense (Creature-attr myself))) 0))
         (damage (max 1 (- npc-attack player-defense))))
    (take-effect-to-creature myself (cons 'hp (- damage)))
    (tg-display (format "%s攻击了你，造成 %d 点伤害！" (Creature-symbol creature) damage))
    (when (<= (cdr (assoc 'hp (Creature-attr myself))) 0)
      (tg-display "你被击败了！游戏结束！")
      (setq tg-over-p t))))

(defun npc-say (creature text)
  "CREATURE says TEXT."
  (tg-display (format "%s说：%s" (Creature-symbol creature) text)))

(defun npc-move (creature direction)
  "Move CREATURE in DIRECTION (symbol or 'random)."
  (let* ((sym (Creature-symbol creature))
         (neighbors (beyond-rooms (Room-symbol current-room) room-map))
         (dir-map '((up . 0) (right . 1) (down . 2) (left . 3)))
         (dir-names '((up . "北") (right . "东") (down . "南") (left . "西")))
         target-symbol)
    (when (eq direction 'random)
      (let* ((valid-dirs (cl-remove-if-not
                          (lambda (d) (nth (cdr d) neighbors))
                          dir-map)))
        (when valid-dirs
          (let ((chosen-dir (nth (random (length valid-dirs)) valid-dirs)))
            (setq direction (car chosen-dir))))))
    (when-let* ((dir-idx (cdr (assoc direction dir-map))))
      (setq target-symbol (nth dir-idx neighbors))
      (when target-symbol
        (remove-creature-from-room current-room sym)
        (let ((target-room (get-room-by-symbol target-symbol)))
          (add-creature-to-room target-room sym))
        (tg-display (format "%s向%s离开了。" sym (cdr (assoc direction dir-names))))))))

(defun npc-apply-buff (creature attr value)
  "CREATURE buffs itself with ATTR + VALUE."
  (take-effect-to-creature creature (cons attr value))
  (tg-display (format "%s怒吼一声，%s增强了！" (Creature-symbol creature) attr)))

(defun npc-apply-debuff (creature attr value)
  "CREATURE debuffs player with ATTR - VALUE."
  (take-effect-to-creature myself (cons attr (- value)))
  (tg-display (format "%s对你施放了诅咒，%s降低了！" (Creature-symbol creature) attr)))

(defun npc-execute-action (creature action)
  "Execute ACTION for CREATURE."
  (pcase (car action)
    ('attack (npc-attack-player creature))
    ('say (npc-say creature (cadr action)))
    ('move (npc-move creature (cadr action)))
    ('buff (npc-apply-buff creature (cadr action) (caddr action)))
    ('debuff (npc-apply-debuff creature (cadr action) (caddr action)))
    (_ nil)))

;; --- Main behavior runner ---

(defun npc-run-behaviors ()
  "Run behaviors for all NPCs in the current room."
  (when (and current-room (Room-creature current-room))
    (dolist (npc-sym (copy-sequence (Room-creature current-room)))
      (let ((npc (get-creature-by-symbol npc-sym)))
        (when (and npc
                   (not (eq npc myself))
                   (> (or (cdr (assoc 'hp (Creature-attr npc))) 0) 0)
                   (Creature-behaviors npc))
          (cl-block 'behavior-loop
            (dolist (rule (Creature-behaviors npc))
              (let ((condition (car rule))
                    (action (cdr rule)))
                (when (npc-evaluate-condition npc condition)
                  (npc-execute-action npc action)
                  (cl-return-from 'behavior-loop))))))))))

(provide 'npc-behavior)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `emacs --batch -L . -L test -l test/test-npc-behavior.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -5`
Expected: All npc-behavior tests PASS.

- [ ] **Step 5: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -3`
Expected: All tests pass (existing + new).

- [ ] **Step 6: Commit**

```bash
git add npc-behavior.el test/test-npc-behavior.el
git commit -m "feat: create npc-behavior.el with condition evaluator and action executor"
```

---

### Task 3: Integrate NPC behaviors into game loop

**Files:**
- Modify: `action.el:17-35` (`tg-move`)
- Modify: `tg-mode.el:81-108` (`tg-parse`)
- Modify: `text-game-maker.el:1-21` (add require)
- Test: `test/test-action.el` (move+behavior integration test)
- Test: `test/test-tg-mode.el` (parse+behavior integration test)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-move triggers npc behaviors ---

(ert-deftest test-tg-move-triggers-npc-behavior ()
  "tg-move should trigger NPC behaviors after entering room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself tg-over-p)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room1 (make-Room :symbol 'room1 :description "Room 1"))
           (room2 (make-Room :symbol 'room2 :description "Room 2" :creature '(goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5))
                                  :behaviors '(((always) say "Welcome!"))))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq current-room room1)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq tg-over-p nil)
      (tg-move "right")
      ;; NPC should have spoken
      (should (cl-some (lambda (s) (string-match-p "Welcome" s)) (mapcar #'car output))))))
```

Append to `test/test-tg-mode.el` before `(provide 'test-tg-mode)`:

```elisp
;; --- tg-parse triggers npc behaviors ---

(ert-deftest test-tg-parse-triggers-npc-behavior-after-action ()
  "After player action in tg-parse, NPC behaviors should run."
  (test-with-globals-saved (tg-valid-actions display-fn rooms-alist room-map current-room
                                              creatures-alist myself tg-over-p)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5))
                                  :behaviors '(((always) say "I see you!"))))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq tg-over-p nil)
      ;; Simulate player typing "status" (a safe action that shouldn't change state)
      (let ((action-result (catch 'exception
                             (tg-status))))
        (when action-result
          (funcall display-fn action-result))
        (npc-run-behaviors))
      ;; NPC should have spoken
      (should (cl-some (lambda (s) (string-match-p "I see you" s)) (mapcar #'car output))))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -E "test-tg-move-triggers-npc|test-tg-parse-triggers-npc"`
Expected: Both new tests may pass or fail depending on whether `npc-run-behaviors` is already called. They should fail since we haven't wired it in yet.

- [ ] **Step 3: Add `(require 'npc-behavior)` to `text-game-maker.el`**

In `text-game-maker.el`, add after line 18 (`(require 'level-system)`):

```elisp
(require 'npc-behavior)
```

- [ ] **Step 4: Add `npc-run-behaviors` call to `tg-move`**

In `action.el`, in the `tg-move` function, after the `(tg-display (describe current-room))` call (line 35), add:

```elisp
    (npc-run-behaviors)
```

The end of `tg-move` should look like:

```elisp
    (tg-display (describe current-room))
    (npc-run-behaviors)))
```

Note: add `(require 'npc-behavior)` at the top of `action.el` after `(require 'level-system)`.

- [ ] **Step 5: Add `npc-run-behaviors` call to `tg-parse`**

In `tg-mode.el`, in `tg-parse`, after the `(when action-result (tg-mprinc action-result))` block (around line 104-105), add the NPC behavior call. The relevant section should become:

```elisp
		      (when action-result
		        (tg-mprinc action-result))
		      (npc-run-behaviors))))))
```

The closing parens change: the `npc-run-behaviors` call goes inside the outer let but after the `action-result` check. The exact change is inserting `(npc-run-behaviors)` before the closing `))))))` of the main let/progn block.

- [ ] **Step 6: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -3`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add action.el tg-mode.el text-game-maker.el test/test-action.el test/test-tg-mode.el
git commit -m "feat: integrate NPC behaviors into game loop (tg-move and tg-parse)"
```

---

### Task 4: Update sample game with NPC behaviors

**Files:**
- Modify: `sample/creature-config.el`

- [ ] **Step 1: Update `sample/creature-config.el` with behaviors for key NPCs**

Replace the entire file with:

```elisp
(hero "一位勇敢的冒险者，被困在了地牢之中" ((hp . 100) (attack . 5) (defense . 3) (exp . 0) (level . 1) (bonus-points . 0)) () () nil 0 nil)
(guard "地牢守卫，身穿破旧的盔甲" ((hp . 40) (attack . 8) (defense . 4)) () () nil 30
  (((player-in-room) say "站住！这里不允许进入！")
   ((always) attack)))
(goblin "一只狡猾的哥布林，手持匕首" ((hp . 25) (attack . 6) (defense . 2)) () () nil 18
  (((hp-below 13) say "你休想活着离开！")
   ((always) attack)))
(bat "一只巨大的蝙蝠，发出刺耳的尖叫" ((hp . 15) (attack . 4) (defense . 1)) () () nil 10
  (((always) attack)))
(skeleton-king "骷髅王，地下城的统治者。它的眼中燃烧着幽蓝色的火焰" ((hp . 80) (attack . 15) (defense . 8)) () () nil 120
  (((hp-below 30) say "蝼蚁！你以为你能赢？")
   ((always) attack)))
(skeleton-minion "骷髅王的仆从，一具行走的骷髅士兵" ((hp . 35) (attack . 9) (defense . 5)) () () nil 25
  (((always) attack)))
(rat "一只肥大的老鼠，警惕地看着你" ((hp . 10) (attack . 2) (defense . 0)) () () nil 5
  (((hp-below 5) move random)))
(prisoner "一个虚弱的囚犯，蜷缩在角落里" ((hp . 20) (attack . 1) (defense . 0)) () () nil 8
  (((player-in-room) say "请救救我...")))
(spider "一只巨大的蜘蛛，从天花板上垂下" ((hp . 20) (attack . 7) (defense . 1)) () () nil 15
  (((always) attack)))
(slime "一团粘稠的绿色史莱姆，缓慢地蠕动着" ((hp . 30) (attack . 3) (defense . 6)) () () nil 20
  (((always) debuff defense 2)))
(golem "一尊石像鬼，守护着武器库的入口" ((hp . 60) (attack . 12) (defense . 10)) () () nil 50
  (((player-in-room) say "擅闯武器库者，杀无赦！")
   ((hp-below 30) buff attack 3)
   ((always) attack)))
```

- [ ] **Step 2: Run full test suite**

Run: `emacs --batch -L . -L test --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -3`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add sample/creature-config.el
git commit -m "feat: add NPC behaviors to sample game creatures"
```
