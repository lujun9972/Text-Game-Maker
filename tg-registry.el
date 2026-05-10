;;; tg-registry.el --- 全局注册表容器  -*- lexical-binding: t; -*-

(require 'cl-lib)

;; 各模块通过 hash table 注册实体，不在此定义 struct
(defvar tg--rooms (make-hash-table :test 'eq))
(defvar tg--objects (make-hash-table :test 'eq))
(defvar tg--creatures (make-hash-table :test 'eq))
(defvar tg--actions (make-hash-table :test 'eq))
(defvar tg--dialogs (make-hash-table :test 'eq))
(defvar tg--shops (make-hash-table :test 'eq))
(defvar tg--quests (make-hash-table :test 'eq))
(defvar tg--action-words (make-hash-table :test 'equal))

(defun tg-get-room (sym)         (gethash sym tg--rooms))
(defun tg-get-object (sym)       (gethash sym tg--objects))
(defun tg-get-creature (sym)     (gethash sym tg--creatures))
(defun tg-get-action (sym)       (gethash sym tg--actions))
(defun tg-get-dialog (sym)       (gethash sym tg--dialogs))
(defun tg-get-shop (sym)         (gethash sym tg--shops))
(defun tg-get-quest (sym)        (gethash sym tg--quests))

(defun tg-register-room (sym r)     (puthash sym r tg--rooms))
(defun tg-register-object (sym o)   (puthash sym o tg--objects))
(defun tg-register-creature (sym c) (puthash sym c tg--creatures))
(defun tg-register-action (sym a)   (puthash sym a tg--actions))
(defun tg-register-dialog (sym d)   (puthash sym d tg--dialogs))
(defun tg-register-shop (sym s)     (puthash sym s tg--shops))
(defun tg-register-quest (sym q)    (puthash sym q tg--quests))

(defun tg-registry-clear ()
  (clrhash tg--rooms)    (clrhash tg--objects)
  (clrhash tg--creatures) (clrhash tg--actions)
  (clrhash tg--dialogs)  (clrhash tg--shops)
  (clrhash tg--quests)   (clrhash tg--action-words))

(provide 'tg-registry)
;;; tg-registry.el ends here