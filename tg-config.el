;;; tg-config.el --- Org 配置解析  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'tg-registry)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-dialog)
(require 'tg-shop)
(require 'tg-quest)
(require 'tg-game)
(require 'tg-level)

;;; 解析工具函数

(defun tg-config--parse-keyword (tree keyword)
  "从 Org 元素树中提取关键字值
tree: org-element-parse-buffer 返回的结果
keyword: 关键字名称 (如 TITLE, AUTHOR)
返回: 关键字值字符串或 nil"
  (catch 'found
    ;; 遍历所有内容（包括嵌套的 section）
    (dolist (node (org-element-contents tree))
      ;; 如果是 section，递归查找其中的 keyword
      (when (eq (org-element-type node) 'section)
        (dolist (item (org-element-contents node))
          (when (and (eq (org-element-type item) 'keyword)
                     (string-equal (org-element-property :key item) keyword))
            (throw 'found (org-element-property :value item))))))
    nil))

(defun tg-config--read-property (element property)
  "从 Org 元素的 PROPERTIES drawer 中读取属性值
element: Org 元素（headline）
property: 属性名称（字符串，如 \"NAME\"）
返回: 属性值字符串或 nil"
  ;; Org 将 PROPERTIES drawer 中的属性直接放在元素上
  ;; 需要将字符串转换为关键字（如 :NAME）
  (org-element-property (intern (concat ":" property)) element))

(defun tg-config--split-list (str)
  "分割逗号分隔的字符串为符号列表
str: 逗号分隔的字符串 (如 \"sword,shield,potion\")
返回: 符号列表 (如 (sword shield potion))"
  (when (and str (> (length str) 0))
    (mapcar #'intern (split-string str "[\s,]+" t "[\s,]+"))))

(defun tg-config--parse-int-list (str)
  "将逗号分隔的整数字符串转为整数列表。
str: 逗号分隔的整数字符串 (如 \"0,100,200,400\")
返回: 整数列表 (如 (0 100 200 400))"
  (when (and str (not (string-empty-p (string-trim str))))
    (mapcar #'string-to-number (split-string str "," t "[\s]+"))))

(defun tg-config--parse-exits (str)
  "解析出口字符串为 alist
str: 格式为 \"north=hall,south=garden\"
返回: ((north . hall) (south . garden))"
  (when (and str (> (length str) 0))
    (let ((pairs (split-string str "," t "[\s,]+"))
          result)
      (dolist (pair pairs)
        (let ((parts (split-string pair "=" t "=")))
          (when (= (length parts) 2)
            (push (cons (intern (car parts)) (intern (cadr parts))) result))))
      (nreverse result))))

(defun tg-config--parse-props (str)
  "解析属性字符串为符号列表
str: 空格分隔的属性字符串 (如 \"container static\")
返回: 符号列表 (如 (container static))"
  (when (and str (> (length str) 0))
    (mapcar #'intern (split-string str))))

(defun tg-config--parse-attr (str)
  "解析属性字符串为属性列表
str: 格式为 \"hp 50 attack 10\"
返回: ((hp 50) (attack 10))"
  (when (and str (> (length str) 0))
    (let ((parts (split-string str))
          result)
      (while parts
        (when (cdr parts)
          (push (list (intern (car parts))
                      (string-to-number (cadr parts)))
                result))
        (setq parts (cddr parts)))
      (nreverse result))))

(defun tg-config--parse-effects (str)
  "解析效果字符串为效果列表
str: 格式为 \"(hp 20) (attack 3 :duration 10)\"
返回: ((hp 20) (attack 3 :duration 10)) 或 nil（如果格式无效）"
  (when (and str (> (length str) 0))
    (condition-case nil
        (let ((result (car (read-from-string (concat "(" str ")")))))
          ;; 验证结果是一个列表，且每个元素都是列表（effect 格式）
          (when (and (listp result)
                     (cl-every 'listp result))
            result))
      (error nil))))

(defun tg-config--parse-behaviors (str)
  "解析行为字符串为行为列表
str: 格式为 \"(always . (say hello))\"
返回: Lisp 对象或 nil（如果格式无效）"
  (when (and str (> (length str) 0))
    (condition-case nil
        (let ((result (car (read-from-string str))))
          ;; 验证结果是一个列表（behaviors 格式）
          (when (listp result)
            result))
      (error nil))))

(defun tg-config--resolve-handler (handler-str)
  "解析 handler 字符串为函数符号
handler-str: handler 字符串
返回: 函数符号或 nil（如果无效）"
  (when (and handler-str (> (length handler-str) 0))
    (let ((sym (intern handler-str)))
      (when (fboundp sym)
        sym))))

(defun tg-config--parse-dialog-option (line)
  "解析对话选项行
line: 格式为 \"[条件] 选项文本 :: 响应文本 → effects → next-node-id\"
返回: tg-dialog-option 结构或 nil"
  (when (and line (> (length line) 0))
    (let ((condition nil)
          (remaining line))
      ;; 检测行首条件：[(condition)]
      (when (string-match "^\\[\\(.*?\\)\\]\s+" line)
        (setq condition (read (match-string 1 line)))
        (setq remaining (substring line (match-end 0))))
      (let* ((parts (split-string remaining "→" t "[\s→]+"))
             (text-response (when (car parts)
                             (split-string (car parts) "::" t "[\s:::]+")))
             (text (when (car text-response) (string-trim (car text-response))))
             (response (when (cadr text-response) (string-trim (cadr text-response))))
             (effects-str (when (cadr parts) (string-trim (cadr parts))))
             (next-node-str (when (caddr parts) (string-trim (caddr parts))))
             (effects (tg-config--parse-effects effects-str))
             (next-node (when next-node-str (intern next-node-str))))
        (when text
          (make-tg-dialog-option
           :text text
           :response response
           :condition condition
           :effects effects
           :next-node next-node))))))

;;; Section 解析器

(defun tg-config--parse-room-section (headline)
  "解析 Rooms section 中的房间
headline: Rooms section 的 headline 元素
注册所有解析的房间"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((sym (intern (org-element-property :raw-value child)))
               (name (tg-config--read-property child "NAME"))
               (desc (tg-config--read-property child "DESC"))
               (short-desc (tg-config--read-property child "SHORT_DESC"))
               (exits (tg-config--parse-exits (tg-config--read-property child "EXITS")))
               (contents (tg-config--split-list (tg-config--read-property child "CONTENTS")))
               (creatures (tg-config--split-list (tg-config--read-property child "CREATURES")))
               (before-handler (tg-config--resolve-handler (tg-config--read-property child "BEFORE_HANDLER")))
               (after-handler (tg-config--resolve-handler (tg-config--read-property child "AFTER_HANDLER")))
               (room (make-tg-room
                      :symbol sym
                      :name name
                      :desc desc
                      :short-desc short-desc
                      :exits exits
                      :contents contents
                      :creatures creatures
                      :before-handler before-handler
                      :after-handler after-handler
                      :visit-count 0)))
          (tg-register-room sym room))))))

(defun tg-config--parse-object-section (headline)
  "解析 Objects section 中的对象
headline: Objects section 的 headline 元素
注册所有解析的对象"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((sym (intern (org-element-property :raw-value child)))
               (name (tg-config--read-property child "NAME"))
               (synonyms (tg-config--split-list (tg-config--read-property child "SYNONYMS")))
               (props (tg-config--parse-props (tg-config--read-property child "PROPS")))
               (state-str (tg-config--read-property child "STATE"))
               (state (when state-str (intern state-str)))
               (key (let ((k (tg-config--read-property child "KEY")))
                      (when k (intern k))))
               (effects (tg-config--parse-effects (tg-config--read-property child "EFFECTS")))
               (handler (tg-config--resolve-handler (tg-config--read-property child "HANDLER")))
               (contents (tg-config--split-list (tg-config--read-property child "CONTENTS")))
               (supports (tg-config--split-list (tg-config--read-property child "SUPPORTS")))
               (obj (make-tg-object
                     :symbol sym
                     :name name
                     :synonyms synonyms
                     :contents contents
                     :supports supports
                     :props props
                     :state state
                     :key key
                     :effects effects
                     :handler handler)))
          (tg-register-object sym obj))))))

(defun tg-config--parse-creature-section (headline)
  "解析 Creatures section 中的生物
headline: Creatures section 的 headline 元素
注册所有解析的生物"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((sym (intern (org-element-property :raw-value child)))
               (name (tg-config--read-property child "NAME"))
               (attr (tg-config--parse-attr (tg-config--read-property child "ATTR")))
               (inventory (tg-config--split-list (tg-config--read-property child "INVENTORY")))
               (equipment (tg-config--split-list (tg-config--read-property child "EQUIPMENT")))
               (exp-reward-str (tg-config--read-property child "EXP_REWARD"))
               (exp-reward (when exp-reward-str (string-to-number exp-reward-str)))
               (behaviors-str (tg-config--read-property child "BEHAVIORS"))
               (behaviors (tg-config--parse-behaviors behaviors-str))
               (death-trigger (tg-config--resolve-handler (tg-config--read-property child "DEATH_TRIGGER")))
               (shopkeeper-str (tg-config--read-property child "SHOPKEEPER"))
               (shopkeeper (when shopkeeper-str (not (string-equal shopkeeper-str "nil"))))
               (handler (tg-config--resolve-handler (tg-config--read-property child "HANDLER")))
               (creature (make-tg-creature
                          :symbol sym
                          :name name
                          :attr attr
                          :inventory inventory
                          :equipment equipment
                          :exp-reward exp-reward
                          :behaviors behaviors
                          :death-trigger death-trigger
                          :shopkeeper shopkeeper
                          :handler handler)))
          (tg-register-creature sym creature))))))

(defun tg-config--parse-dialog-section (headline)
  "解析 Dialogs section 中的对话节点
headline: Dialogs section 的 headline 元素
注册所有解析的对话节点"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((node-id (intern (org-element-property :raw-value child)))
               (npc-symbol-str (tg-config--read-property child "NPC_SYMBOL"))
               (npc-symbol (when npc-symbol-str (intern npc-symbol-str)))
               (greeting (tg-config--read-property child "GREETING"))
               (options nil)
               (contents (org-element-contents child)))
          ;; 遍历内容的每项，查找 paragraph 元素
          ;; headline -> section -> (property-drawer paragraph ...)
          (dolist (item contents)
            (when (eq (org-element-type item) 'section)
              (dolist (sub-item (org-element-contents item))
                (when (eq (org-element-type sub-item) 'paragraph)
                  (let ((text (org-element-interpret-data sub-item)))
                    (when (> (length text) 0)
                      ;; 一个 paragraph 可能包含多行，每行一个选项
                      (dolist (line (split-string text "\n" t "[\s\n]+"))
                        (let ((option (tg-config--parse-dialog-option line)))
                          (when option
                            (push option options))))))))))
          (setq options (nreverse options))
          (let ((dialog (make-tg-dialog-state
                         :node-id node-id
                         :npc-symbol npc-symbol
                         :greeting greeting
                         :options options)))
            (tg-register-dialog node-id dialog)))))))

(defun tg-config--parse-shop-section (headline)
  "解析 Shops section 中的商店
headline: Shops section 的 headline 元素
注册所有解析的商店"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((sym (intern (org-element-property :raw-value child)))
               (npc-symbol-str (tg-config--read-property child "NPC_SYMBOL"))
               (npc-symbol (when npc-symbol-str (intern npc-symbol-str)))
               (sell-rate-str (tg-config--read-property child "SELL_RATE"))
               (sell-rate (when sell-rate-str (string-to-number sell-rate-str)))
               (goods-str (tg-config--read-property child "GOODS"))
               (goods nil))
          ;; 解析商品列表
          (when (and goods-str (> (length goods-str) 0))
            (let ((pairs (split-string goods-str "," t "[\s,]+")))
              (dolist (pair pairs)
                (let ((parts (split-string pair "=" t "=")))
                  (when (= (length parts) 2)
                    (push (cons (intern (car parts))
                                (string-to-number (cadr parts)))
                          goods))))))
          (setq goods (nreverse goods))
          (let ((shop (make-tg-shop
                       :npc-symbol npc-symbol
                       :sell-rate sell-rate
                       :goods goods)))
            (tg-register-shop sym shop)))))))

(defun tg-config--parse-quest-section (headline)
  "解析 Quests section 中的任务
headline: Quests section 的 headline 元素
注册所有解析的任务"
  (let ((children (org-element-contents headline)))
    (dolist (child children)
      (when (eq (org-element-type child) 'headline)
        (let* ((sym (intern (org-element-property :raw-value child)))
               (type-str (tg-config--read-property child "TYPE"))
               (type (when type-str (intern type-str)))
               (target-str (tg-config--read-property child "TARGET"))
               (target (when target-str (intern target-str)))
               (count-str (tg-config--read-property child "COUNT"))
               (count (when count-str (string-to-number count-str)))
               (rewards (tg-config--parse-effects (tg-config--read-property child "REWARDS")))
               (description (tg-config--read-property child "DESCRIPTION"))
               (completion-text (tg-config--read-property child "COMPLETION"))
               (quest (make-tg-quest
                       :symbol sym
                       :type type
                       :target target
                       :count count
                       :progress 0
                       :status 'inactive
                       :rewards rewards
                       :description description
                       :completion-text completion-text)))
          (tg-register-quest sym quest))))))

(defun tg-config--parse-level-section (headline)
  "解析 Level section，设置全局升级变量。
headline: Level section 的 headline 元素"
  (let ((exp-table (tg-config--parse-int-list (tg-config--read-property headline "EXP_TABLE")))
        (bonus (tg-config--read-property headline "BONUS_POINTS"))
        (auto-upgrade (tg-config--parse-attr (tg-config--read-property headline "AUTO_UPGRADE"))))
    (when exp-table (setq tg-level-exp-table exp-table))
    (when bonus (setq tg-level-bonus-points-per-level (string-to-number bonus)))
    (when auto-upgrade (setq tg-level-auto-upgrade-attrs auto-upgrade))))

;;; 主函数

(defun tg-config-load (org-file)
  "加载 Org 配置文件，解析并注册所有游戏实体
org-file: Org 配置文件路径

返回: 游戏状态哈希表 (通过 tg-new-game 创建)

流程:
1. 加载同目录 handlers.el（若存在）
2. org-element-parse-buffer 解析 Org 文件
3. 读取 TITLE/AUTHOR/START 全局属性
4. 按一级标题分派到各 section 解析器
5. 每个 section 遍历二级标题，从 PROPERTIES drawer 读取字段
6. 构造 struct 调用 tg-register-*

支持的 section:
- Rooms: 房间配置
- Objects: 对象配置
- Creatures: 生物配置
- Dialogs: 对话节点配置
- Shops: 商店配置
- Quests: 任务配置"
  (unless (file-exists-p org-file)
    (error "配置文件不存在: %s" org-file))

  ;; 加载 handlers.el（如果存在）
  (let ((handlers-file (expand-file-name "handlers.el"
                                          (file-name-directory org-file))))
    (when (file-exists-p handlers-file)
      (load-file handlers-file)))

  ;; 读取 Org 文件内容
  (let ((content (with-temp-buffer
                   (insert-file-contents org-file)
                   (org-mode)
                   (org-element-parse-buffer))))
    ;; 提取全局属性
    (let ((title (tg-config--parse-keyword content "TITLE"))
          (author (or (tg-config--parse-keyword content "AUTHOR") "Unknown"))
          (start-room (tg-config--parse-keyword content "START"))
          (player-name (tg-config--parse-keyword content "PLAYER")))
      ;; 创建游戏状态
      (let ((game (tg-new-game title author)))
        ;; 设置起始房间
        (when start-room
          (tg-game-put game :location (intern start-room)))
        ;; 设置玩家
        (when player-name
          (tg-game-put game :player (intern player-name)))
        ;; 遍历一级标题，分派到各 section 解析器
        ;; Org 结构: org-data -> section (keywords) + headline (section) + ...
        (dolist (section (org-element-contents content))
          (when (eq (org-element-type section) 'headline)
            (let ((section-name (downcase (org-element-property :raw-value section))))
              (cond
               ((string-equal section-name "rooms")
                (tg-config--parse-room-section section))
               ((string-equal section-name "objects")
                (tg-config--parse-object-section section))
               ((string-equal section-name "creatures")
                (tg-config--parse-creature-section section))
               ((string-equal section-name "dialogs")
                (tg-config--parse-dialog-section section))
               ((string-equal section-name "shops")
                (tg-config--parse-shop-section section))
               ((string-equal section-name "quests")
                (tg-config--parse-quest-section section))
               ((string-equal section-name "level")
                (tg-config--parse-level-section section))))))
        game))))

(provide 'tg-config)
;;; tg-config.el ends here
