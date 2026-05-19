;;; tg-combat.el --- 战斗结算系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-creature)
(require 'tg-object)
(require 'tg-room)
(require 'tg-quest)
(require 'tg-respawn)

;;; 伤害计算

(defun tg-combat-calculate-damage (attacker-attr defender-defense)
  "计算伤害值。
ATTACKER-ATTR: 攻击方的攻击力数值
DEFENDER-DEFENSE: 防御方的防御力数值（可为 nil）
返回：至少为 1 的伤害值"
  (max 1 (- attacker-attr (or defender-defense 0))))

;;; 死亡处理

(defun tg-combat-handle-death (creature-sym player game)
  "处理 NPC 死亡：掉落物品、经验奖励、任务追踪、死亡触发器、刷新调度。
CREATURE-SYM: 死亡 NPC 的 symbol
PLAYER: 玩家 creature 结构
GAME: 游戏状态哈希表"
  (let ((creature (tg-get-creature creature-sym))
        (room (tg-get-room (tg-game-get game :location))))
    (tg-message "%s被击败了！" (tg-creature-name creature))
    ;; 掉落物品（背包 + 装备，含 no-drop 过滤）
    (let ((all-items (append (tg-creature-inventory creature)
                             (tg-creature-equipment creature)))
          (remaining-items nil))
      (dolist (item-sym all-items)
        (let ((obj (tg-get-object item-sym)))
          (if (and obj (memq 'no-drop (tg-object-props obj)))
              (push item-sym remaining-items)
            (tg-room-add-object room item-sym)
            (tg-message "%s掉落了%s。"
                        (tg-creature-name creature)
                        (tg-object-name obj)))))
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
    (tg-track-quest 'kill creature-sym)
    ;; 触发死亡触发器
    (let ((death-trigger (tg-creature-death-trigger creature)))
      (when (and death-trigger (functionp death-trigger))
        (funcall death-trigger creature game)))
    ;; 触发刷新调度
    (tg-respawn-schedule creature-sym)))

;;; 反击

(defun tg-combat-counter-attack (creature player game active-buffs)
  "NPC 反击玩家。
CREATURE: NPC creature 结构
PLAYER: 玩家 creature 结构
GAME: 游戏状态哈希表
ACTIVE-BUFFS: 当前激活的 buff 列表"
  (let* ((npc-attack (tg-creature-attr-get creature 'attack))
         (player-defense (tg-creature-effective-attr player 'defense active-buffs))
         (counter-damage (max 0 (- (or npc-attack 0) player-defense))))
    (when (> counter-damage 0)
      (tg-creature-take-effect player (list 'hp (- counter-damage)))
      (tg-message "%s反击了你，造成了%d点伤害。"
                  (tg-creature-name creature) counter-damage))
    ;; 检查玩家是否死亡
    (when (tg-creature-dead-p player)
      (tg-message "你被%s击败了！游戏结束。" (tg-creature-name creature))
      (tg-game-put game :state 'game-over))))

;;; 战斗编排

(defun tg-combat-resolve (creature-sym player game)
  "执行完整的战斗结算。
CREATURE-SYM: 目标 NPC 的 symbol
PLAYER: 玩家 creature 结构
GAME: 游戏状态哈希表"
  (let* ((creature (tg-get-creature creature-sym))
         (active-buffs (tg-game-get game :active-buffs))
         (player-attack (tg-creature-effective-attr player 'attack active-buffs))
         (npc-defense (tg-creature-attr-get creature 'defense))
         (damage (tg-combat-calculate-damage player-attack npc-defense)))
    ;; 对 NPC 造成伤害
    (tg-creature-take-effect creature (list 'hp (- damage)))
    (tg-message "你攻击了%s，造成了%d点伤害。"
                (tg-creature-name creature) damage)
    ;; 死亡 or 反击
    (if (tg-creature-dead-p creature)
        (tg-combat-handle-death creature-sym player game)
      (tg-combat-counter-attack creature player game active-buffs))
    t))

(provide 'tg-combat)
;;; tg-combat.el ends here
