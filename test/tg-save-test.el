;;; tg-save-test.el --- 存档系统测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'tg-save)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-quest)

;;; 测试夹具

(defun tg-save-test-setup ()
  "设置测试环境：创建 game, rooms, objects, creatures, quests"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Save Test" "Author"))
  (tg-game-put tg-game :state 'playing)
  (tg-game-put tg-game :turns 42)
  (tg-game-put tg-game :location 'room1)
  (tg-game-put tg-game :player 'player)
  (tg-game-put tg-game :active-buffs '((attack :delta 5 :remaining 3 :duration 3)))
  ;; 注册房间
  (let ((room1 (make-tg-room :symbol 'room1
                             :name "房间1"
                             :desc "测试房间1"
                             :exits '((north . room2))
                             :contents '(key chest)
                             :creatures '(player goblin)
                             :visit-count 2)))
    (tg-register-room 'room1 room1))
  (let ((room2 (make-tg-room :symbol 'room2
                             :name "房间2"
                             :desc "测试房间2"
                             :exits '((south . room1))
                             :contents '()
                             :creatures '()
                             :visit-count 0)))
    (tg-register-room 'room2 room2))
  ;; 注册对象
  (let ((key (make-tg-object :symbol 'key
                             :name "钥匙"
                             :props '()
                             :state nil
                             :contents '()
                             :supports '())))
    (tg-register-object 'key key))
  (let ((chest (make-tg-object :symbol 'chest
                               :name "箱子"
                               :props '(container)
                               :state 'open
                               :contents '(gold-coin)
                               :supports '())))
    (tg-register-object 'chest chest))
  (let ((gold-coin (make-tg-object :symbol 'gold-coin
                                   :name "金币"
                                   :props '()
                                   :state nil
                                   :contents '()
                                   :supports '())))
    (tg-register-object 'gold-coin gold-coin))
  (let ((sword (make-tg-object :symbol 'sword
                               :name "铁剑"
                               :props '(wearable)
                               :effects '((attack 5))
                               :state nil
                               :contents '()
                               :supports '())))
    (tg-register-object 'sword sword))
  ;; 注册生物
  (let ((player (make-tg-creature :symbol 'player
                                  :name "玩家"
                                  :attr (list (list 'hp 100) (list 'attack 15))
                                  :inventory '(sword)
                                  :equipment '())))
    (tg-register-creature 'player player))
  (let ((goblin (make-tg-creature :symbol 'goblin
                                  :name "哥布林"
                                  :attr (list (list 'hp 30))
                                  :inventory '()
                                  :equipment '())))
    (tg-register-creature 'goblin goblin))
  ;; 注册任务
  (let ((quest (make-tg-quest :symbol 'q1
                              :type 'kill
                              :target 'goblin
                              :count 3
                              :progress 2
                              :status 'active
                              :rewards '((exp 50)))))
    (tg-register-quest 'q1 quest)))

;;; 测试用的 game.org 配置内容

(defconst tg-save-test-config-content
  "#+TITLE: Save Test
#+AUTHOR: Author
#+START: room1

* Rooms

** room1
:PROPERTIES:
:NAME: 房间1
:DESC: 测试房间1
:EXITS: north=room2
:CONTENTS: key chest
:CREATURES: player goblin
:END:

** room2
:PROPERTIES:
:NAME: 房间2
:DESC: 测试房间2
:EXITS: south=room1
:END:

* Objects

** key
:PROPERTIES:
:NAME: 钥匙
:END:

** chest
:PROPERTIES:
:NAME: 箱子
:PROPS: container
:END:

** gold-coin
:PROPERTIES:
:NAME: 金币
:END:

** sword
:PROPERTIES:
:NAME: 铁剑
:PROPS: wearable
:EFFECTS: (attack 5)
:END:

* Creatures

** player
:PROPERTIES:
:NAME: 玩家
:ATTR: hp 50 attack 10
:END:

** goblin
:PROPERTIES:
:NAME: 哥布林
:ATTR: hp 20
:END:

* Quests

** q1
:PROPERTIES:
:TYPE: kill
:TARGET: goblin
:COUNT: 3
:REWARDS: (exp 50)
:END:
")

;;; 辅助函数

(defun tg-save-test--make-config-dir ()
  "创建包含 game.org 的临时配置目录，返回目录路径"
  (let ((dir (make-temp-file "tg-save-test-config-" t)))
    (write-region tg-save-test-config-content nil
                  (expand-file-name "game.org" dir))
    dir))

;;; 测试：保存 → 文件存在且可读

(ert-deftest test-tg-save-file-exists-and-readable ()
  "保存后文件存在且内容可被 read 解析"
  (tg-save-test-setup)
  (let ((save-file (make-temp-file "tg-save-" nil ".el")))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          (should (file-exists-p save-file))
          ;; 文件内容可被 read 解析
          (let ((data (with-temp-buffer
                        (insert-file-contents save-file)
                        (goto-char (point-min))
                        (read (current-buffer)))))
            (should data)
            ;; 顶层是 alist，包含 :game :rooms :objects :creatures :quests
            (should (assq :game data))
            (should (assq :rooms data))
            (should (assq :objects data))
            (should (assq :creatures data))
            (should (assq :quests data))))
      (delete-file save-file))))

;;; 测试：加载 → game 动态状态恢复

(ert-deftest test-tg-load-restores-game-state ()
  "加载后 game 的 location/turns/state/active-buffs/player 恢复正确"
  (tg-save-test-setup)
  (let* ((save-file (make-temp-file "tg-save-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          ;; 加载：重载配置 + 恢复动态状态
          (tg-load-game save-file config-dir)
          (should (eq (tg-game-get tg-game :location) 'room1))
          (should (= (tg-game-get tg-game :turns) 42))
          (should (eq (tg-game-get tg-game :state) 'playing))
          (should (eq (tg-game-get tg-game :player) 'player))
          (should (equal (tg-game-get tg-game :active-buffs)
                         '((attack :delta 5 :remaining 3 :duration 3)))))
      (delete-file save-file)
      (delete-directory config-dir t))))

;;; 测试：room visit-count 恢复

(ert-deftest test-tg-load-restores-room-visit-count ()
  "加载后房间 visit-count 恢复正确"
  (tg-save-test-setup)
  (let* ((save-file (make-temp-file "tg-save-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          (tg-load-game save-file config-dir)
          (let ((room1 (tg-get-room 'room1))
                (room2 (tg-get-room 'room2)))
            (should (= (tg-room-visit-count room1) 2))
            (should (= (tg-room-visit-count room2) 0))))
      (delete-file save-file)
      (delete-directory config-dir t))))

;;; 测试：object state/contents 恢复

(ert-deftest test-tg-load-restores-object-state ()
  "加载后对象 state/contents/supports 恢复正确"
  (tg-save-test-setup)
  (let* ((save-file (make-temp-file "tg-save-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          (tg-load-game save-file config-dir)
          (let ((chest (tg-get-object 'chest))
                (key (tg-get-object 'key)))
            ;; chest 恢复为 open 且包含 gold-coin
            (should (eq (tg-object-state chest) 'open))
            (should (equal (tg-object-contents chest) '(gold-coin)))
            ;; key 无 state
            (should (null (tg-object-state key)))))
      (delete-file save-file)
      (delete-directory config-dir t))))

;;; 测试：creature attr 恢复

(ert-deftest test-tg-load-restores-creature-attr ()
  "加载后生物 attr/inventory/equipment 恢复正确"
  (tg-save-test-setup)
  (let* ((save-file (make-temp-file "tg-save-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          (tg-save-game save-file)
          (tg-load-game save-file config-dir)
          (let ((player (tg-get-creature 'player))
                (goblin (tg-get-creature 'goblin)))
            ;; player attr 恢复为存档时的值，而非配置默认值
            (should (equal (tg-creature-attr player)
                           '((hp 100) (attack 15))))
            (should (equal (tg-creature-inventory player) '(sword)))
            (should (null (tg-creature-equipment player)))
            ;; goblin attr 恢复
            (should (equal (tg-creature-attr goblin) '((hp 30))))
            (should (null (tg-creature-inventory goblin)))))
      (delete-file save-file)
      (delete-directory config-dir t))))

;;; 测试：round-trip（save→load→save 一致）

(ert-deftest test-tg-save-round-trip ()
  "save→load→save 后两次存档内容一致"
  (tg-save-test-setup)
  (let* ((save-file-1 (make-temp-file "tg-save-rt1-" nil ".el"))
         (save-file-2 (make-temp-file "tg-save-rt2-" nil ".el"))
         (config-dir (tg-save-test--make-config-dir)))
    (unwind-protect
        (progn
          ;; 第一次保存
          (tg-save-game save-file-1)
          ;; 加载恢复
          (tg-load-game save-file-1 config-dir)
          ;; 第二次保存
          (tg-save-game save-file-2)
          ;; 比较两次存档内容
          (let ((data-1 (with-temp-buffer
                          (insert-file-contents save-file-1)
                          (goto-char (point-min))
                          (read (current-buffer))))
                (data-2 (with-temp-buffer
                          (insert-file-contents save-file-2)
                          (goto-char (point-min))
                          (read (current-buffer)))))
            ;; 排序后比较（因为 maphash 遍历顺序不确定）
            (should (equal (tg-save-test--sorted-save-data data-1)
                           (tg-save-test--sorted-save-data data-2)))))
      (delete-file save-file-1)
      (delete-file save-file-2)
      (delete-directory config-dir t))))

(defun tg-save-test--sorted-save-data (data)
  "对存档数据中的列表进行排序以便比较"
  (let ((game (cdr (assq :game data)))
        (rooms (cdr (assq :rooms data)))
        (objects (cdr (assq :objects data)))
        (creatures (cdr (assq :creatures data)))
        (quests (cdr (assq :quests data))))
    (list (cons :game game)
          (cons :rooms (sort (copy-alist rooms)
                             (lambda (a b) (string< (symbol-name (car a))
                                                    (symbol-name (car b))))))
          (cons :objects (sort (copy-alist objects)
                               (lambda (a b) (string< (symbol-name (car a))
                                                      (symbol-name (car b))))))
          (cons :creatures (sort (copy-alist creatures)
                                 (lambda (a b) (string< (symbol-name (car a))
                                                        (symbol-name (car b))))))
          (cons :quests (sort (copy-alist quests)
                              (lambda (a b) (string< (symbol-name (car a))
                                                     (symbol-name (car b)))))))))

(provide 'tg-save-test)
;;; tg-save-test.el ends here
