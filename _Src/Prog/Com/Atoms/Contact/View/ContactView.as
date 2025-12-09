package Src.Prog.Com.Atoms.Contact.View {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.filters.GlowFilter;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Interaction.VisualDragManager;

    /**
     * Визуальное представление Contact.
     * Отвечает за отрисовку и обработку взаимодействий (клики, перетаскивание).
     * 
     * @class ContactView
     * @extends Sprite
     */
    public class ContactView extends Sprite {
        
        private var _contact:Contact;
        private var _dragManager:VisualDragManager;

        // Цвета для визуализации
        private static const OUTPUT_COLOR:uint = 0x0088FF;
        private static const INPUT_COLOR:uint = 0xFF8800;
        private static const BORDER_COLOR:uint = 0xFFFFFF;

        /**
         * Создает новый ContactView для указанного контакта.
         * 
         * @param contact - Контакт для визуализации
         */
        public function ContactView(contact:Contact) {
            _contact = contact;
            super();
            
            draw();
            setupInteractions();
            this.name = "ContactView_" + contact.name;
        }

        /**
         * Отрисовывает визуальное представление контакта.
         */
        private function draw():void {
            graphics.clear();

            // Выбираем цвет в зависимости от типа
            var fillColor:uint = (_contact.type === Contact.TYPE_OUTPUT) ? OUTPUT_COLOR : INPUT_COLOR;

            // Рисуем основную точку (визуальная часть)
            graphics.lineStyle(2, BORDER_COLOR);
            graphics.beginFill(fillColor);
            graphics.drawCircle(0, 0, 4); // Визуальный радиус 4px
            graphics.endFill();

            // Создаем невидимую хит-зону большего размера для удобства взаимодействия
            var hitCircle:Sprite = new Sprite();
            hitCircle.graphics.beginFill(0x000000, 0); // Полностью прозрачная
            hitCircle.graphics.drawCircle(0, 0, 4);    // Радиус хит-зоны 
            hitCircle.graphics.endFill();
            this.addChild(hitCircle);
            this.hitArea = hitCircle;

            // Настраиваем интерактивность
            this.mouseChildren = false;
            this.mouseEnabled = true;
        }

        /**
         * Настраивает обработчики взаимодействий.
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        /**
         * Обрабатывает нажатие мыши на контакте.
         * Запускает процесс создания соединения.
         */
        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();
			trace("🎯 STARTING DRAG FROM CONTACT: " + _contact.name + " (" + _contact.type + ")");
            // 🔥 ИСПРАВЛЕНИЕ: Убрал startPos из конструктора
            _dragManager = new VisualDragManager();
            _dragManager.startDragFromContact(_contact);

            // Визуальная подсветка при перетаскивании
            this.filters = [new GlowFilter(0x00FFFF, 1.0, 10, 10, 3, 3)];

            // Снимаем подсветку при отпускании мыши в любом месте
            var stage:flash.display.Stage = this.stage;
            if (stage) {
                var onMouseUp:Function = function(e:MouseEvent):void {
                    // Убираем свечение
                    this.filters = [];
                    stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
                };
                stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            }
        }

        /**
         * Получает связанный контакты.
         * 
         * @return Contact - Связанный контакт
         */
        public function get contact():Contact {
            return _contact;
        }

        /**
         * Освобождает ресурсы.
         */
        public function dispose():void {
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _contact = null;
            _dragManager = null;
        }
    }
}