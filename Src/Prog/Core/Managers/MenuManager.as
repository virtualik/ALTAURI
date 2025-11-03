package Src.Prog.Core.Managers {
    import flash.geom.Point;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Core.Window;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Com.Menus.AtomCreationContextMenu;
    import Src.Prog.Com.Menus.AtomOptionsContextMenu;
    import Src.Prog.Com.Menus.TrackContextMenu;
    import Src.Prog.Core.Managers.WindowsManager;

    /**
     * MenuManager - Centralized manager for handling context menus throughout the application.
     * Enhanced with menu closing functionality on left click and ESC key press.
     *
     * @class MenuManager
     * @public
     */
    public class MenuManager {
        /** Singleton instance */
        private static var _instance:MenuManager;

        /** Current active window context */
        private var _currentWindow:Window;

        /** Currently open menu reference */
        private var _currentMenu:Object;

        /**
         * Private constructor for singleton pattern
         */
        public function MenuManager() {
            setupImpulseListeners();
        }

        /**
         * Get singleton instance
         * @return {MenuManager} MenuManager singleton instance
         */
        public static function getInstance():MenuManager {
            if (!_instance) {
                _instance = new MenuManager();
            }
            return _instance;
        }

        /**
         * Initialize menu manager system
         */
        public static function initialize():void {
            getInstance(); // Ensures instance creation and setup
        }

        /**
         * Setup all impulse listeners for menu management
         * Enhanced with menu closing impulses
         */
        private function setupImpulseListeners():void {
            // Atom-related impulses
            MultiPulsator.subscribeToImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            MultiPulsator.subscribeToImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            
            // Track-related impulses
            MultiPulsator.subscribeToImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);
            
            // Window/canvas impulses
            MultiPulsator.subscribeToImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            
            // Menu closing impulses
            MultiPulsator.subscribeToImpulse("WINDOW_LEFT_CLICK", onWindowLeftClick);
            MultiPulsator.subscribeToImpulse("WINDOW_CLICK", onWindowClick);
            MultiPulsator.subscribeToImpulse("KEY_ESC_PRESSED", onKeyEscPressed);
            
            // System impulses for cleanup
            MultiPulsator.subscribeToImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.subscribeToImpulse("APP_CLOSE", onAppClose);
        }

        // =========================================================================
        // IMPULSE HANDLERS
        // =========================================================================

        /**
         * Handle atom right-click impulse - show atom options menu
         * @param {Impulse} impulse - ATOM_RIGHT_CLICK impulse
         */
        private function onAtomRightClick(impulse:Impulse):void {
            trace("MenuManager: Atom right click received");
            
            var atom:Atom = impulse.data.atom;
            var globalPosition:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (atom && window) {
                closeCurrentMenu();
                showAtomOptionsMenu(globalPosition, atom, window);
            }
        }

        /**
         * Handle track right-click impulse - show track options menu
         * @param {Impulse} impulse - TRACK_RIGHT_CLICK impulse
         */
        private function onTrackRightClick(impulse:Impulse):void {
            trace("MenuManager: Track right click received");
            
            var track:Track = impulse.data.track;
            var globalPosition:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;

            if (track && window) {
                closeCurrentMenu();
                showTrackMenu(globalPosition, track, window);
            }
        }

        /**
         * Handle window right-click impulse - show atom creation menu
         * @param {Impulse} impulse - WINDOW_RIGHT_CLICK impulse
         */
        private function onWindowRightClick(impulse:Impulse):void {
            trace("MenuManager: Window right click received");
            
            var globalPosition:Point = impulse.data.globalPosition;
            var window:Window = impulse.data.window;
            var localPosition:Point = impulse.data.localPosition;

            if (window) {
                closeCurrentMenu();
                showCreationMenu(globalPosition, localPosition, window);
            }
        }

		/**
		 * Handle window left-click impulse - close current menu
		 * @param {Impulse} impulse - WINDOW_LEFT_CLICK impulse
		 */
		private function onWindowLeftClick(impulse:Impulse):void {
			trace("MenuManager: WINDOW_LEFT_CLICK received - closing menu");
			trace("Impulse data: " + (impulse.data));
			closeCurrentMenu();
		}

		/**
		 * Handle window click impulse - close current menu
		 * @param {Impulse} impulse - WINDOW_CLICK impulse
		 */

		private function onWindowClick(impulse:Impulse):void {
			trace("MenuManager: WINDOW_CLICK received - closing menu");
			trace("Impulse data: " + (impulse.data));
			closeCurrentMenu();
		}

        /**
         * Handle ESC key press impulse - close current menu
         * @param {Impulse} impulse - KEY_ESC_PRESSED impulse
         */
        private function onKeyEscPressed(impulse:Impulse):void {
            trace("MenuManager: ESC key pressed - closing menu");
            closeCurrentMenu();
        }

        /**
         * Handle atom creation from context menu
         * @param {Impulse} impulse - ATOM_CONTEXT_MENU_SELECTED impulse
         */
        private function onAtomContextMenuSelected(impulse:Impulse):void {
            // This is handled by AtomManager, but we close the menu here
            closeCurrentMenu();
        }

        /**
         * Handle window activation to update context
         * @param {Impulse} impulse - WINDOW_ACTIVATED impulse
         */
        private function onWindowActivated(impulse:Impulse):void {
            _currentWindow = impulse.data.window;
        }

        /**
         * Handle app close for cleanup
         * @param {Impulse} impulse - APP_CLOSE impulse
         */
        private function onAppClose(impulse:Impulse):void {
            closeCurrentMenu();
            dispose();
        }

        // =========================================================================
        // MENU DISPLAY METHODS (без изменений)
        // =========================================================================

        /**
         * Show atom options context menu
         * @param {Point} globalPosition - Global stage coordinates
         * @param {Atom} atom - Target atom
         * @param {Window} window - Parent window
         */
        private function showAtomOptionsMenu(globalPosition:Point, atom:Atom, window:Window):void {
            try {
                // Convert global coordinates to overlay layer coordinates
                var overlayPos:Point = window.overlayLayer.globalToLocal(globalPosition);

                trace("MenuManager: Showing atom options menu for: " + atom.name + " at overlay pos: " + overlayPos);

                // Create atom options menu
                var atomMenu:AtomOptionsContextMenu = new AtomOptionsContextMenu(overlayPos, atom);
                window.overlayLayer.addChild(atomMenu);
                _currentMenu = atomMenu;

                trace("MenuManager: Atom options menu displayed successfully");

            } catch (error:Error) {
                trace("MenuManager: ERROR creating atom options menu: " + error.message);
            }
        }

        /**
         * Show track context menu
         * @param {Point} globalPosition - Global stage coordinates
         * @param {Track} track - Target track
         * @param {Window} window - Parent window
         */
        private function showTrackMenu(globalPosition:Point, track:Track, window:Window):void {
            try {
                // Convert global coordinates to overlay layer coordinates
                var overlayPos:Point = window.overlayLayer.globalToLocal(globalPosition);

                trace("MenuManager: Showing track menu for: " + track.connectionId + " at overlay pos: " + overlayPos);

                // Create track menu
                var trackMenu:TrackContextMenu = new TrackContextMenu(overlayPos, track);
                window.overlayLayer.addChild(trackMenu);
                _currentMenu = trackMenu;

                trace("MenuManager: Track menu displayed successfully");

            } catch (error:Error) {
                trace("MenuManager: ERROR creating track menu: " + error.message);
            }
        }

        /**
         * Show atom creation context menu
         * @param {Point} globalPosition - Global stage coordinates
         * @param {Point} localPosition - Local content layer coordinates
         * @param {Window} window - Parent window
         */
        private function showCreationMenu(globalPosition:Point, localPosition:Point, window:Window):void {
            try {
                // Convert global coordinates to overlay layer coordinates
                var overlayPos:Point = window.overlayLayer.globalToLocal(globalPosition);

                trace("MenuManager: Showing creation menu at overlay pos: " + overlayPos + ", content pos: " + localPosition);

                // Create context menu
                var contextMenu:AtomCreationContextMenu = new AtomCreationContextMenu(overlayPos, localPosition);
                window.overlayLayer.addChild(contextMenu);
                _currentMenu = contextMenu;

                trace("MenuManager: Creation menu displayed successfully");

            } catch (error:Error) {
                trace("MenuManager: ERROR creating context menu: " + error.message);
            }
        }

        // =========================================================================
        // MENU MANAGEMENT METHODS
        // =========================================================================

		/**
		 * Close currently open menu
		 */
		public function closeCurrentMenu():void {
			trace("MenuManager.closeCurrentMenu() called");
			trace("Current menu: " + _currentMenu);
			
			if (_currentMenu) {
				try {
					trace("Attempting to close menu: " + _currentMenu);
					
					if (_currentMenu is AtomOptionsContextMenu) {
						trace("Closing AtomOptionsContextMenu");
						(_currentMenu as AtomOptionsContextMenu).close();
					} else if (_currentMenu is TrackContextMenu) {
						trace("Closing TrackContextMenu");
						(_currentMenu as TrackContextMenu).close();
					} else if (_currentMenu is AtomCreationContextMenu) {
						trace("Closing AtomCreationContextMenu");
						(_currentMenu as AtomCreationContextMenu).close();
					}
					_currentMenu = null;
					trace("MenuManager: Current menu closed successfully");
				} catch (error:Error) {
					trace("MenuManager: ERROR closing menu: " + error.message);
				}
			} else {
				trace("MenuManager: No current menu to close");
			}
		}

        /**
         * Check if any menu is currently open
         * @return {Boolean} True if a menu is open
         */
        public function isMenuOpen():Boolean {
            return _currentMenu != null;
        }

        /**
         * Get currently open menu
         * @return {Object} Current menu or null
         */
        public function getCurrentMenu():Object {
            return _currentMenu;
        }

        // =========================================================================
        // CLEANUP METHODS
        // =========================================================================

        /**
         * Cleanup all resources
         */
        public function dispose():void {
            closeCurrentMenu();

            // Remove all impulse listeners
            MultiPulsator.removeImpulse("ATOM_RIGHT_CLICK", onAtomRightClick);
            MultiPulsator.removeImpulse("ATOM_CONTEXT_MENU_SELECTED", onAtomContextMenuSelected);
            MultiPulsator.removeImpulse("TRACK_RIGHT_CLICK", onTrackRightClick);
            MultiPulsator.removeImpulse("WINDOW_RIGHT_CLICK", onWindowRightClick);
            MultiPulsator.removeImpulse("WINDOW_LEFT_CLICK", onWindowLeftClick);
            MultiPulsator.removeImpulse("WINDOW_CLICK", onWindowClick);
            MultiPulsator.removeImpulse("KEY_ESC_PRESSED", onKeyEscPressed);
            MultiPulsator.removeImpulse("WINDOW_ACTIVATED", onWindowActivated);
            MultiPulsator.removeImpulse("APP_CLOSE", onAppClose);

            _currentWindow = null;
            _currentMenu = null;
        }
    }
}