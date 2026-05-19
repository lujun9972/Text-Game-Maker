;;; tg-builtin-test.el --- Tests for builtin action handlers -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tg-commands)
(require 'tg-action)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-dialog)
(require 'tg-shop)
(require 'tg-quest)

;;; 测试辅助

(defvar tg-builtin-test-output nil
  "测试期间捕获的输出文本列表。")

(defun tg-builtin-test-capture (text)
  "捕获 tg-message 输出。"
  (push text tg-builtin-test-output))

(defun tg-builtin-test-output ()
  "返回捕获的输出文本（按顺序，已 reverse）。"
  (mapconcat 'identity (nreverse tg-builtin-test-output) ""))

(defun tg-builtin-test-setup ()
  "设置测试环境。"
  (tg-registry-clear)
  (setq tg-builtin-test-output nil)
  (setq tg-message-hook nil)
  (add-hook 'tg-message-hook #'tg-builtin-test-capture)

  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :state 'playing)
  (tg-game-put tg-game :turns 0)

  ;; 注册所有内置动词
  (tg-register-builtins)

  ;; 创建两个相邻房间
  (let ((room1 (make-tg-room
                :symbol 'room1 :name "Room 1" :desc "First room"
                :exits '((north . room2))
                :contents '(key sword potion chest box wearable-armor edible-apple readable-scroll)
                :creatures '(goblin merchant)
                :visit-count 0))
        (room2 (make-tg-room
                :symbol 'room2 :name "Room 2" :desc "Second room"
                :exits '((south . room1))
                :contents nil :creatures nil :visit-count 0)))
    (tg-register-room 'room1 room1)
    (tg-register-room 'room2 room2)
    (tg-game-put tg-game :location 'room1))

  ;; 创建测试对象
  ;; key - 普通 takeable 物品，同时也是钥匙
  (tg-register-object 'key
    (make-tg-object :symbol 'key :name "钥匙" :synonyms '(key)
                    :contents nil :supports nil :props nil
                    :state nil :key nil :effects nil :handler nil))
  ;; sword - 普通 takeable 物品
  (tg-register-object 'sword
    (make-tg-object :symbol 'sword :name "剑" :synonyms '(sword)
                    :contents nil :supports nil :props nil
                    :state nil :key nil :effects nil :handler nil))
  ;; potion - 可消耗物品
  (tg-register-object 'potion
    (make-tg-object :symbol 'potion :name "药水" :synonyms '(potion)
                    :contents nil :supports nil :props '(edible)
                    :state nil :key nil :effects '((hp 20)) :handler nil))
  ;; chest - 锁着的容器，key 可开锁
  (tg-register-object 'chest
    (make-tg-object :symbol 'chest :name "宝箱" :synonyms '(chest)
                    :contents '(gold-coin) :supports nil :props '(container)
                    :state 'locked :key 'key :effects nil :handler nil))
  ;; gold-coin - 容器内的物品
  (tg-register-object 'gold-coin
    (make-tg-object :symbol 'gold-coin :name "金币" :synonyms '(gold)
                    :contents nil :supports nil :props nil
                    :state nil :key nil :effects nil :handler nil))
  ;; box - 打开的容器
  (tg-register-object 'box
    (make-tg-object :symbol 'box :name "盒子" :synonyms '(box)
                    :contents nil :supports nil :props '(container)
                    :state 'open :key nil :effects nil :handler nil))
  ;; scenery - 不可拾取
  (tg-register-object 'wall
    (make-tg-object :symbol 'wall :name "墙" :synonyms '(wall)
                    :contents nil :supports nil :props '(scenery static)
                    :state nil :key nil :effects nil :handler nil))
  ;; wearable-armor - 可装备
  (tg-register-object 'wearable-armor
    (make-tg-object :symbol 'wearable-armor :name "铠甲" :synonyms '(armor)
                    :contents nil :supports nil :props '(wearable)
                    :state nil :key nil :effects nil :handler nil))
  ;; edible-apple - 可食用
  (tg-register-object 'edible-apple
    (make-tg-object :symbol 'edible-apple :name "苹果" :synonyms '(apple)
                    :contents nil :supports nil :props '(edible)
                    :state nil :key nil :effects '((hp 10)) :handler nil))
  ;; readable-scroll - 可阅读
  (tg-register-object 'readable-scroll
    (make-tg-object :symbol 'readable-scroll :name "卷轴" :synonyms '(scroll)
                    :contents nil :supports nil :props '(readable)
                    :state nil :key nil :effects nil :handler nil))
  ;; supporter - 支撑物
  (tg-register-object 'table
    (make-tg-object :symbol 'table :name "桌子" :synonyms '(table)
                    :contents nil :supports nil :props '(supporter)
                    :state nil :key nil :effects nil :handler nil))
  ;; cursed-ring - no-drop + wearable
  (tg-register-object 'cursed-ring
    (make-tg-object :symbol 'cursed-ring :name "诅咒之戒" :synonyms '(ring)
                    :contents nil :supports nil :props '(no-drop wearable)
                    :state nil :key nil :effects '((attack 3)) :handler nil))

  ;; 创建测试生物
  ;; 玩家
  (let ((player (make-tg-creature
                 :symbol 'player :name "勇者"
                 :attr '((hp 100) (attack 15) (defense 5) (exp 0) (level 1) (gold 200) (bonus-points 0))
                 :inventory '(potion) :equipment nil)))
    (tg-register-creature 'player player)
    (tg-game-put tg-game :player 'player))

  ;; goblin - 敌人
  (let ((goblin (make-tg-creature
                 :symbol 'goblin :name "哥布林"
                 :attr '((hp 30) (attack 8) (defense 2))
                 :inventory '(sword) :equipment '(wearable-armor)
                 :exp-reward 50
                 :behaviors nil :death-trigger nil
                 :shopkeeper nil :handler nil)))
    (tg-register-creature 'goblin goblin))

  ;; merchant - 商人
  (let ((merchant (make-tg-creature
                   :symbol 'merchant :name "商人"
                   :attr '((hp 50))
                   :inventory nil :equipment nil
                   :exp-reward nil
                   :behaviors nil :death-trigger nil
                   :shopkeeper t :handler nil)))
    (tg-register-creature 'merchant merchant))

  ;; 注册商店
  (tg-register-shop 'merchant-shop
    (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                  :goods '((potion . 30) (sword . 50))))

  ;; 注册对话节点
  (tg-register-dialog 'merchant
    (make-tg-dialog-state :node-id 'merchant :npc-symbol 'merchant
                          :greeting "欢迎光临！" :options nil)))

(defun tg-builtin-test-teardown ()
  "清理测试环境。"
  (setq tg-message-hook nil)
  (setq tg-game nil)
  (tg-registry-clear))

(defmacro tg-builtin-with-env (&rest body)
  "在测试环境中执行 BODY。"
  `(progn
     (tg-builtin-test-setup)
     (unwind-protect (progn ,@body)
       (tg-builtin-test-teardown))))

;;; go handler

(ert-deftest test-builtin-go-success ()
  (tg-builtin-with-env
   (let ((result (tg-action--handler-go '(:action go :direction north) tg-game)))
     (should (eq result t))
     (should (eq (tg-game-get tg-game :location) 'room2)))))

(ert-deftest test-builtin-go-no-exit ()
  (tg-builtin-with-env
   (let ((result (tg-action--handler-go '(:action go :direction east) tg-game)))
     (should (not result))
     (should (string-match "走不通" (tg-builtin-test-output))))))

;;; take handler

(ert-deftest test-builtin-take-success ()
  (tg-builtin-with-env
   ;; 房间中有 key，玩家拾取
   (let ((result (tg-action--handler-take '(:action take :do-key key) tg-game)))
     (should (eq result t))
     (should (member 'key (tg-creature-inventory (tg-player tg-game))))
     (should (not (member 'key (tg-room-contents (tg-get-room 'room1))))))))

(ert-deftest test-builtin-take-scenery ()
  (tg-builtin-with-env
   ;; scenery 物品不可拾取
   (let ((result (tg-action--handler-take '(:action take :do-key wall) tg-game)))
     ;; wall 不在 room1 的 contents 里，先添加
     ))
  ;; 用实际包含 scenery 的场景测试
  (tg-builtin-with-env
   (let ((room (tg-get-room 'room1)))
     (push 'wall (tg-room-contents room)))
   (let ((result (tg-action--handler-take '(:action take :do-key wall) tg-game)))
     (should (not result))
     (should (string-match "拿不起来" (tg-builtin-test-output))))))

(ert-deftest test-builtin-take-not-in-room ()
  (tg-builtin-with-env
   ;; table 存在但不在房间 contents 中
   (let ((result (tg-action--handler-take '(:action take :do-key table) tg-game)))
     (should (not result))
     (should (string-match "拿不到" (tg-builtin-test-output))))))

;;; drop handler

(ert-deftest test-builtin-drop-success ()
  (tg-builtin-with-env
   ;; 玩家有 potion，放下
   (let ((result (tg-action--handler-drop '(:action drop :do-key potion) tg-game)))
     (should (eq result t))
     (should (not (member 'potion (tg-creature-inventory (tg-player tg-game)))))
     (should (member 'potion (tg-room-contents (tg-get-room 'room1)))))))

(ert-deftest test-builtin-drop-not-owned ()
  (tg-builtin-with-env
   ;; 玩家没有 sword
   (let ((result (tg-action--handler-drop '(:action drop :do-key sword) tg-game)))
     (should (not result))
     (should (string-match "你没有" (tg-builtin-test-output))))))

;;; open handler

(ert-deftest test-builtin-open-locked ()
  (tg-builtin-with-env
   ;; chest 是 locked 的
   (let ((result (tg-action--handler-open '(:action open :do-key chest) tg-game)))
     (should (not result))
     (should (string-match "锁住" (tg-builtin-test-output))))))

(ert-deftest test-builtin-open-closed ()
  (tg-builtin-with-env
   ;; 先把 chest 设为 closed
   (setf (tg-object-state (tg-get-object 'chest)) 'closed)
   (let ((result (tg-action--handler-open '(:action open :do-key chest) tg-game)))
     (should (eq result t))
     (should (eq (tg-object-state (tg-get-object 'chest)) 'open)))))

(ert-deftest test-builtin-open-already-open ()
  (tg-builtin-with-env
   ;; box 是 open 的
   (let ((result (tg-action--handler-open '(:action open :do-key box) tg-game)))
     (should (not result))
     (should (string-match "已经是打开" (tg-builtin-test-output))))))

;;; close handler

(ert-deftest test-builtin-close-success ()
  (tg-builtin-with-env
   ;; box 是 open 的，关闭它
   (let ((result (tg-action--handler-close '(:action close :do-key box) tg-game)))
     (should (eq result t))
     (should (eq (tg-object-state (tg-get-object 'box)) 'closed)))))

;;; unlock handler

(ert-deftest test-builtin-unlock-success ()
  (tg-builtin-with-env
   ;; 玩家需要先有 key，chest 是 locked
   (tg-creature-add-item (tg-player tg-game) 'key)
   (let ((result (tg-action--handler-unlock
                  '(:action unlock :do-key chest :io-key key) tg-game)))
     (should (eq result t))
     (should (eq (tg-object-state (tg-get-object 'chest)) 'closed)))))

(ert-deftest test-builtin-unlock-wrong-key ()
  (tg-builtin-with-env
   ;; 玩家有 sword（不是正确的钥匙），先用 take 把 sword 拿到
   (tg-action--handler-take '(:action take :do-key sword) tg-game)
   (setq tg-builtin-test-output nil) ;; 清空之前的输出
   (let ((result (tg-action--handler-unlock
                  '(:action unlock :do-key chest :io-key sword) tg-game)))
     (should (not result))
     (should (string-match "不匹配" (tg-builtin-test-output))))))

;;; wear handler

(ert-deftest test-builtin-wear-success ()
  (tg-builtin-with-env
   ;; wearable-armor 在房间中，先加入背包
   (tg-creature-add-item (tg-player tg-game) 'wearable-armor)
   (let ((result (tg-action--handler-wear '(:action wear :do-key wearable-armor) tg-game)))
     (should (eq result t))
     (should (member 'wearable-armor (tg-creature-equipment (tg-player tg-game))))
     (should (not (member 'wearable-armor (tg-creature-inventory (tg-player tg-game))))))))

(ert-deftest test-builtin-wear-non-wearable ()
  (tg-builtin-with-env
   ;; sword 不是 wearable
   (tg-creature-add-item (tg-player tg-game) 'sword)
   (let ((result (tg-action--handler-wear '(:action wear :do-key sword) tg-game)))
     (should (not result))
     (should (string-match "不能装备" (tg-builtin-test-output))))))

;;; eat handler

(ert-deftest test-builtin-eat-success ()
  (tg-builtin-with-env
   ;; 玩家有 potion（edible）
   (let* ((player (tg-player tg-game))
          (hp-before (tg-creature-attr-get player 'hp)))
     (let ((result (tg-action--handler-eat '(:action eat :do-key potion) tg-game)))
       (should (eq result t))
       (should (not (member 'potion (tg-creature-inventory player))))
       ;; hp 应该增加 20（potion 的 effects 是 ((hp 20))）
       (should (> (tg-creature-attr-get player 'hp) hp-before))))))

(ert-deftest test-builtin-eat-non-edible ()
  (tg-builtin-with-env
   ;; key 不是 edible
   (tg-creature-add-item (tg-player tg-game) 'key)
   (let ((result (tg-action--handler-eat '(:action eat :do-key key) tg-game)))
     (should (not result))
     (should (string-match "不能吃" (tg-builtin-test-output))))))

;;; inventory handler

(ert-deftest test-builtin-inventory-with-items ()
  (tg-builtin-with-env
   ;; 玩家有 potion
   (let ((result (tg-action--handler-inventory nil tg-game)))
     (should (eq result t))
     (should (string-match "药水" (tg-builtin-test-output))))))

(ert-deftest test-builtin-inventory-empty ()
  (tg-builtin-with-env
   ;; 清空背包
   (setf (tg-creature-inventory (tg-player tg-game)) nil)
   (setf (tg-creature-equipment (tg-player tg-game)) nil)
   (let ((result (tg-action--handler-inventory nil tg-game)))
     (should (not result))
     (should (string-match "什么也没有" (tg-builtin-test-output))))))

;;; attack handler

(ert-deftest test-builtin-attack-damage ()
  (tg-builtin-with-env
   ;; 攻击 goblin
   (let* ((goblin (tg-get-creature 'goblin))
          (hp-before (tg-creature-attr-get goblin 'hp)))
     (let ((result (tg-action--handler-attack '(:action attack :do-key goblin) tg-game)))
       (should (eq result t))
       ;; goblin hp 应该减少
       (should (< (tg-creature-attr-get goblin 'hp) hp-before))))))

(ert-deftest test-builtin-attack-kill ()
  (tg-builtin-with-env
   ;; 反复攻击 goblin 直到击杀（player attack=15, goblin defense=2, damage≥13, goblin hp=30, 3次足够）
   (let ((goblin (tg-get-creature 'goblin)))
     (setf (tg-creature-inventory goblin) '(sword)))
   ;; 攻击多次确保击杀
   (dotimes (_i 5)
     (when (not (tg-creature-dead-p (tg-get-creature 'goblin)))
       (tg-action--handler-attack '(:action attack :do-key goblin) tg-game)))
   ;; goblin 应该死了
   (should (tg-creature-dead-p (tg-get-creature 'goblin)))
   ;; 玩家应该获得经验
   (should (> (tg-creature-attr-get (tg-player tg-game) 'exp) 0))
   ;; 输出应该包含"击败"
   (should (string-match "击败" (tg-builtin-test-output)))
   ;; 背包物品应掉落到房间
   (should (member 'sword (tg-room-contents (tg-get-room 'room1))))
   ;; 装备物品应掉落到房间
   (should (member 'wearable-armor (tg-room-contents (tg-get-room 'room1))))
   ;; goblin 背包和装备应清空
   (should (null (tg-creature-inventory (tg-get-creature 'goblin))))
   (should (null (tg-creature-equipment (tg-get-creature 'goblin))))))

(ert-deftest test-builtin-attack-kill-no-drop ()
  "测试 no-drop 物品不掉落，保留在 creature 身上"
  (tg-builtin-with-env
   ;; 给 goblin 装备 no-drop 物品
   (let ((goblin (tg-get-creature 'goblin)))
     (setf (tg-creature-equipment goblin) '(cursed-ring)))
   ;; 击杀 goblin
   (dotimes (_i 5)
     (when (not (tg-creature-dead-p (tg-get-creature 'goblin)))
       (tg-action--handler-attack '(:action attack :do-key goblin) tg-game)))
   (should (tg-creature-dead-p (tg-get-creature 'goblin)))
   ;; no-drop 物品不应掉落到房间
   (should (not (member 'cursed-ring (tg-room-contents (tg-get-room 'room1)))))
   ;; no-drop 物品应保留在 creature equipment 中
   (should (member 'cursed-ring (tg-creature-equipment (tg-get-creature 'goblin))))))

;;; talk handler

(ert-deftest test-builtin-talk-success ()
  (tg-builtin-with-env
   (let ((result (tg-action--handler-talk '(:action talk :do-key merchant) tg-game)))
     (should (eq result t)))))

;;; status handler

(ert-deftest test-builtin-status ()
  (tg-builtin-with-env
   (let ((result (tg-action--handler-status nil tg-game)))
     (should (eq result t))
     (should (string-match "勇者" (tg-builtin-test-output))))))

;;; place handler

(ert-deftest test-builtin-place-in-container ()
  (tg-builtin-with-env
   ;; 玩家把 potion 放入 box（open container）
   (let ((result (tg-action--handler-place
                  '(:action place :do-key potion :prep "in" :io-key box) tg-game)))
     (should (eq result t))
     (should (not (member 'potion (tg-creature-inventory (tg-player tg-game)))))
     (should (member 'potion (tg-object-contents (tg-get-object 'box)))))))

(ert-deftest test-builtin-place-closed-container ()
  (tg-builtin-with-env
   ;; box 设为 closed
   (setf (tg-object-state (tg-get-object 'box)) 'closed)
   (let ((result (tg-action--handler-place
                  '(:action place :do-key potion :prep "in" :io-key box) tg-game)))
     (should (not result))
     (should (string-match "关着" (tg-builtin-test-output))))))

;;; look handler

(ert-deftest test-builtin-look-room ()
  (tg-builtin-with-env
   (let ((result (tg-action--handler-look '(:action look) tg-game)))
     ;; look without object describes the room
     (should (string-match "First room" (tg-builtin-test-output))))))

;;; register-builtins

(ert-deftest test-builtin-register-builtins ()
  (tg-builtin-with-env
   ;; 验证所有 27 个动词都已注册
   (dolist (verb '("go" "look" "examine" "take" "drop" "place"
                   "open" "close" "unlock" "wear" "eat" "read"
                   "inventory" "attack" "talk" "buy" "sell" "shop"
                   "status" "upgrade" "quests" "quest" "accept"
                   "save" "load" "help" "quit"))
     (should (tg-find-action verb)))))

(provide 'tg-builtin-test)
;;; tg-builtin-test.el ends here
