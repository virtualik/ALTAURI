// Src/Prog/Core/Managers/MenuManager.as
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
     * Uses a single, parameterized ContextMenu class to display:
     * - Atom creation options (from AtomDefinitions)
     * - Atom operations (delete, properties)
     * - Track operations (delete)
     *
     * All menus are rendered in the overlayLayer of the active window.
     * Supports automatic closing on click, ESC, and window events.
     *
     * @class MenuManager
     * @public
     */
    public class MenuManager {
        /** Singleton instance */
        private static var _instance:MenuManager;

        /** Currently open menu reference (always ContextMenu) */
        private var _currentMenu:ContextMenu;

        /**
         * Private constructor for singleton pattern.
         * Sets up all impulse listeners upon instantiation.
         */
        public function MenuManager() {
            setupImpulseListeners();
        }

        /**
         * Get the singleton instance of MenuManager.
         * @return {MenuManager} The singleton instance.
         */
        public static function getInstance():MenuManager {
            if (!_instance) {
                _instance = new MenuManager();
            }
            return _instance;
        }

        /**
         * Initialize the MenuManager system.
         * Ensures the singleton is created and ready.
         */
        public static function initialize():void {
            getInstance();
        }

        /**
         * Set up all impulse listeners for menu control.
         * Subscribes to user and system events that affect menus.
         */
        private function setupImpulseListeners():void {
            // Creation & interaction
            MultiPulsator.subscribeToImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            MultiPulsator.subscribeToImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            MultiPulsator.subscribeToImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);

            // Closing triggers
            MultiPulsator.subscribeToImpulse("WINDOW_LEFT_CLICK", closeCurrentMenu);
            MultiPulsator.subscribeToImpulse("WINDOW_CLICK", closeCurrentMenu);
            MultiPulsator.subscribeToImpulse("KEY_ESC_PRESSED", closeCurrentMenu);

            // Cleanup
            MultiPulsator.subscribeToImpulse("APP_CLOSE", onAppClose);
        }

        // =========================================================================
        // IMPULSE HANDLERS
        // =========================================================================

        /**
         * Handle right-click on canvas background → show atom creation menu.
         * @param {Impulse} impulse - Must contain: globalPosition, localPosition, window.
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
         * Handle right-click on an atom → show atom options menu.
         * @param {Impulse} impulse - Must contain: atom, globalPosition, window.
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
         * Handle right-click on a track → show track options menu.
         * @param {Impulse} impulse - Must contain: track, globalPosition, window.
         */
        private function onTrackRightClick(impulse:Impulse):void {
            trace("--=== MenuManager: Track right click received ===--");
            var track:Track = impulse.data.track;
            trace("--=== MenuManager: track: " + track.connectionId + "    ===--");
            var globalPos:Point = impulse.data.globalPosition;
            trace("--=== MenuManager: Track right click received ===--");
            var window:Window = impulse.data.window;
            trace("--=== MenuManager: window: " + window + "    ===--");

            if (track && window) {
                closeCurrentMenu();
                showTrackMenu(globalPos, track, window);
            }
        }

        /**
         * Handle application shutdown → clean up.
         * @param {Impulse} impulse - APP_CLOSE impulse.
         */
        private function onAppClose(impulse:Impulse):void {
            closeCurrentMenu();
            dispose();
        }

        // =========================================================================
        // MENU CREATION METHODS
        // =========================================================================

        /**
         * Show dynamic atom creation menu built from AtomDefinitions.
         * @param {Point} globalPosition - Stage coordinates of click.
         * @param {Point} localPosition - Content-layer coordinates (for atom placement).
         * @param {Window} window - Target window.
         */
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

                // Sort by category → name
                items.sortOn(["category", "label"]);

                var menu:ContextMenu = new ContextMenu(items, window, globalPosition);
                window.overlayLayer.addChild(menu);
                _currentMenu = menu;
                trace("MenuManager: Creation menu displayed successfully");
            } catch (error:Error) {
                trace("MenuManager: ERROR creating creation menu: " + error.message);
            }
        }

        /**
         * Factory for atom creation callbacks (closes over type and position).
         * @param {String} atomType - Type of atom to create.
         * @param {Point} position - Position to place the atom.
         * @return {Function} Callback that emits ATOM_CONTEXT_MENU_SELECTED.
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
         * Show atom options menu (Delete, Properties).
         * @param {Point} globalPosition - Stage coordinates of click.
         * @param {Atom} atom - Target atom.
         * @param {Window} window - Parent window.
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
         * Show track options menu (Delete).
         * @param {Point} globalPosition - Stage coordinates of click.
         * @param {Track} track - Target track.
         * @param {Window} window - Parent window.
         */
        private function showTrackMenu(globalPosition:Point, track:Track, window:Window):void {
			trace("--=== showTrackMenu ===-- " + track) 
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
        // MENU CONTROL
        // =========================================================================

        /**
         * Close the currently open context menu, if any.
         * Safe to call multiple times.
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
         * Check if a menu is currently open.
         * @return {Boolean} True if a menu is visible.
         */
        public function isMenuOpen():Boolean {
            return _currentMenu != null;
        }

        // =========================================================================
        // CLEANUP
        // =========================================================================

        /**
         * Clean up all resources and unsubscribe from impulses.
         */
        public function dispose():void {
            closeCurrentMenu();

            // Unsubscribe from all impulses
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
