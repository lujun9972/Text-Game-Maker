;;; test-room-maker.el --- Tests for room-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'room-maker)

;; --- get-room-by-symbol ---

(ert-deftest test-get-room-by-symbol-found ()
  "get-room-by-symbol should return the room when symbol exists."
  (test-with-globals-saved (rooms-alist)
    (let ((room (test-make-room :symbol 'hall :description "A grand hall")))
      (setq rooms-alist (list (cons 'hall room)))
      (should (eq (get-room-by-symbol 'hall) room)))))

(ert-deftest test-get-room-by-symbol-not-found ()
  "get-room-by-symbol should return nil when symbol doesn't exist."
  (test-with-globals-saved (rooms-alist)
    (setq rooms-alist nil)
    (should (null (get-room-by-symbol 'nonexistent)))))

(ert-deftest test-get-room-by-symbol-empty-alist ()
  "get-room-by-symbol should return nil when rooms-alist is empty."
  (test-with-globals-saved (rooms-alist)
    (setq rooms-alist nil)
    (should (null (get-room-by-symbol 'anything)))))

;; --- build-room ---

(ert-deftest test-build-room-from-tuple ()
  "build-room should create a room from a tuple."
  (let* ((result (build-room '(kitchen "A kitchen" (knife) (cook))))
         (room (cdr result)))
    (should (equal (car result) 'kitchen))
    (should (equal (member-symbol room) 'kitchen))
    (should (equal (member-description room) "A kitchen"))
    (should (equal (member-inventory room) '(knife)))
    (should (equal (member-creature room) '(cook)))))

(ert-deftest test-build-room-minimal ()
  "build-room should work with minimal tuple (just symbol and description)."
  (let* ((result (build-room '(cellar "A dark cellar")))
           (room (cdr result)))
      (should (equal (car result) 'cellar))
      (should (equal (member-symbol room) 'cellar))
      (should (equal (member-description room) "A dark cellar"))
      (should (null (member-inventory room)))
      (should (null (member-creature room)))))

;; --- build-rooms ---

(ert-deftest test-build-rooms-from-file ()
  "build-rooms should read config file and create rooms."
  (test-with-temp-file "((room1 \"Room One\" (key) ())
                         (room2 \"Room Two\" () (goblin)))"
    (test-with-globals-saved (rooms-alist)
      (let ((results (build-rooms temp-file)))
        (should (= (length results) 2))
        (should (equal (member-symbol (cdar results)) 'room1))
        (should (equal (member-symbol (cdadr results)) 'room2))))))

;; --- inventory operations ---

(ert-deftest test-add-inventory-to-room ()
  "add-inventory-to-room should add inventory to room."
  (let ((room (test-make-room :symbol 'room1 :description "test")))
    (add-inventory-to-room room 'sword)
    (should (member 'sword (member-inventory room)))))

(ert-deftest test-remove-inventory-from-room ()
  "remove-inventory-from-room should remove inventory from room."
  (let ((room (test-make-room :symbol 'room1 :description "test" :inventory '(sword potion))))
    (remove-inventory-from-room room 'sword)
    (should-not (member 'sword (member-inventory room)))
    (should (member 'potion (member-inventory room)))))

(ert-deftest test-inventory-exist-in-room-p ()
  "inventory-exist-in-room-p should check inventory presence."
  (let ((room (test-make-room :symbol 'room1 :description "test" :inventory '(sword potion))))
    (should (inventory-exist-in-room-p room 'sword))
    (should-not (inventory-exist-in-room-p room 'armor))))

;; --- creature operations ---

(ert-deftest test-add-creature-to-room ()
  "add-creature-to-room should add creature to room."
  (let ((room (test-make-room :symbol 'room1 :description "test")))
    (add-creature-to-room room 'goblin)
    (should (member 'goblin (member-creature room)))))

(ert-deftest test-remove-creature-from-room ()
  "remove-creature-from-room should remove creature from room."
  (let ((room (test-make-room :symbol 'room1 :description "test" :creature '(goblin orc))))
    (remove-creature-from-room room 'goblin)
    (should-not (member 'goblin (member-creature room)))
    (should (member 'orc (member-creature room)))))

(ert-deftest test-creature-exist-in-room-p ()
  "creature-exist-in-room-p should check creature presence."
  (let ((room (test-make-room :symbol 'room1 :description "test" :creature '(goblin))))
    (should (creature-exist-in-room-p room 'goblin))
    (should-not (creature-exist-in-room-p room 'dragon))))

;; --- build-room-map ---

(ert-deftest test-build-room-map-from-file ()
  "build-room-map should parse a map config file."
  (test-with-temp-file "room1 room2 room3\nroom4 room5 room6"
    (let ((rmap (build-room-map temp-file)))
      (should (equal rmap '((room1 room2 room3) (room4 room5 room6)))))))

(ert-deftest test-build-room-map-single-row ()
  "build-room-map should handle a single-row map."
  (test-with-temp-file "room1 room2 room3"
    (let ((rmap (build-room-map temp-file)))
      (should (equal rmap '((room1 room2 room3)))))))

;; --- get-room-position ---

(ert-deftest test-get-room-position-center ()
  "get-room-position should return correct coordinates for center room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (get-room-position 'e rmap) '(1 1)))))

(ert-deftest test-get-room-position-corner ()
  "get-room-position should return correct coordinates for corner room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (get-room-position 'a rmap) '(0 0)))
    (should (equal (get-room-position 'i rmap) '(2 2)))))

(ert-deftest test-get-room-position-nonexistent ()
  "get-room-position should handle nonexistent room symbol."
  (let ((rmap '((a b c))))
    ;; This will error because cl-position-if returns nil, then nth on nil
    (should-error (get-room-position 'z rmap))))

;; --- beyond-rooms ---

(ert-deftest test-beyond-rooms-center ()
  "beyond-rooms should return all 4 neighbors for center room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (beyond-rooms 'e rmap) '(b f h d)))))

(ert-deftest test-beyond-rooms-corners ()
  "beyond-rooms should return nil for edges without neighbors."
  (let ((rmap '((a b c) (d e f) (g h i))))
    ;; top-left corner: up=nil, right=b, down=d, left=nil
    (should (equal (beyond-rooms 'a rmap) '(nil b d nil)))))

(ert-deftest test-beyond-rooms-edge ()
  "beyond-rooms should return partial neighbors for edge room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    ;; top-middle: up=nil, right=c, down=e, left=a
    (should (equal (beyond-rooms 'b rmap) '(nil c e a)))))

;; --- map-init ---

(ert-deftest test-map-init ()
  "map-init should initialize rooms, map, and current room."
  (test-with-temp-file "((room1 \"Room One\") (room2 \"Room Two\"))"
    (let ((map-file (make-temp-file "tg-map-test-" nil ".el")))
      (unwind-protect
          (progn
            (write-region "room1 room2\nroom1 room2" nil map-file)
            (test-with-globals-saved (rooms-alist room-map currect-room)
              (map-init temp-file map-file)
              (should (= (length rooms-alist) 2))
              (should (= (length room-map) 2))
              (should (equal (member-symbol currect-room) 'room1))))
        (delete-file map-file)))))

;; --- describe ---

(ert-deftest test-describe-room ()
  "describe should return a formatted description of the room."
  (test-with-globals-saved (room-map)
    (setq room-map '((room1 room2) (room3 room4)))
    (let ((room (test-make-room :symbol 'room1 :description "A test room"
                                :inventory '(key) :creature '(cat))))
      (let ((desc (describe room)))
        (should (string-match-p "room1" desc))
        (should (string-match-p "A test room" desc))))))

(provide 'test-room-maker)
