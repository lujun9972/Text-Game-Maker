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
(require 'eieio)
(require 'room-maker)
(require 'inventory-maker)
(require 'creature-maker)
(require 'action)


(provide 'text-game-maker)
