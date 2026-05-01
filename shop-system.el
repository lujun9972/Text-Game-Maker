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
SHOP-ENTITY 格式: (npc-symbol sell-rate ((item-symbol . price) ...))"
  (let ((npc-symbol (nth 0 shop-entity))
        (sell-rate (nth 1 shop-entity))
        (goods (nth 2 shop-entity)))
    (cons npc-symbol (cons sell-rate goods))))

(defun shop-init (config-file)
  "从CONFIG-FILE加载商品配置."
  (let* ((content (with-temp-buffer
                    (insert-file-contents config-file)
                    (buffer-string)))
         (shop-entities (read-from-whole-string content)))
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
    (when entry (cdr (cdr entry)))))

(defun shop-get-sell-rate (npc-symbol)
  "返回NPC-SYMBOL对应的卖出折扣率."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry (car (cdr entry)))))

(defun shop-get-item-price (npc-symbol item-symbol)
  "返回NPC-SYMBOL的商品列表中ITEM-SYMBOL的价格."
  (let* ((goods (shop-get-goods npc-symbol))
         (item (assoc item-symbol goods)))
    (when item (cdr item))))

(defun shop-remove-item (npc-symbol item-symbol)
  "从NPC-SYMBOL的商品列表中移除ITEM-SYMBOL."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (setf (cdr (cdr entry)) (assq-delete-all item-symbol (cdr (cdr entry)))))))

(defun shop-add-item (npc-symbol item-symbol price)
  "向NPC-SYMBOL的商品列表中添加ITEM-SYMBOL，价格为PRICE."
  (let ((entry (assoc npc-symbol shop-alist)))
    (when entry
      (setf (cdr (cdr entry)) (append (cdr (cdr entry)) (list (cons item-symbol price)))))))

(provide 'shop-system)
