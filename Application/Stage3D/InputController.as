package Application.Stage3D {
    import flash.events.MouseEvent;
    import flash.events.KeyboardEvent;
    import flash.display.Stage;
    import flash.ui.Keyboard;

    /**
     * Handles user input for camera control
     * Mouse and keyboard interaction
     */
    public class InputController {
        private var stageRef:Stage;
        private var camera:Camera;

        private var isDragging:Boolean = false;
        private var prevMouseX:Number = 0;
        private var prevMouseY:Number = 0;

        private var keyLeft:Boolean = false;
        private var keyRight:Boolean = false;
        private var keyForward:Boolean = false;
        private var keyBackward:Boolean = false;
        private var keyUp:Boolean = false;
        private var keyDown:Boolean = false;

        /** Create input controller for stage and camera */
        public function InputController(stage:Stage, camera:Camera) {
            this.stageRef = stage;
            this.camera = camera;

            stageRef.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            stageRef.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            stageRef.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stageRef.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

            stageRef.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            stageRef.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);

            try { stageRef.focus = stageRef; } catch(e:*) {}
        }

        /** Handle mouse down event */
        private function onMouseDown(e:MouseEvent):void {
            isDragging = true;
            prevMouseX = e.stageX;
            prevMouseY = e.stageY;
        }

        /** Handle mouse up event */
        private function onMouseUp(e:MouseEvent):void {
            isDragging = false;
        }

        /** Handle mouse move event */
        private function onMouseMove(e:MouseEvent):void {
            if (!isDragging) return;

            var dx:Number = -(e.stageX - prevMouseX) * 0.002;
            var dy:Number = -(e.stageY - prevMouseY) * 0.002;
            camera.updateRotation(dx, dy);

            prevMouseX = e.stageX;
            prevMouseY = e.stageY;
        }

        /** Handle mouse wheel event */
        private function onMouseWheel(e:MouseEvent):void {
            var dx:Number = 0, dy:Number = 0, dz:Number = e.delta;
            camera.updatePosition(dx, dy, dz);
        }

        /** Handle key down event */
        private function onKeyDown(e:KeyboardEvent):void {
            switch (e.keyCode) {
                case Keyboard.A:
                case Keyboard.LEFT:
                    keyLeft = true; break;
                case Keyboard.D:
                case Keyboard.RIGHT:
                    keyRight = true; break;
                case Keyboard.W:
                case Keyboard.UP:
                    keyForward = true; break;
                case Keyboard.S:
                case Keyboard.DOWN:
                    keyBackward = true; break;
                case Keyboard.E:
                    keyUp = true; break;
                case Keyboard.Q:
                    keyDown = true; break;
            }
        }

        /** Handle key up event */
        private function onKeyUp(e:KeyboardEvent):void {
            switch (e.keyCode) {
                case Keyboard.A:
                case Keyboard.LEFT:
                    keyLeft = false; break;
                case Keyboard.D:
                case Keyboard.RIGHT:
                    keyRight = false; break;
                case Keyboard.W:
                case Keyboard.UP:
                    keyForward = false; break;
                case Keyboard.S:
                case Keyboard.DOWN:
                    keyBackward = false; break;
                case Keyboard.E:
                    keyUp = false; break;
                case Keyboard.Q:
                    keyDown = false; break;
            }
        }

        /** Update input state */
        public function tick(dt:Number = 1.0):void {
            applyMovement(dt);
        }

        /** Apply movement to camera */
        private function applyMovement(dt:Number = 1.0):void {
            var speed:Number = 0.2 * dt;
            var dx:Number = 0, dy:Number = 0, dz:Number = 0;
            if (keyLeft)     dx -= speed;
            if (keyRight)    dx += speed;
            if (keyForward)  dz += speed;
            if (keyBackward) dz -= speed;
            if (keyUp)       dy += speed;
            if (keyDown)     dy -= speed;

            if (dx != 0 || dy != 0 || dz != 0) {
                camera.updatePosition(dx, dy, dz);
            }
        }
    }
}