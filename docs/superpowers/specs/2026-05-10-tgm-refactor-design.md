# Text-Game-Maker 2.0 重构设计规格

## 背景

对比分析 ifgame（Clojure 文本游戏库）与 Text-Game-Maker 后，发现 TGM 在三个核心基础设施上存在明显差距：

1. **命令解析** — TGM 是分词匹配（`take sword`），ifgame 用 instaparse 做自然语言解析（`"put the bird in the nest"`）
2. **动作分发** — TGM 是直接函数调用 + trigger 钩子，ifgame 是 handler chain（before → indirect-object → direct-object → action → after），任何实体可拦截任何动作
3. **对象模型** — TGM 只有 usable/wearable，ifgame 用属性驱动（container、supporter、scenery、open、static）

此外还存在地图模型受限（2D 矩形网格）、全局状态分散、存档无法保存闭包等问题。

## 核心决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 范围 | 全量重写 | 核心架构缺陷无法通过渐进改进修复 |
| 语言 | Emacs Lisp | TGM 的价值在于 Emacs 集成（buffer 渲染、eldoc、completion），换 Clojure 失去此优势 |
| 兼容性 | 不兼容，直接替换 | 避免在兼容性上消耗精力，新架构值得从零开始 |
| 解析器 | peg.el（内置 PEG） | 声明式语法、无依赖、与 ifgame 的 instaparse 思路一致 |
| 地图 | 方向出口（10 方向） | 支持任意拓扑、多层、斜向移动 |
| 状态模型 | 分离注册表 | rooms/objects/creatures 等定义放在全局 hash table，game state 只存动态数据（location、inventory、turns）。存档只需序列化动态部分，定义通过重载配置恢复 |
| Handler | 显式 handler 函数 | 类似 ifgame，返回 t/nil 控制传播，简单可调试 |
| after-handler | action 后才执行 | 只有 action handler 执行后才触发 room after-handler，before/object 拦截不触发 |
| 重构范围 | 引擎 + UI 同步重写 | 核心引擎和 tg-mode.el 同时重写，保证端到端可用 |
| 对话 | 状态机多轮 | 支持多轮分支对话，有状态的 NPC |
| 对象开闭锁 | 单 state 字段 | open/closed/locked 互斥状态，一个字段控制 |
| 战斗 | TGM 1.0 简单交替 | 玩家攻击 → 敌人反击 → 交替进行 |
| UI | 单 buffer | 一个 buffer 完成所有交互，与 TGM 1.0 一致 |
| 玩家 | 复用 Creature | 玩家就是第一个 Creature，共用同一套结构 |
| 批量操作 | 支持 all | `take all`/`drop all` 逐对象走 handler chain |
| 光照 | 本期不实现 | 避免在核心重构中引入非核心复杂度 |
| place 动作 | 支持 | `put ... in/on ...` 是 container/supporter 的核心交互 |
| open/close/unlock | 支持 | container 状态机的必要交互 |
| 配置 | Org-mode | 直观可读，融入现有 Org-mode 工作流 |
| 存档 | 重载配置 + 恢复动态状态 | 触发器/handler 通过重载配置恢复，不需要函数查表 |
| 辅助命令 | 向导 + 逐项插入 | `tg-gen-game` 生成完整模板，`tg-gen-room` 等逐项插入 |

## 模块架构

```
text-game-maker/
├── tg.el              ;; 入口，require 所有模块
├── tg-parser.el       ;; PEG 语法 + 动态词汇表 + AST 构建
├── tg-game.el         ;; Game 动态状态（location, inventory, turns, state）
├── tg-registry.el     ;; 全局注册表（rooms, objects, creatures, actions, dialogs, shops, quests）
├── tg-room.el         ;; Room 定义 + 方向出口 + 进出触发器
├── tg-object.el       ;; Object 定义 + 属性系统 + 容器状态机 + handler
├── tg-creature.el     ;; Creature 定义 + attr + 玩家/NPC 共用
├── tg-action.el       ;; Action 定义 + 内置动词注册
├── tg-commands.el     ;; Handler chain 调度引擎
├── tg-dialog.el       ;; 状态机对话系统
├── tg-npc.el          ;; NPC 行为规则引擎
├── tg-quest.el        ;; 任务追踪
├── tg-shop.el         ;; 商店/交易
├── tg-level.el        ;; 经验/等级
├── tg-save.el         ;; 存档/读档（重载配置 + 恢复动态状态）
├── tg-config.el       ;; Org-mode 配置解析器
├── tg-config-gen.el   ;; Org 配置辅助生成命令（向导 + 逐项插入 + 验证）
└── tg-mode.el         ;; Emacs major-mode（单 buffer UI）
```

### 依赖关系

单向无循环：

```
tg-registry ← 最底层，注册表容器
  ↓
tg-game     ← 动态状态容器
  ↓
tg-parser   ← 依赖 game 取词汇表，registry 取对象
  ↓
tg-action   ← 动词定义
  ↓
tg-commands ← 调度引擎，组合 room/object/action
  ↓  ↓  ↓
tg-room  tg-object  tg-creature
  ↓  ↓  ↓
tg-dialog  tg-npc  tg-quest  tg-shop  tg-level
  ↓
tg-save     ← 序列化 game 动态状态
  ↓
tg-config   ← Org 解析 + 构建 registry + game
  ↓
tg-config-gen ← 辅助生成命令
  ↓
tg-mode     ← Emacs UI
  ↓
tg.el       ← 入口，require 全部
```

## PEG 解析器（tg-parser.el）

### 语法定义

```elisp
(defvar tg-grammar
  (peg-parse
   ((S            verb (+ (and ws-word (opt (and preposition (+ ws-word))))))
    (verb         (or (string "pick up") (string "put down")
                      (string "look at") (string "listen to")
                      (regexp "[a-z]+")))
    (ws-word      (opt (and article (string " "))) (regexp "[a-z]+"))
    (preposition  (or (string " on ") (string " with ") (string " to ")
                      (string " in ") (string " by ") (string " under ")))
    (article      (or (string "the ") (string "a ") (string "an "))))))
```

### 解析流水线

```
1. PEG 匹配原始输入 → 原始 token 列表
2. normalize-verb：get→take, l→look, x→examine, i→inventory, q→quit, walk→go, pick up→take, put down→drop, look at→examine, listen to→listen, equip→wear, consume→eat, hit→attack, fight→attack, speak→talk
3. 方向检测：north/n/ne 等方向词 → 转为 go action + direction
4. build-vocab：当前房间 + 背包 + 嵌套容器/支持物的对象名和同义词 + 方向词 + all/everything
5. classify：词汇表匹配，最后一个匹配名词 = 中心词，前面的 = 形容词
6. resolve：名词/同义词 → object symbol
7. 输出标准化 AST
```

### AST 格式

```elisp
;; 正常动作
(:action take :do-key :rusty-key :do-adj ("rusty") :prep nil :io-key nil)
(:action place :do-key :bird :do-adj nil :prep "in" :io-key :nest)

;; 方向移动
(:action go :direction north)

;; 批量操作
(:action take :do-key :all :do-adj nil)

;; 错误
(:error :unknown-action :verb "xyz")
(:error :unknown-noun :word "foobar")
```

### 词汇表构建

```elisp
(defun tg-build-vocabulary (game)
  "从当前 room 和 player inventory 构建可见物品词汇表。"
  (let* ((room (tg-get-room (tg-game-get game :location)))
         (room-contents (tg-room-all-visible-objects room))
         (inv (tg-game-get game :inventory))
         (words nil))
    ;; 房间内对象（含 open 容器内容、supporter 上的物品）
    (dolist (sym room-contents)
      (let ((obj (tg-get-object sym)))
        (when obj
          (push (cons (tg-object-name obj) sym) words)
          (dolist (syn (tg-object-synonyms obj))
            (push (cons syn sym) words))
          (dolist (adj (tg-object-adjectives obj))
            (push adj words)))))
    ;; 背包中的对象
    (dolist (sym inv)
      (let ((obj (tg-get-object sym)))
        (when obj
          (push (cons (tg-object-name obj) sym) words)
          (dolist (syn (tg-object-synonyms obj))
            (push (cons syn sym))))))
    ;; 方向词 + 特殊词
    (dolist (dir '(north south east west up down northeast northwest southeast southwest))
      (push (cons (symbol-name dir) dir) words))
    (push (cons "all" 'all) words)
    (push (cons "everything" 'all) words)
    words))
```

## Handler Chain 调度引擎（tg-commands.el）

### 调度顺序

```elisp
(defun tg-dispatch (ast game)
  (cond
   ((tg-handle-error ast game) nil)            ;; 1. 错误处理
   ((tg-run-room-before ast game) nil)         ;; 2. 房间 before-handler
   ((tg-run-io-handler ast game) nil)          ;; 3. 间接宾语 handler
   ((tg-run-do-handler ast game) nil)          ;; 4. 直接宾语 handler
   (t
    (tg-run-action ast game)                   ;; 5. 动词默认 handler
    (tg-run-room-after ast game)))             ;; 6. after-handler（仅 action 后）
  (unless (member (plist-get ast :action) tg-passive-actions)
    (tg-npc-run-behaviors game))              ;; 7. NPC 行为（非被动命令后）
  (unless (member (plist-get ast :action) tg-passive-actions)
    (tg-buffs-tick game)                     ;; 8. 临时效果倒计时
    (tg-game-incf game :turns)))              ;; 9. 回合计数
```

### 执行规则

| 步骤 | 返回 t | 返回 nil |
|---|---|---|
| error handler | 停止，不执行后续 | 继续下一步 |
| room before | 停止，不执行 after | 继续下一步 |
| indirect-object | 停止，不执行 after | 继续下一步 |
| direct-object | 停止，不执行 after | 继续下一步 |
| action handler | 执行 after | （不应到达） |
| room after | 始终执行 | — |

### Handler 函数约定

```elisp
;; 每个 handler 的签名: (lambda (ast game) => t/nil)
;; 返回 t: 动作已处理，停止传播
;; 返回 nil: 未处理，交给下一个 handler

;; 对象 handler 示例
(lambda (ast game)
  (let ((action (plist-get ast :action)))
    (cond
     ((eq action 'examine)
      (tg-message "小鸟叽叽叫了一声，看起来很害怕。")
      t)                    ;; 已处理
     ((eq action 'take)
      (tg-message "小鸟太重了，你搬不动。")
      t)                    ;; 拦截 take
     (t nil))))             ;; 其他动作交给默认 handler
```

### 被动命令列表

不触发 NPC 行为、不计回合的命令：

```elisp
(defvar tg-passive-actions '(look examine inventory status help quests quest save load quit))
```

### `all` 的处理

`take all` / `drop all` 在 action handler 层展开：
1. 收集所有合法目标（`take all` = 房间内所有 takeable 对象）
2. 逐个构建子 AST，逐个走完整 handler chain
3. 每个 t 结果的消息单独输出

## 对象模型（tg-object.el）

### 数据结构

```elisp
(cl-defstruct tg-object
  symbol          ;; 唯一标识符（symbol）
  name            ;; 显示名称 "生锈的钥匙"
  synonyms        ;; 解析用同义词 (key 钥匙)
  desc            ;; 简短描述 "地上有一把生锈的钥匙。"
  first-desc      ;; 首次描述（nil 则用 desc）
  adjectives      ;; 解析用形容词 (rusty 生锈的)
  contents        ;; 容器内的子对象（symbol list）
  supports        ;; 支持物上的子对象（symbol list）
  props           ;; 属性集合 (container supporter scenery static wearable edible readable)
  state           ;; 容器开闭状态: open / closed / locked / nil（非容器为 nil）
  key             ;; 解锁所需钥匙的 object symbol（nil 表示无需钥匙/任何方式可开）
  effects         ;; 效果列表 ((hp . 20) (attack . 3 :duration 10) ...)
                  ;; - 无 :duration: 永久生效（wearable 动态叠加，edible 吃下后永久写 attr）
                  ;; - 有 :duration N: 临时效果（吃下后 N 回合有效），存入 :active-buffs
                  ;; - non-wearable/non-edible 对象忽略此字段
  handler)        ;; (lambda (ast game) => t/nil)
```

### 属性列表与行为

| 属性 | 效果 |
|---|---|
| `container` | 可以装东西，`contents` 生效，`state` 控制开闭 |
| `supporter` | 东西可放在上面，`supports` 生效 |
| `scenery` | 背景装饰：不可取、不出现在物品列表描述中、但进入词汇表 |
| `static` | 不可移动（不能 take），但出现在描述中 |
| `wearable` | 可装备（`wear` 动词可用），装备效果通过 `effects` 字段定义，combat 时动态叠加到玩家 attr |
| `edible` | 可食用（`eat` 动词可用）。食用后物品消耗。永久 effects（无 `:duration`）写入 attr；临时 effects（带 `:duration N`）添加到 `:active-buffs`，N 回合后自动撤销 |
| `readable` | 可阅读（`read` 动词可用） |

### 容器状态机

```
open ──close──→ closed ──lock──→ locked
  ↑                         │
  └──open←──unlock←─────────┘
```

- `open`：可取出/放入物品
- `closed`：不可取出/放入，可 `open` 打开
- `locked`：不可取出/放入，需 `unlock with <key>` 解锁到 `closed`，再 `open`
- 非 container 对象：`state` 为 `nil`，不参与开闭

### 核心谓词

```elisp
(tg-object-takeable-p obj)     ;; (not (or scenery supporter static))
(tg-object-visible-p obj)      ;; 非 scenery，且在可见范围内
(tg-object-accessible-p obj)   ;; 可见 且 (非容器内 或 容器 state=open 或 在 supporter 上)
(tg-object-container-p obj)    ;; props 含 container
(tg-object-supporter-p obj)    ;; props 含 supporter
(tg-object-open-p obj)         ;; state 为 open
(tg-object-locked-p obj)       ;; state 为 locked
```

### 核心操作

```elisp
(tg-object-find sym)                    ;; 在全局注册表中查找
(tg-object-find-parent sym game)        ;; 找对象所在的父容器/supporter
(tg-object-find-in-room sym game)       ;; 在当前房间（含嵌套）中查找
(tg-object-find-in-inventory sym game)  ;; 在背包（含嵌套）中查找
(tg-object-move sym from-list to-list)  ;; 移动对象引用
(tg-object-all-visible game)            ;; 当前可见的所有对象 symbol 列表
```

## 房间与地图（tg-room.el）

### 数据结构

```elisp
(cl-defstruct tg-room
  symbol            ;; 唯一标识符
  name              ;; 房间名称 "森林入口"
  desc              ;; 完整描述
  short-desc        ;; 简短描述（nil 则用 name）
  exits             ;; ((north . forest-path) (south . village) ...)
  contents          ;; 房间中的对象（symbol list）
  creatures         ;; 房间中的生物（symbol list）
  before-handler    ;; (lambda (ast game) => t/nil)
  after-handler     ;; (lambda (ast game) => t/nil)
  visit-count)      ;; 访问次数
```

### 方向系统

10 个方向，每个方向有标准名和缩写：

```elisp
(defconst tg-directions
  '((north . n) (south . s) (east . e) (west . w)
    (up . u) (down . d)
    (northeast . ne) (northwest . nw)
    (southeast . se) (southwest . sw)))
```

parser 中方向词直接识别，AST 设 `:action go` + `:direction north`。

### 房间描述渲染

```elisp
(defun tg-describe-room (room game)
  (let ((first-time (= (tg-room-visit-count room) 0)))
    (tg-room-visit room)  ;; incf visit-count
    (concat
     ;; 1. 房间描述
     (if first-time (tg-room-desc room)
       (or (tg-room-short-desc room) (tg-room-name room)))
     "\n"
     ;; 2. 对象描述（非 scenery 对象）
     (tg-describe-room-objects room game)
     ;; 3. NPC 列表
     (tg-describe-room-creatures room game))))
```

对象描述规则：
- **非 scenery 对象**：显示 `desc`（首次）或 `name`（后续），递归展示 open 容器内容和 supporter 上的物品
- **scenery 对象**：不单独列出（仅首次时体现在房间描述中）
- **容器内容**：open 容器显示 "里面有什么"，closed/locked 容器不显示内容

### Exit 查找

```elisp
(defun tg-room-exit (room direction)
  "查找 ROOM 在 DIRECTION 方向的出口房间 symbol。"
  (cdr (assoc direction (tg-room-exits room))))
```

### 完整内容查找

```elisp
(defun tg-room-all-visible-objects (room)
  "获取 ROOM 中所有可见对象（含 open 容器内容、supporter 上的物品）。"
  (let ((result (copy-sequence (tg-room-contents room))))
    (dolist (sym (tg-room-contents room))
      (let ((obj (tg-get-object sym)))
        (when obj
          (when (tg-object-container-p obj)
            (when (tg-object-open-p obj)
              (setq result (append result (tg-object-contents obj)))))
          (when (tg-object-supporter-p obj)
            (setq result (append result (tg-object-supports obj)))))))
    result))
```

## Creature 系统（tg-creature.el）

### 数据结构

```elisp
(cl-defstruct tg-creature
  symbol          ;; 唯一标识符
  name            ;; 显示名称 "哥布林"
  desc            ;; 描述 "一个绿皮小怪物蹲在角落里。"
  synonyms        ;; 解析用同义词 (goblin 哥布林)
  attr            ;; 属性 alist ((hp . 20) (attack . 5) (defense . 2) (exp . 0) (level . 1) ...)
  inventory       ;; 携带物品（symbol list）
  equipment       ;; 装备栏（symbol list）
  exp-reward      ;; 击败后经验奖励（nil 则按 attr 自动计算）
  behaviors       ;; 行为规则 ((condition . action) ...)
  death-trigger   ;; 死亡触发器符号
  shopkeeper      ;; 是否为商人
  handler)        ;; (lambda (ast game) => t/nil)
```

### 玩家就是 Creature

玩家是第一个注册的 creature，通过 `tg-game` 的 `:player` 字段引用其 symbol。玩家与 NPC 共用同一套结构，区别仅在于：
- 玩家没有 `behaviors`、`death-trigger`、`exp-reward`
- 玩家有 `exp`/`level`/`bonus-points` 等属性（NPC 可选有）

### 约定属性

attr 是一个 alist，游戏作者可自由定义属性名。约定属性：

| 属性 | 说明 |
|---|---|
| `hp` | 生命值，≤ 0 表示死亡 |
| `attack` | 攻击力 |
| `defense` | 防御力 |
| `exp` | 当前经验值 |
| `level` | 当前等级 |
| `bonus-points` | 可分配技能点 |
| `gold` | 金币 |

### 核心操作

```elisp
(tg-creature-dead-p creature)              ;; hp ≤ 0
(tg-creature-take-effect creature effect)  ;; 施加 (attr . delta) 效果
(tg-creature-add-item creature sym)        ;; 添加物品
(tg-creature-remove-item creature sym)     ;; 移除物品
(tg-creature-has-item creature sym)        ;; 是否拥有物品
```

## Action 系统（tg-action.el）

### Action 定义

```elisp
(cl-defstruct tg-action
  id              ;; 动作标识符（symbol）:take :drop :go ...
  synonyms        ;; 触发词 ("take" "get" "pick up")
  handler)        ;; (lambda (ast game) => t/nil)

(defun tg-register-action (id synonyms handler)
  "注册动作及其触发词。"
  (dolist (syn synonyms)
    (puthash syn (make-tg-action :id id :synonyms synonyms :handler handler)
             tg--action-words)))

(defun tg-find-action (word)
  "根据输入词查找 action。"
  (gethash word tg--action-words))
```

### 完整内置动词表

| 动作 | 触发词 | 说明 |
|---|---|---|
| `go` | `go`, `walk`, 方向词 | 移动到相邻房间 |
| `look` | `look`, `l` | 查看当前房间 |
| `examine` | `examine`, `x`, `look at` | 检查对象/NPC |
| `take` | `take`, `get`, `pick up` | 拾取物品，支持 `take all` |
| `drop` | `drop`, `put down` | 丢弃物品，支持 `drop all` |
| `place` | `put`, `place` | 放置物品到容器/支持物上 |
| `open` | `open` | 打开 closed 容器 |
| `close` | `close` | 关闭 open 容器 |
| `unlock` | `unlock` | 解锁 locked 容器（需钥匙） |
| `wear` | `wear`, `equip` | 装备物品 |
| `eat` | `eat`, `consume` | 食用物品 |
| `read` | `read` | 阅读物品 |
| `inventory` | `inventory`, `i` | 查看背包 |
| `attack` | `attack`, `hit`, `fight` | 攻击 NPC |
| `talk` | `talk`, `speak` | 与 NPC 对话 |
| `buy` | `buy` | 购买商品 |
| `sell` | `sell` | 出卖物品 |
| `shop` | `shop` | 查看商店 |
| `status` | `status` | 查看自身状态 |
| `upgrade` | `upgrade` | 分配属性点 |
| `quests` | `quests` | 查看任务列表 |
| `quest` | `quest` | 查看指定任务 |
| `accept` | `accept` | 接受任务 |
| `save` | `save` | 保存游戏 |
| `load` | `load` | 读取存档 |
| `help` | `help` | 查看帮助 |
| `quit` | `quit`, `q` | 退出游戏 |

### 动词标准化映射

```elisp
(defconst tg-verb-aliases
  '(("get" . "take") ("pick up" . "take") ("walk" . "go")
    ("l" . "look") ("x" . "examine") ("look at" . "examine")
    ("i" . "inventory") ("q" . "quit") ("put down" . "drop")
    ("equip" . "wear") ("consume" . "eat") ("hit" . "attack")
    ("fight" . "attack") ("speak" . "talk")))
```

### 战斗流程（attack action handler）

```
1. 验证目标在当前房间
2. 计算有效攻击力: player.attack + sum(equipment effects.attack) + sum(active buffs)
3. 计算有效防御力: player.defense + sum(equipment effects.defense)
4. 伤害 = max(1, effective_attack - target.defense)
5. 施加伤害
6. 若目标死亡:
   - 其 inventory 和 equipment 中所有物品掉落至当前房间
   - 从房间 creatures 列表中移除
   - 触发 death-trigger
   - 发放 exp 奖励
   - 调用 (tg-track-quest 'kill target-creature-symbol) 更新 kill 类任务
7. 若目标存活:
   - 敌人反击: max(1, target.attack - player_effective_defense)
   - 施加反击伤害
   - 若玩家死亡 → 游戏结束
   - 否则显示双方 HP
```

装备加成采用动态计算：attr 存储基础值，每次 combat 遍历 equipment 和 `:active-buffs` 列表叠加 effects。卸下装备/移除 buff 后自动恢复，无需反向计算原始值。

### 临时效果生命周期

```elisp
(defun tg-buffs-tick (game)
  "回合结束时递减所有临时效果的剩余回合。"
  (let ((buffs (tg-game-get game :active-buffs)))
    (dolist (buff buffs)
      (cl-decf (plist-get (cdr buff) :remaining)))
    (tg-game-put game :active-buffs
                 (cl-remove-if (lambda (b) (<= (plist-get (cdr b) :remaining) 0))
                               buffs))))

(defun tg-buffs-apply (game effects)
  "应用效果到 buff 列表。永久效果直接写 attr，临时效果进入 :active-buffs。"
  (dolist (eff effects)
    (if-let ((duration (plist-get (cdr eff) :duration)))
        (push (cons (car eff)
                    (list :delta (cdr eff) :remaining duration :duration duration))
              (tg-game-get game :active-buffs))
      ;; 永久效果：直接写入 player attr
      (tg-creature-take-effect (tg-player game) (cons (car eff) (cadr eff))))))
```

## 对话状态机（tg-dialog.el）

### 数据结构

```elisp
(cl-defstruct tg-dialog-state
  "对话状态节点。NPC 可以有多个状态节点，形成对话网。"
  node-id           ;; 唯一节点 ID（symbol）
  npc-symbol        ;; 所属 NPC
  greeting          ;; 进入此节点时 NPC 说的话
  options)          ;; (tg-dialog-option ...)

(cl-defstruct tg-dialog-option
  "对话选项。"
  text              ;; 选项文字 "问路"
  response          ;; NPC 回应 "往北走就是城堡。"
  condition         ;; 可见条件（nil = 总是显示）
  effects           ;; 选择后效果 ((exp . 50) (item . :sword) ...)
  next-node)        ;; 下一个 node-id（nil = 结束对话）
```

### 对话流程

```
talk <npc-name>
  → 查找该 NPC 的入口 dialog-state（npc-symbol 对应的第一个节点）
  → 显示 greeting + 编号选项列表
  → 玩家输入编号
  → 过滤可见选项（condition 求值）
  → 显示 response，执行 effects
  → next-node 非 nil → 跳转到新 state，显示新 greeting + 选项
  → next-node 为 nil → 结束对话，清除 pending 状态
```

### 内联 DSL 解析

对话选项使用内联 DSL，格式为：

```
- <text> :: <response> → <effects> → <next-node>
```

解析规则：
- `- ` 开头标记一个选项
- ` :: ` 分隔选项文字和 NPC 回应
- ` → ` 分隔回应、effects 和下一节点（两个 `→`）
- `<effects>` 是 S-expression list：`((quest-activate . find-dragon-scale))` 或 `nil`
- `<next-node>` 是 node-id symbol 或 `nil`

```elisp
(defun tg-config-parse-dialog-option (org-body)
  "从 Org body 文本解析 dialog option 列表。"
  (let ((lines (split-string org-body "\n" t))
        (options nil))
    (dolist (line lines)
      (when (string-match "^- \\([^:]+\\) :: \\([^→]+\\) → \\([^→]+\\) → \\(.+\\)$" line)
        (let ((text (string-trim (match-string 1 line)))
              (response (string-trim (match-string 2 line)))
              (effects (read (match-string 3 line)))
              (next-node (read (match-string 4 line))))
          (push (make-tg-dialog-option
                 :text text :response response
                 :effects effects :next-node next-node)
                options))))
    (nreverse options)))
```

### Pending 状态

```elisp
(defvar tg-dialog-pending nil "当前挂起的 dialog-state（nil = 无对话）")
```

`tg-mode.el` 中，如果 `tg-dialog-pending` 非 nil，回车键触发 `tg-dialog-handle-choice` 而非正常命令解析。

### 条件求值器

```elisp
(defun tg-dialog-eval-condition (expr)
  (pcase (car-safe expr)
    ('nil t)
    ('quest-active    (and (tg-get-quest (cadr expr))
                           (eq (tg-quest-status (tg-get-quest (cadr expr))) 'active)))
    ('quest-completed (and (tg-get-quest (cadr expr))
                           (eq (tg-quest-status (tg-get-quest (cadr expr))) 'completed)))
    ('has-item        (tg-creature-has-item (tg-player) (cadr expr)))
    ('and             (cl-every #'tg-dialog-eval-condition (cdr expr)))
    ('or              (cl-some #'tg-dialog-eval-condition (cdr expr)))
    ('not             (not (tg-dialog-eval-condition (cadr expr))))))
```

### Effects 执行

```elisp
(defun tg-dialog-apply-effects (effects)
  (dolist (eff effects)
    (pcase (car eff)
      ('exp            (tg-add-exp (tg-player) (cdr eff)))
      ('item           (tg-creature-add-item (tg-player) (cdr eff)))
      ('gold           (tg-creature-take-effect (tg-player) (cons 'gold (cdr eff))))
      ('bonus-points   (tg-creature-take-effect (tg-player) (cons 'bonus-points (cdr eff))))
      ('quest-activate (tg-quest-activate (cdr eff)))
      ('trigger        (tg-call-trigger (cdr eff))))))
```

## NPC 行为引擎（tg-npc.el）

### 行为规则

每个 NPC 有 `(condition . action)` 对列表，每回合最多执行第一个匹配的行为。

```elisp
;; 行为条件
(always)                    ;; 总是
(hp-below N)                ;; HP < N
(hp-above N)                ;; HP > N
(player-in-room)            ;; 玩家在同一房间
(and cond1 cond2 ...)      ;; 且
(or cond1 cond2 ...)       ;; 或
(not cond)                  ;; 非

;; 行为动作
(attack)                    ;; 攻击玩家
(say "text")                ;; 说话
(move direction)            ;; 移动（direction 可以是 random）
(buff attr value)           ;; 增强 attr +value
(debuff attr value)         ;; 削弱玩家 attr -value
```

### 执行时机

```elisp
(defun tg-npc-run-behaviors (game)
  "在 tg-dispatch 末尾调用。只对非被动命令执行。"
  (let ((room (tg-get-room (tg-game-get game :location))))
    (dolist (npc-sym (tg-room-creatures room))
      (let ((npc (tg-get-creature npc-sym)))
        (when (and npc
                   (not (eq npc-sym (tg-game-get game :player)))
                   (not (tg-creature-dead-p npc)))
          (cl-block behavior-loop
            (dolist (rule (tg-creature-behaviors npc))
              (when (tg-npc-eval-condition npc (car rule))
                (tg-npc-execute-action npc (cdr rule))
                (cl-return-from behavior-loop)))))))))
```

### NPC 移动

`(move direction)` 使用房间的 exits 查找目标房间，更新源房间和目标房间的 creatures 列表。`(move random)` 随机选择一个有效出口。

## 周边系统

### 任务系统（tg-quest.el）

```elisp
(cl-defstruct tg-quest
  symbol description type target count progress
  rewards status description-complete)
```

与 TGM 1.0 一致：
- type: `kill` / `collect` / `explore` / `talk`
- status: `inactive` → `active` → `completed`
- 进度在各 action handler 中直接调用 `tg-track-quest` 推进，调用点：
  - `kill`: attack handler 目标死亡后
  - `collect`: take handler 拾取后
  - `explore`: go handler 进入房间后
  - `talk`: talk handler 对话结束后
- **Handler 拦截与 quest tracking**：当对象/房间 handler 在链中返回 t 拦截了动作（如自定义 take handler），action handler 不会执行，`tg-track-quest` 也不会被调用。这是预期行为——作者若需追踪 quest，应在自定义 handler 中手动调用 `tg-track-quest`
- 完成时发放 rewards（exp/item/bonus-points/trigger）

### 商店系统（tg-shop.el）

```elisp
(cl-defstruct tg-shop
  npc-symbol        ;; 商人 NPC symbol
  sell-rate         ;; 卖出折价率（0.5 = 半价回收）
  goods)            ;; ((item-symbol . price) ...)
```

`buy`/`sell` 动词在 action handler 中实现，通过 `shopkeeper` 属性判断当前房间是否有商人。金币存在玩家 creature 的 attr 中 `(gold . N)`。

### 等级系统（tg-level.el）

与 TGM 1.0 一致：
- 经验表可配置 `(0 100 250 500 850 1300 1900 2700 3800 5000)`
- 升级时自动提升 `auto-upgrade-attrs` 中的属性
- 获得 `bonus-points` 供 `upgrade` 命令分配

## 全局注册表（tg-registry.el）

```elisp
;; 注册表容器
(defvar tg--rooms     (make-hash-table :test 'eq))  ;; symbol → tg-room
(defvar tg--objects   (make-hash-table :test 'eq))  ;; symbol → tg-object
(defvar tg--creatures (make-hash-table :test 'eq))  ;; symbol → tg-creature
(defvar tg--actions   (make-hash-table :test 'eq))  ;; symbol → tg-action
(defvar tg--dialogs   (make-hash-table :test 'eq))  ;; node-id → tg-dialog-state
(defvar tg--shops     (make-hash-table :test 'eq))  ;; npc-symbol → tg-shop
(defvar tg--quests    (make-hash-table :test 'eq))  ;; symbol → tg-quest
(defvar tg--action-words (make-hash-table :test 'equal)) ;; string → tg-action（快速查找）

;; 通用存取函数
(defun tg-get-room (sym)         (gethash sym tg--rooms))
(defun tg-get-object (sym)       (gethash sym tg--objects))
(defun tg-get-creature (sym)     (gethash sym tg--creatures))
(defun tg-get-action (sym)       (gethash sym tg--actions))
(defun tg-get-dialog (sym)       (gethash sym tg--dialogs))
(defun tg-get-shop (sym)         (gethash sym tg--shops))
(defun tg-get-quest (sym)        (gethash sym tg--quests))
(defun tg-register-room (sym r)  (puthash sym r tg--rooms))
(defun tg-register-object (sym o) (puthash sym o tg--objects))
(defun tg-register-creature (sym c) (puthash sym c tg--creatures))
;; ... 类似
```

## Game 动态状态（tg-game.el）

```elisp
(defvar tg-game nil "当前游戏动态状态哈希表")

(defun tg-new-game (title &optional author)
  "创建新游戏实例。"
  (let ((g (make-hash-table :test 'eq)))
    (puthash :title     title g)
    (puthash :author    author g)
    (puthash :state     'starting g)
    (puthash :turns     0 g)
    (puthash :location  nil g)         ;; 当前房间 symbol
    (puthash :player    nil g)         ;; 玩家 creature symbol
    (puthash :inventory nil g)         ;; 玩家物品列表（symbol list）
    (puthash :equipment nil g)         ;; 玩家装备列表（symbol list）
    (puthash :active-buffs nil g)      ;; 活跃临时效果 (((hp . 20) :remaining 3) ...)
    g))

(defun tg-game-get (game key)     (gethash key game))
(defun tg-game-put (game key val) (puthash key val game))
(defun tg-game-incf (game key)    (cl-incf (gethash key game 0)))
```

## 存档系统（tg-save.el）

### 设计思路

沿用 TGM 1.0 的"重载配置 + 恢复动态状态"模式。触发器/handler 在配置文件中定义，重载配置即恢复所有函数，不需要函数查表。

### 保存数据结构

```elisp
;; 存档文件内容（prin1 序列化）
((:config-dir . "/path/to/game-config/")
 (:turns . 42)
 (:location . courtyard)
 (:state . in-progress)
 (:player . player-symbol)
 (:player-attr . ((hp . 80) (attack . 12) (defense . 5) (exp . 350) ...))
 (:player-inventory . (sword potion))
 (:player-equipment . (helmet))
 (:active-buffs . (((attack . 3) :remaining 5) ((hp . 20) :remaining 0)))
 (:rooms . ((courtyard (visit-count . 3) (contents torch key))
            (hall (visit-count . 1) (creatures goblin))))
 (:objects . ((chest (:state . open) (:contents . (diamond)))
              (barrel (:state . closed) (:contents . (fish)))))
 (:creatures . ((goblin (attr ((hp . 5) (attack . 5) ...)) (inventory))
               (old-man (attr ((hp . 50) ...)) (inventory potion))))
 (:shops . ((old-man (sell-rate . 0.5) (goods ((potion . 30))))))
 (:quests . ((find-scale (status . active) (progress . 0)))))
```

### 保存/加载流程

```elisp
(defun tg-save-game (filepath)
  "收集动态状态 → prin1 写入文件。"
  ...)

(defun tg-load-game (filepath)
  "1. 读入存档数据
   2. 从 :config-dir 重载所有配置文件（恢复 rooms/objects/creatures 定义和触发器）
   3. 用存档数据覆盖动态字段（visit-count、contents、creatures attr 等）
   4. 恢复玩家状态")
```

## Org-mode 配置格式（tg-config.el）

### 完整示例

```org
#+TITLE: 迷雾森林
#+AUTHOR: DarkSun
#+START: forest-entrance

* Rooms
** forest-entrance
:PROPERTIES:
:name: 森林入口
:desc: 你站在一片幽暗的森林入口。高大的树木遮天蔽日，一条小径蜿蜒向北。
:short-desc: 森林入口
:exits: ((north . forest-path) (south . village))
:contents: (rusty-key torch)
:creatures: (guard old-man)
:END:

** forest-path
:PROPERTIES:
:name: 林中小路
:desc: 小路在密林中蜿蜒。地上散落着奇怪的蘑菇。东边似乎有什么东西在发光。
:exits: ((south . forest-entrance) (north . clearing) (east . glowing-grove))
:contents: (mushroom)
:END:

* Objects
** rusty-key
:PROPERTIES:
:name: 生锈的钥匙
:synonyms: (钥匙 key)
:desc: 地上有一把生锈的钥匙。
:adjectives: (生锈的 rusty)
:props: (static)
:END:

** wooden-chest
:PROPERTIES:
:name: 木箱子
:synonyms: (箱子 chest 盒子 box)
:desc: 角落里放着一个破旧的木箱子。
:adjectives: (木 wooden 破旧的)
:props: (container)
:state: closed
:key: rusty-key
:contents: (gold-coin)
:END:

** gold-coin
:PROPERTIES:
:name: 金币
:synonyms: (金币 coin 钱 money)
:desc: 一枚闪闪发光的金币。
:END:

** iron-helmet
:PROPERTIES:
:name: 铁头盔
:synonyms: (头盔 helmet)
:desc: 一顶坚固的铁头盔。
:props: (wearable)
:effects: ((defense . 3))
:END:

* Creatures
** player
:PROPERTIES:
:name: 冒险者
:desc: 一个勇敢的冒险者。
:attr: ((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0) (gold . 20))
:END:

** goblin
:PROPERTIES:
:name: 哥布林
:desc: 一个绿皮小怪物蹲在角落里，恶狠狠地盯着你。
:synonyms: (goblin)
:attr: ((hp . 20) (attack . 5) (defense . 2))
:exp-reward: 30
:behaviors: ((always . (attack)))
:death-trigger: goblin-death
:END:

** old-man
:PROPERTIES:
:name: 老人
:desc: 一位白发苍苍的老人坐在树下。他似乎在等待着什么。
:synonyms: (老人)
:attr: ((hp . 50) (attack . 0) (defense . 0))
:shopkeeper: t
:behaviors: ((always . (say "咳咳...")))
:END:

* Dialogs
** old-man-intro
:PROPERTIES:
:npc: old-man
:greeting: "年轻人，你能帮老朽一个忙吗？"
:END:
- 什么事？ :: "森林深处有一枚龙鳞，帮我取来。" → ((quest-activate . find-dragon-scale)) → old-man-waiting
- 没空 :: "那算了。" → nil → nil

** old-man-waiting
:PROPERTIES:
:npc: old-man
:greeting: "你找到龙鳞了吗？"
:END:
- 给你龙鳞 :: "太好了！这是你的报酬。" → ((exp . 200) (item . magic-ring)) → nil
- 还没有 :: "继续找吧。" → nil → nil

* Shops
** old-man-shop
:PROPERTIES:
:npc: old-man
:sell-rate: 0.5
:END:
- health-potion :: 30
- sword :: 100
- shield :: 80

* Quests
** find-dragon-scale
:PROPERTIES:
:desc: 在森林深处找到龙鳞，交给老人。
:type: collect
:target: dragon-scale
:count: 1
:rewards: ((exp . 200) (item . magic-ring))
:END:

* Levels
:PROPERTIES:
:exp-table: (0 100 250 500 850 1300 1900 2700 3800 5000)
:bonus-points-per-level: 3
:auto-upgrade-attrs: ((hp . 5))
:END:
```

### Handler 定义

Org 文件中不适合写 lambda。方案：

1. **简单 handler**：用属性引用 elisp 函数名
   ```org
   :handler: my-chest-handler
   ```
2. **复杂 handler**：在单独的 .el 文件中定义，Org 中只引用符号
   ```elisp
   ;; handlers.el（与 Org 文件同目录）
   (defun my-chest-handler (ast game)
     (when (eq (plist-get ast :action) 'open)
       (tg-message "箱子嘎吱一声打开了。")
       t))
   ```

tg-config 加载时：先加载同目录的 `handlers.el`（若存在），再解析 Org 文件，handler 字段通过 `intern` + `fboundp` 解析为函数引用。

### Org 解析流程

```elisp
(defun tg-config-load (org-file)
  "从 ORG-FILE 加载游戏配置。"
  ;; 1. 加载同目录 handlers.el（若存在）
  (let ((handlers-file (expand-file-name "handlers.el" (file-name-directory org-file))))
    (when (file-exists-p handlers-file)
      (load handlers-file)))
  ;; 2. 解析 Org 文件
  (let ((tree (with-temp-buffer
                (insert-file-contents org-file)
                (org-parse-buffer))))
    ;; 3. 读取全局属性
    (setq tg-title (org-global-props "TITLE"))
    (setq tg-author (org-global-props "AUTHOR"))
    (setq tg-start-room (org-global-props "START"))
    ;; 4. 解析各 section（Rooms, Objects, Creatures, ...）
    ;;    按一级标题分类，二级标题为各实体
    ;;    PROPERTIES drawer 中读取各字段
    ...))
```

## 辅助生成命令（tg-config-gen.el）

### 向导命令

```elisp
(tg-gen-game)
```

交互式流程：title → author → start room → 生成完整 Org 文件模板，包含 `#+TITLE`、`#+AUTHOR`、`#+START` 头部、一个示例 Room section、占位的 Objects/Creatures section。

### 逐项插入命令

```elisp
(tg-gen-room)          ;; 在光标处插入 Room section 模板
(tg-gen-object)        ;; 插入 Object section 模板
(tg-gen-creature)      ;; 插入 Creature section 模板
(tg-gen-dialog)        ;; 插入 Dialog section 模板
(tg-gen-shop)          ;; 插入 Shop section 模板
(tg-gen-quest)         ;; 插入 Quest section 模板
```

每个命令用 `completing-read` 交互式收集必要字段（name、desc 等），可选字段提供默认值，插入格式化的 Org section。

### 验证命令

```elisp
(tg-validate-config)
```

检查：
- exit 引用的房间是否存在
- container 的 contents 中的对象是否已定义
- Room 的 creatures 中的 NPC 是否已定义
- Dialog 的 next-node 是否存在
- Shop 的 npc 是否有 shopkeeper 属性

## Emacs UI（tg-mode.el）

### 整体结构

单 buffer 模式，上面是游戏输出（只读），下面是命令输入区（带 prompt）。

```
┌─────────────────────────────┐
│ === 迷雾森林 ===            │  ← 只读输出区
│ by DarkSun                  │
│                             │
│ 森林入口                    │
│ 你站在一片幽暗的森林入口... │
│ 地上有一把生锈的钥匙。      │
│                             │
│ > take key                  │  ← prompt + 输入区
│ 拾取了生锈的钥匙。          │
│                             │
│ [森林入口]> _               │  ← 当前输入位置
└─────────────────────────────┘
```

### tg-mode 定义

```elisp
(define-derived-mode tg-mode text-mode "TG"
  "Text Game Maker 游戏模式。"
  (setq-local tg-prompt-start (point-max-marker))
  (local-set-key (kbd "RET") #'tg-send-command)
  (local-set-key (kbd "TAB") #'tg-complete-command)
  (local-set-key (kbd "M-p") #'tg-history-prev)
  (local-set-key (kbd "M-n") #'tg-history-next)
  (setq-local eldoc-documentation-function #'tg-eldoc)
  (eldoc-mode 1))
```

### 命令发送流程

```elisp
(defun tg-send-command ()
  (interactive)
  (let* ((input (tg-read-input)))        ;; 读取 prompt 后的文本
    (tg-clear-input)
    (cond
     (tg-dialog-pending
      (tg-dialog-handle-choice input))
     (t
      (let* ((ast (tg-parse input)))     ;; PEG 解析
        (tg-dispatch ast tg-game)))      ;; handler chain（内含 NPC 行为和回合计数）
    (tg-render-prompt)))                 ;; 显示新 prompt
```

### 补全系统

```elisp
(defun tg-complete-command ()
  ;; 1. prompt 后为空 → 补全动词名
  ;; 2. 动词后 → 补全当前可见对象/NPC 名称
  ;; 3. 介词后 → 补全间接宾语
  )
```

### Eldoc

输入动词时显示对应 action 的文档字符串。

### 命令历史

```elisp
(defvar tg-command-history nil)
(defvar tg-command-history-max 50)
```

`M-p`/`M-n` 浏览历史，`up`/`down` 同效果。

### 输出接口

```elisp
(defun tg-message (string)
  "向游戏 buffer 输出文本。所有模块统一通过此函数输出。"
  (let ((inhibit-read-only t))
    (insert string "\n")))
```

### Prompt 显示

```elisp
(defun tg-render-prompt ()
  "显示命令提示符。"
  (let ((room-name (tg-room-name (tg-get-room (tg-game-get tg-game :location)))))
    (tg-message (format "[%s]> " room-name))))
```

## 测试策略

### 单元测试覆盖

| 模块 | 测试重点 |
|---|---|
| tg-parser | PEG 语法匹配各种句式；动词标准化；词汇表构建；名词消歧；方向检测；边界输入（空串、乱码） |
| tg-commands | handler chain 传播顺序；before/after 执行时机（after 仅 action 后）；拦截行为；错误处理路径 |
| tg-object | 属性驱动行为（开/关/锁、取出/放入）；容器状态机转换；嵌套对象查找；移动对象；takeable/visible/accessible 判定 |
| tg-room | 方向出口查找；首次/重复访问描述；进出触发器；all-visible-objects 递归查找 |
| tg-creature | 属性操作；死亡判定；物品管理 |
| tg-dialog | 状态机分支；条件可见性；effects 应用；多轮对话跳转 |
| tg-npc | 条件匹配（always/hp-below/复合条件）；行为执行；每回合上限 |
| tg-save | 序列化/反序列化完整；重载配置恢复触发器；回合计数保持 |
| tg-config | Org 解析各 section；属性读取；handler 符号解析 |

### 集成测试

一个最小可玩游戏（3-4 个房间、5-6 个物品含 container/supporter、1 个战斗 NPC、1 个对话 NPC、1 个商人）覆盖完整游戏循环：移动 → 检查 → 拾取 → 开箱 → 对话 → 战斗 → 购买 → 存档 → 读档。

### 测试框架

使用 ERT（Emacs Lisp Regression Testing），每个模块对应一个 `test/tg-<module>-test.el`。

## 与旧版对比

| 维度 | TGM 1.0 | TGM 2.0 |
|---|---|---|
| 命令解析 | split-string 分词 | PEG 自然语言 |
| 动作分发 | tg-defaction 直接调用 + trigger | Handler chain（before → object → action → after） |
| 对象模型 | usable/wearable | 7 种属性 + 容器状态机 |
| 地图 | 2D 矩阵网格 | 方向出口（10 方向） |
| 状态管理 | 分散 defvar/defstruct | 全局注册表 + Game 动态状态 |
| 对话 | 单层选项 | 状态机多轮 |
| 存档 | 重载配置 + 恢复状态 | 同上（沿用验证过的方式） |
| 配置 | 多个 S-expression 文件 | 单个 Org 文件 |
| 模块依赖 | 有循环 | 单向无环 |
| 辅助工具 | 无 | 向导 + 逐项插入 + 配置验证 |

## 不在范围内的内容

1. **图形界面** — 纯文本，不引入 GUI 渲染
2. **多人/网络** — 单机单人
3. **音效/音乐** — 不涉及
4. **光照/黑暗系统** — 本期不实现，后续可加
5. **实时战斗** — 回合制
6. **脚本语言** — 不使用外部 DSL，配置和逻辑都可以用 Elisp 表达
