;;; tg-save.el --- 存档系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-quest)
(require 'tg-config)

;;; 收集动态状态

(defun tg-save--collect-game-state ()
  "收集 game 哈希表中的动态字段"
  (list :location (tg-game-get tg-game :location)
        :turns (tg-game-get tg-game :turns)
        :state (tg-game-get tg-game :state)
        :active-buffs (tg-game-get tg-game :active-buffs)
        :player (tg-game-get tg-game :player)
        :respawn-queue (tg-game-get tg-game :respawn-queue)))

(defun tg-save--collect-rooms ()
  "遍历 tg--rooms 哈希表，收集每个房间的动态字段"
  (let (result)
    (maphash
     (lambda (sym room)
       (push (cons sym (list (cons :visit-count (tg-room-visit-count room))
                             (cons :contents (tg-room-contents room))
                             (cons :creatures (tg-room-creatures room))))
             result))
     tg--rooms)
    result))

(defun tg-save--collect-objects ()
  "遍历 tg--objects 哈希表，收集每个对象的动态字段"
  (let (result)
    (maphash
     (lambda (sym obj)
       (push (cons sym (list (cons :state (tg-object-state obj))
                             (cons :contents (tg-object-contents obj))
                             (cons :supports (tg-object-supports obj))))
             result))
     tg--objects)
    result))

(defun tg-save--collect-creatures ()
  "遍历 tg--creatures 哈希表，收集每个生物的动态字段"
  (let (result)
    (maphash
     (lambda (sym creature)
       (push (cons sym (list (cons :attr (tg-creature-attr creature))
                             (cons :inventory (tg-creature-inventory creature))
                             (cons :equipment (tg-creature-equipment creature))))
             result))
     tg--creatures)
    result))

(defun tg-save--collect-quests ()
  "遍历 tg--quests 哈希表，收集每个任务的动态字段"
  (let (result)
    (maphash
     (lambda (sym quest)
       (push (cons sym (list (cons :status (tg-quest-status quest))
                             (cons :progress (tg-quest-progress quest))))
             result))
     tg--quests)
    result))

;;; 恢复动态状态

(defun tg-save--restore-game-state (data)
  "从存档数据恢复 game 动态字段"
  (let ((game-data (cdr (assq :game data))))
    (tg-game-put tg-game :location (plist-get game-data :location))
    (tg-game-put tg-game :turns (plist-get game-data :turns))
    (tg-game-put tg-game :state (plist-get game-data :state))
    (tg-game-put tg-game :active-buffs (plist-get game-data :active-buffs))
    (tg-game-put tg-game :player (plist-get game-data :player))
    (tg-game-put tg-game :respawn-queue (plist-get game-data :respawn-queue))))

(defun tg-save--restore-rooms (data)
  "从存档数据恢复房间动态字段"
  (let ((rooms-data (cdr (assq :rooms data))))
    (dolist (entry rooms-data)
      (let ((room (tg-get-room (car entry)))
            (state (cdr entry)))
        (when room
          (setf (tg-room-visit-count room) (cdr (assq :visit-count state)))
          (setf (tg-room-contents room) (cdr (assq :contents state)))
          (setf (tg-room-creatures room) (cdr (assq :creatures state))))))))

(defun tg-save--restore-objects (data)
  "从存档数据恢复对象动态字段"
  (let ((objects-data (cdr (assq :objects data))))
    (dolist (entry objects-data)
      (let ((obj (tg-get-object (car entry)))
            (state (cdr entry)))
        (when obj
          (setf (tg-object-state obj) (cdr (assq :state state)))
          (setf (tg-object-contents obj) (cdr (assq :contents state)))
          (setf (tg-object-supports obj) (cdr (assq :supports state))))))))

(defun tg-save--restore-creatures (data)
  "从存档数据恢复生物动态字段"
  (let ((creatures-data (cdr (assq :creatures data))))
    (dolist (entry creatures-data)
      (let ((creature (tg-get-creature (car entry)))
            (state (cdr entry)))
        (when creature
          (setf (tg-creature-attr creature) (cdr (assq :attr state)))
          (setf (tg-creature-inventory creature) (cdr (assq :inventory state)))
          (setf (tg-creature-equipment creature) (cdr (assq :equipment state))))))))

(defun tg-save--restore-quests (data)
  "从存档数据恢复任务动态字段"
  (let ((quests-data (cdr (assq :quests data))))
    (dolist (entry quests-data)
      (let ((quest (tg-get-quest (car entry)))
            (state (cdr entry)))
        (when quest
          (setf (tg-quest-status quest) (cdr (assq :status state)))
          (setf (tg-quest-progress quest) (cdr (assq :progress state))))))))

;;; 公开 API

(defun tg-save-game (file-path)
  "收集游戏动态状态并序列化到文件

收集 game/rooms/objects/creatures/quests 的动态字段，
用 prin1 写入文件（Lisp 可读格式）。"
  (let ((save-data (list (cons :game (tg-save--collect-game-state))
                         (cons :rooms (tg-save--collect-rooms))
                         (cons :objects (tg-save--collect-objects))
                         (cons :creatures (tg-save--collect-creatures))
                         (cons :quests (tg-save--collect-quests)))))
    ;; 确保目录存在
    (let ((dir (file-name-directory file-path)))
      (when (and dir (not (file-directory-p dir)))
        (make-directory dir t)))
    (with-temp-file file-path
      (let (print-level print-length)
        (prin1 save-data (current-buffer))))))

(defun tg-load-game (file-path config-dir)
  "从文件恢复游戏状态

1. read 存档文件
2. 从 config-dir 调 tg-config-load 重载配置（重建基础结构）
3. 用存档数据覆盖动态字段"
  (unless (file-exists-p file-path)
    (error "存档文件不存在: %s" file-path))
  (let ((data (with-temp-buffer
                (insert-file-contents file-path)
                (goto-char (point-min))
                (read (current-buffer)))))
    ;; 重载配置以重建基础结构
    (let ((config-file (expand-file-name "game.org" config-dir)))
      (when (file-exists-p config-file)
        (setq tg-game (tg-config-load config-file))))
    ;; 用存档数据覆盖动态字段
    (tg-save--restore-game-state data)
    (tg-save--restore-rooms data)
    (tg-save--restore-objects data)
    (tg-save--restore-creatures data)
    (tg-save--restore-quests data)))

(provide 'tg-save)
;;; tg-save.el ends here
