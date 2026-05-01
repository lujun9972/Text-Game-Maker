;;; save-system.el --- Save/Load system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)

;; --- Serialization ---

(defun tg-serialize-creature (creature)
  "Serialize CREATURE to an alist (excluding triggers)."
  `((symbol . ,(Creature-symbol creature))
    (attr . ,(copy-tree (Creature-attr creature)))
    (inventory . ,(copy-sequence (Creature-inventory creature)))
    (equipment . ,(copy-sequence (Creature-equipment creature)))
    (behaviors . ,(copy-tree (Creature-behaviors creature)))))

(defun tg-serialize-room (room)
  "Serialize ROOM runtime state to an alist (excluding triggers)."
  `((inventory . ,(copy-sequence (Room-inventory room)))
    (creature . ,(copy-sequence (Room-creature room)))))

;; --- Save ---

(defun tg-save-game (filepath)
  "Save complete game snapshot to FILEPATH."
  (let ((save-data
         `((player . ,(tg-serialize-creature myself))
           (current-room . ,(Room-symbol current-room))
           (rooms . ,(mapcar (lambda (pair)
                               (cons (car pair) (tg-serialize-room (cdr pair))))
                             rooms-alist))
           (creatures . ,(mapcar (lambda (pair)
                                   (cons (car pair) (tg-serialize-creature (cdr pair))))
                                 creatures-alist)))))
    (let ((dir (file-name-directory filepath)))
      (when (and dir (not (file-directory-p dir)))
        (make-directory dir t)))
    (with-temp-file filepath
      (let (print-level print-length)
        (prin1 save-data (current-buffer))))
    (tg-display (format "游戏已保存到 %s" filepath))))

;; --- Restore ---

(defun tg-restore-game-state (data)
  "Restore game state from save DATA alist."
  ;; Restore player
  (let* ((player-data (cdr (assoc 'player data)))
         (player-symbol (cdr (assoc 'symbol player-data))))
    (setq myself (get-creature-by-symbol player-symbol))
    (when myself
      (setf (Creature-attr myself) (cdr (assoc 'attr player-data)))
      (setf (Creature-inventory myself) (cdr (assoc 'inventory player-data)))
      (setf (Creature-equipment myself) (cdr (assoc 'equipment player-data)))
      (setf (Creature-behaviors myself) (cdr (assoc 'behaviors player-data)))))
  ;; Restore current room
  (setq current-room (get-room-by-symbol (cdr (assoc 'current-room data))))
  ;; Restore rooms runtime state
  (let ((rooms-data (cdr (assoc 'rooms data))))
    (dolist (room-entry rooms-data)
      (let ((room (get-room-by-symbol (car room-entry)))
            (room-state (cdr room-entry)))
        (when room
          (setf (Room-inventory room) (cdr (assoc 'inventory room-state)))
          (setf (Room-creature room) (cdr (assoc 'creature room-state)))))))
  ;; Restore creatures runtime state
  (let ((creatures-data (cdr (assoc 'creatures data))))
    (dolist (cr-entry creatures-data)
      (let ((cr (get-creature-by-symbol (car cr-entry)))
            (cr-state (cdr cr-entry)))
        (when cr
          (setf (Creature-attr cr) (cdr (assoc 'attr cr-state)))
          (setf (Creature-inventory cr) (cdr (assoc 'inventory cr-state)))
          (setf (Creature-equipment cr) (cdr (assoc 'equipment cr-state)))
          (setf (Creature-behaviors cr) (cdr (assoc 'behaviors cr-state))))))))

(defun tg-load-game (filepath)
  "Load game state from FILEPATH."
  (unless (file-exists-p filepath)
    (throw 'exception "存档文件不存在"))
  (let ((data (with-temp-buffer
                (insert-file-contents filepath)
                (goto-char (point-min))
                (read (current-buffer)))))
    (when tg-config-dir
      ;; Re-initialize from config files to restore triggers
      (map-init (expand-file-name "room-config.el" tg-config-dir)
                (expand-file-name "map-config.el" tg-config-dir))
      (inventorys-init (expand-file-name "inventory-config.el" tg-config-dir))
      (creatures-init (expand-file-name "creature-config.el" tg-config-dir))
      (when (file-exists-p (expand-file-name "level-config.el" tg-config-dir))
        (level-init (expand-file-name "level-config.el" tg-config-dir))))
    (tg-restore-game-state data)
    (setq tg-over-p nil)
    (tg-display (format "游戏已从 %s 恢复" filepath))
    (tg-display (describe current-room))))

(provide 'save-system)
