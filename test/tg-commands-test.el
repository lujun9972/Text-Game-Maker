;;; tg-commands-test.el --- Tests for tg-commands -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, test

;;; Commentary:
;; Tests for the handler chain dispatch system in tg-commands.el

;;; Code:

(require 'ert)
(require 'tg-commands)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-action)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)

;;; 测试设置

(defvar tg-commands-test-output nil
  "测试期间捕获的输出。")

(defun tg-commands-test-setup ()
  "设置测试环境。"
  ;; 清理注册表
  (tg-registry-clear)
  ;; 重置输出捕获
  (setq tg-commands-test-output nil)
  (setq tg-message-hook nil)

  ;; 创建测试游戏
  (setq tg-game (tg-new-game "Test Game" "Test Author"))
  (tg-game-put tg-game :state 'playing)
  (tg-game-put tg-game :turns 0)

  ;; 注册测试动作
  (tg-register-action
   :id 'take
   :synonyms '("take")
   :handler (lambda (ast game)
              (tg-message "take handler called")))

  (tg-register-action
   :id 'drop
   :synonyms '("drop")
   :handler (lambda (ast game)
              (tg-message "drop handler called")))

  (tg-register-action
   :id 'look
   :synonyms '("look")
   :handler (lambda (ast game)
              (tg-message "look handler called")))

  (tg-register-action
   :id 'examine
   :synonyms '("examine")
   :handler (lambda (ast game)
              (tg-message "examine handler called")))

  (tg-register-action
   :id 'talk
   :synonyms '("talk")
   :handler (lambda (ast game)
              (tg-message "talk handler called")))

  ;; 创建测试房间
  (let* ((room (make-tg-room
                :symbol 'test-room
                :name "Test Room"
                :desc "A test room"
                :exits nil
                :contents '(test-key test-box test-scenery)
                :creatures nil
                :before-handler nil
                :after-handler nil
                :visit-count 0)))
    (tg-register-room 'test-room room)
    (tg-game-put tg-game :location 'test-room))

  ;; 创建测试对象
  (let* ((key (make-tg-object
               :symbol 'test-key
               :name "key"
               :synonyms '(key)
               :contents nil
               :supports nil
               :props nil
               :state nil
               :key nil
               :effects nil
               :handler nil))
         (box (make-tg-object
               :symbol 'test-box
               :name "box"
               :synonyms '(box)
               :contents nil
               :supports nil
               :props nil
               :state nil
               :key nil
               :effects nil
               :handler nil))
         (scenery (make-tg-object
                   :symbol 'test-scenery
                   :name "wall"
                   :synonyms '(wall)
                   :contents nil
                   :supports nil
                   :props '(scenery)
                   :state nil
                   :key nil
                   :effects nil
                   :handler nil))
         (special-item (make-tg-object
                        :symbol 'test-special
                        :name "special item"
                        :synonyms '(special)
                        :contents nil
                        :supports nil
                        :props nil
                        :state nil
                        :key nil
                        :effects nil
                        :handler (lambda (ast game)
                                   (when (eq (plist-get ast :action) 'take)
                                     (tg-message "You cannot take the special item!")
                                     t)))))
    (tg-register-object 'test-key key)
    (tg-register-object 'test-box box)
    (tg-register-object 'test-scenery scenery)
    (tg-register-object 'test-special special-item))

  ;; 创建测试玩家
  (let ((player (make-tg-creature
                 :symbol 'test-player
                 :name "Player"
                 :attr '((hp 100))
                 :inventory nil
                 :equipment nil
                 :exp-reward nil
                 :behaviors nil
                 :death-trigger nil
                 :shopkeeper nil
                 :handler nil)))
    (tg-register-creature 'test-player player)
    (tg-game-put tg-game :player 'test-player)))

(defun tg-commands-test-teardown ()
  "清理测试环境。"
  (setq tg-game nil)
  (tg-registry-clear))

;;; 辅助函数

(defun tg-commands-test-capture-output ()
  "设置输出捕获。"
  (setq tg-commands-test-output "")
  (add-hook 'tg-message-hook 'tg-commands-test-append-output))

(defun tg-commands-test-append-output (text)
  "将输出追加到测试变量。"
  (setq tg-commands-test-output
        (concat tg-commands-test-output text)))

(defun tg-commands-test-release-output ()
  "释放输出捕获。"
  (remove-hook 'tg-message-hook 'tg-commands-test-append-output))

;;; 错误处理测试

(ert-deftest test-tg-handle-error-empty-input ()
  "测试空输入错误处理。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:error :empty-input)))
          (should (tg-handle-error ast tg-game))
          (should (string= tg-commands-test-output ""))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-handle-error-unknown-action ()
  "测试未知动作错误处理。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:error :unknown-action :verb "xyzzy")))
          (should (tg-handle-error ast tg-game))
          (should (string-match "xyzzy" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-handle-error-unknown-noun ()
  "测试未知名词错误处理。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:error :unknown-noun :word "foobar")))
          (should (tg-handle-error ast tg-game))
          (should (string-match "foobar" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-handle-error-no-error ()
  "测试无错误情况。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-handle-error ast tg-game))))
    (tg-commands-test-teardown)))

;;; 房间 before-handler 测试

(ert-deftest test-tg-run-room-before-nil ()
  "测试无 before-handler 的情况。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-run-room-before ast tg-game))
          (should (string= tg-commands-test-output ""))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-room-before-returns-nil ()
  "测试 before-handler 返回 nil（继续执行）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 设置 before-handler 返回 nil
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-before-handler room)
                (lambda (ast game)
                  (tg-message "before called")
                  nil)))
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-run-room-before ast tg-game))
          (should (string= tg-commands-test-output "before called\n"))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-room-before-returns-t ()
  "测试 before-handler 返回 t（停止传播）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 设置 before-handler 返回 t
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-before-handler room)
                (lambda (ast game)
                  (tg-message "before blocking")
                  t)))
        (let ((ast '(:action take :do-key test-key)))
          (should (tg-run-room-before ast tg-game))
          (should (string= tg-commands-test-output "before blocking\n"))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; 对象 handler 测试

(ert-deftest test-tg-run-do-handler-no-handler ()
  "测试无 do-handler 的情况。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-run-do-handler ast tg-game))))
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-do-handler-returns-nil ()
  "测试 do-handler 返回 nil（继续执行）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 设置对象 handler 返回 nil
        (let ((obj (tg-get-object 'test-key)))
          (setf (tg-object-handler obj)
                (lambda (ast game)
                  (tg-message "do handler called")
                  nil)))
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-run-do-handler ast tg-game))
          (should (string= tg-commands-test-output "do handler called\n"))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-do-handler-returns-t ()
  "测试 do-handler 返回 t（停止传播）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 使用预定义的 special-item handler（返回 t）
        (let ((ast '(:action take :do-key test-special)))
          (should (tg-run-do-handler ast tg-game))
          (should (string-match "cannot take" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; io-handler 测试

(ert-deftest test-tg-run-io-handler-no-io-key ()
  "测试无 io-key 的情况。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (let ((ast '(:action take :do-key test-key)))
          (should-not (tg-run-io-handler ast tg-game))))
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-io-handler-with-handler ()
  "测试 io-handler 存在的情况。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 设置 io 对象 handler
        (let ((obj (tg-get-object 'test-box)))
          (setf (tg-object-handler obj)
                (lambda (ast game)
                  (tg-message "io handler called")
                  nil)))
        (let ((ast '(:action take :do-key test-key :io-key test-box)))
          (should-not (tg-run-io-handler ast tg-game))
          (should (string= tg-commands-test-output "io handler called\n"))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; 动作 handler 测试

(ert-deftest test-tg-run-action ()
  "测试动作 handler 执行。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:action take)))
          (tg-run-action ast tg-game)
          (should (string-match "take handler" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; 房间 after-handler 测试

(ert-deftest test-tg-run-room-after-no-handler ()
  "测试无 after-handler 的情况。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:action take)))
          (tg-run-room-after ast tg-game)
          (should (string= tg-commands-test-output ""))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-run-room-after-with-handler ()
  "测试 after-handler 执行。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-after-handler room)
                (lambda (ast game)
                  (tg-message "after called"))))
        (let ((ast '(:action take)))
          (tg-run-room-after ast tg-game)
          (should (string= tg-commands-test-output "after called\n"))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; Handler chain 顺序测试

(ert-deftest test-tg-dispatch-chain-order ()
  "测试 handler chain 执行顺序。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        ;; 设置 before 和 after handler
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-before-handler room)
                (lambda (ast game)
                  (tg-message "1. before")
                  nil))
          (setf (tg-room-after-handler room)
                (lambda (ast game)
                  (tg-message "6. after"))))
        (let ((ast '(:action look)))
          (tg-dispatch ast tg-game)
          ;; 应该按顺序执行：before -> action -> after
          (should (string-match "1\\. before" tg-commands-test-output))
          (should (string-match "look handler" tg-commands-test-output))
          (should (string-match "6\\. after" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-dispatch-before-blocks ()
  "测试 before-handler 返回 t 时阻止后续执行（不执行 after）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-before-handler room)
                (lambda (ast game)
                  (tg-message "before blocking")
                  t))
          (setf (tg-room-after-handler room)
                (lambda (ast game)
                  (tg-message "after should not run"))))
        (let ((ast '(:action take)))
          (tg-dispatch ast tg-game)
          (should (string-match "before blocking" tg-commands-test-output))
          (should-not (string-match "take handler" tg-commands-test-output))
          (should-not (string-match "after should not run" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-dispatch-do-handler-blocks ()
  "测试 do-handler 返回 t 时阻止后续执行（不执行 action 和 after）。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-after-handler room)
                (lambda (ast game)
                  (tg-message "after should not run"))))
        ;; 添加 special-item 到房间
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-contents room) '(test-key test-box test-scenery test-special)))
        (let ((ast '(:action take :do-key test-special)))
          (tg-dispatch ast tg-game)
          (should (string-match "cannot take" tg-commands-test-output))
          (should-not (string-match "take handler" tg-commands-test-output))
          (should-not (string-match "after should not run" tg-commands-test-output))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; 被动命令测试

(ert-deftest test-tg-dispatch-passive-action-no-turn ()
  "测试被动命令不增加回合。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (tg-game-put tg-game :turns 0)
        (let ((ast '(:action look)))
          (tg-dispatch ast tg-game)
          (should (= (tg-game-get tg-game :turns) 0))))
    (tg-commands-test-teardown)))

(ert-deftest test-tg-dispatch-active-action-inc-turn ()
  "测试主动命令增加回合。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (tg-game-put tg-game :turns 0)
        (let ((ast '(:action take :do-key test-key)))
          (tg-dispatch ast tg-game)
          (should (= (tg-game-get tg-game :turns) 1))))
    (tg-commands-test-teardown)))

;;; take all 展开测试

(ert-deftest test-tg-collect-takeable-objects ()
  "测试收集可取对象。"
  (tg-commands-test-setup)
  (unwind-protect
      (progn
        (let ((takeable (tg-collect-takeable-objects tg-game)))
          ;; key 和 box 可取，scenery 不可取
          (should (memq 'test-key takeable))
          (should (memq 'test-box takeable))
          (should-not (memq 'test-scenery takeable))))
    (tg-commands-test-teardown)))

(ert-deftest test-tg-dispatch-take-all ()
  "测试 take all 展开。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (let ((ast '(:action take :do-key :all)))
          (tg-dispatch ast tg-game)
          ;; 应该对 key 和 box 调用 take handler
          (with-temp-buffer
            (insert tg-commands-test-output)
            (goto-char 1)
            (should (> (count-matches "take handler") 0))))
        ;; 验证回合数增加（take 是主动命令）
        (should (> (tg-game-get tg-game :turns) 0))
        ;; 应该等于可取对象数量
        (should (= (tg-game-get tg-game :turns)
                   (length (tg-collect-takeable-objects tg-game)))))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

;;; tg-message 测试

(ert-deftest test-tg-message-basic ()
  "测试 tg-message 基本输出。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (tg-message "Hello, world!")
        (should (string= tg-commands-test-output "Hello, world!\n")))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-message-format ()
  "测试 tg-message 格式化输出。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (tg-message "You have %d HP." 100)
        (should (string= tg-commands-test-output "You have 100 HP.\n")))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-message-no-newline ()
  "测试 tg-message 无换行时自动添加。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (tg-message "No newline")
        (should (string= tg-commands-test-output "No newline\n")))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(ert-deftest test-tg-message-with-newline ()
  "测试 tg-message 已有换行时不重复添加。"
  (tg-commands-test-setup)
  (tg-commands-test-capture-output)
  (unwind-protect
      (progn
        (tg-message "Has newline\n")
        (should (string= tg-commands-test-output "Has newline\n")))
    (tg-commands-test-release-output)
    (tg-commands-test-teardown)))

(provide 'tg-commands-test)
;;; tg-commands-test.el ends here
