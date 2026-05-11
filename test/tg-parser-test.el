;;; tg-parser-test.el --- Tests for tg-parser -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, test

;;; Commentary:
;; Tests for the parser system in tg-parser.el

;;; Code:

(require 'ert)
(require 'tg-parser)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-action)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)

;;; 测试设置

(defun tg-parser-test-setup ()
  "设置测试环境。"
  ;; 清理注册表
  (tg-registry-clear)
  ;; 创建测试游戏
  (setq tg-game (tg-new-game "Test Game" "Test Author"))
  (tg-game-put tg-game :state 'playing)
  (tg-game-put tg-game :turns 0)

  ;; 注册测试动作
  (tg-register-action
   :id 'take
   :synonyms '("take" "get" "pick up")
   :handler (lambda () "take handler"))

  (tg-register-action
   :id 'drop
   :synonyms '("drop" "put down")
   :handler (lambda () "drop handler"))

  (tg-register-action
   :id 'look
   :synonyms '("look" "l")
   :handler (lambda () "look handler"))

  (tg-register-action
   :id 'examine
   :synonyms '("examine" "x" "look at")
   :handler (lambda () "examine handler"))

  (tg-register-action
   :id 'place
   :synonyms '("place" "put")
   :handler (lambda () "place handler"))

  (tg-register-action
   :id 'go
   :synonyms '("go" "move" "walk")
   :handler (lambda () "go handler"))

  (tg-register-action
   :id 'inventory
   :synonyms '("inventory" "i")
   :handler (lambda () "inventory handler"))

  ;; 创建测试房间
  (let* ((room (make-tg-room
                :symbol 'test-room
                :name "Test Room"
                :desc "A test room"
                :exits '((north . north-room))
                :contents '(test-key test-box)
                :creatures nil))
         (north-room (make-tg-room
                      :symbol 'north-room
                      :name "North Room"
                      :desc "A north room"
                      :exits '((south . test-room))
                      :contents nil
                      :creatures nil)))
    (tg-register-room 'test-room room)
    (tg-register-room 'north-room north-room)
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
         (rusty-key (make-tg-object
                     :symbol 'rusty-key
                     :name "rusty key"
                     :synonyms '(rusty-key iron-key)
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
               :synonyms '(box crate)
               :contents nil
               :supports nil
               :props '(container)
               :state 'open
               :key nil
               :effects nil
               :handler nil))
         (bird (make-tg-object
                :symbol 'test-bird
                :name "bird"
                :synonyms '(bird)
                :contents nil
                :supports nil
                :props nil
                :state nil
                :key nil
                :effects nil
                :handler nil))
         (nest (make-tg-object
                :symbol 'test-nest
                :name "nest"
                :synonyms '(nest)
                :contents nil
                :supports nil
                :props '(supporter)
                :state nil
                :key nil
                :effects nil
                :handler nil)))
    (tg-register-object 'test-key key)
    (tg-register-object 'rusty-key rusty-key)
    (tg-register-object 'test-box box)
    (tg-register-object 'test-bird bird)
    (tg-register-object 'test-nest nest))

  ;; 创建测试玩家
  (let ((player (make-tg-creature
                 :symbol 'test-player
                 :name "Player"
                 :attr '((hp 100) (attack 10))
                 :inventory '(rusty-key)
                 :equipment nil)))
    (tg-register-creature 'test-player player)
    (tg-game-put tg-game :player 'test-player)))

(defun tg-parser-test-teardown ()
  "清理测试环境。"
  (setq tg-game nil)
  (tg-registry-clear))

;;; 分词测试

(ert-deftest test-tg-parser-tokenize ()
  "测试分词功能。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        (should (equal (tg-parser-tokenize "take key") '("take" "key")))
        (should (equal (tg-parser-tokenize "  take   the  rusty  key  ") '("take" "the" "rusty" "key")))
        (should (equal (tg-parser-tokenize "") nil))
        (should (equal (tg-parser-tokenize "   ") nil))
        (should (equal (tg-parser-tokenize nil) nil)))
    (tg-parser-test-teardown)))

;;; 方向检测测试

(ert-deftest test-tg-parser-direction-detection ()
  "测试方向词检测。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 基本方向
        (should (equal (tg-parse "north") '(:action go :direction north)))
        (should (equal (tg-parse "n") '(:action go :direction north)))
        (should (equal (tg-parse "south") '(:action go :direction south)))
        (should (equal (tg-parse "s") '(:action go :direction south)))
        (should (equal (tg-parse "east") '(:action go :direction east)))
        (should (equal (tg-parse "e") '(:action go :direction east)))
        (should (equal (tg-parse "west") '(:action go :direction west)))
        (should (equal (tg-parse "w") '(:action go :direction west)))
        ;; 组合方向
        (should (equal (tg-parse "northeast") '(:action go :direction northeast)))
        (should (equal (tg-parse "ne") '(:action go :direction northeast)))
        (should (equal (tg-parse "northwest") '(:action go :direction northwest)))
        (should (equal (tg-parse "nw") '(:action go :direction northwest)))
        (should (equal (tg-parse "southeast") '(:action go :direction southeast)))
        (should (equal (tg-parse "se") '(:action go :direction southeast)))
        (should (equal (tg-parse "southwest") '(:action go :direction southwest)))
        (should (equal (tg-parse "sw") '(:action go :direction southwest)))
        ;; 垂直方向
        (should (equal (tg-parse "up") '(:action go :direction up)))
        (should (equal (tg-parse "u") '(:action go :direction up)))
        (should (equal (tg-parse "down") '(:action go :direction down)))
        (should (equal (tg-parse "d") '(:action go :direction down)))
        ;; 特殊方向
        (should (equal (tg-parse "in") '(:action go :direction in)))
        (should (equal (tg-parse "out") '(:action go :direction out))))
    (tg-parser-test-teardown)))

;;; 基本动词解析测试

(ert-deftest test-tg-parser-basic-verb ()
  "测试基本动词解析。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 简单动词+名词
        (let ((result (tg-parse "take key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key)))
        ;; 带冠词
        (let ((result (tg-parse "take the key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key)))
        ;; 大小写
        (let ((result (tg-parse "TAKE KEY")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key))))
    (tg-parser-test-teardown)))

;;; 动词标准化测试

(ert-deftest test-tg-parser-verb-normalization ()
  "测试动词标准化（动词别名）。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; get -> take
        (let ((result (tg-parse "get key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key)))
        ;; l -> look
        (let ((result (tg-parse "l")))
          (should (eq (plist-get result :action) 'look)))
        ;; x -> examine
        (let ((result (tg-parse "x box")))
          (should (eq (plist-get result :action) 'examine))
          (should (eq (plist-get result :do-key) 'test-box)))
        ;; pick up -> take
        (let ((result (tg-parse "pick up key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key))))
    (tg-parser-test-teardown)))

;;; 多词动词测试

(ert-deftest test-tg-parser-multiword-verb ()
  "测试多词动词解析。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; pick up
        (let ((result (tg-parse "pick up key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-key)))
        ;; look at -> examine
        (let ((result (tg-parse "look at box")))
          (should (eq (plist-get result :action) 'examine))
          (should (eq (plist-get result :do-key) 'test-box))))
    (tg-parser-test-teardown)))

;;; 同义词测试

(ert-deftest test-tg-parser-synonyms ()
  "测试对象同义词解析。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 用同义词解析
        (let ((result (tg-parse "take crate")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'test-box)))
        ;; rusty-key 的同义词 iron-key
        (let ((result (tg-parse "take iron-key")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) 'rusty-key))))
    (tg-parser-test-teardown)))

;;; 介词短语测试

(ert-deftest test-tg-parser-prepositional-phrase ()
  "测试介词短语解析。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 先添加 bird 和 nest 到房间
        (let ((room (tg-get-room 'test-room)))
          (setf (tg-room-contents room) '(test-key test-box test-bird test-nest)))
        ;; put bird in nest
        (let ((result (tg-parse "put bird in nest")))
          (should (eq (plist-get result :action) 'place))
          (should (eq (plist-get result :do-key) 'test-bird))
          (should (string= (plist-get result :prep) "in"))
          (should (eq (plist-get result :io-key) 'test-nest)))
        ;; place bird on nest
        (let ((result (tg-parse "place bird on nest")))
          (should (eq (plist-get result :action) 'place))
          (should (eq (plist-get result :do-key) 'test-bird))
          (should (string= (plist-get result :prep) "on"))
          (should (eq (plist-get result :io-key) 'test-nest))))
    (tg-parser-test-teardown)))

;;; all/everything 测试

(ert-deftest test-tg-parser-all-words ()
  "测试 all/everything 解析。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; take all
        (let ((result (tg-parse "take all")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) :all)))
        ;; take everything
        (let ((result (tg-parse "take everything")))
          (should (eq (plist-get result :action) 'take))
          (should (eq (plist-get result :do-key) :all)))
        ;; drop all
        (let ((result (tg-parse "drop all")))
          (should (eq (plist-get result :action) 'drop))
          (should (eq (plist-get result :do-key) :all))))
    (tg-parser-test-teardown)))

;;; 不及物动词测试

(ert-deftest test-tg-parser-intransitive-verb ()
  "测试不及物动词（无直接宾语）。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; look
        (let ((result (tg-parse "look")))
          (should (eq (plist-get result :action) 'look))
          (should (null (plist-get result :do-key))))
        ;; inventory
        (let ((result (tg-parse "inventory")))
          (should (eq (plist-get result :action) 'inventory))
          (should (null (plist-get result :do-key))))
        ;; i
        (let ((result (tg-parse "i")))
          (should (eq (plist-get result :action) 'inventory))
          (should (null (plist-get result :do-key)))))
    (tg-parser-test-teardown)))

;;; 错误处理测试

(ert-deftest test-tg-parser-errors ()
  "测试错误处理。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 空输入
        (let ((result (tg-parse "")))
          (should (eq (plist-get result :error) :empty-input)))
        (let ((result (tg-parse "   ")))
          (should (eq (plist-get result :error) :empty-input)))
        (let ((result (tg-parse nil)))
          (should (eq (plist-get result :error) :empty-input)))
        ;; 未知动词
        (let ((result (tg-parse "xyzzy")))
          (should (eq (plist-get result :error) :unknown-action))
          (string= (plist-get result :verb) "xyzzy"))
        ;; 未知名词
        (let ((result (tg-parse "take foobar")))
          (should (eq (plist-get result :error) :unknown-noun))
          (string= (plist-get result :word) "foobar"))
        ;; 未知动词+未知词
        (let ((result (tg-parse "blorf baz")))
          (should (eq (plist-get result :error) :unknown-action))))
    (tg-parser-test-teardown)))

;;; 词汇表构建测试

(ert-deftest test-tg-parser-build-vocabulary ()
  "测试词汇表构建。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 添加对象到玩家背包
        (let ((player (tg-get-creature 'test-player)))
          (setf (tg-creature-inventory player) '(rusty-key)))
        ;; 构建词汇表
        (let ((vocab (tg-build-vocabulary tg-game)))
          ;; 检查房间中的对象
          (should (eq (gethash "key" vocab) 'test-key))
          (should (eq (gethash "box" vocab) 'test-box))
          ;; 检查同义词
          (should (eq (gethash "crate" vocab) 'test-box))
          ;; 检查背包中的对象
          (should (eq (gethash "rusty key" vocab) 'rusty-key))
          (should (eq (gethash "iron-key" vocab) 'rusty-key))
          ;; 检查 all/everything
          (should (eq (gethash "all" vocab) :all))
          (should (eq (gethash "everything" vocab) :all))))
    (tg-parser-test-teardown)))

;;; 词汇表构建 - 嵌套内容测试

(ert-deftest test-tg-parser-vocabulary-nested ()
  "测试嵌套内容的词汇表构建。"
  (tg-parser-test-setup)
  (unwind-protect
      (progn
        ;; 创建一个打开的容器，里面有对象
        (let* ((room (tg-get-room 'test-room))
               (chest (make-tg-object
                       :symbol 'test-chest
                       :name "chest"
                       :synonyms '(chest)
                       :contents '(rusty-key)
                       :supports nil
                       :props '(container)
                       :state 'open
                       :key nil
                       :effects nil
                       :handler nil)))
          (tg-register-object 'test-chest chest)
          ;; 更新房间内容
          (setf (tg-room-contents room) '(test-chest)))
        ;; 构建词汇表
        (let ((vocab (tg-build-vocabulary tg-game)))
          ;; 检查打开的容器中的对象
          (should (eq (gethash "rusty key" vocab) 'rusty-key))
          (should (eq (gethash "chest" vocab) 'test-chest))))
    (tg-parser-test-teardown)))

(provide 'tg-parser-test)
;;; tg-parser-test.el ends here
