;;; test-quest-system.el --- Tests for quest-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'quest-system)

;; --- quest-init ---

(ert-deftest test-quest-init-loads-config ()
  "quest-init should load quests from config file."
  (test-with-temp-file "(kill-rats \"消灭老鼠\" kill rat 3 ((exp . 15)) inactive \"老鼠被消灭了！\")\n(find-key \"找到钥匙\" collect key 1 ((exp . 20)) inactive \"你找到了钥匙！\")"
    (test-with-globals-saved (quests-alist)
      (quest-init temp-file)
      (should (= (length quests-alist) 2))
      (should (equal (Quest-type (cdr (assoc 'kill-rats quests-alist))) 'kill))
      (should (equal (Quest-type (cdr (assoc 'find-key quests-alist))) 'collect)))))

(ert-deftest test-quest-init-preserves-status ()
  "quest-init should preserve status from config file."
  (test-with-temp-file "(test-quest \"Test\" kill rat 1 ((exp . 10)) inactive \"Done!\")"
    (test-with-globals-saved (quests-alist)
      (quest-init temp-file)
      (should (eq (Quest-status (cdr (assoc 'test-quest quests-alist))) 'inactive)))))

(ert-deftest test-quest-accept-activates ()
  "quest-accept should change inactive quest to active."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :description "Test" :type 'kill :target 'rat
                          :count 1 :status 'inactive)))
      (setq quests-alist (list (cons 'test-q q)))
      (quest-accept 'test-q)
      (should (eq (Quest-status q) 'active)))))

(ert-deftest test-quest-accept-rejects-non-inactive ()
  "quest-accept should reject quests that are not inactive."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :description "Test" :type 'kill :target 'rat
                          :count 1 :status 'active)))
      (setq quests-alist (list (cons 'test-q q)))
      (should (equal (catch 'exception (quest-accept 'test-q))
                     "任务Test当前状态无法接受")))))

;; --- quest-track-kill ---

(ert-deftest test-quest-track-kill-updates-progress ()
  "quest-track-kill should increment progress for matching kill quests."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 3 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'kill-goblin q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'goblin)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'active)))))

(ert-deftest test-quest-track-kill-completes ()
  "quest-track-kill should complete quest when progress reaches count."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 0
                          :status 'active :description "Kill rat" :description-complete "Done!"))
          (output nil))
      (setq quests-alist (list (cons 'kill-rat q)))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

(ert-deftest test-quest-track-kill-skips-completed ()
  "quest-track-kill should not update completed quests."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-rat :type 'kill :target 'rat :count 1 :progress 1
                          :status 'completed)))
      (setq quests-alist (list (cons 'kill-rat q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 1)))))

(ert-deftest test-quest-track-kill-no-match ()
  "quest-track-kill should do nothing when no matching quest."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'kill-goblin :type 'kill :target 'goblin :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'kill-goblin q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'kill 'rat)
      (should (= (Quest-progress q) 0)))))

;; --- quest-track-collect ---

(ert-deftest test-quest-track-collect-updates-progress ()
  "quest-track-collect should increment progress for matching collect quests."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'find-key :type 'collect :target 'key :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'find-key q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'collect 'key)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-track-explore ---

(ert-deftest test-quest-track-explore-updates-progress ()
  "quest-track-explore should increment progress for matching explore quests."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'reach-hall :type 'explore :target 'hall :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'reach-hall q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'explore 'hall)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-track-talk ---

(ert-deftest test-quest-track-talk-updates-progress ()
  "quest-track-talk should increment progress for matching talk quests."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'talk-guard :type 'talk :target 'guard :count 1 :progress 0 :status 'active)))
      (setq quests-alist (list (cons 'talk-guard q)))
      (setq tg-display-fn #'ignore)
      (tg-track-quest 'talk 'guard)
      (should (= (Quest-progress q) 1))
      (should (eq (Quest-status q) 'completed)))))

;; --- quest-apply-rewards ---

(ert-deftest test-quest-reward-exp ()
  "quest-apply-rewards should grant exp."
  (test-with-globals-saved (quests-alist tg-display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let ((q (make-Quest :symbol 'test-q :rewards '((exp . 50)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-item ()
  "quest-apply-rewards should add item to player inventory."
  (test-with-globals-saved (quests-alist tg-display-fn creatures-alist inventorys-alist)
    (let ((q (make-Quest :symbol 'test-q :rewards '((item . potion)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq tg-display-fn #'ignore)
      (setq inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (member 'potion (Creature-inventory cr)))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-bonus-points ()
  "quest-apply-rewards should grant bonus-points."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let ((q (make-Quest :symbol 'test-q :rewards '((bonus-points . 2)) :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (let ((old-myself myself))
        (setq myself cr)
        (quest-apply-rewards q)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq myself old-myself)))))

(ert-deftest test-quest-reward-trigger ()
  "quest-apply-rewards should call trigger function."
  (test-with-globals-saved (quests-alist tg-display-fn)
    (let (trigger-called)
      (let ((trigger-fn (lambda () (setq trigger-called t))))
        (let ((q (make-Quest :symbol 'test-q :rewards `((trigger . ,trigger-fn)) :status 'active)))
          (setq tg-display-fn #'ignore)
          (quest-apply-rewards q)
          (should trigger-called))))))

(provide 'test-quest-system)
