# Macro Refactor & Code Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor repeated code patterns into unified functions and macros to reduce duplication.

**Architecture:** 2 general-purpose functions (`tg-track-quest`, `tg-get-entity`) + 2 macros (`tg-run-trigger`, enhanced `tg-defaction`) + ShopConfig struct refactor. The new utilities go into `text-game-maker.el` (or their respective modules) and all call sites are updated.

**Tech Stack:** Emacs Lisp, EIEIO/cl-defstruct, ERT testing

---

### Task 1: tg-track-quest — Merge 4 quest-track-* functions into one

**Files:**
- Modify: `quest-system.el:66-100`
- Modify: `action.el:37,59,73,137` (call sites)
- Modify: `dialog-system.el:96` (call site)
- Modify: `test/test-quest-system.el` (update tests)

- [ ] **Step 1: Write the unified function in quest-system.el**

Replace lines 66-100 with a single function:

```elisp
(defun tg-track-quest (type target-symbol)
  "追踪TYPE类型、目标为TARGET-SYMBOL的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) type)
                 (eq (Quest-target q) target-symbol))
        (quest-update-progress q)))))
```

Delete `quest-track-kill`, `quest-track-collect`, `quest-track-explore`, `quest-track-talk`.

- [ ] **Step 2: Update call sites in action.el**

```
quest-track-kill target    → tg-track-quest 'kill target
quest-track-explore symbol → tg-track-quest 'explore new-room-symbol
quest-track-talk symbol    → tg-track-quest 'talk symbol
quest-track-collect inv    → tg-track-quest 'collect inventory
```

In `action.el`:
- Line 40: `(quest-track-explore new-room-symbol)` → `(tg-track-quest 'explore new-room-symbol)`
- Line 59: `(quest-track-talk symbol)` → `(tg-track-quest 'talk symbol)`
- Line 73: `(quest-track-collect inventory)` → `(tg-track-quest 'collect inventory)`
- Line 137: `(quest-track-kill target)` → `(tg-track-quest 'kill target)`

In `dialog-system.el`:
- Line 96: `(quest-track-talk npc-symbol)` → `(tg-track-quest 'talk npc-symbol)`

- [ ] **Step 3: Update tests in test-quest-system.el**

Replace individual test calls like `(quest-track-kill 'rat)` with `(tg-track-quest 'kill 'rat)`, etc. Search for all `quest-track-` references in test files and update.

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh`
Expected: All 276 tests pass

- [ ] **Step 5: Commit**

```bash
git add quest-system.el action.el dialog-system.el test/test-quest-system.el
git commit -m "refactor: merge 4 quest-track-* functions into tg-track-quest"
```

---

### Task 2: tg-get-entity — Merge 3 get-*-by-symbol functions into one

**Files:**
- Modify: `creature-maker.el:8-10` (get-creature-by-symbol)
- Modify: `room-maker.el:14-16` (get-room-by-symbol)
- Modify: `inventory-maker.el:8-15` (get-inventory-by-symbol)
- Modify: `text-game-maker.el` (add tg-get-entity)
- Modify: `test/test-creature-maker.el`, `test/test-inventory-maker.el` (update tests)

- [ ] **Step 1: Add tg-get-entity to text-game-maker.el**

Add after the `file-content` function (line 7):

```elisp
(defun tg-get-entity (alist symbol &optional no-exception error-fmt)
  "从ALIST中根据SYMBOL获取实体。找不到时抛异常，除非NO-EXCEPTION为t。"
  (let ((object (cdr (assoc symbol alist))))
    (when (and (null object) (null no-exception))
      (throw 'exception (format (or error-fmt "没有定义该%s") symbol)))
    object))
```

- [ ] **Step 2: Replace get-creature-by-symbol in creature-maker.el**

Replace lines 8-10:

```elisp
(defun get-creature-by-symbol (symbol)
  "根据symbol获取creature对象"
  (cdr (assoc symbol creatures-alist)))
```

With:

```elisp
(defun get-creature-by-symbol (symbol)
  "根据symbol获取creature对象"
  (tg-get-entity creatures-alist symbol t))
```

Note: creature version never throws (no error handling in original), so pass `t` for no-exception.

- [ ] **Step 3: Replace get-room-by-symbol in room-maker.el**

Replace lines 14-16:

```elisp
(defun get-room-by-symbol (symbol)
  "根据symbol获取room对象"
  (cdr (assoc symbol rooms-alist)))
```

With:

```elisp
(defun get-room-by-symbol (symbol)
  "根据symbol获取room对象"
  (tg-get-entity rooms-alist symbol t))
```

- [ ] **Step 4: Replace get-inventory-by-symbol in inventory-maker.el**

Replace lines 8-15:

```elisp
(defun get-inventory-by-symbol (symbol &optional noexception)
  "根据symbol获取inventory对象"
  (let (object)
    (setq object (cdr (assoc symbol inventorys-alist)))
    (when (and (null object)
               (null noexception))
      (throw 'exception (format "没有定义该物品[%s]" symbol)))
    object))
```

With:

```elisp
(defun get-inventory-by-symbol (symbol &optional noexception)
  "根据symbol获取inventory对象"
  (tg-get-entity inventorys-alist symbol noexception "没有定义该物品[%s]"))
```

- [ ] **Step 5: Run full test suite**

Run: `bash run-tests.sh`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add text-game-maker.el creature-maker.el room-maker.el inventory-maker.el
git commit -m "refactor: add tg-get-entity, simplify 3 get-*-by-symbol functions"
```

---

### Task 3: tg-run-trigger macro — Unify trigger invocation

**Files:**
- Modify: `action.el:33-34,37-38,55-57,69-71,82-84,95-97,110-112,134-136` (trigger call sites)

- [ ] **Step 1: Add tg-run-trigger macro to action.el**

Add after the `tg-defaction` macro definition (after line 20):

```elisp
(defmacro tg-run-trigger (accessor object)
  "如果ACCESSOR从OBJECT返回的触发器非nil，则调用它。"
  `(when-let* ((trig (,accessor ,object)))
     (funcall trig)))
```

- [ ] **Step 2: Replace trigger calls in action.el**

Replace all `(when-let* ((trig (Foo-trigger obj))) (funcall trig))` patterns:

| Line | Old | New |
|------|-----|-----|
| 33-34 | `(when (Room-out-trigger current-room) (funcall (Room-out-trigger current-room)))` | `(tg-run-trigger Room-out-trigger current-room)` |
| 37-38 | `(when (Room-in-trigger current-room) (funcall (Room-in-trigger current-room)))` | `(tg-run-trigger Room-in-trigger current-room)` |
| 55-57 | `(when-let* ((trig (cond ((Inventory-p object) (Inventory-watch-trigger object)) ((Creature-p object) (Creature-watch-trigger object))))) (funcall trig))` | Keep as-is (this one has cond, not a simple accessor) |
| 69-71 | `(when-let* ((trig (Inventory-take-trigger object))) (funcall trig))` | `(tg-run-trigger Inventory-take-trigger object)` |
| 82-84 | `(when-let* ((trig (Inventory-drop-trigger object))) (funcall trig))` | `(tg-run-trigger Inventory-drop-trigger object)` |
| 95-97 | `(when-let* ((trig (Inventory-use-trigger object))) (funcall trig))` | `(tg-run-trigger Inventory-use-trigger object)` |
| 110-112 | `(when-let* ((trig (Inventory-wear-trigger object))) (funcall trig))` | `(tg-run-trigger Inventory-wear-trigger object)` |
| 134-136 | `(when-let* ((trig (Creature-death-trigger target-creature))) (funcall trig))` | `(tg-run-trigger Creature-death-trigger target-creature)` |

- [ ] **Step 3: Run full test suite**

Run: `bash run-tests.sh`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add action.el
git commit -m "refactor: add tg-run-trigger macro, simplify 7 trigger call sites"
```

---

### Task 4: Enhance tg-defaction — Auto intern string arguments

**Files:**
- Modify: `action.el:14-20` (macro definition)
- Modify: `action.el` (remove all manual `(when (stringp x) (setq x (intern x)))` lines)

- [ ] **Step 1: Enhance tg-defaction macro**

Replace lines 14-20:

```elisp
(defmacro tg-defaction (action args doc-string &rest body)
  (declare (indent defun))
  `(progn
     (add-to-list 'tg-valid-actions ',action)
     (defun ,action ,args
       ,doc-string
       ,@body)))
```

With:

```elisp
(defmacro tg-defaction (action args doc-string &rest body)
  (declare (indent defun))
  (let ((intern-forms
         (delq nil
               (mapcar (lambda (arg)
                         (unless (member arg '(&optional &rest))
                           `(when (stringp ,arg) (setq ,arg (intern ,arg)))))
                       args))))
    `(progn
       (add-to-list 'tg-valid-actions ',action)
       (defun ,action ,args
         ,doc-string
         ,@intern-forms
         ,@body))))
```

- [ ] **Step 2: Remove manual string-to-symbol conversions from all actions**

Remove these lines from action.el:

| Action | Lines to remove |
|--------|----------------|
| `tg-move` | `(when (stringp directory) (setq directory (intern directory)))` |
| `tg-watch` | `(cond ((stringp symbol) (setq symbol (intern symbol))))` |
| `tg-take` | `(cond ((stringp inventory) (setq inventory (intern inventory))))` |
| `tg-drop` | `(cond ((stringp inventory) (setq inventory (intern inventory))))` |
| `tg-use` | `(cond ((stringp inventory) (setq inventory (intern inventory))))` |
| `tg-wear` | `(cond ((stringp equipment) (setq equipment (intern equipment))))` |
| `tg-attack` | `(when (stringp target) (setq target (intern target)))` |
| `tg-upgrade` | `(when (stringp attr) (setq attr (intern attr)))` |
| `tg-talk` | `(when (stringp npc-name) (setq npc-name (intern npc-name)))` |
| `tg-buy` | `(when (stringp item) (setq item (intern item)))` |
| `tg-sell` | `(when (stringp item) (setq item (intern item)))` |

Note: `tg-help` uses `(intern (format "tg-%s" action))` — this is NOT a plain intern, keep it as-is.

- [ ] **Step 3: Run full test suite**

Run: `bash run-tests.sh`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add action.el
git commit -m "refactor: tg-defaction auto-interns string arguments, remove 11 manual conversions"
```

---

### Task 5: ShopConfig struct refactor

**Files:**
- Modify: `shop-system.el` (full refactor)
- Modify: `test/test-shop-system.el` (update accessor calls)

- [ ] **Step 1: Add ShopConfig struct and update build-shop-entry in shop-system.el**

Add after `(defvar shop-alist nil ...)`:

```elisp
(cl-defstruct ShopConfig
  "ShopConfig structure"
  (sell-rate 0.5 :documentation "卖出折扣率")
  (goods nil :documentation "商品列表 ((item-symbol . price) ...)"))
```

Replace `build-shop-entry` (lines 17-23):

```elisp
(defun build-shop-entry (shop-entity)
  "根据SHOP-ENTITY创建商店条目."
  (cl-multiple-value-bind (npc-symbol sell-rate goods) shop-entity
    (cons npc-symbol (make-ShopConfig :sell-rate sell-rate :goods goods))))
```

- [ ] **Step 2: Update shop-init to use file-content**

Replace `shop-init` (lines 25-31):

```elisp
(defun shop-init (config-file)
  "从CONFIG-FILE加载商品配置."
  (let ((shop-entities (read-from-whole-string (file-content config-file))))
    (setq shop-alist (mapcar #'build-shop-entry shop-entities))))
```

- [ ] **Step 3: Update helper functions to use struct accessors**

Replace `shop-get-goods`:

```elisp
(defun shop-get-goods (npc-symbol)
  "返回NPC-SYMBOL对应的商品列表."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry (ShopConfig-goods (cdr entry)))))
```

Replace `shop-get-sell-rate`:

```elisp
(defun shop-get-sell-rate (npc-symbol)
  "返回NPC-SYMBOL对应的卖出折扣率."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry (ShopConfig-sell-rate (cdr entry)))))
```

Replace `shop-remove-item`:

```elisp
(defun shop-remove-item (npc-symbol item-symbol)
  "从NPC-SYMBOL的商品列表中移除ITEM-SYMBOL."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (setf (ShopConfig-goods (cdr entry))
            (assq-delete-all item-symbol (ShopConfig-goods (cdr entry)))))))
```

Replace `shop-add-item`:

```elisp
(defun shop-add-item (npc-symbol item-symbol price)
  "向NPC-SYMBOL的商品列表中添加ITEM-SYMBOL."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (push (cons item-symbol price) (ShopConfig-goods (cdr entry))))))
```

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add shop-system.el
git commit -m "refactor: ShopConfig struct replaces raw cons pairs in shop-alist"
```

---

### Task 6: tg-def-config-builder macro — Unify build + init pattern

**Files:**
- Modify: `text-game-maker.el` (add macro + require cl-lib)
- Modify: `room-maker.el:39-47` (use macro)
- Modify: `inventory-maker.el:36-44` (use macro)
- Modify: `quest-system.el:25-36` (use macro)

- [ ] **Step 1: Add tg-def-config-builder macro to text-game-maker.el**

IMPORTANT: This macro MUST be placed BEFORE `(require 'tg-mode)` (line 8), because room-maker.el is loaded transitively via tg-mode → action → room-maker, and it needs the macro at load time. Also add `(require 'cl-lib)` at the top since the macro uses `cl-mapcan`.

Insert at the top of `text-game-maker.el` (after the `;;; file header` comment, before `file-content`):

```elisp
(require 'cl-lib)

(defmacro tg-def-config-builder (name alist-var struct-name fields)
  "生成 build-NAME 和 NAME-init 函数。
NAME: 模块名 (如 room, inventory, quest)
ALIST-VAR: 存储结果的 alist 变量 (如 rooms-alist)
STRUCT-NAME: cl-defstruct 名 (如 Room, Inventory, Quest)
FIELDS: 解构和构造用的字段名列表"
  (let ((build-fn (intern (format "build-%s" name)))
        (init-fn (intern (format "%s-init" name)))
        (entity-var (intern (format "%s-entity" name))))
    `(progn
       (defun ,build-fn (,entity-var)
         ,(format "根据%s创建%s对象." entity-var struct-name)
         (cl-multiple-value-bind ,fields ,entity-var
           (cons (car ,entity-var)
                 (,struct-name ,@(cl-mapcan (lambda (f) (list (intern (format ":%s" f)) f)) fields)))))
       (defun ,init-fn (config-file)
         ,(format "从CONFIG-FILE加载%s配置." name)
         (let ((entities (read-from-whole-string (file-content config-file))))
           (setq ,alist-var (mapcar #',build-fn entities)))))))
```

- [ ] **Step 2: Replace build-room + build-rooms in room-maker.el**

Delete lines 39-47 (`build-room` and `build-rooms`). Add:

```elisp
(tg-def-config-builder room rooms-alist Room (symbol description inventory creature))
```

Note: must be placed AFTER the `(cl-defstruct Room ...)` definition (after line 26).

- [ ] **Step 3: Replace build-inventory + build-inventorys in inventory-maker.el**

Delete lines 36-44 (`build-inventory` and `build-inventorys`). Add after `(cl-defstruct Inventory ...)`:

```elisp
(tg-def-config-builder inventory inventorys-alist Inventory (symbol description type effects))
```

- [ ] **Step 4: Replace build-quest + quest-init in quest-system.el**

Delete lines 25-36 (`build-quest` and `quest-init`). Add after `(cl-defstruct Quest ...)`:

```elisp
(tg-def-config-builder quest quests-alist Quest (symbol description type target count rewards status description-complete))
```

- [ ] **Step 5: Handle build-creature specially (has optional shopkeeper field)**

`build-creature` has extra logic for optional 9th field `shopkeeper`. This does NOT fit the macro pattern. Keep `build-creature` and `build-creatures` as-is, only refactor the `build-creatures` → use `file-content` directly (it already does).

No changes needed for `creature-maker.el` in this task.

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add text-game-maker.el room-maker.el inventory-maker.el quest-system.el
git commit -m "refactor: tg-def-config-builder macro unifies build+init for room/inventory/quest"
```
