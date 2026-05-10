;;; test/tg-room-test.el --- tg-room 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-object)
(require 'tg-room)

(ert-deftest test-tg-room-create ()
  "测试房间创建"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "这是一个房间"
                            :short-desc "房间"
                            :exits '((north . hallway))
                            :contents '()
                            :creatures '()
                            :visit-count 0)))
    (should (eq (tg-room-symbol room) 'room))
    (should (equal (tg-room-name room) "房间"))
    (should (equal (tg-room-desc room) "这是一个房间"))
    (should (equal (tg-room-short-desc room) "房间"))
    (should (equal (tg-room-exits room) '((north . hallway))))
    (should (equal (tg-room-contents room) '()))
    (should (equal (tg-room-creatures room) '()))
    (should (= (tg-room-visit-count room) 0))))

(ert-deftest test-tg-directions ()
  "测试方向常量"
  (should (assq 'north tg-directions))
  (should (assq 'south tg-directions))
  (should (assq 'east tg-directions))
  (should (assq 'west tg-directions))
  (should (assq 'northeast tg-directions))
  (should (assq 'northwest tg-directions))
  (should (assq 'southeast tg-directions))
  (should (assq 'southwest tg-directions))
  (should (assq 'up tg-directions))
  (should (assq 'down tg-directions))
  (should (assq 'in tg-directions))
  (should (assq 'out tg-directions))
  ;; 检查缩写
  (should (equal (cdr (assq 'north tg-directions)) 'n))
  (should (equal (cdr (assq 'south tg-directions)) 's))
  (should (equal (cdr (assq 'east tg-directions)) 'e))
  (should (equal (cdr (assq 'west tg-directions)) 'w))
  (should (equal (cdr (assq 'up tg-directions)) 'u))
  (should (equal (cdr (assq 'down tg-directions)) 'd))
  ;; in/out 无缩写
  (should (not (cdr (assq 'in tg-directions))))
  (should (not (cdr (assq 'out tg-directions)))))

(ert-deftest test-tg-room-exit ()
  "测试出口查找"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :exits '((north . hallway)
                                     (south . garden)
                                     (up . roof)))))
    (should (eq (tg-room-exit room 'north) 'hallway))
    (should (eq (tg-room-exit room 'south) 'garden))
    (should (eq (tg-room-exit room 'up) 'roof))
    (should (not (tg-room-exit room 'east)))  ;; 不存在的方向
    (should (not (tg-room-exit room 'down)))))

(ert-deftest test-tg-room-visit ()
  "测试访问计数"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :visit-count 0)))
    (should (= (tg-room-visit-count room) 0))
    (tg-room-visit room)
    (should (= (tg-room-visit-count room) 1))
    (tg-room-visit room)
    (should (= (tg-room-visit-count room) 2))
    (tg-room-visit room)
    (should (= (tg-room-visit-count room) 3))))

(ert-deftest test-tg-room-all-visible-objects-simple ()
  "测试简单场景的可见对象"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                              :name "房间"
                              :desc "测试"
                              :contents '(lamp box)))
         (lamp (make-tg-object :symbol 'lamp
                               :name "台灯"
                               :props '()))
         (box (make-tg-object :symbol 'box
                              :name "箱子"
                              :props '(container)
                              :state 'closed
                              :contents '(key))))
    (tg-register-object 'lamp lamp)
    (tg-register-object 'box box)
    (let ((visible (tg-room-all-visible-objects room)))
      (should (member 'lamp visible))
      (should (member 'box visible))
      (should (not (member 'key visible)))  ;; closed 容器内不可见
      (should (= (length visible) 2)))))

(ert-deftest test-tg-room-all-visible-objects-open-container ()
  "测试打开容器内的对象可见"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                              :name "房间"
                              :desc "测试"
                              :contents '(box)))
         (box (make-tg-object :symbol 'box
                              :name "箱子"
                              :props '(container)
                              :state 'open
                              :contents '(key coin))))
    (tg-register-object 'box box)
    (tg-register-object 'key (make-tg-object :symbol 'key :name "钥匙"))
    (tg-register-object 'coin (make-tg-object :symbol 'coin :name "金币"))
    (let ((visible (tg-room-all-visible-objects room)))
      (should (member 'box visible))
      (should (member 'key visible))
      (should (member 'coin visible))
      (should (= (length visible) 3)))))

(ert-deftest test-tg-room-all-visible-objects-supporter ()
  "测试支撑物上的对象可见"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                              :name "房间"
                              :desc "测试"
                              :contents '(table)))
         (table (make-tg-object :symbol 'table
                                :name "桌子"
                                :props '(supporter)
                                :supports '(lamp book))))
    (tg-register-object 'table table)
    (tg-register-object 'lamp (make-tg-object :symbol 'lamp :name "台灯"))
    (tg-register-object 'book (make-tg-object :symbol 'book :name "书"))
    (let ((visible (tg-room-all-visible-objects room)))
      (should (member 'table visible))
      (should (member 'lamp visible))
      (should (member 'book visible))
      (should (= (length visible) 3)))))

(ert-deftest test-tg-room-all-visible-objects-nested ()
  "测试嵌套场景（容器在支撑物上，容器内有物品）"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                              :name "房间"
                              :desc "测试"
                              :contents '(table)))
         (box (make-tg-object :symbol 'box
                              :name "箱子"
                              :props '(container)
                              :state 'open
                              :contents '(key)))
         (table (make-tg-object :symbol 'table
                                :name "桌子"
                                :props '(supporter)
                                :supports '(box))))
    (tg-register-object 'table table)
    (tg-register-object 'box box)
    (tg-register-object 'key (make-tg-object :symbol 'key :name "钥匙"))
    (let ((visible (tg-room-all-visible-objects room)))
      (should (member 'table visible))
      (should (member 'box visible))
      (should (member 'key visible))
      (should (= (length visible) 3)))))

(ert-deftest test-tg-room-describe-first-visit ()
  "测试首次访问的完整描述"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "这是一个明亮的房间，墙上挂着画作。"
                            :visit-count 0)))
    (let ((desc (tg-room-describe room)))
      (should (string-match-p "明亮的房间" desc))
      (should (string-match-p "墙上挂着画作" desc)))))

(ert-deftest test-tg-room-describe-repeat-visit ()
  "测试重复访问的简短描述"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "这是一个明亮的房间。"
                            :short-desc "房间"
                            :visit-count 1)))
    (let ((desc (tg-room-describe room)))
      (should (string-match-p "房间" desc))
      ;; 简短描述不应包含完整描述
      (should (not (string-match-p "明亮的房间" desc))))))

(ert-deftest test-tg-room-describe-with-objects ()
  "测试描述包含可见物品"
  (tg-registry-clear)
  (let* ((room (make-tg-room :symbol 'room
                              :name "房间"
                              :desc "测试房间"
                              :contents '(lamp)
                              :visit-count 0))
         (lamp (make-tg-object :symbol 'lamp
                               :name "台灯"
                               :props '())))
    (tg-register-object 'lamp lamp)
    (let ((desc (tg-room-describe room)))
      (should (string-match-p "台灯" desc)))))

(ert-deftest test-tg-room-describe-with-creatures ()
  "测试描述包含生物"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试房间"
                            :contents '()
                            :creatures '(goblin)
                            :visit-count 0)))
    ;; 注册 creature（这里简单用 symbol 代表）
    (let ((desc (tg-room-describe room)))
      (should (string-match-p "goblin" desc)))))

(ert-deftest test-tg-room-add-object ()
  "测试添加对象到房间"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :contents '())))
    (should (equal (tg-room-contents room) '()))
    (tg-room-add-object room 'lamp)
    (should (member 'lamp (tg-room-contents room)))
    (tg-room-add-object room 'table)
    (should (member 'table (tg-room-contents room)))
    (should (member 'lamp (tg-room-contents room)))
    (should (= (length (tg-room-contents room)) 2))))

(ert-deftest test-tg-room-remove-object ()
  "测试从房间移除对象"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :contents '(lamp table))))
    (should (member 'lamp (tg-room-contents room)))
    (should (member 'table (tg-room-contents room)))
    (tg-room-remove-object room 'lamp)
    (should (not (member 'lamp (tg-room-contents room))))
    (should (member 'table (tg-room-contents room)))
    (should (= (length (tg-room-contents room)) 1))))

(ert-deftest test-tg-room-add-creature ()
  "测试添加生物到房间"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :creatures '())))
    (should (equal (tg-room-creatures room) '()))
    (tg-room-add-creature room 'goblin)
    (should (member 'goblin (tg-room-creatures room)))
    (tg-room-add-creature room 'wolf)
    (should (member 'wolf (tg-room-creatures room)))
    (should (member 'goblin (tg-room-creatures room)))
    (should (= (length (tg-room-creatures room)) 2))))

(ert-deftest test-tg-room-remove-creature ()
  "测试从房间移除生物"
  (let ((room (make-tg-room :symbol 'room
                            :name "房间"
                            :desc "测试"
                            :creatures '(goblin wolf))))
    (should (member 'goblin (tg-room-creatures room)))
    (should (member 'wolf (tg-room-creatures room)))
    (tg-room-remove-creature room 'goblin)
    (should (not (member 'goblin (tg-room-creatures room))))
    (should (member 'wolf (tg-room-creatures room)))
    (should (= (length (tg-room-creatures room)) 1))))

(provide 'tg-room-test)
;;; test/tg-room-test.el ends here
