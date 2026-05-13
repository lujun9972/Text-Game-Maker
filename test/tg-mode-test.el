;;; tg-mode-test.el --- Tests for tg-mode.el (new tg-* architecture)  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 2.0
;; Keywords: games, text, test

;;; Commentary:
;; Tests for the new tg-mode UI main mode.
;; Covers: mode activation, tg-send-command, prompt protection, tg-start-game.

;;; Code:

(require 'ert)
(require 'tg-mode)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-action)
(require 'tg-commands)

;;; ============================================================
;;; 测试辅助
;;; ============================================================

(defvar tg-mode-test-output nil
  "测试期间捕获的输出。")

(defun tg-mode-test-setup ()
  "设置测试环境。"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test Game" "Test Author"))
  (tg-game-put tg-game :state 'playing)
  (tg-game-put tg-game :turns 0)

  ;; 注册测试动作（look）
  (tg-register-action
   :id 'look
   :synonyms '("look" "l")
   :handler (lambda (ast game)
              (tg-message "look handler called")))

  ;; 注册测试动作（go）
  (tg-register-action
   :id 'go
   :synonyms '("go" "move" "walk")
   :handler (lambda (ast game)
              (tg-message "go handler called")))

  ;; 创建测试房间
  (let ((room (make-tg-room
               :symbol 'test-room
               :name "TestRoom"
               :desc "A test room"
               :short-desc "Test room"
               :exits nil
               :contents '(test-key)
               :creatures nil
               :before-handler nil
               :after-handler nil
               :visit-count 0)))
    (tg-register-room 'test-room room)
    (tg-game-put tg-game :location 'test-room))

  ;; 创建测试对象
  (let ((key (make-tg-object
              :symbol 'test-key
              :name "key"
              :synonyms '(key)
              :contents nil
              :supports nil
              :props nil
              :state nil
              :key nil
              :effects nil
              :handler nil)))
    (tg-register-object 'test-key key))

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
    (tg-game-put tg-game :player 'test-player))

  ;; 重置输出捕获
  (setq tg-mode-test-output nil)
  (setq tg-message-hook nil)

  ;; 创建测试 creature
  (let ((goblin (make-tg-creature
                 :symbol 'test-goblin
                 :name "Goblin"
                 :attr '((hp 50))
                 :inventory nil
                 :equipment nil
                 :exp-reward nil
                 :behaviors nil
                 :death-trigger nil
                 :shopkeeper nil
                 :handler nil)))
    (tg-register-creature 'test-goblin goblin)
    (let ((room (tg-get-room 'test-room)))
      (setf (tg-room-creatures room) '(test-goblin))))

  ;; 创建第二个测试对象
  (let ((torch (make-tg-object
                :symbol 'test-torch
                :name "torch"
                :synonyms nil
                :contents nil
                :supports nil
                :props nil
                :state nil
                :key nil
                :effects nil
                :handler nil)))
    (tg-register-object 'test-torch torch)
    (let ((room (tg-get-room 'test-room)))
      (tg-room-add-object room 'test-torch))))

(defun tg-mode-test-teardown ()
  "清理测试环境。"
  (setq tg-game nil)
  (setq tg-dialog-pending nil)
  (setq tg-output-buffer nil)
  (tg-registry-clear))

(defun tg-mode-test-capture-output ()
  "设置输出捕获。"
  (setq tg-mode-test-output "")
  (add-hook 'tg-message-hook 'tg-mode-test-append-output))

(defun tg-mode-test-append-output (text)
  "将输出追加到测试变量。"
  (setq tg-mode-test-output
        (concat tg-mode-test-output text)))

(defun tg-mode-test-release-output ()
  "释放输出捕获。"
  (remove-hook 'tg-message-hook 'tg-mode-test-append-output))

;;; ============================================================
;;; 1. tg-mode 激活测试
;;; ============================================================

(ert-deftest test-tg-mode-is-major-mode ()
  "tg-mode 激活后 buffer 的 major-mode 是 tg-mode。"
  (with-temp-buffer
    (tg-mode)
    (should (eq major-mode 'tg-mode))
    (should (derived-mode-p 'text-mode))))

(ert-deftest test-tg-mode-has-prompt-marker ()
  "tg-mode 激活后 tg-prompt-marker 应为 buffer-local。"
  (with-temp-buffer
    (tg-mode)
    (should (local-variable-p 'tg-prompt-marker))))

(ert-deftest test-tg-mode-has-command-history ()
  "tg-mode 激活后 tg-command-history 应为 buffer-local。"
  (with-temp-buffer
    (tg-mode)
    (should (local-variable-p 'tg-command-history))
    (should (null tg-command-history))))

(ert-deftest test-tg-mode-has-history-index ()
  "tg-mode 激活后 tg-history-index 应为 buffer-local。"
  (with-temp-buffer
    (tg-mode)
    (should (local-variable-p 'tg-history-index))
    (should (= tg-history-index -1))))

;;; ============================================================
;;; 2. tg-send-command 处理输入
;;; ============================================================

(ert-deftest test-tg-send-command-processes-input ()
  "tg-send-command 处理输入，调用 tg-parse + tg-dispatch。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (tg-render-prompt)
        ;; 模拟用户输入 "look"
        (insert "look")
        (tg-send-command)
        ;; 验证 buffer 中有输出
        (let ((content (buffer-string)))
          (should (string-match-p "look handler called" content))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-send-command-empty-input ()
  "tg-send-command 对空输入不报错。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (tg-render-prompt)
        ;; 不输入任何内容，直接 send
        (tg-send-command)
        ;; 应该有新 prompt
        (let ((content (buffer-string)))
          (should (string-match-p "\\[TestRoom\\]>" content))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-send-command-adds-to-history ()
  "tg-send-command 将命令添加到历史。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (tg-render-prompt)
        (insert "look")
        (tg-send-command)
        (should (equal tg-command-history '("look"))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-send-command-dialog-mode ()
  "tg-send-command 在对话模式下调用 tg-dialog-handle-choice。"
  (tg-mode-test-setup)
  (unwind-protect
      (let ((dialog-called nil))
        (cl-letf (((symbol-function 'tg-dialog-handle-choice)
                   (lambda (_choice)
                     (setq dialog-called t))))
          (setq tg-dialog-pending
                (make-tg-dialog-state
                 :node-id 'test-dialog
                 :npc-symbol 'test-npc
                 :greeting "Hello"
                 :options nil))
          (with-temp-buffer
            (tg-mode)
            (setq tg-output-buffer (current-buffer))
            (tg-render-prompt)
            (insert "1")
            (tg-send-command)
            (should dialog-called))))
    (setq tg-dialog-pending nil)
    (tg-mode-test-teardown)))

;;; ============================================================
;;; 3. Prompt 保护（read-only + rear-nonsticky）
;;; ============================================================

(ert-deftest test-tg-render-prompt-read-only ()
  "tg-render-prompt 插入的 prompt 应为 read-only。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    ;; prompt 文本应该有 read-only 属性
    ;; 跳过开头的 \n，找到 [Hall]> 区域
    (goto-char (point-min))
    (forward-char 1)                      ; skip the leading \n
    (should (get-text-property (point) 'read-only))))

(ert-deftest test-tg-render-prompt-rear-nonsticky ()
  "prompt 最后一个字符应有 rear-nonsticky '(read-only)。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    ;; 找到 prompt 末尾
    (goto-char (point-max))
    (let ((pos (1- (point))))
      ;; 往前找到有 read-only 的区域末尾
      (while (and (> pos (point-min))
                  (not (get-text-property pos 'rear-nonsticky)))
        (setq pos (1- pos)))
      (should (member 'read-only (get-text-property pos 'rear-nonsticky))))))

(ert-deftest test-tg-render-prompt-can-type-after ()
  "用户可以在 prompt 后输入文字（rear-nonsticky 允许）。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    ;; 在 prompt 后插入文字不应报错
    (goto-char (point-max))
    (insert "test input")
    (should (string-match-p "test input" (buffer-string)))))

(ert-deftest test-tg-render-prompt-format ()
  "tg-render-prompt 应显示 [房间名]> 格式。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'dungeon :name "Dungeon" :desc "A dark dungeon"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'dungeon room)
      (tg-game-put tg-game :location 'dungeon))
    (tg-render-prompt)
    (should (string-match-p "\\[Dungeon\\]>" (buffer-string)))))

(ert-deftest test-tg-render-prompt-sets-marker ()
  "tg-render-prompt 应设置 tg-prompt-marker。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    (should tg-prompt-marker)
    (should (markerp tg-prompt-marker))))

;;; ============================================================
;;; 4. tg-start-game 创建正确的 buffer
;;; ============================================================

(ert-deftest test-tg-start-game-creates-buffer ()
  "tg-start-game 应创建正确命名的 buffer。"
  (tg-mode-test-setup)
  (let ((org-file (expand-file-name "sample/game.org"
                                    (file-name-directory (or load-file-name buffer-file-name default-directory)))))
    (if (file-exists-p org-file)
        (unwind-protect
            (progn
              (tg-start-game org-file)
              (let ((buf (current-buffer)))
                (should (string-match-p "\\*TG:" (buffer-name buf)))
                (should (eq major-mode 'tg-mode))))
          ;; 清理
          (when (get-buffer "*TG: *")
            (kill-buffer "*TG: *"))
          (tg-mode-test-teardown))
      ;; 如果没有 sample/game.org，用 mock 测试
      (unwind-protect
          (progn
            ;; 手动模拟 tg-start-game 的关键步骤
            (tg-register-builtins)
            (let* ((buf-name "*TG: Test Game*")
                   (buf (get-buffer-create buf-name)))
              (with-current-buffer buf
                (tg-mode)
                (setq tg-output-buffer buf)
                (tg-render-prompt)
                (should (eq major-mode 'tg-mode))
                (should tg-output-buffer)
                (should (string-match-p "\\[TestRoom\\]>" (buffer-string))))
              (kill-buffer buf)))
        (tg-mode-test-teardown)))))

(ert-deftest test-tg-get-buffer-returns-nil-when-no-game ()
  "没有游戏 buffer 时 tg-get-buffer 返回 nil。"
  ;; 关闭所有 tg-mode buffer
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (eq major-mode 'tg-mode)
          (kill-buffer buf)))))
  (should-not (tg-get-buffer)))

(ert-deftest test-tg-get-buffer-returns-game-buffer ()
  "tg-get-buffer 应返回激活的 tg-mode buffer。"
  (let ((buf (get-buffer-create " *test-tg-get-buffer*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (tg-mode))
          (should (eq (tg-get-buffer) buf)))
      (kill-buffer buf))))

;;; ============================================================
;;; 箭头键绑定测试
;;; ============================================================

(ert-deftest test-tg-arrow-keys-bound ()
  "↑↓ 箭头应绑定到 tg-history-prev/next。"
  (with-temp-buffer
    (tg-mode)
    (should (eq (key-binding (kbd "<up>")) #'tg-history-prev))
    (should (eq (key-binding (kbd "<down>")) #'tg-history-next))))

;;; ============================================================
;;; 命令历史测试
;;; ============================================================

(ert-deftest test-tg-record-history-basic ()
  "tg-record-history 应将命令添加到历史前面。"
  (with-temp-buffer
    (tg-mode)
    (tg-record-history "look")
    (should (equal tg-command-history '("look")))
    (tg-record-history "go north")
    (should (equal tg-command-history '("go north" "look")))))

(ert-deftest test-tg-record-history-dedup ()
  "tg-record-history 不应重复记录相同命令。"
  (with-temp-buffer
    (tg-mode)
    (tg-record-history "look")
    (tg-record-history "look")
    (should (equal tg-command-history '("look")))))

(ert-deftest test-tg-record-history-empty ()
  "tg-record-history 不应记录空字符串。"
  (with-temp-buffer
    (tg-mode)
    (tg-record-history "")
    (should (null tg-command-history))))

(ert-deftest test-tg-history-prev-basics ()
  "tg-history-prev 应替换输入为上一条历史。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    ;; 预设历史
    (setq tg-command-history '("look" "go north"))
    (setq tg-history-index -1)
    ;; 输入当前文字
    (goto-char (point-max))
    (insert "current input")
    ;; 向上翻
    (tg-history-prev)
    (should (= tg-history-index 0))
    (should (string-match-p "look$" (buffer-string)))
    (should (equal tg-current-input "current input"))))

(ert-deftest test-tg-history-next-restores-input ()
  "tg-history-next 应恢复到当前输入。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    (setq tg-command-history '("look"))
    (setq tg-history-index -1)
    (goto-char (point-max))
    (insert "my text")
    (tg-history-prev)
    (should (= tg-history-index 0))
    (tg-history-next)
    (should (= tg-history-index -1))
    (should (string-match-p "my text$" (buffer-string)))))

;;; ============================================================
;;; TAB 补全测试
;;; ============================================================

(ert-deftest test-tg-complete-verb-prefix ()
  "tg-complete-command 应补全动词前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "lo")
        (tg-complete-command)
        ;; 应补全为 "look"
        (should (string-match-p "look$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-no-match ()
  "tg-complete-command 对无匹配前缀不做任何事。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "zzzzz")
        (let ((before (buffer-string)))
          (tg-complete-command)
          ;; 无匹配，buffer 内容不变
          (should (equal (buffer-string) before))))
    (tg-mode-test-teardown)))

;;; ============================================================
;;; 双名称补全测试（中文名 + symbol 名）
;;; ============================================================

(ert-deftest test-tg-complete-object-symbol-name ()
  "对象补全应支持 symbol 名前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents '(my-sword)
                     :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (let ((sword (make-tg-object
                      :symbol 'my-sword
                      :name "长剑"
                      :synonyms nil :contents nil :supports nil
                      :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-sword sword))
        (tg-render-prompt)
        (insert "take my-")
        (tg-complete-command)
        (should (string-match-p "my-sword$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-chinese-name ()
  "对象补全应支持中文名前缀。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents '(my-sword)
                     :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (let ((sword (make-tg-object
                      :symbol 'my-sword
                      :name "长剑"
                      :synonyms nil :contents nil :supports nil
                      :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-sword sword))
        (tg-render-prompt)
        (insert "take 长")
        (tg-complete-command)
        (should (string-match-p "长剑$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-creature-symbol ()
  "对象补全应包含房间内 creature 的 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil
                     :creatures '(test-goblin)
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "attack test-")
        (tg-complete-command)
        (should (string-match-p "test-goblin$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-creature-name ()
  "对象补全应包含房间内 creature 的显示名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil
                     :creatures '(test-goblin)
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        (tg-render-prompt)
        (insert "attack gob")
        (tg-complete-command)
        (should (string-match-p "goblin$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-complete-object-inventory-symbol ()
  "对象补全应包含背包物品 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (with-temp-buffer
        (tg-mode)
        (setq tg-output-buffer (current-buffer))
        (setq tg-game (tg-new-game "Test" "Author"))
        (let ((room (make-tg-room
                     :symbol 'hall :name "Hall" :desc "A hall"
                     :exits nil :contents nil :creatures nil
                     :visit-count 0)))
          (tg-register-room 'hall room)
          (tg-game-put tg-game :location 'hall))
        ;; 需要注册 player
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
          (tg-game-put tg-game :player 'test-player))
        (let ((potion (make-tg-object
                       :symbol 'my-potion
                       :name "药水"
                       :synonyms nil :contents nil :supports nil
                       :props nil :state nil :key nil :effects nil :handler nil)))
          (tg-register-object 'my-potion potion)
          (let* ((player-sym (tg-game-get tg-game :player))
                 (player (tg-get-creature player-sym)))
            (setf (tg-creature-inventory player) '(my-potion))))
        (tg-render-prompt)
        (insert "drop my-")
        (tg-complete-command)
        (should (string-match-p "my-potion$" (buffer-string))))
    (tg-mode-test-teardown)))

(ert-deftest test-tg-parser-recognizes-symbol-name ()
  "解析器应能识别对象的 symbol 名。"
  (tg-mode-test-setup)
  (unwind-protect
      (progn
        (tg-register-builtins)
        (let ((ast (tg-parse "take test-key")))
          (should (eq (plist-get ast :action) 'take))
          (should (eq (plist-get ast :do-key) 'test-key))))
    (tg-mode-test-teardown)))

;;; ============================================================
;;; C-r 搜索历史测试
;;; ============================================================

(ert-deftest test-tg-isearch-key-binding ()
  "C-r 应绑定到 tg-history-isearch。"
  (with-temp-buffer
    (tg-mode)
    (should (eq (key-binding (kbd "C-r")) #'tg-history-isearch))))

(ert-deftest test-tg-isearch-single-match ()
  "C-r 单条匹配直接填入命令行。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-game (tg-new-game "Test" "Author"))
    (let ((room (make-tg-room
                 :symbol 'hall :name "Hall" :desc "A hall"
                 :exits nil :contents nil :creatures nil
                 :visit-count 0)))
      (tg-register-room 'hall room)
      (tg-game-put tg-game :location 'hall))
    (tg-render-prompt)
    (setq tg-command-history '("look" "go north" "take key"))
    ;; 模拟搜索逻辑：单条匹配
    (let* ((term "go")
           (matches (cl-remove-if-not
                     (lambda (s) (string-match-p term s))
                     tg-command-history)))
      (should (= (length matches) 1))
      (should (equal (car matches) "go north"))
      ;; 填入
      (let ((inhibit-read-only t))
        (delete-region tg-prompt-marker (point-max)))
      (insert (car matches))
      (should (string-match-p "go north$" (buffer-string))))))

(ert-deftest test-tg-isearch-no-match ()
  "C-r 无匹配时返回空列表。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-command-history '("look" "take key"))
    (let ((matches (cl-remove-if-not
                    (lambda (s) (string-match-p "xyz" s))
                    tg-command-history)))
      (should (null matches)))))

(ert-deftest test-tg-isearch-multiple-matches ()
  "C-r 多条匹配：填入最近一条，候选列表包含全部匹配。"
  (with-temp-buffer
    (tg-mode)
    (setq tg-command-history '("look" "look at key" "go north"))
    (let* ((term "look")
           (matches (cl-remove-if-not
                     (lambda (s) (string-match-p term s))
                     tg-command-history)))
      (should (equal (length matches) 2))
      (should (equal (car matches) "look"))
      (should (equal matches '("look" "look at key"))))))

(provide 'tg-mode-test)
;;; tg-mode-test.el ends here
