;;; action.el --- Game action commands for Text-Game-Maker  -*- lexical-binding: t; -*-

(defvar tg-valid-actions ()
  "允许执行的命令")

(require 'room-maker)
(require 'inventory-maker)
(require 'level-system)
;; action functions
(defmacro tg-defaction (action args doc-string &rest body)
  (declare (indent defun))
  `(progn
     (add-to-list 'tg-valid-actions ',action)
     (defun ,action ,args
       ,doc-string
       ,@body)))
;; 移动到各rooms的命令
(tg-defaction tg-move(directory)
  "使用'move up/right/down/left'往`directory'方向移动"
  (when (stringp directory)
    (setq directory (intern directory)))
  (setq directory (cdr (assoc directory '((up . 0) (right . 1) (down . 2) (left . 3)))))
  (unless directory
    (throw 'exception "未知的方向"))
  (let ((new-room-symbol (nth directory (beyond-rooms (Room-symbol current-room) room-map))))
    (unless new-room-symbol
      (throw 'exception "那里没有路"))
    ;; 触发离开事件
    (when (Room-out-trigger current-room)
      (funcall (Room-out-trigger current-room)))
    (setq current-room (get-room-by-symbol new-room-symbol))
    ;; 触发进入事件
    (when (Room-in-trigger current-room)
      (funcall (Room-in-trigger current-room)))
    (tg-display (describe current-room))))

(tg-defaction tg-watch (&optional symbol)
  "使用'watch'查看周围环境
使用'watch 物品'查看指定物品"
  (cond ((stringp symbol)
         (setq symbol (intern symbol))))
  (unless (or (null symbol)
              (inventory-exist-in-room-p current-room symbol)
              (creature-exist-in-room-p current-room symbol))
    (throw 'exception (format "房间中没有%s" symbol )))
  (let ((object (or (unless symbol current-room)
                    (get-room-by-symbol symbol)
                    (get-inventory-by-symbol symbol t)
                    (get-creature-by-symbol symbol))))
    (when-let* ((trig (cond ((Inventory-p object) (Inventory-watch-trigger object))
                           ((Creature-p object) (Creature-watch-trigger object)))))
      (funcall trig))
    (describe object)))

(tg-defaction tg-take (inventory)
  "使用'take 物品'获取ROOM中的物品"
  (cond ((stringp inventory)
         (setq inventory (intern inventory))))
  (unless (inventory-exist-in-room-p current-room inventory)
    (throw 'exception (format "房间中没有%s" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
    (when-let* ((trig (Inventory-take-trigger object)))
      (funcall trig))
    (add-inventory-to-creature myself inventory)
    (remove-inventory-from-room current-room inventory)))

(tg-defaction tg-drop (inventory)
  "使用'drop 物品'丢弃身上的物品"
  (cond ((stringp inventory)
         (setq inventory (intern inventory))))
  (unless (inventory-exist-in-creature-p myself inventory)
    (throw 'exception (format "身上没有%s" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
    (when-let* ((trig (Inventory-drop-trigger object)))
      (funcall trig))
    (remove-inventory-from-creature myself inventory)
    (add-inventory-to-room current-room inventory)))

(tg-defaction tg-use (inventory)
  "使用'use 物品'消耗自己随身携带的inventory"
  (cond ((stringp inventory)
         (setq inventory (intern inventory))))
  (unless (inventory-exist-in-creature-p myself inventory)
    (throw 'exception (format "未携带%s" inventory)))
  (unless (inventory-usable-p inventory)
    (throw 'exception (format "%s不可使用" inventory)))
  (let ((object (get-inventory-by-symbol inventory)))
    (when-let* ((trig (Inventory-use-trigger object)))
      (funcall trig))
    (take-effects-to-creature myself (Inventory-effects object))
    (remove-inventory-from-creature myself inventory)))

(tg-defaction tg-wear (equipment)
  "使用'wear 物品'装备自己随身携带的equipment"
  (cond ((stringp equipment)
         (setq equipment (intern equipment))))
  (unless (inventory-exist-in-creature-p myself equipment)
    (throw 'exception (format "未携带%s" equipment)))
  (unless (inventory-wearable-p equipment)
    (throw 'exception (format "%s不可装备" equipment)))
  (let ((object (get-inventory-by-symbol equipment)))
    (when-let* ((trig (Inventory-wear-trigger object)))
      (funcall trig))
    (take-effects-to-creature myself (Inventory-effects object))
    (remove-inventory-from-creature myself equipment)
    (add-equipment-to-creature myself equipment)
    (tg-display (format "您装备了%s" equipment))))

(tg-defaction tg-attack (target)
  "使用'attack <target>'攻击当前房间中的生物"
  (when (stringp target)
    (setq target (intern target)))
  (unless (creature-exist-in-room-p current-room target)
    (throw 'exception (format "房间中没有%s" target)))
  (let* ((target-creature (get-creature-by-symbol target))
         (my-attack (or (cdr (assoc 'attack (Creature-attr myself))) 0))
         (my-defense (or (cdr (assoc 'defense (Creature-attr myself))) 0))
         (target-attack (or (cdr (assoc 'attack (Creature-attr target-creature))) 0))
         (target-defense (or (cdr (assoc 'defense (Creature-attr target-creature))) 0))
         (damage (max 1 (- my-attack target-defense))))
    (take-effect-to-creature target-creature (cons 'hp (- damage)))
    (tg-display (format "你攻击了%s，造成 %d 点伤害！" target damage))
    (if (<= (cdr (assoc 'hp (Creature-attr target-creature))) 0)
        (progn
          (remove-creature-from-room current-room target)
          (when-let* ((trig (Creature-death-trigger target-creature)))
            (funcall trig))
          (tg-display (format "%s被击败了！" target))
          (let ((exp-gained (get-exp-reward target-creature)))
            (tg-display (format "获得 %d 点经验值！" exp-gained))
            (add-exp-to-creature myself exp-gained)))
      (let* ((counter-damage (max 1 (- target-attack my-defense))))
        (take-effect-to-creature myself (cons 'hp (- counter-damage)))
        (tg-display (format "%s反击，造成 %d 点伤害！" target counter-damage))
        (if (<= (cdr (assoc 'hp (Creature-attr myself))) 0)
            (progn
              (tg-display "你被击败了！游戏结束！")
              (setq tg-over-p t))
          (tg-display (format "你的HP: %d | %s的HP: %d"
                              (cdr (assoc 'hp (Creature-attr myself)))
                              target
                              (cdr (assoc 'hp (Creature-attr target-creature))))))))))

(tg-defaction tg-upgrade (attr points)
  "使用'upgrade <属性> <点数>'消耗技能点提升指定属性"
  (when (stringp attr)
    (setq attr (intern attr)))
  (unless (assoc 'bonus-points (Creature-attr myself))
    (throw 'exception "没有bonus-points属性"))
  (unless (assoc attr (Creature-attr myself))
    (throw 'exception (format "没有%s属性，无法分配" attr)))
  (let ((pts (string-to-number (or points "0")))
        (available (cdr (assoc 'bonus-points (Creature-attr myself)))))
    (unless (> pts 0)
      (throw 'exception "请输入有效的点数"))
    (unless (>= available pts)
      (throw 'exception "技能点不足"))
    (cl-incf (cdr (assoc attr (Creature-attr myself))) pts)
    (cl-decf (cdr (assoc 'bonus-points (Creature-attr myself))) pts)
    (tg-display (format "分配 %d 点到 %s，剩余技能点: %d" pts attr (cdr (assoc 'bonus-points (Creature-attr myself)))))))

(tg-defaction tg-status(&optional useless)
  "使用'status'查看自己的状态"
  (tg-display (describe myself)))

(tg-defaction tg-help (&rest actions)
  "使用'help'查看各action说明
使用'help action'查看指定action的说明"
  (unless actions
    (setq actions tg-valid-actions))
  (dolist (action actions)
    (when (stringp action)
      (setq action (intern (format "tg-%s" action))))
    (tg-display (documentation action))))
(tg-defaction tg-quit()
  "使用'quit'退出游戏"
  (setq tg-over-p t))
(provide 'action)
