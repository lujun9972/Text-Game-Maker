(defvar display-fn #'message
  "显示信息的函数")
(add-to-list 'load-path "~/myLisp/Text-Game-Maker")
(require 'room-maker)
(require 'inventory-maker)
;; action functions

;; 移动到各rooms的命令
(defconst up 0)
(defconst right 1)
(defconst down 2)
(defconst left 3)
(defun move(directory)
  "往`directory'方向移动"
  (when (symbolp directory)
	(setq (cdr (assoc directory '((0 . up) (1 . right) (2 . down) (3 . left))))))
  (let ((new-room-symbol (nth directory (beyond-rooms (member-symbol currect-room) room-map))))
	(unless new-room-symbol
	  (throw 'exception "那里没有路"))
	;; 触发离开事件
	(when (member-out-trigger currect-room)
	  (funcall (member-out-trigger currect-room)))
	(setq currect-room (get-room-by-symbol new-room-symbol))
	;; 触发进入事件
	(when (member-in-trigger currect-room)
	  (funcall (member-in-trigger currect-room)))
	(funcall display-fn (describe currect-room))))

(defun watch (&optional symbol)
  "查看物品/周围环境"
  (cond ((stringp symbol)
		 (setq symbol (intern symbol))))
  (unless (or (null symbol)
			  (inventory-exist-in-room-p currect-room symbol)
			  (creature-exist-in-room-p currect-room symbol))
	(throw 'exception (format "房间中没有%s" symbol )))
  (let ((object (or (unless symbol currect-room)
					(get-room-by-symbol symbol)
					(get-inventory-by-symbol symbol))))
	(when (and (slot-exists-p object 'watch-trigger)
			   (slot-boundp object 'watch-trigger)
			   (slot-value object 'watch-trigger))
	  (funcall (slot-value object 'watch-trigger)))
	(describe object)))

(defun get (inventory)
  "获取ROOM中的物品"
  (cond ((stringp inventory)
		 (setq inventory (intern inventory))))
  (unless (inventory-exist-in-room-p currect-room inventory)
	(throw 'exception (format "房间中没有%s" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
	(when (and (slot-exists-p object 'get-trigger)
			   (slot-boundp object 'get-trigger)
			   (slot-value object 'get-trigger))
	  (funcall (slot-value object 'get-trigger)))
	(add-inventory-to-creature myself inventory)
	(remove-inventory-from-room currect-room inventory)))

(defun drop (inventory)
  "丢弃身上的物品"
  (cond ((stringp inventory)
		 (setq inventory (intern inventory))))
  (unless (inventory-exist-in-creature-p myself inventory)
	(throw 'exception (format "身上没有%s" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
	(when (and (slot-exists-p object 'drop-trigger)
			   (slot-boundp object 'drop-trigger)
			   (slot-value object 'drop-trigger))
	  (funcall (slot-value object 'drop-trigger)))
	(remove-inventory-from-creature myself inventory)
	(add-inventory-to-room currect-room inventory)))

(defun use (inventory)
  "使用自己随身携带的inventory"
  (cond ((stringp inventory)
		 (setq inventory (intern inventory))))
  (unless (inventory-exist-in-creature-p myself inventory)
	(throw 'exception (format "未携带%s" inventory)))
  (unless (inventory-usable-p inventory)
	(throw 'exception (format "%s不可使用" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
	(when (and (slot-exists-p object 'use-trigger)
			   (slot-boundp object 'use-trigger)
			   (slot-value object 'use-trigger))
	  (funcall (slot-value object 'use-trigger)))
	(take-effects-to-creature myself (member-effects object))
	(remove-inventory-from-creature myself inventory)))

(defun wear (equipment)
  "装备自己随身携带的equipment"
  (cond ((stringp equipment)
		 (setq equipment (intern equipment))))
  (unless (equipment-exist-in-creature-p myself equipment)
	(throw 'exception (format "未携带%s" equipment)))
  (unless (inventory-wearable-p equipment)
	(throw 'exception (format "%s不可使用" equipment)))
  (let ((object (get-inventory-by-symbol equipment)))
	(when (and (slot-exists-p object 'use-trigger)
			   (slot-boundp object 'use-trigger)
			   (slot-value object 'use-trigger))
	  (funcall (slot-value object 'use-trigger)))
	(take-effects-to-creature myself (member-effects object))
	(remove-inventory-from-creature myself equipment)
	(add-inventory-to-creature creature myself equipment)))

(provide 'action)
