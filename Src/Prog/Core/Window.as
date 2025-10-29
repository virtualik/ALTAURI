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

    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Universal Window - configurable window system with built-in event to impulse transformation
     * AND integrated canvas with pan/zoom functionality and layered content system
     *
     * Key features:
     * - Platform-aware window creation (Desktop vs Mobile)
     * - Built-in content types (Editor, Device, Default)
     * - Integrated zoom/pan for canvas manipulation
     * - Two-layer canvas system (background + dynamic content)
     * - Automatic event-to-impulse transformation
     * - MultiPulsator event system integration
     * - Proper resource management and cleanup
     */
    public class Window extends NativeWindow {
        /** Window type identifier */
        private var _type:String;

        /** Main content container sprite */
        private var _content:Sprite;

        // =========================================================================
        // CANVAS SYSTEM - Integrated pan/zoom functionality
        // =========================================================================
        
        /** Main canvas for pan/zoom operations */
        private var _canvas:Sprite;
        
        /** Background layer - static background elements */
        private var _backgroundLayer:Sprite;
        
        /** Content layer - dynamic elements that move with canvas */
        private var _contentLayer:Sprite;
        
        /** Current viewport position for panning operations */
        private var _viewPoint:Point = new Point(0, 0);
        
        /** Current zoom level for canvas scaling */
        private var _zoomLevel:Number = 1.0;
        
        /** Dragging state flag for panning operations */
        private var _isDragging:Boolean = false;
        
        /** Last mouse position for movement calculations */
        private var _lastMousePos:Point = new Point();
        
        /** Zoom constraints */
        private static const ZOOM_MIN:Number = 0.1;
        private static const ZOOM_MAX:Number = 2.0;
        private static const ZOOM_STEP:Number = 0.1;

        /** Platform detection flag - true for desktop OS */
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        /**
         * Universal Window constructor
         * @param type - Window type identifier ("Editor", "Device", etc.)
         * @param config - Configuration object for window properties (optional)
         * @throws Error If window initialization fails
         */
        public function Window(type:String, config:Object = null) {
            // Initialize NativeWindow with configuration options
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

            // Platform-specific window sizing and positioning
            if (_isDesktop) {
                this.bounds = new Rectangle(
                    actualConfig.x || 100,
                    actualConfig.y || 100,
                    actualConfig.width || 800,
                    actualConfig.height || 600
                );
            } else {
                // Mobile - full screen usage
                this.bounds = new Rectangle(0, 0,
                    Capabilities.screenResolutionX,
                    Capabilities.screenResolutionY);
            }

            // Register event listeners for impulse transformation
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
         * Ensures content is initialized when stage becomes available
         * @param event - ADDED_TO_STAGE event
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            initializeContent();
        }

        /**
         * Setup all event listeners that transform native events into impulses
         * Creates unified event handling system across entire application
         * All native events are converted to MultiPulsator impulses
         */
        private function setupEventToImpulseTransformers():void {
            // Window lifecycle events
            addEventListener(Event.ACTIVATE, transformWindowActivate);
            addEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            addEventListener(Event.CLOSING, transformWindowClosing);
            addEventListener(Event.RESIZE, transformWindowResize);
            addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Mouse events
            addEventListener(MouseEvent.CLICK, transformMouseClick);
            addEventListener(MouseEvent.DOUBLE_CLICK, transformMouseDoubleClick);
            addEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            addEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            addEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            addEventListener(MouseEvent.MOUSE_OVER, transformMouseOver);
            addEventListener(MouseEvent.MOUSE_OUT, transformMouseOut);
            addEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            addEventListener(MouseEvent.RIGHT_CLICK, transformMouseRightClick);
            addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformMouseRightDown);
            addEventListener(MouseEvent.RIGHT_MOUSE_UP, transformMouseRightUp);

            // Keyboard events
            addEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
            addEventListener(KeyboardEvent.KEY_UP, transformKeyUp);

            // Focus events
            addEventListener(FocusEvent.FOCUS_IN, transformFocusIn);
            addEventListener(FocusEvent.FOCUS_OUT, transformFocusOut);
        }

        /**
         * Initialize window content based on window type
         * Creates appropriate UI elements and sets up interactions
         * Called automatically when stage becomes available
         */
        private function initializeContent():void {
            try {
                _content = new Sprite();
                _content.name = "Content";
                stage.quality = StageQuality.BEST;
                stage.addChild(_content);

                // Initialize canvas system with pan/zoom functionality
                initializeCanvasSystem();

                // Type-specific content initialization
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
            } catch (error:Error) {
                trace("Window content initialization error: " + error.message);
            }
        }

        /**
         * Initialize canvas system with pan/zoom functionality
         * Creates the layered canvas structure and sets up viewport controls
         */
        private function initializeCanvasSystem():void {
            // Create main canvas container
            _canvas = new Sprite();
            _canvas.name = "Canvas";
            _content.addChild(_canvas);
            
            // Create background layer for static elements
            _backgroundLayer = new Sprite();
            _backgroundLayer.name = "BackgroundLayer";
            _canvas.addChild(_backgroundLayer);
            
            // Create content layer for dynamic elements
            _contentLayer = new Sprite();
            _contentLayer.name = "ContentLayer";
            _canvas.addChild(_contentLayer);
            
            // Setup viewport controls
            setupViewportControls();
            
            // Center canvas initially
            centerCanvas();
        }

        /**
         * Setup viewport controls for pan/zoom operations
         * Configures mouse wheel zoom and middle mouse button panning
         */
        private function setupViewportControls():void {
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave);
            stage.addEventListener(Event.RESIZE, onStageResize);
        }

        /**
         * Center canvas on stage and reset viewport
         * Useful for resetting the view or initial setup
         */
        private function centerCanvas():void {
            _canvas.x = stage.stageWidth / 2;
            _canvas.y = stage.stageHeight / 2;
            _viewPoint.setTo(0, 0);
            _zoomLevel = 1.0;
            updateViewport();
        }

        /**
         * Mouse wheel handler for zoom operations
         * Provides smooth zooming centered on mouse position
         * @param event - Mouse wheel event
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
            
            // Emit zoom impulse for external listeners
            MultiPulsator.emit(new Impulse("CANVAS_ZOOM_CHANGED", {
                windowType: _type,
                zoomLevel: _zoomLevel,
                viewPoint: _viewPoint.clone()
            }));
        }

        /**
         * Middle mouse down handler - start panning operation
         * @param event - Middle mouse button down event
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _lastMousePos.setTo(stage.mouseX, stage.mouseY);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse drag handler - update panning position
         * @param event - Mouse move event during drag
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
                
                // Emit pan impulse for external listeners
                MultiPulsator.emit(new Impulse("CANVAS_PANNED", {
                    windowType: _type,
                    viewPoint: _viewPoint.clone(),
                    movement: new Point(dx, dy)
                }));
            }
        }

        /**
         * Middle mouse up handler - end panning operation
         * @param event - Middle mouse button up event
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Mouse leave handler - cancel ongoing operations
         * @param event - Mouse leave event
         */
        private function onMouseLeave(event:Event):void {
            _isDragging = false;
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Stage resize handler - maintain canvas positioning
         * @param event - Stage resize event
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
         * Update viewport transformation based on current zoom and position
         * Applies scale and translation to canvas for zoom/pan operations
         */
        private function updateViewport():void {
            _canvas.scaleX = _canvas.scaleY = _zoomLevel;
            _canvas.x = stage.stageWidth / 2 + _viewPoint.x * _zoomLevel;
            _canvas.y = stage.stageHeight / 2 + _viewPoint.y * _zoomLevel;
        }

        /**
         * Set up editor-specific content with professional styling
         * Includes canvas background and information display
         */
        private function setupEditorContent():void {
            // Background styling for editor
            _backgroundLayer.graphics.lineStyle(3, 0xffffcc, 0.0);
            _backgroundLayer.graphics.beginFill(0x006699, 1.0);
            _backgroundLayer.graphics.drawRect(-1000, -500, 2000, 1000);
            _backgroundLayer.graphics.endFill();

            // Information label
            var info:TextField = createLabel("Editor Canvas", 10, 10);
            _contentLayer.addChild(info);
        }

        /**
         * Set up device-specific content with status display
         * Optimized for device simulation and monitoring
         */
        private function setupDeviceContent():void {
            // Background styling for device
            _backgroundLayer.graphics.lineStyle(3, 0xffffcc, 0.0);
            _backgroundLayer.graphics.beginFill(0x077770, 1.0);
            _backgroundLayer.graphics.drawRect(-1000, -500, 2000, 1000);
            _backgroundLayer.graphics.endFill();

            // Information label
            var info:TextField = createLabel("Device Canvas", 10, 10);
            _contentLayer.addChild(info);

            // Fixed positioning for mobile platforms
            if (!_isDesktop) {
                this.alwaysInFront = false;
            }
        }

        /**
         * Set up default content for unknown window types
         * Provides basic fallback UI with neutral styling
         */
        private function setupDefaultContent():void {
            _backgroundLayer.graphics.beginFill(0x333333, 1.0);
            _backgroundLayer.graphics.drawRect(-1000, -500, 2000, 1000);
            _backgroundLayer.graphics.endFill();

            var info:TextField = createLabel(_type + " Canvas", 10, 10);
            _contentLayer.addChild(info);
        }

        /**
         * Create standardized text label with consistent formatting
         * Uses professional typography for clear information display
         * @param text - Label text content
         * @param x - Horizontal position in pixels
         * @param y - Vertical position in pixels
         * @return TextField - Configured and styled text field
         */
        private function createLabel(text:String, x:Number, y:Number):TextField {
            var label:TextField = new TextField();
            label.width = 200;
            label.height = 40;
            label.x = x;
            label.y = y;
            label.background = false;
            label.textColor = 0x00FFCC;

            var format:TextFormat = new TextFormat();
            format.font = "Consolas";
            format.size = 12;
            format.bold = true;
            label.defaultTextFormat = format;
            label.text = text;

            return label;
        }

        // =========================================================================
        // PUBLIC API METHODS - Canvas Access and Control
        // =========================================================================

        /**
         * Get main canvas reference
         * @return Sprite - Main canvas container with pan/zoom transformation
         */
        public function get canvas():Sprite {
            return _canvas;
        }

        /**
         * Get background layer reference
         * @return Sprite - Background layer for static elements
         */
        public function get backgroundLayer():Sprite {
            return _backgroundLayer;
        }

        /**
         * Get content layer reference
         * @return Sprite - Content layer for dynamic elements
         */
        public function get contentLayer():Sprite {
            return _contentLayer;
        }

        /**
         * Get current zoom level
         * @return Number - Current zoom level (0.1 to 2.0)
         */
        public function get zoomLevel():Number {
            return _zoomLevel;
        }

        /**
         * Set zoom level with bounds checking
         * @param level - New zoom level
         */
        public function set zoomLevel(level:Number):void {
            _zoomLevel = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, level));
            updateViewport();
        }

        /**
         * Get current viewport position
         * @return Point - Current viewport position
         */
        public function get viewPoint():Point {
            return _viewPoint.clone();
        }

        /**
         * Set viewport position
         * @param point - New viewport position
         */
        public function set viewPoint(point:Point):void {
            _viewPoint = point.clone();
            updateViewport();
        }

        /**
         * Reset viewport to default position and zoom
         * Centers canvas and sets zoom to 1.0
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
         * Convert global coordinates to canvas-local coordinates
         * Useful for positioning elements relative to canvas
         * @param globalPoint - Global stage coordinates
         * @return Point - Canvas-local coordinates
         */
        public function globalToCanvas(globalPoint:Point):Point {
            return _canvas.globalToLocal(globalPoint);
        }

        /**
         * Convert canvas-local coordinates to global coordinates
         * Useful for UI elements that need stage positioning
         * @param localPoint - Canvas-local coordinates
         * @return Point - Global stage coordinates
         */
        public function canvasToGlobal(localPoint:Point):Point {
            return _canvas.localToGlobal(localPoint);
        }

        /**
         * Get window type identifier
         * @return String - Window type as specified during construction
         */
        public function get windowType():String {
            return _type;
        }

        /**
         * Get window content reference
         * Returns main content container (not canvas)
         * @return Sprite - Primary content container for this window
         */
        public function get content():Sprite {
            return _content;
        }

        // =========================================================================
        // EVENT TRANSFORMER METHODS - Convert native events to MultiPulsator impulses
        // =========================================================================

        /**
         * Window activation event transformer
         * Emits WINDOW_ACTIVATED impulse when window gains focus
         * @param event - Native window activation event
         */
        private function transformWindowActivate(event:Event):void {
            if (!_content) initializeContent();

            MultiPulsator.emit(new Impulse("WINDOW_ACTIVATED", {
                windowType: _type,
                window: this,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Window deactivation event transformer
         * Emits WINDOW_DEACTIVATED impulse when window loses focus
         * @param event - Native window deactivation event
         */
        private function transformWindowDeactivate(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_DEACTIVATED", {
                windowType: _type,
                window: this,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Window closing event transformer
         * Emits WINDOW_CLOSING impulse and APP_CLOSE for backward compatibility
         * @param event - Native window closing event
         */
        private function transformWindowClosing(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_CLOSING", {
                windowType: _type,
                window: this,
                timestamp: new Date().getTime()
            }));

            // Also emit app close for backward compatibility
            MultiPulsator.emit(new Impulse("APP_CLOSE"));
        }

        /**
         * Window resize event transformer
         * Emits WINDOW_RESIZED impulse with new dimensions
         * @param event - Native window resize event
         */
        private function transformWindowResize(event:Event):void {
            MultiPulsator.emit(new Impulse("WINDOW_RESIZED", {
                windowType: _type,
                window: this,
                width: this.width,
                height: this.height,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Display state change event transformer
         * Emits WINDOW_DISPLAY_STATE_CHANGED impulse for maximize/minimize/restore
         * @param event - Native display state change event
         */
        private function transformDisplayStateChange(event:NativeWindowDisplayStateEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_DISPLAY_STATE_CHANGED", {
                windowType: _type,
                window: this,
                displayState: this.displayState,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse click event transformer
         * Emits WINDOW_MOUSE_CLICK impulse with detailed click information
         * @param event - Native mouse click event
         */
        private function transformMouseClick(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_CLICK", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                buttonDown: event.buttonDown,
                ctrlKey: event.ctrlKey,
                altKey: event.altKey,
                shiftKey: event.shiftKey,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse double click event transformer
         * Emits WINDOW_MOUSE_DOUBLE_CLICK impulse
         * @param event - Native mouse double click event
         */
        private function transformMouseDoubleClick(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOUBLE_CLICK", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse down event transformer
         * Emits WINDOW_MOUSE_DOWN impulse with button state
         * @param event - Native mouse down event
         */
        private function transformMouseDown(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_DOWN", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                buttonDown: event.buttonDown,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse up event transformer
         * Emits WINDOW_MOUSE_UP impulse with button state
         * @param event - Native mouse up event
         */
        private function transformMouseUp(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_UP", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                buttonDown: event.buttonDown,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse move event transformer
         * Emits WINDOW_MOUSE_MOVE impulse with movement delta
         * Tracks last position for delta calculations
         * @param event - Native mouse move event
         */
        private function transformMouseMove(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_MOVE", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                movementX: event.localX - _lastMousePos.x,
                movementY: event.localY - _lastMousePos.y,
                timestamp: new Date().getTime()
            }));

            _lastMousePos.setTo(event.localX, event.localY);
        }

        /**
         * Mouse over event transformer
         * Emits WINDOW_MOUSE_OVER impulse when mouse enters window
         * @param event - Native mouse over event
         */
        private function transformMouseOver(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_OVER", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse out event transformer
         * Emits WINDOW_MOUSE_OUT impulse when mouse leaves window
         * @param event - Native mouse out event
         */
        private function transformMouseOut(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_OUT", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Mouse wheel event transformer
         * Emits WINDOW_MOUSE_WHEEL impulse with scroll delta
         * Note: Actual zoom handling is in onMouseWheel method
         * @param event - Native mouse wheel event
         */
        private function transformMouseWheel(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_WHEEL", {
                windowType: _type,
                window: this,
                delta: event.delta,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Right mouse click event transformer
         * Emits WINDOW_MOUSE_RIGHT_CLICK impulse for right-button clicks
         * @param event - Native right mouse click event
         */
        private function transformMouseRightClick(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_RIGHT_CLICK", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Right mouse down event transformer
         * Emits WINDOW_MOUSE_RIGHT_DOWN impulse for right-button press
         * @param event - Native right mouse down event
         */
        private function transformMouseRightDown(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_RIGHT_DOWN", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Right mouse up event transformer
         * Emits WINDOW_MOUSE_RIGHT_UP impulse for right-button release
         * @param event - Native right mouse up event
         */
        private function transformMouseRightUp(event:MouseEvent):void {
            if (!_content) return;

            MultiPulsator.emit(new Impulse("WINDOW_MOUSE_RIGHT_UP", {
                windowType: _type,
                window: this,
                localX: event.localX,
                localY: event.localY,
                stageX: event.stageX,
                stageY: event.stageY,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Key down event transformer
         * Emits WINDOW_KEY_DOWN impulse with key information
         * @param event - Native key down event
         */
        private function transformKeyDown(event:KeyboardEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_KEY_DOWN", {
                windowType: _type,
                window: this,
                keyCode: event.keyCode,
                charCode: event.charCode,
                keyLocation: event.keyLocation,
                ctrlKey: event.ctrlKey,
                altKey: event.altKey,
                shiftKey: event.shiftKey,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Key up event transformer
         * Emits WINDOW_KEY_UP impulse with key information
         * @param event - Native key up event
         */
        private function transformKeyUp(event:KeyboardEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_KEY_UP", {
                windowType: _type,
                window: this,
                keyCode: event.keyCode,
                charCode: event.charCode,
                keyLocation: event.keyLocation,
                ctrlKey: event.ctrlKey,
                altKey: event.altKey,
                shiftKey: event.shiftKey,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Focus in event transformer
         * Emits WINDOW_FOCUS_IN impulse when window gains keyboard focus
         * @param event - Native focus in event
         */
        private function transformFocusIn(event:FocusEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_FOCUS_IN", {
                windowType: _type,
                window: this,
                timestamp: new Date().getTime()
            }));
        }

        /**
         * Focus out event transformer
         * Emits WINDOW_FOCUS_OUT impulse when window loses keyboard focus
         * @param event - Native focus out event
         */
        private function transformFocusOut(event:FocusEvent):void {
            MultiPulsator.emit(new Impulse("WINDOW_FOCUS_OUT", {
                windowType: _type,
                window: this,
                timestamp: new Date().getTime()
            }));
        }

        // =========================================================================
        // CLEANUP AND DISPOSAL
        // =========================================================================

        /**
         * Clean up window resources and event listeners
         * Essential for preventing memory leaks and clean application shutdown
         * Should be called before window closure or application termination
         */
        public function dispose():void {
            // Remove internal event listeners
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            // Remove viewport control listeners
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
                stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
                stage.removeEventListener(Event.MOUSE_LEAVE, onMouseLeave);
                stage.removeEventListener(Event.RESIZE, onStageResize);
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
            }

            // Remove all impulse transformer listeners
            removeEventListener(Event.ACTIVATE, transformWindowActivate);
            removeEventListener(Event.DEACTIVATE, transformWindowDeactivate);
            removeEventListener(Event.CLOSING, transformWindowClosing);
            removeEventListener(Event.RESIZE, transformWindowResize);
            removeEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, transformDisplayStateChange);

            // Remove mouse event listeners
            removeEventListener(MouseEvent.CLICK, transformMouseClick);
            removeEventListener(MouseEvent.DOUBLE_CLICK, transformMouseDoubleClick);
            removeEventListener(MouseEvent.MOUSE_DOWN, transformMouseDown);
            removeEventListener(MouseEvent.MOUSE_UP, transformMouseUp);
            removeEventListener(MouseEvent.MOUSE_MOVE, transformMouseMove);
            removeEventListener(MouseEvent.MOUSE_OVER, transformMouseOver);
            removeEventListener(MouseEvent.MOUSE_OUT, transformMouseOut);
            removeEventListener(MouseEvent.MOUSE_WHEEL, transformMouseWheel);
            removeEventListener(MouseEvent.RIGHT_CLICK, transformMouseRightClick);
            removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, transformMouseRightDown);
            removeEventListener(MouseEvent.RIGHT_MOUSE_UP, transformMouseRightUp);

            // Remove keyboard event listeners
            removeEventListener(KeyboardEvent.KEY_DOWN, transformKeyDown);
            removeEventListener(KeyboardEvent.KEY_UP, transformKeyUp);

            // Remove focus event listeners
            removeEventListener(FocusEvent.FOCUS_IN, transformFocusIn);
            removeEventListener(FocusEvent.FOCUS_OUT, transformFocusOut);

            // Clean up display objects
            if (_content && stage && stage.contains(_content)) {
                stage.removeChild(_content);
            }

            // Clear references
            _content = null;
            _canvas = null;
            _backgroundLayer = null;
            _contentLayer = null;
        }
    }
}
