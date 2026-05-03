;;; test-quest-system.el --- Tests for quest-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'quest-system)

;; --- tg-quest-init ---

(ert-deftest test-quest-init-loads-config ()
  "tg-quest-init should load quests from config file."
  (test-with-temp-file "(kill-rats \"消灭老鼠\" kill rat 3 ((exp . 15)) inactive \"老鼠被消灭了！\")\n(find-key \"找到钥匙\" collect key 1 ((exp . 20)) inactive \"你找到了钥匙！\")"
    (test-with-globals-saved (tg-quests-alist)
      (tg-quest-init temp-file)
      (should (= (length tg-quests-alist) 2))
      (should (equal (Quest-type (cdr (assoc 'kill-rats tg-quests-alist))) 'kill))
      (should (equal (Quest-type (cdr (assoc 'find-key tg-quests-alist))) 'collect)))))

(ert-deftest test-quest-init-preserves-status ()
  "tg-quest-init should preserve status from config file."
  (test-with-temp-file "(test-quest \"Test\" kill rat 1 ((exp . 10)) inactive \"Done!\")"
    (test-with-globals-saved (tg-quests-alist)
      (tg-quest-init temp-file)
      (should (eq (Quest-status (cdr (assoc 'test-quest tg-quests-alist))) 'inactive)))))

(ert-deftest test-tg-quest-accept-activates ()
  "tg-quest-accept should change inactive quest to active."
  (test-with-globals-saved (tg-quests-alist)
    (let ((q (make-Quest :symbol 'test-q :description "Test" :type 'kill :target 'rat
                          :count 1 :status 'inactive)))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (tg-quest-accept 'test-q)
      (should (eq (Quest-status q) 'active)))))

(ert-deftest test-tg-quest-accept-rejects-non-inactive ()
  "tg-quest-accept should reject quests that are not inactive."
  (test-with-globals-saved (tg-quests-alist)
    (let ((q (make-Quest :symbol 'test-q :description "Test" :type 'kill :target 'rat
                          :count 1 :status 'active)))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (should (equal (catch 'exception (tg-quest-accept 'test-q))
                     "任务Test当前状态无法接受")))))

;; --- tg-track-quest ---

(ert-deftest test-tg-track-quest-updates-progress-kill ()
  "tg-track-quest should increment progress for matching kill quests."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 3 :progress 0 :status 'active)))
      (setq tg-quests-alist (list (cons 'kill-goblin q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'goblin)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'active)))))

(ert-deftest test-tg-track-quest-completes ()
  "tg-track-quest should complete quest when progress reaches count."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 0
                          :status 'active :description "Kill rat" :description-complete "Done!"))
          (output nil))
      (setq tg-quests-alist (list (cons 'kill-rat q)))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

(ert-deftest test-tg-track-quest-skips-completed ()
  "tg-track-quest should not update completed quests."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 1
                          :status 'completed)))
      (setq tg-quests-alist (list (cons 'kill-rat q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 1)))))

(ert-deftest test-tg-track-quest-no-match ()
  "tg-track-quest should do nothing when no matching quest."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 1 :progress 0 :status 'active)))
      (setq tg-quests-alist (list (cons 'kill-goblin q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 0)))))

;; --- tg-track-quest ---

(ert-deftest test-tg-track-quest-updates-progress-collect ()
  "tg-track-quest should increment progress for matching collect quests."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'find-key :type 'collect :target 'key :count 1 :progress 0 :status 'active)))
      (setq tg-quests-alist (list (cons 'find-key q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'collect 'key)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- tg-track-quest ---

(ert-deftest test-tg-track-quest-updates-progress-explore ()
  "tg-track-quest should increment progress for matching explore quests."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'reach-hall :type 'explore :target 'hall :count 1 :progress 0 :status 'active)))
      (setq tg-quests-alist (list (cons 'reach-hall q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'explore 'hall)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- tg-track-quest ---

(ert-deftest test-tg-track-quest-updates-progress-talk ()
  "tg-track-quest should increment progress for matching talk quests."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'talk-guard :type 'talk :target 'guard :count 1 :progress 0 :status 'active)))
      (setq tg-quests-alist (list (cons 'talk-guard q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'talk 'guard)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- tg-quest-apply-rewards ---

(ert-deftest test-quest-reward-exp ()
  "tg-quest-apply-rewards should grant exp."
  (test-with-globals-saved (tg-quests-alist tg-display-fn tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs)
    (let ((q (make-Quest :symbol 'test-q :rewards '((exp . 50)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (setq tg-level-exp-table '(0 100))
      (setq tg-level-up-bonus-points 3)
      (setq tg-auto-upgrade-attrs '((hp . 5)))
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-quest-apply-rewards q)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-quest-reward-item ()
  "tg-quest-apply-rewards should add item to player inventory."
  (test-with-globals-saved (tg-quests-alist tg-display-fn tg-creatures-alist tg-inventorys-alist)
    (let ((q (make-Quest :symbol 'test-q :rewards '((item . potion)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq tg-display-fn #'ignore)
      (setq tg-inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-quest-apply-rewards q)
        (should (member 'potion (Creature-inventory cr)))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-quest-reward-bonus-points ()
  "tg-quest-apply-rewards should grant bonus-points."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'test-q :rewards '((bonus-points . 2)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-quest-apply-rewards q)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-quest-reward-trigger ()
  "tg-quest-apply-rewards should call trigger function."
  (test-with-globals-saved (tg-quests-alist tg-display-fn)
    (let (trigger-called)
      (let ((trigger-fn (lambda () (setq trigger-called t))))
        (let ((q (make-Quest :symbol 'test-q :rewards `((trigger . ,trigger-fn)) :status 'active)))
          (setq tg-display-fn #'ignore)
          (tg-quest-apply-rewards q)
          (should trigger-called))))))

(provide 'test-quest-system)
