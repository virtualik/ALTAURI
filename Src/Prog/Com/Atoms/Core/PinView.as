package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.display.DisplayObject;
    import flash.geom.Point;

    public class PinView extends Sprite {
        private var _pin:Pin;

        public function PinView(pin:Pin) {
            _pin = pin;
            super();
            draw();
            setupInteractions();
        }

        private function draw():void {
            this.graphics.clear();
            var color:uint = (_pin.type == Pin.TYPE_INPUT) ? 0xFF4444 : 0x44FF44;
            this.graphics.beginFill(color);
            this.graphics.drawCircle(0, 0, 4);
            this.graphics.endFill();

            this.buttonMode = true;
            this.useHandCursor = true;
        }

        /**
         * Setup mouse interactions for dragging
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation(); // Important: prevent atom from handling this event

            MultiPulsator.emit(new Impulse("PIN_DRAG_START", {
                pin: _pin,
                startX: event.stageX,
                startY: event.stageY,
                windowType: "Editor" // Assuming pins are in Editor window
            }));

            // Subscribe to mouse move and up on stage
            stage.addEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
        }

        private function on_MouseMove(event:MouseEvent):void {
            MultiPulsator.emit(new Impulse("PIN_DRAG_UPDATE", {
                pin: _pin,
                currentX: event.stageX,
                currentY: event.stageY
            }));
        }

        private function on_MouseUp(event:MouseEvent):void {
            // Find if we're over another pin (улучшенный поиск)
            var targetPin:Pin = findPinUnderMouse(event.stageX, event.stageY);

            MultiPulsator.emit(new Impulse("PIN_DRAG_END", {
                pin: _pin,
                toPin: targetPin,
                endX: event.stageX,
                endY: event.stageY
            }));

            // Clean up stage listeners
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, on_MouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, on_MouseUp);
        }

        /**
         * Find a pin under mouse coordinates (улучшенная версия)
         */
        private function findPinUnderMouse(stageX:Number, stageY:Number):Pin {
            var objects:Array = stage.getObjectsUnderPoint(new Point(stageX, stageY));

            trace("Objects under mouse: " + objects.length);
            
            for each (var obj:DisplayObject in objects) {
                // Пропускаем временные дорожки и другие не-pin объекты
                if (obj is TempTrack) continue;
                if (obj is Track) continue;
                if (obj is Sprite && (obj as Sprite).name == "BackgroundLayer") continue;
                
                if (obj is PinView && obj != this) {
                    trace("Found target pin: " + (obj as PinView).pin.name);
                    return (obj as PinView).pin;
                }
            }
            
            trace("No target pin found in exact search");
            return null;
        }

        public function get pin():Pin { return _pin; }
    }
}
