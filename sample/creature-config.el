(hero "一位勇敢的冒险者，被困在了地牢之中" ((hp . 100) (attack . 5) (defense . 3) (exp . 0) (level . 1) (bonus-points . 0)) () () nil 0 nil)
(guard "地牢守卫，身穿破旧的盔甲" ((hp . 40) (attack . 8) (defense . 4)) () () nil 30
  (((player-in-room) say "站住！这里不允许进入！")
   ((always) attack)))
(goblin "一只狡猾的哥布林，手持匕首" ((hp . 25) (attack . 6) (defense . 2)) () () nil 18
  (((hp-below 13) say "你休想活着离开！")
   ((always) attack)))
(bat "一只巨大的蝙蝠，发出刺耳的尖叫" ((hp . 15) (attack . 4) (defense . 1)) () () nil 10
  (((always) attack)))
(skeleton-king "骷髅王，地下城的统治者。它的眼中燃烧着幽蓝色的火焰" ((hp . 80) (attack . 15) (defense . 8)) () () nil 120
  (((hp-below 30) say "蝼蚁！你以为你能赢？")
   ((always) attack)))
(skeleton-minion "骷髅王的仆从，一具行走的骷髅士兵" ((hp . 35) (attack . 9) (defense . 5)) () () nil 25
  (((always) attack)))
(rat "一只肥大的老鼠，警惕地看着你" ((hp . 10) (attack . 2) (defense . 0)) () () nil 5
  (((hp-below 5) move random)))
(prisoner "一个虚弱的囚犯，蜷缩在角落里" ((hp . 20) (attack . 1) (defense . 0)) () () nil 8
  (((player-in-room) say "请救救我...")))
(spider "一只巨大的蜘蛛，从天花板上垂下" ((hp . 20) (attack . 7) (defense . 1)) () () nil 15
  (((always) attack)))
(slime "一团粘稠的绿色史莱姆，缓慢地蠕动着" ((hp . 30) (attack . 3) (defense . 6)) () () nil 20
  (((always) debuff defense 2)))
(golem "一尊石像鬼，守护着武器库的入口" ((hp . 60) (attack . 12) (defense . 10)) () () nil 50
  (((player-in-room) say "擅闯武器库者，杀无赦！")
   ((hp-below 30) buff attack 3)
   ((always) attack)))
(goblin-merchant "一个精明的哥布林商人，推着装满货物的小车" ((hp . 30) (attack . 3) (defense . 2)) () () nil 15
  (((player-in-room) say "来来来，看看我的好东西！"))
  t)
