;;; tg.el --- Text Game Maker 2.0 入口  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 2.0
;; Keywords: games, text

;;; Commentary:
;; Text Game Maker 入口模块。
;; 加载所有子模块，提供 tg-init 和 tg-start 公开接口。

;;; Code:

(require 'tg-registry)
(require 'tg-game)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-room)
(require 'tg-action)
(require 'tg-parser)
(require 'tg-commands)
(require 'tg-dialog)
(require 'tg-npc)
(require 'tg-quest)
(require 'tg-shop)
(require 'tg-level)
(require 'tg-save)
(require 'tg-config)
(require 'tg-config-gen)
(require 'tg-mode)

(defun tg-init (org-config-file)
  "从 ORG-CONFIG-FILE 加载游戏配置并初始化。
加载 Org 配置、注册内置动词，返回游戏状态。"
  (tg-registry-clear)
  (setq tg-game (tg-config-load org-config-file))
  (tg-register-builtins)
  tg-game)

;;;###autoload
(defun tg-start (org-config-file)
  "加载配置并启动游戏 UI。
ORG-CONFIG-FILE: 游戏 Org 配置文件路径"
  (interactive "f游戏配置 (Org 文件): ")
  (let ((game (tg-init org-config-file)))
    (tg-game-put game :state 'in-progress)
    (switch-to-buffer
     (get-buffer-create (format "*TG: %s*" (or (tg-game-get game :title) "Game"))))
    (tg-mode)
    ;; 设置输出目标
    (setq tg-output-buffer (current-buffer))
    ;; 显示初始房间描述
    (let* ((location (tg-game-get game :location))
           (room (tg-get-room location)))
      (when room
        (tg-room-visit room)
        (tg-message "%s" (tg-room-describe room))))
    (tg-render-prompt)))

(provide 'tg)
;;; tg.el ends here
