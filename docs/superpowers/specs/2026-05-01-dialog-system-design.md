# NPC 对话树系统设计

## 目标

为 Text-Game-Maker 添加 NPC 对话系统，支持简单单层分支对话。玩家通过 `talk <NPC>` 命令与 NPC 交互，看到编号选项列表，选择后 NPC 回应并可能触发效果（奖励、事件等）。选项可根据条件动态显示/隐藏。

## 现有架构

游戏已有完整的 action 系统（`tg-attack`, `tg-take`, `tg-move`, `tg-watch` 等），通过 `tg-defaction` 宏定义。NPC 行为系统、任务系统已集成。

关键集成点：
- `tg-parse` — 命令解析入口，可检测 pending 状态
- `creature-exist-in-room-p` — 检查 NPC 是否在当前房间
- `quests-alist` — 对话条件判断依赖任务状态
- `Creature-inventory` / `myself` — 对话条件判断依赖玩家物品

## 设计

### 1. 数据结构

#### Dialog 结构体

```elisp
(cl-defstruct Dialog
  (npc nil :documentation "关联的 NPC symbol")
  (greeting "" :documentation "NPC 开场白")
  (options nil :documentation "DialogOption 列表"))
```

#### DialogOption 结构体

```elisp
(cl-defstruct DialogOption
  (text "" :documentation "玩家看到的选项文本")
  (response "" :documentation "NPC 的回应文本")
  (condition nil :documentation "显示条件（nil 表示总是显示）")
  (effects nil :documentation "效果列表: ((exp . N) (item . symbol) (bonus-points . N) (trigger . lambda))"))
```

### 2. 配置文件格式

`dialog-config.el`，每行一个对话定义：

```elisp
(<npc-symbol> "<开场白>"
  (("<选项文本>" "<NPC回应>" <condition> <effects>)
   ("<选项文本>" "<NPC回应>" <condition> <effects>)
   ...))
```

示例：

```elisp
(prisoner "请救救我...你在找什么？"
  (("你是谁？" "我是被骷髅王关押的探险者。" nil nil)
   ("有什么线索吗？" "听说武器库里有把好剑！西边的走廊可以过去。"
    (quest-active find-sword) ((exp . 10)))
   ("给你点吃的" "谢谢你...这个给你，可能对你有用。"
    (has-item bread) ((item . map)))))
```

### 3. 条件表达式

| 条件 | 说明 |
|------|------|
| `nil` | 总是显示 |
| `(quest-active symbol)` | 指定任务处于 active 状态 |
| `(quest-completed symbol)` | 指定任务已完成 |
| `(has-item symbol)` | 玩家携带指定物品 |
| `(and cond1 cond2 ...)` | 逻辑与 |
| `(or cond1 cond2 ...)` | 逻辑或 |

条件表达式在显示选项列表时实时评估，不满足条件的选项不显示。

### 4. 效果类型

与任务系统奖励格式一致：

| 效果 key | 值类型 | 说明 |
|----------|--------|------|
| `exp` | 整数 | 通过 `add-exp-to-creature` 发放经验值 |
| `item` | symbol | 通过 `add-inventory-to-creature` 添加物品到玩家 |
| `bonus-points` | 整数 | 直接增加玩家 `bonus-points` 属性 |
| `trigger` | lambda | 选择后调用的回调函数 |

多个效果可以共存于同一个选项的 effects 列表中。

### 5. 交互流程

#### 两阶段输入机制

`talk` 命令使用两阶段输入，无需修改 tg-mode 核心循环：

1. **阶段 1**：玩家输入 `talk <NPC>`，显示开场白和选项列表，设置 `dialog-pending` 全局变量
2. **阶段 2**：`tg-parse` 检测到 `dialog-pending` 不为 nil，直接将输入作为选项编号处理

#### 示例交互

```
> talk prisoner
囚犯说：请救救我...你在找什么？
  1. 你是谁？
  2. 有什么线索吗？
  3. 给你点吃的
请输入选项编号:
> 2
囚犯说：听说武器库里有把好剑！西边的走廊可以过去。
获得 10 点经验值！
```

#### 输入验证

- 输入非数字或超出范围：提示"请输入有效的选项编号"，保持对话状态
- 输入 0 或负数：提示无效
- 输入有效数字：执行回应和效果，清除 `dialog-pending`

### 6. 核心函数

新增模块 `dialog-system.el`：

| 函数 | 说明 |
|------|------|
| `dialog-init (config-file)` | 从配置文件加载所有对话 |
| `dialog-evaluate-condition (cond)` | 评估条件表达式 |
| `dialog-get-visible-options (dialog)` | 返回满足条件的选项列表 |
| `dialog-apply-effects (option)` | 执行选项效果 |
| `dialog-start (npc-symbol)` | 开始与 NPC 对话 |
| `dialog-handle-choice (choice-str)` | 处理玩家选择 |

全局变量：
- `dialogs-alist` — NPC symbol 到 Dialog 对象的映射
- `dialog-pending` — 当前等待选择的 Dialog 对象（nil 表示无待处理对话）

### 7. 新增游戏命令

| 命令 | 函数 | 说明 |
|------|------|------|
| `talk <NPC>` | `tg-talk` | 与指定 NPC 开始对话 |

### 8. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `dialog-system.el` | 新建模块 |
| `test/test-dialog-system.el` | 新建测试 |
| `action.el` | 新增 `tg-talk` action；`tg-parse` 中添加 `dialog-pending` 检测 |
| `text-game-maker.el` | `(require 'dialog-system)` |
| `run-tests.sh` | `(require 'test-dialog-system)` |
| `sample/dialog-config.el` | 新建示例对话配置 |
| `sample/sample-game.el` | 调用 `dialog-init`，添加对话提示 |

### 9. tg-parse 集成

在 `tg-parse` 函数中，命令解析前检查 `dialog-pending`：

```elisp
;; 在 tg-parse 中，命令解析之前插入
(when dialog-pending
  (dialog-handle-choice input)
  (setq tg-over-p nil)  ; 保持游戏继续
  ...)  ; 跳过正常的命令解析
```

具体实现需要在 `tg-parse` 的输入获取之后、命令分发之前添加检测。

### 10. 边界情况

- NPC 不在当前房间时抛出"房间中没有<NPC>"异常
- NPC 没有对话配置时提示"无法与<NPC>对话"
- 所有选项条件都不满足时显示 NPC 开场白但提示"没有可用的对话选项"
- `dialog-pending` 激活时，非数字输入提示重新选择（不丢失对话状态）
- NPC 死亡后（不在房间中）不能对话
- 同一 NPC 每次调用 `talk` 都重新评估条件，可以多次对话

### 11. 测试覆盖

- `dialog-init` — 从临时文件加载对话配置
- `dialog-evaluate-condition` — 各种条件表达式（nil、quest-active、quest-completed、has-item、and、or）
- `dialog-get-visible-options` — 过滤不满足条件的选项
- `dialog-apply-effects` — exp/item/bonus-points/trigger 效果
- `dialog-start` — 成功开始对话、NPC 不在房间、NPC 无对话配置
- `dialog-handle-choice` — 有效选择、无效选择、效果执行
- `tg-talk` — 集成测试
- `tg-parse` — dialog-pending 检测集成
