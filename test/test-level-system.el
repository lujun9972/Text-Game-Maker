;;; test-level-system.el --- Tests for level-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'level-system)

;; --- tg-level-init ---

(ert-deftest test-tg-level-init-loads-config ()
  "tg-level-init should load level config from file."
  (test-with-temp-file "(tg-level-exp-table 0 100 250 500)
                         (tg-level-up-bonus-points 3)
                         (tg-auto-upgrade-attrs ((hp . 5)))"
    (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs)
      (tg-level-init temp-file)
      (should (equal tg-level-exp-table '(0 100 250 500)))
      (should (= tg-level-up-bonus-points 3))
      (should (equal tg-auto-upgrade-attrs '((hp . 5)))))))

;; --- tg-get-exp-reward ---

(ert-deftest test-tg-get-exp-reward-explicit ()
  "tg-get-exp-reward should return explicit exp-reward value."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6) (defense . 2)) :exp-reward 15)))
    (should (= (tg-get-exp-reward cr) 15))))

(ert-deftest test-tg-get-exp-reward-auto-calculate ()
  "tg-get-exp-reward should auto-calculate from hp+attack+defense when exp-reward is nil."
  (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6) (defense . 2)) :exp-reward nil)))
    (should (= (tg-get-exp-reward cr) 33))))

(ert-deftest test-tg-get-exp-reward-auto-missing-attrs ()
  "tg-get-exp-reward should treat missing attrs as 0."
  (let ((cr (make-Creature :symbol 'blob :attr '((hp . 10)) :exp-reward nil)))
    (should (= (tg-get-exp-reward cr) 10))))

;; --- tg-add-exp-to-creature ---

(ert-deftest test-add-exp-accumulates ()
  "tg-add-exp-to-creature should add exp to creature's attr."
  (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs tg-display-fn)
    (setq tg-level-exp-table '(0 100 250))
    (setq tg-level-up-bonus-points 3)
    (setq tg-auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-add-exp-to-creature cr 50)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 1)))))

(ert-deftest test-add-exp-triggers-level-up ()
  "tg-add-exp-to-creature should level up when exp reaches threshold."
  (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs tg-display-fn)
    (setq tg-level-exp-table '(0 100 250))
    (setq tg-level-up-bonus-points 3)
    (setq tg-auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-add-exp-to-creature cr 120)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 120))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 2))
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 105))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 3)))))

(ert-deftest test-add-exp-multi-level-up ()
  "tg-add-exp-to-creature should handle multiple level ups at once."
  (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs tg-display-fn)
    (setq tg-level-exp-table '(0 100 250 500))
    (setq tg-level-up-bonus-points 3)
    (setq tg-auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-add-exp-to-creature cr 300)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 300))
      (should (= (cdr (assoc 'level (Creature-attr cr))) 3))
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 6)))))

(ert-deftest test-add-exp-max-level ()
  "tg-add-exp-to-creature should not level up beyond exp-table range."
  (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs tg-display-fn)
    (setq tg-level-exp-table '(0 100 250))
    (setq tg-level-up-bonus-points 3)
    (setq tg-auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 200) (level . 2) (bonus-points . 3))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-add-exp-to-creature cr 500)
      (should (= (cdr (assoc 'exp (Creature-attr cr))) 700))
      ;; Already at max level (2), exp-table has entries for 1->2 only
      (should (= (cdr (assoc 'level (Creature-attr cr))) 2)))))

(ert-deftest test-add-exp-no-level-attrs ()
  "tg-add-exp-to-creature should do nothing special when creature has no level/exp attrs."
  (test-with-globals-saved (tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs tg-display-fn)
    (setq tg-level-exp-table '(0 100))
    (setq tg-level-up-bonus-points 3)
    (setq tg-auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6))))
          (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-add-exp-to-creature cr 50)
      ;; exp not in attr, so no effect
      (should (null (assoc 'exp (Creature-attr cr)))))))

(provide 'test-level-system)
