;;; action.el --- Game action commands for Text-Game-Maker  -*- lexical-binding: t; -*-

(defvar tg-valid-actions ()
  "允许执行的命令")

(require 'room-maker)
(require 'inventory-maker)
(require 'level-system)
(require 'npc-behavior)
(require 'quest-system)
(require 'dialog-system)
(require 'shop-system)
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
    (tg-display (describe current-room))
    (quest-track-explore new-room-symbol)
    (npc-run-behaviors)))

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
    (when (and symbol (Creature-p object))
      (quest-track-talk symbol))
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
    (remove-inventory-from-room current-room inventory)
    (quest-track-collect inventory)))

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
          (quest-track-kill target)
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
(tg-defaction tg-talk (npc-name)
  "使用'talk <NPC>'与NPC对话"
  (when (stringp npc-name)
    (setq npc-name (intern npc-name)))
  (unless (creature-exist-in-room-p current-room npc-name)
    (throw 'exception (format "房间中没有%s" npc-name)))
  (dialog-start npc-name))

(tg-defaction tg-quests ()
  "使用'quests'查看当前任务列表"
  (tg-display "=== 任务列表 ===")
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (cond ((eq (Quest-status q) 'active)
             (tg-display (format "[进行中] %s (%d/%d)" (Quest-description q) (Quest-progress q) (Quest-count q))))
            ((eq (Quest-status q) 'completed)
             (tg-display (format "[已完成] %s" (Quest-description q))))
            ((eq (Quest-status q) 'inactive)
             (tg-display (format "[未开始] %s" (Quest-description q))))))))

(tg-defaction tg-quest (name)
  "使用'quest <名称>'查看指定任务详情"
  (when (stringp name)
    (setq name (intern name)))
  (let ((q (cdr (assoc name quests-alist))))
    (unless q
      (throw 'exception (format "没有任务%s" name)))
    (tg-display (format "任务：%s" (Quest-description q)))
    (tg-display (format "类型：%s  目标：%s" (Quest-type q) (Quest-target q)))
    (tg-display (format "进度：%d/%d" (Quest-progress q) (Quest-count q)))
    (tg-display (format "状态：%s" (Quest-status q)))
    (when (Quest-rewards q)
      (tg-display (format "奖励：%s" (Quest-rewards q))))))

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

(tg-defaction tg-quit()
  "使用'quit'退出游戏"
  (setq tg-over-p t))

(tg-defaction tg-shop ()
  "使用'shop'查看当前房间商人的商品"
  (let ((sk (shop-get-shopkeeper)))
    (if (not sk)
        (tg-display "这里没有商人")
      (let* ((npc-sym (Creature-symbol sk))
             (goods (shop-get-goods npc-sym)))
        (if (not goods)
            (tg-display "商品已售罄")
          (tg-display (format "=== %s 的商店 ===" npc-sym))
          (dolist (item goods)
            (tg-display (format "  %s: %d 金币" (car item) (cdr item))))
          (tg-display (format "你的金币: %d" player-gold)))))))

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

(provide 'action)
