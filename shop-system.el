;;; shop-system.el --- Shop/trading system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)

;; --- Variables ---

(defvar tg-player-gold 0
  "玩家持有金币数量")

(defvar tg-shop-alist nil
  "商品列表缓存，格式 ((npc-symbol . ShopConfig) ...)")

(cl-defstruct ShopConfig
  "ShopConfig structure"
  (sell-rate 0.5 :documentation "卖出折扣率")
  (goods nil :documentation "商品列表 ((item-symbol . price) ...)"))

;; --- Config loading ---

(defun tg-build-shop-entry (shop-entity)
  "根据SHOP-ENTITY创建商店条目."
  (cl-multiple-value-bind (npc-symbol sell-rate goods) shop-entity
    (cons npc-symbol (make-ShopConfig :sell-rate sell-rate :goods goods))))

(defun tg-shop-init (config-file)
  "从CONFIG-FILE加载商品配置."
  (let ((shop-entities (tg-read-from-whole-string (tg-file-content config-file))))
    (setq tg-shop-alist (mapcar #'tg-build-shop-entry shop-entities))))

;; --- Helpers ---

(defun tg-shop-get-shopkeeper ()
  "返回当前房间中的第一个商人Creature，无则返回nil."
  (when (and tg-current-room (Room-creature tg-current-room))
    (cl-dolist (sym (Room-creature tg-current-room))
      (let ((cr (tg-get-creature-by-symbol sym)))
        (when (and cr (Creature-shopkeeper cr))
          (cl-return cr))))))

(defun tg-shop-get-config (npc-symbol)
  "返回NPC-SYMBOL对应的ShopConfig，无则返回nil."
  (cdr (assoc npc-symbol tg-shop-alist)))

(defun tg-shop-get-goods (npc-symbol)
  "返回NPC-SYMBOL对应的商品列表."
  (when-let* ((config (tg-shop-get-config npc-symbol)))
    (ShopConfig-goods config)))

(defun tg-shop-get-sell-rate (npc-symbol)
  "返回NPC-SYMBOL对应的卖出折扣率."
  (when-let* ((config (tg-shop-get-config npc-symbol)))
    (ShopConfig-sell-rate config)))

(defun tg-shop-get-item-price (npc-symbol item-symbol)
  "返回NPC-SYMBOL的商品列表中ITEM-SYMBOL的价格."
  (let* ((goods (tg-shop-get-goods npc-symbol))
         (item (assoc item-symbol goods)))
    (when item (cdr item))))

(defun tg-shop-remove-item (npc-symbol item-symbol)
  "从NPC-SYMBOL的商品列表中移除ITEM-SYMBOL."
  (when-let* ((config (tg-shop-get-config npc-symbol)))
    (setf (ShopConfig-goods config)
          (assq-delete-all item-symbol (ShopConfig-goods config)))))

(defun tg-shop-add-item (npc-symbol item-symbol price)
  "向NPC-SYMBOL的商品列表中添加ITEM-SYMBOL."
  (when-let* ((config (tg-shop-get-config npc-symbol)))
    (push (cons item-symbol price) (ShopConfig-goods config))))

(provide 'shop-system)
