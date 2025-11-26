package Src.Prog.Com.Atoms.Core {
	import flash.display.Stage;
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
	import flash.filters.GlowFilter;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
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
			graphics.clear();

			// === Визуальная часть ===
			var fillColor:uint = (_pin.type === Pin.TYPE_OUTPUT) ? 0x0088FF : 0xFF8800;
			var borderColor:uint = 0xFFFFFF;

			graphics.lineStyle(2, borderColor);
			graphics.beginFill(fillColor);
			graphics.drawCircle(0, 0, 4); // ВИЗУАЛЬНЫЙ радиус 4px
			graphics.endFill();

			// === Создаём хит-зону с радиусом 6px для коллизий ===
			var hitCircle:Sprite = new Sprite();
			hitCircle.graphics.beginFill(0x000000, 0);     // полностью прозрачная
			hitCircle.graphics.drawCircle(0, 0, 6);        // радиус 6 — для коллизий
			hitCircle.graphics.endFill();

			// КРИТИЧЕСКИ ВАЖНО: добавляем хит-зону на дисплей-лист!
			this.addChild(hitCircle);

			// Назначаем как hitArea
			this.hitArea = hitCircle;

			// Обязательно для правильной работы hitArea!
			this.mouseChildren = false;   // чтобы клики не "проваливались"
			this.mouseEnabled = true;     // чтобы события приходили
		}

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            this.mouseEnabled = true;
            this.mouseChildren = false;
        }

		/**
		 * Handles mouse down on the pin.
		 * Starts track creation from ANY pin (input or output) with visual feedback.
		 */
		private function onMouseDown(event:MouseEvent):void {
			event.stopPropagation();

			// Запускаем создание дорожки с любого пина
			var startPos:Point = new Point(event.stageX, event.stageY);
			_pin.startTrackCreation(startPos);

			// Визуальная подсветка: пин светится, пока тянем дорожку
			this.filters = [new GlowFilter(0x00FFFF, 1.0, 10, 10, 3, 3)];

			// Снимаем подсветку при отпускании мыши в любом месте
			var stage:Stage = this.stage;
			if (stage) {
				var onMouseUp:Function = function(e:MouseEvent):void {
					// Убираем свечение
					this.filters = [];
					stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
				};
				stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
			}
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