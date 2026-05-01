# 商店/交易系统设计

## 目标

为 Text-Game-Maker 添加基于 NPC 商人的交易系统，支持金币、买卖物品、可配置卖出折扣率。

## 现有架构

Creature 系统使用 `cl-defstruct` 定义生物结构体，包含 symbol、description、attr、inventory、equipment、triggers 字段。`action.el` 通过 `tg-defaction` 宏定义玩家命令。

`creature-config.el` 配置格式为 `(symbol description attr-list inventory equipment triggers)`。

## 设计

### 1. 货币

单一金币体系。新增全局变量 `player-gold`，默认值为 0。可在 level-config 或游戏初始化时设置初始金币。

### 2. 商人标记

在 Creature 结构体中新增 `shopkeeper` 布尔字段。

creature-config.el 扩展格式：
```
(symbol description attr-list inventory equipment triggers shopkeeper)
```

非商人 NPC 的 shopkeeper 值为 nil（向后兼容）。

### 3. 商品配置

独立配置文件 `shop-config.el`，格式：
```
(npc-symbol sell-rate
  ((item-symbol price) ...))
```

- `npc-symbol`：对应 creature-config 中的商人 symbol
- `sell-rate`：浮点数，卖给该商人时的价格折扣率（如 0.3 表示卖出价 = 买价 × 30%）
- `item-symbol`：物品 symbol，对应 inventory-config 中的物品
- `price`：整数，购买价格

示例：
```
(goblin-merchant 0.3
  ((bread 10) (health-potion 25) (iron-sword 50)))
(blacksmith 0.6
  ((iron-shield 40) (steel-sword 80)))
```

### 4. 数据结构

```elisp
;; shop-system.el

(defvar player-gold 0
  "玩家持有金币数量")

(defvar shop-alist nil
  "商品列表缓存，格式 ((npc-symbol . (sell-rate . ((item . price) ...))) ...)")
```

### 5. 命令

| 命令 | 函数 | 行为 |
|------|------|------|
| `shop` | `tg-shop` | 显示当前房间商人的商品列表和价格 |
| `buy <物品>` | `tg-buy` | 从商人购买物品，扣除金币，物品加入背包 |
| `sell <物品>` | `tg-sell` | 卖出背包物品，获得 price × sell-rate 金币 |

### 6. 交易逻辑

#### `tg-shop`

1. 检查当前房间是否有 creature 且该 creature 的 shopkeeper 为 t
2. 从 shop-alist 中查找该商人的商品列表
3. 显示格式：`商品名: X金币`，每行一个
4. 如果房间没有商人或商人没有商品，提示"这里没有商店"

#### `tg-buy`

1. 检查当前房间是否有商人
2. 检查指定物品是否在该商人商品列表中
3. 检查 player-gold >= 价格
4. 扣除 player-gold
5. 从商人商品列表中移除该物品
6. 物品加入玩家（myself）背包
7. 提示"购买了 XXX，花费 X 金币"

#### `tg-sell`

1. 检查当前房间是否有商人
2. 检查玩家背包是否有该物品
3. 从商人商品列表中查找该物品的基础价格（如果没有，则查询物品是否有默认价格配置）
4. 计算卖出价 = 基础价格 × sell-rate
5. player-gold 增加卖出价
6. 物品从玩家背包移除
7. 物品加入商人商品列表（可再购买）
8. 提示"卖出了 XXX，获得 X 金币"

### 7. 初始化

```elisp
(defun shop-init (config-file)
  "从 CONFIG-FILE 加载商品配置。"
  ;; 用 read-from-whole-string + eval 读取
  ;; 解析为 shop-alist
  )
```

游戏启动时调用 `(shop-init path)`，与 `creatures-init` 等类似。

### 8. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `creature-maker.el` | Creature 结构体加 `shopkeeper` 字段（默认 nil） |
| `shop-system.el` | 新建：shop-init、商品查询、buy/sell 辅助函数 |
| `action.el` | 新增 tg-shop、tg-buy、tg-sell 三个 tg-defaction |
| `text-game-maker.el` | 添加 `(require 'shop-system)` |
| `save-system.el` | 保存/恢复 player-gold 和 shop-alist |

### 9. 测试覆盖

- shop-init：配置加载、解析
- tg-shop：有/无商人、有/无商品
- tg-buy：正常购买、金币不足、物品不存在、无商人
- tg-sell：正常卖出、背包无物品、无商人、sell-rate 计算
- 集成：购买后物品在背包、卖出后物品回到商人列表
- 存档：player-gold 和商品列表的保存/恢复

### 10. 边界情况

- 房间内多个生物时，只与第一个 shopkeeper 交互
- 卖出不在商人原商品列表中的物品：使用默认价格（需要物品有 price 属性或使用固定最低价）
- 金币为 0 时无法购买
- 商品列表为空时 shop 显示"商品已售罄"
- 向后兼容：shopkeeper 字段可选，不提供时默认 nil
