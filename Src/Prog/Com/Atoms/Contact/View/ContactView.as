package Src.Prog.Com.Atoms.Contact.View {
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.filters.GlowFilter;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Interaction.VisualDragManager;

    public class ContactView extends Sprite {
        private var _contact:Contact;
        private var _dragManager:VisualDragManager;
        private static const OUTPUT_COLOR:uint = 0x0088FF;
        private static const INPUT_COLOR:uint = 0xFF8800;
        private static const BORDER_COLOR:uint = 0xFFFFFF;

        public function ContactView(contact:Contact) {
            _contact = contact;
            super();
            draw();
            setupInteractions();
            this.name = "ContactView_" + contact.name;
        }

        private function draw():void {
            graphics.clear();
            var fillColor:uint = (_contact.type === Contact.TYPE_OUTPUT) ? OUTPUT_COLOR : INPUT_COLOR;
            graphics.lineStyle(2, BORDER_COLOR);
            graphics.beginFill(fillColor);
            graphics.drawCircle(0, 0, 4);
            graphics.endFill();

            var hitCircle:Sprite = new Sprite();
            hitCircle.graphics.beginFill(0x000000, 0);
            hitCircle.graphics.drawCircle(0, 0, 4);
            hitCircle.graphics.endFill();
            this.addChild(hitCircle);
            this.hitArea = hitCircle;

            this.mouseChildren = false;
            this.mouseEnabled = true;
        }

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        }

        private function onMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            _dragManager = new VisualDragManager();
            _dragManager.startDragFromContact(_contact);

            this.filters = [new GlowFilter(0x00FFFF, 1.0, 10, 10, 3, 3)];

            var stage:flash.display.Stage = this.stage;
            if (stage) {
                var onMouseUp:Function = function(e:MouseEvent):void {
                    this.filters = [];
                    stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
                };
                stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            }
        }

        public function get contact():Contact {
            return _contact;
        }

        public function dispose():void {
            this.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            _contact = null;
            _dragManager = null;
        }
    }
}
