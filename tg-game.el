;;; tg-game.el --- 游戏动态状态  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)

;;; 当前游戏状态

(defvar tg-game nil
  "当前游戏动态状态哈希表")

;;; 游戏初始化

(defun tg-new-game (title author)
  "创建新游戏哈希表
初始键：:title, :author, :state('starting), :turns(0), :location(nil), :player(nil), :active-buffs(nil)"
  (let ((game (make-hash-table :test 'eq)))
    (puthash :title title game)
    (puthash :author author game)
    (puthash :state 'starting game)
    (puthash :turns 0 game)
    (puthash :location nil game)
    (puthash :player nil game)
    (puthash :active-buffs nil game)
    game))

;;; 游戏状态读写

(defun tg-game-get (game key)
  "从游戏哈希表获取值"
  (gethash key game))

(defun tg-game-put (game key value)
  "向游戏哈希表设置值"
  (puthash key value game)
  value)

(defun tg-game-incf (game key)
  "递增游戏哈希表中指定键的数值"
  (let ((current (tg-game-get game key)))
    (puthash key (1+ current) game)))

;;; 玩家访问

(defun tg-player (game)
  "获取当前玩家 creature 结构
从 tg-game 的 :player 键获取 symbol，再通过 tg-get-creature 获取结构"
  (let ((player-sym (tg-game-get game :player)))
    (when player-sym
      (tg-get-creature player-sym))))

;;; Buff 系统

(defun tg-buffs-tick (game)
  "回合结束时递减所有临时效果的剩余回合，移除过期效果
active-buffs 格式：((attr (:delta value :remaining N :duration N)) ...)
- 对所有 buff 的 :remaining 减 1
- 移除 remaining < 0 的 buff（remaining = 0 表示本回合有效，下回合过期）"
  (let ((buffs (tg-game-get game :active-buffs)))
    ;; 先递减所有 remaining
    (dolist (buff buffs)
      (let ((plist (cdr buff)))  ; 格式是 (attr . plist)，用 cdr 获取
        (let ((remaining (plist-get plist :remaining)))
          (when (numberp remaining)
            (plist-put plist :remaining (1- remaining))))))
    ;; 过滤掉 remaining < 0 的 buff
    (tg-game-put game :active-buffs
                 (cl-remove-if (lambda (buff)
                                 (let ((plist (cdr buff)))
                                   (let ((remaining (plist-get plist :remaining)))
                                     (and (numberp remaining) (< remaining 0)))))
                               buffs))))

(defun tg-buffs-apply (game effects)
  "应用效果列表到玩家
永久效果：直接写 player attr（通过 tg-creature-take-effect）
临时效果（有 :duration）：进入 :active-buffs

effects 格式：((attr value) (attr value :duration N) ...)"
  (let ((player (tg-player game)))
    (unless player
      (error "No player in game"))
    (dolist (effect effects)
      (let* ((attr (car effect))
             (value (cadr effect))
             (duration (plist-get (cddr effect) :duration)))
        (if duration
            ;; 临时效果：加入 active-buffs
            ;; 格式是 (attr . plist)，alist 的标准格式
            (let* ((buffs (tg-game-get game :active-buffs))
                   (existing (assq attr buffs)))
              (if existing
                  ;; 已有同属性 buff，更新 delta
                  ;; 用 cdr 获取 plist
                  (let ((plist (cdr existing)))
                    (plist-put plist :delta
                              (+ (or (plist-get plist :delta) 0) value))
                    (plist-put plist :remaining duration)
                    (plist-put plist :duration duration))
                ;; 新 buff，用 cons 创建 (attr . plist)
                (tg-game-put game :active-buffs
                             (append buffs
                                     (list (cons attr
                                                 (list :delta value
                                                       :remaining duration
                                                       :duration duration)))))))
          ;; 永久效果：直接应用到 player
          ;; tg-creature-take-effect 期望 (attr delta) 列表格式
          (tg-creature-take-effect player (list attr value)))))))

;;; 存档快照

(defun tg-game-snapshot (game)
  "返回游戏动态状态的 alist"
  (list (cons :location (tg-game-get game :location))
        (cons :turns (tg-game-get game :turns))
        (cons :state (tg-game-get game :state))
        (cons :active-buffs (tg-game-get game :active-buffs))
        (cons :player (tg-game-get game :player))
        (cons :respawn-queue (tg-game-get game :respawn-queue))))

(defun tg-game-restore-snapshot (game snapshot)
  "从 SNAPSHOT 恢复游戏动态状态"
  (tg-game-put game :location (cdr (assq :location snapshot)))
  (tg-game-put game :turns (cdr (assq :turns snapshot)))
  (tg-game-put game :state (cdr (assq :state snapshot)))
  (tg-game-put game :active-buffs (cdr (assq :active-buffs snapshot)))
  (tg-game-put game :player (cdr (assq :player snapshot)))
  (tg-game-put game :respawn-queue (cdr (assq :respawn-queue snapshot))))

(provide 'tg-game)
;;; tg-game.el ends here
