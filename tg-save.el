;;; tg-save.el --- 存档系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-quest)
(require 'tg-config)

;;; 收集动态状态（通过各模块的 snapshot 接口）

(defun tg-save--collect-entities (get-fn snapshot-fn table)
  "遍历注册表 TABLE，对每个实体调用 SNAPSHOT-FN 收集快照。
GET-FN: 从注册表获取实体的函数（用于 restore）
SNAPSHOT-FN: 获取快照的函数"
  (let (result)
    (maphash
     (lambda (sym entity)
       (push (cons sym (funcall snapshot-fn entity)) result))
     table)
    result))

;;; 恢复动态状态（通过各模块的 restore-snapshot 接口）

(defun tg-save--restore-entities (data-key data get-fn restore-fn)
  "从存档数据恢复实体状态。
DATA-KEY: 存档中的键（如 :rooms）
DATA: 完整存档数据
GET-FN: 从注册表获取实体的函数
RESTORE-FN: 恢复快照的函数"
  (let ((entries (cdr (assq data-key data))))
    (dolist (entry entries)
      (let ((entity (funcall get-fn (car entry)))
            (snapshot (cdr entry)))
        (when entity
          (funcall restore-fn entity snapshot))))))

;;; 公开 API

(defun tg-save-game (file-path)
  "收集游戏动态状态并序列化到文件。
通过各模块的 snapshot 接口收集，不直接访问结构体字段。"
  (let ((save-data (list (cons :game (tg-game-snapshot tg-game))
                         (cons :rooms (tg-save--collect-entities #'tg-get-room #'tg-room-snapshot tg--rooms))
                         (cons :objects (tg-save--collect-entities #'tg-get-object #'tg-object-snapshot tg--objects))
                         (cons :creatures (tg-save--collect-entities #'tg-get-creature #'tg-creature-snapshot tg--creatures))
                         (cons :quests (tg-save--collect-entities #'tg-get-quest #'tg-quest-snapshot tg--quests)))))
    (let ((dir (file-name-directory file-path)))
      (when (and dir (not (file-directory-p dir)))
        (make-directory dir t)))
    (with-temp-file file-path
      (let (print-level print-length)
        (prin1 save-data (current-buffer))))))

(defun tg-load-game (file-path config-dir)
  "从文件恢复游戏状态。
1. read 存档文件
2. 从 config-dir 重载配置（重建基础结构）
3. 通过各模块的 restore-snapshot 接口恢复动态字段"
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
    ;; 通过 snapshot 接口恢复动态字段
    (tg-game-restore-snapshot tg-game (cdr (assq :game data)))
    (tg-save--restore-entities :rooms data #'tg-get-room #'tg-room-restore-snapshot)
    (tg-save--restore-entities :objects data #'tg-get-object #'tg-object-restore-snapshot)
    (tg-save--restore-entities :creatures data #'tg-get-creature #'tg-creature-restore-snapshot)
    (tg-save--restore-entities :quests data #'tg-get-quest #'tg-quest-restore-snapshot)))

(provide 'tg-save)
;;; tg-save.el ends here
