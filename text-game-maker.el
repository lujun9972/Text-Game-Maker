;;; text-game-maker.el --- Main entry for Text-Game-Maker  -*- lexical-binding: t; -*-

(defun file-content(file)
  "返回file的文件内容"
  (with-temp-buffer
	(insert-file-contents file)
	(buffer-string)))

(defun tg-get-entity (alist symbol &optional no-exception error-fmt)
  "从ALIST中根据SYMBOL获取实体。找不到时抛异常，除非NO-EXCEPTION为t。"
  (let ((object (cdr (assoc symbol alist))))
	(when (and (null object) (null no-exception))
	  (throw 'exception (format (or error-fmt "没有定义该%s") symbol)))
	object))
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
(require 'save-system)
(require 'quest-system)
(require 'dialog-system)
(require 'shop-system)


(provide 'text-game-maker)
