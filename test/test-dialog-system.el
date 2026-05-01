;;; test-dialog-system.el --- Tests for dialog-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'dialog-system)

;; --- dialog-init ---

(ert-deftest test-dialog-init-loads-config ()
  "dialog-init should load dialogs from config file."
  (test-with-temp-file "(prisoner \"请救救我\" ((\"你是谁？\" \"探险者\" nil nil)))"
    (test-with-globals-saved (dialogs-alist)
      (dialog-init temp-file)
      (should (= (length dialogs-alist) 1))
      (should (eq (Dialog-npc (cdr (assoc 'prisoner dialogs-alist))) 'prisoner))
      (should (equal (Dialog-greeting (cdr (assoc 'prisoner dialogs-alist))) "请救救我"))
      (should (= (length (Dialog-options (cdr (assoc 'prisoner dialogs-alist)))) 1)))))

;; --- dialog-evaluate-condition ---

(ert-deftest test-dialog-evaluate-condition-nil ()
  "nil condition should always be true."
  (should (dialog-evaluate-condition nil)))

(ert-deftest test-dialog-evaluate-condition-quest-active ()
  "quest-active should match active quests."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'active)))
      (setq quests-alist (list (cons 'test-q q)))
      (should (dialog-evaluate-condition '(quest-active test-q)))
      (should-not (dialog-evaluate-condition '(quest-active other-q))))))

(ert-deftest test-dialog-evaluate-condition-quest-completed ()
  "quest-completed should match completed quests."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'test-q :status 'completed)))
      (setq quests-alist (list (cons 'test-q q)))
      (should (dialog-evaluate-condition '(quest-completed test-q)))
      (should-not (dialog-evaluate-condition '(quest-completed other-q))))))

(ert-deftest test-dialog-evaluate-condition-has-item ()
  "has-item should check player inventory."
  (test-with-globals-saved (myself)
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword potion))))
      (setq myself cr)
      (should (dialog-evaluate-condition '(has-item sword)))
      (should (dialog-evaluate-condition '(has-item potion)))
      (should-not (dialog-evaluate-condition '(has-item shield))))))

(ert-deftest test-dialog-evaluate-condition-and ()
  "and should require all conditions true."
  (test-with-globals-saved (quests-alist myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq quests-alist (list (cons 'test-q q)))
      (setq myself cr)
      (should (dialog-evaluate-condition '(and (quest-active test-q) (has-item sword))))
      (should-not (dialog-evaluate-condition '(and (quest-active test-q) (has-item shield)))))))

(ert-deftest test-dialog-evaluate-condition-or ()
  "or should require at least one condition true."
  (test-with-globals-saved (quests-alist myself)
    (let ((q (make-Quest :symbol 'test-q :status 'active))
          (cr (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword))))
      (setq quests-alist (list (cons 'test-q q)))
      (setq myself cr)
      (should (dialog-evaluate-condition '(or (quest-active test-q) (has-item shield))))
      (should-not (dialog-evaluate-condition '(or (quest-active other-q) (has-item shield)))))))

;; --- dialog-get-visible-options ---

(ert-deftest test-dialog-get-visible-options ()
  "Should filter options by condition."
  (test-with-globals-saved (quests-alist)
    (let ((q (make-Quest :symbol 'find-key :status 'active)))
      (setq quests-alist (list (cons 'find-key q)))
      (let* ((opt1 (make-DialogOption :text "A" :response "R1" :condition nil))
             (opt2 (make-DialogOption :text "B" :response "R2" :condition '(quest-active find-key)))
             (opt3 (make-DialogOption :text "C" :response "R3" :condition '(quest-completed find-key)))
             (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt1 opt2 opt3))))
        (let ((visible (dialog-get-visible-options dialog)))
          (should (= (length visible) 2))
          (should (equal (DialogOption-text (nth 0 visible)) "A"))
          (should (equal (DialogOption-text (nth 1 visible)) "B")))))))

;; --- dialog-apply-effects ---

(ert-deftest test-dialog-apply-effects-exp ()
  "dialog-apply-effects should grant exp."
  (test-with-globals-saved (display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :effects '((exp . 50))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 50))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-item ()
  "dialog-apply-effects should add item to player inventory."
  (test-with-globals-saved (display-fn creatures-alist inventorys-alist)
    (let* ((opt (make-DialogOption :effects '((item . potion))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
      (setq display-fn #'ignore)
      (setq inventorys-alist (list (cons 'potion (make-Inventory :symbol 'potion :description "Potion" :type '(usable)))))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (member 'potion (Creature-inventory cr)))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-bonus-points ()
  "dialog-apply-effects should grant bonus-points."
  (test-with-globals-saved (display-fn)
    (let* ((opt (make-DialogOption :effects '((bonus-points . 2))))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 0)))))
      (setq display-fn #'ignore)
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-apply-effects opt)
        (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 2))
        (setq myself old-myself)))))

(ert-deftest test-dialog-apply-effects-trigger ()
  "dialog-apply-effects should call trigger function."
  (test-with-globals-saved (display-fn)
    (let (trigger-called)
      (let ((trigger-fn (lambda () (setq trigger-called t))))
        (let ((opt (make-DialogOption :effects `((trigger . ,trigger-fn)))))
          (setq display-fn #'ignore)
          (dialog-apply-effects opt)
          (should trigger-called))))))

;; --- dialog-start ---

(ert-deftest test-dialog-start-success ()
  "dialog-start should display greeting and options, set dialog-pending."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending)
    (let* ((opt (make-DialogOption :text "Hello" :response "Hi" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "What?" :options (list opt)))
           (output nil))
      (setq dialogs-alist (list (cons 'guard dialog)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-start 'guard)
      (should (eq dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "What?" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-start-no-dialog ()
  "dialog-start should throw when NPC has no dialog."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending)
    (setq dialogs-alist nil)
    (setq display-fn #'ignore)
    (should (equal (catch 'exception (dialog-start 'nobody)) "无法与nobody对话"))))

(ert-deftest test-dialog-start-no-visible-options ()
  "dialog-start should show message when no options are visible."
  (test-with-globals-saved (dialogs-alist display-fn dialog-pending quests-alist)
    (let* ((opt (make-DialogOption :text "Hidden" :response "R" :condition '(quest-active missing)))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialogs-alist (list (cons 'guard dialog)))
      (setq display-fn (lambda (&rest args) (push args output)))
      (setq quests-alist nil)
      (dialog-start 'guard)
      (should (null dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "没有可用的对话选项" s)) (mapcar #'car output))))))

;; --- dialog-handle-choice ---

(ert-deftest test-dialog-handle-choice-valid ()
  "dialog-handle-choice should process valid choice and clear dialog-pending."
  (test-with-globals-saved (dialog-pending display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "Response A" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialog-pending dialog)
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-handle-choice "1")
      (should (null dialog-pending))
      (should (cl-some (lambda (s) (string-match-p "Response A" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-handle-choice-invalid ()
  "dialog-handle-choice should keep dialog-pending on invalid input."
  (test-with-globals-saved (dialog-pending display-fn)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (output nil))
      (setq dialog-pending dialog)
      (setq display-fn (lambda (&rest args) (push args output)))
      (dialog-handle-choice "5")
      (should (eq dialog-pending dialog))
      (should (cl-some (lambda (s) (string-match-p "请输入有效的选项编号" s)) (mapcar #'car output))))))

(ert-deftest test-dialog-handle-choice-applies-effects ()
  "dialog-handle-choice should apply effects on valid choice."
  (test-with-globals-saved (dialog-pending display-fn level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (let* ((opt (make-DialogOption :text "A" :response "R" :condition nil :effects '((exp . 30))))
           (dialog (make-Dialog :npc 'guard :greeting "Hi" :options (list opt)))
           (cr (make-Creature :symbol 'hero :attr '((hp . 100) (exp . 0) (level . 1) (bonus-points . 0)))))
      (setq dialog-pending dialog)
      (setq display-fn #'ignore)
      (setq level-exp-table '(0 100))
      (setq level-up-bonus-points 3)
      (setq auto-upgrade-attrs '((hp . 5)))
      (let ((old-myself myself))
        (setq myself cr)
        (dialog-handle-choice "1")
        (should (= (cdr (assoc 'exp (Creature-attr cr))) 30))
        (should (null dialog-pending))
        (setq myself old-myself)))))

(provide 'test-dialog-system)
