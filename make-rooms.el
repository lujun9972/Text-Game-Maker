(add-to-list 'load-path (pwd))
(defvar display-fn #'message
  "显示信息的函数")
(require 'room-maker)
(map-init "room-description.el" "room-map.ini")
(require 'inventory-maker)
(inventorys-init "inventory-config.el")
(require 'creature-maker)
(creatures-init "creature-config.el")
(require 'action)
(watch )
(move right)
(get '案板)
(describe myself)