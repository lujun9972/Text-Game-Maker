;;; tg-respawn.el --- 生物刷新系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-creature)
(require 'tg-room)

(defvar tg-respawn-default-interval nil
  "默认刷新区间 (min . max) 或 nil（不刷新）")

(defun tg-respawn-schedule (creature-symbol)
  "死亡时调用，将 creature 加入刷新队列。
通过全局 tg-game 访问游戏状态。"
  (let ((creature (tg-get-creature creature-symbol)))
    (when (and creature
               (tg-creature-dead-p creature)  ;; 只调度已死亡的
               (tg-creature-respawn-interval creature)  ;; 有刷新配置
               (not (tg-creature-shopkeeper creature))   ;; 非 shopkeeper
               (not (assq creature-symbol (tg-game-get tg-game :respawn-queue)))) ;; 防重复
      (let* ((interval (tg-creature-respawn-interval creature))
             (min-val (car interval))
             (max-val (cdr interval))
             (random-offset (+ min-val (random (1+ (- max-val min-val)))))
             (current-turn (or (tg-game-get tg-game :turns) 0))
             (respawn-turn (+ current-turn random-offset))
             (queue (tg-game-get tg-game :respawn-queue)))
        (tg-game-put tg-game :respawn-queue
                     (append queue (list (cons creature-symbol respawn-turn))))))))

(defun tg-respawn-tick (game)
  "每回合调用，检查并执行到期的刷新。
GAME: 游戏状态哈希表"
  (let* ((current-turn (tg-game-get game :turns))
         (queue (tg-game-get game :respawn-queue))
         (remaining nil))
    (dolist (entry queue)
      (if (<= (cdr entry) current-turn)
          (tg-respawn-restore (car entry))
        (push entry remaining)))
    (tg-game-put game :respawn-queue (nreverse remaining))))

(defun tg-respawn-restore (creature-symbol)
  "恢复 creature 到初始状态。
通过全局 tg-game 访问游戏状态。
tg-message 运行时可用（不 require tg-commands 避免循环依赖）。"
  (let ((creature (tg-get-creature creature-symbol)))
    (when (and creature (tg-creature-p creature))  ;; 必须是 creature struct
      ;; 恢复 attr（copy-tree 深拷贝）
      (when (tg-creature-initial-attr creature)
        (setf (tg-creature-attr creature)
              (copy-tree (tg-creature-initial-attr creature))))
      ;; 恢复 inventory（copy-sequence，元素是 symbol/immutable；若变为 mutable struct 需升级为 copy-tree）
      (when (tg-creature-initial-inventory creature)
        (setf (tg-creature-inventory creature)
              (copy-sequence (tg-creature-initial-inventory creature))))
      ;; 恢复 equipment
      (when (tg-creature-initial-equipment creature)
        (setf (tg-creature-equipment creature)
              (copy-sequence (tg-creature-initial-equipment creature))))
      ;; 同房间通知
      (let ((current-room-sym (tg-game-get tg-game :location)))
        (when current-room-sym
          (let ((room (tg-get-room current-room-sym)))
            (when (and room (memq creature-symbol (tg-room-creatures room)))
              (tg-message "%s从地上爬了起来！" (tg-creature-name creature)))))))))

(provide 'tg-respawn)
;;; tg-respawn.el ends here
