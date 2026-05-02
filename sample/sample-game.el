;;; sample-game.el --- Sample dungeon adventure game  -*- lexical-binding: t; -*-

;; 启动地牢冒险示例游戏
;; 使用方法: M-x eval-buffer 然后 M-x play-sample-game

(require 'text-game-maker)

(defvar sample-game-dir nil
  "Sample game config files directory.")
(setq sample-game-dir (file-name-directory (or load-file-name buffer-file-name)))

(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((sample-dir sample-game-dir))
    (map-init (expand-file-name "room-config.el" sample-dir)
              (expand-file-name "map-config.el" sample-dir))
    (inventorys-init (expand-file-name "inventory-config.el" sample-dir))
    (creatures-init (expand-file-name "creature-config.el" sample-dir))
    (level-init (expand-file-name "level-config.el" sample-dir))
    (quest-init (expand-file-name "quest-config.el" sample-dir))
    (dialog-init (expand-file-name "dialog-config.el" sample-dir))
    (shop-init (expand-file-name "shop-config.el" sample-dir))
    (setq player-gold 20)
    (tg-mode)
    (tg-display (tg-prompt-string))
    (tg-display (describe current-room))
    (tg-display "\n=== 地牢冒险 ===")
    (tg-display "你被困在了地下城中！探索房间，收集装备，击败怪物，找到出口！")
    (tg-display "输入 help 查看可用命令。")
    (tg-display "升级提示: 击败怪物获得经验值，升级后用 upgrade <属性> <点数> 分配技能点！")
    (tg-display "存档提示: 使用 save <名称> 保存进度，load <名称> 恢复进度！")
    (tg-display "战斗提示: 先去走廊和武器库收集装备，再去挑战骷髅王！")
    (tg-display "任务提示: 输入 quests 查看任务列表，quest <名称> 查看详情，accept <名称> 接受任务！")
    (tg-display "对话提示: 输入 talk <NPC名称> 与NPC对话！")
    (tg-display "商店提示: 输入 shop 查看商品，buy <物品> 购买，sell <物品> 出售！")
    (tg-display "")
    (tg-messages)))

(provide 'sample-game)
