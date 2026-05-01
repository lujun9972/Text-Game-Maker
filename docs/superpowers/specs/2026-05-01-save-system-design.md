# 存档/读档系统设计

## 目标

为 Text-Game-Maker 添加完整的游戏存档/读档功能，支持保存和恢复完整游戏快照。

## 现有架构

游戏状态分布在多个全局变量中：
- `myself` — 玩家 Creature 对象（attr, inventory, equipment）
- `current-room` — 当前房间 Room 对象
- `rooms-alist` — 所有房间的 alist，Room 有 inventory 和 creature 列表
- `creatures-alist` — 所有生物的 alist，Creature 有 attr（运行时 HP 等）
- `room-map` — 二维地图网格（静态配置）
- `inventorys-alist` — 物品模板（静态配置）

触发器（lambda 函数）不可序列化。恢复时需要从原始配置文件重新加载以获取触发器。

## 设计

### 1. 存档格式

保存为 Emacs Lisp 数据文件（`.el`），内容是一个 alist：

```elisp
((player . ((symbol . hero)
            (attr . ((hp . 85) (attack . 12) (defense . 8) (exp . 150) (level . 3) (bonus-points . 1)))
            (inventory . (potion iron-sword))
            (equipment . (shield))
            (behaviors)))
 (current-room . hall)
 (rooms . ((entrance . ((inventory . (torch)) (creature . (guard))))
           (hall . ((inventory . (map)) (creature . (goblin bat))))))
 (creatures . ((guard . ((attr . ((hp . 40) (attack . 8) (defense . 4))) (inventory) (equipment) (behaviors))))
              (goblin . ((attr . ((hp . 0) (attack . 6) (defense . 2))) (inventory) (equipment) (behaviors))))))
```

### 2. 保存内容

| 数据 | 来源 | 说明 |
|------|------|------|
| 玩家完整状态 | `myself` | symbol, attr, inventory, equipment, behaviors |
| 当前房间 | `current-room` | 房间 symbol |
| 各房间运行时状态 | `rooms-alist` | 每个房间的 inventory 和 creature 列表 |
| 各生物运行时状态 | `creatures-alist` | 每个生物的 attr, inventory, equipment, behaviors |

### 3. 不保存的内容

- 触发器（lambda 不可序列化）— 恢复时从配置文件重新加载
- `room-map`（静态配置）— 恢复时从配置文件重新加载
- `inventorys-alist`（物品模板）— 恢复时从配置文件重新加载
- `level-exp-table` 等升级配置（静态）— 恢复时从配置文件重新加载
- `tg-over-p`（游戏结束标记）

### 4. 恢复流程

```
tg-load-game(filepath)
  → 读取存档文件（read 存档数据）
  → 重新调用 map-init / inventorys-init / creatures-init / level-init
    （重新加载原始配置，恢复所有触发器和静态数据）
  → 用存档数据覆盖：
    - myself 的 attr, inventory, equipment, behaviors
    - current-room
    - 每个 Room 的 inventory 和 creature 列表
    - 每个 Creature 的 attr, inventory, equipment, behaviors
  → 进入 tg-mode，显示当前房间描述
```

### 5. 核心函数

新增模块 `save-system.el`：

| 函数 | 说明 |
|------|------|
| `tg-save-game (filepath)` | 保存完整游戏快照到文件 |
| `tg-load-game (filepath)` | 从文件恢复游戏状态 |
| `tg-serialize-creature (creature)` | 将 Creature 序列化为 alist |
| `tg-serialize-room (room)` | 将 Room 运行时状态序列化为 alist |
| `tg-restore-game-state (data)` | 用存档数据覆盖当前游戏状态 |

### 6. 新增命令

通过 `tg-defaction` 添加两个游戏命令：

- `save <文件名>` — 保存游戏到 `saves/<文件名>.sav`
- `load <文件名>` — 从存档恢复游戏

`save` 命令：
- 自动创建 `saves/` 目录（如不存在）
- 存档文件保存为 Emacs Lisp 可读格式
- 保存后显示确认信息

`load` 命令：
- 读取存档文件
- 需要知道原始配置文件路径（通过全局变量保存）
- 恢复游戏状态并刷新界面

### 7. 配置路径保存

为了 `load` 能正确恢复，需要记住配置文件路径。在初始化时保存：

```elisp
(defvar tg-config-dir nil
  "游戏配置文件目录路径，用于存档恢复时重新加载配置。")
```

`map-init` / `creatures-init` 等函数被调用时，自动从文件路径提取目录保存到 `tg-config-dir`。

### 8. 序列化/反序列化细节

**Creature 序列化：**
```elisp
;; 输入: Creature 对象
;; 输出: alist
((symbol . hero)
 (attr . ((hp . 85) (attack . 12)))
 (inventory . (potion sword))
 (equipment . (shield))
 (behaviors . (((always) attack))))
```

**Room 序列化（仅运行时状态）：**
```elisp
;; 输入: Room 对象
;; 输出: alist（不含触发器）
((inventory . (torch key))
 (creature . (goblin bat)))
```

### 9. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `save-system.el` | 新建模块 |
| `action.el` | 新增 `tg-save` 和 `tg-load` action |
| `room-maker.el` | `map-init` 保存配置目录到 `tg-config-dir` |
| `text-game-maker.el` | `(require 'save-system)` |
| `sample/sample-game.el` | 确保配置路径正确保存 |

### 10. 存档文件路径

存档保存在配置目录下的 `saves/` 子目录：
```
/path/to/game-config/
├── room-config.el
├── map-config.el
├── creature-config.el
├── ...
└── saves/
    ├── slot1.sav
    └── slot2.sav
```

### 11. 边界情况

- 存档文件不存在时显示错误信息
- 存档文件格式损坏时显示错误信息
- `load` 后游戏状态完全重置，之前的进度丢失
- 游戏结束后仍可 `load` 恢复（重置 `tg-over-p`）
- `saves/` 目录不存在时自动创建

### 12. 测试覆盖

- `tg-serialize-creature` — 序列化 Creature 为 alist
- `tg-serialize-room` — 序列化 Room 运行时状态
- `tg-save-game` — 保存到临时文件并验证内容
- `tg-load-game` — 保存后恢复并验证状态一致
- `tg-save-game` / `tg-load-game` 往返测试
- 存档不存在时的错误处理
- 恢复后玩家属性/物品/位置正确
- 恢复后房间状态正确
- 恢复后已击败的 NPC 不在房间中
