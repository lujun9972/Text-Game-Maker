# 升级系统设计

## 目标

为 Text-Game-Maker 添加经验值 + 等级 + 技能点分配的升级机制，通过战斗获取经验值自动升级。

## 现有架构

Creature 的 `attr` 是一个 alist，如 `((hp . 100) (attack . 5) (defense . 3))`。`take-effect-to-creature` 已能增减属性值。

## 设计

### 1. 升级配置文件 `level-config.el`

不带外层括号，与其他配置文件格式一致：

```elisp
(level-exp-table 0 100 250 500 800 1200 1600 2100 2700 3500)
(level-up-bonus-points 3)
(auto-upgrade-attrs ((hp . 5)))
```

- `level-exp-table`：每级所需**累计**经验值。索引 0 对应 1→2 级所需累计经验 100，索引 1 对应 2→3 级所需 250，以此类推。达到最大等级后不再升级。
- `level-up-bonus-points`：每次升级获得的可自由分配技能点数。
- `auto-upgrade-attrs`：升级时自动提升的属性列表（不消耗技能点），如 hp +5。

### 2. Creature 属性扩展

在 Creature 的 `attr` alist 中新增三个属性：

| 属性 | 初始值 | 说明 |
|------|--------|------|
| `exp` | 0 | 当前累计经验值 |
| `level` | 1 | 当前等级 |
| `bonus-points` | 0 | 可用技能点 |

`creature-config.el` 示例：

```elisp
(hero "勇敢的冒险者" ((hp . 100) (attack . 5) (defense . 3) (exp . 0) (level . 1) (bonus-points . 0)) () ())
```

不填这些属性的 Creature（如怪物）默认没有升级能力——只有 `myself`（玩家）需要配置。

### 3. 经验值获取

仅通过 `attack` 命令击败怪物获得经验。

经验奖励来源：在 `creature-config.el` 中为每个生物新增第 6 个字段 `exp-reward`：

```elisp
(goblin "哥布林" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15)
```

若 `exp-reward` 为 nil 或未提供，则自动按怪物 `(hp + attack + defense)` 计算经验值。

### 4. 升级触发

在 `tg-attack` 中，当怪物被击败时：

1. 计算经验奖励值
2. 调用 `add-exp-to-creature` 将经验加到 `myself` 的 `exp` 属性
3. `add-exp-to-creature` 检查是否达到升级阈值
4. 若达到：循环升级（可能一次升多级），每次升级执行：
   - `level` +1
   - 应用 `auto-upgrade-attrs`（如 hp +5）
   - `bonus-points` += `level-up-bonus-points`
   - 输出升级信息到游戏 buffer

### 5. 新增 action：`tg-upgrade`

```
upgrade <attr> <points>
```

将指定数量的技能点分配到指定属性上。

规则：
- 必须有足够的 `bonus-points`
- `attr` 必须是已有的属性（不能凭空创建新属性）
- 执行后 `bonus-points` 减少，目标属性增加

示例：`upgrade attack 2` → attack +2，bonus-points -2

### 6. 新增模块：`level-system.el`

| 函数 | 说明 |
|------|------|
| `level-init (config-file)` | 加载升级配置文件 |
| `add-exp-to-creature (creature exp)` | 给生物加经验，自动检查并处理升级 |
| `get-exp-reward (creature)` | 获取生物的经验奖励值（优先 exp-reward，否则自动计算） |
| `tg-upgrade` | 技能点分配 action |

### 7. 数据流

```
tg-attack 击败怪物
  → get-exp-reward 获取经验值
  → add-exp-to-creature(myself, exp)
    → 累加 exp 属性
    → 循环检查 level-exp-table
      → 升级: level+1, auto-upgrade-attrs, bonus-points+N
      → tg-display 升级信息
```

### 8. 配置文件解析

`level-config.el` 使用 `##` 分隔块格式（与 tg-config-generator 一致），但内容只有一块，也可用简单的 key-value 格式：

```elisp
(level-exp-table 0 100 250 500 800 1200)
(level-up-bonus-points 3)
(auto-upgrade-attrs ((hp . 5)))
```

每行一个列表，通过 `read-from-whole-string` 解析（会自动包裹外层括号变为列表的列表），然后用 `assoc` 提取各配置项。

### 9. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `creature-maker.el` | `build-creature` 解析第 6 个字段 `exp-reward`，存入新 slot |
| `creature-maker.el` | Creature struct 新增 `exp-reward` slot |
| `action.el` | `tg-attack` 击败怪物后调用 `add-exp-to-creature` |
| `action.el` | 新增 `tg-upgrade` action |
| `text-game-maker.el` | `(require 'level-system)` |
| `sample/creature-config.el` | 为每个生物添加 exp-reward 字段 |
| `sample/level-config.el` | 新建升级配置文件 |
| `sample/sample-game.el` | 调用 `level-init` |

### 10. 测试覆盖

- `level-init` 配置加载
- `add-exp-to-creature` 经验累加
- 升级触发（单次、连续升级）
- `auto-upgrade-attrs` 自动属性提升
- `bonus-points` 正确增加
- `tg-upgrade` 技能点分配（正常、不足、无效属性）
- `get-exp-reward`（显式值 vs 自动计算）
- `tg-attack` 击败后获得经验
