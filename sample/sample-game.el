;;; sample-game.el --- Sample dungeon adventure game  -*- lexical-binding: t; -*-

;; 启动地牢冒险示例游戏
;; 使用方法: M-x eval-buffer 然后 M-x play-sample-game

(require 'text-game-maker)

(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((sample-dir (file-name-directory (or load-file-name buffer-file-name))))
    (map-init (expand-file-name "room-config.el" sample-dir)
              (expand-file-name "map-config.el" sample-dir))
    (inventorys-init (expand-file-name "inventory-config.el" sample-dir))
    (creatures-init (expand-file-name "creature-config.el" sample-dir))
    (tg-mode)
    (tg-display (tg-prompt-string))
    (tg-display (describe current-room))
    (tg-display "\n=== 地牢冒险 ===")
    (tg-display "你被困在了地下城中！探索房间，收集装备，击败怪物，找到出口！")
    (tg-display "输入 help 查看可用命令。")
    (tg-display "战斗提示: 先去走廊和武器库收集装备，再去挑战骷髅王！")
    (tg-display "")))

(provide 'sample-game)
