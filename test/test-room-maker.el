;;; test-room-maker.el --- Tests for room-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'room-maker)

;; --- tg-get-room-by-symbol ---

(ert-deftest test-tg-get-room-by-symbol-found ()
  "tg-get-room-by-symbol should return the room when symbol exists."
  (test-with-globals-saved (tg-rooms-alist)
    (let ((room (test-make-room :symbol 'hall :description "A grand hall")))
      (setq tg-rooms-alist (list (cons 'hall room)))
      (should (eq (tg-get-room-by-symbol 'hall) room)))))

(ert-deftest test-tg-get-room-by-symbol-not-found ()
  "tg-get-room-by-symbol should return nil when symbol doesn't exist."
  (test-with-globals-saved (tg-rooms-alist)
    (setq tg-rooms-alist nil)
    (should (null (tg-get-room-by-symbol 'nonexistent)))))

(ert-deftest test-tg-get-room-by-symbol-empty-alist ()
  "tg-get-room-by-symbol should return nil when tg-rooms-alist is empty."
  (test-with-globals-saved (tg-rooms-alist)
    (setq tg-rooms-alist nil)
    (should (null (tg-get-room-by-symbol 'anything)))))

;; --- tg-build-room ---

(ert-deftest test-build-room-from-tuple ()
  "tg-build-room should create a room from a tuple."
  (let* ((result (tg-build-room '(kitchen "A kitchen" (knife) (cook))))
         (room (cdr result)))
    (should (equal (car result) 'kitchen))
    (should (equal (Room-symbol room) 'kitchen))
    (should (equal (Room-description room) "A kitchen"))
    (should (equal (Room-inventory room) '(knife)))
    (should (equal (Room-creature room) '(cook)))))

(ert-deftest test-build-room-minimal ()
  "tg-build-room should work with minimal tuple (just symbol and description)."
  (let* ((result (tg-build-room '(cellar "A dark cellar")))
           (room (cdr result)))
      (should (equal (car result) 'cellar))
      (should (equal (Room-symbol room) 'cellar))
      (should (equal (Room-description room) "A dark cellar"))
      (should (null (Room-inventory room)))
      (should (null (Room-creature room)))))

;; --- tg-room-init ---

(ert-deftest test-room-init-from-file ()
  "tg-room-init should read config file and create rooms."
  (test-with-temp-file "(room1 \"Room One\" (key) ())
                         (room2 \"Room Two\" () (goblin))"
    (test-with-globals-saved (tg-rooms-alist)
      (tg-room-init temp-file)
      (should (= (length tg-rooms-alist) 2))
      (should (equal (Room-symbol (cdar tg-rooms-alist)) 'room1))
      (should (equal (Room-symbol (cdadr tg-rooms-alist)) 'room2)))))

;; --- inventory operations ---

(ert-deftest test-tg-add-inventory-to-room ()
  "tg-add-inventory-to-room should add inventory to room."
  (let ((room (test-make-room :symbol 'room1 :description "test")))
    (tg-add-inventory-to-room room 'sword)
    (should (member 'sword (Room-inventory room)))))

(ert-deftest test-tg-remove-inventory-from-room ()
  "tg-remove-inventory-from-room should remove inventory from room."
  (let ((room (test-make-room :symbol 'room1 :description "test" :inventory '(sword potion))))
    (tg-remove-inventory-from-room room 'sword)
    (should-not (member 'sword (Room-inventory room)))
    (should (member 'potion (Room-inventory room)))))

(ert-deftest test-tg-inventory-exist-in-room-p ()
  "tg-inventory-exist-in-room-p should check inventory presence."
  (let ((room (test-make-room :symbol 'room1 :description "test" :inventory '(sword potion))))
    (should (tg-inventory-exist-in-room-p room 'sword))
    (should-not (tg-inventory-exist-in-room-p room 'armor))))

;; --- creature operations ---

(ert-deftest test-tg-add-creature-to-room ()
  "tg-add-creature-to-room should add creature to room."
  (let ((room (test-make-room :symbol 'room1 :description "test")))
    (tg-add-creature-to-room room 'goblin)
    (should (member 'goblin (Room-creature room)))))

(ert-deftest test-tg-remove-creature-from-room ()
  "tg-remove-creature-from-room should remove creature from room."
  (let ((room (test-make-room :symbol 'room1 :description "test" :creature '(goblin orc))))
    (tg-remove-creature-from-room room 'goblin)
    (should-not (member 'goblin (Room-creature room)))
    (should (member 'orc (Room-creature room)))))

(ert-deftest test-tg-creature-exist-in-room-p ()
  "tg-creature-exist-in-room-p should check creature presence."
  (let ((room (test-make-room :symbol 'room1 :description "test" :creature '(goblin))))
    (should (tg-creature-exist-in-room-p room 'goblin))
    (should-not (tg-creature-exist-in-room-p room 'dragon))))

;; --- tg-build-room-map ---

(ert-deftest test-tg-build-room-map-from-file ()
  "tg-build-room-map should parse a map config file."
  (test-with-temp-file "room1 room2 room3\nroom4 room5 room6"
    (let ((rmap (tg-build-room-map temp-file)))
      (should (equal rmap '((room1 room2 room3) (room4 room5 room6)))))))

(ert-deftest test-tg-build-room-map-single-row ()
  "tg-build-room-map should handle a single-row map."
  (test-with-temp-file "room1 room2 room3"
    (let ((rmap (tg-build-room-map temp-file)))
      (should (equal rmap '((room1 room2 room3)))))))

;; --- tg-get-room-position ---

(ert-deftest test-tg-get-room-position-center ()
  "tg-get-room-position should return correct coordinates for center room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (tg-get-room-position 'e rmap) '(1 1)))))

(ert-deftest test-tg-get-room-position-corner ()
  "tg-get-room-position should return correct coordinates for corner room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (tg-get-room-position 'a rmap) '(0 0)))
    (should (equal (tg-get-room-position 'i rmap) '(2 2)))))

(ert-deftest test-tg-get-room-position-nonexistent ()
  "tg-get-room-position should handle nonexistent room symbol."
  (let ((rmap '((a b c))))
    ;; This will error because cl-position-if returns nil, then nth on nil
    (should-error (tg-get-room-position 'z rmap))))

;; --- tg-beyond-rooms ---

(ert-deftest test-tg-beyond-rooms-center ()
  "tg-beyond-rooms should return all 4 neighbors for center room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    (should (equal (tg-beyond-rooms 'e rmap) '(b f h d)))))

(ert-deftest test-tg-beyond-rooms-corners ()
  "tg-beyond-rooms should return nil for edges without neighbors."
  (let ((rmap '((a b c) (d e f) (g h i))))
    ;; top-left corner: up=nil, right=b, down=d, left=nil
    (should (equal (tg-beyond-rooms 'a rmap) '(nil b d nil)))))

(ert-deftest test-tg-beyond-rooms-edge ()
  "tg-beyond-rooms should return partial neighbors for edge room."
  (let ((rmap '((a b c) (d e f) (g h i))))
    ;; top-middle: up=nil, right=c, down=e, left=a
    (should (equal (tg-beyond-rooms 'b rmap) '(nil c e a)))))

;; --- tg-map-init ---

(ert-deftest test-tg-map-init ()
  "tg-map-init should initialize rooms, map, and current room."
  (test-with-temp-file "(room1 \"Room One\") (room2 \"Room Two\")"
    (let ((map-file (make-temp-file "tg-map-test-" nil ".el")))
      (unwind-protect
          (progn
            (write-region "room1 room2\nroom1 room2" nil map-file)
            (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room)
              (tg-map-init temp-file map-file)
              (should (= (length tg-rooms-alist) 2))
              (should (= (length tg-room-map) 2))
              (should (equal (Room-symbol tg-current-room) 'room1))))
        (delete-file map-file)))))

;; --- describe ---

(ert-deftest test-describe-room ()
  "describe should return a formatted description of the room."
  (test-with-globals-saved (tg-room-map)
    (setq tg-room-map '((room1 room2) (room3 room4)))
    (let ((room (test-make-room :symbol 'room1 :description "A test room"
                                :inventory '(key) :creature '(cat))))
      (let ((desc (describe room)))
        (should (string-match-p "room1" desc))
        (should (string-match-p "A test room" desc))))))

(provide 'test-room-maker)
