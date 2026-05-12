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
- `initial-*` 三个字段：在 `tg-config--parse-creature-section` 解析时，从 `attr`/`inventory`/`equipment` 复制一份保存。运行时修改不会影响这些快照。

### 1.2 全局配置

- `tg-respawn-default-interval`（defvar）：默认刷新区间，nil 表示默认不刷新
- 由 `#+RESPAWN_DEFAULT` 文件级关键字设置，格式同 per-creature 的 `RESPAWN`

### 1.3 刷新队列

在 `tg-game` hash table 中存储：

```
:respawn-queue → alist: ((creature-symbol . respawn-turn) ...)
```

- creature 死亡时 schedule，刷新时移除
- 存活/未死亡的 creature 不在队列中

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
- 格式 `"N-M"` → `(N . M)`
- 无 `RESPAWN` 属性 → 使用 `tg-respawn-default-interval` 全局默认
- 全局默认也为 nil → 该 creature 不刷新
- `shopkeeper` 为 true 的 creature 始终不刷新，无视 RESPAWN 配置

---

## 3. 刷新流程

### 3.1 死亡调度

在 `tg-action--handler-attack` 的死亡处理中（现有逻辑之后），调用 `tg-respawn-schedule`：

1. 检查 creature 的 `respawn-interval` 是否非 nil
2. 检查 creature 是否为 shopkeeper（shopkeeper 不刷新）
3. **检查队列中是否已存在该 creature-symbol（防重复）**，已存在则跳过
4. 取 `[min, max]` 区间内随机整数 `interval`
5. 计算 `respawn-turn = current-turn + interval`
6. push `(creature-symbol . respawn-turn)` 到 `:respawn-queue`

### 3.2 回合检查

在 `tg-commands.el` 的 `tg-dispatch` 中，回合递增 `(tg-game-incf game :turns)` 之后，调用 `tg-respawn-tick`：

```
tg-respawn-tick:
  current-turn = tg-game-get tg-game :turns
  遍历 respawn-queue:
    if (cdr entry) <= current-turn:
      从 queue 移除该 entry
      调用 tg-respawn-restore 恢复 creature
```

### 3.3 状态恢复

`tg-respawn-restore(creature-symbol)`：

1. 从 registry 获取 creature
2. 恢复 `attr` 为 `initial-attr` 的深拷贝（`copy-alist`）
3. 恢复 `inventory` 为 `initial-inventory` 的 `copy-sequence`
4. 恢复 `equipment` 为 `initial-equipment` 的 `copy-sequence`
5. 静默完成，无输出

注意：creature 已在 room.creatures 列表中（死亡后未被移除），无需处理位置。

---

## 4. 解析变更

### 4.1 新增辅助函数

在 `tg-config.el` 中新增 `tg-config--parse-respawn-interval`：

```
输入: "8-15" 或 nil
输出: (8 . 15) 或 nil
```

解析规则：
- 匹配 `^\([0-9]+\)-\([0-9]+\)$` → `(min . max)`
- 单个数字 `N` → `(N . N)`（固定间隔的简写）
- nil 或空字符串 → nil

### 4.2 tg-config--parse-creature-section 修改

在解析 creature 时：
1. 新增 `respawn-interval` 字段解析（调用 `tg-config--parse-respawn-interval`）
2. 在 `make-tg-creature` 中保存 `initial-attr`（copy-alist attr）、`initial-inventory`（copy-sequence inventory）、`initial-equipment`（copy-sequence equipment）
3. 若 `respawn-interval` 为 nil 且全局默认非 nil 且非 shopkeeper，则使用全局默认

### 4.3 tg-config-load 修改

在提取全局属性阶段新增：
```
(respawn-default (tg-config--parse-keyword content "RESPAWN_DEFAULT"))
```
解析后 setq `tg-respawn-default-interval`。

---

## 5. 模块接口

### tg-respawn.el

```elisp
;; 公开接口
(tg-respawn-schedule creature-symbol)     ;; 死亡时调用，加入刷新队列
(tg-respawn-tick)                         ;; 每回合调用，检查并执行刷新
(tg-respawn-restore creature-symbol)      ;; 恢复 creature 初始状态

;; 全局变量
tg-respawn-default-interval               ;; 默认刷新区间 (min . max) 或 nil
```

依赖：`tg-registry`（获取 creature）、`tg-game`（读取回合和刷新队列）、`tg-creature`（struct 访问）

不依赖：`tg-commands`（避免循环依赖），`tg-respawn-tick` 由 `tg-commands` 调用

---

## 5.1 Save/Load 持久化

`initial-*` 字段是配置时固定的（类似 quest 的 `description`），不需要 save——加载后由 `tg-config-load` 重建。

`:respawn-queue` 是运行时动态状态，**必须 save/load**：

### tg-save--collect-game-state 新增

在 `tg-save.el` 的游戏状态收集函数中，新增：
```
:respawn-queue → (tg-game-get tg-game :respawn-queue)
```

### tg-save--restore-game-state 新增

在恢复游戏状态时，新增：
```
(tg-game-put game :respawn-queue (plist-get saved :respawn-queue))
```

---

## 6. 文件变更汇总

| 文件 | 改动类型 | 说明 |
|---|---|---|
| `tg-respawn.el` | 新增 | 刷新模块（schedule/tick/restore） |
| `tg-creature.el` | 修改 | struct 加 4 字段 |
| `tg-config.el` | 修改 | 解析 RESPAWN + RESPAWN_DEFAULT + 保存初始状态 |
| `tg-commands.el` | 修改 | dispatch 中调用 tg-respawn-tick |
| `tg-action.el` | 修改 | attack 死亡时调用 tg-respawn-schedule |
| `tg-save.el` | 修改 | 保存/加载 :respawn-queue |
| `tg.el` | 修改 | require tg-respawn |
| `sample/game.org` | 修改 | 添加 #+RESPAWN_DEFAULT + 部分 creature 加 RESPAWN |
| `test/tg-respawn-test.el` | 新增 | 刷新模块测试 |
| `test/tg-config-test.el` | 修改 | RESPAWN 解析测试 |
| `test/tg-creature-test.el` | 修改 | struct 新字段测试 |

---

## 7. 测试要点

1. **解析测试**：`tg-config--parse-respawn-interval` 的各种输入（"8-15"、"10"、nil）
2. **struct 字段测试**：新字段读写、initial-* 快照独立性
3. **调度测试**：死亡时 schedule 正确计算 respawn-turn
4. **刷新测试**：tick 到达 respawn-turn 时恢复 creature 状态
5. **不刷新测试**：无 RESPAWN + 无全局默认 → 不 schedule
6. **shopkeeper 测试**：shopkeeper 死亡后不 schedule
7. **全局默认测试**：无 per-creature RESPAWN 时使用全局默认
8. **per-creature 覆盖测试**：有 per-creature RESPAWN 时优先使用
9. **多次死亡刷新测试**：同一 creature 多次死亡-刷新循环
10. **防重复调度测试**：同一 creature 不会重复加入刷新队列
11. **save/load 测试**：刷新队列保存后加载恢复正确
