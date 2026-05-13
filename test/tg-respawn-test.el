;;; test/tg-respawn-test.el --- tg-respawn 测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-creature)
(require 'tg-respawn)
(require 'tg-commands)                  ;; tg-message for notification mock

(ert-deftest test-tg-respawn-schedule-basic ()
  "测试死亡调度加入队列"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (let ((queue (tg-game-get tg-game :respawn-queue)))
    (should (= (length queue) 1))
    (should (eq (caar queue) 'goblin))
    (should (<= 15 (cdar queue)))  ;; 10 + [5,10]
    (should (>= 20 (cdar queue))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-no-interval ()
  "测试无 interval 时不调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'guard (make-tg-creature :symbol 'guard :name "守卫"
                                                   :attr '((hp 0))  ;; 已死亡
                                                   :respawn-interval nil))
  (tg-respawn-schedule 'guard)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-shopkeeper ()
  "测试 shopkeeper 不调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'merchant (make-tg-creature :symbol 'merchant :name "商人"
                                                      :attr '((hp 0))  ;; 已死亡
                                                      :respawn-interval '(5 . 10)
                                                      :shopkeeper t))
  (tg-respawn-schedule 'merchant)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-dedup ()
  "测试防重复调度"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (tg-respawn-schedule 'goblin)  ;; 第二次应跳过
  (should (= (length (tg-game-get tg-game :respawn-queue)) 1))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-tick-restore ()
  "测试 tick 到达时恢复 creature"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 20)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))  ;; 已死亡
                                                    :inventory nil
                                                    :equipment nil
                                                    :respawn-interval '(5 . 10)
                                                    :initial-attr '((hp 30) (attack 5))
                                                    :initial-inventory '(sword)
                                                    :initial-equipment '(helmet)))
  ;; 手动加入队列，respawn-turn = 15（已过期）
  (tg-game-put tg-game :respawn-queue '((goblin . 15)))
  (tg-respawn-tick)
  ;; 队列应清空
  (should (null (tg-game-get tg-game :respawn-queue)))
  ;; creature 应恢复
  (let ((c (tg-get-creature 'goblin)))
    (should (= (tg-creature-attr-get c 'hp) 30))
    (should (= (tg-creature-attr-get c 'attack) 5))
    (should (equal (tg-creature-inventory c) '(sword)))
    (should (equal (tg-creature-equipment c) '(helmet))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-tick-not-yet ()
  "测试 tick 未到达时不恢复"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :attr '((hp 0))
                                                    :initial-attr '((hp 30))))
  (tg-game-put tg-game :respawn-queue '((goblin . 20)))
  (tg-respawn-tick)
  ;; 队列不变
  (should (equal (tg-game-get tg-game :respawn-queue) '((goblin . 20))))
  ;; creature 仍为死亡
  (should (tg-creature-dead-p (tg-get-creature 'goblin)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-restore-isolation ()
  "测试恢复后的 attr 与 initial-attr 独立"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin
                                                    :attr '((hp 0))
                                                    :initial-attr '((hp 30) (attack 5))))
  (tg-respawn-restore 'goblin)
  (let ((c (tg-get-creature 'goblin)))
    ;; 修改 attr 不影响 initial-attr
    (tg-creature-take-effect c '(hp -10))
    (should (= (tg-creature-attr-get c 'hp) 20))
    (should (= (tg-creature-attr-get c 'attack) 5))
    (should (equal (tg-creature-initial-attr c) '((hp 30) (attack 5)))))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-schedule-alive ()
  "测试活着 creature 的 dead-p 守卫"
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  (tg-game-put tg-game :turns 10)
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin
                                                    :attr '((hp 30))  ;; 还活着
                                                    :respawn-interval '(5 . 10)))
  (tg-respawn-schedule 'goblin)
  (should (null (tg-game-get tg-game :respawn-queue)))
  (tg-registry-clear))

(ert-deftest test-tg-respawn-restore-notification ()
  "测试同房间刷新有通知，异房间无通知"
  (require 'tg-room)
  (tg-registry-clear)
  (setq tg-game (tg-new-game "Test" "Author"))
  ;; 创建房间
  (tg-register-room 'forest (make-tg-room :symbol 'forest :name "森林" :creatures '(goblin)))
  (tg-register-room 'cave (make-tg-room :symbol 'cave :name "洞穴"))
  ;; 创建已死亡 creature
  (tg-register-creature 'goblin (make-tg-creature :symbol 'goblin :name "哥布林"
                                                    :attr '((hp 0))
                                                    :initial-attr '((hp 30))
                                                    :respawn-interval '(5 . 10)))
  ;; Mock tg-message 捕获输出
  (let ((captured-output nil))
    (cl-letf (((symbol-function 'tg-message)
               (lambda (fmt &rest args)
                 (setq captured-output (apply #'format fmt args)))))
      ;; 场景 1：玩家与 creature 同房间 — 应通知
      (tg-game-put tg-game :location 'forest)
      (tg-respawn-restore 'goblin)
      (should captured-output)
      (should (string-match "哥布林" captured-output))
      ;; 重置
      (setq captured-output nil)
      (setf (tg-creature-attr (tg-get-creature 'goblin)) '((hp 0)))
      ;; 场景 2：玩家在另一个房间 — 不通知
      (tg-game-put tg-game :location 'cave)
      (tg-respawn-restore 'goblin)
      (should (null captured-output))))
  (tg-registry-clear))

(provide 'tg-respawn-test)
