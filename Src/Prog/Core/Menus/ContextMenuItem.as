package Src.Prog.Core.Menus {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;

    public class ContextMenuItem extends Sprite {
        public var action:String;
        private var _label:TextField;
        private var _isHighlighted:Boolean = false;
        private var _category:String;
        private var _callback:Function;

        public function ContextMenuItem(label:String, action:String, callback:Function, category:String = "Default") {
            this.action = action;
            this._callback = callback;
            this._category = category;

            _label = new TextField();
            _label.text = label;
            _label.x = 5;
            _label.y = 2;
            _label.width = 160;
            _label.height = 16;
            _label.selectable = false;
            _label.mouseEnabled = false;
            var fmt:TextFormat = new TextFormat("Consolas", 10, 0x000000);
            _label.setTextFormat(fmt);
            addChild(_label);

            updateAppearance();
            buttonMode = true;
            useHandCursor = true;

            addEventListener(MouseEvent.MOUSE_OVER, onHover);
            addEventListener(MouseEvent.MOUSE_OUT, onOut);
            addEventListener(MouseEvent.CLICK, onClick);
        }

        private function onHover(e:MouseEvent):void {
            _isHighlighted = true;
            updateAppearance();
        }

        private function onOut(e:MouseEvent):void {
            _isHighlighted = false;
            updateAppearance();
        }

        private function onClick(e:MouseEvent):void {
            e.stopPropagation();
            if (_callback != null) {
                _callback(action);
            }
        }

        private function updateAppearance():void {
            graphics.clear();
            var color:uint = 0xFFFFFF;

            if (_category == "Danger") {
                color = _isHighlighted ? 0xFF6666 : 0xFFCCCC;
            } else if (_category == "Info") {
                color = _isHighlighted ? 0x66A3FF : 0xCCE0FF;
            } else {
                color = _isHighlighted ? 0x3399FF : 0xFFFFFF;
            }

            graphics.beginFill(color);
            graphics.drawRect(2, 2, 166, 22);
            graphics.endFill();
        }
    }
}
