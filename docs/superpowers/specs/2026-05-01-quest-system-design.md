# 任务系统设计

## 目标

为 Text-Game-Maker 添加任务系统，支持击杀、收集/交付、探索、对话四种任务类型，通过配置文件预定义任务，游戏过程中自动追踪进度和完成检测。

## 现有架构

游戏已有完整的 action 系统（`tg-attack`, `tg-take`, `tg-move`, `tg-watch` 等），通过 `tg-defaction` 宏定义。NPC 行为系统已集成到游戏循环中。

关键集成点：
- `tg-attack` 击败目标后 → 可追踪击杀任务
- `tg-take` 捡起物品后 → 可追踪收集任务
- `tg-move` 进入房间后 → 可追踪探索任务
- `tg-watch` 查看 NPC 后 → 可追踪对话任务

`add-exp-to-creature` 已有经验值发放和升级逻辑。`add-inventory-to-creature` 可添加物品到玩家。

## 设计

### 1. Quest 结构体

```elisp
(cl-defstruct Quest
  (symbol nil :documentation "任务唯一标识符")
  (description "" :documentation "任务描述")
  (type nil :documentation "任务类型: kill/collect/explore/talk")
  (target nil :documentation "任务目标 symbol")
  (count 1 :documentation "目标数量")
  (progress 0 :documentation "当前进度")
  (rewards nil :documentation "奖励列表: ((exp . N) (item . symbol) (bonus-points . N) (trigger . lambda))")
  (status 'inactive :documentation "任务状态: inactive/active/completed/failed")
  (description-complete "" :documentation "完成时的提示文本"))
```

### 2. 任务类型

| 类型 | type 值 | 触发动作 | target 含义 |
|------|---------|----------|-------------|
| 击杀 | `kill` | `tg-attack` 击败目标 | 怪物 symbol |
| 收集 | `collect` | `tg-take` 捡起物品 | 物品 symbol |
| 探索 | `explore` | `tg-move` 进入房间 | 房间 symbol |
| 对话 | `talk` | `tg-watch` 查看 NPC | NPC symbol |

### 3. 配置文件格式

`quest-config.el`，每行一个任务：

```elisp
(<symbol> "<描述>" <type> <target> <count> ((reward-key . value)...) <status> "<完成提示>")
```

示例：

```elisp
(kill-goblin "击败3只哥布林" kill goblin 3 ((exp . 30)) inactive "你消灭了哥布林群！")
(find-key "找到魔法钥匙" collect magic-key 1 ((exp . 20) (item . treasure)) inactive "你找到了魔法钥匙！")
(reach-throne "到达王座" explore throne-room 1 ((exp . 100) (trigger . (lambda () (tg-display "王座之门打开了！")))) inactive "你到达了王座！")
(talk-prisoner "与囚犯对话" talk prisoner 1 ((exp . 15) (item . map)) inactive "囚犯给了你一张地图！")
```

### 4. 奖励类型

| 奖励 key | 值类型 | 说明 |
|----------|--------|------|
| `exp` | 整数 | 通过 `add-exp-to-creature` 发放经验值 |
| `item` | symbol | 通过 `add-inventory-to-creature` 添加物品到玩家 |
| `bonus-points` | 整数 | 直接增加玩家 `bonus-points` 属性 |
| `trigger` | lambda | 任务完成时调用的回调函数 |

多个奖励可以共存于同一个任务的 rewards 列表中。

### 5. 核心函数

新增模块 `quest-system.el`：

| 函数 | 说明 |
|------|------|
| `quest-init (config-file)` | 从配置文件加载所有任务 |
| `quest-track-kill (target-symbol)` | 追踪击杀任务进度 |
| `quest-track-collect (item-symbol)` | 追踪收集任务进度 |
| `quest-track-explore (room-symbol)` | 追踪探索任务进度 |
| `quest-track-talk (npc-symbol)` | 追踪对话任务进度 |
| `quest-apply-rewards (quest)` | 发放任务奖励 |
| `quest-update-progress (quest)` | 更新进度并检测完成 |
| `quest-list-active` | 列出所有活跃任务 |
| `quest-list-all` | 列出所有任务 |

全局变量：
- `quests-alist` — symbol 到 Quest 对象的映射

### 6. 新增游戏命令

| 命令 | 函数 | 说明 |
|------|------|------|
| `quests` | `tg-quests` | 显示所有活跃任务的进度 |
| `quest <名称>` | `tg-quest` | 显示指定任务的详情 |

`quests` 输出示例：
```
=== 任务列表 ===
[进行中] 击败3只哥布林 (1/3)
[进行中] 找到魔法钥匙 (0/1)
[未开始] 到达王座
```

### 7. 追踪集成

在现有 action 函数中添加追踪调用：

| 文件 | 函数 | 添加的调用 |
|------|------|-----------|
| `action.el` | `tg-attack` | 击败目标后 `(quest-track-kill target)` |
| `action.el` | `tg-take` | 捡起物品后 `(quest-track-collect inventory)` |
| `action.el` | `tg-move` | 进入房间后 `(quest-track-explore new-room-symbol)` |
| `action.el` | `tg-watch` | 查看 NPC 后 `(quest-track-talk symbol)` |

### 8. 进度更新与完成检测

```elisp
(defun quest-update-progress (quest)
  "Update quest progress and check completion."
  (cl-incf (Quest-progress quest))
  (when (>= (Quest-progress quest) (Quest-count quest))
    (setf (Quest-status quest) 'completed)
    (tg-display (format "任务完成：%s" (Quest-description quest)))
    (when (Quest-description-complete quest)
      (tg-display (Quest-description-complete quest)))
    (quest-apply-rewards quest)))
```

### 9. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `quest-system.el` | 新建模块 |
| `action.el` | 在 tg-attack/tg-take/tg-move/tg-watch 中添加追踪调用 |
| `action.el` | 新增 tg-quests 和 tg-quest action |
| `text-game-maker.el` | `(require 'quest-system)` |
| `sample/quest-config.el` | 新建示例任务配置 |
| `sample/sample-game.el` | 调用 `quest-init`，添加任务提示 |

### 10. 边界情况

- 只有 `active` 状态的任务会被追踪
- 奖励只发放一次（status 变为 completed 后不再触发）
- `count` 默认为 1
- 任务 rewards 中 `item` 奖励通过 `add-inventory-to-creature` 添加到 myself
- 任务 rewards 中 `exp` 奖励通过 `add-exp-to-creature` 发放（可触发升级）
- 任务 rewards 中 `bonus-points` 通过 `take-effect-to-creature` 增加
- 任务 rewards 中 `trigger` 是 lambda 函数，完成时调用
- `inactive` 任务不追踪，但通过 `quests` 命令可见
- 配置文件中的 status 初始值一般为 `inactive`，游戏可通过 `quest-activate` 或其他机制激活（初始版本中所有任务默认 active）

### 11. 初始版本简化

为降低初始实现复杂度：
- 所有任务加载后自动标记为 `active`（忽略配置中的 status 字段）
- 不实现任务激活/关闭的显式机制
- 不实现任务失败（`failed` 状态）
- 不实现任务链（前置任务完成才解锁下一个）

这些功能可在后续版本中添加。

### 12. 测试覆盖

- `quest-init` — 从临时文件加载任务配置
- `quest-track-kill` — 击杀任务进度更新
- `quest-track-collect` — 收集任务进度更新
- `quest-track-explore` — 探索任务进度更新
- `quest-track-talk` — 对话任务进度更新
- 任务完成检测 — progress 达到 count 时自动完成
- 任务奖励发放 — exp/item/bonus-points/trigger
- 多次击杀累积进度
- 已完成任务不再追踪
- `tg-quests` — 显示任务列表
- 集成测试 — tg-attack 触发击杀任务完成
