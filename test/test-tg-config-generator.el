;;; test-tg-config-generator.el --- Tests for tg-config-generator.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'tg-config-generator)

;; --- Parsing utilities ---

(ert-deftest test-tg-gen-parse-value-as-list ()
  "Should parse space-separated symbols."
  (should (equal (tg-gen-parse-value-as-list "key sword") '(key sword))))

(ert-deftest test-tg-gen-parse-value-as-list-empty ()
  "Should return nil for empty string."
  (should (null (tg-gen-parse-value-as-list "")))
  (should (null (tg-gen-parse-value-as-list nil))))

(ert-deftest test-tg-gen-parse-value-as-data ()
  "Should parse Elisp alist data."
  (should (equal (tg-gen-parse-value-as-data "(hp . 100) (attack . 10)")
                 '((hp . 100) (attack . 10)))))

(ert-deftest test-tg-gen-parse-value-as-data-empty ()
  "Should return nil for empty string."
  (should (null (tg-gen-parse-value-as-data "")))
  (should (null (tg-gen-parse-value-as-data nil))))

;; --- Parse blocks ---

(ert-deftest test-tg-gen-parse-blocks-single ()
  "Should parse a single entity block."
  (let ((blocks (tg-gen-parse-blocks "## Room 1\nsymbol: living-room\ndescription: A room")))
    (should (= (length blocks) 1))
    (should (equal (assoc "symbol" (car blocks)) '("symbol" . "living-room")))))

(ert-deftest test-tg-gen-parse-blocks-multiple ()
  "Should parse multiple entity blocks."
  (let ((blocks (tg-gen-parse-blocks
                 "## Room 1\nsymbol: a\n## Room 2\nsymbol: b")))
    (should (= (length blocks) 2))))

(ert-deftest test-tg-gen-parse-blocks-skip-comments ()
  "Should skip comment and blank lines."
  (let ((blocks (tg-gen-parse-blocks "# comment\n\n## Room 1\nsymbol: x")))
    (should (= (length blocks) 1))))

;; --- Room config ---

(ert-deftest test-tg-gen-parse-room-single ()
  "Should parse single room config."
  (let ((result (tg-gen-parse-room-config
                 "## Room 1\nsymbol: living-room\ndescription: 一间客厅\ninventory: key sword\ncreature: cat")))
    (should (= (length result) 1))
    (should (equal (car result)
                   '(living-room "一间客厅" (key sword) (cat))))))

(ert-deftest test-tg-gen-parse-room-multiple ()
  "Should parse multiple room configs."
  (let ((result (tg-gen-parse-room-config
                 "## Room 1\nsymbol: a\ndescription: A\n## Room 2\nsymbol: b\ndescription: B")))
    (should (= (length result) 2))
    (should (equal (car result) '(a "A" nil nil)))
    (should (equal (cadr result) '(b "B" nil nil)))))

(ert-deftest test-tg-gen-parse-room-empty-fields ()
  "Empty fields should become nil."
  (let ((result (tg-gen-parse-room-config
                 "## Room 1\nsymbol: empty\ndescription: \ninventory: \ncreature: ")))
    (should (equal (car result) '(empty "" nil nil)))))

(ert-deftest test-tg-gen-parse-room-skip-empty-symbol ()
  "Blocks with empty symbol should be skipped."
  (let ((result (tg-gen-parse-room-config
                 "## Room 1\nsymbol: \ndescription: no symbol")))
    (should (null result))))

;; --- Major mode ---

(ert-deftest test-tg-gen-config-mode ()
  "tg-gen-config-mode should be a major mode."
  (with-temp-buffer
    (tg-gen-config-mode)
    (should (equal major-mode 'tg-gen-config-mode))
    (should (derived-mode-p 'text-mode))))

(ert-deftest test-tg-gen-room-config-creates-buffer ()
  "tg-gen-room-config should create a config buffer."
  (tg-gen-room-config)
  (should (get-buffer "*TG Config: room*"))
  (with-current-buffer "*TG Config: room*"
    (should (equal major-mode 'tg-gen-config-mode))
    (should (eq tg-config-type 'room)))
  (kill-buffer "*TG Config: room*"))

;; --- Inventory config ---

(ert-deftest test-tg-gen-parse-inventory-single ()
  "Should parse single inventory config with effects."
  (let ((result (tg-gen-parse-inventory-config
                 "## Item 1\nsymbol: key\ndescription: 一把钥匙\ntype: usable\neffects: (wisdom . 1)")))
    (should (= (length result) 1))
    (should (equal (car result) '(key "一把钥匙" usable ((wisdom . 1)))))))

(ert-deftest test-tg-gen-parse-inventory-wearable ()
  "Should parse wearable inventory config."
  (let ((result (tg-gen-parse-inventory-config
                 "## Item 1\nsymbol: sword\ndescription: 剑\ntype: wearable\neffects: (attack . 5) (defense . 2)")))
    (should (equal (car result) '(sword "剑" wearable ((attack . 5) (defense . 2)))))))

(ert-deftest test-tg-gen-parse-inventory-empty-effects ()
  "Empty effects should become nil."
  (let ((result (tg-gen-parse-inventory-config
                 "## Item 1\nsymbol: stone\ndescription: 石头\ntype: usable\neffects: ")))
    (should (equal (car result) '(stone "石头" usable nil)))))

(ert-deftest test-tg-gen-inventory-config-creates-buffer ()
  "tg-gen-inventory-config should create a config buffer."
  (tg-gen-inventory-config)
  (should (get-buffer "*TG Config: inventory*"))
  (with-current-buffer "*TG Config: inventory*"
    (should (eq tg-config-type 'inventory)))
  (kill-buffer "*TG Config: inventory*"))

;; --- Creature config ---

(ert-deftest test-tg-gen-parse-creature-single ()
  "Should parse single creature config with attr."
  (let ((result (tg-gen-parse-creature-config
                 "## Creature 1\nsymbol: hero\ndescription: 勇者\nattr: (hp . 100) (attack . 10)\ninventory: key\nequipment: ")))
    (should (= (length result) 1))
    (should (equal (car result)
                   '(hero "勇者" ((hp . 100) (attack . 10)) (key) nil)))))

(ert-deftest test-tg-gen-parse-creature-empty-fields ()
  "Empty attr/inventory/equipment should become nil."
  (let ((result (tg-gen-parse-creature-config
                 "## Creature 1\nsymbol: rat\ndescription: 老鼠\nattr: \ninventory: \nequipment: ")))
    (should (equal (car result) '(rat "老鼠" nil nil nil)))))

(ert-deftest test-tg-gen-creature-config-creates-buffer ()
  "tg-gen-creature-config should create a config buffer."
  (tg-gen-creature-config)
  (should (get-buffer "*TG Config: creature*"))
  (with-current-buffer "*TG Config: creature*"
    (should (eq tg-config-type 'creature)))
  (kill-buffer "*TG Config: creature*"))

;; --- Map config ---

(ert-deftest test-tg-gen-parse-map-single-row ()
  "Should parse single row map."
  (let ((result (tg-gen-parse-map-config "room1 room2")))
    (should (equal result '((room1 room2))))))

(ert-deftest test-tg-gen-parse-map-multi-row ()
  "Should parse multi-row map."
  (let ((result (tg-gen-parse-map-config "room1 room2\nroom3 room4")))
    (should (equal result '((room1 room2) (room3 room4))))))

(ert-deftest test-tg-gen-parse-map-skip-comments ()
  "Should skip comment lines."
  (let ((result (tg-gen-parse-map-config "# comment\nroom1 room2\n\nroom3 room4")))
    (should (equal result '((room1 room2) (room3 room4))))))

(ert-deftest test-tg-gen-map-config-creates-buffer ()
  "tg-gen-map-config should create a config buffer."
  (tg-gen-map-config)
  (should (get-buffer "*TG Config: map*"))
  (with-current-buffer "*TG Config: map*"
    (should (eq tg-config-type 'map)))
  (kill-buffer "*TG Config: map*"))

(provide 'test-tg-config-generator)
