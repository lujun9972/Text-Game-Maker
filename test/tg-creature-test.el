;;; test/tg-creature-test.el --- tg-creature 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)

(ert-deftest test-tg-creature-create ()
  "测试生物创建"
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30) (attack 5) (defense 2))
                    :inventory '(sword potion)
                    :equipment '(sword)
                    :exp-reward 10
                    :behaviors '(aggressive)
                    :death-trigger 'goblin-death
                    :shopkeeper nil
                    :handler 'goblin-handler)))
    (should (eq (tg-creature-symbol creature) 'goblin))
    (should (equal (tg-creature-name creature) "哥布林"))
    (should (equal (tg-creature-attr creature) '((hp 30) (attack 5) (defense 2))))
    (should (equal (tg-creature-inventory creature) '(sword potion)))
    (should (equal (tg-creature-equipment creature) '(sword)))
    (should (eq (tg-creature-exp-reward creature) 10))
    (should (equal (tg-creature-behaviors creature) '(aggressive)))
    (should (eq (tg-creature-death-trigger creature) 'goblin-death))
    (should (not (tg-creature-shopkeeper creature)))
    (should (eq (tg-creature-handler creature) 'goblin-handler))))

(ert-deftest test-tg-creature-attr-get ()
  "测试属性获取"
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30) (attack 5) (defense 2)))))
    (should (= (tg-creature-attr-get creature 'hp) 30))
    (should (= (tg-creature-attr-get creature 'attack) 5))
    (should (= (tg-creature-attr-get creature 'defense) 2))
    ;; 不存在的属性返回 nil
    (should (not (tg-creature-attr-get creature 'speed)))))

(ert-deftest test-tg-creature-dead-p ()
  "测试死亡判定"
  (let ((alive (make-tg-creature
                :symbol 'goblin
                :name "活着的哥布林"
                :attr '((hp 30))))
        (dead (make-tg-creature
               :symbol 'goblin
               :name "死去的哥布林"
               :attr '((hp 0))))
        (negative (make-tg-creature
                   :symbol 'goblin
                   :name "负血量哥布林"
                   :attr '((hp -5)))))
    (should (not (tg-creature-dead-p alive)))
    (should (tg-creature-dead-p dead))
    (should (tg-creature-dead-p negative))))

(ert-deftest test-tg-creature-take-effect ()
  "测试效果应用"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100) (attack 10))))
         (original-hp (tg-creature-attr-get creature 'hp)))
    ;; 修改现有属性
    (tg-creature-take-effect creature '(hp -20))
    (should (= (tg-creature-attr-get creature 'hp) 80))

    ;; 添加新属性
    (tg-creature-take-effect creature '(defense 5))
    (should (= (tg-creature-attr-get creature 'defense) 5))

    ;; HP 不低于 0
    (tg-creature-take-effect creature '(hp -100))
    (should (= (tg-creature-attr-get creature 'hp) 0))

    ;; 多次叠加同一属性
    (tg-creature-take-effect creature '(attack 3))
    (should (= (tg-creature-attr-get creature 'attack) 13))))

(ert-deftest test-tg-creature-add-item ()
  "测试添加物品"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :inventory '(sword))))
    (tg-creature-add-item creature 'potion)
    (should (member 'potion (tg-creature-inventory creature)))
    (should (member 'sword (tg-creature-inventory creature)))))

(ert-deftest test-tg-creature-remove-item ()
  "测试移除物品"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :inventory '(sword potion shield))))
    (tg-creature-remove-item creature 'potion)
    (should (member 'sword (tg-creature-inventory creature)))
    (should (member 'shield (tg-creature-inventory creature)))
    (should (not (member 'potion (tg-creature-inventory creature))))))

(ert-deftest test-tg-creature-has-item ()
  "测试物品存在性检查"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :inventory '(sword potion))))
    (should (tg-creature-has-item creature 'sword))
    (should (tg-creature-has-item creature 'potion))
    (should (not (tg-creature-has-item creature 'shield)))))

(ert-deftest test-tg-creature-effective-attr-basic ()
  "测试基础属性计算（无装备无buff）"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100) (attack 10))
                    :equipment '())))
    (should (= (tg-creature-effective-attr creature 'hp nil) 100))
    (should (= (tg-creature-effective-attr creature 'attack nil) 10))))

(ert-deftest test-tg-creature-effective-attr-with-equipment ()
  "测试装备效果叠加"
  (tg-registry-clear)
  (let* ((sword (make-tg-object :symbol 'sword
                                :name "铁剑"
                                :props '(wearable)
                                :effects '((attack 5))))
         (shield (make-tg-object :symbol 'shield
                                 :name "盾牌"
                                 :props '(wearable)
                                 :effects '((defense 3))))
         (creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100) (attack 10) (defense 0))
                    :equipment '(sword shield))))
    (tg-register-object 'sword sword)
    (tg-register-object 'shield shield)
    (should (= (tg-creature-effective-attr creature 'attack nil) 15)) ; 10 + 5
    (should (= (tg-creature-effective-attr creature 'defense nil) 3))  ; 0 + 3
    (should (= (tg-creature-effective-attr creature 'hp nil) 100))))    ; 无装备加成

(ert-deftest test-tg-creature-effective-attr-with-buffs ()
  "测试buff 叠加"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100) (attack 10))
                    :equipment '()))
         (buffs '((attack 3) (defense 5))))
    (should (= (tg-creature-effective-attr creature 'attack buffs) 13)) ; 10 + 3
    (should (= (tg-creature-effective-attr creature 'defense buffs) 5))   ; 0 + 5
    (should (= (tg-creature-effective-attr creature 'hp buffs) 100))))    ; 无buff加成

(ert-deftest test-tg-creature-effective-attr-combined ()
  "测试装备 + buff 组合叠加"
  (tg-registry-clear)
  (let* ((sword (make-tg-object :symbol 'sword
                                :name "铁剑"
                                :props '(wearable)
                                :effects '((attack 5))))
         (creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100) (attack 10) (defense 0))
                    :equipment '(sword)))
         (buffs '((attack 3) (defense 2))))
    (tg-register-object 'sword sword)
    (should (= (tg-creature-effective-attr creature 'attack buffs) 18)) ; 10 + 5 + 3
    (should (= (tg-creature-effective-attr creature 'defense buffs) 2))   ; 0 + 0 + 2
    (should (= (tg-creature-effective-attr creature 'hp buffs) 100))))    ; 100 + 0 + 0

(ert-deftest test-tg-creature-effective-attr-unknown-attr ()
  "测试未知属性返回0"
  (let* ((creature (make-tg-creature
                    :symbol 'hero
                    :name "英雄"
                    :attr '((hp 100))
                    :equipment '())))
    (should (= (tg-creature-effective-attr creature 'speed nil) 0))
    (should (= (tg-creature-effective-attr creature 'magic nil) 0))))

(ert-deftest test-tg-creature-respawn-fields ()
  "测试刷新相关字段"
  (let ((c (make-tg-creature :symbol 'goblin :name "哥布林"
                              :attr '((hp 30) (attack 5))
                              :inventory '(sword)
                              :equipment '(helmet)
                              :respawn-interval '(8 . 15)
                              :initial-attr '((hp 30) (attack 5))
                              :initial-inventory '(sword)
                              :initial-equipment '(helmet))))
    (should (equal (tg-creature-respawn-interval c) '(8 . 15)))
    (should (equal (tg-creature-initial-attr c) '((hp 30) (attack 5))))
    (should (equal (tg-creature-initial-inventory c) '(sword)))
    (should (equal (tg-creature-initial-equipment c) '(helmet)))
    ;; 不刷新生物这些字段为 nil
    (let ((c2 (make-tg-creature :symbol 'guard)))
      (should (null (tg-creature-respawn-interval c2)))
      (should (null (tg-creature-initial-attr c2))))))

(provide 'tg-creature-test)
;;; tg-creature-test.el ends here
