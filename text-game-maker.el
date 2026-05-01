;;; text-game-maker.el --- Main entry for Text-Game-Maker  -*- lexical-binding: t; -*-

(defun file-content(file)
  "返回file的文件内容"
  (with-temp-buffer
	(insert-file-contents file)
	(buffer-string)))
(require 'tg-mode)
(defvar display-fn #'tg-mprinc
  "显示信息的函数")
(defun tg-display (&rest args)
  (apply display-fn args))
(require 'room-maker)
(require 'inventory-maker)
(require 'creature-maker)
(require 'action)
(require 'tg-config-generator)
(require 'level-system)
(require 'npc-behavior)


(provide 'text-game-maker)
