;;; tg-quest-test.el --- 任务系统测试  -*- lexical-binding: t; -->

(require 'ert)
(require 'cl-lib)
(require 'tg-quest)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-game)

;;; 测试夹具

(defun tg-quest-test-setup ()
  "设置测试环境"
  (tg-registry-clear)
  ;; 创建测试游戏
  (setq tg-game (tg-new-game "Test" "TestAuthor"))
  ;; 创建测试玩家
  ;; 注意：使用 list 而不是 quoted 字面量，避免字节编译后的常量共享问题
  (let ((player (make-tg-creature
                 :symbol 'test-player
                 :name "TestPlayer"
                 :attr (list (list 'hp 100) (list 'exp 0) (list 'level 1))
                 :inventory nil
                 :equipment nil)))
    (tg-register-creature 'test-player player)
    (tg-game-put tg-game :player 'test-player))
  ;; 注册测试任务
  (let ((kill-quest (make-tg-quest
                     :symbol 'quest-kill-goblin
                     :type 'kill
                     :target 'goblin
                     :count 3
                     :progress 0
                     :status 'inactive
                     :rewards '((exp 50) (item sword)))))
    (tg-register-quest 'quest-kill-goblin kill-quest))
  (let ((collect-quest (make-tg-quest
                        :symbol 'quest-collect-herb
                        :type 'collect
                        :target 'herb
                        :count 5
                        :progress 0
                        :status 'inactive
                        :rewards '((exp 20)))))
    (tg-register-quest 'quest-collect-herb collect-quest))
  (let ((explore-quest (make-tg-quest
                        :symbol 'quest-explore-forest
                        :type 'explore
                        :target 'forest
                        :count 1
                        :progress 0
                        :status 'inactive
                        :rewards '((bonus-points 1)))))
    (tg-register-quest 'quest-explore-forest explore-quest))
  (let ((talk-quest (make-tg-quest
                     :symbol 'quest-talk-npc
                     :type 'talk
                     :target 'npc
                     :count 1
                     :progress 0
                     :status 'inactive
                     :rewards '((trigger (lambda (game) (tg-game-put game :talked-to-npc t)))))))
    (tg-register-quest 'quest-talk-npc talk-quest)))

;;; 任务激活测试

(ert-deftest test-tg-quest-activate ()
  "测试 tg-quest-activate 将任务从 inactive 改为 active"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin)))
    (should (eq (tg-quest-status quest) 'inactive))
    (tg-quest-activate quest)
    (should (eq (tg-quest-status quest) 'active))))

;;; kill 任务追踪测试

(ert-deftest test-tg-track-quest-kill ()
  "测试 kill 任务进度增加"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin)))
    (tg-quest-activate quest)
    (should (= (tg-quest-progress quest) 0))
    ;; 追踪一次
    (tg-track-quest 'kill 'goblin)
    (should (= (tg-quest-progress quest) 1))
    ;; 再追踪两次
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    (should (= (tg-quest-progress quest) 3))))

;;; collect 任务追踪测试

(ert-deftest test-tg-track-quest-collect ()
  "测试 collect 任务进度增加"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-collect-herb)))
    (tg-quest-activate quest)
    (should (= (tg-quest-progress quest) 0))
    (tg-track-quest 'collect 'herb)
    (should (= (tg-quest-progress quest) 1))
    (tg-track-quest 'collect 'herb)
    (tg-track-quest 'collect 'herb)
    (should (= (tg-quest-progress quest) 3))))

;;; explore 任务追踪测试

(ert-deftest test-tg-track-quest-explore ()
  "测试 explore 任务进度增加"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-explore-forest)))
    (tg-quest-activate quest)
    (should (= (tg-quest-progress quest) 0))
    (tg-track-quest 'explore 'forest)
    (should (= (tg-quest-progress quest) 1))))

;;; talk 任务追踪测试

(ert-deftest test-tg-track-quest-talk ()
  "测试 talk 任务进度增加"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-talk-npc)))
    (tg-quest-activate quest)
    (should (= (tg-quest-progress quest) 0))
    (tg-track-quest 'talk 'npc)
    (should (= (tg-quest-progress quest) 1))))

;;; 进度达标自动完成测试

(ert-deftest test-tg-quest-auto-complete ()
  "测试进度达标时自动完成"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin)))
    (tg-quest-activate quest)
    (should (eq (tg-quest-status quest) 'active))
    ;; 追踪 3 次，达到 count
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    (should (eq (tg-quest-status quest) 'completed))))

;;; exp 奖励发放测试

(ert-deftest test-tg-quest-reward-exp ()
  "测试 exp 奖励发放"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin))
        (player (tg-player tg-game)))
    (tg-quest-activate quest)
    (should (= (tg-creature-attr-get player 'exp) 0))
    ;; 完成任务
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    ;; 检查经验增加
    (should (= (tg-creature-attr-get player 'exp) 50))))

;;; item 奖励发放测试

(ert-deftest test-tg-quest-reward-item ()
  "测试 item 奖励发放"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin))
        (player (tg-player tg-game)))
    (tg-quest-activate quest)
    (should (null (tg-creature-inventory player)))
    ;; 完成任务
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    (tg-track-quest 'kill 'goblin)
    ;; 检查物品添加
    (should (tg-creature-has-item player 'sword))))

;;; bonus-points 奖励发放测试

(ert-deftest test-tg-quest-reward-bonus-points ()
  "测试 bonus-points 奖励发放"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-explore-forest))
        (player (tg-player tg-game)))
    (tg-quest-activate quest)
    (should (null (tg-creature-attr-get player 'bonus-points)))
    ;; 完成任务
    (tg-track-quest 'explore 'forest)
    ;; 检查属性点增加
    (should (= (tg-creature-attr-get player 'bonus-points) 1))))

;;; trigger 奖励发放测试

(ert-deftest test-tg-quest-reward-trigger ()
  "测试 trigger 奖励发放"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-talk-npc)))
    (tg-quest-activate quest)
    (should (null (tg-game-get tg-game :talked-to-npc)))
    ;; 完成任务
    (tg-track-quest 'talk 'npc)
    ;; 检查触发器执行
    (should (tg-game-get tg-game :talked-to-npc))))

;;; 已完成任务不重复追踪测试

(ert-deftest test-tg-quest-no-double-tracking ()
  "测试已完成任务不重复追踪"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-explore-forest))
        (player (tg-player tg-game)))
    (tg-quest-activate quest)
    ;; 完成任务
    (tg-track-quest 'explore 'forest)
    (should (eq (tg-quest-status quest) 'completed))
    (should (= (tg-quest-progress quest) 1))
    (should (= (tg-creature-attr-get player 'bonus-points) 1))
    ;; 再次追踪，不应增加进度或重复发放奖励
    (tg-track-quest 'explore 'forest)
    (should (= (tg-quest-progress quest) 1))
    (should (= (tg-creature-attr-get player 'bonus-points) 1))))

;;; 类型不匹配不追踪测试

(ert-deftest test-tg-quest-no-match-no-track ()
  "测试类型或目标不匹配时不追踪"
  (tg-quest-test-setup)
  (let ((quest (tg-get-quest 'quest-kill-goblin)))
    (tg-quest-activate quest)
    (should (= (tg-quest-progress quest) 0))
    ;; 类型不匹配
    (tg-track-quest 'collect 'goblin)
    (should (= (tg-quest-progress quest) 0))
    ;; 目标不匹配
    (tg-track-quest 'kill 'orc)
    (should (= (tg-quest-progress quest) 0))
    ;; 两者都匹配
    (tg-track-quest 'kill 'goblin)
    (should (= (tg-quest-progress quest) 1))))

(ert-deftest test-tg-quest-description-field ()
  "测试 quest struct 新字段。"
  (let ((q (make-tg-quest :symbol 'test :type 'kill :target 'rat
                          :count 1 :progress 0 :status 'active :rewards nil
                          :description "消灭老鼠" :completion-text "干得好！")))
    (should (string= (tg-quest-description q) "消灭老鼠"))
    (should (string= (tg-quest-completion-text q) "干得好！"))
    (should (null (tg-quest-description (make-tg-quest))))))

(ert-deftest test-tg-quest-completion-text-on-complete ()
  "测试任务完成时输出 completion-text。"
  (tg-registry-clear)
  (let ((tg-game (tg-new-game "Test" "Author")))
    (tg-game-put tg-game :player 'hero)
    (tg-register-creature 'hero (make-tg-creature :symbol 'hero :name "Hero"
                                                   :attr '((hp 100))))
    (tg-register-quest 'test-q (make-tg-quest :symbol 'test-q :type 'kill
                                                :target 'rat :count 1 :progress 0
                                                :status 'active :rewards nil
                                                :completion-text "任务完成！"))
    (tg-track-quest 'kill 'rat)
    (should (eq (tg-quest-status (tg-get-quest 'test-q)) 'completed)))
  (tg-registry-clear))

(provide 'tg-quest-test)
;;; tg-quest-test.el ends here
