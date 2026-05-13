;;; test/tg-config-test.el --- tg-config 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-config)

(ert-deftest test-tg-config-parse-keyword ()
  "测试关键字解析"
  (let ((org-content "#+TITLE: 测试游戏
#+AUTHOR: 测试作者
#+START: entrance

* Test Section
Test content"))
    (with-temp-buffer
      (insert org-content)
      (org-mode)
      (let ((tree (org-element-parse-buffer)))
        (should (equal (tg-config--parse-keyword tree "TITLE") "测试游戏"))
        (should (equal (tg-config--parse-keyword tree "AUTHOR") "测试作者"))
        (should (equal (tg-config--parse-keyword tree "START") "entrance"))
        (should (not (tg-config--parse-keyword tree "NONEXISTENT")))))))

(ert-deftest test-tg-config-split-list ()
  "测试列表字符串分割"
  (should (equal (tg-config--split-list "sword,shield,potion") '(sword shield potion)))
  (should (equal (tg-config--split-list "sword shield potion") '(sword shield potion)))
  (should (equal (tg-config--split-list "sword") '(sword)))
  (should (not (tg-config--split-list "")))
  (should (not (tg-config--split-list nil))))

(ert-deftest test-tg-config-parse-exits ()
  "测试出口解析"
  (let ((exits (tg-config--parse-exits "north=hall,south=garden")))
    (should (equal exits '((north . hall) (south . garden)))))
  (let ((exits (tg-config--parse-exits "up=roof")))
    (should (equal exits '((up . roof)))))
  (should (not (tg-config--parse-exits nil)))
  (should (not (tg-config--parse-exits ""))))

(ert-deftest test-tg-config-parse-props ()
  "测试属性解析"
  (should (equal (tg-config--parse-props "container static") '(container static)))
  (should (equal (tg-config--parse-props "wearable") '(wearable)))
  (should (not (tg-config--parse-props nil)))
  (should (not (tg-config--parse-props ""))))

(ert-deftest test-tg-config-parse-attr ()
  "测试生物属性解析"
  (let ((attr (tg-config--parse-attr "hp 50 attack 10")))
    (should (equal attr '((hp 50) (attack 10)))))
  (let ((attr (tg-config--parse-attr "hp 100 defense 5 exp 0")))
    (should (equal attr '((hp 100) (defense 5) (exp 0)))))
  (should (not (tg-config--parse-attr nil)))
  (should (not (tg-config--parse-attr ""))))

(ert-deftest test-tg-config-parse-effects ()
  "测试效果解析"
  (let ((effects (tg-config--parse-effects "(hp 20) (attack 3 :duration 10)")))
    (should (equal effects '((hp 20) (attack 3 :duration 10)))))
  (let ((effects (tg-config--parse-effects "(exp 50)")))
    (should (equal effects '((exp 50)))))
  (should (not (tg-config--parse-effects nil)))
  (should (not (tg-config--parse-effects "")))
  ;; 测试无效格式
  (should (not (tg-config--parse-effects "invalid"))))

(ert-deftest test-tg-config-parse-behaviors ()
  "测试行为解析"
  (let ((behaviors (tg-config--parse-behaviors "((always . (say hello)))")))
    (should behaviors))
  (let ((behaviors (tg-config--parse-behaviors "((hp-below 10) say \"help\") (always attack)")))
    (should behaviors))
  (should (not (tg-config--parse-behaviors nil)))
  (should (not (tg-config--parse-behaviors "")))
  (should (not (tg-config--parse-behaviors "invalid"))))

(ert-deftest test-tg-config-resolve-handler ()
  "测试 handler 符号解析"
  ;; 有效函数
  (defun test-valid-handler () "test")
  (should (eq (tg-config--resolve-handler "test-valid-handler") 'test-valid-handler))
  ;; 无效函数
  (should (not (tg-config--resolve-handler "non-existent-handler")))
  ;; 空字符串
  (should (not (tg-config--resolve-handler "")))
  (should (not (tg-config--resolve-handler nil)))
  (fmakunbound 'test-valid-handler))

(ert-deftest test-tg-config-parse-dialog-option ()
  "测试对话选项解析"
  (let ((option (tg-config--parse-dialog-option "你好 :: 你好啊 → (exp 10) → next-node")))
    (should option)
    (should (equal (tg-dialog-option-text option) "你好"))
    (should (equal (tg-dialog-option-response option) "你好啊"))
    (should (equal (tg-dialog-option-effects option) '((exp 10))))
    (should (eq (tg-dialog-option-next-node option) 'next-node)))
  ;; 简单选项
  (let ((option (tg-config--parse-dialog-option "再见 :: 再见")))
    (should option)
    (should (equal (tg-dialog-option-text option) "再见"))
    (should (equal (tg-dialog-option-response option) "再见"))
    (should (not (tg-dialog-option-next-node option))))
  (should (not (tg-config--parse-dialog-option "")))
  (should (not (tg-config--parse-dialog-option nil))))

(ert-deftest test-tg-config-load-full ()
  "测试完整配置文件加载"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 测试地牢
#+AUTHOR: 测试作者
#+START: entrance

* Rooms

** entrance
:PROPERTIES:
:NAME: 地牢入口
:DESC: 这是一个阴暗的入口，石门缓缓关闭。
:SHORT_DESC: 地牢入口
:EXITS: north=hall
:CONTENTS: torch
:CREATURES: guard
:END:

** hall
:PROPERTIES:
:NAME: 大厅
:DESC: 宏伟的大厅，墙上挂着火把。
:EXITS: south=entrance,east=throne
:CONTENTS: potion
:CREATURES:
:END:

* Objects

** torch
:PROPERTIES:
:NAME: 火把
:SYNONYMS: light
:PROPS: scenery static
:EFFECTS:
:END:

** potion
:PROPERTIES:
:NAME: 药水
:SYNONYMS: bottle
:PROPS: edible usable
:EFFECTS: (hp 20)
:END:

** key
:PROPERTIES:
:NAME: 铁钥匙
:PROPS: wearable
:EFFECTS: (defense 2)
:END:

* Creatures

** guard
:PROPERTIES:
:NAME: 守卫
:ATTR: hp 30 attack 5
:INVENTORY: sword
:EQUIPMENT:
:EXP_REWARD: 15
:BEHAVIORS: ((always . (say \"站住！\")))
:SHOPKEEPER: nil
:END:

** hero
:PROPERTIES:
:NAME: 英雄
:ATTR: hp 100 attack 10 defense 5 exp 0 level 1 bonus-points 0
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 0
:END:

* Dialogs

** guard
:PROPERTIES:
:NPC_SYMBOL: guard
:GREETING: 站住！你是谁？
:END:
你是谁？ :: 我是一个冒险者。
你是谁？ :: 我不知道 → (exp 5) → guard-trust

** guard-trust
:PROPERTIES:
:NPC_SYMBOL: guard
:GREETING: 哦，我信任你。
:END:
你可以通过了。 :: 谢谢。

* Shops

** shop
:PROPERTIES:
:NPC_SYMBOL: merchant
:SELL_RATE: 0.5
:GOODS: potion=10,sword=30
:END:

* Quests

** kill-rats
:PROPERTIES:
:TYPE: kill
:TARGET: rat
:COUNT: 3
:REWARDS: (exp 20) (item potion)
:END:

** find-key
:PROPERTIES:
:TYPE: collect
:TARGET: key
:COUNT: 1
:REWARDS: (exp 30)
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (let ((game (tg-config-load temp-file)))
              ;; 检查游戏状态
              (should game)
              (should (equal (tg-game-get game :title) "测试地牢"))
              (should (equal (tg-game-get game :author) "测试作者"))
              (should (eq (tg-game-get game :location) 'entrance))
              (should (eq (tg-game-get game :state) 'starting))
              (should (= (tg-game-get game :turns) 0))
              ;; 检查房间
              (let ((entrance (tg-get-room 'entrance)))
                (should entrance)
                (should (eq (tg-room-symbol entrance) 'entrance))
                (should (equal (tg-room-name entrance) "地牢入口"))
                (should (equal (tg-room-desc entrance) "这是一个阴暗的入口，石门缓缓关闭。"))
                (should (equal (tg-room-short-desc entrance) "地牢入口"))
                (should (equal (tg-room-exits entrance) '((north . hall))))
                (should (equal (tg-room-contents entrance) '(torch)))
                (should (equal (tg-room-creatures entrance) '(guard))))
              (let ((hall (tg-get-room 'hall)))
                (should hall)
                (should (equal (tg-room-name hall) "大厅"))
                (should (equal (tg-room-exits hall) '((south . entrance) (east . throne))))
                (should (equal (tg-room-contents hall) '(potion))))
              ;; 检查对象
              (let ((torch (tg-get-object 'torch)))
                (should torch)
                (should (equal (tg-object-name torch) "火把"))
                (should (equal (tg-object-synonyms torch) '(light)))
                (should (memq 'scenery (tg-object-props torch)))
                (should (memq 'static (tg-object-props torch))))
              (let ((potion (tg-get-object 'potion)))
                (should potion)
                (should (equal (tg-object-name potion) "药水"))
                (should (memq 'edible (tg-object-props potion)))
                (should (equal (tg-object-effects potion) '((hp 20)))))
              ;; 检查生物
              (let ((guard (tg-get-creature 'guard)))
                (should guard)
                (should (equal (tg-creature-name guard) "守卫"))
                (should (equal (tg-creature-attr guard) '((hp 30) (attack 5))))
                (should (equal (tg-creature-inventory guard) '(sword)))
                (should (= (tg-creature-exp-reward guard) 15))
                (should (tg-creature-behaviors guard)))
              (let ((hero (tg-get-creature 'hero)))
                (should hero)
                (should (equal (tg-creature-name hero) "英雄"))
                (should (equal (tg-creature-attr hero) '((hp 100) (attack 10) (defense 5) (exp 0) (level 1) (bonus-points 0)))))))
          (delete-file temp-file)))))

(ert-deftest test-tg-config-load-rooms-only ()
  "测试仅加载房间配置"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 简单测试
#+START: room1

* Rooms

** room1
:PROPERTIES:
:NAME: 房间1
:DESC: 第一个房间
:EXITS: east=room2
:END:

** room2
:PROPERTIES:
:NAME: 房间2
:DESC: 第二个房间
:EXITS: west=room1
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (let ((game (tg-config-load temp-file)))
              (should game)
              (should (tg-get-room 'room1))
              (should (tg-get-room 'room2))
              (should (equal (tg-room-name (tg-get-room 'room1)) "房间1"))
              (should (equal (tg-room-exits (tg-get-room 'room1)) '((east . room2))))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-objects-with-effects ()
  "测试加载带效果的对象"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 对象测试

* Objects

** sword
:PROPERTIES:
:NAME: 铁剑
:PROPS: wearable
:EFFECTS: (attack 5 :duration 10)
:END:

** bread
:PROPERTIES:
:NAME: 面包
:PROPS: edible usable
:EFFECTS: (hp 10)
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((sword (tg-get-object 'sword)))
              (should sword)
              (should (equal (tg-object-effects sword) '((attack 5 :duration 10)))))
            (let ((bread (tg-get-object 'bread)))
              (should bread)
              (should (equal (tg-object-effects bread) '((hp 10))))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-creatures-with-behaviors ()
  "测试加载带行为的生物"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 生物测试

* Creatures

** goblin
:PROPERTIES:
:NAME: 哥布林
:ATTR: hp 25 attack 6
:BEHAVIORS: ((hp-below 10) say \"救命！\") (always attack)
:END:

** passive-npc
:PROPERTIES:
:NAME: 被动NPC
:ATTR: hp 50
:BEHAVIORS: ((always) say \"你好\")
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((goblin (tg-get-creature 'goblin)))
              (should goblin)
              (should (tg-creature-behaviors goblin)))
            (let ((npc (tg-get-creature 'passive-npc)))
              (should npc)
              (should (tg-creature-behaviors npc))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-dialogs ()
  "测试加载对话配置"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 对话测试

* Dialogs

** merchant
:PROPERTIES:
:NPC_SYMBOL: merchant
:GREETING: 欢迎光临！
:END:
看看商品 :: 好的，请看。 → (exp 5)
什么也不买 :: 再见。

** merchant-after
:PROPERTIES:
:NPC_SYMBOL: merchant
:GREETING: 你还想买点什么吗？
:END:
不买了 :: 谢谢，再见。
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((dialog (tg-get-dialog 'merchant)))
              (should dialog)
              (should (eq (tg-dialog-state-node-id dialog) 'merchant))
              (should (eq (tg-dialog-state-npc-symbol dialog) 'merchant))
              (should (equal (tg-dialog-state-greeting dialog) "欢迎光临！"))
              (should (= (length (tg-dialog-state-options dialog)) 2)))
            (let ((dialog2 (tg-get-dialog 'merchant-after)))
              (should dialog2)
              (should (= (length (tg-dialog-state-options dialog2)) 1))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-shops ()
  "测试加载商店配置"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 商店测试

* Shops

** general-store
:PROPERTIES:
:NPC_SYMBOL: shopkeeper
:SELL_RATE: 0.3
:GOODS: potion=10,bread=5,sword=50
:END:

** blacksmith
:PROPERTIES:
:NPC_SYMBOL: smith
:SELL_RATE: 0.6
:GOODS: shield=40,armor=100
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((shop (tg-get-shop 'general-store)))
              (should shop)
              (should (eq (tg-shop-npc-symbol shop) 'shopkeeper))
              (should (= (tg-shop-sell-rate shop) 0.3))
              (should (equal (tg-shop-goods shop) '((potion . 10) (bread . 5) (sword . 50)))))
            (let ((shop2 (tg-get-shop 'blacksmith)))
              (should shop2)
              (should (eq (tg-shop-npc-symbol shop2) 'smith))
              (should (= (tg-shop-sell-rate shop2) 0.6))
              (should (equal (tg-shop-goods shop2) '((shield . 40) (armor . 100))))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-quests ()
  "测试加载任务配置"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 任务测试

* Quests

** kill-rats
:PROPERTIES:
:TYPE: kill
:TARGET: rat
:COUNT: 5
:REWARDS: (exp 30) (item sword)
:END:

** find-treasure
:PROPERTIES:
:TYPE: collect
:TARGET: gold
:COUNT: 100
:REWARDS: (exp 50) (bonus-points 2)
:END:

** explore-cave
:PROPERTIES:
:TYPE: explore
:TARGET: cave
:COUNT: 1
:REWARDS: (exp 100)
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((quest (tg-get-quest 'kill-rats)))
              (should quest)
              (should (eq (tg-quest-type quest) 'kill))
              (should (eq (tg-quest-target quest) 'rat))
              (should (= (tg-quest-count quest) 5))
              (should (equal (tg-quest-rewards quest) '((exp 30) (item sword))))
              (should (eq (tg-quest-status quest) 'inactive))
              (should (= (tg-quest-progress quest) 0)))
            (let ((quest2 (tg-get-quest 'find-treasure)))
              (should quest2)
              (should (eq (tg-quest-type quest2) 'collect))
              (should (eq (tg-quest-target quest2) 'gold))
              (should (= (tg-quest-count quest2) 100))
              (should (equal (tg-quest-rewards quest2) '((exp 50) (bonus-points 2))))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-invalid-section-ignored ()
  "测试无效 section 被忽略"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 无效Section测试

* InvalidSection
This should be ignored.

* Rooms

** room1
:PROPERTIES:
:NAME: 房间1
:DESC: 测试房间
:END:

* AnotherInvalid
More content to ignore.
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (let ((game (tg-config-load temp-file)))
              (should game)
              (should (tg-get-room 'room1))
              (should (not (tg-get-object 'invalid)))
              (should (not (tg-get-creature 'invalid)))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-load-nonexistent-file ()
  "测试加载不存在的文件"
  (should-error (tg-config-load "/nonexistent/file.org")))

(ert-deftest test-tg-config-load-empty-properties ()
  "测试空属性处理"
  (tg-registry-clear)
  (let ((org-content "#+TITLE: 空属性测试

* Rooms

** room1
:PROPERTIES:
:NAME: 房间1
:DESC: 描述
:EXITS:
:CONTENTS:
:CREATURES:
:END:

* Objects

** obj1
:PROPERTIES:
:NAME: 对象1
:PROPS:
:EFFECTS:
:END:

* Creatures

** creature1
:PROPERTIES:
:NAME: 生物1
:ATTR:
:INVENTORY:
:EQUIPMENT:
:END:
"))
    (let ((temp-file (make-temp-file "tg-test-" nil ".org")))
      (unwind-protect
          (progn
            (write-region org-content nil temp-file)
            (tg-config-load temp-file)
            (let ((room (tg-get-room 'room1)))
              (should room)
              (should (not (tg-room-exits room)))
              (should (not (tg-room-contents room)))
              (should (not (tg-room-creatures room))))
            (let ((obj (tg-get-object 'obj1)))
              (should obj)
              (should (not (tg-object-props obj)))
              (should (not (tg-object-effects obj))))
            (let ((creature (tg-get-creature 'creature1)))
              (should creature)
              (should (not (tg-creature-attr creature)))
              (should (not (tg-creature-inventory creature)))
              (should (not (tg-creature-equipment creature)))))
        (delete-file temp-file)))))

(ert-deftest test-tg-config-parse-dialog-option-complex ()
  "测试复杂对话选项解析"
  ;; 带条件和多个效果
  (let ((option (tg-config--parse-dialog-option "购买物品 :: 好的，给你 → (gold -10) (item potion) → done")))
    (should option)
    (should (equal (tg-dialog-option-text option) "购买物品"))
    (should (equal (tg-dialog-option-response option) "好的，给你"))
    (should (equal (tg-dialog-option-effects option) '((gold -10) (item potion))))
    (should (eq (tg-dialog-option-next-node option) 'done))))

(ert-deftest test-tg-config-parse-dialog-option-with-condition ()
  "测试解析带条件的对话选项。"
  (let ((opt (tg-config--parse-dialog-option "[(has-item bread)] 给你面包 :: 谢谢！ → (exp 10)")))
    (should opt)
    (should (equal (tg-dialog-option-condition opt) '(has-item bread)))
    (should (string= (tg-dialog-option-text opt) "给你面包"))
    (should (string= (tg-dialog-option-response opt) "谢谢！"))
    (should (equal (tg-dialog-option-effects opt) '((exp 10))))))

(ert-deftest test-tg-config-parse-dialog-option-without-condition ()
  "测试无条件的对话选项仍然正常解析。"
  (let ((opt (tg-config--parse-dialog-option "你是谁？ :: 我是探险者。")))
    (should opt)
    (should (null (tg-dialog-option-condition opt)))
    (should (string= (tg-dialog-option-text opt) "你是谁？"))
    (should (string= (tg-dialog-option-response opt) "我是探险者。"))))

(ert-deftest test-tg-config-parse-level-section-default ()
  "测试无 Level 段时保持默认值。"
  (let ((default-table tg-level-exp-table)
        (default-bonus tg-level-bonus-points-per-level)
        (default-auto tg-level-auto-upgrade-attrs))
    (unwind-protect
        (progn
          (tg-config-load (expand-file-name "test/fixtures/mini-game/game.org"))
          (should (equal tg-level-exp-table default-table)))
      (setq tg-level-exp-table default-table
            tg-level-bonus-points-per-level default-bonus
            tg-level-auto-upgrade-attrs default-auto))))

(ert-deftest test-tg-config-parse-level-section-with-data ()
  "测试 Level 段解析设置全局变量。"
  (let ((default-table tg-level-exp-table)
        (default-bonus tg-level-bonus-points-per-level)
        (default-auto tg-level-auto-upgrade-attrs))
    (unwind-protect
        (progn
          (tg-config-load (expand-file-name "test/fixtures/level-game.org"))
          (should (equal tg-level-exp-table '(0 100 200 400)))
          (should (eq tg-level-bonus-points-per-level 5))
          (should (equal tg-level-auto-upgrade-attrs '((hp 20) (attack 1)))))
      (setq tg-level-exp-table default-table
            tg-level-bonus-points-per-level default-bonus
            tg-level-auto-upgrade-attrs default-auto)
      (tg-registry-clear))))

(ert-deftest test-tg-config-parse-object-with-contents ()
  "测试解析容器对象的 CONTENTS 字段。"
  (tg-registry-clear)
  (let ((org-content "
* Objects
** chest
:PROPERTIES:
:NAME: 宝箱
:PROPS: container
:CONTENTS: coin,gem
:END:
"))
    (with-temp-buffer
      (insert org-content)
      (org-mode)
      (let* ((tree (org-element-parse-buffer))
             (objects-section (org-element-map tree 'headline
                               (lambda (h) (when (string= (downcase (org-element-property :raw-value h)) "objects") h))
                               nil t)))
        (tg-config--parse-object-section objects-section)
        (let ((chest (tg-get-object 'chest)))
          (should chest)
          (should (equal (tg-object-contents chest) '(coin gem)))))))
  (tg-registry-clear))

(ert-deftest test-tg-config-parse-object-with-supports ()
  "测试解析支撑物对象的 SUPPORTS 字段。"
  (tg-registry-clear)
  (let ((org-content "
* Objects
** table
:PROPERTIES:
:NAME: 木桌
:PROPS: supporter
:SUPPORTS: lamp,book
:END:
"))
    (with-temp-buffer
      (insert org-content)
      (org-mode)
      (let* ((tree (org-element-parse-buffer))
             (objects-section (org-element-map tree 'headline
                               (lambda (h) (when (string= (downcase (org-element-property :raw-value h)) "objects") h))
                               nil t)))
        (tg-config--parse-object-section objects-section)
        (let ((table (tg-get-object 'table)))
          (should table)
          (should (equal (tg-object-supports table) '(lamp book)))))))
  (tg-registry-clear))

(ert-deftest test-tg-config-parse-respawn-interval ()
  "测试刷新区间解析"
  (should (equal (tg-config--parse-respawn-interval "8-15") '(8 . 15)))
  (should (equal (tg-config--parse-respawn-interval "10") '(10 . 10)))
  (should (null (tg-config--parse-respawn-interval nil)))
  (should (null (tg-config--parse-respawn-interval "")))
  (should (null (tg-config--parse-respawn-interval "15-8")))  ;; N > M → nil
  (should (null (tg-config--parse-respawn-interval "0")))     ;; 0 → nil（无效间隔）
  (should (null (tg-config--parse-respawn-interval "0-0")))   ;; 0-0 → nil
  (should (null (tg-config--parse-respawn-interval "0-5"))))  ;; min < 1 → nil

(provide 'tg-config-test)
;;; test/tg-config-test.el ends here
