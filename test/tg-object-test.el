;;; test/tg-object-test.el --- tg-object 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-object)

(cl-defstruct tg-room
  symbol name desc short-desc exits contents creatures
  before-handler after-handler visit-count)

(ert-deftest test-tg-object-create-and-props ()
  "测试对象创建及属性检查"
  (let* ((box (make-tg-object :symbol 'box
                             :name "木箱"
                             :synonyms '(chest crate)
                             :props '(container)
                             :state 'closed
                             :key 'lockpick
                             :effects '((lock-pick-level 2))
                             :contents '(item1 item2))))
    (should (eq (tg-object-symbol box) 'box))
    (should (equal (tg-object-name box) "木箱"))
    (should (equal (tg-object-synonyms box) '(chest crate)))
    (should (equal (tg-object-contents box) '(item1 item2)))
    (should (tg-object-container-p box))
    (should (not (tg-object-supporter-p box)))
    (should (not (tg-object-locked-p box)))  ;; closed 不等于 locked
    (should (not (tg-object-open-p box)))))

(ert-deftest test-tg-object-supporter ()
  "测试 supporter 属性"
  (let ((table (make-tg-object :symbol 'table
                               :name "桌子"
                               :props '(supporter)
                               :supports '(lamp book))))
    (should (tg-object-supporter-p table))
    (should (not (tg-object-container-p table)))
    (should (equal (tg-object-supports table) '(lamp book)))))

(ert-deftest test-tg-object-scenery ()
  "测试 scenery 属性"
  (let ((tree (make-tg-object :symbol 'tree
                              :name "大树"
                              :props '(scenery))))
    (should (tg-object-has-prop-p tree 'scenery))
    (should (not (tg-object-takeable-p tree)))))

(ert-deftest test-tg-object-static ()
  "测试 static 属性"
  (let ((statue (make-tg-object :symbol 'statue
                                :name "雕像"
                                :props '(static))))
    (should (tg-object-has-prop-p statue 'static))
    (should (not (tg-object-takeable-p statue)))))

(ert-deftest test-tg-object-wearable ()
  "测试 wearable 属性及 effects"
  (let* ((sword (make-tg-object :symbol 'sword
                                :name "铁剑"
                                :props '(wearable)
                                :effects '((attack 5) (damage 3))))
         (effects (tg-object-effects sword)))
    (should (tg-object-wearable-p sword))
    (should (tg-object-has-prop-p sword 'wearable))
    (should (= (length effects) 2))
    (should (equal (car effects) '(attack 5)))))

(ert-deftest test-tg-object-edible ()
  "测试 edible 属性及临时 effects"
  (let* ((potion (make-tg-object :symbol 'potion
                                 :name "治疗药水"
                                 :props '(edible)
                                 :effects '((hp 20) (strength 2 :duration 10))))
         (effects (tg-object-effects potion)))
    (should (tg-object-has-prop-p potion 'edible))
    (should (= (length effects) 2))
    (should (equal (car effects) '(hp 20)))
    (should (equal (cadr effects) '(strength 2 :duration 10)))))

(ert-deftest test-tg-object-readable ()
  "测试 readable 属性"
  (let ((book (make-tg-object :symbol 'book
                              :name "魔法书"
                              :props '(readable))))
    (should (tg-object-has-prop-p book 'readable))))

(ert-deftest test-tg-object-takeable-p ()
  "测试 takeable-p 判定逻辑"
  (let ((item (make-tg-object :symbol 'coin :name "金币")))
    (should (tg-object-takeable-p item)))
  (let ((tree (make-tg-object :symbol 'tree :name "树" :props '(scenery))))
    (should (not (tg-object-takeable-p tree))))
  (let ((table (make-tg-object :symbol 'table :name "桌子" :props '(supporter))))
    (should (not (tg-object-takeable-p table))))
  (let ((statue (make-tg-object :symbol 'statue :name "雕像" :props '(static))))
    (should (not (tg-object-takeable-p statue)))))

(ert-deftest test-tg-object-state-machine ()
  "测试容器状态机转换"
  (let ((box (make-tg-object :symbol 'box
                             :name "箱子"
                             :props '(container)
                             :state 'closed
                             :key 'key)))
    ;; 初始状态 closed
    (should (tg-object-can-open-p box))
    (should (not (tg-object-can-close-p box)))  ;; 已关闭，不能再关闭
    (should (not (tg-object-locked-p box)))     ;; closed 不等于 locked
    ;; 打开箱子
    (setf (tg-object-state box) 'open)
    (should (tg-object-open-p box))
    (should (tg-object-can-close-p box))        ;; 打开后可以关闭
    ;; 关闭箱子
    (setf (tg-object-state box) 'closed)
    (should (not (tg-object-open-p box)))
    ;; 锁定箱子
    (setf (tg-object-state box) 'locked)
    (should (tg-object-locked-p box))
    (should (not (tg-object-can-open-p box)))))

(provide 'tg-object-test)

(ert-deftest test-tg-object-accessible-p ()
  "测试 accessible-p 判定"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                             :name "房间"
                             :desc "测试房间"
                             :exits '()
                             :contents '(table box-closed box-open box-locked)))
         (table (make-tg-object :symbol 'table
                               :name "桌子"
                               :props '(supporter)
                               :supports '(lamp)))
         (box-closed (make-tg-object :symbol 'box-closed
                                    :name "关闭的箱子"
                                    :props '(container)
                                    :state 'closed
                                    :contents '(key)))
         (box-open (make-tg-object :symbol 'box-open
                                  :name "打开的箱子"
                                  :props '(container)
                                  :state 'open
                                  :contents '(coin)))
         (box-locked (make-tg-object :symbol 'box-locked
                                    :name "锁住的箱子"
                                    :props '(container)
                                    :state 'locked
                                    :contents '(gem)
                                    :key 'lockpick))
         (lamp (make-tg-object :symbol 'lamp :name "台灯"))
         (key (make-tg-object :symbol 'key :name "钥匙"))
         (coin (make-tg-object :symbol 'coin :name "金币"))
         (gem (make-tg-object :symbol 'gem :name "宝石")))
    (tg-register-object 'table table)
    (tg-register-object 'box-closed box-closed)
    (tg-register-object 'box-open box-open)
    (tg-register-object 'box-locked box-locked)
    (tg-register-object 'lamp lamp)
    (tg-register-object 'key key)
    (tg-register-object 'coin coin)
    (tg-register-object 'gem gem)
    (should (tg-object-accessible-p table room))
    (should (tg-object-accessible-p lamp room))
    (should (tg-object-accessible-p coin room))
    (should (not (tg-object-accessible-p key room)))
    (should (not (tg-object-accessible-p gem room)))))

(ert-deftest test-tg-object-find-parent ()
  "测试在房间/背包中查找父容器"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                             :name "房间"
                             :desc "测试"
                             :exits '()
                             :contents '(box)))
         (box (make-tg-object :symbol 'box
                             :name "箱子"
                             :props '(container)
                             :state 'open
                             :contents '(coin)))
         (coin (make-tg-object :symbol 'coin :name "金币")))
    (tg-register-object 'box box)
    (tg-register-object 'coin coin)
    (should (eq (tg-object-find-parent coin room) 'box))
    (should (eq (tg-object-find-parent box room) 'room))
    (should (not (tg-object-find-parent (make-tg-object :symbol 'unknown) room)))))

(ert-deftest test-tg-object-find-in-room ()
  "测试在房间中查找对象"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                             :name "房间"
                             :desc "测试"
                             :exits '()
                             :contents '(table)))
         (table (make-tg-object :symbol 'table
                               :name "桌子"
                               :props '(supporter)
                               :supports '(lamp)))
         (lamp (make-tg-object :symbol 'lamp :name "台灯" :synonyms '(light))))
    (tg-register-object 'table table)
    (tg-register-object 'lamp lamp)
    (should (eq (tg-object-find-in-room room 'table) 'table))
    (should (eq (tg-object-find-in-room room 'lamp) 'lamp))
    (should (not (tg-object-find-in-room room 'unknown)))))

(ert-deftest test-tg-object-find-in-inventory ()
  "测试在背包中查找对象"
  (tg-registry-clear)
  (let* ((inventory '(sword potion))
         (sword (make-tg-object :symbol 'sword :name "剑"))
         (potion (make-tg-object :symbol 'potion :name "药水")))
    (tg-register-object 'sword sword)
    (tg-register-object 'potion potion)
    (should (eq (tg-object-find-in-inventory inventory 'sword) 'sword))
    (should (eq (tg-object-find-in-inventory inventory 'potion) 'potion))
    (should (not (tg-object-find-in-inventory inventory 'unknown)))))

(ert-deftest test-tg-object-find ()
  "测试全局查找对象（通过注册表）"
  (tg-registry-clear)
  (let ((obj (make-tg-object :symbol 'book :name "书")))
    (tg-register-object 'book obj)
    (should (eq (tg-object-find 'book) obj))
    (should (not (tg-object-find 'unknown)))))

(ert-deftest test-tg-object-move ()
  "测试对象移动"
  (tg-registry-clear)
  (let* ((room1 (make-tg-room :symbol 'room1
                              :name "房间1"
                              :desc "测试1"
                              :exits '()
                              :contents '(box)))
         (room2 (make-tg-room :symbol 'room2
                              :name "房间2"
                              :desc "测试2"
                              :exits '()
                              :contents '()))
         (box (make-tg-object :symbol 'box :name "箱子")))
    (tg-register-object 'box box)
    (should (member 'box (tg-room-contents room1)))
    (should (not (member 'box (tg-room-contents room2))))
    (tg-object-move 'box room1 room2)
    (should (not (member 'box (tg-room-contents room1))))
    (should (member 'box (tg-room-contents room2)))))

(provide 'tg-object-test)
;;; tg-object-test.el ends here
