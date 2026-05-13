# Readline 增强设计

## 目标

为 tg-mode 的命令输入区域增加 4 项 readline 风格的增强功能。

## 现状

tg-mode.el 已有：M-p/M-n 历史浏览（50 条上限）、TAB 补全（动词名 + 对象中文名）、基本 Emacs 行编辑。

## 功能规格

### 1. ↑↓ 箭头翻历史

绑定 `<up>` → `tg-history-prev`，`<down>` → `tg-history-next`。直接复用现有函数，零新代码。

### 2. C-r 搜索历史

新增 `tg-history-isearch` 函数：
- C-r 触发，用 `read-string` 在 mini-buffer 输入搜索词
- 从 `tg-command-history` 中 `string-match` 过滤匹配项
- 无匹配时 tg-message 提示 "无匹配历史"
- 单条匹配直接填入命令行
- 多条匹配：tg-message 列出所有候选 + 填入最近一条

新增 `tg-history-isearch-next` 函数（循环模式）：
- 再次按 C-r 时复用上次搜索词，跳到下一条匹配（index +1，越界回 0）
- 任意非 C-r 按键退出循环状态

状态管理：buffer-local 变量 `tg-isearch-matches`（匹配列表）和 `tg-isearch-index`（当前位置）。

### 3. 对象名补全用 symbol

修改 `tg-complete-object`：
- 候选列表改为 `(symbol-name obj-sym)`（如 `torch`、`sword`）
- 匹配源：房间可见对象 + 背包物品 + 房间内 creature symbol
- 补全时替换最后一个词为 symbol 名

### 4. 方向词补全

修改 `tg-complete-command`：
- 当输入的动词通过 `tg-find-action` 归一化后等于 `go` 时，切换到方向词补全
- 方向词来源：`tg-parser-direction-map` 的所有 key（含 in/out）
- 补全时始终扩展为长形式（n → north、s → south 等）
- 补全时替换最后一个词

## 影响范围

仅修改 `tg-mode.el`。无新增文件，无跨模块接口变更。
