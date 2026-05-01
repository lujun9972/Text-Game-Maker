;;; test-npc-behavior.el --- Tests for npc-behavior.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'npc-behavior)

;; --- npc-evaluate-condition ---

(ert-deftest test-npc-condition-always ()
  "always condition should return t."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25)))))
    (should (npc-evaluate-condition cr '(always)))))

(ert-deftest test-npc-condition-hp-below-true ()
  "hp-below should return t when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-below-false ()
  "hp-below should return nil when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (npc-evaluate-condition cr '(hp-below 15)))))

(ert-deftest test-npc-condition-hp-above-true ()
  "hp-above should return t when hp is above threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should (npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-hp-above-false ()
  "hp-above should return nil when hp is below threshold."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should-not (npc-evaluate-condition cr '(hp-above 15)))))

(ert-deftest test-npc-condition-player-in-room-true ()
  "player-in-room should return t when player symbol is in room creatures."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (should (npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-player-in-room-false ()
  "player-in-room should return nil when player not in room."
  (test-with-globals-saved (rooms-alist room-map current-room creatures-alist myself)
    (let* ((room (make-Room :symbol 'room1 :creature '(goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (should-not (npc-evaluate-condition goblin '(player-in-room))))))

(ert-deftest test-npc-condition-and ()
  "and should return t only when all sub-conditions are true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(and (hp-below 15) (hp-above 5))))
    (should-not (npc-evaluate-condition cr '(and (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-or ()
  "or should return t when any sub-condition is true."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 10)))))
    (should (npc-evaluate-condition cr '(or (hp-below 5) (hp-above 5))))
    (should-not (npc-evaluate-condition cr '(or (hp-below 5) (hp-above 15))))))

(ert-deftest test-npc-condition-not ()
  "not should invert condition result."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 20)))))
    (should-not (npc-evaluate-condition cr '(not (hp-above 10))))
    (should (npc-evaluate-condition cr '(not (hp-below 10))))))

;; --- npc-execute-action: attack ---

(ert-deftest test-npc-attack-player-deals-damage ()
  "npc attack should deal damage to player."
  (test-with-globals-saved (display-fn creatures-alist myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 8))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 3))))
      (setq tg-over-p nil)
      (npc-execute-action goblin '(attack))
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 95)))))

(ert-deftest test-npc-attack-player-kills ()
  "npc attack should set tg-over-p when player dies."
  (test-with-globals-saved (display-fn creatures-alist myself tg-over-p)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((attack . 50))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 10) (defense . 0))))
      (setq tg-over-p nil)
      (npc-execute-action goblin '(attack))
      (should tg-over-p))))

;; --- npc-execute-action: say ---

(ert-deftest test-npc-say-displays-message ()
  "npc say should display message via tg-display."
  (test-with-globals-saved (display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25))))
          (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (npc-execute-action goblin '(say "Hello!"))
      (should (cl-some (lambda (s) (string-match-p "goblin" s)) (mapcar #'car output))))))

;; --- npc-execute-action: move ---

(ert-deftest test-npc-move-random ()
  "npc move random should move creature to an adjacent room."
  (test-with-globals-saved (rooms-alist room-map current-room display-fn)
    (let* ((room1 (make-Room :symbol 'room1 :creature '(goblin)))
           (room2 (make-Room :symbol 'room2 :creature nil))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25)))))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq current-room room1)
      (setq display-fn #'ignore)
      (npc-execute-action goblin '(move random))
      (should-not (creature-exist-in-room-p room1 'goblin)))))

;; --- npc-execute-action: buff/debuff ---

(ert-deftest test-npc-buff-self ()
  "npc buff should increase creature's own attr."
  (test-with-globals-saved (display-fn)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq display-fn #'ignore)
      (npc-execute-action goblin '(buff attack 3))
      (should (= (cdr (assoc 'attack (Creature-attr goblin))) 8)))))

(ert-deftest test-npc-debuff-player ()
  "npc debuff should decrease player's attr."
  (test-with-globals-saved (display-fn myself)
    (let ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5)))))
      (setq display-fn #'ignore)
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (defense . 5))))
      (npc-execute-action goblin '(debuff defense 2))
      (should (= (cdr (assoc 'defense (Creature-attr myself))) 3)))))

;; --- npc-run-behaviors ---

(ert-deftest test-npc-run-behaviors-matches-first-rule ()
  "npc-run-behaviors should execute only the first matching rule."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 5))
                                  :behaviors '(((always) say "first") ((always) say "second"))))
           (room (make-Room :symbol 'room1 :creature '(hero goblin)))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (= 1 (cl-count-if (lambda (s) (string-match-p "first" s)) (mapcar #'car output)))))))

(ert-deftest test-npc-run-behaviors-skips-myself ()
  "npc-run-behaviors should skip myself even if it has behaviors."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))
                                  :behaviors '(((always) say "I act!"))))
      (setq creatures-alist (list (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-npc-run-behaviors-skips-dead-npc ()
  "npc-run-behaviors should skip NPCs with HP <= 0."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 0))
                                  :behaviors '(((always) say "I'm dead"))))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(ert-deftest test-npc-run-behaviors-no-behaviors-noop ()
  "npc-run-behaviors should do nothing for NPCs with nil behaviors."
  (test-with-globals-saved (display-fn creatures-alist myself rooms-alist room-map current-room tg-over-p)
    (let* ((goblin (make-Creature :symbol 'goblin :attr '((hp . 25)) :behaviors nil))
           (output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'goblin goblin) (cons 'hero myself)))
      (setq rooms-alist (list (cons 'room1 (make-Room :symbol 'room1 :creature '(hero goblin)))))
      (setq room-map '((room1)))
      (setq current-room (get-room-by-symbol 'room1))
      (setq tg-over-p nil)
      (npc-run-behaviors)
      (should (null output)))))

(provide 'test-npc-behavior)
