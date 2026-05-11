;;; test/tg-config-gen-test.el --- tg-config-gen 测试套件  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tg-registry)
(require 'tg-config-gen)

;;; tg-gen-game 测试

(ert-deftest test-tg-gen-game-contains-template-headers ()
  "tg-gen-game 输出含 #+TITLE: 等模板头"
  (let ((result (tg-gen-game "测试游戏" "测试作者" "entrance")))
    (should (string-prefix-p "#+TITLE: 测试游戏\n" result))
    (should (string-match "#\\+AUTHOR: 测试作者" result))
    (should (string-match "#\\+START: entrance" result))
    (should (string-match "^\\* Rooms$" result))
    (should (string-match "^\\* Objects$" result))
    (should (string-match "^\\* Creatures$" result))
    (should (string-match "^\\* Dialogs$" result))
    (should (string-match "^\\* Shops$" result))
    (should (string-match "^\\* Quests$" result))))

(ert-deftest test-tg-gen-game-nil-values ()
  "tg-gen-game 处理 nil 参数"
  (let ((result (tg-gen-game nil nil nil)))
    (should (string-prefix-p "#+TITLE: \n" result))
    (should (string-match "#\\+AUTHOR: " result))
    (should (string-match "#\\+START: " result))))

;;; tg-gen-room 测试

(ert-deftest test-tg-gen-room-correct-org-format ()
  "tg-gen-room 输出正确 Org 格式"
  (let ((result (tg-gen-room "hall" "大厅" "一个宽敞的大厅" "north=garden" "key,sword" "goblin")))
    (should (string-prefix-p "** hall\n" result))
    (should (string-match ":PROPERTIES:" result))
    (should (string-match ":NAME: 大厅" result))
    (should (string-match ":DESC: 一个宽敞的大厅" result))
    (should (string-match ":SHORT_DESC: 一个宽敞的大厅" result))
    (should (string-match ":EXITS: north=garden" result))
    (should (string-match ":CONTENTS: key,sword" result))
    (should (string-match ":CREATURES: goblin" result))
    (should (string-match ":END:" result))))

(ert-deftest test-tg-gen-room-empty-fields ()
  "tg-gen-room 处理空字段"
  (let ((result (tg-gen-room "empty" "空房间" "什么都没有" "" "" "")))
    (should (string-match ":EXITS: $" result))
    (should (string-match ":CONTENTS: $" result))
    (should (string-match ":CREATURES: $" result))))

(ert-deftest test-tg-gen-room-nil-fields ()
  "tg-gen-room 处理 nil 字段"
  (let ((result (tg-gen-room "room1" "房间" "描述" nil nil nil)))
    (should (string-match ":EXITS: $" result))
    (should (string-match ":CONTENTS: $" result))
    (should (string-match ":CREATURES: $" result))))

;;; tg-gen-object 测试

(ert-deftest test-tg-gen-object-correct-org-format ()
  "tg-gen-object 输出正确 Org 格式"
  (let ((result (tg-gen-object "sword" "剑" "sword,blade" "wearable" nil nil nil nil)))
    (should (string-prefix-p "** sword\n" result))
    (should (string-match ":PROPERTIES:" result))
    (should (string-match ":NAME: 剑" result))
    (should (string-match ":SYNONYMS: sword,blade" result))
    (should (string-match ":PROPS: wearable" result))
    (should (string-match ":STATE: $" result))
    (should (string-match ":KEY: $" result))
    (should (string-match ":EFFECTS: $" result))
    (should (string-match ":HANDLER: $" result))
    (should (string-match ":END:" result))))

(ert-deftest test-tg-gen-object-with-effects ()
  "tg-gen-object 带效果"
  (let ((result (tg-gen-object "potion" "药水" "potion" "edible" nil nil "(hp 20)" nil)))
    (should (string-match ":EFFECTS: (hp 20)" result))))

;;; tg-validate-config 测试

(ert-deftest test-tg-validate-config-exit-refs-nonexistent-room ()
  "tg-validate-config 检测 exit 引用不存在的房间"
  (tg-registry-clear)
  ;; 注册一个 exit 指向不存在房间的房间
  (let ((room (make-tg-room :symbol 'hall
                             :name "大厅"
                             :desc "宽敞的大厅"
                             :exits '((north . nonexistent-room))
                             :contents nil
                             :creatures nil)))
    (tg-register-room 'hall room))
  (let ((warnings (tg-validate-config)))
    (should (= (length warnings) 1))
    (should (string-match "nonexistent-room" (car warnings)))))

(ert-deftest test-tg-validate-config-contents-ref-undefined-object ()
  "tg-validate-config 检测未定义对象"
  (tg-registry-clear)
  ;; 注册一个 contents 引用未定义对象的房间
  (let ((room (make-tg-room :symbol 'hall
                             :name "大厅"
                             :desc "宽敞的大厅"
                             :exits nil
                             :contents '(missing-key missing-sword)
                             :creatures nil)))
    (tg-register-room 'hall room))
  (let ((warnings (tg-validate-config)))
    (should (= (length warnings) 2))
    (should (cl-some (lambda (w) (string-match "missing-key" w)) warnings))
    (should (cl-some (lambda (w) (string-match "missing-sword" w)) warnings))))

(ert-deftest test-tg-validate-config-no-warnings-when-valid ()
  "tg-validate-config 有效配置不产生警告"
  (tg-registry-clear)
  (let ((room (make-tg-room :symbol 'hall
                             :name "大厅"
                             :desc "宽敞的大厅"
                             :exits '((north . garden))
                             :contents '(key)
                             :creatures nil))
        (garden (make-tg-room :symbol 'garden
                               :name "花园"
                               :desc "美丽花园"
                               :exits '((south . hall))
                               :contents nil
                               :creatures nil))
        (key (make-tg-object :symbol 'key
                              :name "钥匙"
                              :synonyms nil
                              :contents nil
                              :supports nil
                              :props nil
                              :state nil
                              :key nil
                              :effects nil
                              :handler nil)))
    (tg-register-room 'hall room)
    (tg-register-room 'garden garden)
    (tg-register-object 'key key))
  (let ((warnings (tg-validate-config)))
    (should (null warnings))))

(ert-deftest test-tg-validate-config-dialog-next-node-nonexistent ()
  "tg-validate-config 检测对话 next-node 引用不存在的节点"
  (tg-registry-clear)
  (let ((dialog (make-tg-dialog-state
                 :node-id 'merchant
                 :npc-symbol 'merchant
                 :greeting "你好"
                 :options (list (make-tg-dialog-option
                                 :text "再见"
                                 :response "再见"
                                 :condition nil
                                 :effects nil
                                 :next-node 'nonexistent-dialog)))))
    (tg-register-dialog 'merchant dialog))
  (let ((warnings (tg-validate-config)))
    (should (= (length warnings) 1))
    (should (string-match "nonexistent-dialog" (car warnings)))))

(provide 'tg-config-gen-test)
;;; test/tg-config-gen-test.el ends here
