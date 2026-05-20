# Creature 刷新机制设计规格

**目标：** 支持小兵死亡后按随机回合区间自动刷新，恢复初始状态，实现反复刷怪的 MUD 经典玩法。

**架构：** 新增 `tg-respawn.el` 模块（单职责），在 creature struct 中新增刷新相关字段，在游戏 dispatch 回合递增后触发刷新检查。

**技术栈：** Emacs Lisp, Org-mode (org-element), ERT

---

## 1. 数据模型

### 1.1 tg-creature struct 新增字段

在 `tg-creature.el` 的 struct 末尾新增 4 个字段：

```
respawn-interval     ;; 刷新区间 (min . max) cons 或 nil。nil 表示不刷新。
initial-attr         ;; 初始属性快照（解析时保存的 attr 副本）
initial-inventory    ;; 初始背包（解析时保存的 inventory 副本）
initial-equipment    ;; 初始装备（解析时保存的 equipment 副本）
```

- `respawn-interval`：来自 Org 配置的 `RESPAWN` 属性，格式 `"8-15"` 解析为 `(8 . 15)`
- `initial-*` 三个字段：**仅当 `respawn-interval` 非 nil 时保存**，避免为不刷新的生物浪费内存。在 `tg-config--parse-creature-section` 解析时，从 `attr`/`inventory`/`equipment` 复制一份保存。运行时修改不会影响这些快照。

### 1.2 全局配置

- `tg-respawn-default-interval`（defvar，定义于 `tg-respawn.el`）：默认刷新区间，nil 表示默认不刷新
- 由 `#+RESPAWN_DEFAULT` 文件级关键字设置，格式同 per-creature 的 `RESPAWN`
- `tg-config-load` 开头重置此变量为 nil，防止上一次加载的旧值残留

### 1.3 刷新队列

在 `tg-game` hash table 中存储：

```
:respawn-queue → alist: ((creature-symbol . respawn-turn) ...)
```

- creature 死亡时 schedule，刷新时移除
- 存活/未死亡的 creature 不在队列中
- 队列中同一 creature-symbol 最多只出现一次（防重复调度）
- 队列初始为 nil（`tg-game-get` 对不存在的 key 返回 nil，无需在 `tg-new-game` 中显式初始化）

---

## 2. Org 配置语法

### 2.1 文件级关键字

```
#+RESPAWN_DEFAULT: 10-20
```

| 关键字 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `RESPAWN_DEFAULT` | 区间字符串 | 否 | nil | 全局默认刷新区间 |

### 2.2 per-creature 属性

```
** goblin
:PROPERTIES:
:NAME: 狡猾的哥布林
:ATTR: hp 25 attack 6 defense 2
:RESPAWN: 8-15
:END:
```

| 属性 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `RESPAWN` | 区间字符串 | 否 | 全局默认 | 该 creature 的刷新区间 |

**解析规则：**
- 格式 `"N-M"` → `(N . M)`，必须满足 `N <= M`
- 单个数字 `"N"` → `(N . N)`（固定间隔的简写）
- 无 `RESPAWN` 属性 → 使用 `tg-respawn-default-interval` 全局默认
- 全局默认也为 nil → 该 creature 不刷新
- `shopkeeper` 为 true 的 creature 始终不刷新，无视 RESPAWN 配置

---

## 3. 刷新流程

### 3.1 死亡调度

在 `tg-action--handler-attack` 的死亡处理中（现有逻辑之后），调用 `tg-respawn-schedule`：

1. 检查 creature 是否确实死亡（通过 `tg-creature-dead-p` 守卫，防止误调度活 creature）
2. 检查 creature 的 `respawn-interval` 是否非 nil
3. 检查 creature 是否为 shopkeeper（shopkeeper 不刷新）
4. 检查队列中是否已存在该 creature-symbol（防重复），已存在则跳过
5. 取 `[min, max]` 区间内随机整数 `interval`
6. 计算 `respawn-turn = current-turn + interval`
7. append `(creature-symbol . respawn-turn)` 到 `:respawn-queue` 末尾（FIFO 顺序，先死后活），并通过 `tg-game-put` 写回 game

**生命周期：** creature 死亡 → 进队列 → 回合到达 → 刷新恢复 → 从队列移除。之后 creature 可再次死亡、再次进队列，形成完整的"死-活-死"循环。

**关于物品掉落与恢复：** 生物死亡时，背包和装备栏物品掉落在地、清空。可通过 object 的 `no-drop` prop 标记某物品不掉落（该物品保留在生物身上不处理）。刷新时从 `initial-inventory`/`initial-equipment` 恢复。这意味着同一件物品会同时在地上和生物身上——这是经典 MUD 刷怪刷装备的玩法，属于有意设计。玩家可以反复击杀同一种怪获取多份战利品。

### 3.2 回合检查

在 `tg-commands.el` 的 `tg-dispatch` 中，非被动命令处理块内、回合递增 `(tg-game-incf game :turns)` 之后，调用 `(tg-respawn-tick)`：

```elisp
(unless (or (member action-id passive-list)
            (member (format "%s" action-id) passive-list))
  (tg-npc-run-behaviors game)
  (tg-buffs-tick game)
  (tg-game-incf game :turns)
  (tg-respawn-tick))  ;; 新增
```

- `tg-respawn-tick` 通过全局变量 `tg-game` 访问游戏状态
- 放在 `unless` 块内意味着被动命令（look/examine/inventory 等）不会推进刷新计时器。只有玩家实际行动才推进回合，这符合回合制游戏语义

```
tg-respawn-tick:
  current-turn = (tg-game-get tg-game :turns)
  遍历 (tg-game-get tg-game :respawn-queue):
    if (cdr entry) <= current-turn:
      从 queue 移除该 entry
      tg-game-put 更新 :respawn-queue
      调用 tg-respawn-restore 恢复 creature
```

### 3.3 状态恢复

`tg-respawn-restore(creature-symbol)`：

1. 从 registry 获取 creature，若为 nil 或非 creature struct（`tg-creature-p` 检查）则静默跳过
2. 恢复 `attr` 为 `initial-attr` 的 `copy-tree`
3. 恢复 `inventory` 为 `initial-inventory` 的 `copy-sequence`

   > 代码注释提醒：`copy-sequence` 对 symbol list 已足够；若装备变为 mutable struct 需升级为 `copy-tree`。
4. 恢复 `equipment` 为 `initial-equipment` 的 `copy-sequence`
5. 若玩家与 creature 在同一房间，输出刷新通知：
   - 格式：`"(creature-name) 从地上爬了起来！"` 或类似文字
   - 若玩家不在同一房间，不输出通知（等玩家回到该房间自然能看到）
   - 通知通过 `tg-message` 输出

注意：creature 已在 room.creatures 列表中（死亡后未被移除），无需处理位置。

### 3.4 复制方法说明

- `copy-tree`：递归深拷贝全部 cons cell。attr alist `((hp 30) (attack 5))` 的每层 cons（外层 association pair + 内层值 cell）全部独立，`tg-creature-take-effect` 的 `setcar` 修改只影响当前 attr，不会污染 `initial-attr`。
- `copy-sequence`：浅拷贝 list。由于 inventory/equipment 中元素是 symbol（immutable），浅拷贝已足够。若未来 item 变成 mutable struct，需升级为 `copy-tree`。

---

## 4. 解析变更

### 4.1 新增辅助函数

在 `tg-config.el` 中新增 `tg-config--parse-respawn-interval`：

```
输入: "8-15" 或 nil 或 ""
输出: (8 . 15) 或 nil
```

解析规则：
- 匹配 `^\([0-9]+\)-\([0-9]+\)$` → 若 `1 ≤ min ≤ max` 则返回 `(min . max)`，否则 nil。min 至少为 1，0 回合刷新无意义
- 单个数字 `"N"` → 若 `N ≥ 1` 则返回 `(N . N)`（固定间隔的简写），`"0"` 返回 nil
- nil 或空字符串 → nil

### 4.2 tg-config--parse-creature-section 修改

在解析 creature 时：
1. 新增 `respawn-interval` 字段解析（调用 `tg-config--parse-respawn-interval`）
2. 若 `respawn-interval` 为 nil 且全局默认非 nil 且非 shopkeeper，则使用全局默认
3. **仅当最终 `respawn-interval` 非 nil 时**，在 `make-tg-creature` 中保存 `initial-attr`（`copy-tree` attr）、`initial-inventory`（`copy-sequence` inventory）、`initial-equipment`（`copy-sequence` equipment）。不刷新的生物这三个字段为 nil，节省内存。

### 4.3 tg-config-load 修改

在函数开头新增：
```
(setq tg-respawn-default-interval nil)
```
防止前一次加载的旧值残留。

在提取全局属性阶段新增：
```
#+RESPAWN_DEFAULT → (setq tg-respawn-default-interval (tg-config--parse-respawn-interval value))
```
位置在 `#+TITLE`、`#+AUTHOR`、`#+START`、`#+PLAYER` 提取的同一阶段（在解析各 section 之前），确保 per-creature 使用全局默认时变量已就绪。

---

## 5. 模块接口

### 5.1 tg-respawn.el

```elisp
;; 公开接口
(tg-respawn-schedule creature-symbol)     ;; 死亡时调用，加入刷新队列。通过全局 tg-game 访问游戏状态。
(tg-respawn-tick)                         ;; 每回合调用，检查并执行刷新。通过全局 tg-game 访问游戏状态。
(tg-respawn-restore creature-symbol)      ;; 恢复 creature 初始状态。通过全局 tg-game 访问游戏状态。

;; 全局变量
tg-respawn-default-interval               ;; 默认刷新区间 (min . max) 或 nil
```

依赖：`tg-registry`（获取 creature）、`tg-game`（读取回合和刷新队列）、`tg-creature`（struct 访问）、`tg-room`（判断 player 是否与 creature 同房间，用于通知）

不依赖：`tg-commands`（避免循环依赖），`tg-respawn-tick` 由 `tg-commands` 调用。

**关于 `tg-message` 的运行时调用**：`tg-respawn-restore` 中的同房间通知通过 `tg-message` 输出（定义于 `tg-commands.el`），但 `tg-respawn.el` **不 require `tg-commands`**——与 `tg-dialog.el` 的模式一致：运行时所有模块已加载，`tg-message` 可直接调用而不引入循环依赖。

**加载顺序**：`tg-respawn.el` 必须在 `tg-config.el` 之前加载，因为 `tg-config-load` 需要设置 `tg-respawn-default-interval`。在 `tg.el` 中：
```
... tg-level → tg-respawn → tg-save → tg-config ...
```

---

## 6. Save/Load 持久化

`initial-*` 字段是配置时固定的（类似 quest 的 `description`），不需要 save——加载后由 `tg-config-load` 重建。

`:respawn-queue` 是运行时动态状态，**必须 save/load**：

### 6.1 tg-save--collect-game-state 新增

在 `tg-save.el` 的游戏状态收集函数中，新增：
```
:respawn-queue → (tg-game-get tg-game :respawn-queue)
```

### 6.2 tg-save--restore-game-state 新增

在恢复游戏状态时，新增：
```
(tg-game-put game :respawn-queue (plist-get saved :respawn-queue))
```

**注意**：读档时先执行 `tg-config-load`（重建所有 creature 结构体，设置 initial-*），再执行 `tg-save--restore-creatures`（覆盖 attr/inventory/equipment 为存档中的值）。队列中 creature-symbol 指向 registry 中新重建的结构体，`initial-*` 字段由 `tg-config-load` 正确设置，不依赖存档。

---

## 7. 边界情况

### 7.1 death-trigger 与刷新交互

可刷新生物每次死亡都会执行 `death-trigger`。若触发器有副作用（如"boss 死后开门"、"触发剧情对话"），刷新后再次击杀会重复触发。**框架不处理此问题**——由游戏设计师通过判断条件（如全局状态标记）在触发器内部处理。

### 7.2 两次死亡间隔短于刷新区间

生物死亡后在队列中等待刷新时，理论上不会再次被攻击（hp ≤ 0 时通过 `tg-creature-dead-p` 已被判定死亡，正常游戏逻辑不应以死亡生物为目标）。若出现极端情况（AoE 伤害等），防重复 guard 会阻止二次调度。

### 7.3 shopkeeper 不受 RESPAWN 影响

`shopkeeper` 为 true 的生物，即使有 `RESPAWN` 属性或全局默认，也始终不刷新。这是硬性规则，因为商店老板不应被反复击杀。

### 7.4 玩家角色不刷新

`tg-respawn-schedule` 只应用于 creature（NPC），不应在玩家死亡时调用。玩家死亡由现有游戏结束逻辑处理。

### 7.5 刷新时玩家不在场

若 creature 刷新时玩家不在同一房间，不输出通知。玩家下次进入该房间时，新刷新的 creature 自然出现在房间的 creature 列表中。

### 7.6 no-drop prop 与掉落

object 可设置 `:PROPS: no-drop` 标记物品不可掉落。creature 死亡时，背包和装备栏中带有 `no-drop` prop 的物品不落地、不清除，保留在 creature 身上。这对 boss 专属装备等场景有用——boss 死后武器不落地，避免玩家获得。

`no-drop` 通过 `(memq 'no-drop (tg-object-props obj))` 检查。该 prop 同时影响 inventory 和 equipment 掉落。

---

## 8. 文件变更汇总

| 文件 | 改动类型 | 说明 |
|---|---|---|
| `tg-respawn.el` | 新增 | 刷新模块（schedule/tick/restore） |
| `tg-creature.el` | 修改 | struct 加 4 字段 |
| `tg-config.el` | 修改 | 解析 RESPAWN + RESPAWN_DEFAULT + 按需保存初始状态 + 开头重置全局默认 |
| `tg-commands.el` | 修改 | dispatch 中非被动块内调用 tg-respawn-tick |
| `tg-action.el` | 修改 | attack 死亡时掉落 equipment + no-drop 过滤 + 调用 tg-respawn-schedule |
| `tg-save.el` | 修改 | 保存/加载 :respawn-queue |
| `tg.el` | 修改 | require tg-respawn（在 tg-config 之前） |
| `sample/game.org` | 修改 | 添加 #+RESPAWN_DEFAULT + 部分 creature 加 RESPAWN |
| `test/tg-respawn-test.el` | 新增 | 刷新模块测试 |
| `test/tg-config-test.el` | 修改 | RESPAWN 解析测试 |
| `test/tg-creature-test.el` | 修改 | struct 新字段测试 |

---

## 9. 测试要点

1. **解析测试**：`tg-config--parse-respawn-interval` 的各种输入（"8-15"、"10"、nil、""）
2. **struct 字段测试**：新字段读写、initial-* 快照独立性、不刷新生物 initial-* 为空
3. **调度测试**：死亡时 schedule 正确计算 respawn-turn
4. **刷新测试**：tick 到达 respawn-turn 时恢复 creature 状态
5. **通知测试**：玩家与 creature 同房间时刷新有输出，异房间时无输出
6. **不刷新测试**：无 RESPAWN + 无全局默认 → 不 schedule
7. **shopkeeper 测试**：shopkeeper 死亡后不 schedule
8. **全局默认测试**：无 per-creature RESPAWN 时使用全局默认
9. **per-creature 覆盖测试**：有 per-creature RESPAWN 时优先使用
10. **多次死亡刷新测试**：同一 creature 多次死亡-刷新循环，背包物品可重复掉落
11. **防重复调度测试**：同一 creature 不会重复加入刷新队列
12. **save/load 测试**：刷新队列保存后加载恢复正确；读档后 creature 按原定回合刷新
13. **全局默认重置测试**：加载无 RESPAWN_DEFAULT 的游戏后，前次默认值不残留
14. **equipment 掉落测试**：生物死亡时 equipment 掉落在地、equipment 清空
15. **no-drop 测试**：带 `no-drop` prop 的物品不掉落也不清除
16. **tg-creature-p 守卫测试**：对非 creature struct 调用 restore 静默跳过
