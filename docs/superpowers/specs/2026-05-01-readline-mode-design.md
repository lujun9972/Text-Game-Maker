# Readline 编辑模式设计

## 目标

为 tg-mode 添加类 readline 的命令历史浏览和 Tab 补全功能。

## 现有架构

tg-mode 继承 text-mode，提示符 `[ROOM]>` 之前的文本设为 read-only。目前仅绑定 `<RET>` 到 `tg-parse`。已有 eldoc 支持（`tg-eldoc-function`）基于 `try-completion` 做命令前缀匹配。

`tg-valid-actions` 变量包含所有已注册命令（`tg-move` 等），去掉 `tg-` 前缀即为用户输入的命令名。

## 设计

### 1. 命令历史

#### 数据结构

```elisp
(defvar tg-command-history nil
  "命令历史列表，最新的在前面")

(defvar tg-command-history-max 50
  "命令历史最大条数")

(defvar tg-history-index -1
  "当前浏览的历史索引，-1 表示不在浏览历史")

(defvar tg-current-input ""
  "浏览历史前保存的当前输入")
```

#### 操作

| 按键 | 函数 | 行为 |
|------|------|------|
| `<up>` / `M-p` | `tg-history-prev` | 显示上一条历史命令 |
| `<down>` / `M-n` | `tg-history-next` | 显示下一条历史命令 |

#### 逻辑

**`tg-history-prev`：**
1. 如果 `tg-history-index` 为 -1，保存当前输入到 `tg-current-input`
2. 递增 `tg-history-index`（不超过历史长度）
3. 替换提示符后的文本为历史中对应条目

**`tg-history-next`：**
1. 递减 `tg-history-index`
2. 如果回到 -1，恢复 `tg-current-input`
3. 否则替换为历史中对应条目

#### 记录时机

在 `tg-parse` 中，成功解析命令后（非空命令、非异常、非 dialog-pending 输入）：
1. 将命令字符串插入 `tg-command-history` 开头
2. 如果与最新历史相同则跳过（去重）
3. 超过 `tg-command-history-max` 时移除末尾
4. 重置 `tg-history-index` 为 -1

### 2. Tab 补全

#### 按键绑定

| 按键 | 函数 | 行为 |
|------|------|------|
| `TAB` | `tg-complete-command` | 补全命令名 |

#### 逻辑

**`tg-complete-command`：**
1. 获取提示符后的当前输入
2. 用 `try-completion` 对 `tg-valid-actions`（去掉 `tg-` 前缀的命令名列表）做补全
3. 如果唯一匹配 — 替换输入为补全结果
4. 如果多个匹配 — 显示候选列表，补全到最长公共前缀
5. 如果无匹配 — 不做任何事

复用 eldoc 中已有的补全逻辑模式。

### 3. 对现有代码的修改

| 文件 | 修改 |
|------|------|
| `tg-mode.el` | 新增历史变量和函数、`tg-complete-command`、`tg-parse` 中记录历史、绑定新按键 |

全部修改集中在 `tg-mode.el`，无需新建文件。

### 4. 按键绑定

在 `tg-mode` 定义中添加：

```elisp
(local-set-key (kbd "<up>") #'tg-history-prev)
(local-set-key (kbd "<down>") #'tg-history-next)
(local-set-key (kbd "M-p") #'tg-history-prev)
(local-set-key (kbd "M-n") #'tg-history-next)
(local-set-key (kbd "TAB") #'tg-complete-command)
```

### 5. 测试覆盖

- `tg-history-prev` — 浏览历史、在无历史时无操作、保存当前输入
- `tg-history-next` — 回到当前输入、超出范围时无操作
- 历史记录 — 成功命令记录、空命令不记录、重复命令不记录
- 历史上限 — 超过 50 条时移除最旧
- `tg-complete-command` — 唯一匹配补全、多匹配显示候选、无匹配无操作
- `tg-parse` 集成 — 命令执行后历史被记录、dialog-pending 输入不记录

### 6. 边界情况

- 空命令不记录到历史
- 异常命令（throw 'exception）不记录到历史
- dialog-pending 时的选择输入不记录
- 重复连续命令只记录一次
- 光标不在提示符后时，历史浏览和补全不做操作
- 游戏重新启动时历史不清空（可以在 `tg-mode` 激活时清空）
