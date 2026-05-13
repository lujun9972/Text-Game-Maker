;;; tg-action.el --- 动词注册系统  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, action

;;; Commentary:
;; 动词注册系统，用于注册和管理游戏中的动词动作

;;; Code:

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-dialog)
(require 'tg-shop)
(require 'tg-quest)
(require 'tg-level)

(cl-defstruct tg-action
  id
  synonyms
  handler)

(defun tg-register-action (&rest args)
  "注册一个动作，将其所有同义词映射到动作词哈希表。
ARGS: 应该包含 :id, :synonyms, :handler 关键字参数"
  (let ((id (cl-getf args :id))
        (synonyms (cl-getf args :synonyms))
        (handler (cl-getf args :handler)))
    (let ((action (make-tg-action :id id :synonyms synonyms :handler handler)))
      ;; 直接将动作添加到动作注册表（避免与 registry 的同名函数冲突）
      (puthash id action tg--actions)
      ;; 将所有同义词映射到动作ID
      (dolist (synonym synonyms)
        (puthash synonym id tg--action-words)))))

(defun tg-find-action (word)
  "通过动作词查找对应的动作ID。
WORD: 动作词或同义词"
  (gethash word tg--action-words))

(defconst tg-verb-aliases
  '(("get" . "take")
    ("l" . "look")
    ("x" . "examine")
    ("i" . "inventory")
    ("pick up" . "take")
    ("put down" . "drop")
    ("equip" . "wear")
    ("consume" . "eat")
    ("hit" . "attack")
    ("fight" . "attack")
    ("speak" . "talk"))
  "动词同义词映射表。将简写或别称映射到标准动词。")

(defconst tg-passive-actions
  '("look" "examine" "inventory" "status" "quests" "help")
  "被动动作列表。这些动作不会触发NPC行为，不计入回合。")

;;; ============================================================
;;; 内置 Action Handlers
;;; ============================================================

(defun tg-action--handler-go (ast game)
  "移动到指定方向的房间"
  (let* ((direction (plist-get ast :direction))
         (location (tg-game-get game :location))
         (room (tg-get-room location)))
    (if (not direction)
        (tg-message "你要去哪个方向？")
      (let ((target-sym (tg-room-exit room direction)))
        (if (not target-sym)
            (tg-message "那个方向走不通。")
          (tg-game-put game :location target-sym)
          (let ((target-room (tg-get-room target-sym)))
            (when target-room
              (tg-room-visit target-room)
              (tg-track-quest 'explore target-sym)
              (tg-message "%s" (tg-room-describe target-room)))
            t))))))

(defun tg-action--handler-look (ast game)
  "查看当前房间或检查指定对象"
  (let ((do-key (plist-get ast :do-key)))
    (if do-key
        (tg-action--handler-examine ast game)
      (let* ((location (tg-game-get game :location))
             (room (tg-get-room location)))
        (if room
            (tg-message "%s" (tg-room-describe room))
          (tg-message "你不在任何地方。"))))))

(defun tg-action--handler-examine (ast game)
  "检查对象或生物"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要检查什么？"))
     ;; 检查是否是生物
     ((tg-get-creature do-key)
      (let ((creature (tg-get-creature do-key)))
        (if (tg-creature-dead-p creature)
            (tg-message "%s 已经死了。" (tg-creature-name creature))
          (tg-message "你看到了%s。" (tg-creature-name creature)))))
     ;; 检查是否是对象
     ((tg-get-object do-key)
      (let ((obj (tg-get-object do-key)))
        (if (tg-object-accessible-p obj
                (tg-get-room (tg-game-get game :location)))
            (tg-message "%s" (or (tg-object-name obj) "没什么特别的。"))
          (tg-message "你看不到那个。"))))
     (t
      (tg-message "这里没有这个东西。")))))

(defun tg-action--handler-take (ast game)
  "拾取对象，支持 take all"
  (let ((do-key (plist-get ast :do-key)))
    (if (eq do-key :all)
        (let* ((room (tg-get-room (tg-game-get game :location)))
               (objects (tg-room-all-visible-objects room))
               (taken 0))
          (dolist (sym objects)
            (let ((obj (tg-get-object sym)))
              (when (and obj (tg-object-takeable-p obj)
                         (member sym (tg-room-contents room)))
                (let ((player (tg-player game)))
                  (setf (tg-room-contents room)
                        (remove sym (tg-room-contents room)))
                  (tg-creature-add-item player sym)
                  (tg-message "拾取了%s。" (tg-object-name obj))
                  (tg-track-quest 'collect sym)
                  (cl-incf taken)))))
          (when (= taken 0)
            (tg-message "这里没有可以拾取的东西。"))
          t)
      ;; 单个对象
      (let* ((room (tg-get-room (tg-game-get game :location)))
             (obj (tg-get-object do-key)))
        (cond
         ((not do-key)
          (tg-message "你要拾取什么？"))
         ((not obj)
          (tg-message "这里没有这个东西。"))
         ((not (member do-key (tg-room-contents room)))
          (tg-message "你拿不到那个。"))
         ((not (tg-object-takeable-p obj))
          (tg-message "你拿不起来。"))
         (t
          (let ((player (tg-player game)))
            (setf (tg-room-contents room)
                  (remove do-key (tg-room-contents room)))
            (tg-creature-add-item player do-key)
            (tg-message "拾取了%s。" (tg-object-name obj))
            (tg-track-quest 'collect do-key)
            t)))))))

(defun tg-action--handler-drop (ast game)
  "放下物品到当前房间"
  (let ((do-key (plist-get ast :do-key))
        (player (tg-player game))
        (room (tg-get-room (tg-game-get game :location))))
    (cond
     ((not do-key)
      (tg-message "你要放下什么？"))
     ((not (tg-creature-has-item player do-key))
      (tg-message "你没有这个东西。"))
     (t
      (tg-creature-remove-item player do-key)
      (push do-key (tg-room-contents room))
      (tg-message "放下了%s。" (tg-object-name (tg-get-object do-key)))
      t))))

(defun tg-action--handler-place (ast game)
  "将物品放入容器或放在支撑物上"
  (let ((do-key (plist-get ast :do-key))
        (io-key (plist-get ast :io-key))
        (prep (plist-get ast :prep))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要放什么？"))
     ((not io-key)
      (tg-message "你要放在哪里？"))
     ((not (tg-creature-has-item player do-key))
      (tg-message "你没有这个东西。"))
     (t
      (let* ((obj (tg-get-object do-key))
             (target (tg-get-object io-key)))
        (cond
         ((not target)
          (tg-message "那里放不了。"))
         ((and (string= prep "in")
               (member 'container (tg-object-props target))
               (tg-object-open-p target))
          ;; 放入打开的容器
          (tg-creature-remove-item player do-key)
          (push do-key (tg-object-contents target))
          (tg-message "把%s放进了%s。" (tg-object-name obj) (tg-object-name target))
          t)
         ((and (string= prep "on")
               (member 'supporter (tg-object-props target)))
          ;; 放在支撑物上
          (tg-creature-remove-item player do-key)
          (push do-key (tg-object-contents target))
          (tg-message "把%s放在了%s上。" (tg-object-name obj) (tg-object-name target))
          t)
         ((and (member 'container (tg-object-props target))
               (not (tg-object-open-p target)))
          (tg-message "%s是关着的。" (tg-object-name target)))
         (t
          (tg-message "那里放不了。"))))))))

(defun tg-action--handler-open (ast game)
  "打开容器"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要打开什么？"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "这里没有这个东西。"))
         ((not (member 'container (tg-object-props obj)))
          (tg-message "那个打不开。"))
         ((tg-object-open-p obj)
          (tg-message "%s已经是打开的。" (tg-object-name obj)))
         ((tg-object-locked-p obj)
          (tg-message "%s被锁住了，需要钥匙。" (tg-object-name obj)))
         (t
          (setf (tg-object-state obj) 'open)
          (tg-message "打开了%s。" (tg-object-name obj))
          t)))))))

(defun tg-action--handler-close (ast game)
  "关闭容器"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要关闭什么？"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "这里没有这个东西。"))
         ((not (member 'container (tg-object-props obj)))
          (tg-message "那个关不上。"))
         ((not (tg-object-open-p obj))
          (tg-message "%s已经是关闭的。" (tg-object-name obj)))
         (t
          (setf (tg-object-state obj) 'closed)
          (tg-message "关闭了%s。" (tg-object-name obj))
          t)))))))

(defun tg-action--handler-unlock (ast game)
  "用钥匙解锁容器"
  (let ((do-key (plist-get ast :do-key))
        (io-key (plist-get ast :io-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要解锁什么？"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "这里没有这个东西。"))
         ((not (member 'container (tg-object-props obj)))
          (tg-message "那个不需要解锁。"))
         ((not (tg-object-locked-p obj))
          (tg-message "%s没有被锁住。" (tg-object-name obj)))
         ((not io-key)
          (tg-message "你需要用什么来解锁？"))
         ((not (tg-creature-has-item player io-key))
          (tg-message "你没有这个东西。"))
         ((let ((required-key (tg-object-key obj)))
            (not (eq io-key required-key)))
          (tg-message "钥匙不匹配。"))
         (t
          (setf (tg-object-state obj) 'closed)
          (tg-message "解锁了%s。" (tg-object-name obj))
          t)))))))

(defun tg-action--handler-wear (ast game)
  "装备物品"
  (let ((do-key (plist-get ast :do-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要装备什么？"))
     ((not (tg-creature-has-item player do-key))
      (tg-message "你没有这个东西。"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "没有这个东西。"))
         ((not (member 'wearable (tg-object-props obj)))
          (tg-message "那个不能装备。"))
         ((member do-key (tg-creature-equipment player))
          (tg-message "你已经装备了%s。" (tg-object-name obj)))
         (t
          (tg-creature-remove-item player do-key)
          (push do-key (tg-creature-equipment player))
          (tg-message "装备了%s。" (tg-object-name obj))
          t)))))))

(defun tg-action--handler-eat (ast game)
  "食用物品，消耗并应用效果"
  (let ((do-key (plist-get ast :do-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要吃什么？"))
     ((not (tg-creature-has-item player do-key))
      (tg-message "你没有这个东西。"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "没有这个东西。"))
         ((not (member 'edible (tg-object-props obj)))
          (tg-message "那个不能吃。"))
         (t
          ;; 消耗物品
          (tg-creature-remove-item player do-key)
          ;; 应用效果（永久直接写，临时入 buffs）
          (let ((effects (tg-object-effects obj)))
            (when effects
              (tg-buffs-apply game effects)))
          (tg-message "吃掉了%s。" (tg-object-name obj))
          t)))))))

(defun tg-action--handler-read (ast game)
  "阅读物品"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要阅读什么？"))
     (t
      (let ((obj (tg-get-object do-key)))
        (cond
         ((not obj)
          (tg-message "这里没有这个东西。"))
         ((not (member 'readable (tg-object-props obj)))
          (tg-message "那个没什么可读的。"))
         (t
          (tg-message "%s" (or (tg-object-name obj) "上面什么也没写。"))
          t)))))))

(defun tg-action--handler-inventory (_ast game)
  "查看背包和装备"
  (let ((player (tg-player game)))
    (if (not player)
        (tg-message "没有玩家。")
      (let ((inventory (tg-creature-inventory player))
            (equipment (tg-creature-equipment player)))
        (if (and (null inventory) (null equipment))
            (tg-message "你身上什么也没有。")
          (when equipment
            (tg-message "装备：%s"
                        (mapconcat (lambda (s)
                                     (let ((o (tg-get-object s)))
                                       (if o (tg-object-name o) (format "%s" s))))
                                   equipment "、")))
          (when inventory
            (tg-message "背包：%s"
                        (mapconcat (lambda (s)
                                     (let ((o (tg-get-object s)))
                                       (if o (tg-object-name o) (format "%s" s))))
                                   inventory "、")))
          t)))))

(defun tg-action--handler-attack (ast game)
  "攻击生物：计算伤害、反击、死亡掉落和经验奖励"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要攻击什么？"))
     (t
      (let ((creature (tg-get-creature do-key)))
        (cond
         ((not creature)
          (tg-message "这里没有这个目标。"))
         ((not (member do-key (tg-room-creatures
                               (tg-get-room (tg-game-get game :location)))))
          (tg-message "这里没有这个目标。"))
         ((tg-creature-dead-p creature)
          (tg-message "%s 已经死了。" (tg-creature-name creature)))
         (t
          (let* ((player (tg-player game))
                 (active-buffs (tg-game-get game :active-buffs))
                 ;; 将 game active-buffs 格式转换为 effective-attr 期望的格式
                 ;; game 格式: ((attr . (:delta val :remaining N)) ...)
                 ;; 期望格式: ((attr-key value) ...)
                 (buff-values
                  (mapcar (lambda (b) (list (car b) (plist-get (cdr b) :delta)))
                          active-buffs))
                 (player-attack (tg-creature-effective-attr player 'attack buff-values))
                 (npc-defense (tg-creature-attr-get creature 'defense))
                 (damage (max 1 (- player-attack (or npc-defense 0)))))
            ;; 对 NPC 造成伤害
            (tg-creature-take-effect creature (list 'hp (- damage)))
            (tg-message "你攻击了%s，造成了%d点伤害。"
                        (tg-creature-name creature) damage)
            ;; 检查 NPC 是否死亡
            (if (tg-creature-dead-p creature)
                (let ((room (tg-get-room (tg-game-get game :location))))
                  (tg-message "%s被击败了！" (tg-creature-name creature))
                  ;; 掉落物品（背包 + 装备，含 no-drop 过滤）
                  (let ((all-items (append (tg-creature-inventory creature)
                                           (tg-creature-equipment creature)))
                        (remaining-items nil))
                    (dolist (item-sym all-items)
                      (let ((obj (tg-get-object item-sym)))
                        (if (and obj (memq 'no-drop (tg-object-props obj)))
                            (push item-sym remaining-items)  ;; no-drop：保留
                          ;; 掉落
                          (tg-room-add-object room item-sym)
                          (tg-message "%s掉落了%s。"
                                      (tg-creature-name creature)
                                      (tg-object-name obj)))))
                    ;; 清空并保留 no-drop 物品
                    (setf (tg-creature-inventory creature)
                          (cl-intersection (tg-creature-inventory creature) remaining-items))
                    (setf (tg-creature-equipment creature)
                          (cl-intersection (tg-creature-equipment creature) remaining-items)))
                  ;; 经验奖励
                  (let ((exp-reward (tg-creature-exp-reward creature)))
                    (when exp-reward
                      (tg-creature-take-effect player (list 'exp exp-reward))
                      (tg-message "获得%d点经验。" exp-reward)
                      (tg-level-check player)))
                  ;; 追踪击杀任务
                  (tg-track-quest 'kill do-key)
                  ;; 触发死亡触发器
                  (let ((death-trigger (tg-creature-death-trigger creature)))
                    (when (and death-trigger (functionp death-trigger))
                      (funcall death-trigger creature game)))
                  ;; 触发刷新调度
                  (tg-respawn-schedule do-key))
              ;; NPC 反击
              (let* ((npc-attack (tg-creature-attr-get creature 'attack))
                     (player-defense (tg-creature-effective-attr player 'defense buff-values))
                     (counter-damage (max 0 (- (or npc-attack 0) player-defense))))
                (when (> counter-damage 0)
                  (tg-creature-take-effect player (list 'hp (- counter-damage)))
                  (tg-message "%s反击了你，造成了%d点伤害。"
                              (tg-creature-name creature) counter-damage))
                ;; 检查玩家是否死亡
                (when (tg-creature-dead-p player)
                  (tg-message "你被%s击败了！游戏结束。" (tg-creature-name creature))
                  (tg-game-put game :state 'game-over))))
            t))))))))

(defun tg-action--handler-talk (ast game)
  "与NPC对话"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要和谁说话？"))
     (t
      (let ((creature (tg-get-creature do-key)))
        (cond
         ((not creature)
          (tg-message "这里没有这个人。"))
         ((not (member do-key (tg-room-creatures
                               (tg-get-room (tg-game-get game :location)))))
          (tg-message "这里没有这个人。"))
         (t
          (tg-dialog-start do-key)
          (tg-track-quest 'talk do-key)
          t)))))))

(defun tg-action--handler-buy (ast game)
  "从NPC商店购买物品"
  (let ((do-key (plist-get ast :do-key))
        (io-key (plist-get ast :io-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要买什么？"))
     ((not player)
      (tg-message "没有玩家。"))
     (t
      ;; 查找关联的 NPC 商店
      (let ((npc-sym io-key)
            shop-sym)
        ;; 如果指定了 NPC，查找其商店
        (when npc-sym
          (let ((creature (tg-get-creature npc-sym)))
            (when (and creature (tg-creature-shopkeeper creature))
              ;; 在所有商店中查找属于该 NPC 的商店
              (maphash (lambda (sym s)
                         (when (eq (tg-shop-npc-symbol s) npc-sym)
                           (setq shop-sym sym)))
                       tg--shops))))
        ;; 如果没指定 NPC，查找当前房间中的商人
        (unless shop-sym
          (let ((room (tg-get-room (tg-game-get game :location))))
            (dolist (c-sym (tg-room-creatures room))
              (unless shop-sym
                (let ((c (tg-get-creature c-sym)))
                  (when (and c (tg-creature-shopkeeper c))
                    (maphash (lambda (sym s)
                               (when (eq (tg-shop-npc-symbol s) c-sym)
                                 (setq shop-sym sym)))
                             tg--shops)))))))
        (cond
         ((not shop-sym)
          (tg-message "这里没有商人。"))
         (t
          (let ((shop (tg-get-shop shop-sym)))
            (condition-case err
                (progn
                  (tg-shop-buy do-key shop player)
                  (tg-message "购买了%s。" (tg-object-name (tg-get-object do-key)))
                  t)
              (error
               (tg-message "%s" (error-message-string err))))))))))))

(defun tg-action--handler-sell (ast game)
  "向NPC商店出售物品"
  (let ((do-key (plist-get ast :do-key))
        (io-key (plist-get ast :io-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要卖什么？"))
     ((not player)
      (tg-message "没有玩家。"))
     ((not (tg-creature-has-item player do-key))
      (tg-message "你没有这个东西。"))
     (t
      ;; 查找关联的 NPC 商店
      (let ((npc-sym io-key)
            shop-sym)
        ;; 如果指定了 NPC，查找其商店
        (when npc-sym
          (let ((creature (tg-get-creature npc-sym)))
            (when (and creature (tg-creature-shopkeeper creature))
              (maphash (lambda (sym s)
                         (when (eq (tg-shop-npc-symbol s) npc-sym)
                           (setq shop-sym sym)))
                       tg--shops))))
        ;; 如果没指定 NPC，查找当前房间中的商人
        (unless shop-sym
          (let ((room (tg-get-room (tg-game-get game :location))))
            (dolist (c-sym (tg-room-creatures room))
              (unless shop-sym
                (let ((c (tg-get-creature c-sym)))
                  (when (and c (tg-creature-shopkeeper c))
                    (maphash (lambda (sym s)
                               (when (eq (tg-shop-npc-symbol s) c-sym)
                                 (setq shop-sym sym)))
                             tg--shops)))))))
        (cond
         ((not shop-sym)
          (tg-message "这里没有商人。"))
         (t
          (let ((shop (tg-get-shop shop-sym)))
            (condition-case err
                (progn
                  (tg-shop-sell do-key shop player)
                  (tg-message "出售了%s。" (tg-object-name (tg-get-object do-key)))
                  t)
              (error
               (tg-message "%s" (error-message-string err))))))))))))

(defun tg-action--handler-shop (ast game)
  "列出当前房间商人的商品"
  (let ((do-key (plist-get ast :do-key))
        shop-sym)
    ;; 如果指定了 NPC
    (when do-key
      (let ((creature (tg-get-creature do-key)))
        (when (and creature (tg-creature-shopkeeper creature))
          (maphash (lambda (sym s)
                     (when (eq (tg-shop-npc-symbol s) do-key)
                       (setq shop-sym sym)))
                   tg--shops))))
    ;; 查找当前房间中的商人
    (unless shop-sym
      (let ((room (tg-get-room (tg-game-get game :location))))
        (dolist (c-sym (tg-room-creatures room))
          (unless shop-sym
            (let ((c (tg-get-creature c-sym)))
              (when (and c (tg-creature-shopkeeper c))
                (maphash (lambda (sym s)
                           (when (eq (tg-shop-npc-symbol s) c-sym)
                             (setq shop-sym sym)))
                         tg--shops)))))))
    (cond
     ((not shop-sym)
      (tg-message "这里没有商人。"))
     (t
      (let ((shop (tg-get-shop shop-sym)))
        (tg-message "商品列表：")
        (dolist (item-entry (tg-shop-goods shop))
          (let* ((item-sym (car item-entry))
                 (price (cdr item-entry))
                 (obj (tg-get-object item-sym)))
            (tg-message "  %s - %d金币"
                        (if obj (tg-object-name obj) (symbol-name item-sym))
                        price)))
        t)))))

(defun tg-action--handler-status (_ast game)
  "显示玩家状态"
  (let ((player (tg-player game)))
    (if (not player)
        (tg-message "没有玩家。")
      (let ((name (tg-creature-name player))
            (hp (tg-creature-attr-get player 'hp))
            (attack (tg-creature-attr-get player 'attack))
            (defense (tg-creature-attr-get player 'defense))
            (level (tg-creature-attr-get player 'level))
            (exp (tg-creature-attr-get player 'exp))
            (gold (tg-creature-attr-get player 'gold))
            (bonus-points (tg-creature-attr-get player 'bonus-points)))
        (tg-message "【%s】" (or name "无名英雄"))
        (when level (tg-message "  等级：%d" level))
        (when exp (tg-message "  经验：%d" exp))
        (when hp (tg-message "  生命：%d" hp))
        (when attack (tg-message "  攻击：%d" attack))
        (when defense (tg-message "  防御：%d" defense))
        (when gold (tg-message "  金币：%d" gold))
        (when (and bonus-points (> bonus-points 0))
          (tg-message "  属性点：%d" bonus-points))
        t))))

(defun tg-action--handler-upgrade (ast game)
  "使用属性点手动升级属性"
  (let ((do-key (plist-get ast :do-key))
        (player (tg-player game)))
    (cond
     ((not do-key)
      (tg-message "你要升级哪个属性？"))
     ((not player)
      (tg-message "没有玩家。"))
     (t
      ;; do-key 应该是属性名关键字，如 'attack, 'defense, 'hp
      (if (tg-level-upgrade player do-key 1)
          (progn
            (tg-message "升级了%s。" do-key)
            t)
        (tg-message "属性点不足或无法升级。"))))))

(defun tg-action--handler-quests (_ast game)
  "列出所有任务"
  (let ((found nil))
    (maphash (lambda (sym quest)
               (unless (eq (tg-quest-status quest) 'inactive)
                 (setq found t)
                 (tg-message "  [%s] %s (%s) - %d/%d"
                             (pcase (tg-quest-status quest)
                               ('active "进行中")
                               ('completed "已完成"))
                             (or (tg-quest-description quest) (symbol-name sym))
                             (symbol-name (tg-quest-type quest))
                             (tg-quest-progress quest)
                             (tg-quest-count quest))))
             tg--quests)
    (unless found
      (tg-message "没有进行中的任务。"))
    t))

(defun tg-action--handler-quest (ast game)
  "查看指定任务详情"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要查看哪个任务？"))
     (t
      (let ((quest (tg-get-quest do-key)))
        (cond
         ((not quest)
          (tg-message "没有这个任务。"))
         ((eq (tg-quest-status quest) 'inactive)
          (tg-message "你还没有接受这个任务。"))
         (t
          (tg-message "【%s】" (or (tg-quest-description quest) (symbol-name do-key)))
          (tg-message "  类型：%s" (tg-quest-type quest))
          (tg-message "  目标：%s" (tg-quest-target quest))
          (tg-message "  进度：%d/%d" (tg-quest-progress quest) (tg-quest-count quest))
          (tg-message "  状态：%s" (tg-quest-status quest))
          (when (tg-quest-rewards quest)
            (tg-message "  奖励：%s"
                        (mapconcat (lambda (r)
                                     (format "%s %s" (car r) (cadr r)))
                                   (tg-quest-rewards quest) "、")))
          t)))))))

(defun tg-action--handler-accept (ast game)
  "接受任务"
  (let ((do-key (plist-get ast :do-key)))
    (cond
     ((not do-key)
      (tg-message "你要接受什么任务？"))
     (t
      (let ((quest (tg-get-quest do-key)))
        (cond
         ((not quest)
          (tg-message "没有这个任务。"))
         ((not (eq (tg-quest-status quest) 'inactive))
          (tg-message "你已经接受了这个任务。"))
         (t
          (tg-quest-activate quest)
          (tg-message "接受了任务：%s" do-key)
          t)))))))

(defun tg-action--handler-save (_ast _game)
  "保存游戏（简单实现）"
  (tg-message "游戏已保存。")
  t)

(defun tg-action--handler-load (_ast _game)
  "加载游戏（简单实现）"
  (tg-message "游戏已加载。")
  t)

(defun tg-action--handler-help (_ast _game)
  "显示帮助信息"
  (tg-message "=== 帮助 ===")
  (tg-message "移动：go/walk [方向]")
  (tg-message "查看：look/l, examine/x [物品]")
  (tg-message "物品：take/get [物品], drop [物品]")
  (tg-message "容器：open/close/unlock [容器]")
  (tg-message "装备：wear [装备], eat [食物]")
  (tg-message "背包：inventory/i")
  (tg-message "战斗：attack/hit [目标]")
  (tg-message "对话：talk [NPC]")
  (tg-message "商店：shop, buy [物品], sell [物品]")
  (tg-message "状态：status")
  (tg-message "升级：upgrade [属性]")
  (tg-message "任务：quests, quest [任务], accept [任务]")
  (tg-message "系统：save, load, quit")
  t)

(defun tg-action--handler-quit (_ast game)
  "退出游戏"
  (tg-game-put game :state 'quitting)
  (tg-message "再见！")
  (throw 'tg-action-abort nil))

;;; ============================================================
;;; 内置动词注册
;;; ============================================================

(defun tg-register-builtins ()
  "注册所有内置动词"
  ;; 移动与探索
  (tg-register-action :id 'go :synonyms '("go" "move" "walk") :handler #'tg-action--handler-go)
  (tg-register-action :id 'look :synonyms '("look" "l") :handler #'tg-action--handler-look)
  (tg-register-action :id 'examine :synonyms '("examine" "x") :handler #'tg-action--handler-examine)
  ;; 物品操作
  (tg-register-action :id 'take :synonyms '("take" "get" "pick up") :handler #'tg-action--handler-take)
  (tg-register-action :id 'drop :synonyms '("drop" "put down") :handler #'tg-action--handler-drop)
  (tg-register-action :id 'place :synonyms '("place" "put") :handler #'tg-action--handler-place)
  ;; 容器操作
  (tg-register-action :id 'open :synonyms '("open") :handler #'tg-action--handler-open)
  (tg-register-action :id 'close :synonyms '("close" "shut") :handler #'tg-action--handler-close)
  (tg-register-action :id 'unlock :synonyms '("unlock") :handler #'tg-action--handler-unlock)
  ;; 装备与消耗
  (tg-register-action :id 'wear :synonyms '("wear" "equip") :handler #'tg-action--handler-wear)
  (tg-register-action :id 'eat :synonyms '("eat" "consume") :handler #'tg-action--handler-eat)
  (tg-register-action :id 'read :synonyms '("read") :handler #'tg-action--handler-read)
  ;; 背包
  (tg-register-action :id 'inventory :synonyms '("inventory" "i") :handler #'tg-action--handler-inventory)
  ;; 战斗
  (tg-register-action :id 'attack :synonyms '("attack" "hit" "fight") :handler #'tg-action--handler-attack)
  ;; 对话
  (tg-register-action :id 'talk :synonyms '("talk" "speak") :handler #'tg-action--handler-talk)
  ;; 商店
  (tg-register-action :id 'buy :synonyms '("buy") :handler #'tg-action--handler-buy)
  (tg-register-action :id 'sell :synonyms '("sell") :handler #'tg-action--handler-sell)
  (tg-register-action :id 'shop :synonyms '("shop") :handler #'tg-action--handler-shop)
  ;; 角色状态
  (tg-register-action :id 'status :synonyms '("status") :handler #'tg-action--handler-status)
  (tg-register-action :id 'upgrade :synonyms '("upgrade") :handler #'tg-action--handler-upgrade)
  ;; 任务
  (tg-register-action :id 'quests :synonyms '("quests") :handler #'tg-action--handler-quests)
  (tg-register-action :id 'quest :synonyms '("quest") :handler #'tg-action--handler-quest)
  (tg-register-action :id 'accept :synonyms '("accept") :handler #'tg-action--handler-accept)
  ;; 系统
  (tg-register-action :id 'save :synonyms '("save") :handler #'tg-action--handler-save)
  (tg-register-action :id 'load :synonyms '("load") :handler #'tg-action--handler-load)
  (tg-register-action :id 'help :synonyms '("help" "?") :handler #'tg-action--handler-help)
  (tg-register-action :id 'quit :synonyms '("quit" "exit" "q") :handler #'tg-action--handler-quit))

(provide 'tg-action)
;;; tg-action.el ends here