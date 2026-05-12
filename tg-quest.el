;;; tg-quest.el --- 任务系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-game)

;;; 任务结构

(cl-defstruct tg-quest
  symbol           ;; 唯一标识符
  type             ;; 任务类型：kill/collect/explore/talk
  target           ;; 目标 symbol
  count            ;; 目标数量
  progress         ;; 当前进度
  status           ;; 状态：inactive/active/completed
  rewards          ;; 奖励列表 ((exp N) (item sym) (bonus-points N) (trigger fn))
  description      ;; 任务描述文本 (string or nil)
  completion-text) ;; 完成时显示文本 (string or nil)

;;; 任务激活

(defun tg-quest-activate (quest)
  "将任务状态从 inactive 改为 active"
  (setf (tg-quest-status quest) 'active))

;;; 任务追踪

(defun tg-track-quest (type target-symbol)
  "追踪任务进度
遍历所有 active 的任务，按 type 和 target-symbol 匹配
如果匹配，增加 progress
如果 progress >= count，设置 status 为 completed 并发放奖励
已完成任务不重复追踪"
  (let ((game tg-game)
        (player (tg-player tg-game)))
    (unless player
      (error "No player in game"))
    ;; 遍历所有已注册的任务
    (maphash (lambda (_sym quest)
               (when (eq (tg-quest-status quest) 'active)
                 ;; 检查类型和目标是否匹配
                 (when (and (eq (tg-quest-type quest) type)
                            (eq (tg-quest-target quest) target-symbol))
                   ;; 增加进度
                   (let ((new-progress (1+ (tg-quest-progress quest))))
                     (setf (tg-quest-progress quest) new-progress)
                     ;; 检查是否完成
                     (when (>= new-progress (tg-quest-count quest))
                       ;; 标记为已完成
                       (setf (tg-quest-status quest) 'completed)
                       ;; 显示完成文本
                       (when (tg-quest-completion-text quest)
                         (tg-message "%s" (tg-quest-completion-text quest)))
                       ;; 发放奖励
                       (tg-quest--give-rewards quest game player))))))
             tg--quests)))

;;; 奖励发放

(defun tg-quest--give-rewards (quest game player)
  "发放任务奖励
- (exp N) → tg-creature-take-effect player (exp N)
- (item sym) → tg-creature-add-item player sym
- (bonus-points N) → tg-creature-take-effect player (bonus-points N)
- (trigger fn) → (funcall fn game)"
  (dolist (reward (tg-quest-rewards quest))
    (let ((type (car reward))
          (value (cadr reward)))
      (cond
       ;; 经验奖励
       ((eq type 'exp)
        (tg-creature-take-effect player (list 'exp value)))
       ;; 物品奖励
       ((eq type 'item)
        (tg-creature-add-item player value))
       ;; 属性点奖励
       ((eq type 'bonus-points)
        (tg-creature-take-effect player (list 'bonus-points value)))
       ;; 触发器奖励
       ((eq type 'trigger)
        (funcall value game))
       ;; 未知奖励类型
       (t
        (error "Unknown reward type: %s" type))))))

(provide 'tg-quest)
;;; tg-quest.el ends here
