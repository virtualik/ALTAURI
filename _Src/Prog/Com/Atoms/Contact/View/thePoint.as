package Src.Prog.Com.Atoms.Contact.View {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Interaction.VisualDragManager;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;

    /**
     * Точка ветвления на Link. Позволяет создавать отводы от существующего соединения.
     * Чисто визуальный элемент, не участвующий в передаче данных.
     * 
     * @class Point
     * @extends Sprite
     */
    public class thePoint extends Sprite {
        
        private var _sourceContact:Contact;   // Исходный контакт (выход), от которого идет ветвление
        private var _parentLink:Link;         // Родительский Link, на котором находится эта точка
        private var _connectedLinks:Vector.<Link>; // Все Links, идущие от этой точки

        /**
         * Создает новую точку ветвления.
         * 
         * @param sourceContact - Исходный контакт (выход), от которого идет ветвление
         * @param parentLink - Родительский Link, на котором находится точка
         */
        public function thePoint(sourceContact:Contact, parentLink:Link) {
            _sourceContact = sourceContact;
            _parentLink = parentLink;
            _connectedLinks = new Vector.<Link>();

            super();

            setupVisuals();
            setupInteractions();
        }

        /**
         * Настраивает визуальное представление точки.
         */
        private function setupVisuals():void {
            // Рисуем точку-кружок
            graphics.beginFill(0x888888);
            graphics.drawCircle(0, 0, 3);
            graphics.endFill();

            // Делаем точку интерактивной
            this.buttonMode = true;
            this.mouseEnabled = true;
        }

        /**
         * Настраивает обработчики взаимодействий.
         */
        private function setupInteractions():void {
            this.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        /**
         * Обрабатывает правый клик для показа контекстного меню.
         */
        private function onRightClick(event:MouseEvent):void {
            event.stopPropagation();
            
            Impulsys.emit(new Impulse("POINT_RIGHT_CLICK", {
                point: this,
                globalPosition: new Point(event.stageX, event.stageY),
                sourceContact: _sourceContact
            }));
        }

        /**
         * Обрабатывает нажатие мыши для начала перетаскивания отвода.
         */
        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();

            // Запускаем процесс создания нового отвода от этой точки
            var startPos:Point = new Point(event.stageX, event.stageY);
            var dragManager:VisualDragManager = new VisualDragManager(_sourceContact, startPos);
        }

        /**
         * Добавляет Link, который идет от этой точки.
         * 
         * @param link - Link, подключенный к точке
         */
        public function addConnectedLink(link:Link):void {
            if (_connectedLinks.indexOf(link) === -1) {
                _connectedLinks.push(link);
            }
        }

        /**
         * Удаляет Link из точки.
         * 
         * @param link - Link для удаления
         */
        public function removeConnectedLink(link:Link):void {
            var index:int = _connectedLinks.indexOf(link);
            if (index !== -1) {
                _connectedLinks.splice(index, 1);
            }
        }

        /**
         * Освобождает ресурсы.
         */
        public function dispose():void {
            this.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);

            _sourceContact = null;
            _parentLink = null;
            _connectedLinks = null;
        }

        // =========================================================================
        // PUBLIC ACCESSORS
        // =========================================================================
        public function get sourceContact():Contact { return _sourceContact; }
        public function get parentLink():Link { return _parentLink; }
        public function get connectedLinks():Vector.<Link> { return _connectedLinks.slice(); }
    }
}