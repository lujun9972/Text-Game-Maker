;;; test/tg-npc-test.el --- tg-npc 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-room)
(require 'tg-creature)
(require 'tg-game)
(require 'tg-npc)

;;; Condition 求值测试

(ert-deftest test-tg-npc-eval-condition-always ()
  "测试 always 条件永远为真"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits '((north . garden))
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (should (tg-npc-eval-condition creature 'always))))

(ert-deftest test-tg-npc-eval-condition-hp-below ()
  "测试 hp-below 条件"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (should (tg-npc-eval-condition creature '(hp-below 20)))
    (should (tg-npc-eval-condition creature '(hp-below 16)))
    (should (not (tg-npc-eval-condition creature '(hp-below 15))))
    (should (not (tg-npc-eval-condition creature '(hp-below 10))))))

(ert-deftest test-tg-npc-eval-condition-hp-above ()
  "测试 hp-above 条件"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (should (tg-npc-eval-condition creature '(hp-above 10)))
    (should (tg-npc-eval-condition creature '(hp-above 14)))
    (should (not (tg-npc-eval-condition creature '(hp-above 15))))
    (should (not (tg-npc-eval-condition creature '(hp-above 20))))))

(ert-deftest test-tg-npc-eval-condition-player-in-room ()
  "测试 player-in-room 条件"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))))
         (creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30))))
         (courtyard (make-tg-room
                     :symbol 'courtyard
                     :name "庭院"
                     :desc "一个庭院"
                     :exits '((north . garden))
                     :creatures '(goblin)))
         (garden (make-tg-room
                  :symbol 'garden
                  :name "花园"
                  :desc "一个花园"
                  :exits '((south . courtyard))
                  :creatures nil))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard courtyard)
    (tg-register-room 'garden garden)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    ;; 玩家在庭院，哥布林也在庭院
    (should (tg-npc-eval-condition creature '(player-in-room)))
    ;; 玩家移动到花园
    (tg-game-put game :location 'garden)
    (should (not (tg-npc-eval-condition creature '(player-in-room))))))

(ert-deftest test-tg-npc-eval-condition-and ()
  "测试 and 逻辑组合"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    ;; 两个条件都满足
    (should (tg-npc-eval-condition creature '(and (hp-below 20) (hp-above 10))))
    ;; 只有一个满足
    (should (not (tg-npc-eval-condition creature '(and (hp-below 20) (hp-above 20)))))
    ;; 都不满足
    (should (not (tg-npc-eval-condition creature '(and (hp-below 10) (hp-above 20)))))))

(ert-deftest test-tg-npc-eval-condition-or ()
  "测试 or 逻辑组合"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    ;; 两个条件都满足
    (should (tg-npc-eval-condition creature '(or (hp-below 20) (hp-above 20))))
    ;; 只有一个满足
    (should (tg-npc-eval-condition creature '(or (hp-below 20) (hp-above 10))))
    ;; 都不满足
    (should (not (tg-npc-eval-condition creature '(or (hp-below 10) (hp-above 20)))))))

(ert-deftest test-tg-npc-eval-condition-not ()
  "测试 not 逻辑组合"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (should (tg-npc-eval-condition creature '(not (hp-below 10))))
    (should (not (tg-npc-eval-condition creature '(not (hp-below 20)))))))

;;; Action 执行测试

(ert-deftest test-tg-npc-execute-action-attack ()
  "测试 attack 动作"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (defense 5))))
         (creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30) (attack 10))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-execute-action creature '(attack))))
      ;; 伤害 = 10 - 5 = 5
      (should (= (tg-creature-attr-get (tg-player game) 'hp) 95))
      (should (stringp output)))))

(ert-deftest test-tg-npc-execute-action-say ()
  "测试 say 动作"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-execute-action creature '(say "你好，英雄！"))))
      (should (stringp output))
      (should (string-match-p "你好，英雄！" output)))))

(ert-deftest test-tg-npc-execute-action-move ()
  "测试 move 动作"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30))))
         (courtyard (make-tg-room
                     :symbol 'courtyard
                     :name "庭院"
                     :desc "一个庭院"
                     :exits '((north . garden))
                     :creatures '(goblin)))
         (garden (make-tg-room
                  :symbol 'garden
                  :name "花园"
                  :desc "一个花园"
                  :exits '((south . courtyard))
                  :creatures nil))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard courtyard)
    (tg-register-room 'garden garden)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (tg-npc-execute-action creature '(move north))
    ;; 哥布林应该从庭院移动到花园
    (should (not (memq 'goblin (tg-room-creatures courtyard))))
    (should (memq 'goblin (tg-room-creatures garden)))))

(ert-deftest test-tg-npc-execute-action-buff ()
  "测试 buff 动作（增加自身属性）"
  (tg-registry-clear)
  (let* ((creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30) (attack 10))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (tg-npc-execute-action creature '(buff attack 5))
    (should (= (tg-creature-attr-get creature 'attack) 15))
    (tg-npc-execute-action creature '(buff defense 3))
    (should (= (tg-creature-attr-get creature 'defense) 3))))

(ert-deftest test-tg-npc-execute-action-debuff ()
  "测试 debuff 动作（减少玩家属性）"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100) (attack 20))))
         (creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 30))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (tg-npc-execute-action creature '(debuff attack 5))
    (should (= (tg-creature-attr-get (tg-player game) 'attack) 15))
    (tg-npc-execute-action creature '(debuff defense 2))
    (should (= (tg-creature-attr-get (tg-player game) 'defense) -2))))

;;; 运行行为测试

(ert-deftest test-tg-npc-run-behaviors-single-npc ()
  "测试单个 NPC 行为执行"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))))
         (creature (make-tg-creature
                    :symbol 'goblin
                    :name "哥布林"
                    :attr '((hp 15) (attack 10))
                    :behaviors (list (cons '(hp-below 20) '(say "我受伤了！"))
                                     (cons '(always) '(say "你好")))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin creature)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-run-behaviors game)))
      ;; 应该匹配第一条规则（hp < 20）
      (should (stringp output))
      (when output
        (should (string-match-p "我受伤了！" output))))))

(ert-deftest test-tg-npc-run-behaviors-multiple-npcs ()
  "测试多个 NPC 行为执行"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))))
         (goblin1 (make-tg-creature
                   :symbol 'goblin1
                   :name "哥布林1"
                   :attr '((hp 15) (attack 10))
                   :behaviors (list (cons '(hp-below 20) '(say "哥布林1受伤了")))))
         (goblin2 (make-tg-creature
                   :symbol 'goblin2
                   :name "哥布林2"
                   :attr '((hp 25) (attack 8))
                   :behaviors (list (cons '(hp-above 20) '(say "哥布林2很健康")))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero goblin1 goblin2)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin1 goblin1)
    (tg-register-creature 'goblin2 goblin2)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-run-behaviors game)))
      ;; 两个 NPC 都应该执行
      (should (stringp output))
      (when output
        (should (string-match-p "哥布林1受伤了" output))
        (should (string-match-p "哥布林2很健康" output))))))

(ert-deftest test-tg-npc-run-behaviors-dead-npc-skipped ()
  "测试死亡 NPC 不执行行为"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))))
         (dead-goblin (make-tg-creature
                       :symbol 'dead-goblin
                       :name "死去的哥布林"
                       :attr '((hp 0))
                       :behaviors (list (cons '(always) '(say "我不应该说话")))))
         (alive-goblin (make-tg-creature
                        :symbol 'alive-goblin
                        :name "活着的哥布林"
                        :attr '((hp 30))
                        :behaviors (list (cons '(always) '(say "我还活着")))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero dead-goblin alive-goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'dead-goblin dead-goblin)
    (tg-register-creature 'alive-goblin alive-goblin)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-run-behaviors game)))
      (should (stringp output))
      (when output
        (should (string-match-p "我还活着" output))
        (should (not (string-match-p "我不应该说话" output)))))))

(ert-deftest test-tg-npc-run-behaviors-player-excluded ()
  "测试玩家被排除在行为执行之外"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))
                  :behaviors (list (cons '(always) '(say "我是玩家")))))
         (goblin (make-tg-creature
                  :symbol 'goblin
                  :name "哥布林"
                  :attr '((hp 30))
                  :behaviors (list (cons '(always) '(say "我是哥布林")))))
         (room (make-tg-room
                :symbol 'courtyard
                :name "庭院"
                :desc "一个庭院"
                :exits nil
                :creatures '(hero goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'goblin goblin)
    (tg-register-room 'courtyard room)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-run-behaviors game)))
      (should (stringp output))
      (when output
        (should (string-match-p "我是哥布林" output))
        (should (not (string-match-p "我是玩家" output)))))))

(ert-deftest test-tg-npc-run-behaviors-only-current-room ()
  "测试只执行当前房间的 NPC 行为"
  (tg-registry-clear)
  (let* ((player (make-tg-creature
                  :symbol 'hero
                  :name "英雄"
                  :attr '((hp 100))))
         (courtyard-goblin (make-tg-creature
                            :symbol 'courtyard-goblin
                            :name "庭院哥布林"
                            :attr '((hp 30))
                            :behaviors (list (cons '(always) '(say "我在庭院")))))
         (garden-goblin (make-tg-creature
                         :symbol 'garden-goblin
                         :name "花园哥布林"
                         :attr '((hp 30))
                         :behaviors (list (cons '(always) '(say "我在花园")))))
         (courtyard (make-tg-room
                     :symbol 'courtyard
                     :name "庭院"
                     :desc "一个庭院"
                     :exits '((north . garden))
                     :creatures '(hero courtyard-goblin)))
         (garden (make-tg-room
                  :symbol 'garden
                  :name "花园"
                  :desc "一个花园"
                  :exits '((south . courtyard))
                  :creatures '(garden-goblin)))
         (game (tg-new-game "测试" "测试作者")))
    (tg-register-creature 'hero player)
    (tg-register-creature 'courtyard-goblin courtyard-goblin)
    (tg-register-creature 'garden-goblin garden-goblin)
    (tg-register-room 'courtyard courtyard)
    (tg-register-room 'garden garden)
    (tg-game-put game :player 'hero)
    (tg-game-put game :location 'courtyard)
    (setq tg-game game)
    (let ((output (tg-npc-run-behaviors game)))
      (should (stringp output))
      (when output
        (should (string-match-p "我在庭院" output))
        (should (not (string-match-p "我在花园" output)))))))

(provide 'tg-npc-test)
;;; test/tg-npc-test.el ends here
