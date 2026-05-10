;;; tg-action.el --- 动词注册系统  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, action

;;; Commentary:
;; 动词注册系统，用于注册和管理游戏中的动词动作

;;; Code:

(require 'cl-lib)
(require 'tg-registry)

(cl-defstruct tg-action
  id
  synonyms
  handler)

(defun tg-register-action (&rest args)
  "注册一个动作，将其所有同义词映射到动作词哈希表。
ARGS: 应该包含 :id, :synonyms, :handler 关键字参数"
  (let ((id (cl-getf args :id))
        (synonyms (cl-getf args :synonyms))
        (handler (cl-getf args :handler)))
    (let ((action (make-tg-action :id id :synonyms synonyms :handler handler)))
      ;; 直接将动作添加到动作注册表（避免与 registry 的同名函数冲突）
      (puthash id action tg--actions)
      ;; 将所有同义词映射到动作ID
      (dolist (synonym synonyms)
        (puthash synonym id tg--action-words)))))

(defun tg-find-action (word)
  "通过动作词查找对应的动作ID。
WORD: 动作词或同义词"
  (gethash word tg--action-words))

(defconst tg-verb-aliases
  '(("get" . "take")
    ("l" . "look")
    ("x" . "examine")
    ("i" . "inventory")
    ("pick up" . "take")
    ("put down" . "drop")
    ("equip" . "wear")
    ("consume" . "eat")
    ("hit" . "attack")
    ("fight" . "attack")
    ("speak" . "talk"))
  "动词同义词映射表。将简写或别称映射到标准动词。")

(defconst tg-passive-actions
  '("look" "examine" "inventory" "status" "quests" "help")
  "被动动作列表。这些动作不会触发NPC行为，不计入回合。")

(provide 'tg-action)
;;; tg-action.el ends here