;;; test-dialog-system.el --- Tests for dialog-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'dialog-system)

;; --- dialog-init ---

(ert-deftest test-dialog-init-loads-config ()
  "dialog-init should load dialogs from config file."
  (test-with-temp-file "(prisoner \"请救救我\" ((\"你是谁？\" \"探险者\" nil nil)))"
    (test-with-globals-saved (tg-dialogs-alist)
      (tg-dialog-init temp-file)
      (should (= (length tg-dialogs-alist) 1))
      (should (eq (Dialog-npc (cdr (assoc 'prisoner tg-dialogs-alist))) 'prisoner))
      (should (equal (Dialog-greeting (cdr (assoc 'prisoner tg-dialogs-alist))) "请救救我"))
      (should (= (length (Dialog-options (cdr (assoc 'prisoner tg-dialogs-alist)))) 1)))))

;; --- tg-dialog-evaluate-condition ---

(ert-deftest test-tg-dialog-evaluate-condition-nil ()
  "nil condition should always be true."
  (should (tg-dialog-evaluate-condition nil)))

(ert-deftest test-tg-dialog-evaluate-condition-quest-active ()
  "quest-active should match active quests."
  (test-with-globals-saved (tg-quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'active)))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (should (tg-dialog-evaluate-condition '(quest-active test-q)))
      (should-not (tg-dialog-evaluate-condition '(quest-active other-q))))))

(ert-deftest test-tg-dialog-evaluate-condition-quest-completed ()
  "quest-completed should match completed quests."
  (test-with-globals-saved (tg-quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'completed)))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (should (tg-dialog-evaluate-condition '(quest-completed test-q)))
      (should-not (tg-dialog-evaluate-condition '(quest-completed other-q))))))

(ert-deftest test-tg-dialog-evaluate-condition-has-item ()
  "has-item should check player inventory."
  (test-with-globals-saved (tg-myself)
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword potion))))
      (setq tg-myself cr)
      (should (tg-dialog-evaluate-condition '(has-item sword)))
      (should (tg-dialog-evaluate-condition '(has-item potion)))
      (should-not (tg-dialog-evaluate-condition '(has-item shield))))))

(ert-deftest test-tg-dialog-evaluate-condition-and ()
  "and should require all conditions true."
  (test-with-globals-saved (tg-quests-alist tg-myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (setq tg-myself cr)
      (should (tg-dialog-evaluate-condition '(and (quest-active test-q) (has-item sword))))
      (should-not (tg-dialog-evaluate-condition '(and (quest-active test-q) (has-item shield)))))))

(ert-deftest test-tg-dialog-evaluate-condition-or ()
  "or should require at least one condition true."
  (test-with-globals-saved (tg-quests-alist tg-myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq tg-quests-alist (list (cons 'test-q q)))
      (setq tg-myself cr)
      (should (tg-dialog-evaluate-condition '(or (quest-active test-q) (has-item shield))))
      (should-not (tg-dialog-evaluate-condition '(or (quest-active other-q) (has-item shield)))))))

;; --- tg-dialog-get-visible-options ---

(ert-deftest test-tg-dialog-get-visible-options ()
  "Should filter options by condition."
  (test-with-globals-saved (tg-quests-alist)
    (let ((q (make-Quest :symbol 'find-key :status 'active)))
      (setq tg-quests-alist (list (cons 'find-key q)))
      (let* ((opt1 (make-DialogOption :text "A" :response "R1" :condition nil))
             (opt2 (make-DialogOption :text "B" :response "R2" :condition '(quest-active find-key)))
             (opt3 (make-DialogOption :text "C" :response "R3" :condition '(quest-completed find-key)))
             (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt1 opt2 opt3))))
        (let ((visible (tg-dialog-get-visible-options dialog)))
          (should (= (length visible) 2))
          (should (equal (DialogOption-text (nth 0 visible)) "A"))
          (should (equal (DialogOption-text (nth 1 visible)) "B")))))))

;; --- tg-dialog-apply-effects ---

(ert-deftest test-tg-dialog-apply-effects-exp ()
  "tg-dialog-apply-effects should grant exp."
  (test-with-globals-saved (tg-display-fn tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :effects '((exp . 50))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (setq tg-level-exp-table '(0 100))
      (setq tg-level-up-bonus-points 3)
      (setq tg-auto-upgrade-attrs '((hp . 5)))
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-dialog-apply-effects opt)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-tg-dialog-apply-effects-item ()
  "tg-dialog-apply-effects should add item to player inventory."
  (test-with-globals-saved (tg-display-fn tg-creatures-alist tg-inventorys-alist)
    (let* ((opt (make-DialogOption :effects '((item . potion))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq tg-display-fn #'ignore)
      (setq tg-inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-dialog-apply-effects opt)
        (should (member 'potion (Creature-inventory cr)))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-tg-dialog-apply-effects-bonus-points ()
  "tg-dialog-apply-effects should grant bonus-points."
  (test-with-globals-saved (tg-display-fn)
    (let* ((opt (make-DialogOption :effects '((bonus-points . 2))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq tg-display-fn #'ignore)
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-dialog-apply-effects opt)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq tg-myself old-tg-myself)))))

(ert-deftest test-tg-dialog-apply-effects-trigger ()
  "tg-dialog-apply-effects should call trigger function."
  (test-with-globals-saved (tg-display-fn)
    (let (trigger-called)
      (let ((trigger-fn (lambda () (setq trigger-called t))))
        (let ((opt (make-DialogOption :effects `((trigger . ,trigger-fn)))))
          (setq tg-display-fn #'ignore)
          (tg-dialog-apply-effects opt)
          (should trigger-called))))))

;; --- tg-dialog-start ---

(ert-deftest test-tg-dialog-start-success ()
  "tg-dialog-start should display greeting and options, set tg-dialog-pending."
  (test-with-globals-saved (tg-dialogs-alist tg-display-fn tg-dialog-pending)
    (let* ((opt (make-DialogOption :text "Hello" :response "Hi" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "What?" :options (list opt)))
           (output nil))
      (setq tg-dialogs-alist (list (cons 'guard dialog)))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-dialog-start 'guard)
      (should (eq tg-dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "What?" s)) (mapcar #'car output))))))

(ert-deftest test-tg-dialog-start-no-dialog ()
  "tg-dialog-start should throw when NPC has no dialog."
  (test-with-globals-saved (tg-dialogs-alist tg-display-fn tg-dialog-pending)
    (setq tg-dialogs-alist nil)
    (setq tg-display-fn #'ignore)
    (should (equal (catch 'exception (tg-dialog-start 'nobody)) "无法与nobody对话"))))

(ert-deftest test-tg-dialog-start-no-visible-options ()
  "tg-dialog-start should show message when no options are visible."
  (test-with-globals-saved (tg-dialogs-alist tg-display-fn tg-dialog-pending tg-quests-alist)
    (let* ((opt (make-DialogOption :text "Hidden" :response "R" :condition '(quest-active missing)))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq tg-dialogs-alist (list (cons 'guard dialog)))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-quests-alist nil)
      (tg-dialog-start 'guard)
      (should (null tg-dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "没有可用的对话选项" s)) (mapcar #'car output))))))

;; --- tg-dialog-handle-choice ---

(ert-deftest test-tg-dialog-handle-choice-valid ()
  "tg-dialog-handle-choice should process valid choice and clear tg-dialog-pending."
  (test-with-globals-saved (tg-dialog-pending tg-display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "Response A" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq tg-dialog-pending dialog)
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-dialog-handle-choice "1")
      (should (null tg-dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "Response A" s)) (mapcar #'car output))))))

(ert-deftest test-tg-dialog-handle-choice-invalid ()
  "tg-dialog-handle-choice should keep tg-dialog-pending on invalid input."
  (test-with-globals-saved (tg-dialog-pending tg-display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq tg-dialog-pending dialog)
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (tg-dialog-handle-choice "5")
      (should (eq tg-dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "请输入有效的选项编号" s)) (mapcar #'car output))))))

(ert-deftest test-tg-dialog-handle-choice-applies-effects ()
  "tg-dialog-handle-choice should apply effects on valid choice."
  (test-with-globals-saved (tg-dialog-pending tg-display-fn tg-level-exp-table tg-level-up-bonus-points tg-auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil :effects '((exp . 30))))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq tg-dialog-pending dialog)
      (setq tg-display-fn #'ignore)
      (setq tg-level-exp-table '(0 100))
      (setq tg-level-up-bonus-points 3)
      (setq tg-auto-upgrade-attrs '((hp . 5)))
      (let ((old-tg-myself tg-myself))
        (setq tg-myself cr)
        (tg-dialog-handle-choice "1")
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 30))
        (should (null tg-dialog-pending))
        (setq tg-myself old-tg-myself)))))

(provide 'test-dialog-system)
