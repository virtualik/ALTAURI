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
     * Transforms native Flash events into MultiPulsator impulses for unified application communication
     *
     * Key features:
     * - Platform-aware window creation (Desktop vs Mobile)
     * - Built-in content types (Editor, Device, Default)
     * - Integrated zoom/pan for editor-type windows
     * - Automatic event-to-impulse transformation
     * - MultiPulsator event system integration
     * - Proper resource management and cleanup
     */
    public class Window extends NativeWindow {
        /** Window type identifier */
        private var _type:String;

        /** Main content container sprite */
        private var _content:Sprite;

        /** Drawing surface for editor-type windows */
        private var _drawingSurface:Sprite;

        /** Current viewport position for panning */
        private var _viewPoint:Point = new Point(0, 0);

        /** Current zoom level for editor-type windows */
        private var _zoom:Number = 0.5;

        /** Dragging state flag for panning operations */
        private var _isDragging:Boolean = false;

        /** Last mouse position for movement calculations */
        private var _lastMousePos:Point = new Point();

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
         * Set up editor-specific content with drawing surface and interactions
         * Includes zoom/pan capabilities and mouse event handling
         * Features professional styling with information display
         */
        private function setupEditorContent():void {
            // Background styling
            _content.graphics.lineStyle(3, 0xffffcc, 0.0);
            _content.graphics.beginFill(0x006699, 1.0);
            _content.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            _content.graphics.endFill();

            // Information label
            var info:TextField = createLabel("Editor", 10, 10);
            _content.addChild(info);

            // Drawing surface for graphical elements
            _drawingSurface = new Sprite();
            _drawingSurface.cacheAsBitmap = true;
            _drawingSurface.name = "DrawingSurface";
            _content.addChild(_drawingSurface);
        }

        /**
         * Set up device-specific content with status display
         * Includes device information panel and control elements
         * Optimized for mobile platform constraints when applicable
         */
        private function setupDeviceContent():void {
            // Background styling
            _content.graphics.lineStyle(3, 0xffffcc, 0.0);
            _content.graphics.beginFill(0x077770, 1.0);
            _content.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            _content.graphics.endFill();

            // Information label
            var info:TextField = createLabel("Device", 10, 10);
            _content.addChild(info);

            // Fixed positioning for mobile platforms
            if (!_isDesktop) {
                this.alwaysInFront = false;
            }
        }

        /**
         * Set up default content for unknown window types
         * Provides basic fallback UI with neutral styling
         * Ensures all window types have functional content
         */
        private function setupDefaultContent():void {
            _content.graphics.beginFill(0x333333, 1.0);
            _content.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            _content.graphics.endFill();

            var info:TextField = createLabel(_type, 10, 10);
            _content.addChild(info);
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

        /**
         * Update viewport transformation based on current zoom and position
         * Applies scale and translation to drawing surface for zoom/pan operations
         * Maintains visual center while adjusting viewport
         */
        private function updateViewport():void {
            if (!_drawingSurface) return;
            _drawingSurface.scaleX = _drawingSurface.scaleY = _zoom;
            _drawingSurface.x = stage.stageWidth / 2 + _viewPoint.x * _zoom;
            _drawingSurface.y = stage.stageHeight / 2 + _viewPoint.y * _zoom;
        }

        /**
         * Handle editor-specific zoom functionality
         * Provides smooth zooming with mouse wheel input
         * Maintains zoom level constraints for usability
         * @param event - Mouse wheel event containing delta information
         */
        private function handleEditorZoom(event:MouseEvent):void {
            var oldZoom:Number = _zoom;
            _zoom += event.delta > 0 ? 0.1 : -0.1;
            _zoom = Math.max(0.4, Math.min(1.0, _zoom));

            updateViewport();
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
         * Handles editor-specific zoom functionality
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

            // Editor-specific zoom handling
            if (_type == "Editor") {
                handleEditorZoom(event);
            }
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
        // PUBLIC API METHODS
        // =========================================================================

        /**
         * Get window content reference
         * Returns drawing surface for editor windows, main content for others
         * @return Sprite - Primary content container for this window
         */
        public function get content():Sprite {
            return _drawingSurface || _content;
        }

        /**
         * Get window type identifier
         * @return String - Window type as specified during construction
         */
        public function get windowType():String {
            return _type;
        }

        /**
         * Clean up window resources and event listeners
         * Essential for preventing memory leaks and clean application shutdown
         * Should be called before window closure or application termination
         */
        public function dispose():void {
            // Remove internal event listeners
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            
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
            _drawingSurface = null;
        }
    }
}
