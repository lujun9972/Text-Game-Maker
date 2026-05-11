;;; tg-mode.el --- UI 主模式 — 单 buffer 上半只读输出区 + 下半 prompt 输入区  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 2.0
;; Keywords: games, text, ui

;;; Commentary:
;; tg-mode 是 Text-Game-Maker 的 UI 主模式。
;; 单 buffer 设计：上半只读输出区 + 下半 prompt 输入区。
;; 使用 buffer-local 变量管理状态，支持多游戏 buffer 并行。

;;; Code:

(require 'cl-lib)
(require 'tg-parser)
(require 'tg-commands)
(require 'tg-dialog)
(require 'tg-save)
(require 'tg-game)
(require 'tg-room)
(require 'tg-registry)
(require 'tg-action)
(require 'tg-config)

;;; ============================================================
;;; Buffer-local 变量
;;; ============================================================

(defvar-local tg-prompt-marker nil
  "当前 prompt 起始位置的 marker。
每次 tg-render-prompt 时更新。")

(defvar-local tg-command-history nil
  "命令历史列表，最新的在前面。")

(defvar-local tg-history-index -1
  "当前浏览的历史索引。-1 表示不在浏览历史。")

(defvar-local tg-current-input ""
  "浏览历史前保存的当前输入。")

(defvar tg-command-history-max 50
  "命令历史最大条数。")

(defvar tg-over-p nil
  "游戏是否结束。")

;;; ============================================================
;;; tg-mode 定义
;;; ============================================================

(define-derived-mode tg-mode text-mode "TG"
  "Major mode for Text-Game-Maker.

单 buffer 设计：上半为只读输出区，下半为 prompt 输入区。
Prompt 格式：[房间名]> "
  (setq-local scroll-step 2)
  ;; 初始化 buffer-local 变量
  (setq-local tg-prompt-marker nil)
  (setq-local tg-command-history nil)
  (setq-local tg-history-index -1)
  (setq-local tg-current-input "")
  ;; 键绑定
  (local-set-key (kbd "RET") #'tg-send-command)
  (local-set-key (kbd "TAB") #'tg-complete-command)
  (local-set-key (kbd "M-p") #'tg-history-prev)
  (local-set-key (kbd "M-n") #'tg-history-next))

;;; ============================================================
;;; Buffer 管理
;;; ============================================================

(defun tg-get-buffer ()
  "返回当前游戏 buffer（如果存在）。"
  (catch 'found
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (eq major-mode 'tg-mode)
          (throw 'found buf))))
    nil))

;;; ============================================================
;;; 游戏启动
;;; ============================================================

(defun tg-start-game (org-file)
  "启动游戏。

ORG-FILE: Org 配置文件路径。

流程：
1. 调 tg-config-load 加载配置
2. 调 tg-register-builtins 注册内置动词
3. 创建 \"*TG: game-title*\" buffer
4. 切换到 tg-mode
5. 设置 tg-output-buffer 为当前 buffer
6. 显示初始房间描述
7. 渲染 prompt"
  (let ((game (tg-config-load org-file)))
    (setq tg-game game)
    (tg-register-builtins)
    (let* ((title (or (tg-game-get game :title) "Game"))
           (buf-name (format "*TG: %s*" title))
           (buf (get-buffer-create buf-name)))
      (with-current-buffer buf
        (tg-mode)
        (setq tg-output-buffer buf)
        ;; 显示初始房间描述
        (let* ((location (tg-game-get game :location))
               (room (tg-get-room location)))
          (when room
            (tg-message "%s" (tg-room-describe room))))
        ;; 渲染 prompt
        (tg-render-prompt))
      (switch-to-buffer buf))))

;;; ============================================================
;;; Prompt 渲染
;;; ============================================================

(defun tg-render-prompt ()
  "显示 [房间名]> 格式 prompt，设置 marker。

Prompt 区域设为 read-only + rear-nonsticky，保护已输出文本不被修改。"
  (when (eq major-mode 'tg-mode)
    (let ((room-name
           (if (and tg-game (tg-game-get tg-game :location))
               (let* ((location (tg-game-get tg-game :location))
                      (room (tg-get-room location)))
                 (if room
                     (tg-room-name room)
                   ">"))
             ">"))
          (start (point-max)))
      (goto-char (point-max))
      (let ((inhibit-read-only t)
            (prompt-text (format "[%s]> " room-name)))
        (insert "\n")
        (setq start (point))
        (insert prompt-text)
        ;; 设置 read-only 属性保护 prompt
        (put-text-property start (point) 'read-only t)
        (put-text-property (1- (point)) (point) 'rear-nonsticky '(read-only))
        ;; 设置 prompt marker
        (setq tg-prompt-marker (point-marker))
        (goto-char (point-max))))))

;;; ============================================================
;;; 命令发送与处理
;;; ============================================================

(defun tg-send-command ()
  "读取 prompt 后的文本，处理命令。

流程：
1. 获取 prompt-marker 到 buffer-end 的文本
2. 判断是否在对话中（tg-dialog-pending 非 nil）
   - 如果在对话中，用 tg-dialog-handle-choice 处理
   - 否则用 tg-parse + tg-dispatch 处理
3. 添加到命令历史
4. 渲染新的 prompt"
  (interactive)
  (when (and tg-prompt-marker
             (>= (point) tg-prompt-marker))
    (let* ((input (buffer-substring-no-properties
                   tg-prompt-marker (point-max)))
           (trimmed (string-trim input)))
      ;; 添加到命令历史
      (tg-record-history trimmed)
      ;; 处理命令
      (if tg-dialog-pending
          (tg-dialog-handle-choice trimmed)
        (let ((ast (tg-parse trimmed)))
          (tg-dispatch ast tg-game)))
      ;; 渲染新 prompt
      (tg-render-prompt))))

;;; ============================================================
;;; 命令历史
;;; ============================================================

(defun tg-record-history (cmd)
  "Record CMD to command history (buffer-local)."
  (when (and (stringp cmd) (not (string-empty-p cmd)))
    (unless (and tg-command-history
                 (string= cmd (car tg-command-history)))
      (push cmd tg-command-history)
      (when (> (length tg-command-history) tg-command-history-max)
        (setf (nthcdr tg-command-history-max tg-command-history) nil)))
    (setq tg-history-index -1)))

(defun tg-history-prev ()
  "Show previous command from history."
  (interactive)
  (when (and tg-prompt-marker
             tg-command-history
             (>= (point) tg-prompt-marker))
    (when (= tg-history-index -1)
      (setq tg-current-input
            (buffer-substring-no-properties tg-prompt-marker (point-max))))
    (let ((next-index (1+ tg-history-index)))
      (when (< next-index (length tg-command-history))
        (setq tg-history-index next-index)
        (let ((inhibit-read-only t))
          (delete-region tg-prompt-marker (point-max)))
        (insert (nth tg-history-index tg-command-history))
        (goto-char (point-max))))))

(defun tg-history-next ()
  "Show next command from history."
  (interactive)
  (when (and tg-prompt-marker
             (>= tg-history-index 0)
             (>= (point) tg-prompt-marker))
    (cl-decf tg-history-index)
    (let ((inhibit-read-only t))
      (delete-region tg-prompt-marker (point-max)))
    (insert (if (= tg-history-index -1)
                tg-current-input
              (nth tg-history-index tg-command-history)))
    (goto-char (point-max))))

;;; ============================================================
;;; TAB 补全
;;; ============================================================

(defun tg-complete-command ()
  "TAB 补全。

prompt 后为空：补全动词名。
动词后：补全当前可见对象名。"
  (interactive)
  (when (and tg-prompt-marker
             (>= (point) tg-prompt-marker))
    (let* ((input (buffer-substring-no-properties tg-prompt-marker (point-max)))
           (tokens (tg-parser-tokenize input)))
      (if (or (null tokens) (string-empty-p (string-trim input)))
          ;; 空输入：补全动词
          (tg-complete-verb "")
        ;; 有输入：判断是动词补全还是名词补全
        (let* ((words (split-string input "[ \t]+" t))
               (verb (car words))
               (rest (cdr words)))
          (if rest
              ;; 动词后：补全对象名
              (tg-complete-object (car (last words)))
            ;; 只有动词：补全动词
            (tg-complete-verb verb)))))))

(defun tg-complete-verb (prefix)
  "补全动词。PREFIX 为当前输入的动词前缀。"
  (let ((candidates '())
        (lower-prefix (downcase prefix)))
    ;; 从 tg--action-words 收集所有动词
    (maphash (lambda (word _action-id)
               (when (string-prefix-p lower-prefix (downcase word))
                 (push word candidates)))
             tg--action-words)
    (when candidates
      (let ((completion (try-completion lower-prefix candidates)))
        (cond
         ((null completion) nil)
         ((eq completion t) nil)
         ((string= (downcase completion) lower-prefix)
          ;; 完全匹配或有多个候选：显示候选列表
          (let ((matches (all-completions lower-prefix candidates)))
            (when (> (length matches) 1)
              (tg-message "候选命令: %s" (string-join matches ", ")))))
         ((stringp completion)
          ;; 替换输入区域
          (let ((inhibit-read-only t))
            (delete-region tg-prompt-marker (point-max)))
          (insert completion)))))))

(defun tg-complete-object (prefix)
  "补全对象名。PREFIX 为当前输入的对象前缀。"
  (when (and tg-game (tg-game-get tg-game :location))
    (let* ((location (tg-game-get tg-game :location))
           (room (tg-get-room location))
           (candidates '())
           (lower-prefix (downcase prefix)))
      (when room
        (dolist (obj-sym (tg-room-all-visible-objects room))
          (let ((obj (tg-get-object obj-sym)))
            (when obj
              (let ((name (tg-object-name obj)))
                (when (and name (string-prefix-p lower-prefix (downcase name)))
                  (push name candidates)))))))
      ;; 也补全背包物品
      (let* ((player-sym (tg-game-get tg-game :player))
             (player (when player-sym (tg-get-creature player-sym))))
        (when player
          (dolist (obj-sym (tg-creature-inventory player))
            (let ((obj (tg-get-object obj-sym)))
              (when obj
                (let ((name (tg-object-name obj)))
                  (when (and name (string-prefix-p lower-prefix (downcase name)))
                    (push name candidates))))))))
      (when candidates
        (let ((completion (try-completion lower-prefix candidates)))
          (cond
           ((null completion) nil)
           ((eq completion t) nil)
           ((string= (downcase completion) lower-prefix)
            (let ((matches (all-completions lower-prefix candidates)))
              (when (> (length matches) 1)
                (tg-message "候选对象: %s" (string-join matches ", ")))))
           ((stringp completion)
            ;; 只替换最后一个词
            (let ((inhibit-read-only t))
              (delete-region (- (point) (length prefix)) (point)))
            (insert completion))))))))

(provide 'tg-mode)
;;; tg-mode.el ends here
