# v1→v2 文档与 Sample 迁移规格

> **面向 AI 代理的工作者：** 必需子技能：`superpowers:serial-executing-plans`（任务强耦合，共享 sample/ 目录）。

**目标：** 将 README.md、docs/manual.org、sample/ 游戏全部从 v1 格式迁移到 v2 Org-based 架构。

**范围：** 文档/内容迁移 + 1 处 v2 bug 修复（explore/talk 任务追踪缺失）。

---

## 1. 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 创建 | `sample/game.org` | v1 全部配置合并为单个 Org 文件（内容见第 2 节） |
| 创建 | `sample/handlers.el` | 升级表自定义（内容见第 3 节） |
| 重写 | `sample/sample-game.el` | 改用 `tg-start`（内容见第 4 节） |
| 重写 | `sample/play.sh` | 改用 `tg-start`（内容见第 5 节） |
| 重写 | `README.md` | v2 精简概览（大纲见第 6 节） |
| 重写 | `docs/manual.org` | v2 完整手册（大纲见第 7 节） |
| 修改 | `tg-action.el` | 补全 explore/talk 任务追踪（2 行 bug fix） |
| 删除 | `sample/room-config.el` | 被 game.org Rooms 段替代 |
| 删除 | `sample/map-config.el` | 出口信息内嵌到各房间 EXITS 字段 |
| 删除 | `sample/inventory-config.el` | 被 game.org Objects 段替代 |
| 删除 | `sample/creature-config.el` | 被 game.org Creatures 段替代 |
| 删除 | `sample/level-config.el` | 被 handlers.el 替代 |
| 删除 | `sample/quest-config.el` | 被 game.org Quests 段替代 |
| 删除 | `sample/dialog-config.el` | 被 game.org Dialogs 段替代 |
| 删除 | `sample/shop-config.el` | 被 game.org Shops 段替代 |

## 2. sample/game.org 完整内容

```org
#+TITLE: 地牢冒险
#+AUTHOR: DarkSun
#+START: entrance
#+PLAYER: hero

* Rooms

** cell
:PROPERTIES:
:NAME: 阴暗潮湿的牢房
:DESC: 铁栅栏已经锈蚀，角落里堆着一些破烂的稻草。
:SHORT_DESC: 牢房
:EXITS: east=corridor,south=entrance
:CONTENTS: bread,lockpick
:CREATURES: rat,prisoner
:END:

** corridor
:PROPERTIES:
:NAME: 狭窄的走廊
:DESC: 两侧墙壁上的火把忽明忽暗，远处传来奇怪的声响。
:SHORT_DESC: 走廊
:EXITS: west=cell,east=armory,south=hall
:CONTENTS: shield,leather-armor
:CREATURES: spider,slime
:END:

** armory
:PROPERTIES:
:NAME: 废弃的武器库
:DESC: 锈迹斑斑的武器架上还残留着一些可以使用的装备。
:SHORT_DESC: 武器库
:EXITS: west=corridor,south=throne
:CONTENTS: iron-sword,bow,arrow,helmet
:CREATURES: golem
:END:

** entrance
:PROPERTIES:
:NAME: 地牢入口
:DESC: 沉重的石门在你身后缓缓关闭，四周弥漫着腐朽的气息。墙壁上的火把发出微弱的光芒。
:SHORT_DESC: 地牢入口
:EXITS: north=cell,east=hall
:CONTENTS: torch,rusty-key
:CREATURES: guard
:END:

** hall
:PROPERTIES:
:NAME: 宏伟的大厅
:DESC: 破旧的水晶灯从天花板上垂下，地板上布满了裂痕和灰尘。
:SHORT_DESC: 大厅
:EXITS: north=corridor,west=entrance,east=throne
:CONTENTS: map,potion,gold
:CREATURES: goblin,bat,goblin-merchant
:END:

** throne
:PROPERTIES:
:NAME: 王座间
:DESC: 一张腐朽的石制王座矗立在房间尽头，周围的空气中漂浮着诡异的光点。
:SHORT_DESC: 王座间
:EXITS: north=armory,west=hall
:CONTENTS: crown,gem,sword-of-king
:CREATURES: skeleton-king,skeleton-minion
:END:

* Objects

** torch
:PROPERTIES:
:NAME: 燃烧的火把
:SYNONYMS: torch
:PROPS:
:STATE:
:KEY:
:EFFECTS:
:HANDLER:
:END:

** rusty-key
:PROPERTIES:
:NAME: 生锈的钥匙
:SYNONYMS: key,rusty-key
:PROPS:
:STATE:
:KEY:
:EFFECTS:
:HANDLER:
:END:

** map
:PROPERTIES:
:NAME: 残破的地图
:SYNONYMS: map
:PROPS:
:STATE:
:KEY:
:EFFECTS:
:HANDLER:
:END:

** potion
:PROPERTIES:
:NAME: 红色药水
:SYNONYMS: potion
:PROPS: edible
:STATE:
:KEY:
:EFFECTS: (hp 30)
:HANDLER:
:END:

** gold
:PROPERTIES:
:NAME: 一袋金币
:SYNONYMS: gold,coin
:PROPS:
:STATE:
:KEY:
:EFFECTS:
:HANDLER:
:END:

** crown
:PROPERTIES:
:NAME: 古老的王冠
:SYNONYMS: crown
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (attack 3) (defense 2)
:HANDLER:
:END:

** gem
:PROPERTIES:
:NAME: 璀璨的宝石
:SYNONYMS: gem
:PROPS: edible
:STATE:
:KEY:
:EFFECTS: (hp 10) (attack 2)
:HANDLER:
:END:

** sword-of-king
:PROPERTIES:
:NAME: 国王之剑
:SYNONYMS: sword-of-king,king-sword
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (attack 15) (defense 5)
:HANDLER:
:END:

** bread
:PROPERTIES:
:NAME: 干硬的面包
:SYNONYMS: bread
:PROPS: edible
:STATE:
:KEY:
:EFFECTS: (hp 15)
:HANDLER:
:END:

** lockpick
:PROPERTIES:
:NAME: 精巧的开锁工具
:SYNONYMS: lockpick,pick
:PROPS:
:STATE:
:KEY:
:EFFECTS:
:HANDLER:
:END:

** shield
:PROPERTIES:
:NAME: 铁盾
:SYNONYMS: shield
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (defense 5)
:HANDLER:
:END:

** leather-armor
:PROPERTIES:
:NAME: 轻便的皮甲
:SYNONYMS: armor,leather-armor
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (defense 3)
:HANDLER:
:END:

** iron-sword
:PROPERTIES:
:NAME: 铁剑
:SYNONYMS: iron-sword
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (attack 5)
:HANDLER:
:END:

** bow
:PROPERTIES:
:NAME: 短弓
:SYNONYMS: bow
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (attack 4)
:HANDLER:
:END:

** arrow
:PROPERTIES:
:NAME: 箭矢
:SYNONYMS: arrow,arrows
:PROPS: edible
:STATE:
:KEY:
:EFFECTS: (attack 2)
:HANDLER:
:END:

** helmet
:PROPERTIES:
:NAME: 铁头盔
:SYNONYMS: helmet
:PROPS: wearable
:STATE:
:KEY:
:EFFECTS: (defense 2) (hp 5)
:HANDLER:
:END:

* Creatures

** hero
:PROPERTIES:
:NAME: 勇敢的冒险者
:ATTR: hp 100 attack 5 defense 3 exp 0 level 1 bonus-points 0 gold 20
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD:
:BEHAVIORS:
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** guard
:PROPERTIES:
:NAME: 地牢守卫
:ATTR: hp 40 attack 8 defense 4
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 30
:BEHAVIORS: (((player-in-room) say "站住！这里不允许进入！") (always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** goblin
:PROPERTIES:
:NAME: 狡猾的哥布林
:ATTR: hp 25 attack 6 defense 2
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 18
:BEHAVIORS: (((hp-below 13) say "你休想活着离开！") (always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** bat
:PROPERTIES:
:NAME: 巨大的蝙蝠
:ATTR: hp 15 attack 4 defense 1
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 10
:BEHAVIORS: ((always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** skeleton-king
:PROPERTIES:
:NAME: 骷髅王
:ATTR: hp 80 attack 15 defense 8
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 120
:BEHAVIORS: (((hp-below 30) say "蝼蚁！你以为你能赢？") (always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** skeleton-minion
:PROPERTIES:
:NAME: 骷髅士兵
:ATTR: hp 35 attack 9 defense 5
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 25
:BEHAVIORS: ((always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** rat
:PROPERTIES:
:NAME: 肥大的老鼠
:ATTR: hp 10 attack 2 defense 0
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 5
:BEHAVIORS: (((hp-below 5) move random))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** prisoner
:PROPERTIES:
:NAME: 虚弱的囚犯
:ATTR: hp 20 attack 1 defense 0
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 8
:BEHAVIORS: (((player-in-room) say "请救救我..."))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** spider
:PROPERTIES:
:NAME: 巨大的蜘蛛
:ATTR: hp 20 attack 7 defense 1
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 15
:BEHAVIORS: ((always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** slime
:PROPERTIES:
:NAME: 绿色史莱姆
:ATTR: hp 30 attack 3 defense 6
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 20
:BEHAVIORS: ((always debuff defense 2))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** golem
:PROPERTIES:
:NAME: 石像鬼
:ATTR: hp 60 attack 12 defense 10
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 50
:BEHAVIORS: (((player-in-room) say "擅闯武器库者，杀无赦！") ((hp-below 30) buff attack 3) (always attack))
:DEATH_TRIGGER:
:SHOPKEEPER: nil
:HANDLER:
:END:

** goblin-merchant
:PROPERTIES:
:NAME: 哥布林商人
:ATTR: hp 30 attack 3 defense 2
:INVENTORY:
:EQUIPMENT:
:EXP_REWARD: 15
:BEHAVIORS: (((player-in-room) say "来来来，看看我的好东西！"))
:DEATH_TRIGGER:
:SHOPKEEPER: t
:HANDLER:
:END:

* Dialogs

** prisoner
:PROPERTIES:
:NPC_SYMBOL: prisoner
:GREETING: 请救救我...你能帮帮我吗？
:END:
你是谁？ :: 我是被骷髅王关押的探险者。如果你能救我出去，我会报答你的！
有什么线索吗？ :: 听说武器库里有把好剑！从走廊往右就能到。还有...地牢入口的守卫身上可能有钥匙。 → (exp 15)
给你点面包 :: 谢谢你！这个给你，是我在牢房角落找到的。 → (exp 10)

** guard
:PROPERTIES:
:NPC_SYMBOL: guard
:GREETING: 哼，你想干什么？
:END:
你是谁？ :: 我是骷髅王的手下，负责看守地牢入口。
关于骷髅王... :: 骷髅王？他在王座间等着呢。不过你得先通过走廊里的那些怪物才行。 → (exp 10)

** goblin
:PROPERTIES:
:NPC_SYMBOL: goblin
:GREETING: 嘿嘿嘿...你想跟哥布林做什么？
:END:
交出你的宝物！ :: 好吧好吧...拿去！ → (exp 5)

** golem
:PROPERTIES:
:NPC_SYMBOL: golem
:GREETING: ......
:END:
（沉默注视） :: ......你可不像其他入侵者。

* Shops

** merchant-shop
:PROPERTIES:
:NPC_SYMBOL: goblin-merchant
:SELL_RATE: 0.3
:GOODS: bread=10,potion=25,rusty-key=15
:END:

* Quests

** kill-rat
:PROPERTIES:
:TYPE: kill
:TARGET: rat
:COUNT: 1
:REWARDS: (exp 10)
:END:

** talk-prisoner
:PROPERTIES:
:TYPE: talk
:TARGET: prisoner
:COUNT: 1
:REWARDS: (exp 15) (item map)
:END:

** collect-sword
:PROPERTIES:
:TYPE: collect
:TARGET: iron-sword
:COUNT: 1
:REWARDS: (exp 20)
:END:

** kill-goblin
:PROPERTIES:
:TYPE: kill
:TARGET: goblin
:COUNT: 1
:REWARDS: (exp 30)
:END:

** explore-throne
:PROPERTIES:
:TYPE: explore
:TARGET: throne
:COUNT: 1
:REWARDS: (exp 50)
:END:

** defeat-skeleton-king
:PROPERTIES:
:TYPE: kill
:TARGET: skeleton-king
:COUNT: 1
:REWARDS: (exp 200) (bonus-points 5)
:END:
```

### 转换决策说明

**地图→出口映射：** v1 2D 网格 `cell corridor armory / entrance hall throne` 转为方向出口。行 0=北，行 1=南；列 0=西，列 1=中，列 2=东。

**物品 PROPS 映射：**
- v1 `usable`（消耗品：potion, bread, gem, arrow）→ v2 `edible`
- v1 `wearable`（装备：crown, shield 等）→ v2 `wearable`（`effective-attr` 战斗时动态计算加成）
- v1 `usable`（非消耗品：torch, rusty-key, map, gold, lockpick）→ v2 无特殊 PROPS（普通可拾取对象）

**行为格式：** v1 行为规则 `(condition action args...)` 其中 car 为条件、cdr 为动作。v2 规则语义相同，但字符串表示有差异：`((always) attack)`（v1）→ `(always attack)`（v2 单行 Org 属性）。`tg-npc-eval-condition` 的 pcase 同时匹配 `'always`（裸符号）和 `'(always)`（单元素列表），功能兼容。无单元素列表形式的 condition（如 `(hp-below 13)`）两版格式一致。

**对话条件：** v2 解析器不支持条件字段（`condition` 始终 nil）。prisoner 的"给你点面包"选项原需 `(has-item bread)` 条件，迁移后始终可见。

**goblin-merchant 放置：** v1 未放置到任何房间。v2 放入 hall（合理交易地点）。

**v1 shop 的 health-potion：** 不存在于 inventory-config，替换为 `potion`（已注册对象）。

**creature 描述文本：** v2 `tg-creature` struct 只有 `name` 字段无 `desc`。v1 中类似 `"地牢守卫，身穿破旧的盔甲"` 的描述直接丢弃。

**玩家 creature 放置：** 玩家通过 `#+PLAYER` 在 `tg-game` 哈希表中单独追踪（`:player` 键），不放入任何房间的 `creatures` 列表。`tg-npc-run-behaviors` 通过 symbol 比对排除玩家。这避免了 `tg-room-describe` 将玩家显示为房间生物。

**任务无描述/完成文本：** v2 tg-quest struct 无此字段，直接省略。

## 3. sample/handlers.el 完整内容

```elisp
;;; handlers.el --- 地牢冒险自定义配置  -*- lexical-binding: t; -*-

;; 升级表（索引 0 = 等级 1→2 所需累计经验）
(setq tg-level-exp-table '(0 50 120 220 350 500 700 950 1300 1700))
;; 每次升级获得自由属性点
(setq tg-level-bonus-points-per-level 3)
;; 每次升级自动提升的属性
(setq tg-level-auto-upgrade-attrs '((hp 10)))

(provide 'handlers)
;;; handlers.el ends here
```

## 4. sample/sample-game.el 完整内容

```elisp
;;; sample-game.el --- 地牢冒险示例游戏  -*- lexical-binding: t; -*-

;; 使用方法：
;;   M-x eval-buffer 然后 M-x play-sample-game
;;   或 bash sample/play.sh

(require 'tg)

(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((game-file (expand-file-name "game.org"
                                      (file-name-directory (or load-file-name buffer-file-name)))))
    (tg-start game-file)))

(provide 'sample-game)
;;; sample-game.el ends here
```

## 5. sample/play.sh 完整内容

```bash
#!/bin/bash
# 地牢冒险 - Text-Game-Maker 2.0 示例游戏启动脚本
# 用法: bash sample/play.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

emacs --no-init-file -nw --directory "$PROJECT_DIR" \
      --load "$PROJECT_DIR/tg.el" \
      --eval '(tg-start "'"$SCRIPT_DIR"'/game.org")'
```

## 6. README.md 大纲

精简概览，约 80-100 行，7 个章节：

1. **项目名称 + 一句话简介**
2. **特性** — 8-10 条要点（Org 配置、cl-defstruct、27 内置命令、装备动态加成、NPC 行为、对话状态机、商店、任务、存档、可扩展动词）
3. **依赖** — Emacs 27+（org-element、cl-lib）
4. **安装** — `add-to-list 'load-path` + `(require 'tg)`
5. **快速开始** — `M-x tg-start` 或 `bash sample/play.sh`
6. **文件结构** — 18 个 tg-*.el 模块的名称+说明表格
7. **测试** — `emacs -batch -L . -l test/... -f ert-run-tests-batch-and-exit`
8. **TODO** — v2 功能缺口（对话条件解析、Level Org 段、任务描述字段）

## 7. docs/manual.org 大纲

全部重写，8 个主要章节：

1. **简介** — v2 架构概览（Registry 模式 + Org 配置 + handler chain dispatch）
2. **安装与快速开始** — 依赖、load-path、`tg-start`、运行 sample 游戏
3. **核心概念**
   - tg-room（symbol, name, desc, exits, contents, creatures, visit-count）
   - tg-object（symbol, name, synonyms, props, state, key, effects）
   - tg-creature（symbol, name, attr, inventory, equipment, behaviors, shopkeeper）
   - tg-game（哈希表，键：:title, :author, :location, :player, :state, :turns, :active-buffs）
   - tg-dialog-state / tg-dialog-option
4. **Org 配置格式** — 六个 section 逐字段说明
   - 每个字段：字段名、类型、是否必填、默认值、示例
   - 引用完整 sample/game.org 作为示例
5. **游戏命令** — 27 个内置命令表格
   - 列：命令、同义词、说明
   - 按功能分组：移动探索、物品操作、容器、装备消耗、背包、战斗、对话、商店、角色、任务、系统
6. **扩展开发**
   - tg-register-action 注册自定义动词（含示例代码）
   - handlers.el 回调（before-handler, after-handler, death-trigger）
   - tg-message-hook 输出拦截
7. **模块参考** — 18 个模块的公共 API 表格
   - 每模块：文件名、核心 struct、公共函数
8. **已知限制** — 4 条 TODO 项（同 README TODO）

## 8. v2 Bug 修复

在 `tg-action.el` 中补全 `explore`/`talk` 任务追踪：

**tg-action--handler-go**（`tg-action--handler-go` 移动成功后，约第 83 行 `t` 之前）：
```elisp
(tg-track-quest 'explore target-sym)
```

**tg-action--handler-talk**（`tg-action--handler-talk` 对话启动后，约第 464 行 `t` 之前）：
```elisp
(tg-track-quest 'talk do-key)
```

## 9. v2 功能缺口（记入 README TODO）

| 缺口 | 影响 | 所在代码 |
|---|---|---|
| 对话选项条件 | 所有选项始终可见 | `tg-config--parse-dialog-option` 未解析条件字段 |
| Level Org 配置段 | 无 Org 方式设置升级表 | `tg-config-load` 不处理 Level section |
| 任务描述/完成文本 | quests 命令只显示类型和进度 | `tg-quest` struct 无 description/completion 字段 |
| Object 容器/支撑物初始化 | 无法在 Org 中配置容器内初始物品或支撑物上物品 | `tg-config--parse-object-section` 硬编码 `:contents nil :supports nil` |
