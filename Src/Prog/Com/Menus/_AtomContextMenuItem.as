package Src.Prog.Com.Menus {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;

    /**
     * Represents a single item in the AtomContextMenu.
     * Displays the atom type name and category, and provides visual feedback on hover.
     */
    public class AtomContextMenuItem extends Sprite {
        public var atomType:String;
        private var _label:TextField;
        private var _isHighlighted:Boolean = false;
        private var _category:String;

        /**
         * Constructs an AtomContextMenuItem instance.
         * @param type The type of atom this item represents.
         * @param label The display name for the atom type.
         * @param category The optional category for the atom type.
         */
        public function AtomContextMenuItem(type:String, label:String, category:String = "") {
            _category = category;
            this.atomType = type;
            _label = new TextField();
            _label.text = label + (category ? " (" + category + ")" : "");
            _label.x = 5;
            _label.y = 2;
            _label.width = 150;
            _label.height = 16;
            _label.selectable = false;
            _label.mouseEnabled = false;
            var fmt:TextFormat = new TextFormat("Consolas", 10, 0x000000);
            _label.setTextFormat(fmt);
            addChild(_label);

            updateAppearance();
            buttonMode = true;
            addEventListener(MouseEvent.MOUSE_OVER, onHover);
            addEventListener(MouseEvent.MOUSE_OUT, onOut);
            addEventListener(MouseEvent.CLICK, onClick);
        }

        /**
         * Handles the mouse over event to highlight the item.
         */
        private function onHover(e:MouseEvent):void {
            _isHighlighted = true;
            updateAppearance();
        }

        /**
         * Handles the mouse out event to remove the highlight.
         */
        private function onOut(e:MouseEvent):void {
            _isHighlighted = false;
            updateAppearance();
        }

        /**
         * Handles the click event.
         * Stops event propagation to prevent it from bubbling up to the parent menu.
         */
        private function onClick(e:MouseEvent):void {
            e.stopPropagation();
        }

        /**
         * Updates the visual appearance of the item based on its highlighted state.
         */
        private function updateAppearance():void {
            graphics.clear();

            var color:uint = 0xFFFFFF;
            if (_category == "Danger") color = _isHighlighted ? 0xFF6666 : 0xFFCCCC;
            else if (_category == "Info") color = _isHighlighted ? 0x66A3FF : 0xCCE0FF;
            else color = _isHighlighted ? 0x3399FF : 0xFFFFFF;

            graphics.beginFill(color);
            graphics.drawRect(0, 0, this.width, 22);
            graphics.endFill();
        }
    }
}
