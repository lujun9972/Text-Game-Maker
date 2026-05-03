;;; text-game-maker.el --- Main entry for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)

(defun tg-file-content(file)
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

(defmacro tg-def-config-builder (name alist-var struct-name fields)
  "生成 build-NAME 和 NAME-init 函数。
NAME: 模块名 (如 room, inventory, quest)
ALIST-VAR: 存储结果的 alist 变量 (如 tg-rooms-alist)
STRUCT-NAME: cl-defstruct 名 (如 Room, Inventory, Quest)
FIELDS: 解构和构造用的字段名列表"
  (let ((build-fn (intern (format "tg-build-%s" name)))
        (init-fn (intern (format "tg-%s-init" name)))
        (entity-var (intern (format "%s-entity" name)))
        (constructor (intern (format "make-%s" struct-name))))
    `(progn
       (defun ,build-fn (,entity-var)
         ,(format "根据%s创建%s对象." entity-var struct-name)
         (cl-multiple-value-bind ,fields ,entity-var
           (cons (car ,entity-var)
                 (,constructor ,@(cl-mapcan (lambda (f) (list (intern (format ":%s" f)) f)) fields)))))
       (defun ,init-fn (config-file)
         ,(format "从CONFIG-FILE加载%s配置." name)
         (let ((entities (tg-read-from-whole-string (tg-file-content config-file))))
           (setq ,alist-var (mapcar #',build-fn entities)))))))

(require 'tg-mode)
(defvar tg-display-fn #'tg-mprinc
  "显示信息的函数")
(defun tg-display (&rest args)
  (apply tg-display-fn args))
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
