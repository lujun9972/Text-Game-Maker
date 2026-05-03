;;; test-save-system.el --- Tests for save-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)
(require 'save-system)

;; --- tg-serialize-creature ---

(ert-deftest test-serialize-creature-full ()
  "tg-serialize-creature should serialize all serializable fields."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin"
                            :attr '((hp . 25) (attack . 6))
                            :inventory '(potion)
                            :equipment '(sword)
                            :behaviors '(((always) attack)))))
    (let ((data (tg-serialize-creature cr)))
      (should (equal (cdr (assoc 'symbol data)) 'goblin))
      (should (equal (cdr (assoc 'attr data)) '((hp . 25) (attack . 6))))
      (should (equal (cdr (assoc 'inventory data)) '(potion)))
      (should (equal (cdr (assoc 'equipment data)) '(sword)))
      (should (equal (cdr (assoc 'behaviors data)) '(((always) attack)))))))

(ert-deftest test-serialize-creature-empty-lists ()
  "tg-serialize-creature should handle empty inventory/equipment."
  (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100)))))
    (let ((data (tg-serialize-creature cr)))
      (should (null (cdr (assoc 'inventory data))))
      (should (null (cdr (assoc 'equipment data))))
      (should (null (cdr (assoc 'behaviors data)))))))

;; --- tg-serialize-room ---

(ert-deftest test-serialize-room-with-items-and-creatures ()
  "tg-serialize-room should serialize inventory and creature list."
  (let ((room (make-Room :symbol 'hall :description "A hall"
                          :inventory '(torch key) :creature '(goblin bat))))
    (let ((data (tg-serialize-room room)))
      (should (equal (cdr (assoc 'inventory data)) '(torch key)))
      (should (equal (cdr (assoc 'creature data)) '(goblin bat))))))

(ert-deftest test-serialize-room-empty ()
  "tg-serialize-room should handle empty room."
  (let ((room (make-Room :symbol 'empty :description "Empty room")))
    (let ((data (tg-serialize-room room)))
      (should (null (cdr (assoc 'inventory data))))
      (should (null (cdr (assoc 'creature data)))))))

;; --- tg-save-game ---

(ert-deftest test-save-game-creates-file ()
  "tg-save-game should create a save file."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-creatures-alist tg-myself tg-display-fn)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(potion) :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25))))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero hero)))
      (setq tg-myself hero)
      (tg-save-game save-file)
      (should (file-exists-p save-file))
      (delete-file save-file))))

(ert-deftest test-save-game-tg-file-content ()
  "tg-save-game should write correct alist data."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-creatures-alist tg-myself tg-display-fn)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(torch) :creature '(hero)))
           (hero (make-Creature :symbol 'hero :attr '((hp . 100)) :inventory '(sword) :equipment '(shield)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-creatures-alist (list (cons 'hero hero)))
      (setq tg-myself hero)
      (unwind-protect
          (progn
            (tg-save-game save-file)
            (let* ((content (tg-file-content save-file))
                   (data (read content)))
              ;; Check player data
              (should (equal (cdr (assoc 'tg-current-room data)) 'room1))
              (should (equal (cdr (assoc 'symbol (cdr (assoc 'player data)))) 'hero))
              (should (equal (cdr (assoc 'inventory (cdr (assoc 'player data)))) '(sword)))
              ;; Check rooms data
              (let ((room-data (cdr (assoc 'room1 (cdr (assoc 'rooms data))))))
                (should (equal (cdr (assoc 'inventory room-data)) '(torch))))))
        (delete-file save-file)))))

;; --- tg-load-game round-trip ---

(ert-deftest test-save-load-round-trip ()
  "Saving and loading should preserve game state."
  (test-with-globals-saved (tg-rooms-alist tg-room-map tg-current-room tg-creatures-alist tg-myself tg-display-fn
                                        tg-config-dir tg-over-p)
    (let* ((room (make-Room :symbol 'room1 :description "Room 1" :inventory '(torch) :creature '(hero goblin)))
           (goblin (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6)) :inventory '() :equipment '()))
           (hero (make-Creature :symbol 'hero :attr '((hp . 85) (attack . 10)) :inventory '(sword) :equipment '(shield)))
           (save-file (make-temp-file "tg-save-test-" nil ".sav"))
           (output nil))
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (setq tg-rooms-alist (list (cons 'room1 room)))
      (setq tg-room-map '((room1)))
      (setq tg-current-room room)
      (setq tg-creatures-alist (list (cons 'goblin goblin) (cons 'hero hero)))
      (setq tg-myself hero)
      (setq tg-over-p nil)
      (setq tg-config-dir nil)
      (unwind-protect
          (progn
            (tg-save-game save-file)
            ;; Modify state to prove load restores it
            (setf (Creature-attr tg-myself) '((hp . 1)))
            (setf (Creature-inventory tg-myself) nil)
            ;; Load (tg-config-dir is nil, so no re-init)
            (tg-load-game save-file)
            ;; Verify restored state
            (should (= (cdr (assoc 'hp (Creature-attr tg-myself))) 85))
            (should (equal (Creature-inventory tg-myself) '(sword)))
            (should (equal (Creature-equipment tg-myself) '(shield)))
            (should (equal (Room-symbol tg-current-room) 'room1)))
        (when (file-exists-p save-file)
          (delete-file save-file))))))

;; --- Error handling ---

(ert-deftest test-load-nonexistent-file ()
  "tg-load-game should throw exception for nonexistent file."
  (test-with-globals-saved (tg-display-fn)
    (setq tg-display-fn #'ignore)
    (should (equal (catch 'exception (tg-load-game "/nonexistent/path/save.sav"))
                   "存档文件不存在"))))

;; --- Shop save/load ---

(ert-deftest test-tg-save-restore-player-gold ()
  "Save/restore should persist player-gold."
  (test-with-globals-saved (player-gold tg-current-room tg-rooms-alist tg-room-map tg-creatures-alist
                        shop-alist tg-myself tg-over-p tg-config-dir)
    (setq player-gold 42)
    (setq tg-over-p nil)
    (setq tg-config-dir nil)
    (setq tg-creatures-alist nil)
    (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
    (push (cons 'hero tg-myself) tg-creatures-alist)
    (setq tg-rooms-alist nil)
    (setq tg-current-room (make-Room :symbol 'start :description "Start"))
    (push (cons 'start tg-current-room) tg-rooms-alist)
    (setq tg-room-map '((start)))
    (setq shop-alist nil)
    (test-with-temp-file ""
      (tg-save-game temp-file)
      (setq player-gold 0)
      (tg-load-game temp-file)
      (should (= player-gold 42)))))

(ert-deftest test-tg-save-restore-shop-alist ()
  "Save/restore should persist shop-alist."
  (test-with-globals-saved (player-gold tg-current-room tg-rooms-alist tg-room-map tg-creatures-alist
                        shop-alist tg-myself tg-over-p tg-config-dir)
    (setq player-gold 0)
    (setq tg-over-p nil)
    (setq tg-config-dir nil)
    (setq tg-creatures-alist nil)
    (setq tg-myself (make-Creature :symbol 'hero :attr '((hp . 100))))
    (push (cons 'hero tg-myself) tg-creatures-alist)
    (setq tg-rooms-alist nil)
    (setq tg-current-room (make-Room :symbol 'start :description "Start"))
    (push (cons 'start tg-current-room) tg-rooms-alist)
    (setq tg-room-map '((start)))
    (setq shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.5 :goods '((sword . 50))))))
    (test-with-temp-file ""
      (tg-save-game temp-file)
      (setq shop-alist nil)
      (tg-load-game temp-file)
      (should (assoc 'merchant shop-alist))
      (should (= (shop-get-sell-rate 'merchant) 0.5))
      (should (= (shop-get-item-price 'merchant 'sword) 50)))))

(provide 'test-save-system)
