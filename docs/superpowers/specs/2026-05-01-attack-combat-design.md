# Attack Combat System Design

## 概述

为 Text-Game-Maker 添加战斗系统：`attack <target>` 命令，支持攻防交替、伤害计算、生物死亡触发器、玩家死亡游戏结束。

## 战斗流程

```
玩家输入: attack <target>
    ↓
1. 验证目标是否在当前房间
    ↓
2. 计算玩家伤害: max(1, player_attack - target_defense)
    ↓
3. 扣除目标 HP
    ↓
4. 目标死亡? (HP <= 0)
   ├─ 是: 移除目标 + 触发 death-trigger → 显示结果
   └─ 否: 继续步骤 5
    ↓
5. 目标反击: max(1, target_attack - player_defense)
    ↓
6. 扣除玩家 HP
    ↓
7. 玩家死亡? (HP <= 0)
   ├─ 是: 显示死亡信息 + 游戏结束
   └─ 否: 显示双方剩余 HP
```

## 伤害公式

```
damage = max(1, attacker_attack - defender_defense)
```

其中 `attack` 和 `defense` 从 Creature 的 `attr` alist 中读取。不存在时默认为 0。

## 数据变更

### Creature 新增 `death-trigger` slot

在 `creature-maker.el` 的 `cl-defstruct Creature` 中新增：

```elisp
(death-trigger nil :documentation "该CREATURE被击败后触发的事件")
```

### 生物配置格式扩展

```
旧: (<symbol> <description> <attr> <inventory> <equipment>)
新: (<symbol> <description> <attr> <inventory> <equipment> <death-trigger>)
```

`death-trigger` 可选，不提供则为 nil。通过 `cl-multiple-value-bind` 新增第 6 个变量实现向后兼容。

配置示例：
```elisp
((hero "勇敢的冒险者" ((hp . 100) (attack . 10) (defense . 5)) (sword) ())
 (goblin "哥布林" ((hp . 30) (attack . 6) (defense . 2)) () ()))
```

### describe 方法不显示 death-trigger

`death-trigger` 是内部逻辑，不出现在 `describe` 输出中。

## 新增 action

### tg-attack

```
attack <target> — 攻击当前房间中的生物
```

交互示例：
```
> attack goblin
你攻击了哥布林，造成 8 点伤害！
哥布林反击，造成 1 点伤害！
你的HP: 99 | 哥布林的HP: 22

> attack goblin
你攻击了哥布林，造成 8 点伤害！
哥布林发出惨叫倒下了！
```

## 影响范围

| 文件 | 改动 |
|------|------|
| `creature-maker.el` | Creature 新增 `death-trigger` slot，`build-creature` 解构新增第 6 个参数 |
| `action.el` | 新增 `tg-attack` action |
| `test/test-creature-maker.el` | 新增 death-trigger 相关测试 |
| `test/test-action.el` | 新增 tg-attack 系列测试 |

## 测试覆盖

- 攻击房间中存在的生物
- 攻击不存在的生物（异常）
- 攻击不存在的目标名（异常）
- 伤害计算（attack - defense，最小为 1）
- 击杀目标（HP 归零，从房间移除）
- 击杀触发 death-trigger
- 反击机制（目标存活时反击）
- 反击伤害计算
- 玩家死亡（游戏结束）
- attack/defense 属性不存在时默认为 0
