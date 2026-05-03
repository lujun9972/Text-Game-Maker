;;; test-npc-behavior.el --- Tests for npc-behavior.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'npc-behavior)

;; --- tg-npc-evaluate-condition ---

(ert-deftest test-npc-condition-always ()
  "always condition should return t."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25)))))
    (should (tg-npc-evaluate-condition cr '(always)))))

(ert-deftest test-npc-condition-hp-below-true ()
  "hp-below should return t when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (tg-npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-below-false ()
  "hp-below should return nil when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (tg-npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-above-true ()
  "hp-above should return t when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should (tg-npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-hp-above-false ()
  "hp-above should return nil when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should-not (tg-npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-player-in-room-true ()
  "player-in-room should return t when player symbol is in room creatures."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-creatures-alist tg-myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero tg-myself)))
      (should (tg-npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-player-in-room-false ()
  "player-in-room should return nil when player not in room."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-creatures-alist tg-myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero tg-myself)))
      (should-not (tg-npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-and ()
  "and should return t only when all sub-conditions are true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (tg-npc-evaluate-condition cr '(and (hp-below 15) (hp-above 5))))
    (should-not (tg-npc-evaluate-condition cr '(and (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-or ()
  "or should return t when any sub-condition is true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (tg-npc-evaluate-condition cr '(or (hp-below 5) (hp-above 5))))
    (should-not (tg-npc-evaluate-condition cr '(or (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-not ()
  "not should invert condition result."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (tg-npc-evaluate-condition cr '(not (hp-above 10))))
    (should (tg-npc-evaluate-condition cr '(not (hp-below 10))))))

;; --- tg-npc-execute-action: attack ---

(ert-deftest test-npc-attack-player-deals-damage ()
  "npc attack should deal damage to player."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 8))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 3))))
      (setq tg-over-p nil)
      (tg-npc-execute-action goblin '(attack))
      (should (= (cdr (assoc 'hp (Creature-attr tg-myself))) 95)))))

(ert-deftest test-npc-attack-player-kills ()
  "npc attack should set tg-over-p when player dies."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 50))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 10) (defense . 0))))
      (setq tg-over-p nil)
      (tg-npc-execute-action goblin '(attack))
      (should tg-over-p))))

;; --- tg-npc-execute-action: say ---

(ert-deftest test-tg-npc-say-displays-message ()
  "npc say should display message via tg-display."
  (test-with-globals-saved (tg-display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-npc-execute-action goblin '(say "Hello!"))
      (should (cl-some (lambda (s) (string-match-p "goblin" s)) (mapcar #'car output))))))

;; --- tg-npc-execute-action: move ---

(ert-deftest test-tg-npc-move-random ()
  "npc move random should move creature to an adjacent room."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-display-fn)
    (let* ((room1 (make-Room :symbol 'room1 :creature '(goblin)))
           (room2 (make-Room :symbol 'room2 :creature nil))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq tg-rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq tg-room-map '((room1 room2)))
      (setq tg-current-room room1)
      (setq tg-display-fn #'ignore)
      (tg-npc-execute-action goblin '(move random))
      (should-not (tg-creature-exist-in-room-p room1 'goblin)))))

;; --- tg-npc-execute-action: buff/debuff ---

(ert-deftest test-tg-npc-buff-self ()
  "npc buff should increase creature's own attr."
  (test-with-globals-saved (tg-display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq tg-display-fn #'ignore)
      (tg-npc-execute-action goblin '(buff attack 3))
      (should (= (cdr (assoc 'attack (Creature-attr goblin))) 8)))))

(ert-deftest test-tg-npc-debuff-player ()
  "npc debuff should decrease player's attr."
  (test-with-globals-saved (tg-display-fn tg-myself)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq tg-display-fn #'ignore)
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 5))))
      (tg-npc-execute-action goblin '(debuff defense 2))
      (should (= (cdr (assoc 'defense (Creature-attr tg-myself))) 3)))))

;; --- tg-npc-run-behaviors ---

(ert-deftest test-tg-npc-run-behaviors-matches-first-rule ()
  "tg-npc-run-behaviors should execute only the first matching rule."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-rooms-alist tg-room-map tg-current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5))
                                  :behaviors '(((always) say "first") ((always) say "second"))))
           (room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero tg-myself)))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-over-p nil)
      (tg-npc-run-behaviors)
      (should (= 1 (cl-count-if (lambda (s) (string-match-p "first" s)) (mapcar #'car output)))))))

(ert-deftest test-tg-npc-run-behaviors-skips-tg-myself ()
  "tg-npc-run-behaviors should skip tg-myself even if it has behaviors."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-rooms-alist tg-room-map tg-current-room tg-over-p)
    (let* ((output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))
                                  :behaviors '(((always) say "I act!"))))
      (setq tg-creatures-alist (list (cons 'hero tg-myself)))
      (setq tg-rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero)))))
      (setq tg-room-map '((room1)))
      (setq tg-current-room (tg-get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (tg-npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-tg-npc-run-behaviors-skips-dead-npc ()
  "tg-npc-run-behaviors should skip NPCs with HP <= 0."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-rooms-alist tg-room-map tg-current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 0))
                                  :behaviors '(((always) say "I'm dead"))))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero tg-myself)))
      (setq tg-rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq tg-room-map '((room1)))
      (setq tg-current-room (tg-get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (tg-npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-tg-npc-run-behaviors-no-behaviors-noop ()
  "tg-npc-run-behaviors should do nothing for NPCs with nil behaviors."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-myself tg-rooms-alist tg-room-map tg-current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25)) :behaviors nil))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero tg-myself)))
      (setq tg-rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq tg-room-map '((room1)))
      (setq tg-current-room (tg-get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (tg-npc-run-behaviors)
      (should (null output)))))

(provide 'test-npc-behavior)
