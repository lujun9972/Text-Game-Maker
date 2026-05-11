;;; test/tg-dialog-test-v3.el --- tg-dialog 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-game)
(require 'tg-dialog)
(require 'tg-quest)

(ert-deftest test-tg-dialog-state-create ()
  "测试对话状态创建"
  (let* ((option (make-tg-dialog-option
                  :text "你好"
                  :response "你好啊"
                  :condition nil
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "站住！"
                 :options (list option))))
    (should (eq (tg-dialog-state-node-id state) 'guard))
    (should (eq (tg-dialog-state-npc-symbol state) 'guard))
    (should (equal (tg-dialog-state-greeting state) "站住！"))
    (should (= (length (tg-dialog-state-options state)) 1))
    (should (equal (tg-dialog-option-text (car (tg-dialog-state-options state))) "你好"))))

(ert-deftest test-tg-dialog-option-create ()
  "测试对话选项创建"
  (let* ((option (make-tg-dialog-option
                  :text "选择A"
                  :response "回复A"
                  :condition '(has-item sword)
                  :effects '((exp 10))
                  :next-node 'node-a)))
    (should (equal (tg-dialog-option-text option) "选择A"))
    (should (equal (tg-dialog-option-response option) "回复A"))
    (should (equal (tg-dialog-option-condition option) '(has-item sword)))
    (should (equal (tg-dialog-option-effects option) '((exp 10))))
    (should (eq (tg-dialog-option-next-node option) 'node-a))))

(ert-deftest test-tg-dialog-start-basic ()
  "测试基本对话启动"
  (tg-registry-clear)
  (let* ((option (make-tg-dialog-option
                  :text "你好"
                  :response "你好啊"
                  :condition nil
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "站住！"
                 :options (list option))))
    (setq tg-dialog-pending nil)
    (tg-register-dialog 'guard state)
    (should (null tg-dialog-pending))
    (tg-dialog-start 'guard)
    (should (eq tg-dialog-pending state))))

(ert-deftest test-tg-dialog-start-no-dialog ()
  "测试对话启动时NPC不存在"
  (tg-registry-clear)
  (should-error (tg-dialog-start 'unknown-npc)))

(ert-deftest test-tg-dialog-start-no-visible-options ()
  "测试对话启动时没有可见选项"
  (tg-registry-clear)
  (let* ((option (make-tg-dialog-option
                  :text "隐藏选项"
                  :response "回复"
                  :condition '(quest-active missing-quest)
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "你好"
                 :options (list option))))
    (tg-register-dialog 'guard state)
    (tg-dialog-start 'guard)
    (should (null tg-dialog-pending))))

(ert-deftest test-tg-dialog-handle-choice-valid ()
  "测试选择有效选项"
  (tg-registry-clear)
  (let* ((option (make-tg-dialog-option
                  :text "选择A"
                  :response "回复A"
                  :condition nil
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "你好"
                 :options (list option))))
    (setq tg-dialog-pending state)
    (tg-dialog-handle-choice "1")
    (should (null tg-dialog-pending))))

(ert-deftest test-tg-dialog-handle-choice-invalid ()
  "测试选择无效选项"
  (tg-registry-clear)
  (let* ((option (make-tg-dialog-option
                  :text "选择A"
                  :response "回复A"
                  :condition nil
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "你好"
                 :options (list option))))
    (setq tg-dialog-pending state)
    (should-error (tg-dialog-handle-choice "5"))
    (should (eq tg-dialog-pending state))))

(ert-deftest test-tg-dialog-handle-choice-no-pending ()
  "测试没有待处理对话时选择"
  (setq tg-dialog-pending nil)
  (should-error (tg-dialog-handle-choice "1")))

(ert-deftest test-tg-dialog-handle-choice-with-next-node ()
  "测试选择选项后跳转到下一节点"
  (tg-registry-clear)
  (let* ((option2 (make-tg-dialog-option
                   :text "选择B"
                   :response "回复B"
                   :condition nil
                   :effects nil
                   :next-node nil))
         (state2 (make-tg-dialog-state
                  :node-id 'node-b
                  :npc-symbol 'guard
                  :greeting "第二节"
                  :options (list option2)))
         (option1 (make-tg-dialog-option
                   :text "选择A"
                   :response "回复A"
                   :condition nil
                   :effects nil
                   :next-node 'node-b))
         (state1 (make-tg-dialog-state
                  :node-id 'node-a
                  :npc-symbol 'guard
                  :greeting "第一节"
                  :options (list option1))))
    (tg-register-dialog 'node-a state1)
    (tg-register-dialog 'node-b state2)
    (setq tg-dialog-pending state1)
    (tg-dialog-handle-choice "1")
    (should (eq tg-dialog-pending state2))))

(ert-deftest test-tg-dialog-filter-options-no-condition ()
  "测试过滤选项：无条件选项总是可见"
  (tg-registry-clear)
  (let* ((option (make-tg-dialog-option
                  :text "可见选项"
                  :response "回复"
                  :condition nil
                  :effects nil
                  :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "你好"
                 :options (list option))))
    (let ((visible (tg-dialog-filter-options state)))
      (should (= (length visible) 1))
      (should (equal (tg-dialog-option-text (car visible)) "可见选项")))))

(ert-deftest test-tg-dialog-filter-options-with-condition ()
  "测试过滤选项：根据条件过滤"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword)))
         (option1 (make-tg-dialog-option
                   :text "有剑选项"
                   :response "回复1"
                   :condition '(has-item sword)
                   :effects nil
                   :next-node nil))
         (option2 (make-tg-dialog-option
                   :text "有盾选项"
                   :response "回复2"
                   :condition '(has-item shield)
                   :effects nil
                   :next-node nil))
         (state (make-tg-dialog-state
                 :node-id 'guard
                 :npc-symbol 'guard
                 :greeting "你好"
                 :options (list option1 option2))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (let ((visible (tg-dialog-filter-options state)))
      (should (= (length visible) 1))
      (should (equal (tg-dialog-option-text (car visible)) "有剑选项")))))

(ert-deftest test-tg-dialog-eval-condition-nil ()
  "测试条件求值：nil总是真"
  (should (tg-dialog-eval-condition nil tg-game)))

(ert-deftest test-tg-dialog-eval-condition-quest-active ()
  "测试条件求值：quest-active"
  (tg-registry-clear)
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 0
                 :status 'active
                 :rewards nil)))
    (tg-register-quest 'test-quest quest)
    (should (tg-dialog-eval-condition '(quest-active test-quest) tg-game))
    (should-not (tg-dialog-eval-condition '(quest-active other-quest) tg-game))))

(ert-deftest test-tg-dialog-eval-condition-quest-completed ()
  "测试条件求值：quest-completed"
  (tg-registry-clear)
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 1
                 :status 'completed
                 :rewards nil)))
    (tg-register-quest 'test-quest quest)
    (should (tg-dialog-eval-condition '(quest-completed test-quest) tg-game))
    (should-not (tg-dialog-eval-condition '(quest-completed other-quest) tg-game))))

(ert-deftest test-tg-dialog-eval-condition-has-item ()
  "测试条件求值：has-item"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword potion))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (should (tg-dialog-eval-condition '(has-item sword) tg-game))
    (should (tg-dialog-eval-condition '(has-item potion) tg-game))
    (should-not (tg-dialog-eval-condition '(has-item shield) tg-game))))

(ert-deftest test-tg-dialog-eval-condition-and ()
  "测试条件求值：and"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 0
                 :status 'active
                 :rewards nil))
         (player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword))))
    (tg-register-quest 'test-quest quest)
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (should (tg-dialog-eval-condition '(and (quest-active test-quest) (has-item sword)) tg-game))
    (should-not (tg-dialog-eval-condition '(and (quest-active test-quest) (has-item shield)) tg-game))
    (should-not (tg-dialog-eval-condition '(and (quest-active other-quest) (has-item sword)) tg-game))))

(ert-deftest test-tg-dialog-eval-condition-or ()
  "测试条件求值：or"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 0
                 :status 'active
                 :rewards nil))
         (player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword))))
    (tg-register-quest 'test-quest quest)
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (should (tg-dialog-eval-condition '(or (quest-active test-quest) (has-item shield)) tg-game))
    (should (tg-dialog-eval-condition '(or (quest-active other-quest) (has-item sword)) tg-game))
    (should-not (tg-dialog-eval-condition '(or (quest-active other-quest) (has-item shield)) tg-game))))

(ert-deftest test-tg-dialog-eval-condition-not ()
  "测试条件求值：not"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (should (tg-dialog-eval-condition '(not (has-item shield)) tg-game))
    (should-not (tg-dialog-eval-condition '(not (has-item sword)) tg-game))))

(ert-deftest test-tg-dialog-apply-effects-exp ()
  "测试效果应用：exp"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (exp 0)))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (tg-dialog-apply-effects '((exp 50)))
    (should (= (tg-creature-attr-get player 'exp) 50))))

(ert-deftest test-tg-dialog-apply-effects-item ()
  "测试效果应用：item"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :inventory '(sword))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (tg-dialog-apply-effects '((item potion)))
    (should (tg-creature-has-item player 'potion))
    (should (tg-creature-has-item player 'sword))))

(ert-deftest test-tg-dialog-apply-effects-gold ()
  "测试效果应用：gold"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (gold 0)))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (tg-dialog-apply-effects '((gold 100)))
    (should (= (tg-creature-attr-get player 'gold) 100))))

(ert-deftest test-tg-dialog-apply-effects-bonus-points ()
  "测试效果应用：bonus-points"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (bonus-points 0)))))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (tg-dialog-apply-effects '((bonus-points 3)))
    (should (= (tg-creature-attr-get player 'bonus-points) 3))))

(ert-deftest test-tg-dialog-apply-effects-quest-activate ()
  "测试效果应用：quest-activate"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 0
                 :status 'inactive
                 :rewards nil)))
    (tg-register-quest 'test-quest quest)
    (tg-dialog-apply-effects '((quest-activate test-quest)))
    (should (eq (tg-quest-status quest) 'active))))

(ert-deftest test-tg-dialog-apply-effects-trigger ()
  "测试效果应用：trigger"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let ((trigger-called nil))
    (let ((trigger-fn (lambda () (setq trigger-called t))))
      (tg-dialog-apply-effects `((trigger ,trigger-fn)))
      (should trigger-called))))

(ert-deftest test-tg-dialog-apply-effects-multiple ()
  "测试效果应用：多个效果"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "测试" "测试作者"))
  (let* ((quest (make-tg-quest
                 :symbol 'test-quest
                 :type 'kill
                 :target 'goblin
                 :count 1
                 :progress 0
                 :status 'inactive
                 :rewards nil))
         (player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (exp 0) (gold 0))
                  :inventory nil)))
    (tg-register-quest 'test-quest quest)
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero player)
    (tg-dialog-apply-effects '((exp 50) (gold 100) (item potion) (quest-activate test-quest)))
    (should (= (tg-creature-attr-get player 'exp) 50))
    (should (= (tg-creature-attr-get player 'gold) 100))
    (should (tg-creature-has-item player 'potion))
    (should (eq (tg-quest-status quest) 'active))))

(provide 'tg-dialog-test-v3)
