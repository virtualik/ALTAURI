package Src.Managers {
    import flash.geom.Point;
    import Src.Impulsator.Impulsys;
    import Src.Impulsator.Impulse;
    import Src.Windows.Window;
    import Src.Atom.Core.Atom;
    import Src.Atom.Data.AtomDefinitions;
    import Src.ContextMenu.ContextMenu;

    public class MenuManager {
        private static var _instance:MenuManager;
        private var _currentMenu:ContextMenu;

        public function MenuManager() {
            if (_instance) {
                throw new Error("MenuManager is singleton. Use getInstance() instead.");
            }
            setupImpulseListeners();
        }

        public static function getInstance():MenuManager {
            if (!_instance) {
                _instance = new MenuManager();
            }
            return _instance;
        }

        public static function initialize():void {
            getInstance();
        }

        private function setupImpulseListeners():void {
            Impulsys.subscribeToImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            Impulsys.subscribeToImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            Impulsys.subscribeToImpulse("LINK_RIGHT_CLICK", onLinkRightClick);
            Impulsys.subscribeToImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            Impulsys.subscribeToImpulse("WINDOW_CLICK", closeCurrentMenu);
            Impulsys.subscribeToImpulse("KEY_ESC_PRESSED", closeCurrentMenu);
            Impulsys.subscribeToImpulse("APP_CLOSE", onAppClose);
        }

        private function onWindowRightClick(impulse:Impulse):void {
            var globalPos:Point = impulse.data.globalPosition;
            var localPos:Point = impulse.data.localPosition;
            var window:Window = findWindowByType(impulse.data.windowType);

            if (window) {
                closeCurrentMenu();
                showCreationMenu(globalPos, localPos, window);
            }
        }

        private function onAtomRightClick(impulse:Impulse):void {
            var atom:Atom = impulse.data.atom;
            var globalPos:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (atom && window) {
                closeCurrentMenu();
                showAtomOptionsMenu(globalPos, atom, window);
            }
        }

        private function onLinkRightClick(impulse:Impulse):void {
            var link:Object = impulse.data.link;
            var globalPos:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (link && window) {
                closeCurrentMenu();
                showLinkMenu(globalPos, link, window);
            }
        }

        private function onAppClose(impulse:Impulse):void {
            closeCurrentMenu();
            dispose();
        }

        private function showCreationMenu(globalPosition:Point, localPosition:Point, window:Window):void {
            try {
                var items:Array = [];
                var types:Array = AtomDefinitions.getSupportedTypes();

                for each (var type:String in types) {
                    var def:Object = AtomDefinitions.getAtomDefinition(type);
                    if (def) {
                        items.push({
                            label: (def.displayName || type) + " (" + (def.category || "General") + ")",
                            action: type,
                            callback: createAtomCallback(type, localPosition),
                            category: def.category || "General"
                        });
                    }
                }

                items.sortOn(["category", "label"]);

                var menu:ContextMenu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
            } catch (error:Error) {
            }
        }

        private function createAtomCallback(atomType:String, position:Point):Function {
            return function(action:String):void {
                _currentMenu.close();
                Impulsys.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
                    atomType: atomType,
                    position: position
                }));
            };
        }

        private function showAtomOptionsMenu(globalPosition:Point, atom:Atom, window:Window):void {
            try {
                var menu:ContextMenu;
                var items:Array = [
                    {
                        label: "Delete Atom",
                        action: "delete",
                        callback: function(action:String):void {
                            menu.close();
                            Impulsys.emit(new Impulse("ATOM_DELETE_REQUEST", { atom: atom }));
                        },
                        category: "Danger"
                    },
                    {
                        label: "Properties",
                        action: "properties",
                        callback: function(action:String):void {
                            menu.close();
                            Impulsys.emit(new Impulse("ATOM_PROPERTIES_REQUEST", { atom: atom }));
                        },
                        category: "Info"
                    }
                ];

                menu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
            } catch (error:Error) {
            }
        }

        private function showLinkMenu(globalPosition:Point, link:Object, window:Window):void {
            try {
                var menu:ContextMenu;
                var items:Array = [{
                    label: "Delete Link",
                    action: "delete_link",
                    callback: function(action:String):void {
                        menu.close();
                        if (link && link.dispose is Function) {
                            link.dispose();
                        }
                    },
                    category: "Danger"
                }];

                menu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
            } catch (error:Error) {
            }
        }

        public function closeCurrentMenu(impulse:Impulse = null):void {
            if (_currentMenu) {
                try {
                    _currentMenu.close();
                } catch (e:Error) {
                }
                _currentMenu = null;
            }
        }

        public function isMenuOpen():Boolean {
            return _currentMenu != null;
        }

        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            return windowsManager ? windowsManager.findWindow(windowType) : null;
        }

        public function dispose():void {
            closeCurrentMenu();

            Impulsys.removeImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            Impulsys.removeImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            Impulsys.removeImpulse("LINK_RIGHT_CLICK", onLinkRightClick);
            Impulsys.removeImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            Impulsys.removeImpulse("WINDOW_CLICK", closeCurrentMenu);
            Impulsys.removeImpulse("KEY_ESC_PRESSED", closeCurrentMenu);
            Impulsys.removeImpulse("APP_CLOSE", onAppClose);

            _currentMenu = null;
        }
    }
}
