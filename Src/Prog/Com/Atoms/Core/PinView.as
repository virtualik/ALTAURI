package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.geom.Point;
    import Src.Prog.Core.Managers.AtomManager;

    /**
     * Visual representation of a pin. Only output pins initiate track creation.
     */
    public class PinView extends Sprite {
        private var _pin:Pin;

        public function PinView(pin:Pin) {
            _pin = pin;
            super();
            draw();
            setupInteractions();
            this.name = "PinView_" + pin.name;
        }

		private function draw():void {
			this.graphics.clear();
			
			// 🔥 УБИРАЕМ НЕВИДИМЫЙ КРУГ - оставляем только видимую часть
			var color:uint = (_pin.type == Pin.TYPE_INPUT) ? 0xFF4444 : 0x44FF44;
			this.graphics.beginFill(color);
			this.graphics.drawCircle(0, 0, 4); // Видимая часть - радиус 4
			this.graphics.endFill();
			
			// 🔥 СОЗДАЕМ ТОЧНУЮ HITAREA ДЛЯ КОЛЛИЗИЙ
			createHitArea();
			
			this.buttonMode = true;
			this.useHandCursor = true;
		}

		/**
		 * Создает точную область для коллизий вокруг пина
		 */
		private function createHitArea():void {
			// Создаем спрайт для hitArea
			var hitAreaSprite:Sprite = new Sprite();
			hitAreaSprite.graphics.beginFill(0x222222, 0.5); // Полностью прозрачный
			hitAreaSprite.graphics.drawCircle(0, 0, 8);    // Радиус коллизий - 6 пикселей
			hitAreaSprite.graphics.endFill();
			
			// Устанавливаем hitArea
			this.hitArea = hitAreaSprite;
			this.addChild(hitAreaSprite);
			
			// 🔥 ВАЖНО: Включаем флаг для использования hitArea
			this.mouseEnabled = true;
		}

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.mouseEnabled = true;
            this.mouseChildren = false;
        }

        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            if (_pin.type === Pin.TYPE_OUTPUT) {
                trace("=== OUTPUT PIN CLICKED: " + _pin.name + " ===");
                var startPos:Point = new Point(event.stageX, event.stageY);
                _pin.startTrackCreation(startPos);
            }
            // Input pins — больше ничего не делают при нажатии
        }

        public function get pin():Pin {
            return _pin;
        }

        public function dispose():void {
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _pin = null;
        }
    }
}