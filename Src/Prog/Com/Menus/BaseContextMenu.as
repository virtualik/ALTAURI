package Src.Prog.Com.Menus {
    import flash.display.Sprite;
    import flash.events.MouseEvent;

    /**
     * Base class for all context menus in ALTAURUS
     * Provides common functionality and ensures consistent behavior
     */
    public class BaseContextMenu extends Sprite {

        public function BaseContextMenu() {
            // Add common mouse handling to prevent event propagation
            addEventListener(MouseEvent.MOUSE_DOWN, onMenuMouseDown);
        }

        /**
         * Prevents the menu from closing when clicking inside it
         */
        protected function onMenuMouseDown(event:MouseEvent):void {
            event.stopPropagation();
        }

        /**
         * Removes the context menu from display list
         * Override in child classes if additional cleanup is needed
         */
        public function close():void {
            if (parent) {
                parent.removeChild(this);
            }
        }
    }
}
