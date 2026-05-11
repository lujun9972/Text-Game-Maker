;;; sample-game.el --- 地牢冒险示例游戏  -*- lexical-binding: t; -*-

;; 使用方法：
;;   M-x eval-buffer 然后 M-x play-sample-game
;;   或 bash sample/play.sh

(require 'tg)

(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((game-file (expand-file-name "game.org"
                                      (file-name-directory (or load-file-name buffer-file-name)))))
    (tg-start game-file)))

(provide 'sample-game)
;;; sample-game.el ends here
