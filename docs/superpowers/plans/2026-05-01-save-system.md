# Save/Load System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete game save/load functionality that serializes the full game snapshot to an Elisp data file and restores it.

**Architecture:** New module `save-system.el` with serialization functions (creature → alist, room → alist) and a restore flow that re-initializes config files then overlays saved state. Two new `tg-defaction` commands: `save` and `load`. A global `tg-config-dir` variable tracks the config directory for re-initialization on load.

**Tech Stack:** Emacs Lisp, ERT testing, existing `cl-defstruct` (Creature, Room), `file-content` / `read-from-whole-string` for file I/O.

---

### Task 1: Create `save-system.el` — serialization and file I/O

**Files:**
- Create: `save-system.el`
- Create: `test/test-save-system.el`
- Modify: `run-tests.sh` (add `(require 'test-save-system)`)
- Modify: `text-game-maker.el:19` (add `(require 'save-system)`)

- [ ] **Step 1: Write the failing tests**

Create `test/test-save-system.el`:

```elisp
;;; test-save-system.el --- Tests for save-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'save-system)

;; --- tg-serialize-creature ---

(ert-deftest test-serialize-creature-full ()
  "tg-serialize-creature should serialize all serializable fields."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin"
                            :attr '((hp . 25) (attack . 6))
                            :inventory '(potion)
                            :equipment '(sword)
                            :behaviors '(((always) attack)))))
    (let ((data (tg-serialize-creature cr)))
      (should (equal (cdr (assoc 'symbol data)) 'goblin))
      (should (equal (cdr (assoc 'attr data)) '((hp . 25) (attack . 6))))
      (should (equal (cdr (assoc 'inventory data)) '(potion)))
      (should (equal (cdr (assoc 'equipment data)) '(sword)))
      (should (equal (cdr (assoc 'behaviors data)) '(((always) attack)))))))

(ert-deftest test-serialize-creature-empty-lists ()
  "tg-serialize-creature should handle empty inventory/equipment."
  (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
    (let ((data (tg-serialize-creature cr)))
      (should (null (cdr (assoc 'inventory data))))
      (should (null (cdr (assoc 'equipment data))))
      (should (null (cdr (assoc 'behaviors data)))))))

;; --- tg-serialize-room ---

(ert-deftest test-serialize-room-with-items-and-creatures ()
  "tg-serialize-room should serialize inventory and creature list."
  (let ((room (make-Room :symbol 'hall :description "A hall"
                          :inventory '(torch key) :creature '(goblin bat))))
    (let ((data (tg-serialize-room room)))
      (should (equal (cdr (assoc 'inventory data)) '(torch key)))
      (should (equal (cdr (assoc 'creature data)) '(goblin bat))))))

(ert-deftest test-serialize-room-empty ()
  "tg-serialize-room should handle empty room."
  (let ((room (make-Room :symbol 'empty :description "Empty room")))
    (let ((data (tg-serialize-room room)))
      (should (null (cdr (assoc 'inventory data))))
      (should (null (cdr (assoc 'creature data)))))))

;; --- tg-save-game ---

(ert-deftest test-save-game-creates-file ()
  "tg-save-game should create a save file."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself display-fn)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(potion) :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25))))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero hero)))
      (setq myself hero)
      (tg-save-game save-file)
      (should (file-exists-p save-file))
      (delete-file save-file))))

(ert-deftest test-save-game-file-content ()
  "tg-save-game should write correct alist data."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself display-fn)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(torch) :creature '(hero)))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword) :equipment '(shield)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero hero)))
      (setq myself hero)
      (unwind-protect
          (progn
            (tg-save-game save-file)
            (let* ((content (file-content save-file))
                   (data (read content)))
              ;; Check player data
              (should (equal (cdr (assoc 'current-room data)) 'room1))
              (should (equal (cdr (assoc 'symbol (cdr (assoc 'player data)))) 'hero))
              (should (equal (cdr (assoc 'inventory (cdr (assoc 'player data)))) '(sword)))
              ;; Check rooms data
              (let ((room-data (cdr (assoc 'room1 (cdr (assoc 'rooms data))))))
                (should (equal (cdr (assoc 'inventory room-data)) '(torch))))))
        (delete-file save-file)))))

;; --- tg-load-game round-trip ---

(ert-deftest test-save-load-round-trip ()
  "Saving and loading should preserve game state."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself display-fn
                                        tg-config-dir tg-over-p)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(torch) :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6)) :inventory '() :equipment '()))
           (hero (make-Creature :symbol 'hero :attr '((hp . 85) (attack . 10)) :inventory '(sword) :equipment '(shield)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero hero)))
      (setq myself hero)
      (setq tg-over-p nil)
      (setq tg-config-dir nil)
      (unwind-protect
          (progn
            (tg-save-game save-file)
            ;; Modify state to prove load restores it
            (setf (Creature-attr myself) '((hp . 1)))
            (setf (Creature-inventory myself) nil)
            ;; Load
            (tg-load-game save-file)
            ;; Verify restored state
            (should (= (cdr (assoc 'hp (Creature-attr myself))) 85))
            (should (equal (Creature-inventory myself) '(sword)))
            (should (equal (Creature-equipment myself) '(shield)))
            (should (equal (Room-symbol current-room) 'room1)))
        (when (file-exists-p save-file)
          (delete-file save-file))))))

;; --- Error handling ---

(ert-deftest test-load-nonexistent-file ()
  "tg-load-game should throw exception for nonexistent file."
  (test-with-globals-saved (display-fn)
    (setq display-fn #'ignore)
    (should (equal (catch 'exception (tg-load-game "/nonexistent/path/save.sav"))
                   "存档文件不存在"))))

(provide 'test-save-system)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-save-system.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | tail -5`
Expected: Tests FAIL (module doesn't exist yet).

- [ ] **Step 3: Create `save-system.el`**

```elisp
;;; save-system.el --- Save/Load system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)

(defvar tg-config-dir nil
  "游戏配置文件目录路径，用于存档恢复时重新加载配置。")

;; --- Serialization ---

(defun tg-serialize-creature (creature)
  "Serialize CREATURE to an alist (excluding triggers)."
  `((symbol . ,(Creature-symbol creature))
    (attr . ,(copy-tree (Creature-attr creature)))
    (inventory . ,(copy-sequence (Creature-inventory creature)))
    (equipment . ,(copy-sequence (Creature-equipment creature)))
    (behaviors . ,(copy-tree (Creature-behaviors creature)))))

(defun tg-serialize-room (room)
  "Serialize ROOM runtime state to an alist (excluding triggers)."
  `((inventory . ,(copy-sequence (Room-inventory room)))
    (creature . ,(copy-sequence (Room-creature room)))))

;; --- Save ---

(defun tg-save-game (filepath)
  "Save complete game snapshot to FILEPATH."
  (let ((save-data
         `((player . ,(tg-serialize-creature myself))
           (current-room . ,(Room-symbol current-room))
           (rooms . ,(mapcar (lambda (pair)
                               (cons (car pair) (tg-serialize-room (cdr pair))))
                             rooms-alist))
           (creatures . ,(mapcar (lambda (pair)
                                   (cons (car pair) (tg-serialize-creature (cdr pair))))
                                 creatures-alist)))))
    (let ((dir (file-name-directory filepath)))
      (when (and dir (not (file-directory-p dir)))
        (make-directory dir t)))
    (with-temp-file filepath
      (let (print-level print-length)
        (prin1 save-data (current-buffer))))
    (tg-display (format "游戏已保存到 %s" filepath))))

;; --- Restore ---

(defun tg-restore-game-state (data)
  "Restore game state from save DATA alist."
  ;; Restore player
  (let* ((player-data (cdr (assoc 'player data)))
         (player-symbol (cdr (assoc 'symbol player-data))))
    (setq myself (get-creature-by-symbol player-symbol))
    (when myself
      (setf (Creature-attr myself) (cdr (assoc 'attr player-data)))
      (setf (Creature-inventory myself) (cdr (assoc 'inventory player-data)))
      (setf (Creature-equipment myself) (cdr (assoc 'equipment player-data)))
      (setf (Creature-behaviors myself) (cdr (assoc 'behaviors player-data)))))
  ;; Restore current room
  (setq current-room (get-room-by-symbol (cdr (assoc 'current-room data))))
  ;; Restore rooms runtime state
  (let ((rooms-data (cdr (assoc 'rooms data))))
    (dolist (room-entry rooms-data)
      (let ((room (get-room-by-symbol (car room-entry)))
            (room-state (cdr room-entry)))
        (when room
          (setf (Room-inventory room) (cdr (assoc 'inventory room-state)))
          (setf (Room-creature room) (cdr (assoc 'creature room-state)))))))
  ;; Restore creatures runtime state
  (let ((creatures-data (cdr (assoc 'creatures data))))
    (dolist (cr-entry creatures-data)
      (let ((cr (get-creature-by-symbol (car cr-entry)))
            (cr-state (cdr cr-entry)))
        (when cr
          (setf (Creature-attr cr) (cdr (assoc 'attr cr-state)))
          (setf (Creature-inventory cr) (cdr (assoc 'inventory cr-state)))
          (setf (Creature-equipment cr) (cdr (assoc 'equipment cr-state)))
          (setf (Creature-behaviors cr) (cdr (assoc 'behaviors cr-state))))))))

(defun tg-load-game (filepath)
  "Load game state from FILEPATH."
  (unless (file-exists-p filepath)
    (throw 'exception "存档文件不存在"))
  (let ((data (with-temp-buffer
                (insert-file-contents filepath)
                (goto-char (point-min))
                (read (current-buffer)))))
    (when tg-config-dir
      ;; Re-initialize from config files to restore triggers
      (map-init (expand-file-name "room-config.el" tg-config-dir)
                (expand-file-name "map-config.el" tg-config-dir))
      (inventorys-init (expand-file-name "inventory-config.el" tg-config-dir))
      (creatures-init (expand-file-name "creature-config.el" tg-config-dir))
      (when (file-exists-p (expand-file-name "level-config.el" tg-config-dir))
        (level-init (expand-file-name "level-config.el" tg-config-dir))))
    (tg-restore-game-state data)
    (setq tg-over-p nil)
    (tg-display (format "游戏已从 %s 恢复" filepath))
    (tg-display (describe current-room))))

(provide 'save-system)
```

- [ ] **Step 4: Add `(require 'save-system)` to `text-game-maker.el`**

After line 19 (`(require 'npc-behavior)`), add:

```elisp
(require 'save-system)
```

- [ ] **Step 5: Add `(require 'test-save-system)` to `run-tests.sh`**

After line 22 (`(require 'test-npc-behavior)`), add:

```elisp
    (require 'test-save-system)
```

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (184 existing + 7 new = 191).

- [ ] **Step 7: Commit**

```bash
git add save-system.el test/test-save-system.el text-game-maker.el run-tests.sh
git commit -m "feat: create save-system.el with serialization and save/load

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add `save` and `load` game commands

**Files:**
- Modify: `action.el:177-180` (before `(provide 'action)`)
- Test: `test/test-action.el`

- [ ] **Step 1: Write the failing tests**

Append to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- tg-save ---

(ert-deftest test-tg-save-creates-save-file ()
  "tg-save should create a save file in saves directory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself tg-config-dir)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :creature '(hero)))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100))))
           (output nil)
           (tmp-dir (make-temp-file "tg-save-dir-" t)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero hero)))
      (setq myself hero)
      (setq tg-config-dir tmp-dir)
      (tg-save "test-slot")
      (should (file-exists-p (expand-file-name "saves/test-slot.sav" tmp-dir)))
      (delete-directory tmp-dir t))))

;; --- tg-load ---

(ert-deftest test-tg-load-restores-state ()
  "tg-load should restore game state from save."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself tg-config-dir tg-over-p)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :creature '(hero)))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword)))
           (output nil)
           (tmp-dir (make-temp-file "tg-save-dir-" t)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero hero)))
      (setq myself hero)
      (setq tg-config-dir tmp-dir)
      (setq tg-over-p nil)
      (unwind-protect
          (progn
            (tg-save "test-slot")
            ;; Modify state
            (setf (Creature-attr myself) '((hp . 1)))
            (setq tg-over-p t)
            ;; Load
            (tg-load "test-slot")
            ;; Verify
            (should (= (cdr (assoc 'hp (Creature-attr myself))) 100))
            (should (equal (Creature-inventory myself) '(sword)))
            (should-not tg-over-p))
        (delete-directory tmp-dir t)))))

(ert-deftest test-tg-load-nonexistent-throws ()
  "tg-load should throw for nonexistent save."
  (test-with-globals-saved (tg-valid-actions display-fn myself tg-config-dir)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((hero (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq display-fn #'ignore)
      (setq myself hero)
      (setq tg-config-dir "/tmp/nonexistent-tg-dir")
      (should (equal (catch 'exception (tg-load "no-such-save"))
                     "存档文件不存在")))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-action.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -E "test-tg-save|test-tg-load"`
Expected: New tests FAIL (tg-save / tg-load commands don't exist yet).

- [ ] **Step 3: Add `tg-save` and `tg-load` actions to `action.el`**

Add before `(tg-defaction tg-quit ...)` (around line 177) in `action.el`:

```elisp
(tg-defaction tg-save (name)
  "使用'save <名称>'保存游戏到saves/<名称>.sav"
  (unless name
    (throw 'exception "请输入存档名称"))
  (let ((save-dir (if tg-config-dir
                      (expand-file-name "saves" tg-config-dir)
                    "saves"))
        (save-path nil))
    (setq save-path (expand-file-name (concat name ".sav") save-dir))
    (tg-save-game save-path)))

(tg-defaction tg-load (name)
  "使用'load <名称>'从saves/<名称>.sav恢复游戏"
  (unless name
    (throw 'exception "请输入存档名称"))
  (let ((save-dir (if tg-config-dir
                      (expand-file-name "saves" tg-config-dir)
                    "saves"))
        (save-path nil))
    (setq save-path (expand-file-name (concat name ".sav") save-dir))
    (tg-load-game save-path)))

```

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (191 existing + 3 new = 194).

- [ ] **Step 5: Commit**

```bash
git add action.el test/test-action.el
git commit -m "feat: add save and load game commands

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Save config directory on initialization and update sample game

**Files:**
- Modify: `room-maker.el:116-120` (`map-init`)
- Modify: `sample/sample-game.el`

- [ ] **Step 1: Update `map-init` to save config directory**

In `room-maker.el`, change `map-init` to save the config directory:

```elisp
(defun map-init(room-config-file room-map-config-file)
  "初始化函数,生成room对象,组装map"
  (setq tg-config-dir (file-name-directory room-config-file))
  (setq rooms-alist (build-rooms room-config-file))
  (setq room-map (build-room-map room-map-config-file))
  (setq current-room (get-room-by-symbol (caar rooms-alist))))
```

Note: `tg-config-dir` is defined in `save-system.el`. Since `room-maker.el` is loaded before `save-system.el`, we need a `defvar` in `room-maker.el` as a forward declaration. Add before `map-init`:

```elisp
(defvar tg-config-dir nil
  "游戏配置文件目录路径，用于存档恢复时重新加载配置。")
```

And remove the `(defvar tg-config-dir ...)` line from `save-system.el` to avoid duplicate definition warnings (keep it only in `room-maker.el` since that's where `map-init` sets it).

- [ ] **Step 2: Update `sample/sample-game.el` to hint about save/load**

In `sample/sample-game.el`, add a save/load hint to the intro text. After the upgrade hint line, add:

```elisp
    (tg-display "存档提示: 使用 save <名称> 保存进度，load <名称> 恢复进度！")
```

- [ ] **Step 3: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All 194 tests pass.

- [ ] **Step 4: Commit**

```bash
git add room-maker.el save-system.el sample/sample-game.el
git commit -m "feat: save config directory on init for save/load support

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
