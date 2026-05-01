# Shop System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add NPC-based shop/trading system with gold currency, buy/sell commands, and per-merchant configurable sell-rate.

**Architecture:** New `shop-system.el` module for shop config loading and trade logic. Creature struct extended with `shopkeeper` field. Three new `tg-defaction` commands (shop/buy/sell) in `action.el`. Save-system extended to persist `player-gold` and `shop-alist`.

**Tech Stack:** Emacs Lisp, ERT testing, `cl-defstruct`, `tg-defaction` macro.

---

### Task 1: Add shopkeeper field to Creature struct

**Files:**
- Modify: `creature-maker.el` (add `shopkeeper` field, update `build-creature`)
- Modify: `test/test-creature-maker.el` (add shopkeeper tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-creature-maker.el` before `(provide 'test-creature-maker)`:

```elisp
;; --- Shopkeeper ---

(ert-deftest test-creature-shopkeeper-default-nil ()
  "Creature shopkeeper should default to nil."
  (let ((c (make-Creature :symbol 'goblin :description "A goblin")))
    (should-not (Creature-shopkeeper c))))

(ert-deftest test-creature-shopkeeper-set ()
  "Creature shopkeeper can be set to t."
  (let ((c (make-Creature :symbol 'merchant :description "A merchant" :shopkeeper t)))
    (should (Creature-shopkeeper c))))

(ert-deftest test-build-creature-with-shopkeeper ()
  "build-creature should parse 9th element as shopkeeper."
  (test-with-globals-saved (creatures-alist)
    (setq creatures-alist nil)
    (let ((result (build-creature '(merchant "商人" ((hp . 30)) () () nil 0 nil t))))
      (should (Creature-shopkeeper (cdr result))))))

(ert-deftest test-build-creature-without-shopkeeper ()
  "build-creature should default shopkeeper to nil for 8-element config."
  (test-with-globals-saved (creatures-alist)
    (setq creatures-alist nil)
    (let ((result (build-creature '(goblin "哥布林" ((hp . 25)) () () nil 10 nil))))
      (should-not (Creature-shopkeeper (cdr result))))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-creature-maker.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: Some tests FAIL (shopkeeper field doesn't exist yet).

- [ ] **Step 3: Implement shopkeeper field**

In `creature-maker.el`, add `shopkeeper` field to the `cl-defstruct Creature` (after `behaviors`):

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
  (exp-reward nil :documentation "击败该CREATURE获得的经验值")
  (behaviors nil :documentation "NPC主动行为规则列表")
  (shopkeeper nil :documentation "是否为商人"))
```

Update `build-creature` to handle optional 9th element:

```elisp
(defun build-creature (creature-entity)
  "根据creature-entity创建creature,并将creature存入creatures-alist中"
  (let* ((len (length creature-entity))
         (shopkeeper (when (> len 8) (nth 8 creature-entity))))
    (cl-multiple-value-bind (symbol description attr inventory equipment death-trigger exp-reward behaviors) creature-entity
      (cons symbol (make-Creature :symbol symbol :description description :inventory inventory
                                  :equipment equipment :attr attr :death-trigger death-trigger
                                  :exp-reward exp-reward :behaviors behaviors
                                  :shopkeeper shopkeeper)))))
```

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All existing tests still pass (244) + 4 new = 248.

- [ ] **Step 5: Commit**

```bash
git add creature-maker.el test/test-creature-maker.el
git commit -m "feat: add shopkeeper field to Creature struct

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Create shop-system.el with config loading and helpers

**Files:**
- Create: `shop-system.el`
- Create: `test/test-shop-system.el`

- [ ] **Step 1: Write the failing tests**

Create `test/test-shop-system.el`:

```elisp
;;; test-shop-system.el --- Tests for shop-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'shop-system)

;; --- player-gold ---

(ert-deftest test-player-gold-default ()
  "player-gold should default to 0."
  (test-with-globals-saved (player-gold)
    (setq player-gold 0)
    (should (= player-gold 0))))

;; --- shop-init ---

(ert-deftest test-shop-init-parses-config ()
  "shop-init should parse shop config file."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (test-with-temp-file "(goblin-merchant 0.3 ((bread 10) (health-potion 25)))"
      (shop-init temp-file)
      (let ((entry (cdr (assoc 'goblin-merchant shop-alist))))
        (should entry)
        (should (= (car entry) 0.3))
        (should (equal (cdr entry) '((bread 10) (health-potion 25))))))))

(ert-deftest test-shop-init-multiple-merchants ()
  "shop-init should handle multiple merchants."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (test-with-temp-file "(merchant-a 0.5 ((sword 30)))
(merchant-b 0.3 ((bread 10)))"
      (shop-init temp-file)
      (should (= (length shop-alist) 2)))))

;; --- shop helper functions ---

(ert-deftest test-get-shopkeeper-in-room ()
  "shop-get-shopkeeper should return first shopkeeper creature in room."
  (test-with-globals-saved (current-room rooms-alist room-map creatures-alist)
    (setq creatures-alist nil)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (push (cons 'goblin (make-Creature :symbol 'goblin :shopkeeper nil)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market"
                                   :creature '(merchant goblin)))
    (let ((sk (shop-get-shopkeeper)))
      (should sk)
      (should (eq (Creature-symbol sk) 'merchant)))))

(ert-deftest test-get-shopkeeper-no-shopkeeper ()
  "shop-get-shopkeeper should return nil when no shopkeeper in room."
  (test-with-globals-saved (current-room rooms-alist room-map creatures-alist)
    (setq creatures-alist nil)
    (push (cons 'goblin (make-Creature :symbol 'goblin)) creatures-alist)
    (setq current-room (make-Room :symbol 'cave :description "Cave"
                                   :creature '(goblin)))
    (should-not (shop-get-shopkeeper))))

(ert-deftest test-get-shopkeeper-empty-room ()
  "shop-get-shopkeeper should return nil for empty room."
  (test-with-globals-saved (current-room rooms-alist room-map)
    (setq current-room (make-Room :symbol 'empty :description "Empty room"
                                   :creature nil))
    (should-not (shop-get-shopkeeper))))

(ert-deftest test-shop-get-goods ()
  "shop-get-goods should return goods list for a merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword 30) (bread 10))))))
    (should (equal (shop-get-goods 'merchant) '((sword 30) (bread 10))))))

(ert-deftest test-shop-get-goods-unknown ()
  "shop-get-goods should return nil for unknown merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (should-not (shop-get-goods 'unknown))))

(ert-deftest test-shop-get-sell-rate ()
  "shop-get-sell-rate should return sell rate for merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.3 . ((sword 30))))))
    (should (= (shop-get-sell-rate 'merchant) 0.3))))

(ert-deftest test-shop-get-item-price ()
  "shop-get-item-price should return price of item in merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword 30) (bread 10))))))
    (should (= (shop-get-item-price 'merchant 'sword) 30))
    (should (= (shop-get-item-price 'merchant 'bread) 10))
    (should-not (shop-get-item-price 'merchant 'unknown))))

(ert-deftest test-shop-remove-item ()
  "shop-remove-item should remove item from merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword 30) (bread 10))))))
    (shop-remove-item 'merchant 'sword)
    (should (equal (shop-get-goods 'merchant) '((bread 10))))))

(ert-deftest test-shop-add-item ()
  "shop-add-item should add item to merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword 30))))))
    (shop-add-item 'merchant 'bread 10)
    (should (member '(bread 10) (shop-get-goods 'merchant)))))

(provide 'test-shop-system)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-shop-system.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: All tests FAIL (file doesn't exist).

- [ ] **Step 3: Implement shop-system.el**

Create `shop-system.el`:

```elisp
;;; shop-system.el --- Shop/trading system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)

;; --- Variables ---

(defvar player-gold 0
  "玩家持有金币数量")

(defvar shop-alist nil
  "商品列表缓存，格式 ((npc-symbol . (sell-rate . ((item . price) ...))) ...)")

;; --- Config loading ---

(defun build-shop-entry (shop-entity)
  "根据SHOP-ENTITY创建商店条目.
SHOP-ENTITY 格式: (npc-symbol sell-rate ((item-symbol price) ...))"
  (let ((npc-symbol (nth 0 shop-entity))
        (sell-rate (nth 1 shop-entity))
        (goods (nth 2 shop-entity)))
    (cons npc-symbol (cons sell-rate goods))))

(defun shop-init (config-file)
  "从CONFIG-FILE加载商品配置."
  (let ((shop-entities (read-from-whole-string (file-content config-file))))
    (setq shop-alist (mapcar #'build-shop-entry shop-entities))))

;; --- Helpers ---

(defun shop-get-shopkeeper ()
  "返回当前房间中的第一个商人Creature，无则返回nil."
  (when (and current-room (Room-creature current-room))
    (cl-dolist (sym (Room-creature current-room))
      (let ((cr (get-creature-by-symbol sym)))
        (when (and cr (Creature-shopkeeper cr))
          (cl-return cr))))))

(defun shop-get-goods (npc-symbol)
  "返回NPC-SYMBOL对应的商品列表."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry (cdr entry))))

(defun shop-get-sell-rate (npc-symbol)
  "返回NPC-SYMBOL对应的卖出折扣率."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry (car entry))))

(defun shop-get-item-price (npc-symbol item-symbol)
  "返回NPC-SYNAME的商品列表中ITEM-SYMBOL的价格."
  (let* ((goods (shop-get-goods npc-symbol))
         (item (assoc item-symbol goods)))
    (when item (cdr item))))

(defun shop-remove-item (npc-symbol item-symbol)
  "从NPC-SYMBOL的商品列表中移除ITEM-SYMBOL."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (setf (cdr entry) (assq-delete-all item-symbol (cdr entry))))))

(defun shop-add-item (npc-symbol item-symbol price)
  "向NPC-SYMBOL的商品列表中添加ITEM-SYMBOL，价格为PRICE."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (setf (cdr entry) (append (cdr entry) (list (cons item-symbol price)))))))

(provide 'shop-system)
```

- [ ] **Step 4: Register test in run-tests.sh**

Add `(require 'test-shop-system)` to the `--eval` block in `run-tests.sh`, after `(require 'test-dialog-system)`:

```elisp
    (require 'test-shop-system)
```

- [ ] **Step 5: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (248 existing + 12 new = 260).

- [ ] **Step 6: Commit**

```bash
git add shop-system.el test/test-shop-system.el run-tests.sh
git commit -m "feat: create shop-system.el with config loading and helpers

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add buy/sell/shop commands

**Files:**
- Modify: `action.el` (add tg-buy, tg-sell, tg-shop, require shop-system)
- Modify: `test/test-action.el` (add buy/sell/shop tests)
- Modify: `text-game-maker.el` (add require shop-system)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-action.el` before `(provide 'test-action)`:

```elisp
;; --- Shop commands ---

(ert-deftest test-tg-shop-shows-goods ()
  "tg-shop should display merchant's goods."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist shop-alist display-fn player-gold)
    (setq tg-valid-actions '(tg-shop))
    (setq player-gold 100)
    (setq creatures-alist nil)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((bread . 10) (sword . 50))))))
    (let (output)
      (setq display-fn (lambda (&rest args) (push (car args) output)))
      (tg-shop)
      (let ((all-output (mapconcat #'identity (nreverse output) " ")))
        (should (string-match-p "bread" all-output))
        (should (string-match-p "sword" all-output))
        (should (string-match-p "10" all-output))
        (should (string-match-p "50" all-output))))))

(ert-deftest test-tg-shop-no-merchant ()
  "tg-shop should show message when no merchant in room."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist shop-alist display-fn)
    (setq tg-valid-actions '(tg-shop))
    (setq creatures-alist nil)
    (push (cons 'goblin (make-Creature :symbol 'goblin)) creatures-alist)
    (setq current-room (make-Room :symbol 'cave :description "Cave" :creature '(goblin)))
    (setq shop-alist nil)
    (let (output)
      (setq display-fn (lambda (&rest args) (push (car args) output)))
      (tg-shop)
      (should (cl-some (lambda (s) (string-match-p "没有商店" s)) output)))))

(ert-deftest test-tg-buy-success ()
  "tg-buy should purchase item and deduct gold."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist display-fn player-gold myself)
    (setq tg-valid-actions '(tg-buy))
    (setq player-gold 100)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory nil))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((bread . 10))))))
    (let (output)
      (setq display-fn (lambda (&rest args) (push (car args) output)))
      (tg-buy "bread")
      (should (= player-gold 90))
      (should (member 'bread (Creature-inventory myself)))
      (should (cl-some (lambda (s) (string-match-p "购买" s)) output)))))

(ert-deftest test-tg-buy-not-enough-gold ()
  "tg-buy should fail when not enough gold."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist player-gold myself)
    (setq tg-valid-actions '(tg-buy))
    (setq player-gold 5)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory nil))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((sword . 50))))))
    (let ((result (catch 'exception (tg-buy "sword"))))
      (should (stringp result))
      (should (string-match-p "金币不足" result)))))

(ert-deftest test-tg-buy-item-not-in-shop ()
  "tg-buy should fail when item not in merchant's goods."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist player-gold myself)
    (setq tg-valid-actions '(tg-buy))
    (setq player-gold 100)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory nil))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((bread . 10))))))
    (let ((result (catch 'exception (tg-buy "sword"))))
      (should (stringp result))
      (should (string-match-p "没有这个商品" result)))))

(ert-deftest test-tg-sell-success ()
  "tg-sell should sell item and add gold based on sell-rate."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist display-fn player-gold myself)
    (setq tg-valid-actions '(tg-sell))
    (setq player-gold 0)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(bread)))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.3 . ((sword . 50))))))
    (let (output)
      (setq display-fn (lambda (&rest args) (push (car args) output)))
      ;; bread is not in merchant's goods, so we need to check fallback price
      ;; For items not in merchant's goods, use the item's own price or a default
      (tg-sell "bread")
      ;; sell-rate is 0.3, bread has no price in shop, should use default 5
      ;; Actually, selling an item not in merchant's list: price comes from the item's shop price if known, or fallback
      ;; Since bread is not in merchant's goods and has no price, the sell uses fallback
      (should-not (member 'bread (Creature-inventory myself)))
      (should (cl-some (lambda (s) (string-match-p "卖出" s)) output)))))

(ert-deftest test-tg-sell-with-known-price ()
  "tg-sell should calculate sell price from item's shop price × sell-rate."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist display-fn player-gold myself)
    (setq tg-valid-actions '(tg-sell))
    (setq player-gold 0)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword)))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((sword . 50))))))
    (let (output)
      (setq display-fn (lambda (&rest args) (push (car args) output)))
      (tg-sell "sword")
      (should (= player-gold 25))  ;; 50 × 0.5 = 25
      (should-not (member 'sword (Creature-inventory myself))))))

(ert-deftest test-tg-sell-not-in-inventory ()
  "tg-sell should fail when item not in player inventory."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist player-gold myself)
    (setq tg-valid-actions '(tg-sell))
    (setq player-gold 0)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory nil))
    (push (cons 'hero myself) creatures-alist)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market" :creature '(merchant)))
    (setq shop-alist '((merchant . (0.5 . ((sword . 50))))))
    (let ((result (catch 'exception (tg-sell "sword"))))
      (should (stringp result))
      (should (string-match-p "身上没有" result)))))

(ert-deftest test-tg-buy-no-merchant ()
  "tg-buy should fail when no merchant in room."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map creatures-alist
                        shop-alist player-gold)
    (setq tg-valid-actions '(tg-buy))
    (setq player-gold 100)
    (setq creatures-alist nil)
    (push (cons 'goblin (make-Creature :symbol 'goblin)) creatures-alist)
    (setq current-room (make-Room :symbol 'cave :description "Cave" :creature '(goblin)))
    (setq shop-alist nil)
    (let ((result (catch 'exception (tg-buy "bread"))))
      (should (stringp result))
      (should (string-match-p "没有商人" result)))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-action.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: Some tests FAIL (functions don't exist yet).

- [ ] **Step 3: Add require and commands to action.el**

Add `(require 'shop-system)` after the existing requires in `action.el` (after line 11):

```elisp
(require 'shop-system)
```

Add the three shop commands at the end of `action.el`, before `(provide 'action)`:

```elisp
(tg-defaction tg-shop ()
  "使用'shop'查看当前房间商人的商品"
  (let ((sk (shop-get-shopkeeper)))
    (unless sk
      (throw 'exception "这里没有商人"))
    (let* ((npc-sym (Creature-symbol sk))
           (goods (shop-get-goods npc-sym)))
      (if (not goods)
          (tg-display "商品已售罄")
        (tg-display (format "=== %s 的商店 ===" npc-sym))
        (dolist (item goods)
          (tg-display (format "  %s: %d 金币" (car item) (cdr item))))
        (tg-display (format "你的金币: %d" player-gold))))))

(tg-defaction tg-buy (item)
  "使用'buy <物品>'从商人购买物品"
  (when (stringp item)
    (setq item (intern item)))
  (let ((sk (shop-get-shopkeeper)))
    (unless sk
      (throw 'exception "这里没有商人"))
    (let* ((npc-sym (Creature-symbol sk))
           (price (shop-get-item-price npc-sym item)))
      (unless price
        (throw 'exception "商人没有这个商品"))
      (unless (>= player-gold price)
        (throw 'exception "金币不足"))
      (cl-decf player-gold price)
      (shop-remove-item npc-sym item)
      (add-inventory-to-creature myself item)
      (tg-display (format "购买了 %s，花费 %d 金币（剩余: %d）" item price player-gold)))))

(tg-defaction tg-sell (item)
  "使用'sell <物品>'向商人卖出物品"
  (when (stringp item)
    (setq item (intern item)))
  (let ((sk (shop-get-shopkeeper)))
    (unless sk
      (throw 'exception "这里没有商人"))
    (unless (inventory-exist-in-creature-p myself item)
      (throw 'exception (format "身上没有%s" item)))
    (let* ((npc-sym (Creature-symbol sk))
           (sell-rate (shop-get-sell-rate npc-sym))
           (base-price (or (shop-get-item-price npc-sym item) 5))
           (sell-price (max 1 (floor (* base-price sell-rate)))))
      (cl-incf player-gold sell-price)
      (remove-inventory-from-creature myself item)
      (shop-add-item npc-sym item base-price)
      (tg-display (format "卖出了 %s，获得 %d 金币（持有: %d）" item sell-price player-gold)))))
```

- [ ] **Step 4: Add require to text-game-maker.el**

Add `(require 'shop-system)` to `text-game-maker.el` after the existing require lines:

```elisp
(require 'shop-system)
```

- [ ] **Step 5: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (260 existing + 10 new = 270).

- [ ] **Step 6: Commit**

```bash
git add action.el test/test-action.el text-game-maker.el
git commit -m "feat: add shop/buy/sell commands

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Integrate with save-system

**Files:**
- Modify: `save-system.el` (save/restore player-gold and shop-alist)
- Modify: `test/test-save-system.el` (add shop save/load tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/test-save-system.el` before `(provide 'test-save-system)`:

```elisp
;; --- Shop save/load ---

(ert-deftest test-tg-save-restore-player-gold ()
  "Save/restore should persist player-gold."
  (test-with-globals-saved (player-gold current-room rooms-alist room-map creatures-alist
                        shop-alist myself tg-over-p tg-config-dir)
    (setq player-gold 42)
    (setq tg-over-p nil)
    (setq tg-config-dir nil)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
    (push (cons 'hero myself) creatures-alist)
    (setq rooms-alist nil)
    (setq current-room (make-Room :symbol 'start :description "Start"))
    (push (cons 'start current-room) rooms-alist)
    (setq room-map '((start)))
    (setq shop-alist nil)
    (test-with-temp-file ""
      (tg-save-game temp-file)
      (setq player-gold 0)
      (tg-load-game temp-file)
      (should (= player-gold 42)))))

(ert-deftest test-tg-save-restore-shop-alist ()
  "Save/restore should persist shop-alist."
  (test-with-globals-saved (player-gold current-room rooms-alist room-map creatures-alist
                        shop-alist myself tg-over-p tg-config-dir)
    (setq player-gold 0)
    (setq tg-over-p nil)
    (setq tg-config-dir nil)
    (setq creatures-alist nil)
    (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
    (push (cons 'hero myself) creatures-alist)
    (setq rooms-alist nil)
    (setq current-room (make-Room :symbol 'start :description "Start"))
    (push (cons 'start current-room) rooms-alist)
    (setq room-map '((start)))
    (setq shop-alist '((merchant . (0.5 . ((sword . 50))))))
    (test-with-temp-file ""
      (tg-save-game temp-file)
      (setq shop-alist nil)
      (tg-load-game temp-file)
      (should (assoc 'merchant shop-alist))
      (should (= (shop-get-sell-rate 'merchant) 0.5))
      (should (= (shop-get-item-price 'merchant 'sword) 50)))))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `emacs --batch -L . -L test -l test/test-save-system.el --eval "(ert-run-tests-batch-and-exit t)" 2>&1 | grep -c "FAILED"`
Expected: Some tests FAIL (gold/shop not saved yet).

- [ ] **Step 3: Modify save-system.el**

Add `(require 'shop-system)` to requires in `save-system.el`.

In `tg-save-game`, add shop data to the save-data alist. Find the line:
```elisp
	           (creatures . ,(mapcar (lambda (pair)
	                                   (cons (car pair) (tg-serialize-creature (cdr pair))))
	                                 creatures-alist)))))
```

Replace with:
```elisp
	           (creatures . ,(mapcar (lambda (pair)
	                                   (cons (car pair) (tg-serialize-creature (cdr pair))))
	                                 creatures-alist))
	           (player-gold . ,player-gold)
	           (shop-alist . ,shop-alist))))
```

In `tg-restore-game-state`, add restore of player-gold and shop-alist. After the creatures restore block (after the `dolist` for creatures-data), add:

```elisp
  ;; Restore shop state
  (setq player-gold (or (cdr (assoc 'player-gold data)) 0))
  (setq shop-alist (or (cdr (assoc 'shop-alist data)) shop-alist))
```

- [ ] **Step 4: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All tests pass (270 existing + 2 new = 272).

- [ ] **Step 5: Commit**

```bash
git add save-system.el test/test-save-system.el
git commit -m "feat: save/restore player-gold and shop-alist

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Update sample game and documentation

**Files:**
- Create: `sample/shop-config.el`
- Modify: `sample/creature-config.el` (add merchant with shopkeeper)
- Modify: `sample/sample-game.el` (add shop-init, gold init)
- Modify: `README.md`
- Modify: `docs/manual.org`

- [ ] **Step 1: Add merchant to creature-config.el**

Append to `sample/creature-config.el`:

```
(goblin-merchant "一个精明的哥布林商人，推着装满货物的小车" ((hp . 30) (attack . 3) (defense . 2)) () () nil 15
  (((player-in-room) say "来来来，看看我的好东西！"))
  t)
```

- [ ] **Step 2: Create shop-config.el**

Create `sample/shop-config.el`:

```
(goblin-merchant 0.3
  ((bread . 10) (health-potion . 25) (rusty-key . 15)))
```

- [ ] **Step 3: Update sample-game.el**

Add `(shop-init ...)` call after `(dialog-init ...)`. Also set initial gold. Find the line:

```elisp
    (dialog-init (expand-file-name "dialog-config.el" sample-dir))
```

Add after it:

```elisp
    (shop-init (expand-file-name "shop-config.el" sample-dir))
    (setq player-gold 20)
```

Add a shop hint to the display messages. Find:

```elisp
    (tg-display "对话提示: 输入 talk <NPC名称> 与NPC对话！")
```

Add after it:

```elisp
    (tg-display "商店提示: 输入 shop 查看商品，buy <物品> 购买，sell <物品> 出售！")
```

- [ ] **Step 4: Update README.md**

Add shop system to features list. Add `shop-system.el` to file structure. Update test count.

- [ ] **Step 5: Update docs/manual.org**

Add shop system chapter covering:
- `shop-config.el` format
- Commands: shop, buy, sell
- Integration with creature-config (shopkeeper field)
- API reference for shop-system.el
- Update command table with shop/buy/sell
- Update file structure and test counts

- [ ] **Step 6: Run full test suite**

Run: `bash run-tests.sh 2>&1 | tail -3`
Expected: All 272 tests pass.

- [ ] **Step 7: Commit**

```bash
git add sample/shop-config.el sample/creature-config.el sample/sample-game.el README.md docs/manual.org
git commit -m "feat: add shop system to sample game and docs

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
