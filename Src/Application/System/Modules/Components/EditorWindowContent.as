package Src.Application.System.Modules.Components {
    import flash.display.Sprite;
    import flash.display.DisplayObject;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import flash.events.Event;

    import Src.Application.System.MultiPulsator.MultiPulsator;
    import Src.Application.System.MultiPulsator.Impulse;
    import Src.Application.System.Modules.Components.DrawingSurface;

    /**
     * Editor Window Content - main editor workspace management
     * Handles editor canvas, viewport control, and user interaction
     * 
     * Provides complete editor interface with zoom, pan, and mouse interaction
     * Manages drawing surface and viewport transformations
     */
    public class EditorWindowContent {
        private var _container:Sprite;
        private var _editorInfo:TextField;
        private var _drawingSurface:DrawingSurface;
        private var _viewPointPosition:Point = new Point(0, 0);
        private var _zoomLevel:Number = 0.1;
        private var _zoomStep:Number = 0.1;
        private var _zoomMin:Number = 0.4;
        private var _zoomMax:Number = 1.0;
        private var _isDragging:Boolean = false;
        private var _lastMousePos:Point = new Point();
        private var _stage:flash.display.Stage;

        /**
         * Editor Content constructor
         * @param container - graphic container
         * @param stage - window stage
         */
        public function EditorWindowContent(container:Sprite, stage:flash.display.Stage) {
            _container = container;
            _stage = stage;

            initialize();
            setupMouseListeners();
        }

        /**
         * Set up mouse event listeners
         */
        private function setupMouseListeners():void {
            _stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            _stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        }

        /**
         * Handle mouse move events
         */
        private function onMouseMove(e:MouseEvent):void {
            var localMousePos:Point = _drawingSurface.globalToLocal(new Point(e.stageX, e.stageY));
            MultiPulsator.emit(new Impulse("EDITOR_MOUSE_MOVE", {
                mousePos: localMousePos
            }));
        }

        /**
         * Handle mouse up events
         */
        private function onMouseUp(e:MouseEvent):void {
            MultiPulsator.emit(new Impulse("EDITOR_MOUSE_UP", {
                mousePos: new Point(e.stageX, e.stageY)
            }));
        }

        /**
         * Initialize editor content
         */
        private function initialize():void {
            _editorInfo = new TextField();
            _editorInfo.width = 200;
            _editorInfo.height = 40;
            _editorInfo.x = 10;
            _editorInfo.y = 10;
            _editorInfo.background = false;
            _editorInfo.backgroundColor = 0x003333;
            _editorInfo.textColor = 0x00FFCC;

            var textFormat:TextFormat = new TextFormat();
            textFormat.font = "Consolas";
            textFormat.size = 12;
            textFormat.bold = true;
            _editorInfo.defaultTextFormat = textFormat;

            _editorInfo.text = "Editor";
            _container.addChild(_editorInfo);

            _drawingSurface = new DrawingSurface();
            _drawingSurface.name = "Face";
            _container.addChild(_drawingSurface);
            _drawingSurface.mouseEnabled = false;
            _drawingSurface.mouseChildren = true;

            centerDrawingSurface();
            _stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
            _stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
            _stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
            _stage.addEventListener(Event.MOUSE_LEAVE, handleMouseLeave);
            _stage.addEventListener(Event.RESIZE, onResize);
            subscribeToAtomEvents();
        }

        /**
         * Subscribe to atom-related events
         */
        private function subscribeToAtomEvents():void {
            MultiPulsator.subscribeToImpulse("APP_STARTUP_COMPLETE", onAppStartupComplete);
        }

        /**
         * Handle app startup completion
         */
        private function onAppStartupComplete(impulse:Impulse):void {
            // Application startup complete handling
        }

        /**
         * Handle object addition to editor
         */
        private function onAddToEditor(impulse:Impulse):void {
            var object:Sprite = impulse.data.object as Sprite;
            if(object && _drawingSurface) {
                _drawingSurface.addChild(object);
            }
        }

        /**
         * Center drawing surface
         */
        private function centerDrawingSurface():void {
            _drawingSurface.x = _stage.stageWidth / 2;
            _drawingSurface.y = _stage.stageHeight / 2;
            _viewPointPosition.x = 0;
            _viewPointPosition.y = 0;
            _zoomLevel = 0.5;
            updateViewPointPosition();
        }

        /**
         * Handle mouse wheel for zoom
         */
        private function onMouseWheel(event:MouseEvent):void {
            var mouseStageX:Number = _stage.mouseX;
            var mouseStageY:Number = _stage.mouseY;
            var mouseLocalBefore:Point = _drawingSurface.globalToLocal(new Point(mouseStageX, mouseStageY));
            var oldZoom:Number = _zoomLevel;

            _zoomLevel += (event.delta > 0) ? _zoomStep : -_zoomStep;
            _zoomLevel = Math.max(_zoomMin, Math.min(_zoomMax, _zoomLevel));

            updateViewPointPosition();

            var mouseLocalAfter:Point = _drawingSurface.globalToLocal(new Point(mouseStageX, mouseStageY));
            var scaleRatio:Number = _zoomLevel / oldZoom;
            _viewPointPosition.x += (mouseLocalAfter.x - mouseLocalBefore.x) * scaleRatio;
            _viewPointPosition.y += (mouseLocalAfter.y - mouseLocalBefore.y) * scaleRatio;

            updateViewPointPosition();
        }

        /**
         * Handle middle mouse button down for dragging
         */
        private function onMiddleMouseDown(event:MouseEvent):void {
            _isDragging = true;
            _lastMousePos = new Point(_stage.mouseX, _stage.mouseY);
            _stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Handle mouse dragging
         */
        private function onMouseDrag(event:MouseEvent):void {
            if(_isDragging) {
                var currentMousePos:Point = new Point(_stage.mouseX, _stage.mouseY);
                var dx:Number = currentMousePos.x - _lastMousePos.x;
                var dy:Number = currentMousePos.y - _lastMousePos.y;
                _viewPointPosition.x += dx / _zoomLevel;
                _viewPointPosition.y += dy / _zoomLevel;
                updateViewPointPosition();
                _lastMousePos = currentMousePos;
            }
        }

        /**
         * Handle middle mouse button up
         */
        private function onMiddleMouseUp(event:MouseEvent):void {
            _isDragging = false;
            _stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Handle window resize
         */
        private function onResize(event:Event):void {
            centerDrawingSurface();
        }

        /**
         * Handle mouse leave
         */
        private function handleMouseLeave(event:Event):void {
            event.stopImmediatePropagation();
            _stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseDrag);
        }

        /**
         * Update view point position
         */
        private function updateViewPointPosition():void {
            _drawingSurface.scaleX = _drawingSurface.scaleY = _zoomLevel;
            _drawingSurface.x = _stage.stageWidth / 2 + _viewPointPosition.x * _zoomLevel;
            _drawingSurface.y = _stage.stageHeight / 2 + _viewPointPosition.y * _zoomLevel;
        }

        /**
         * Get drawing surface
         * @return DrawingSurface - drawing surface reference
         */
        public function getDrawingSurface():DrawingSurface {
            return _drawingSurface;
        }
    }
}
