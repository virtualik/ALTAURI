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
    import flash.events.FocusEvent;
    import flash.events.NativeWindowDisplayStateEvent;
    import flash.system.Capabilities;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.ui.Keyboard;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.display.DisplayObject;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Com.Menus.AtomCreationContextMenu;
    import Src.Prog.Com.Menus.AtomContextMenuItem;

    /**
     * Universal Window with integrated canvas, pan/zoom, and detailed impulse system.
     * Provides layered content system and transforms native events into precise impulses.
     */
    public class Window extends NativeWindow {
        /** Window type identifier */
        private var _type:String;

        /** Main content container */
        private var _content:Sprite;

        // =========================================================================
        // CANVAS SYSTEM - Integrated pan/zoom functionality
        // =========================================================================

        /** Main canvas for pan/zoom operations */
        private var _canvas:Sprite;

        /** Background layer - static background elements */
        private var _backgroundLayer:Sprite;

        /** Content layer - dynamic elements that move with canvas (atoms, tracks) */
        private var _contentLayer:Sprite;

        /** Overlay layer - temporary elements (drag previews, UI) */
        private var _overlayLayer:Sprite;

        /** Current viewport position for panning */
        private var _viewPoint:Point = new Point(0, 0);

        /** Current zoom level */
        private var _zoomLevel:Number = 1.0;

        /** Dragging state for panning */
        private var _isDragging:Boolean = false;

        /** Last mouse position for movement calculations */
        private var _lastMousePos:Point = new Point();

        /** Zoom constraints */
        private static const ZOOM_MIN:Number = 0.1;
        private static const ZOOM_MAX:Number = 3.0;
        private static const ZOOM_STEP:Number = 0.1;

        /** Platform detection */
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Universal Window constructor
         * @param type Window type identifier ("Editor", "Device", etc.)
         * @param config Configuration object for window properties (optional)
         */
        public function Window(type:String, config:Object = null) {
            var options:NativeWindowInitOptions = new NativeWindowInitOptions();
            options.type = NativeWindowType.NORMAL;
            options.systemChrome = NativeWindowSystemChrome.STANDARD;
            options.transparent = false;

            super(options);

            _type = type;
            var actualConfig:Object = config || {};

            // Configure window properties
            this.title = actualConfig.title || type + " Window";
            this.alwaysInFront = true;

            // Platform-specific sizing and positioning
            if (_isDesktop) {
                this.bounds = new Rectangle(
                    actualConfig.x || 100,
                    actualConfig.y || 100,
                    actualConfig.width || 800,
                    actualConfig.height || 600
                );
            } else {
                // Mobile - full screen
                this.bounds = new Rectangle(0, 0,
                    Capabilities.screenResolutionX,
                    Capabilities.screenResolutionY);
            }

            // Setup event to impulse transformers
            setupEventToImpulseTransformers();

            // Initialize content when stage is available
            if (stage) {
                initializeContent();
            } else {
                addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            }
        }

        /**
         * Handler when window is added to stage
         * @param event ADDED_TO_STAGE event
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            initializeContent();
        }

        /**
         * Setup all event listeners that transform native events into impulses
         */
        private function setupEventToImpulseTransformers():void {
            // Window lifecycle events
            addEventListener(Event.ACTIVATE, transformWindowActivate);
            addEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            addEventListener(Event.CLOSING, transformWindowClosing);
            addEventListener(Event.RESIZE, transformWindowResize);
            addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Mouse events with pin detection
            addEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            addEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            addEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            addEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            addEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            addEventListener(MouseEvent.CLICK, transformClick);
        }

        /**
         * Initialize window content based on window type
         */
        private function initializeContent():void {
            try {
                _content = new Sprite();
                _content.name = "Content";
                stage.quality = StageQuality.BEST;
                stage.addChild(_content);

                // Initialize canvas system
                initializeCanvasSystem();

                // Type-specific content
                switch(_type) {
                    case "Editor":
                        setupEditorContent();
                        break;
                    case "Device":
                        setupDeviceContent();
                        break;
                    default:
                        setupDefaultContent();
                }

                // Center canvas initially
                centerCanvas();

            } catch (error:Error) {
                trace("Window content initialization error: " + error.message);
            }
        }

        /**
         * Initialize canvas system with pan/zoom functionality
         */
        private function initializeCanvasSystem():void {
            // Create main canvas container
            _canvas = new Sprite();
            _canvas.name = "Canvas";
            _content.addChild(_canvas);

            // Create background layer for static elements
            _backgroundLayer = new Sprite();
            _backgroundLayer.name = "BackgroundLayer";
            _backgroundLayer.mouseEnabled = true;
            _backgroundLayer.doubleClickEnabled = true;
            _backgroundLayer.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
            _canvas.addChild(_backgroundLayer);

            // Create content layer for dynamic elements (atoms, tracks)
            _contentLayer = new Sprite();
            _contentLayer.name = "ContentLayer";
            _contentLayer.mouseEnabled = true;
            _contentLayer.doubleClickEnabled = true;
            _canvas.addChild(_contentLayer);

            // Create overlay layer for temporary elements
            _overlayLayer = new Sprite();
            _overlayLayer.name = "OverlayLayer";
            _overlayLayer.mouseEnabled = false; // Disable for menus so clicks pass through
            _overlayLayer.mouseChildren = true; // But allow children to be interactive
            _canvas.addChild(_overlayLayer);

            // Setup viewport controls
            setupViewportControls();
        }

        /**
         * Background right click handler
         */
        private function onBackgroundRightClick(event:MouseEvent):void {
            if (_type == "Editor") {
                showContextMenu(new Point(event.stageX, event.stageY));
                event.stopPropagation();
            }
        }

        /**
         * Setup viewport controls for pan/zoom operations
         */
        private function setupViewportControls():void {
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave);
            stage.addEventListener(Event.RESIZE, onStageResize);
        }

        /**
         * Center canvas on stage and reset viewport - FROM WORKING VERSION
         */
        private function centerCanvas():void {
            _canvas.x = stage.stageWidth / 2;
            _canvas.y = stage.stageHeight / 2;
            _viewPoint.setTo(0, 0);
            _zoomLevel = 1.0;
            updateViewport();
        }

        /**
         * Mouse wheel handler for zoom operations - FROM WORKING VERSION
         * @param event Mouse wheel event
         */
        private function onMouseWheel(event:MouseEvent):void {
            var mouseStageX:Number = stage.mouseX;
            var mouseStageY:Number = stage.mouseY;
            var mouseLocalBefore:Point = _canvas.globalToLocal(new Point(mouseStageX, mouseStageY));

            var oldZoom:Number = _zoomLevel;
            _zoomLevel += (event.delta > 0) ? ZOOM_STEP : -ZOOM_STEP;
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, _zoomLevel));

            updateViewport();

            var mouseLocalAfter:Point = _canvas.globalToLocal(new Point(mouseStageX, mouseStageY));
            var scaleRatio:Number = _zoomLevel / oldZoom;
            _viewPoint.x += (mouseLocalAfter.x - mouseLocalBefore.x) * scaleRatio;
            _viewPoint.y += (mouseLocalAfter.y - mouseLocalBefore.y) * scaleRatio;

            updateViewport();

            MultiPulsator.emit(new Impulse("CANVAS_ZOOM_CHANGED", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

        /**
         * Middle mouse down handler - start panning - FROM WORKING VERSION
         * @param event Middle mouse button down event
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _lastMousePos.setTo(stage.mouseX, stage.mouseY);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse drag handler - update panning position - FROM WORKING VERSION
         * @param event Mouse move event during drag
         */
        private function onMouseDrag(event:MouseEvent):void {
            if (_isDragging) {
                var currentMousePos:Point = new Point(stage.mouseX, stage.mouseY);
                var dx:Number = currentMousePos.x - _lastMousePos.x;
                var dy:Number = currentMousePos.y - _lastMousePos.y;

                _viewPoint.x += dx / _zoomLevel;
                _viewPoint.y += dy / _zoomLevel;

                updateViewport();
                _lastMousePos = currentMousePos;

                MultiPulsator.emit(new Impulse("CANVAS_PANNED", {
                    windowType: _type,
                    viewPoint: _viewPoint.clone(),
                    movement: new Point(dx, dy)
                }));
            }
        }

        /**
         * Middle mouse up handler - end panning - FROM WORKING VERSION
         * @param event Middle mouse button up event
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse leave handler - cancel ongoing operations - FROM WORKING VERSION
         * @param event Mouse leave event
         */
        private function onMouseLeave(event:Event):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Stage resize handler
         * @param event Stage resize event
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
         * Update viewport transformation based on current zoom and position - FROM WORKING VERSION
         */
        private function updateViewport():void {
            _canvas.scaleX = _canvas.scaleY = _zoomLevel;
            _canvas.x = stage.stageWidth / 2 + _viewPoint.x * _zoomLevel;
            _canvas.y = stage.stageHeight / 2 + _viewPoint.y * _zoomLevel;
        }

        // =========================================================================
        // CONTEXT MENU HANDLING - FROM NEW VERSION
        // =========================================================================

        /**
         * Transform right mouse down event to show context menu
         * @param event Native right mouse down event
         */
        private function transformRightMouseDown(event:MouseEvent):void {
            // Only show context menu in Editor window
            if (_type != "Editor") {
                return;
            }

            // Check if click was on background or content (not on pins or existing menus)
            var target:DisplayObject = event.target as DisplayObject;
            while (target && target != stage) {
                if (target is Pin || target is AtomContextMenuItem) {
                    return;
                }
                target = target.parent;
            }

            showContextMenu(new Point(event.stageX, event.stageY));
            
            // Prevent default context menu
            event.stopPropagation();
        }

        /**
         * Transform right mouse up event
         * @param event Native right mouse up event
         */
        private function transformRightMouseUp(event:MouseEvent):void {
            // Don't prevent propagation here to allow menu items to work
        }

        /**
         * Transform click event
         * @param event Native click event
         */
        private function transformClick(event:MouseEvent):void {
            // Close context menus on any click (except right click)
            if (event.target != _overlayLayer && !(event.target is AtomContextMenuItem)) {
                closeContextMenus();
            }
        }

        /**
         * Show context menu at specified stage coordinates
         * @param stagePos Stage coordinates where menu should appear
         */
        private function showContextMenu(stagePos:Point):void {
            // Close any existing menus
            closeContextMenus();

            try {
                // Convert stage coordinates to overlay layer coordinates
                var overlayPos:Point = _overlayLayer.globalToLocal(stagePos);
                var contentPos:Point = _contentLayer.globalToLocal(stagePos);
                
                // Create context menu
                var contextMenu:AtomCreationContextMenu = new AtomCreationContextMenu(overlayPos, contentPos);
                _overlayLayer.addChild(contextMenu);
				
				// Debug: add marker at click position
				addDebugMarker(contentPos);

                MultiPulsator.emit(new Impulse("WINDOW_RIGHT_CLICK", {
                    windowType: _type,
                    window: this,
                    globalPosition: stagePos,
                    localPosition: contentPos
                }));

            } catch (error:Error) {
                trace("ERROR creating context menu: " + error.message);
            }
        }

        /**
         * Close any open context menus
         */
        public function closeContextMenus():void {
            for (var i:int = _overlayLayer.numChildren - 1; i >= 0; i--) {
                var child:DisplayObject = _overlayLayer.getChildAt(i);
                if (child is AtomCreationContextMenu) {
                    _overlayLayer.removeChildAt(i);
                }
            }
        }

        // =========================================================================
        // CONTENT SETUP METHODS - FROM NEW VERSION WITH IMPROVEMENTS
        // =========================================================================

        /**
         * Set up editor-specific content
         */
        private function setupEditorContent():void {
            // Clear any existing graphics
            _backgroundLayer.graphics.clear();
            
            // Draw background with reasonable size
            _backgroundLayer.graphics.beginFill(0x1a1a2e, 1.0);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();

            // Add subtle grid
            drawGrid();

            // Add informative text
            var info:TextField = createLabel("Editor - Right click to add atoms\nMouse wheel: Zoom\nMiddle mouse: Pan", -380, -280);
            _contentLayer.addChild(info);
        }

        /**
         * Draw grid on background for better orientation
         */
        private function drawGrid():void {
            var gridSize:int = 50;
            var gridColor:uint = 0x2d2d4d;
            var gridAlpha:Number = 0.5;

            _backgroundLayer.graphics.lineStyle(1, gridColor, gridAlpha);

            // Vertical lines
            for (var x:int = -400; x <= 400; x += gridSize) {
                _backgroundLayer.graphics.moveTo(x, -300);
                _backgroundLayer.graphics.lineTo(x, 300);
            }

            // Horizontal lines
            for (var y:int = -300; y <= 300; y += gridSize) {
                _backgroundLayer.graphics.moveTo(-400, y);
                _backgroundLayer.graphics.lineTo(400, y);
            }
        }

        /**
         * Set up device-specific content
         */
        private function setupDeviceContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x077770, 1.0);
            _backgroundLayer.graphics.drawRect(-320, -240, 640, 480);
            _backgroundLayer.graphics.endFill();

            var info:TextField = createLabel("Device Window", 10, 10);
            _contentLayer.addChild(info);

            if (!_isDesktop) {
                this.alwaysInFront = false;
            }
        }

        /**
         * Set up default content
         */
        private function setupDefaultContent():void {
            _backgroundLayer.graphics.clear();
            _backgroundLayer.graphics.beginFill(0x333333, 1.0);
            _backgroundLayer.graphics.drawRect(-400, -300, 800, 600);
            _backgroundLayer.graphics.endFill();

            var info:TextField = createLabel(_type + " Window", 10, 10);
            _contentLayer.addChild(info);
        }

        /**
         * Create standardized text label
         * @param text Label text content
         * @param x Horizontal position
         * @param y Vertical position
         * @return Configured text field
         */
        private function createLabel(text:String, x:Number, y:Number):TextField {
            var label:TextField = new TextField();
            label.width = 400;
            label.height = 60;
            label.x = x;
            label.y = y;
            label.background = false;
            label.textColor = 0xFFFFFF;
            label.selectable = false;
            label.multiline = true;
            label.wordWrap = true;

            var format:TextFormat = new TextFormat();
            format.font = "Verdana";
            format.size = 12;
            format.color = 0xFFFFFF;
            label.defaultTextFormat = format;
            label.text = text;

            return label;
        }

        // =========================================================================
        // EVENT TRANSFORMER METHODS - Convert native events to impulses
        // =========================================================================

        /**
         * Transform mouse down event with pin detection
         * @param event Native mouse down event
         */
        private function transformMouseDown(event:MouseEvent):void {
            // Close any open context menus on regular left click
            if (!event.ctrlKey) {
                closeContextMenus();
            }

            var targetPin:Pin = getPinFromTarget(event.target as DisplayObject);

            if (targetPin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_DOWN", {
                    pin: targetPin,
                    windowType: _type,
                    localX: event.localX,
                    localY: event.localY,
                    stageX: event.stageX,
                    stageY: event.stageY,
                    ctrlKey: event.ctrlKey,
                    altKey: event.altKey,
                    shiftKey: event.shiftKey
                }));
            }

            // Emit general window mouse down
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOWN", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                target: event.target
            }));
        }

        /**
         * Transform mouse up event with pin detection
         * @param event Native mouse up event
         */
        private function transformMouseUp(event:MouseEvent):void {
            var targetPin:Pin = getPinFromTarget(event.target as DisplayObject);

            if (targetPin) {
                MultiPulsator.emit(new Impulse("PIN_MOUSE_UP", {
                    pin: targetPin,
                    windowType: _type,
                    localX: event.localX,
                    localY: event.localY,
                    stageX: event.stageX,
                    stageY: event.stageY
                }));
            }

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                target: event.target
            }));
        }

        /**
         * Transform mouse move event
         * @param event Native mouse move event
         */
        private function transformMouseMove(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_MOVE", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                movementX: event.localX - _lastMousePos.x,
                movementY: event.localY - _lastMousePos.y
            }));

            _lastMousePos.setTo(event.localX, event.localY);
        }

        /**
         * Transform mouse wheel event
         * @param event Native mouse wheel event
         */
        private function transformMouseWheel(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_WHEEL", {
                windowType: _type,
                window: this,
                delta: event.delta,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY
            }));
        }

        /**
         * Helper method to find Pin from any display object in hierarchy
         * @param target Starting display object
         * @return Found Pin or null
         */
        private function getPinFromTarget(target:DisplayObject):Pin {
            var current:DisplayObject = target;
            while (current && !(current is Pin) && current.parent) {
                current = current.parent;
            }
            return current as Pin;
        }

        // =========================================================================
        // WINDOW EVENT TRANSFORMERS
        // =========================================================================

        private function transformWindowActivate(event:Event):void {
            if (!_content) initializeContent();
            MultiPulsator.emit(new Impulse("WINDOW_ACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        private function transformWindowDeactivate(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED", {
                windowType: _type,
                window: this
            }));
        }

        private function transformWindowClosing(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_CLOSING", {
                windowType: _type,
                window: this
            }));
            MultiPulsator.emit(new Impulse("APP_CLOSE"));
        }

        private function transformWindowResize(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_RESIZED", {
                windowType: _type,
                window: this,
                width: this.width,
                height: this.height
            }));
        }

        private function transformDisplayStateChange(event:NativeWindowDisplayStateEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_DISPLAY_STATE_CHANGED", {
                windowType: _type,
                window: this,
                displayState: this.displayState
            }));
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        /**
         * Get main canvas reference
         * @return Main canvas container
         */
        public function get canvas():Sprite {
            return _canvas;
        }

        /**
         * Get background layer reference
         * @return Background layer for static elements
         */
        public function get backgroundLayer():Sprite {
            return _backgroundLayer;
        }

        /**
         * Get content layer reference
         * @return Content layer for dynamic elements
         */
        public function get contentLayer():Sprite {
            return _contentLayer;
        }

        /**
         * Get overlay layer reference
         * @return Overlay layer for temporary elements
         */
        public function get overlayLayer():Sprite {
            return _overlayLayer;
        }

        /**
         * Get current zoom level
         * @return Current zoom level
         */
        public function get zoomLevel():Number {
            return _zoomLevel;
        }

        /**
         * Set zoom level with bounds checking
         * @param level New zoom level
         */
        public function set zoomLevel(level:Number):void {
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, level));
            updateViewport();
        }

        /**
         * Get current viewport position
         * @return Current viewport position
         */
        public function get viewPoint():Point {
            return _viewPoint.clone();
        }

        /**
         * Set viewport position
         * @param point New viewport position
         */
        public function set viewPoint(point:Point):void {
            _viewPoint = point.clone();
            updateViewport();
        }

        /**
         * Get window type identifier
         * @return Window type
         */
        public function get windowType():String {
            return _type;
        }

        /**
         * Reset viewport to default position and zoom
         */
        public function resetViewport():void {
            centerCanvas();
            MultiPulsator.emit(new Impulse("CANVAS_RESET", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

		/**
		 * Add temporary marker at position for debugging
		 */
		private function addDebugMarker(position:Point):void {
			var marker:Sprite = new Sprite();
			marker.graphics.beginFill(0xFF0000, 0.7);
			marker.graphics.drawCircle(0, 0, 10);
			marker.graphics.endFill();
			marker.x = position.x;
			marker.y = position.y;
			_contentLayer.addChild(marker);
			
			// Remove after 2 seconds
			var timer:Timer = new Timer(2000, 1);
			timer.addEventListener(TimerEvent.TIMER, function(e:TimerEvent):void {
				if (_contentLayer.contains(marker)) {
					_contentLayer.removeChild(marker);
				}
			});
			timer.start();
		}

        /**
         * Clean up window resources
         */
        public function dispose():void {
            trace("Disposing window: " + _type);

            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            if (stage) {
                // Remove viewport controls
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                stage.removeEventListener(Event.MOUSE_LEAVE, onMouseLeave);
                stage.removeEventListener(Event.RESIZE, onStageResize);
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
            }

            // Remove background layer listeners
            if (_backgroundLayer) {
                _backgroundLayer.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onBackgroundRightClick);
            }

            // Remove window lifecycle listeners
            removeEventListener(Event.ACTIVATE, transformWindowActivate);
            removeEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            removeEventListener(Event.CLOSING, transformWindowClosing);
            removeEventListener(Event.RESIZE, transformWindowResize);
            removeEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Remove mouse event transformers
            removeEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            removeEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            removeEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            removeEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformRightMouseDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_UP, transformRightMouseUp);
            removeEventListener(MouseEvent.CLICK, transformClick);

            if (_content && stage && stage.contains(_content)) {
                stage.removeChild(_content);
            }

            _content = null;
            _canvas = null;
            _backgroundLayer = null;
            _contentLayer = null;
            _overlayLayer = null;
        }
    }
}
