package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Context menu for creating new atoms on the canvas
     */
    public class AtomCreationContextMenu extends BaseContextMenu {
        private var _clickPosition:Point;
        private var _items:Array = [];

        public function AtomCreationContextMenu(localClickPos:Point, canvasPos:Point) {
            super();
            _clickPosition = canvasPos;

            trace("AtomCreationContextMenu created at: " + localClickPos);
            
            // Build menu UI
            buildMenuUI();

            // Position menu - используем переданные локальные координаты
            this.x = localClickPos.x;
            this.y = localClickPos.y;
            
            trace("Menu positioned at: " + this.x + ", " + this.y);
        }

        /**
         * Builds the menu user interface with temporary atom types
         */
        private function buildMenuUI():void {
            // Временный список типов атомов
            var atomTypes:Array = [
                {type: "Button", displayName: "Button", category: "Input"},
                {type: "Counter", displayName: "Counter", category: "Logic"}, 
                {type: "NumberDisplay", displayName: "Number Display", category: "Output"}
            ];

            // Рисуем яркий видимый фон для отладки
            graphics.beginFill(0x333333, 0.95);
            graphics.lineStyle(2, 0xFFFFFF);
            graphics.drawRect(0, 0, 170, 10 + 22 * atomTypes.length);
            graphics.endFill();

            var y:Number = 5;

            for each (var atomType:Object in atomTypes) {
                var item:AtomContextMenuItem = new AtomContextMenuItem(
                    atomType.type,
                    atomType.displayName,
                    atomType.category
                );
                item.y = y;
                item.addEventListener(MouseEvent.CLICK, onItemClick);
                addChild(item);
                _items.push(item);
                y += 22;
            }
            
            trace("Menu UI built with " + atomTypes.length + " items");
        }

        /**
         * Handles menu item click
         */
		private function onItemClick(event:MouseEvent):void {
			var item:AtomContextMenuItem = event.currentTarget as AtomContextMenuItem;
			trace("Menu item clicked: " + item.atomType + " at position: " + _clickPosition);
			close();

			MultiPulsator.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
				atomType: item.atomType,
				position: _clickPosition
			}));
		}
    }
}
