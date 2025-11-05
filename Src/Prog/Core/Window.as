package Src.Prog.Core {
    import flash.display.NativeWindow;
    import flash.display.NativeWindowInitOptions;
    import flash.display.NativeWindowSystemChrome;
    import flash.display.NativeWindowType;
    import flash.display.Sprite;
    import flash.display.StageQuality;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.KeyboardEvent;
    import flash.events.NativeWindowDisplayStateEvent;
    import flash.system.Capabilities;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.ui.Keyboard;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.display.DisplayObject;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Menus.ContextMenu;
    import Src.Prog.Com.Menus.ContextMenuItem;
    import Src.Prog.Core.Managers.MenuManager;
    import Src.Prog.Com.Atoms.Core.TrackManager;

    /**
     * Universal application window with comprehensive mouse event handling system.
     * Serves as the primary gateway for all user input events including LKM and RKM.
     * Implements smooth pan/zoom canvas, context menu coordination, and impulse-based event distribution.
     * 
     * Key Features:
     * - Unified mouse event processing pipeline
     * - Frame-based smooth panning and zooming
     * - Context-aware right-click handling
     * - MultiPulsator integration for system-wide event distribution
     * - Debug overlay with viewport information
     * 
     * @class Window
     * @extends NativeWindow
     * @public
     */
    public class Window extends NativeWindow {
        
        /** Window type identifier ("Editor", "Device", etc.) */
        private var _type:String;
        
        /** Root content container sprite */
        private var _content:Sprite;
        
        /** Main canvas container for all visual layers */
        private var _canvas:Sprite;
        
        /** Background layer for grid and base visuals */
        private var _backgroundLayer:Sprite;
        
        /** Layer for track connections between atoms */
        private var _tracksLayer:Sprite;
        
        /** Primary content layer for atom views */
        private var _contentLayer:Sprite;
        
        /** Overlay layer for context menus and UI elements */
        private var _overlayLayer:Sprite;
        
        /** Current viewport center point in world coordinates */
        private var _viewPoint:Point = new Point(0, 0);
        
        /** Current zoom level (0.09 to 0.25) */
        private var _zoomLevel:Number = 0.1;
        
        /** Panning state flag for middle mouse drag operations */
        private var _isDragging:Boolean = false;
        
        /** Screen coordinates when panning started */
        private var _dragStartScreen:Point;
        
        /** Viewpoint coordinates when panning started */
        private var _dragStartViewPoint:Point;
        
        /** Debug overlay display state */
        private var _debugEnabled:Boolean = false;
		
        /** MOUSE_DOWN Event handler */
		private var transformMouseDown: *; 
		private var transformMouseUp: *; 
		
		/** Zoom configuration constants */
        private static const ZOOM_MIN:Number = 0.09;
        private static const ZOOM_MAX:Number = 0.25;
        private static const ZOOM_STEP:Number = 0.01;
        
        /** Platform detection for desktop vs mobile behavior */
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 || 
                                               Capabilities.os.indexOf("Mac") >= 0 || 
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Creates a new Window instance with specified type and configuration.
         * 
         * @constructor
         * @param {String} type - Window type identifier ("Editor", "Device")
         * @param {Object} config - Configuration object with position, size, and title
         */
        public function Window(type:String, config:Object = null) {
            var options:NativeWindowInitOptions = new NativeWindowInitOptions();
            options.type = NativeWindowType.NORMAL;
            options.systemChrome = NativeWindowSystemChrome.STANDARD;
            options.transparent = false;
            super(options);
            
            _type = type;
            var cfg:Object = config || {};
            this.title = cfg.title || type + " Window";
            this.alwaysInFront = true;
            
            // Set window bounds based on platform
            if (_isDesktop) {
                this.bounds = new Rectangle(cfg.x || 100, cfg.y || 100, cfg.width || 800, cfg.height || 600);
            } else {
                this.bounds = new Rectangle(0, 0, Capabilities.screenResolutionX, Capabilities.screenResolutionY);
            }
            
            setupEventToImpulseTransformers();
            
            if (stage) {
                initializeContent();
            } else {
                addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            }
        }

        /**
         * Handles added to stage event for deferred initialization.
         * 
         * @private
         * @param {Event} event - ADDED_TO_STAGE event
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            this.activate();
            this.stage.focus = this.stage;
            initializeContent();
        }

        /**
         * Sets up all native event to impulse transformers.
         * Establishes Window as the central event processing hub for mouse and keyboard input.
         * 
         * @private
         */
        private function setupEventToImpulseTransformers():void {
            // Window lifecycle events
            addEventListener(Event.ACTIVATE, transformWindowActivate);
            addEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            addEventListener(Event.CLOSING, transformWindowClosing);
            addEventListener(Event.RESIZE, transformWindowResize);
            addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);
            
            /** Mouse input events - primary LKM and RKM handlers */
			stage.addEventListener(MouseEvent.MOUSE_DOWN, 
				function(e:MouseEvent):void {
					transformMouseDown = this;
					// Force cleanup on any mouse down to prevent stuck temporary tracks
					var trackManager:TrackManager = TrackManager.getInstance();
					if (trackManager.getCurrentDragPin()) {
						trace("WARNING: Active drag operation detected on new mouse down. Forcing cleanup.");
						trackManager.forceCleanup();
					}
					var isMenu: Boolean = isMenuElement(e.target as DisplayObject);
						if(!isMenu) {
							MultiPulsator.emit(new Impulse("WINDOW_LEFT_CLICK", {
								windowType: _type,
								window: this,
								stageX: e.stageX,
								stageY: e.stageY
							}));
							closeContextMenus();
						}
						var pin: Pin = getPinFromTarget(e.target as DisplayObject);
						if(pin) {
							MultiPulsator.emit(new Impulse("PIN_MOUSE_DOWN", { // for beginning of the Track 
								pin: pin,
								windowType: _type,
								stageX: e.stageX,
								stageY: e.stageY
							}));
						}
						MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOWN", {
							windowType: _type,
							window: this,
							stageX: e.stageX,
							stageY: e.stageY
						}));}
			);		
            stage.addEventListener(MouseEvent.MOUSE_UP,
				function(e:MouseEvent):void {
					transformMouseUp = this;
					var pin:Pin = getPinFromTarget(e.target as DisplayObject);
					trace("[--TEST MOUSE_UP in Window--]")
					if (pin) {
						MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
							pin: pin,
							windowType: _type
						}));
					}
					
					MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
						windowType: _type,
						window: this,
						stageX: e.stageX,
						stageY: e.stageY
						}));}
			);		
            stage.addEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            stage.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            stage.addEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            stage.addEventListener(MouseEvent.CLICK, transformClick);
						
			addEventListener(Event.DEACTIVATE, onWindowDeactivate);
        }

        /**
         * Initializes window content and visual hierarchy.
         * Creates layer system and sets up platform-specific content.
         * 
         * @private
         */
        private function initializeContent():void {
            try {
                _content = new Sprite();
                _content.name = "Content";
                stage.quality = StageQuality.BEST;
                stage.addChild(_content);
                
                initializeCanvasSystem();
                
                // Platform-specific content setup
                switch (_type) {
                    case "Editor":
                        setupEditorContent();
                        break;
                    case "Device":
                        setupDeviceContent();
                        break;
                    default:
                        setupDefaultContent();
                }
                
                resetViewport();
                
                // Additional input handlers
                stage.addEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
                stage.addEventListener(KeyboardEvent.KEY_UP, transformKeyUp);
                
                trace("Window initialized: " + _type);
            } catch (e:Error) {
                trace("Window init error: " + e.message);
            }
        }

        /**
         * Initializes the canvas system with layered rendering architecture.
         * Creates background, tracks, content, and overlay layers for proper z-ordering.
         * 
         * @private
         */
        private function initializeCanvasSystem():void {
            _canvas = new Sprite();
            _canvas.name = "Canvas";
            _content.addChild(_canvas);
            
            // Background layer for grid and base visuals
            _backgroundLayer = new Sprite();
            _backgroundLayer.name = "BackgroundLayer";
            _backgroundLayer.mouseEnabled = true;
            _backgroundLayer.doubleClickEnabled = true;
            _canvas.addChild(_backgroundLayer);
            
            // Tracks layer for connection lines
            _tracksLayer = new Sprite();
            _tracksLayer.name = "TracksLayer";
            _tracksLayer.mouseEnabled = false;
            _canvas.addChild(_tracksLayer);
            
            // Content layer for atom views
            _contentLayer = new Sprite();
            _contentLayer.name = "ContentLayer";
            _contentLayer.mouseEnabled = true;
            _contentLayer.doubleClickEnabled = true;
            _canvas.addChild(_contentLayer);
            
            // Overlay layer for context menus and UI
            _overlayLayer = new Sprite();
            _overlayLayer.name = "OverlayLayer";
            _overlayLayer.mouseEnabled = false;
            _overlayLayer.mouseChildren = true;
            _canvas.addChild(_overlayLayer);
            
            setupViewportControls();
        }

        /**
         * Sets up viewport control event listeners for pan and zoom operations.
         * 
         * @private
         */
        private function setupViewportControls():void {
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave);
            stage.addEventListener(Event.RESIZE, onStageResize);
        }

		/** 
         * Window deactivation handler 
         */
		private function onWindowDeactivate(event:Event):void {
			trace("Window deactivated: " + _type + ", forcing cleanup of temporary tracks");
			
			// Force cleanup of temporary track state
			var trackManager:TrackManager = TrackManager.getInstance();
			trackManager.forceCleanup();
			
			// Also close any open context menus
			MenuManager.getInstance().closeCurrentMenu();
			
			MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED_CLEANUP", {
				windowType: _type,
				window: this
			}));
		}

        // =========================================================================
        // SMOOTH PAN & ZOOM IMPLEMENTATION
        // =========================================================================

        /**
         * Handles middle mouse button down for panning initiation.
         * Starts frame-based smooth panning operation.
         * 
         * @private
         * @param {MouseEvent} event - MIDDLE_MOUSE_DOWN event
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            _isDragging = true;
            
            // Store screen coordinates and current viewpoint for smooth panning
            _dragStartScreen = new Point(event.stageX, event.stageY);
            _dragStartViewPoint = _viewPoint.clone();
            
            stage.addEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
        }

        /**
         * Frame-based pan update handler for ultra-smooth panning experience.
         * 
         * @private
         * @param {Event} event - ENTER_FRAME event
         */
        private function onPanFrameUpdate(event:Event):void {
            if (!_isDragging || !stage || !_canvas) return;

            // Calculate screen-space mouse movement
            var currentScreen:Point = new Point(stage.mouseX, stage.mouseY);
            var screenDx:Number = currentScreen.x - _dragStartScreen.x;
            var screenDy:Number = currentScreen.y - _dragStartScreen.y;

            // Convert screen movement to world-space viewpoint adjustment
            _viewPoint.x = _dragStartViewPoint.x - screenDx / _zoomLevel;
            _viewPoint.y = _dragStartViewPoint.y - screenDy / _zoomLevel;

            // Apply viewport constraints
            _viewPoint.x = Math.max(-10000, Math.min(10000, _viewPoint.x));
            _viewPoint.y = Math.max(-10000, Math.min(10000, _viewPoint.y));

            updateViewport();

            // Notify system of canvas panning
            MultiPulsator.emit(new Impulse("CANVAS_PANNED", {
                windowType: _type,
                viewPoint: _viewPoint.clone(),
                movement: new Point(-screenDx / _zoomLevel, -screenDy / _zoomLevel)
            }));
        }

        /**
         * Handles middle mouse button up for panning termination.
         * 
         * @private
         * @param {MouseEvent} event - MIDDLE_MOUSE_UP event
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
            _dragStartScreen = null;
            _dragStartViewPoint = null;
        }

        /**
         * Handles mouse leave event to cancel ongoing pan operations.
         * 
         * @private
         * @param {Event} event - MOUSE_LEAVE event
         */
        private function onMouseLeave(event:Event):void {
            _isDragging = false;
            stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
        }

        /**
         * Handles mouse wheel events for smooth zoom operations.
         * Implements cursor-anchored zoom for intuitive user experience.
         * 
         * @private
         * @param {MouseEvent} event - MOUSE_WHEEL event
         */
        private function onMouseWheel(event:MouseEvent):void {
            if (!_canvas || !stage) return;

            // Get current cursor position in screen coordinates
            var screenX:Number = event.stageX;
            var screenY:Number = event.stageY;

            // Calculate world position under cursor before zoom
            var worldBefore:Point = _canvas.globalToLocal(new Point(screenX, screenY));

            // Apply zoom delta with constraints
            _zoomLevel += (event.delta > 0) ? ZOOM_STEP : -ZOOM_STEP;
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, _zoomLevel));

            // Calculate new viewpoint to maintain cursor position
            var newViewX:Number = (stage.stageWidth * 0.5 - screenX) / _zoomLevel + worldBefore.x;
            var newViewY:Number = (stage.stageHeight * 0.5 - screenY) / _zoomLevel + worldBefore.y;

            _viewPoint.x = newViewX;
            _viewPoint.y = newViewY;

            updateViewport();

            // Notify system of zoom change
            MultiPulsator.emit(new Impulse("CANVAS_ZOOM_CHANGED", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

        /**
         * Handles stage resize events and updates viewport accordingly.
         * 
         * @private
         * @param {Event} event - RESIZE event
         */
        private function onStageResize(event:Event):void {
            updateViewport();
            MultiPulsator.emit(new Impulse("CANVAS_RESIZED", {
                windowType: _type,
                stageWidth: stage.stageWidth,
                stageHeight: stage.stageHeight
            }));
        }

        /**
         * Updates the viewport transformation based on current zoom and viewpoint.
         * Applies canvas scaling and positioning for pan/zoom visualization.
         * 
         * @private
         */
        private function updateViewport():void {
            if (!_canvas || !stage) return;
            
            // Validate zoom and viewpoint values
            if (isNaN(_zoomLevel) || _zoomLevel <= 0) _zoomLevel = 0.1;
            if (isNaN(_viewPoint.x) || isNaN(_viewPoint.y)) {
                _viewPoint.setTo(0, 0);
            }
            
            // Apply zoom scaling
            _canvas.scaleX = _canvas.scaleY = _zoomLevel;
            
            // Center canvas based on viewpoint
            _canvas.x = stage.stageWidth * 0.5 - _viewPoint.x * _zoomLevel;
            _canvas.y = stage.stageHeight * 0.5 - _viewPoint.y * _zoomLevel;
            
            // Update debug overlay if enabled
            if (_debugEnabled) drawDebugOverlay();
        }

        // =========================================================================
        // MOUSE EVENT TRANSFORMERS - CORE INPUT PROCESSING
        // =========================================================================


        /**
         * Transforms native mouse up events into application impulses.
         * 
         * @private
         * @param {MouseEvent} e - Native MOUSE_UP event
         */
/*        private function transformMouseUp(e:MouseEvent):void {
            var pin:Pin = getPinFromTarget(e.target as DisplayObject);
            if (pin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
                    pin: pin,
                    windowType: _type
                }));
            }
            
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
                windowType: _type,
                window: this,
                stageX: e.stageX,
                stageY: e.stageY
            }));
        }*/

        /**
         * Transforms native mouse move events into application impulses.
         * 
         * @private
         * @param {MouseEvent} e - Native MOUSE_MOVE event
         */
        private function transformMouseMove(e:MouseEvent):void {
            var pin:Pin = getPinFromTarget(e.target as DisplayObject);
            if (pin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
                    pin: pin,
                    windowType: _type
                }));
            }

			MultiPulsator.emit(new Impulse("WINDOW_MOUSE_MOVE", {
                windowType: _type,
                window: this,
                stageX: e.stageX,
                stageY: e.stageY
            }));
        }

        /**
         * Transforms native mouse wheel events into application impulses.
         * 
         * @private
         * @param {MouseEvent} e - Native MOUSE_WHEEL event
         */
        private function transformMouseWheel(e:MouseEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_WHEEL", {
                windowType: _type,
                window: this,
                delta: e.delta,
                stageX: e.stageX,
                stageY: e.stageY
            }));
        }

        /**
         * Transforms native click events (LKM release) into application impulses.
         * Handles menu closing and provides click confirmation.
         * 
         * @private
         * @param {MouseEvent} e - Native CLICK event
         */
        private function transformClick(e:MouseEvent):void {
            var isMenu:Boolean = isMenuElement(e.target as DisplayObject);
            
            if (!isMenu) {
                MultiPulsator.emit(new Impulse("WINDOW_CLICK", {
                    windowType: _type,
                    window: this,
                    stageX: e.stageX,
                    stageY: e.stageY
                }));
                MenuManager.getInstance().closeCurrentMenu();
            }
        }

        /**
         * Transforms native right mouse down events into context-aware impulses.
         * Implements sophisticated target detection for atoms, tracks, and background.
         * This is the primary entry point for context menu operations.
         * 
         * @private
         * @param {MouseEvent} e - Native RIGHT_MOUSE_DOWN event
         */
        private function transformRightMouseDown(e:MouseEvent):void {
            // Early exit for non-Editor windows or menu elements
            if (_type !== "Editor" || isMenuElement(e.target as DisplayObject)) return;
            
            var target:DisplayObject = e.target as DisplayObject;
            var pos:Point = new Point(e.stageX, e.stageY);
            
            // Target detection hierarchy: Atom → Track → Background
            var atom:Atom = findClickedAtom(target);
            var track:Track = findClickedTrack(target);
            
            if (atom) {
                // Atom-specific context menu impulse
                MultiPulsator.emit(new Impulse("ATOM_RIGHT_CLICK", {
                    atom: atom,
                    globalPosition: pos,
                    window: this,
                    windowType: _type
                }));
                e.stopPropagation();
            } else if (track) {
                // Track-specific context menu impulse
                MultiPulsator.emit(new Impulse("TRACK_RIGHT_CLICK", {
                    track: track,
                    globalPosition: pos,
                    window: this,
                    windowType: _type
                }));
                e.stopPropagation();
            } else {
                // Background context menu for atom creation
                MultiPulsator.emit(new Impulse("WINDOW_RIGHT_CLICK", {
                    globalPosition: pos,
                    window: this,
                    windowType: _type,
                    localPosition: _contentLayer.globalToLocal(pos)
                }));
            }
        }

        /**
         * Transforms native right mouse up events into application impulses.
         * 
         * @private
         * @param {MouseEvent} e - Native RIGHT_MOUSE_UP event
         */
        private function transformRightMouseUp(e:MouseEvent):void {
            // Currently no specific right mouse up handling required
        }

        // =========================================================================
        // WINDOW EVENT TRANSFORMERS
        // =========================================================================

        /**
         * Transforms window activate events into application impulses.
         * 
         * @private
         * @param {Event} e - ACTIVATE event
         */
        private function transformWindowActivate(e:Event):void {
            if (!_content) initializeContent();
            
            MultiPulsator.emit(new Impulse("WINDOW_ACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        /**
         * Transforms window deactivate events into application impulses.
         * 
         * @private
         * @param {Event} e - DEACTIVATE event
         */
        private function transformWindowDeactivate(e:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        /**
         * Transforms window closing events into application impulses.
         * 
         * @private
         * @param {Event} e - CLOSING event
         */
        private function transformWindowClosing(e:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_CLOSING", {
                windowType: _type,
                window: this
            }));
            MultiPulsator.emit(new Impulse("APP_CLOSE"));
        }

        /**
         * Transforms window resize events into application impulses.
         * 
         * @private
         * @param {Event} e - RESIZE event
         */
        private function transformWindowResize(e:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_RESIZED", {
                windowType: _type,
                window: this,
                width: this.width,
                height: this.height
            }));
        }

        /**
         * Transforms window display state change events into application impulses.
         * 
         * @private
         * @param {NativeWindowDisplayStateEvent} e - DISPLAY_STATE_CHANGE event
         */
        private function transformDisplayStateChange(e:NativeWindowDisplayStateEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_DISPLAY_STATE_CHANGED", {
                windowType: _type,
                window: this,
                displayState: this.displayState
            }));
        }

        /**
         * Transforms keyboard key down events into application impulses.
         * Handles debug toggle (Ctrl+D) and escape key for menu closing.
         * 
         * @private
         * @param {KeyboardEvent} e - KEY_DOWN event
         */
        private function transformKeyDown(e:KeyboardEvent):void {
            // Escape key handling for menu dismissal
            if (e.keyCode == Keyboard.ESCAPE) {
                MultiPulsator.emit(new Impulse("KEY_ESC_PRESSED", {
                    window: this,
                    windowType: _type
                }));
                e.stopPropagation();
            }
            
            // Debug overlay toggle with Ctrl+D
            if (e.keyCode == Keyboard.D && e.ctrlKey) {
                _debugEnabled = !_debugEnabled;
                trace("Debug overlay: " + (_debugEnabled ? "ON" : "OFF"));
                if (!_debugEnabled) {
                    var overlay:Sprite = _content.getChildByName("debugOverlay") as Sprite;
                    if (overlay) _content.removeChild(overlay);
                }
            }
            
            MultiPulsator.emit(new Impulse("WINDOW_KEY_DOWN", {
                windowType: _type,
                window: this,
                keyCode: e.keyCode,
                charCode: e.charCode,
                ctrlKey: e.ctrlKey,
                altKey: e.altKey,
                shiftKey: e.shiftKey
            }));
        }

        /**
         * Transforms keyboard key up events into application impulses.
         * 
         * @private
         * @param {KeyboardEvent} e - KEY_UP event
         */
        private function transformKeyUp(e:KeyboardEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_KEY_UP", {
                windowType: _type,
                window: this,
                keyCode: e.keyCode,
                charCode: e.charCode
            }));
        }

        // =========================================================================
        // UTILITY METHODS
        // =========================================================================

        /**
         * Checks if a display object is part of any context menu hierarchy.
         * Prevents event propagation issues with context menus.
         * 
         * @private
         * @param {DisplayObject} obj - Target display object to check
         * @return {Boolean} True if object belongs to context menu hierarchy
         */
        private function isMenuElement(obj:DisplayObject):Boolean {
            var current:DisplayObject = obj;
            while (current && current != stage) {
                if (current is ContextMenuItem || current is ContextMenu) {
                    return true;
                }
                current = current.parent;
            }
            return false;
        }

        /**
         * Finds the atom associated with a clicked display object.
         * Traverses display hierarchy to locate parent AtomView.
         * 
         * @private
         * @param {DisplayObject} target - Clicked display object
         * @return {Atom} Associated atom or null if not found
         */
        private function findClickedAtom(target:DisplayObject):Atom {
            var cur:DisplayObject = target;
            while (cur && cur != stage) {
                if (cur is AtomView) return (cur as AtomView).atom;
                if (cur is Pin) {
                    var p:DisplayObject = cur.parent;
                    while (p && p != stage) {
                        if (p is AtomView) return (p as AtomView).atom;
                        p = p.parent;
                    }
                }
                cur = cur.parent;
            }
            return null;
        }

        /**
         * Finds the track associated with a clicked display object.
         * Traverses display hierarchy to locate parent Track.
         * 
         * @private
         * @param {DisplayObject} target - Clicked display object
         * @return {Track} Associated track or null if not found
         */
        private function findClickedTrack(target:DisplayObject):Track {
            var cur:DisplayObject = target;
            while (cur && cur != stage) {
                if (cur is Track) return cur as Track;
                cur = cur.parent;
            }
            return null;
        }

        /**
         * Extracts Pin instance from clicked display object hierarchy.
         * 
         * @private
         * @param {DisplayObject} target - Clicked display object
         * @return {Pin} Associated pin or null if not found
         */
        private function getPinFromTarget(target:DisplayObject):Pin {
            var cur:DisplayObject = target;
            while (cur && !(cur is Pin) && cur.parent) {
                cur = cur.parent;
            }
            return cur as Pin;
        }

        /**
         * Closes all open context menus via MenuManager.
         * 
         * @public
         */
        public function closeContextMenus():void {
            MenuManager.getInstance().closeCurrentMenu();
        }

        // =========================================================================
        // CONTENT SETUP METHODS
        // =========================================================================

        /**
         * Sets up Editor-specific window content with grid background.
         * 
         * @private
         */
        private function setupEditorContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x1a1a2e);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();
            drawGrid();
            _contentLayer.addChild(createLabel("Editor | R-Click: Menu | Wheel: Zoom | MMB: Pan | Ctrl+D: Debug", -380, -280));
        }

        /**
         * Draws grid pattern on background layer for visual reference.
         * 
         * @private
         */
        private function drawGrid():void {
            var s:int = 10;
            var c:uint = 0x2d2d4d;
            _backgroundLayer.graphics.lineStyle(1, c, 0.77);
            
            // Vertical grid lines
            for (var x:int = -400; x <= 400; x += s) {
                _backgroundLayer.graphics.moveTo(x, -300);
                _backgroundLayer.graphics.lineTo(x, 300);
            }
            
            // Horizontal grid lines
            for (var y:int = -300; y <= 300; y += s) {
                _backgroundLayer.graphics.moveTo(-400, y);
                _backgroundLayer.graphics.lineTo(400, y);
            }
        }

        /**
         * Sets up Device-specific window content.
         * 
         * @private
         */
        private function setupDeviceContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x077770);
            _backgroundLayer.graphics.drawRect(-320, -240, 640, 480);
            _backgroundLayer.graphics.endFill();
            _contentLayer.addChild(createLabel("Device Window", 10, 10));
            
            if (!_isDesktop) this.alwaysInFront = false;
        }

        /**
         * Sets up default window content for unknown window types.
         * 
         * @private
         */
        private function setupDefaultContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x333333);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();
            _contentLayer.addChild(createLabel(_type + " Window", 10, 10));
        }

        /**
         * Creates a text label with specified content and position.
         * 
         * @private
         * @param {String} text - Label text content
         * @param {Number} x - X position
         * @param {Number} y - Y position
         * @return {TextField} Configured text field
         */
        private function createLabel(text:String, x:Number, y:Number):TextField {
            var tf:TextField = new TextField();
            tf.width = 500;
            tf.height = 60;
            tf.x = x;
            tf.y = y;
            tf.textColor = 0xFFFFFF;
            tf.selectable = false;
            tf.multiline = true;
            tf.wordWrap = true;
            
            var fmt:TextFormat = new TextFormat("Verdana", 12, 0xFFFFFF);
            tf.defaultTextFormat = fmt;
            tf.text = text;
            
            return tf;
        }

        // =========================================================================
        // DEBUG OVERLAY SYSTEM
        // =========================================================================

        /**
         * Draws debug overlay with viewport information when debug mode is enabled.
         * 
         * @private
         */
        private function drawDebugOverlay():void {
            var overlay:Sprite = _content.getChildByName("debugOverlay") as Sprite;
            if (!overlay) {
                overlay = new Sprite();
                overlay.name = "debugOverlay";
                overlay.mouseEnabled = false;
                _content.addChild(overlay);
            }
            
            // Draw canvas boundary
            overlay.graphics.clear();
            overlay.graphics.lineStyle(3, 0xFF0000, 0.8);
            overlay.graphics.drawRect(_canvas.x, _canvas.y, stage.stageWidth, stage.stageHeight);
            
            // Update debug text
            var tf:TextField = overlay.getChildByName("dbg") as TextField;
            if (!tf) {
                tf = new TextField();
                tf.name = "dbg";
                tf.width = 420;
                tf.height = 140;
                tf.background = true;
                tf.backgroundColor = 0x000000;
                tf.textColor = 0x00FF00;
                tf.x = 10;
                tf.y = 10;
                overlay.addChild(tf);
            }
            
            tf.text = "VIEWPOINT: " + _viewPoint.x.toFixed(1) + ", " + _viewPoint.y.toFixed(1) +
                     "\nZOOM: " + _zoomLevel.toFixed(3) +
                     "\nCANVAS: " + _canvas.x.toFixed(1) + ", " + _canvas.y.toFixed(1) +
                     "\nMOUSE: " + stage.mouseX.toFixed(1) + ", " + stage.mouseY.toFixed(1) +
                     "\nDRAG: " + (_isDragging ? "YES" : "NO");
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Resets viewport to default position and zoom level.
         * 
         * @public
         */
        public function resetViewport():void {
            _viewPoint.setTo(0, 0);
            _zoomLevel = 0.1;
            updateViewport();
            
            MultiPulsator.emit(new Impulse("CANVAS_RESET", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

        /**
         * Gets the main canvas sprite.
         * 
         * @public
         * @return {Sprite} Main canvas container
         */
        public function get canvas():Sprite {
            return _canvas;
        }

        /**
         * Gets the background layer sprite.
         * 
         * @public
         * @return {Sprite} Background layer
         */
        public function get backgroundLayer():Sprite {
            return _backgroundLayer;
        }

        /**
         * Gets the content layer sprite for atom views.
         * 
         * @public
         * @return {Sprite} Content layer
         */
        public function get contentLayer():Sprite {
            return _contentLayer;
        }

        /**
         * Gets the overlay layer sprite for UI elements.
         * 
         * @public
         * @return {Sprite} Overlay layer
         */
        public function get overlayLayer():Sprite {
            return _overlayLayer;
        }

        /**
         * Gets the tracks layer sprite for connections.
         * 
         * @public
         * @return {Sprite} Tracks layer
         */
        public function get tracksLayer():Sprite {
            return _tracksLayer;
        }

        /**
         * Gets the current zoom level.
         * 
         * @public
         * @return {Number} Current zoom level (0.09 to 0.25)
         */
        public function get zoomLevel():Number {
            return _zoomLevel;
        }

        /**
         * Sets the zoom level with constraints.
         * 
         * @public
         * @param {Number} value - New zoom level
         */
        public function set zoomLevel(value:Number):void {
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, value));
            updateViewport();
        }

        /**
         * Gets the current viewpoint in world coordinates.
         * 
         * @public
         * @return {Point} Current viewpoint coordinates
         */
        public function get viewPoint():Point {
            return _viewPoint.clone();
        }

        /**
         * Sets the viewpoint to specified coordinates.
         * 
         * @public
         * @param {Point} point - New viewpoint coordinates
         */
        public function set viewPoint(point:Point):void {
            _viewPoint = point.clone();
            updateViewport();
        }

        /**
         * Gets the window type identifier.
         * 
         * @public
         * @return {String} Window type ("Editor", "Device")
         */
        public function get windowType():String {
            return _type;
        }

        // =========================================================================
        // CLEANUP AND DISPOSAL
        // =========================================================================

        /**
         * Cleans up all resources and event listeners.
         * Performs comprehensive cleanup to prevent memory leaks.
         * 
         * @public
         */
        public function dispose():void {
            trace("Disposing window: " + _type);
            
            // Remove event listeners
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            
            if (stage) {
                stage.removeEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
                stage.removeEventListener(KeyboardEvent.KEY_UP, transformKeyUp);
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                stage.removeEventListener(Event.MOUSE_LEAVE, onMouseLeave);
                stage.removeEventListener(Event.RESIZE, onStageResize);
                stage.removeEventListener(Event.ENTER_FRAME, onPanFrameUpdate);
            }
            
            removeEventListener(Event.ACTIVATE, transformWindowActivate);
            removeEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            removeEventListener(Event.CLOSING, transformWindowClosing);
            removeEventListener(Event.RESIZE, transformWindowResize);
            removeEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);
            
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            stage.removeEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            stage.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            stage.removeEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            stage.removeEventListener(MouseEvent.CLICK, transformClick);
            
            // Remove content from stage
            if (_content && stage && stage.contains(_content)) {
                stage.removeChild(_content);
            }
            
            _content = _canvas = null;
        }
    }
}