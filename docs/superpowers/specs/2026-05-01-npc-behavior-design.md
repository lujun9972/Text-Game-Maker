# NPC 主动行为系统设计

## 目标

为 Text-Game-Maker 添加 NPC 主动行为系统，使 NPC 不再只是被动接受动作，而是能根据条件主动攻击、移动、对话和施放状态效果。

## 现有架构

当前 NPC（Creature）的行为完全被动：
- 唯一"主动"行为是 `tg-attack` 中硬编码的反击逻辑（写在玩家攻击流程内）
- 触发器系统（`in-trigger`, `watch-trigger`, `death-trigger` 等）是回调式的，需要玩家先执行动作
- NPC 没有自己的"回合"概念

Creature 的 `attr` 是 alist，如 `((hp . 100) (attack . 5) (defense . 3))`。`take-effect-to-creature` 可增减属性值。Room 的 `creature` slot 存储当前房间内的 NPC symbol 列表。

## 设计

### 1. 数据模型：behaviors slot

Creature struct 新增 `behaviors` slot：

```elisp
(behaviors nil :documentation "NPC主动行为规则列表")
```

`behaviors` 是规则列表，每条规则形如 `(条件表达式 . 动作)`。配置文件中为 Creature 新增第 8 个字段。

示例：

```elisp
(goblin "哥布林" ((hp . 25) (attack . 6) (defense . 2)) () () nil 18
  (((always) attack)
   ((hp-below 13) say "你休想活着离开！")
   ((and (player-in-room) (hp-below 8)) move random)))
```

没有 behaviors 的 NPC（`nil`）不会主动行动，完全向后兼容。

### 2. 条件表达式

条件是一个 S-expression，支持以下形式：

| 条件 | 说明 |
|------|------|
| `(always)` | 无条件满足 |
| `(hp-below N)` | 当前 HP < N |
| `(hp-above N)` | 当前 HP > N |
| `(player-in-room)` | 玩家在同一房间 |
| `(and cond1 cond2 ...)` | 逻辑与 |
| `(or cond1 cond2 ...)` | 逻辑或 |
| `(not cond)` | 逻辑非 |

### 3. 动作类型

| 动作 | 说明 |
|------|------|
| `(attack)` | NPC 攻击玩家，造成 max(1, NPC-attack - player-defense) 伤害 |
| `(say "文本")` | NPC 说话，显示对话文本 |
| `(move random)` | NPC 随机移动到相邻房间 |
| `(move up/right/down/left)` | NPC 向指定方向移动 |
| `(buff attr value)` | NPC 给自己施加增益 |
| `(debuff attr value)` | NPC 给玩家施加减益 |

### 4. 执行流程

#### 触发时机

1. **玩家进入房间时**：`tg-move` 中 `in-trigger` 触发之后
2. **玩家每次行动后**：`tg-parse` 中玩家命令执行完成之后

注意：`tg-attack` 的反击逻辑属于战斗系统固有部分，不替换。但玩家攻击完成后，当前房间其他 NPC 仍应通过行为系统行动。

#### 规则匹配

```
对当前房间每个 NPC（跳过 myself 和 HP<=0 的 NPC）：
  遍历其 behaviors 列表（顺序优先级）：
    评估条件表达式
    如果条件满足：
      执行动作
      跳出（每回合每个 NPC 只执行第一条匹配的规则）
```

### 5. 核心函数

新增模块 `npc-behavior.el`：

| 函数 | 说明 |
|------|------|
| `npc-run-behaviors` | 遍历当前房间所有 NPC，执行匹配行为 |
| `npc-evaluate-condition (creature condition)` | 评估条件表达式，返回 t/nil |
| `npc-execute-action (creature action)` | 执行一条动作 |
| `npc-attack-player (creature)` | NPC 攻击玩家 |
| `npc-say (creature text)` | NPC 说话 |
| `npc-move (creature direction)` | NPC 移动（`random` 或具体方向） |
| `npc-apply-buff (creature attr value)` | NPC 给自己加增益 |
| `npc-apply-debuff (creature attr value)` | NPC 给玩家加减益 |

### 6. 配置文件格式

`creature-config.el` 扩展为 8 个字段：

```elisp
(symbol "描述" (attrs) (inventory) (equipment) death-trigger exp-reward behaviors)
```

示例：

```elisp
(hero "冒险者" ((hp . 100) (attack . 5) (defense . 3) (exp . 0) (level . 1) (bonus-points . 0)) () () nil 0 nil)
(goblin "哥布林" ((hp . 25) (attack . 6) (defense . 2)) () () nil 18
  (((always) attack)))
(skeleton-king "骷髅王" ((hp . 80) (attack . 15) (defense . 8)) () () nil 120
  (((hp-below 30) say "蝼蚁！你以为你能赢？")
   ((always) attack)))
(guard "守卫" ((hp . 40) (attack . 8) (defense . 4)) () () nil 30
  (((player-in-room) say "站住！这里不允许进入！")
   ((always) attack)))
(prisoner "囚犯" ((hp . 20) (attack . 1) (defense . 0)) () () nil 8
  (((player-in-room) say "请救救我...")))
```

### 7. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `creature-maker.el` | Creature struct 新增 `behaviors` slot |
| `creature-maker.el` | `build-creature` 解析第 8 个字段 `behaviors` |
| `tg-mode.el` | `tg-parse` 玩家命令完成后调用 `npc-run-behaviors` |
| `action.el` | `tg-move` 进入房间后调用 `npc-run-behaviors` |
| `text-game-maker.el` | `(require 'npc-behavior)` |
| `sample/creature-config.el` | 为部分 NPC 添加 behaviors |

### 8. 边界情况

- NPC 行动前检查 HP，HP <= 0 的 NPC 不行动
- NPC 攻击后检查玩家 HP，玩家 HP <= 0 则 `tg-over-p = t`
- NPC 移动时从当前房间 creature 列表移除，添加到目标房间 creature 列表
- NPC 移动到玩家不在的房间时，玩家不看到该 NPC 的行动信息
- `myself` 永远不参与行为系统
- `behaviors` 为 `nil` 的 NPC 不行动（向后兼容）
- NPC 行为不会触发自身的 `watch-trigger`
- NPC 行为在房间 `in-trigger` 之后执行

### 9. 消息格式

NPC 行动信息通过 `tg-display` 输出：

- 攻击：`"哥布林攻击了你，造成 3 点伤害！"`
- 说话：`"哥布林说：你休想活着离开！"`
- 移动：`"哥布林向北离开了。"` / `"哥布林从北方走了过来。"`（目标房间看到）
- Buff：`"哥布林怒吼一声，攻击力增强了！"`
- Debuff：`"哥布林对你施放了诅咒，防御力降低了！"`

### 10. 测试覆盖

- `npc-evaluate-condition`：各种条件（always, hp-below, hp-above, player-in-room, and/or/not）
- `npc-execute-action`：各种动作（attack, say, move, buff, debuff）
- `npc-run-behaviors`：规则匹配顺序、每回合只执行一条、跳过 myself 和已死亡 NPC
- NPC 移动：从房间移除、添加到目标房间
- NPC 攻击：伤害计算、玩家死亡
- 集成测试：`tg-parse` 和 `tg-move` 后 NPC 行为触发
- 向后兼容：`behaviors` 为 nil 时 NPC 不行动
