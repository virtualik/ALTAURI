package Src.Contact.View {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import Src.Contact.Core.Contact;
    import Src.Contact.Interaction.VisualDragManager;
    import Src.Impulsys.Impulsys;
    import Src.Impulsys.Impulse;

    public class thePoint extends Sprite {
        private var _sourceContact:Contact;
        private var _parentLink:Link;
        private var _connectedLinks:Vector.<Link>;

        public function thePoint(sourceContact:Contact, parentLink:Link) {
            _sourceContact = sourceContact;
            _parentLink = parentLink;
            _connectedLinks = new Vector.<Link>();
            super();
            setupVisuals();
            setupInteractions();
        }

        private function setupVisuals():void {
            graphics.beginFill(0x888888);
            graphics.drawCircle(0, 0, 3);
            graphics.endFill();
            this.buttonMode = true;
            this.mouseEnabled = true;
        }

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        private function onRightClick(event:MouseEvent):void {
            event.stopPropagation();
            Impulsys.emit(new Impulse("POINT_RIGHT_CLICK", {
                point: this,
                globalPosition: new Point(event.stageX, event.stageY),
                sourceContact: _sourceContact
            }));
        }

        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            var startPos:Point = new Point(event.stageX, event.stageY);
            var dragManager:VisualDragManager = new VisualDragManager(_sourceContact, startPos);
        }

        public function addConnectedLink(link:Link):void {
            if (_connectedLinks.indexOf(link) === -1) {
                _connectedLinks.push(link);
            }
        }

        public function removeConnectedLink(link:Link):void {
            var index:int = _connectedLinks.indexOf(link);
            if (index !== -1) {
                _connectedLinks.splice(index, 1);
            }
        }

        public function dispose():void {
            this.removeEventListener(MouseEvent.RIGHT_CLICK, onRightClick);
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _sourceContact = null;
            _parentLink = null;
            _connectedLinks = null;
        }

        public function get sourceContact():Contact { return _sourceContact; }
        public function get parentLink():Link { return _parentLink; }
        public function get connectedLinks():Vector.<Link> { return _connectedLinks.slice(); }
    }
}
