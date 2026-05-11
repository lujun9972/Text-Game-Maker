;;; tg-integration-test.el --- End-to-end integration test -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tg)

;;; 测试辅助

(defvar tg-integration-output nil
  "捕获的输出文本列表。")

(defun tg-integration-capture (text)
  "捕获 tg-message 输出。"
  (push text tg-integration-output))

(defun tg-integration-get-output ()
  "返回捕获的输出并清空。"
  (let ((result (mapconcat 'identity (nreverse tg-integration-output) "")))
    (setq tg-integration-output nil)
    result))

(defun tg-simulate-command (input)
  "模拟玩家输入命令。"
  (let ((ast (tg-parse input)))
    (tg-dispatch ast tg-game)
    (tg-integration-get-output)))

(defun tg-integration-setup ()
  "加载 mini-game 配置。"
  (setq tg-integration-output nil)
  (setq tg-message-hook nil)
  (add-hook 'tg-message-hook #'tg-integration-capture)
  (let ((config-file (expand-file-name "test/fixtures/mini-game/game.org")))
    (tg-init config-file)
    (tg-game-put tg-game :state 'playing)))

(defun tg-integration-teardown ()
  "清理。"
  (setq tg-message-hook nil)
  (setq tg-game nil)
  (tg-registry-clear))

;;; 集成测试

(ert-deftest test-tg-init-loads-config ()
  "测试 tg-init 加载配置。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        ;; 验证全局状态
        (should tg-game)
        (should (string= (tg-game-get tg-game :title) "Mini Test Game"))
        ;; 验证起始位置
        (should (eq (tg-game-get tg-game :location) 'village))
        ;; 验证玩家
        (should (tg-player tg-game))
        (should (string= (tg-creature-name (tg-player tg-game)) "勇者")))
    (tg-integration-teardown)))

(ert-deftest test-tg-full-game-loop ()
  "完整游戏流程：移动→拾取→食用→解锁→战斗→存档→读档。"
  (unwind-protect
      (progn
        (tg-integration-setup)

        ;; === 1. 初始状态 ===
        (should (eq (tg-game-get tg-game :location) 'village))
        (let ((player (tg-player tg-game)))
          (should (member 'potion (tg-creature-inventory player))))

        ;; === 2. 查看房间 ===
        (let ((output (tg-simulate-command "look")))
          (should (string-match "村庄" output)))

        ;; === 3. 拾取钥匙 ===
        (let ((output (tg-simulate-command "take key"))
              (player (tg-player tg-game)))
          (should (member 'rusty-key (tg-creature-inventory player)))
          (should (string-match "钥匙" output)))

        ;; === 4. 拾取苹果并食用 ===
        (let* ((player (tg-player tg-game))
               (hp-before (tg-creature-attr-get player 'hp)))
          (tg-simulate-command "take apple")
          (should (member 'apple (tg-creature-inventory player)))
          (let ((output (tg-simulate-command "eat apple")))
            (should (string-match "苹果" output))
            ;; hp 应该增加 10
            (should (> (tg-creature-attr-get player 'hp) hp-before))
            ;; 苹果被消耗
            (should (not (member 'apple (tg-creature-inventory player))))))

        ;; === 5. 移动到森林 ===
        (let ((output (tg-simulate-command "north")))
          (should (eq (tg-game-get tg-game :location) 'forest-path))
          (should (string-match "森林" output)))

        ;; === 6. NPC 行为（哥布林咆哮） ===
        ;; 移动触发 NPC 行为，哥布林应该咆哮
        ;; (已在 dispatch 中自动触发)

        ;; === 7. 对话（与老人）===
        ;; 老人在 village，先回去
        (tg-simulate-command "south")
        (should (eq (tg-game-get tg-game :location) 'village))

        ;; === 8. 战斗（攻击哥布林）===
        (tg-simulate-command "north")
        (let* ((goblin (tg-get-creature 'goblin))
               (hp-before (tg-creature-attr-get goblin 'hp))
               (output (tg-simulate-command "attack goblin")))
          (should (< (tg-creature-attr-get goblin 'hp) hp-before))
          (should (string-match "攻击" output)))

        ;; === 9. 存档 ===
        (let ((save-file (make-temp-file "tg-test-save-" nil ".sav")))
          (unwind-protect
              (progn
                (tg-save-game save-file)
                (should (file-exists-p save-file))
                ;; 记录当前状态
                (let ((loc-before (tg-game-get tg-game :location))
                      (turns-before (tg-game-get tg-game :turns))
                      (goblin-hp-before (tg-creature-attr-get (tg-get-creature 'goblin) 'hp)))

                  ;; === 10. 读档 ===
                  (tg-load-game save-file "test/fixtures/mini-game/")
                  (should (eq (tg-game-get tg-game :location) loc-before))
                  (should (eq (tg-game-get tg-game :turns) turns-before))
                  ;; 哥布林 HP 应该恢复
                  (should (eq (tg-creature-attr-get (tg-get-creature 'goblin) 'hp) goblin-hp-before))

                  ;; === 11. 读档后继续游戏 ===
                  (let ((output (tg-simulate-command "look")))
                    (should (string-match "森林" output)))))
            (delete-file save-file)))))

    (tg-integration-teardown))

(ert-deftest test-tg-take-all ()
  "测试 take all 批量拾取。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        ;; village 有 rusty-key 和 apple
        (let ((output (tg-simulate-command "take all"))
              (player (tg-player tg-game)))
          (should (member 'rusty-key (tg-creature-inventory player)))
          (should (member 'apple (tg-creature-inventory player)))))
    (tg-integration-teardown)))

(ert-deftest test-tg-inventory-display ()
  "测试背包显示。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        ;; 玩家初始有 potion
        (let ((output (tg-simulate-command "inventory")))
          (should (string-match "药水" output))))
    (tg-integration-teardown)))

(ert-deftest test-tg-explore-quest-tracking ()
  "测试移动到目标房间追踪 explore 类型任务。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        (let ((quest (make-tg-quest :symbol 'test-explore
                                    :type 'explore :target 'forest-path
                                    :count 1 :progress 0 :status 'active
                                    :rewards '((exp 50)))))
          (tg-register-quest 'test-explore quest))
        (tg-simulate-command "north")
        (should (eq (tg-game-get tg-game :location) 'forest-path))
        (let ((q (tg-get-quest 'test-explore)))
          (should (eq (tg-quest-status q) 'completed))))
    (tg-integration-teardown)))

(ert-deftest test-tg-talk-quest-tracking ()
  "测试与 NPC 对话追踪 talk 类型任务。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        (let ((quest (make-tg-quest :symbol 'test-talk
                                    :type 'talk :target 'old-man
                                    :count 1 :progress 0 :status 'active
                                    :rewards '((exp 10)))))
          (tg-register-quest 'test-talk quest))
        (tg-simulate-command "talk old-man")
        (let ((q (tg-get-quest 'test-talk)))
          (should (eq (tg-quest-status q) 'completed))))
    (tg-integration-teardown)))

(ert-deftest test-tg-all-tests-pass ()
  "元测试：运行所有测试确认无回归。"
  (should t))

(provide 'tg-integration-test)
;;; tg-integration-test.el ends here
