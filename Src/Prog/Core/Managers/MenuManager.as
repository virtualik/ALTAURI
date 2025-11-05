package Src.Prog.Core.Managers {
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Com.Menus.ContextMenu;

    /**
     * Centralized manager for all context menus in the application.
     * Coordinates menu creation, display, and lifecycle management for LKM and RKM operations.
     * Uses a single, parameterized ContextMenu class to handle all menu types dynamically.
     * 
     * Key Responsibilities:
     * - Processes right-click impulses for context menu creation
     * - Manages menu lifecycle and automatic closing
     * - Dynamically builds menus from atom definitions
     * - Handles menu item callbacks and action execution
     * - Integrates with MultiPulsator system for event coordination
     * 
     * @class MenuManager
     * @public
     */
    public class MenuManager {
        
        /** Singleton instance reference */
        private static var _instance:MenuManager;
        
        /** Currently open menu reference for state management */
        private var _currentMenu:ContextMenu;

        /**
         * Private constructor for singleton pattern.
         * Initializes impulse listeners upon instantiation.
         * 
         * @constructor
         * @private
         */
        public function MenuManager() {
            setupImpulseListeners();
        }

        /**
         * Gets the singleton instance of MenuManager.
         * Implements lazy initialization for optimal resource usage.
         * 
         * @static
         * @public
         * @return {MenuManager} Singleton MenuManager instance
         */
        public static function getInstance():MenuManager {
            if (!_instance) {
                _instance = new MenuManager();
            }
            return _instance;
        }

        /**
         * Initializes the MenuManager system.
         * Ensures singleton is created and ready for operation.
         * 
         * @static
         * @public
         */
        public static function initialize():void {
            getInstance();
        }

        /**
         * Sets up all impulse listeners for menu control system.
         * Subscribes to user interaction and system events that affect menu behavior.
         * Establishes comprehensive menu lifecycle management.
         * 
         * @private
         */
        private function setupImpulseListeners():void {
            // Context menu creation triggers
            MultiPulsator.subscribeToImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            MultiPulsator.subscribeToImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            MultiPulsator.subscribeToImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);

            // Menu closing triggers
            MultiPulsator.subscribeToImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            MultiPulsator.subscribeToImpulse("WINDOW_CLICK", closeCurrentMenu);
            MultiPulsator.subscribeToImpulse("KEY_ESC_PRESSED", closeCurrentMenu);

            // System cleanup
            MultiPulsator.subscribeToImpulse("APP_CLOSE", onAppClose);
        }

        // =========================================================================
        // IMPULSE HANDLERS - CONTEXT MENU CREATION
        // =========================================================================

        /**
         * Handles window background right-click for atom creation menu.
         * Dynamically builds menu from registered atom definitions in AtomDefinitions.
         * 
         * @private
         * @param {Impulse} impulse - WINDOW_RIGHT_CLICK impulse containing position and window data
         */
        private function onWindowRightClick(impulse:Impulse):void {
            trace("MenuManager: Window right click received");
            var globalPos:Point = impulse.data.globalPosition;
            var localPos:Point = impulse.data.localPosition;
            var window:Window = impulse.data.window;

            if (window) {
                closeCurrentMenu();
                showCreationMenu(globalPos, localPos, window);
            }
        }

        /**
         * Handles atom right-click for atom-specific operations menu.
         * Provides context-sensitive options like delete and properties.
         * 
         * @private
         * @param {Impulse} impulse - ATOM_RIGHT_CLICK impulse containing atom and position data
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
         * Handles track right-click for connection management menu.
         * Provides track-specific operations like deletion.
         * 
         * @private
         * @param {Impulse} impulse - TRACK_RIGHT_CLICK impulse containing track and position data
         */
        private function onTrackRightClick(impulse:Impulse):void {
            trace("MenuManager: Track right click received");
            var track:Track = impulse.data.track;
            var globalPos:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (track && window) {
                closeCurrentMenu();
                showTrackMenu(globalPos, track, window);
            }
        }

        /**
         * Handles application shutdown for resource cleanup.
         * Ensures proper disposal of menu resources on application close.
         * 
         * @private
         * @param {Impulse} impulse - APP_CLOSE impulse
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
         * Creates categorized menu items for all registered atom types.
         * 
         * @private
         * @param {Point} globalPosition - Stage coordinates of click for menu positioning
         * @param {Point} localPosition - Content-layer coordinates for atom placement
         * @param {Window} window - Target window for menu display
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
         * Creates closure over atom type and position for menu item execution.
         * 
         * @private
         * @param {String} atomType - Type of atom to create
         * @param {Point} position - Position to place the new atom
         * @return {Function} Callback function that emits ATOM_CONTEXT_MENU_SELECTED impulse
         */
        private function createAtomCallback(atomType:String, position:Point):Function {
            return function(action:String):void {
                _currentMenu.close();
                MultiPulsator.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
                    atomType: atomType,
                    position: position
                }));
            };
        }

        /**
         * Shows atom-specific options menu with operations like delete and properties.
         * Provides context-sensitive operations for individual atoms.
         * 
         * @private
         * @param {Point} globalPosition - Stage coordinates for menu positioning
         * @param {Atom} atom - Target atom for operations
         * @param {Window} window - Parent window for menu display
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
                            MultiPulsator.emit(new Impulse("ATOM_DELETE_REQUEST", { atom: atom }));
                        },
                        category: "Danger"
                    },
                    {
                        label: "Properties", 
                        action: "properties",
                        callback: function(action:String):void {
                            menu.close();
                            MultiPulsator.emit(new Impulse("ATOM_PROPERTIES_REQUEST", { atom: atom }));
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
         * Shows track-specific options menu for connection management.
         * Currently provides track deletion capability.
         * 
         * @private
         * @param {Point} globalPosition - Stage coordinates for menu positioning
         * @param {Track} track - Target track for operations
         * @param {Window} window - Parent window for menu display
         */
        private function showTrackMenu(globalPosition:Point, track:Track, window:Window):void {
            try {
                var menu:ContextMenu;
                var items:Array = [{
                    label: "Delete Track",
                    action: "delete_track",
                    callback: function(action:String):void {
                        menu.close();
                        MultiPulsator.emit(new Impulse("TRACK_DELETE_REQUEST", { track: track }));
                    },
                    category: "Danger"
                }];

                menu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
                
                trace("MenuManager: Track menu displayed successfully");
            } catch (error:Error) {
                trace("MenuManager: ERROR creating track menu: " + error.message);
            }
        }

        // =========================================================================
        // MENU CONTROL AND LIFECYCLE MANAGEMENT
        // =========================================================================

        /**
         * Closes the currently open context menu if one exists.
         * Provides safe cleanup with error handling for menu operations.
         * 
         * @public
         * @param {Impulse} impulse - Optional impulse that triggered the close operation
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
         * Used for input event processing to prevent interference.
         * 
         * @public
         * @return {Boolean} True if a menu is currently open and visible
         */
        public function isMenuOpen():Boolean {
            return _currentMenu != null;
        }

        // =========================================================================
        // RESOURCE CLEANUP AND DISPOSAL
        // =========================================================================

        /**
         * Cleans up all MenuManager resources and unsubscribes from impulses.
         * Performs comprehensive cleanup to prevent memory leaks and ensure proper shutdown.
         * 
         * @public
         */
        public function dispose():void {
            closeCurrentMenu();

            // Unsubscribe from all impulses to prevent memory leaks
            MultiPulsator.removeImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            MultiPulsator.removeImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            MultiPulsator.removeImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);
            MultiPulsator.removeImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            MultiPulsator.removeImpulse("WINDOW_CLICK", closeCurrentMenu);
            MultiPulsator.removeImpulse("KEY_ESC_PRESSED", closeCurrentMenu);
            MultiPulsator.removeImpulse("APP_CLOSE", onAppClose);

            _currentMenu = null;
        }
    }
}
