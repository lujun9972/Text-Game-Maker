;;; tg-commands.el --- Handler Chain 调度引擎  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, command

;;; Commentary:
;; Handler Chain 调度引擎，按顺序执行：
;; error → room-before → io → do → action → after → NPC → buffs-tick → turn-increment

;;; Code:

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-parser)
(require 'tg-action)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-game)
(require 'tg-npc)

;;; 全局输出配置

(defvar tg-output-buffer nil
  "游戏输出缓冲区。nil 表示输出到当前缓冲区。")

(defvar tg-message-hook nil
  "消息输出后调用的钩子函数列表。每个函数接收两个参数：(text game)。")

;;; 全局输出函数

(defun tg-message (format &rest args)
  "向输出缓冲区插入文本。
FORMAT: 格式化字符串
ARGS: 格式化参数
如果 tg-output-buffer 为 nil，输出到当前缓冲区。"
  (let ((text (apply 'format format args))
        (buffer (or tg-output-buffer (current-buffer))))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert text)
      (unless (string-suffix-p "\n" text)
        (insert "\n")))
    ;; 确保传给钩子的文本包含换行符（与实际输出一致）
    (let ((hook-text (if (string-suffix-p "\n" text) text (concat text "\n"))))
      (run-hook-with-args 'tg-message-hook hook-text))))

;;; 错误处理

(defun tg-handle-error (ast game)
  "处理 AST 中的错误类型。
AST: (:error TYPE ...)
返回 t 表示已处理错误，nil 表示无错误。"
  (let ((error-type (plist-get ast :error)))
    (when error-type
      (cond
       ((eq error-type :empty-input)
        nil)  ;; 空输入不输出任何内容
       ((eq error-type :unknown-action)
        (let ((verb (plist-get ast :verb)))
          (tg-message "我不明白 '%s' 是什么意思。" (or verb ""))))
       ((eq error-type :unknown-noun)
        (let ((word (plist-get ast :word)))
          (tg-message "我不认识 '%s' 这个东西。" (or word ""))))
       (t
        (tg-message "发生未知错误。"))))
    error-type))

;;; 房间 before-handler

(defun tg-run-room-before (ast game)
  "运行当前房间的 before-handler。
返回 t 表示 handler 已处理动作并停止传播，nil 表示继续。"
  (let* ((location (tg-game-get game :location))
         (room (tg-get-room location)))
    (when room
      (let ((handler (tg-room-before-handler room)))
        (when handler
          (funcall handler ast game))))))

;;; 间接宾语 handler

(defun tg-run-io-handler (ast game)
  "运行间接宾语的 handler。
返回 t 表示 handler 已处理动作并停止传播，nil 表示继续。"
  (let* ((io-key (plist-get ast :io-key))
         (handler nil))
    (when io-key
      ;; 尝试从对象中获取 handler
      (let ((obj (tg-get-object io-key)))
        (when obj
          (setq handler (tg-object-handler obj))))
      ;; 尝试从生物中获取 handler
      (unless handler
        (let ((creature (tg-get-creature io-key)))
          (when creature
            (setq handler (tg-creature-handler creature)))))
      (when handler
        (funcall handler ast game)))))

;;; 直接宾语 handler

(defun tg-run-do-handler (ast game)
  "运行直接宾语的 handler。
返回 t 表示 handler 已处理动作并停止传播，nil 表示继续。"
  (let* ((do-key (plist-get ast :do-key))
         (handler nil))
    (when do-key
      ;; 尝试从对象中获取 handler
      (let ((obj (tg-get-object do-key)))
        (when obj
          (setq handler (tg-object-handler obj))))
      ;; 尝试从生物中获取 handler
      (unless handler
        (let ((creature (tg-get-creature do-key)))
          (when creature
            (setq handler (tg-creature-handler creature)))))
      (when handler
        (funcall handler ast game)))))

;;; 动作 handler

(defun tg-run-action (ast game)
  "运行动作的默认 handler。
通过 tg-find-action 查找 action struct 并调用其 handler。
action handler 可以抛出 'tg-action-abort 来跳过 after-handler。"
  (let* ((action-id (plist-get ast :action))
         (action (gethash action-id tg--actions)))
    (when action
      (let ((handler (tg-action-handler action)))
        (when handler
          (funcall handler ast game))))))

;;; 房间 after-handler

(defun tg-run-room-after (ast game)
  "运行当前房间的 after-handler。
仅在 action handler 未抛出 tg-action-abort 时执行。"
  (let* ((location (tg-game-get game :location))
         (room (tg-get-room location)))
    (when room
      (let ((handler (tg-room-after-handler room)))
        (when handler
          (funcall handler ast game))))))

;;; take all 展开

(defun tg-collect-takeable-objects (game)
  "收集当前房间所有可取对象的 symbol 列表。
可取对象：非 scenery、非 supporter、非 static。"
  (let* ((location (tg-game-get game :location))
         (room (tg-get-room location))
         (takeable '()))
    (when room
      (dolist (obj-sym (tg-room-all-visible-objects room))
        (let ((obj (tg-get-object obj-sym)))
          (when (and obj (tg-object-takeable-p obj))
            (push obj-sym takeable)))))
    (nreverse takeable)))

(defun tg-expand-all-ast (ast game)
  "当 AST 的 :do-key 为 :all 时，展开为多个子 AST 并逐个 dispatch。
返回处理的子 AST 数量。"
  (when (eq (plist-get ast :do-key) :all)
    (let* ((action (plist-get ast :action))
           (takeable (tg-collect-takeable-objects game))
           (count 0))
      (dolist (obj-sym takeable)
        ;; 构建子 AST：复制原 AST 但替换 :do-key 为具体对象
        (let ((sub-ast (copy-sequence ast)))
          (setq sub-ast (plist-put sub-ast :do-key obj-sym))
          (tg-dispatch sub-ast game)
          (setq count (1+ count))))
      count)))

;;; 主调度函数

(defun tg-dispatch (ast game)
  "Handler Chain 调度引擎。
按顺序执行：error → room-before → io → do → action → after
非被动命令后执行：NPC 行为 → buffs-tick → 回合递增

AST: 解析后的动作结构
GAME: 游戏状态哈希表

返回值：无"
  (cl-block tg-dispatch
    ;; 处理 take all 展开
    (when (eq (plist-get ast :do-key) :all)
      (tg-expand-all-ast ast game)
      (cl-return-from tg-dispatch))

    ;; Handler chain
    (cond
     ((tg-handle-error ast game) nil)
     ((tg-run-room-before ast game) nil)
     ((tg-run-io-handler ast game) nil)
     ((tg-run-do-handler ast game) nil)
     (t
      (catch 'tg-action-abort
        (tg-run-action ast game)
        (tg-run-room-after ast game))))

    ;; 非被动命令后的后处理
    (let ((action-id (plist-get ast :action))
          (passive-list tg-passive-actions))
      ;; 检查是否是被动命令（同时支持 symbol 和 string）
      (unless (or (member action-id passive-list)
                  (member (format "%s" action-id) passive-list))
        (tg-npc-run-behaviors game)
        (tg-buffs-tick game)
        (tg-game-incf game :turns)))))

(provide 'tg-commands)
;;; tg-commands.el ends here
