;;; inventory-maker.el --- Inventory system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'thingatpt)
(defvar inventorys-alist nil
  "symbol与inventory对象的映射")

(defun get-inventory-by-symbol (symbol &optional noexception)
  "根据symbol获取inventory对象"
  (tg-get-entity inventorys-alist symbol noexception "没有定义该物品[%s]"))

(cl-defstruct Inventory
  "Inventory structure"
  (symbol nil :documentation "INVENTORY标志")
  (description "" :documentation "INVENTORY描述")
  (type nil :documentation "INVENTORY的类型")
  (effects nil :documentation "INVENTORY的使用效果")
  (watch-trigger nil :documentation "查看该INVENTORY时触发的事件")
  (take-trigger nil :documentation "获取该INVENTORY时触发的事件")
  (drop-trigger nil :documentation "丢弃该INVENTORY时触发的事件")
  (use-trigger nil :documentation "使用该INVENTORY时触发的事件")
  (wear-trigger nil :documentation "装备该INVENTORY时触发的事件"))

(tg-def-config-builder inventory inventorys-alist Inventory (symbol description type effects))

(cl-defmethod describe ((inventory Inventory))
  "输出inventory的描述"
  (format "这个是%s\n%s\n类型:%s\n使用效果:%s"
          (Inventory-symbol inventory) (Inventory-description inventory)
          (Inventory-type inventory) (Inventory-effects inventory)))

;; 创建inventory列表的方法

(defun inventory-has-type-p (inventory type)
  "`inventory'是否能被装备"
  (when (symbolp inventory)
	(setq inventory (get-inventory-by-symbol inventory)))
  (let ((inventory-type (Inventory-type inventory)))
	(or (eq inventory-type type)
		(member type inventory-type))))

(defun inventory-usable-p (inventory)
  "`inventory'是否能被消耗"
  (inventory-has-type-p inventory 'usable))

(defun inventory-wearable-p (inventory)
  "`inventory'是否能被装备"
  (inventory-has-type-p inventory 'wearable))

(provide 'inventory-maker)
