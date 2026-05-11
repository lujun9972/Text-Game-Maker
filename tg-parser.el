;;; tg-parser.el --- PEG 自然语言解析器  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-game)
(require 'tg-action)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)

(defconst tg-parser-direction-map
  '(("n" . north) ("north" . north)
    ("s" . south) ("south" . south)
    ("e" . east) ("east" . east)
    ("w" . west) ("west" . west)
    ("ne" . northeast) ("northeast" . northeast)
    ("nw" . northwest) ("northwest" . northwest)
    ("se" . southeast) ("southeast" . southeast)
    ("sw" . southwest) ("southwest" . southwest)
    ("u" . up) ("up" . up)
    ("d" . down) ("down" . down)
    ("in" . in) ("out" . out))
  "方向词到标准方向的映射表")

(defconst tg-parser-prepositions
  '("on" "with" "to" "in" "by" "under" "into" "from" "at"))

(defconst tg-parser-all-words '("all" "everything"))

(defun tg-parser-tokenize (input)
  "将输入字符串分词。"
  (when (and input (not (string-empty-p (string-trim input))))
    (split-string (string-trim input) "[ \t]+" t)))

(defun tg-parser-is-direction-only (tokens)
  "检查 TOKENS 是否仅包含一个方向词。返回方向符号或 nil。"
  (when (= (length tokens) 1)
    (cdr (assoc (downcase (car tokens)) tg-parser-direction-map))))

(defun tg-parser-normalize-verb (verb)
  "通过 tg-verb-aliases 标准化动词。"
  (let ((lower-verb (downcase verb)))
    (or (cdr (assoc lower-verb tg-verb-aliases))
        lower-verb)))

(defun tg-parser-match-multiword-verb (tokens)
  "检查 TOKENS 开头是否为多词动词。返回 (verb . remaining) 或 nil。"
  (when (and tokens (>= (length tokens) 2))
    (let ((combined (downcase (concat (car tokens) " " (cadr tokens)))))
      (cond
       ((string= combined "pick up") (cons "pick up" (cddr tokens)))
       ((string= combined "put down") (cons "put down" (cddr tokens)))
       ((string= combined "look at") (cons "look at" (cddr tokens)))
       ((string= combined "listen to") (cons "listen to" (cddr tokens)))
       (t nil)))))

(defun tg-parser-split-prep-phrase (tokens)
  "将 TOKENS 按介词分割为主宾语和介词短语。"
  (catch 'found
    (let ((before-prep '())
          (rest tokens))
      (while rest
        (let ((token (car rest)))
          (if (member (downcase token) tg-parser-prepositions)
              (throw 'found (list (nreverse before-prep)
                                  (cons (downcase token) (cdr rest))))
            (push token before-prep)
            (setq rest (cdr rest)))))
      (list (nreverse before-prep) nil))))

(defun tg-parser-build-vocabulary (game)
  "构建当前可用词汇表。返回哈希表 (word -> object-symbol)。"
  (let ((vocab (make-hash-table :test 'equal))
        (location (tg-game-get game :location))
        (player-sym (tg-game-get game :player)))
    (let* ((player (when player-sym (tg-get-creature player-sym)))
           (inventory (when player (tg-creature-inventory player))))
      (when location
        (let ((room (tg-get-room location)))
          (when room
            (dolist (obj-sym (tg-room-all-visible-objects room))
              (tg-parser-add-object-vocab vocab obj-sym)))))
      (when inventory
        (dolist (obj-sym inventory)
          (tg-parser-add-object-vocab vocab obj-sym)))
      (dolist (w tg-parser-all-words)
        (puthash w :all vocab)))
    vocab))

(defun tg-parser-add-object-vocab (vocab obj-sym)
  "将对象的名称和同义词添加到词汇表。"
  (let ((obj (tg-get-object obj-sym)))
    (when obj
      (puthash (downcase (tg-object-name obj)) obj-sym vocab)
      (dolist (syn (tg-object-synonyms obj))
        (puthash (downcase (format "%s" syn)) obj-sym vocab)))))

(defun tg-parser-classify-words (tokens vocab)
  "将词列表分类为形容词和名词。返回 (noun-sym adjectives-list)。"
  (when tokens
    (let ((noun-found nil)
          (noun-sym nil)
          (adjectives '()))
      (dolist (token (reverse tokens))
        (let ((lower (downcase token)))
          (cond
           (noun-found (push lower adjectives))
           ((gethash lower vocab)
            (setq noun-sym (gethash lower vocab)
                  noun-found t))
           ((eq (gethash lower vocab) :all)
            (setq noun-sym :all
                  noun-found t))
           (t (push lower adjectives)))))
      (unless noun-found
        (setq adjectives (mapcar 'downcase tokens)))
      (list noun-sym adjectives))))

(defun tg-parser-parse-words (tokens vocab)
  "解析词序列。返回 (object-symbol adjectives-list unknown-word)。"
  (let* ((result (tg-parser-classify-words tokens vocab))
         (noun-sym (car result))
         (adjectives (cadr result))
         (unknown-word
          (unless noun-sym
            (when adjectives (car (last adjectives))))))
    (list noun-sym adjectives unknown-word)))

(defun tg-parse (input)
  "解析玩家输入，返回动作 AST。"
  (let ((tokens (tg-parser-tokenize input))
        direction)
    (cond
     ((not tokens)
      (list :error :empty-input))
     ((setq direction (tg-parser-is-direction-only tokens))
      (list :action 'go :direction direction))
     (t
      (let* ((multi-result (tg-parser-match-multiword-verb tokens))
             (verb (or (car multi-result) (downcase (car tokens))))
             (remaining (or (cdr multi-result) (cdr tokens)))
             (normalized-verb (tg-parser-normalize-verb verb))
             (action-id (tg-find-action normalized-verb)))
        (if (not action-id)
            (list :error :unknown-action :verb verb)
          (let* ((vocab (tg-parser-build-vocabulary tg-game))
                 (prep-split (tg-parser-split-prep-phrase remaining))
                 (main-words (car prep-split))
                 (prep-phrase (cadr prep-split))
                 (main-result (if main-words
                                  (tg-parser-parse-words main-words vocab)
                                '(nil nil nil)))
                 (do-key (nth 0 main-result))
                 (do-adj (nth 1 main-result))
                 (do-unknown (nth 2 main-result))
                 (prep-word (when prep-phrase (car prep-phrase)))
                 (io-words (when prep-phrase (cdr prep-phrase)))
                 (io-result (when io-words
                              (tg-parser-parse-words io-words vocab)))
                 (io-key (when io-result (nth 0 io-result)))
                 (io-adj (when io-result (nth 1 io-result)))
                 (io-unknown (when io-result (nth 2 io-result))))
            (cond
             (do-unknown
              (list :error :unknown-noun :word do-unknown))
             (io-unknown
              (list :error :unknown-noun :word io-unknown))
             (t
              (let ((ast (list :action action-id)))
                (when do-key
                  (setq ast (plist-put ast :do-key do-key)))
                (when do-adj
                  (setq ast (plist-put ast :do-adj do-adj)))
                (when prep-word
                  (setq ast (plist-put ast :prep prep-word)))
                (when io-key
                  (setq ast (plist-put ast :io-key io-key)))
                (when io-adj
                  (setq ast (plist-put ast :io-adj io-adj)))
                ast))))))))))

(defvar tg-grammar nil
  "兼容性别名：PEG 语法（当前使用手写解析器）")

(defun tg-build-vocabulary (game)
  "构建词汇表的公开接口。"
  (tg-parser-build-vocabulary game))

(provide 'tg-parser)
;;; tg-parser.el ends here
