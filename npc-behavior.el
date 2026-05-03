;;; npc-behavior.el --- NPC proactive behavior system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)

;; --- Condition evaluator ---

(defun tg-npc-evaluate-condition (creature condition)
  "Evaluate CONDITION for CREATURE. Return t or nil."
  (let ((op (car condition))
        (args (cdr condition)))
    (pcase op
      ('always t)
      ('hp-below
       (let ((hp (or (cdr (assoc 'hp (Creature-attr creature))) 0)))
         (< hp (car args))))
      ('hp-above
       (let ((hp (or (cdr (assoc 'hp (Creature-attr creature))) 0)))
         (> hp (car args))))
      ('player-in-room
       (and tg-current-room
            (member (Creature-symbol tg-myself) (Room-creature tg-current-room))))
      ('and
       (cl-every (lambda (c) (tg-npc-evaluate-condition creature c)) args))
      ('or
       (cl-some (lambda (c) (tg-npc-evaluate-condition creature c)) args))
      ('not
       (not (tg-npc-evaluate-condition creature (car args))))
      (_ nil))))

;; --- Action executor ---

(defun tg-npc-attack-player (creature)
  "CREATURE attacks the player."
  (let* ((npc-attack (or (cdr (assoc 'attack (Creature-attr creature))) 0))
         (player-defense (or (cdr (assoc 'defense (Creature-attr tg-myself))) 0))
         (damage (max 1 (- npc-attack player-defense))))
    (tg-take-effect-to-creature tg-myself (cons 'hp (- damage)))
    (tg-display (format "%s攻击了你，造成 %d 点伤害！" (Creature-symbol creature) damage))
    (when (<= (cdr (assoc 'hp (Creature-attr tg-myself))) 0)
      (tg-display "你被击败了！游戏结束！")
      (setq tg-over-p t))))

(defun tg-npc-say (creature text)
  "CREATURE says TEXT."
  (tg-display (format "%s说：%s" (Creature-symbol creature) text)))

(defun tg-npc-move (creature direction)
  "Move CREATURE in DIRECTION (symbol or 'random)."
  (let* ((sym (Creature-symbol creature))
         (neighbors (tg-beyond-rooms (Room-symbol tg-current-room) tg-room-map))
         (dir-map '((up . 0) (right . 1) (down . 2) (left . 3)))
         (dir-names '((up . "北") (right . "东") (down . "南") (left . "西")))
         target-symbol)
    (when (eq direction 'random)
      (let* ((valid-dirs (cl-remove-if-not
                          (lambda (d) (nth (cdr d) neighbors))
                          dir-map)))
        (when valid-dirs
          (let ((chosen-dir (nth (random (length valid-dirs)) valid-dirs)))
            (setq direction (car chosen-dir))))))
    (when-let* ((dir-idx (cdr (assoc direction dir-map))))
      (setq target-symbol (nth dir-idx neighbors))
      (when target-symbol
        (tg-remove-creature-from-room tg-current-room sym)
        (let ((target-room (tg-get-room-by-symbol target-symbol)))
          (tg-add-creature-to-room target-room sym))
        (tg-display (format "%s向%s离开了。" sym (cdr (assoc direction dir-names))))))))

(defun tg-npc-apply-buff (creature attr value)
  "CREATURE buffs itself with ATTR + VALUE."
  (tg-take-effect-to-creature creature (cons attr value))
  (tg-display (format "%s怒吼一声，%s增强了！" (Creature-symbol creature) attr)))

(defun tg-npc-apply-debuff (creature attr value)
  "CREATURE debuffs player with ATTR - VALUE."
  (tg-take-effect-to-creature tg-myself (cons attr (- value)))
  (tg-display (format "%s对你施放了诅咒，%s降低了！" (Creature-symbol creature) attr)))

(defun tg-npc-execute-action (creature action)
  "Execute ACTION for CREATURE."
  (pcase (car action)
    ('attack (tg-tg-npc-attack-player creature))
    ('say (tg-npc-say creature (cadr action)))
    ('move (tg-tg-npc-move creature (cadr action)))
    ('buff (tg-npc-apply-buff creature (cadr action) (caddr action)))
    ('debuff (tg-npc-apply-debuff creature (cadr action) (caddr action)))
    (_ nil)))

;; --- Main behavior runner ---

(defun tg-npc-run-behaviors ()
  "Run behaviors for all NPCs in the current room."
  (when (and tg-current-room (Room-creature tg-current-room))
    (dolist (npc-sym (copy-sequence (Room-creature tg-current-room)))
      (let ((npc (tg-get-creature-by-symbol npc-sym)))
        (when (and npc
                   (not (eq npc tg-myself))
                   (> (or (cdr (assoc 'hp (Creature-attr npc))) 0) 0)
                   (Creature-behaviors npc))
          (cl-block 'behavior-loop
            (dolist (rule (Creature-behaviors npc))
              (let ((condition (car rule))
                    (action (cdr rule)))
                (when (tg-tg-npc-evaluate-condition npc condition)
                  (tg-npc-execute-action npc action)
                  (cl-return-from 'behavior-loop))))))))))

(provide 'npc-behavior)
