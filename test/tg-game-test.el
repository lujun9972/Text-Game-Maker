;;; tg-game-test.el --- tg-game 测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'tg-game)

(ert-deftest test-tg-new-game ()
  (let ((g (tg-new-game "测试" "作者")))
    (should (equal (tg-game-get g :title) "测试"))
    (should (equal (tg-game-get g :author) "作者"))
    (should (eq (tg-game-get g :state) 'starting))
    (should (= (tg-game-get g :turns) 0))
    (should (null (tg-game-get g :location)))
    (should (null (tg-game-get g :active-buffs)))))

(ert-deftest test-tg-game-incf ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-incf g :turns)
    (should (= (tg-game-get g :turns) 1))
    ;; 测试连续递增
    (tg-game-incf g :turns)
    (tg-game-incf g :turns)
    (should (= (tg-game-get g :turns) 3))))

(ert-deftest test-tg-buffs-apply-permanent ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :player 'test-player)
    (tg-register-creature 'test-player
      (make-tg-creature :symbol 'test-player :attr '((hp 50))))
    (tg-buffs-apply g '((hp 20)))
    (should (= (tg-creature-attr-get (tg-get-creature 'test-player) 'hp) 70))
    ;; 清理
    (tg-registry-clear)))

(ert-deftest test-tg-buffs-apply-temporary ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :player 'test-player)
    (tg-register-creature 'test-player
      (make-tg-creature :symbol 'test-player :attr '((hp 50))))
    (tg-buffs-apply g '((attack 5 :duration 3)))
    (let ((buffs (tg-game-get g :active-buffs)))
      (should (= (length buffs) 1))
      (should (eq (caar buffs) 'attack))
      (should (= (plist-get (cdar buffs) :delta) 5))
      (should (= (plist-get (cdar buffs) :remaining) 3))
      (should (= (plist-get (cdar buffs) :duration) 3)))
    ;; 清理
    (tg-registry-clear)))

(ert-deftest test-tg-buffs-tick ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :active-buffs
                 '((attack :delta 3 :remaining 2 :duration 2)
                   (hp :delta 20 :remaining 0 :duration 1)))
    (tg-buffs-tick g)
    (let ((buffs (tg-game-get g :active-buffs)))
      (should (= (length buffs) 1))
      (should (eq (caar buffs) 'attack))
      (should (= (plist-get (cdar buffs) :remaining) 1)))))

(ert-deftest test-tg-buffs-tick-remove-expired ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :active-buffs
                 '((attack :delta 3 :remaining 1 :duration 2)))
    (tg-buffs-tick g)
    ;; tick 后 remaining 变为 0，但还没被移除
    (let ((buffs (tg-game-get g :active-buffs)))
      (should (= (length buffs) 1))
      (should (= (plist-get (cdar buffs) :remaining) 0)))
    ;; 再 tick 一次，remaining 变为 -1，被移除
    (tg-buffs-tick g)
    (let ((buffs (tg-game-get g :active-buffs)))
      (should (null buffs)))))

(ert-deftest test-tg-buffs-apply-mixed ()
  (let ((g (tg-new-game "T" nil)))
    (tg-game-put g :player 'test-player)
    (tg-register-creature 'test-player
      (make-tg-creature :symbol 'test-player :attr '((hp 50) (attack 10))))
    ;; 混合应用永久和临时效果
    (tg-buffs-apply g '((hp 20) (attack 5 :duration 2)))
    ;; 检查永久效果已应用
    (should (= (tg-creature-attr-get (tg-get-creature 'test-player) 'hp) 70))
    (should (= (tg-creature-attr-get (tg-get-creature 'test-player) 'attack) 10)) ; attack 不变
    ;; 检查临时效果已记录
    (let ((buffs (tg-game-get g :active-buffs)))
      (should (= (length buffs) 1))
      (should (eq (caar buffs) 'attack)))
    ;; 清理
    (tg-registry-clear)))

(ert-deftest test-tg-player ()
  (let ((g (tg-new-game "T" nil)))
    (should (null (tg-player g)))
    (tg-game-put g :player 'test-player)
    (tg-register-creature 'test-player
      (make-tg-creature :symbol 'test-player :name "Test Player"))
    (let ((player (tg-player g)))
      (should (tg-creature-p player))
      (should (eq (tg-creature-symbol player) 'test-player))
      (should (equal (tg-creature-name player) "Test Player")))
    ;; 清理
    (tg-registry-clear)))

(provide 'tg-game-test)
;;; tg-game-test.el ends here
