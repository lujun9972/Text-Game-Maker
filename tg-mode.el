;;; tg-mode.el --- Major mode for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'action)
(require 'npc-behavior)
(require 'dialog-system)

(defvar tg-over-p nil
  "游戏是否结束")

(defun tg-prompt-string ()
  "Return the prompt string showing current room symbol."
  (if (and current-room (Room-p current-room))
      (format "[%s]>" (Room-symbol current-room))
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
        (if dialog-pending
            (progn
              (dialog-handle-choice line)
              (npc-run-behaviors))
          (let (action-result action things)
            (setq action-result (catch 'exception
                                  (setq action (car (split-string line)))
                                  (setq things (cdr (split-string line)))
                                  (setq action (intern (format "tg-%s" action)))
                                  (unless (member action tg-valid-actions)
                                    (throw 'exception "未知的命令"))
                                  (apply action things)))
            (when action-result
              (tg-mprinc action-result))
            (npc-run-behaviors))))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))

(provide 'tg-mode)
