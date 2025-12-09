package Src.Prog.Core.Managers {
    import flash.geom.Point;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Core.Menus.ContextMenu;

    /**
     * Centralized manager for all context menus in the application.
     * Updated for Contact-only system (Track system removed).
     */
    public class MenuManager {
        
        /** Singleton instance reference */
        private static var _instance:MenuManager;
        
        /** Currently open menu reference for state management */
        private var _currentMenu:ContextMenu;

        /**
         * Private constructor for singleton pattern.
         */
        public function MenuManager() {
            if (_instance) {
                throw new Error("MenuManager is singleton. Use getInstance() instead.");
            }
            setupImpulseListeners();
        }

        /**
         * Gets the singleton instance of MenuManager.
         */
        public static function getInstance():MenuManager {
            if (!_instance) {
                _instance = new MenuManager();
            }
            return _instance;
        }

        /**
         * Initializes the MenuManager system.
         */
        public static function initialize():void {
            getInstance();
        }

        /**
         * Sets up impulse listeners for menu control system.
         * Updated for Contact-only system.
         */
        private function setupImpulseListeners():void {
            // Context menu creation triggers
            Impulsys.subscribeToImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            Impulsys.subscribeToImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            
            // 🔥 ТОЛЬКО Link (Contact система) - Track удалён
            Impulsys.subscribeToImpulse("LINK_RIGHT_CLICK", onLinkRightClick);

            // Menu closing triggers
            Impulsys.subscribeToImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            Impulsys.subscribeToImpulse("WINDOW_CLICK", closeCurrentMenu);
            Impulsys.subscribeToImpulse("KEY_ESC_PRESSED", closeCurrentMenu);

            // System cleanup
            Impulsys.subscribeToImpulse("APP_CLOSE", onAppClose);
        }

        // =========================================================================
        // IMPULSE HANDLERS - CONTEXT MENU CREATION
        // =========================================================================

        /**
         * Handles window background right-click for atom creation menu.
         */
        private function onWindowRightClick(impulse:Impulse):void {
            trace("MenuManager: Window right click Impulse received");
            var globalPos:Point = impulse.data.globalPosition;
            var localPos:Point = impulse.data.localPosition;
            var window:Window = findWindowByType(impulse.data.windowType);

            if (window) {
                closeCurrentMenu();
                showCreationMenu(globalPos, localPos, window);
            }
        }

        /**
         * Handles atom right-click for atom-specific operations menu.
         */
        private function onAtomRightClick(impulse:Impulse):void {
            trace("MenuManager: Atom right click received");
            var atom:Atom = impulse.data.atom;
            var globalPos:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (atom && window) {
                closeCurrentMenu();
                showAtomOptionsMenu(globalPos, atom, window);
            }
        }

        /**
         * 🔥 НОВЫЙ: Handles Link right-click for connection management menu.
         * Replaces old Track menu.
         */
        private function onLinkRightClick(impulse:Impulse):void {
            trace("MenuManager: Link right click received");
            var link:Object = impulse.data.link;
            var globalPos:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (link && window) {
                closeCurrentMenu();
                showLinkMenu(globalPos, link, window);
            }
        }

        /**
         * Handles application shutdown for resource cleanup.
         */
        private function onAppClose(impulse:Impulse):void {
            closeCurrentMenu();
            dispose();
        }

        // =========================================================================
        // MENU CREATION METHODS
        // =========================================================================

        /**
         * Shows dynamic atom creation menu built from AtomDefinitions registry.
         */
        private function showCreationMenu(globalPosition:Point, localPosition:Point, window:Window):void {
            try {
                var items:Array = [];
                var types:Array = AtomDefinitions.getSupportedTypes();

                // Build menu items from all registered atom types
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

                // Sort items by category and label for better UX
                items.sortOn(["category", "label"]);

                // Create and display context menu
                var menu:ContextMenu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
                
                trace("MenuManager: Creation menu displayed successfully");
            } catch (error:Error) {
                trace("MenuManager: ERROR creating creation menu: " + error.message);
            }
        }

        /**
         * Factory function for atom creation callbacks.
         */
        private function createAtomCallback(atomType:String, position:Point):Function {
            return function(action:String):void {
                _currentMenu.close();
                Impulsys.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
                    atomType: atomType,
                    position: position
                }));
            };
        }

        /**
         * Shows atom-specific options menu with operations like delete and properties.
         */
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
                
                trace("MenuManager: Atom options menu displayed successfully");
            } catch (error:Error) {
                trace("MenuManager: ERROR creating atom options menu: " + error.message);
            }
        }

        /**
         * 🔥 НОВЫЙ: Shows Link-specific options menu for connection management.
         * Replaces old showTrackMenu().
         */
        private function showLinkMenu(globalPosition:Point, link:Object, window:Window):void {
            try {
                var menu:ContextMenu;
                var items:Array = [{
                    label: "Delete Link",
                    action: "delete_link",
                    callback: function(action:String):void {
                        menu.close();
                        // Прямое удаление Link
                        if (link && link.dispose is Function) {
                            link.dispose();
                        }
                    },
                    category: "Danger"
                }];

                menu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
                
                trace("MenuManager: Link menu displayed successfully");
            } catch (error:Error) {
                trace("MenuManager: ERROR creating link menu: " + error.message);
            }
        }

        // =========================================================================
        // MENU CONTROL AND LIFECYCLE MANAGEMENT
        // =========================================================================

        /**
         * Closes the currently open context menu if one exists.
         */
        public function closeCurrentMenu(impulse:Impulse = null):void {
            if (_currentMenu) {
                try {
                    _currentMenu.close();
                } catch (e:Error) {
                    trace("MenuManager: Error closing menu: " + e.message);
                }
                _currentMenu = null;
                trace("MenuManager: Current menu closed");
            }
        }

        /**
         * Checks if a context menu is currently open and visible.
         */
        public function isMenuOpen():Boolean {
            return _currentMenu != null;
        }

        /**
         * Finds a window by type using WindowsManager.
         */
        private function findWindowByType(windowType:String):Window {
            var windowsManager:WindowsManager = WindowsManager.getInstance();
            return windowsManager ? windowsManager.findWindow(windowType) : null;
        }

        // =========================================================================
        // RESOURCE CLEANUP AND DISPOSAL
        // =========================================================================

        /**
         * Cleans up all MenuManager resources and unsubscribes from impulses.
         */
        public function dispose():void {
            closeCurrentMenu();

            // Unsubscribe from all impulses to prevent memory leaks
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