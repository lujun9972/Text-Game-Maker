;;; tg-mode.el --- Major mode for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'action)
(require 'npc-behavior)
(require 'dialog-system)

(defvar tg-over-p nil
  "游戏是否结束")

(defvar tg-command-history nil
  "命令历史列表，最新的在前面")

(defvar tg-command-history-max 50
  "命令历史最大条数")

(defvar tg-history-index -1
  "当前浏览的历史索引，-1 表示不在浏览历史")

(defvar tg-current-input ""
  "浏览历史前保存的当前输入")

(defvar tg-passive-actions '(tg-watch tg-help tg-status tg-quests tg-quest tg-accept
                                      tg-save tg-load tg-quit tg-shop)
  "不消耗回合的动作列表，这些动作不触发 NPC 行为")

(defun tg-prompt-string ()
  "Return the prompt string showing current room symbol."
  (if (and tg-current-room (Room-p tg-current-room))
      (format "[%s]>" (Room-symbol tg-current-room))
    ">"))

(defun tg-messages ()
  (if tg-over-p
	  (text-mode)
	(tg-fix-screen)
	(let ((start (point))
		  (inhibit-read-only t))
	  (tg-mprinc (tg-prompt-string) 'no-newline)
	  (put-text-property start (point) 'read-only t)
	  (put-text-property (1- (point)) (point) 'rear-nonsticky '(read-only)))
	(goto-char (point-max))))


(defun tg-fix-screen ()
  " In window mode, keep screen from jumping by keeping last line at the bottom of the screen."
  (interactive)
  (forward-line (- 0 (- (window-height) 2 )))
  (set-window-start (selected-window) (point))
  (end-of-buffer))

(defun tg-eldoc-function ()
  "Eldoc function for tg-mode. Show docstring for matching command."
  (let* ((line-end (line-end-position))
         (prompt-pos (save-excursion
                       (beginning-of-line)
                       (search-forward ">" line-end t))))
    (when (and prompt-pos (<= (point) line-end))
      (let* ((input (buffer-substring-no-properties prompt-pos (point)))
             (input (string-trim input))
             (candidates (mapcar (lambda (sym)
                                   (substring (symbol-name sym) 3))
                                 tg-valid-actions))
             (completion-result (try-completion input candidates)))
        (cond
         ;; Exact match - use input as the command
         ((eq completion-result t)
          (when (member input candidates)
            (let ((fn (intern (concat "tg-" input))))
              (when (fboundp fn)
                (documentation fn)))))
         ;; Unique prefix match - use the completed string
         ((stringp completion-result)
          (when (member completion-result candidates)
            (let ((fn (intern (concat "tg-" completion-result))))
              (when (fboundp fn)
                (documentation fn)))))
         ;; Ambiguous or no match - return nil
         (t nil))))))

(defun tg-record-history (cmd)
  "Record CMD to command history."
  (when (and (stringp cmd) (not (string-empty-p cmd)))
    (unless (and tg-command-history (string= cmd (car tg-command-history)))
      (push cmd tg-command-history)
      (when (> (length tg-command-history) tg-command-history-max)
        (setf (nthcdr tg-command-history-max tg-command-history) nil)))
    (setq tg-history-index -1)))

(defun tg-history-prev ()
  "Show previous command from history."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t))))
    (when (and prompt-end tg-command-history)
      (when (= tg-history-index -1)
        (setq tg-current-input
              (buffer-substring-no-properties prompt-end (line-end-position))))
      (let ((next-index (1+ tg-history-index)))
        (when (< next-index (length tg-command-history))
          (setq tg-history-index next-index)
          (delete-region prompt-end (line-end-position))
          (insert (nth tg-history-index tg-command-history))
          (end-of-line))))))

(defun tg-history-next ()
  "Show next command from history."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t))))
    (when (and prompt-end (>= tg-history-index 0))
      (cl-decf tg-history-index)
      (delete-region prompt-end (line-end-position))
      (insert (if (= tg-history-index -1)
                  tg-current-input
                (nth tg-history-index tg-command-history)))
      (end-of-line))))

(defun tg-complete-command ()
  "Complete command name after prompt."
  (interactive)
  (let ((prompt-end (save-excursion
                      (beginning-of-line)
                      (search-forward ">" (line-end-position) t))))
    (when prompt-end
      (let* ((input (buffer-substring-no-properties prompt-end (line-end-position)))
             (candidates (mapcar (lambda (sym)
                                   (substring (symbol-name sym) 3))
                                 tg-valid-actions))
             (completion (try-completion input candidates)))
        (cond
         ((null completion) nil)
         ((eq completion t) nil)
         ((string= completion input)
          (let ((matches (all-completions input candidates)))
            (when (> (length matches) 1)
              (tg-display (format "候选命令: %s" (string-join matches ", "))))))
         ((stringp completion)
          (delete-region prompt-end (line-end-position))
          (insert completion)))))))




(defun tg-mprinc (string &optional no-newline)
  " Print something out, in window mode"
  (if (stringp string)
      (insert string)
    (insert (prin1-to-string string)))
  (unless no-newline
	(insert "\n")))


(define-derived-mode tg-mode text-mode "TextGame"
  "Major mode for running text game."
  (make-local-variable 'scroll-step)
  (setq scroll-step 2)
  (local-set-key (kbd "<RET>") #'tg-parse)
  (local-set-key (kbd "<up>") #'tg-history-prev)
  (local-set-key (kbd "<down>") #'tg-history-next)
  (local-set-key (kbd "M-p") #'tg-history-prev)
  (local-set-key (kbd "M-n") #'tg-history-next)
  (local-set-key (kbd "TAB") #'tg-complete-command)
  (setq-local eldoc-documentation-function #'tg-eldoc-function)
  (eldoc-mode 1))



(defun tg-parse (arg)
  "Function called when return is pressed in interactive mode to parse line."
  (interactive "*p")
  (beginning-of-line)
  (let ((line-start (point))
        line prompt-end)
    (end-of-line)
    (when (and (not (= line-start (point)))
               (not (< (point) line-start)))
      (save-excursion
        (setq prompt-end (search-backward ">" (line-beginning-position) t)))
      (when prompt-end
        (setq line (downcase (buffer-substring (1+ prompt-end) (point))))
        (tg-mprinc "\n")
        (if tg-dialog-pending
            (progn
              (tg-dialog-handle-choice line)
              (tg-npc-run-behaviors))
          (let (action-result action things (success nil))
            (setq action-result (catch 'exception
                                  (setq action (car (split-string line)))
                                  (setq things (cdr (split-string line)))
                                  (setq action (intern (format "tg-%s" action)))
                                  (unless (member action tg-valid-actions)
                                    (throw 'exception "未知的命令"))
                                  (let ((result (apply action things)))
                                    (setq success t)
                                    result)))
            (when success
              (tg-record-history line))
            (when action-result
              (tg-mprinc action-result))
            (when (and success (not (member action tg-passive-actions)))
              (tg-npc-run-behaviors)))))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))

(provide 'tg-mode)
