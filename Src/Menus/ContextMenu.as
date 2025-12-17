package Src.Menus {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Windows.Window;

    public class ContextMenu extends Sprite {
        private var _items:Array;
        private var _window:Window;
        private var _globalClickPos:Point;

        public function ContextMenu(items:Array, window:Window, globalClickPos:Point) {
            _items = items;
            _window = window;
            _globalClickPos = globalClickPos.clone();
            buildUI();
            positionInWindow();
            addEventListener(MouseEvent.MOUSE_DOWN, onMenuMouseDown);
        }

        private function buildUI():void {
            var height:Number = 7 + 22 * _items.length;
            graphics.clear();
            graphics.beginFill(0x333333, 0.95);
            graphics.lineStyle(1, 0x666666);
            graphics.drawRect(-1, 4, 172, height);
            graphics.endFill();

            var y:Number = 5;
            for each (var itemConfig:Object in _items) {
                var item:ContextMenuItem = new ContextMenuItem(
                    itemConfig.label,
                    itemConfig.action,
                    itemConfig.callback,
                    itemConfig.category || "Default"
                );
                item.y = y;
                addChild(item);
                y += 22;
            }
        }

        private function positionInWindow():void {
            if (_window && _window.overlayLayer) {
                var localPos:Point = _window.overlayLayer.globalToLocal(_globalClickPos);
                this.x = localPos.x;
                this.y = localPos.y;
            } else {
                this.x = _globalClickPos.x;
                this.y = _globalClickPos.y;
            }
        }

        private function onMenuMouseDown(event:MouseEvent):void {
            event.stopPropagation();
        }

        public function close():void {
            if (parent) {
                parent.removeChild(this);
            }
        }
    }
}
