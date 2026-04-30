;;; tg-mode.el --- Major mode for Text-Game-Maker  -*- lexical-binding: t; -*-

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
	(tg-mprinc (tg-prompt-string) 'no-newline)
	(message "point-max=%s" (point-max))
	(goto-char (point-max))))


(defun tg-fix-screen ()
  " In window mode, keep screen from jumping by keeping last line at the bottom of the screen."
  (interactive)
  (forward-line (- 0 (- (window-height) 2 )))
  (set-window-start (selected-window) (point))
  (end-of-buffer))

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
  (local-set-key (kbd "<RET>") #'tg-parse))



(defun tg-parse (arg)
  "Function called when return is pressed in interactive mode to parse line."
  (interactive "*p")
  (beginning-of-line)
  (let ((line-start (point))
        line prompt-end)
    (end-of-line)
    (when (and (not (= line-start (point)))
               (not (< (point) line-start)))
      ;; Find the last '>' on this line to locate end of prompt
      (save-excursion
        (setq prompt-end (search-backward ">" (line-beginning-position) t)))
      (when prompt-end
        (setq line (downcase (buffer-substring (1+ prompt-end) (point))))
        (princ line)
        (tg-mprinc "\n")
        (let (action-result action things)
	      (setq action-result (catch 'exception
							    (setq action (car (split-string line)))
							    (setq things (cdr (split-string line)))
								(setq action (intern (format "tg-%s" action)))
								(unless (member action tg-valid-actions)
									(throw 'exception "未知的命令"))
								  (apply action things)))
	      (when action-result
	        (tg-mprinc action-result))))))
  (goto-char (point-max))
  (tg-mprinc "\n")
  (tg-messages))

(provide 'tg-mode)
