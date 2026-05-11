;;; tg-npc.el --- NPC 行为引擎  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-room)
(require 'tg-game)

;;; Condition 求值

(defun tg-npc-eval-condition (creature condition)
  "评估 CREATURE 的 CONDITION 是否满足
CONDITION 格式：
- always → 永远为真
- (hp-below N) → hp < N
- (hp-above N) → hp > N
- (player-in-room) → 玩家在同一房间
- (and ...) → 所有条件都满足
- (or ...) → 任一条件满足
- (not cond) → 条件不满足"
  (pcase condition
    ((or 'always '(always)) t)
    (`(hp-below ,n)
     (let ((hp (tg-creature-attr-get creature 'hp)))
       (< hp n)))
    (`(hp-above ,n)
     (let ((hp (tg-creature-attr-get creature 'hp)))
       (> hp n)))
    (`(player-in-room)
     (let* ((game tg-game)
            (location (tg-game-get game :location))
            (room (tg-get-room location)))
       (when room
         (memq (tg-creature-symbol creature) (tg-room-creatures room)))))
    (`(and . ,conds)
     (cl-every (lambda (c) (tg-npc-eval-condition creature c)) conds))
    (`(or . ,conds)
     (cl-some (lambda (c) (tg-npc-eval-condition creature c)) conds))
    (`(not ,cond)
     (not (tg-npc-eval-condition creature cond)))))

;;; Action 执行

(defun tg-npc-execute-action (creature action)
  "执行 CREATURE 的 ACTION
ACTION 格式：
- (attack) → 攻击玩家（伤害 = npc-attack - player-defense）
- (say text) → 输出文本
- (move direction) → NPC 移动到相邻房间
- (buff attr value) → 增加自身属性
- (debuff attr value) → 减少玩家属性

返回输出字符串（如果有）"
  (pcase action
    (`(attack)
     (let* ((game tg-game)
            (player (tg-player game))
            (attack (tg-creature-attr-get creature 'attack))
            (defense (tg-creature-attr-get player 'defense))
            (damage (max 0 (- attack defense))))
       (tg-creature-take-effect player (list 'hp (- damage)))
       (format "%s 攻击了你，造成 %d 点伤害！"
               (tg-creature-name creature) damage)))
    (`(say ,text)
     text)
    (`(move ,direction)
     (let* ((game tg-game)
            (location (tg-game-get game :location))
            (room (tg-get-room location)))
       (when room
         (let ((target-room-sym (tg-room-exit room direction)))
           (when target-room-sym
             (let ((target-room (tg-get-room target-room-sym)))
               (when target-room
                 ;; 从当前房间移除
                 (tg-room-remove-creature room (tg-creature-symbol creature))
                 ;; 添加到目标房间
                 (tg-room-add-creature target-room (tg-creature-symbol creature))
                 (format "%s 向 %s 移动了。"
                         (tg-creature-name creature) direction))))))))
    (`(buff ,attr ,value)
     (tg-creature-take-effect creature (list attr value))
     nil)
    (`(debuff ,attr ,value)
     (let* ((game tg-game)
            (player (tg-player game)))
       (tg-creature-take-effect player (list attr (- value)))
       nil))
    (_
     (error "Unknown action: %S" action))))

;;; 行为运行

(defun tg-npc-run-behaviors (game)
  "运行当前房间所有 NPC 的行为
遍历当前房间的 creatures：
- 排除玩家
- 排除死亡 NPC
- 每个 NPC 执行第一条匹配的 behavior rule

返回组合的输出字符串（如果有）"
  (let* ((location (tg-game-get game :location))
         (room (tg-get-room location))
         (outputs '()))
    (when room
      (let* ((creatures (tg-room-creatures room))
             (player-sym (tg-game-get game :player)))
        (dolist (creature-sym creatures)
          (unless (eq creature-sym player-sym)
            (let ((creature (tg-get-creature creature-sym)))
              (when (and creature
                         (not (tg-creature-dead-p creature)))
                (let ((behaviors (tg-creature-behaviors creature)))
                  (catch 'found
                    (dolist (rule behaviors)
                      (let ((condition (car rule))
                            (action (cdr rule)))
                        (when (tg-npc-eval-condition creature condition)
                          (let ((output (tg-npc-execute-action creature action)))
                            (when output
                              (push output outputs)))
                          (throw 'found nil))))))))))))
    (when outputs
      (mapconcat 'identity (nreverse outputs) "\n"))))

(provide 'tg-npc)
;;; tg-npc.el ends here
