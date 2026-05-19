;;; tg-level-test.el --- 经验等级系统测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'tg-registry)
(require 'tg-creature)

(ert-deftest test-tg-level-check-level-up ()
  "测试经验足够时自动升级"
  (tg-registry-clear)
  (let* ((tg-level-exp-table '(0 100 250 500))
         (tg-level-bonus-points-per-level 3)
         (tg-level-auto-upgrade-attrs '((hp 5)))
         (player (make-tg-creature :symbol 'hero
                                   :attr '((hp 50) (attack 5) (exp 150) (level 1) (bonus-points 0)))))
    (tg-register-creature 'hero player)
    (tg-level-check player)
    (should (= (tg-creature-attr-get player 'level) 2))
    (should (= (tg-creature-attr-get player 'hp) 55))
    (should (= (tg-creature-attr-get player 'bonus-points) 3))))

(ert-deftest test-tg-level-no-level-up ()
  "测试经验不足时不升级"
  (let ((tg-level-exp-table '(0 100 250))
        (tg-level-bonus-points-per-level 3)
        (tg-level-auto-upgrade-attrs '((hp 5)))
        (player (make-tg-creature :symbol 'hero
                                  :attr '((hp 50) (exp 50) (level 1) (bonus-points 0)))))
    (tg-level-check player)
    (should (= (tg-creature-attr-get player 'level) 1))
    (should (= (tg-creature-attr-get player 'hp) 50))
    (should (= (tg-creature-attr-get player 'bonus-points) 0))))

(ert-deftest test-tg-level-multiple-level-ups ()
  "测试经验足够时连续升级"
  (tg-registry-clear)
  (let* ((tg-level-exp-table '(0 100 250))
         (tg-level-bonus-points-per-level 3)
         (tg-level-auto-upgrade-attrs '((hp 5)))
         (player (make-tg-creature :symbol 'hero
                                   :attr '((hp 50) (exp 300) (level 1) (bonus-points 0)))))
    (tg-register-creature 'hero player)
    (tg-level-check player)
    (should (= (tg-creature-attr-get player 'level) 3))
    (should (= (tg-creature-attr-get player 'hp) 60))  ; 50 + 5 + 5
    (should (= (tg-creature-attr-get player 'bonus-points) 6))))  ; 3 + 3

(ert-deftest test-tg-level-upgrade-success ()
  "测试手动升级成功"
  (let ((player (make-tg-creature :symbol 'hero
                                  :attr '((hp 50) (attack 5) (bonus-points 10)))))
    (should (tg-level-upgrade player 'attack 3))
    (should (= (tg-creature-attr-get player 'attack) 8))
    (should (= (tg-creature-attr-get player 'bonus-points) 7))))

(ert-deftest test-tg-level-upgrade-insufficient-points ()
  "测试手动升级失败（点数不足）"
  (let ((player (make-tg-creature :symbol 'hero
                                  :attr '((hp 50) (attack 5) (bonus-points 2)))))
    (should (not (tg-level-upgrade player 'attack 5)))
    (should (= (tg-creature-attr-get player 'attack) 5))
    (should (= (tg-creature-attr-get player 'bonus-points) 2))))

(ert-deftest test-tg-level-upgrade-new-attr ()
  "测试手动升级新属性"
  (let ((player (make-tg-creature :symbol 'hero
                                  :attr '((hp 50) (bonus-points 5)))))
    (should (tg-level-upgrade player 'defense 3))
    (should (= (tg-creature-attr-get player 'defense) 3))
    (should (= (tg-creature-attr-get player 'bonus-points) 2))))

(provide 'tg-level-test)
;;; tg-level-test.el ends here
