# Text-Game-Maker

基于 Emacs Lisp 的文本游戏制作工具，功能仿照 RPG Maker。

## 特性

- 基于 EIEIO / cl-defstruct 的面向对象设计，包含 Room、Inventory、Creature 三大核心类
- 房间系统：支持房间描述、物品、生物、进出触发事件
- 地图系统：通过文本配置文件定义二维地图，支持上下左右导航
- 物品系统：支持 usable（消耗品）和 wearable（装备）两种类型，可配置使用效果
- 生物系统：支持属性管理、物品携带、装备穿戴
- 战斗系统：支持攻击、反击、击败触发事件
- 升级系统：经验值、等级、技能点分配
- 触发器系统：为房间、物品、生物提供丰富的触发事件机制
- 自定义 major mode（`tg-mode`）：提供交互式游戏命令行界面，支持 eldoc
- 可扩展的 action 系统：通过 `tg-defaction` 宏轻松定义新的游戏命令
- 配置文件生成器：通过交互界面生成配置文件

## 依赖

- Emacs 24+（需要内置 EIEIO 库）
- 内置依赖：`eieio`, `thingatpt`, `cl-lib`

## 安装

```elisp
(add-to-list 'load-path "~/path/to/Text-Game-Maker")
(require 'text-game-maker)
```

## 快速开始

项目自带了示例游戏（地牢冒险），可以直接运行：

```sh
bash sample/play.sh
```

或手动加载：

```elisp
M-x eval-buffer  ; 评估 sample-game.el
M-x play-sample-game
```

## 文档

完整使用手册见 [docs/manual.org](docs/manual.org)。

## 文件结构

| 文件 | 说明 |
|------|------|
| `text-game-maker.el` | 主入口文件，加载所有模块 |
| `tg-mode.el` | 游戏主模式，命令解析与界面 |
| `room-maker.el` | 房间与地图系统 |
| `inventory-maker.el` | 物品系统 |
| `creature-maker.el` | 生物系统 |
| `action.el` | 游戏命令定义 |
| `level-system.el` | 升级系统 |
| `tg-config-generator.el` | 配置文件生成器 |
| `sample/` | 示例游戏目录 |
| `test/` | ERT 单元测试目录 |
| `run-tests.sh` | 测试运行脚本 |

## 测试

项目包含 159+ 个 ERT 单元测试，覆盖所有核心模块。

```sh
bash run-tests.sh
```

## 许可证

TODO
