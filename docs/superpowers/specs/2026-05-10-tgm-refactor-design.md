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
| 状态 | 单一 Game 哈希表 | 集中管理，序列化友好 |
| Handler | 显式 handler 函数 | 类似 ifgame，返回 t/nil 控制传播，简单可调试 |
| 配置 | Org-mode | 直观可读，融入现有 Org-mode 工作流 |
| 存档 | 纯数据 + 函数查表 | 解决闭包序列化问题 |
| 对话 | 状态机 | 支持多轮分支对话，有状态的 NPC |
| 循环 | Emacs 事件驱动 | 利用 Emacs major-mode 事件循环 |

## 模块架构

```
text-game-maker/
├── tg.el                 ;; 入口，require 所有模块
├── tg-parser.el          ;; PEG 语法定义 + 动态词汇表 + AST 构建
├── tg-game.el            ;; Game 状态管理（哈希表 + 操作函数）
├── tg-room.el            ;; Room 定义 + 方向出口 + 进出触发器
├── tg-object.el          ;; Object 定义 + 属性系统 + 处理器
├── tg-action.el          ;; Action 定义 + 内置动词注册
├── tg-commands.el        ;; Handler chain 调度引擎
├── tg-dialog.el          ;; 状态机对话系统
├── tg-npc.el             ;; NPC 行为规则引擎
├── tg-quest.el           ;; 任务追踪
├── tg-shop.el            ;; 商店/交易
├── tg-level.el           ;; 经验/等级
├── tg-save.el            ;; 存档/读档（纯数据）
└── tg-config.el          ;; Org-mode 配置解析器
```

### 依赖关系

单向无循环：

```
tg-game     ← 最底层，状态容器
  ↓
tg-parser   ← 依赖 game 取词汇表
  ↓
tg-action   ← 动词定义
  ↓
tg-commands ← 调度引擎，组合 room/object/action
  ↓  ↓  ↓
tg-room  tg-object  tg-npc
  ↓  ↓  ↓
tg-dialog  tg-quest  tg-shop  tg-level
  ↓
tg-save     ← 序列化 game 状态
  ↓
tg-config   ← Org 解析 + 构建 game
  ↓
tg.el       ← 入口，require 全部
```

## PEG 解析器（tg-parser.el）

### 语法定义

```elisp
(defvar tg-grammar
  (peg-parse
   ((S           : verb (+ (and opt-article opt-adjectives noun))
                       (opt (and preposition (+ (and opt-article opt-adjectives noun)))))
    (verb        : (or (string "pick up") (string "put down")
                       (string "look at") (regexp "\\w+")))
    (noun        : (or direction-word vocabulary-word (string "all") (string "everything")))
    (adjectives  : (list (+ (regexp "\\w+"))))
    (preposition : (or (string "on") (string "in") (string "with")
                       (string "to") (string "by") (string "under"))))
   ...))
```

### 解析流程

1. PEG 匹配原始输入 → 原始 AST
2. 动词标准化：`l` → `look`, `x` → `examine`, `get` → `take`, `walk` → `go`, `i` → `inventory`
3. 从 Game 构建动态词汇表：当前房间内容 + 玩家背包 + 嵌套内容 + 可见方向
4. 名词/形容词匹配，消歧
5. 输出标准化 AST plist：`(:action <action> :do-key <symbol> :io-key <symbol> :preposition <string> :direction <symbol> :error <keyword>)`

### 支持的句式

- `north` / `south` / ... （方向移动）
- `look` / `examine room` / `x bird`
- `take the rusty key` / `get bird`
- `put the bird in the nest`
- `give the key to the guard`
- `open the box with the key`
- `eat the apple`
- `wear the cloak`

### 词汇表构建

```elisp
(defun tg-build-vocabulary (game)
  "从当前 room 和 player inventory 构建可见物品词汇表。"
  (let* ((room (tg-game-get game :location))
         (inv  (tg-game-get game :inventory))
         (words nil))
    (dolist (obj (tg-room-all-objects room game))
      (push (cons (tg-object-name obj) (tg-object-symbol obj)) words)
      (dolist (syn (tg-object-synonyms obj))
        (push (cons syn (tg-object-symbol obj)) words)))
    words))
```

## Handler Chain 调度引擎（tg-commands.el）

### 调度函数

```elisp
(defun tg-dispatch (ast game)
  "按优先级依次尝试 handler。返回 t 停止传播，nil 继续。"
  (or (tg-handle-error ast game)           ;; 1. 未知动词/名词
      (tg-run-room-before ast game)        ;; 2. 房间 before-handler
      (tg-run-indirect-object ast game)    ;; 3. 间接宾语 handler
      (tg-run-direct-object ast game)      ;; 4. 直接宾语 handler
      (tg-run-action ast game))            ;; 5. 动词默认 handler
  ;; after-handler 始终执行
  (tg-run-room-after ast game))
```

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

## 对象属性系统（tg-object.el）

### 数据结构

```elisp
(cl-defstruct tg-object
  "游戏中的物品实体。"
  symbol          ;; 唯一标识符（keyword）
  name            ;; 显示名称
  synonyms        ;; 解析用的同义词列表
  desc            ;; 简短描述 "有一把生锈的钥匙。"
  first-desc      ;; 首次遇到描述（nil 则用 desc）
  adjectives      ;; 解析用的形容词列表
  contents        ;; 包含的子对象（container 属性下）
  supports        ;; 支撑的子对象（supporter 属性下）
  props           ;; 属性集合
  handler)        ;; (lambda (ast game) => t/nil)
```

### 属性列表与行为

| 属性 | 效果 |
|---|---|
| `container` | 可以装东西（`contents` 生效） |
| `supporter` | 东西可以放在上面（`supports` 生效） |
| `open` | 容器是打开的（可取出/放入物品） |
| `closed` | 容器是关闭的（必须先 open） |
| `locked` | 容器是锁住的（需要钥匙才能 open） |
| `scenery` | 背景装饰，不可取，不参与物品列表 |
| `static` | 不可移动（不能 take） |
| `wearable` | 可装备（出现在装备栏） |
| `edible` | 可食用（eat 动词可用） |
| `light-source` | 光源（暗房间中可照明） |
| `readable` | 可阅读（read 动词可用） |

### 核心函数

```elisp
(tg-object-accessible-p object)   ;; 对象是否可访问（考虑封闭/锁住）
(tg-object-takeable-p object)     ;; 对象是否可捡起
(tg-object-visible-p object)      ;; 对象是否可见（scenery 不影响）
(tg-object-find-parent key game)  ;; 在房间/背包中找对象的父容器
(tg-object-move obj from to game) ;; 移动对象（处理嵌套）
```

## 房间与地图（tg-room.el）

### 数据结构

```elisp
(cl-defstruct tg-room
  "游戏中的地点。"
  symbol            ;; 唯一标识符
  name              ;; 房间名称
  desc              ;; 完整描述（首次进入显示）
  short-desc        ;; 简短描述（重复进入显示，nil 则用 name）
  exits             ;; ((north . :room-key) (up . :tree-top) (southwest . :garden))
  props             ;; (light dark indoors)
  contents          ;; 房间中的对象（symbol 集合或嵌套结构）
  creatures         ;; 房间中的生物（symbol 集合）
  before-handler    ;; (lambda (ast game) => t/nil)
  after-handler     ;; (lambda (ast game) => t/nil)
  visit-count)      ;; 访问次数
```

### 方向

10 个方向：`north south east west up down northwest northeast southwest southeast`

方向函数 `tg-go` 不是独立的 action handler，而是 handler chain 中的一个特殊分支：方向词在 parser 阶段就被识别，AST 中设置 `:direction` 字段。

### 首次访问 vs 重复访问

```elisp
(cl-defmethod tg-describe-room ((room tg-room) game)
  (let ((first-time (= (tg-room-visit-count room) 0)))
    (tg-room-visit room)  ;; incf visit-count
    (if first-time
        (tg-room-desc room)
      (or (tg-room-short-desc room)
          (tg-room-name room)))))
```

## Game 状态管理（tg-game.el）

### 唯一全局变量

```elisp
(defvar tg-current-game nil
  "当前游戏实例。nil 表示没有活跃游戏。")

(defun tg-new-game (title &optional author)
  "创建新游戏实例。"
  (let ((game (make-hash-table :test 'equal :size 50)))
    (puthash :title    title          game)
    (puthash :author   author         game)
    (puthash :state    'starting      game)
    (puthash :turns    0              game)
    (puthash :location nil            game)
    (puthash :inventory (make-hash-table :test 'equal) game)
    (puthash :rooms    (make-hash-table :test 'equal) game)
    (puthash :objects  (make-hash-table :test 'equal) game)
    (puthash :actions  (make-hash-table :test 'equal) game)
    (puthash :creatures (make-hash-table :test 'equal) game)
    (puthash :quests   (make-hash-table :test 'equal) game)
    (puthash :dialogs  (make-hash-table :test 'equal) game)
    (puthash :shops    (make-hash-table :test 'equal) game)
    (puthash :player   nil            game)
    game))
```

### 存取函数

```elisp
(defun tg-game-get (game key)     (gethash key game))
(defun tg-game-put (game key val) (puthash key val game))
(defun tg-game-incf (game key)    (cl-incf (gethash key game 0)))
```

## 对话状态机（tg-dialog.el）

### 数据结构

```elisp
(cl-defstruct tg-dialog-state
  "对话状态节点。NPC 可以有多个状态节点，形成对话网。"
  node-id           ;; 唯一节点 ID
  npc-symbol        ;; 所属 NPC
  greeting          ;; 开场白（进入此节点时 NPC 说的话）
  prompt            ;; 玩家看到的提示
  options)          ;; (tg-dialog-option ...)

(cl-defstruct tg-dialog-option
  "对话选项。"
  text              ;; 玩家看到的选项文字
  response          ;; NPC 的回应
  condition         ;; 可见条件：nil / (quest-active sym) / (quest-completed sym) / (has-item sym) / (and ...) / (or ...)
  effects           ;; 选择后效果：((exp . 50) (item . :sword) (trigger . fn-sym))
  next-node)        ;; 下一个 tg-dialog-state 的 node-id（nil = 结束对话）
```

### 对话流程

```
tg-dialog-start(npc-symbol, node-id)
  → 设置 tg-dialog-pending = tg-dialog-state
  → 显示 greeting + options
tg-dialog-handle-choice(n)
  → 应用 effects
  → 如果 next-node 非 nil，跳转到新 state
  → 如果 next-node 为 nil，结束对话
```

### 状态机示例（Org 配置）

```org
** Dialog old-man-greeting
:PROPERTIES:
:npc: old-man
:greeting: "咳咳...你是谁？"
:END:
- 问路 :: "往北走就是城堡。" → nothing → old-man-quest
- 挑衅 :: "年轻人不要冲动。" → nothing → nil

** Dialog old-man-quest
:PROPERTIES:
:npc: old-man
:greeting: "你又来了。"
:END:
- 接受任务 → ((quest . :save-princess)) → old-man-thanks
```

## NPC 行为引擎（tg-npc.el）

### 行为规则

```elisp
(cl-defstruct tg-behavior
  "NPC 行为规则。"
  condition         ;; (always) | (hp-below N) | (hp-above N) | (player-in-room) | (and ...) | (or ...) | (not ...)
  action)           ;; (attack) | (say "text") | (move direction) | (buff attr value) | (debuff attr value)
```

### 执行时机

非被动命令（`tg-passive-actions` 中的命令如 `look`、`inventory`、`status` 不会触发 NPC 行为）之后，当前房间中的 NPC 按顺序评估行为规则，第一个匹配的被执行。每个 NPC 每回合最多执行一个动作。死亡的 NPC 不执行行为。

```elisp
(defun tg-npc-run-behaviors (game)
  "让当前房间中所有存活 NPC 执行一轮行为。"
  (let ((room (tg-game-get game :location)))
    (dolist (creature (tg-room-creatures room))
      (unless (tg-creature-dead-p creature game)
        (tg-npc-run-one-creature creature game)))))
```

## 周边系统

### 任务系统（tg-quest.el）

```elisp
(cl-defstruct tg-quest
  symbol description
  type              ;; kill collect explore talk
  target            ;; 目标标识（杀死哪个、收集哪个等）
  count progress    ;; 需要数量 / 当前进度
  rewards           ;; ((exp . 100) (item . :sword) (gold . 50))
  status            ;; inactive active completed
  description-complete)
```

任务进度在 handler chain 中更新——例如 `kill` 类型的任务在 creature death handler 中触发进度增加。

### 商店系统（tg-shop.el）

```elisp
(cl-defstruct tg-shop
  npc-symbol        ;; 商店 NPC
  sell-rate         ;; 卖出折价率
  goods)            ;; ((item-symbol . price) ...)
```

`buy` 和 `sell` 动词作为内置 action。NPC 的 `shopkeeper` 属性为 t 时，`talk` 命令自动触发商店界面。

### 等级系统（tg-level.el）

经验表可配置。每级需要的经验：
`(0 100 250 500 850 1300 1900 2700 3800 5000 ...)`

升级时获得属性点，玩家自行分配到 hp/attack/defense。

### 存档系统（tg-save.el）

存档数据结构：

```elisp
;; 存档文件内容（prin1 序列化）
((:title . "My Game")
 (:author . "DarkSun")
 (:turns . 42)
 (:location . :courtyard)
 (:state . in-progress)
 (:rooms . ((:courtyard (:visit-count . 3) (:contents . (:key :torch)))))
 (:objects . ((:chest (:props . (closed container)) (:contents . (:gold)))))
 (:player . ((:attr . ((:hp . 80) (:attack . 12)))
             (:inventory . (:sword :potion)))))
```

闭包问题通过函数查表解决：所有触发器/处理器用符号名引用，存档只存符号。加载时从函数表中恢复：

```elisp
(defvar tg-function-table
  '((magic-mirror-handler . tg-handler-magic-mirror)
    (chest-after-open . tg-trigger-chest-open)
    ...))
```

## Org-mode 配置格式

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
:props: (light outdoors)
:END:

** forest-path
:PROPERTIES:
:name: 林中小路
:desc: 小路在密林中蜿蜒。地上散落着奇怪的蘑菇。东边似乎有什么东西在发光。
:exits: ((south . forest-entrance) (north . clearing) (east . glowing-grove))
:props: (light outdoors)
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
:props: (container closed)
:contents: (gold-coin)
:END:

** gold-coin
:PROPERTIES:
:name: 金币
:synonyms: (金币 coin 钱 money)
:desc: 一枚闪闪发光的金币。
:props: (static)
:END:

* Creatures
** goblin
:PROPERTIES:
:name: 哥布林
:desc: 一个绿皮小怪物蹲在角落里，恶狠狠地盯着你。
:attr: ((hp . 20) (attack . 5) (defense . 2))
:exp-reward: 30
:behaviors: ((always . (attack)))
:death-trigger: goblin-death
:END:

** old-man
:PROPERTIES:
:name: 老人
:desc: 一位白发苍苍的老人坐在树下。他似乎在等待着什么。
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
- 什么事？ :: "森林深处有一枚龙鳞，帮我取来。" → (quest . find-dragon-scale) → old-man-waiting
- 没空 :: "那算了。" → nothing → nil

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
:rewards: ((exp . 200) (item . :magic-ring))
:END:

* Levels
:PROPERTIES:
:exp-table: (0 100 250 500 850 1300 1900 2700 3800 5000)
:bonus-points-per-level: 3
:END:
```

## 测试策略

### 单元测试覆盖

| 模块 | 测试重点 |
|---|---|
| tg-parser | PEG 语法匹配各种句式；动词标准化；词汇表构建；名词消歧；边界输入（空串、乱码） |
| tg-commands | handler chain 传播顺序；before/after 执行时机；拦截行为；错误处理路径 |
| tg-object | 属性驱动的行为（开/关/锁、取出/放入）；嵌套对象查找；移动对象 |
| tg-room | 方向出口查找；首次/重复访问描述；进出触发器 |
| tg-game | 状态存取正确性；new/load/save 往返 |
| tg-dialog | 状态机分支；条件可见性；effects 应用；多轮对话 |
| tg-npc | 条件匹配（always/hp-below/复合条件）；行为执行；每回合上限 |
| tg-save | 序列化/反序列化完整；函数表恢复；回合计数保持 |

### 集成测试

一个最小可玩游戏（3-4 个房间、2-3 个物品、1 个 NPC）覆盖完整游戏循环：移动 → 检查 → 拾取 → 对话 → 战斗 → 存档 → 读档。

### 测试框架

使用 ERT（Emacs Lisp Regression Testing），每个模块对应一个 `test/tg-<module>-test.el`。

## 与旧版对比

| 维度 | TGM 1.0 | TGM 2.0 |
|---|---|---|
| 命令解析 | 分词匹配 | PEG 自然语言 |
| 动作分发 | 直接调用 + trigger | Handler chain |
| 对象模型 | usable/wearable | 11 种属性驱动 |
| 地图 | 2D 矩形网格 | 方向出口（10 方向） |
| 状态管理 | 分散 defvar | 单一哈希表 |
| 对话 | 单层选项 | 状态机多轮 |
| 存档 | 丢闭包 | 纯数据 + 函数表 |
| 配置 | S-expression | Org-mode |
| 模块依赖 | 有循环 | 单向无环 |

## 不在范围内的内容

1. **图形界面** — 纯文本，不引入 GUI 渲染
2. **多人/网络** — 单机单人
3. **音效/音乐** — 不涉及
4. **实时战斗** — 回合制
5. **脚本语言** — 不使用外部 DSL，配置和逻辑都可以用 Elisp 表达
