package Src.Prog.Com.Atoms.Contact.View {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Core.Windows.Window;
    import flash.filters.GlowFilter;
    import flash.events.Event;
    import Src.Prog.Com.Atoms.Contact.Core.LinkRegistry;
    import Src.Prog.Com.Atoms.Core.AtomView;

    public class Link extends Sprite {
        private var _fromContact:Contact;
        private var _toContact:Contact;
        private var _connectionId:String;
        private var _parentWindow:Window;
        private var _isHighlighted:Boolean = false;

        private static const LINE_COLOR:uint = 0x777777;
        private static const HIGHLIGHT_COLOR:uint = 0x00AAFF;
        private static const LINE_ALPHA:Number = 0.7;
        private static const LINE_THICKNESS:Number = 4;

        public function Link(fromContact:Contact, toContact:Contact) {
            super();

            if (fromContact.type !== Contact.TYPE_OUTPUT) {
                throw new ArgumentError("From contact must be OUTPUT type");
            }
            if (toContact.type !== Contact.TYPE_INPUT) {
                throw new ArgumentError("To contact must be INPUT type");
            }

            _fromContact = fromContact;
            _toContact = toContact;
            _connectionId = generateConnectionId();
            this.name = "Link_" + _connectionId;

            var subscriptionSuccess:Boolean = _toContact.subscribeTo(_fromContact);
            if (!subscriptionSuccess) {
                throw new Error("Failed to create subscription");
            }

            LinkRegistry.getInstance().registerLink(this);
            setupInteractions();
            addToParentWindow();

            if (this.stage) {
                draw();
            } else {
                this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            }
        }

        private function onAddedToStage(event:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            draw();
        }

        private function setupInteractions():void {
            this.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
            this.mouseEnabled = true;
            this.buttonMode = true;
            this.useHandCursor = true;
        }

        private function addToParentWindow():void {
            _parentWindow = getParentWindow();
            if (!_parentWindow) return;

            var targetLayer:Sprite = _parentWindow.tracksLayer ||
                                    _parentWindow.overlayLayer ||
                                    _parentWindow.contentLayer;

            if (targetLayer) {
                targetLayer.addChild(this);
            }
        }

        private function getParentWindow():Window {
            if (!_fromContact.atom) return null;
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(_fromContact.atom.id);
            if (!atomData || !atomData.view) return null;
            var atomView = atomData.view;
            return (atomView.stage) ? atomView.stage.nativeWindow as Window : null;
        }

        private function onRightMouseDown(event:MouseEvent):void {
            event.stopPropagation();
            var pos:Point = new Point(event.stageX, event.stageY);
            this.dispose();
            Impulsys.emit(new Impulse("LINK_RIGHT_CLICK", {
                link: this,
                globalPosition: pos,
                connectionId: _connectionId
            }));
        }

        private function onMouseOver(event:MouseEvent):void {
            _isHighlighted = true;
            draw();
        }

        private function onMouseOut(event:MouseEvent):void {
            _isHighlighted = false;
            draw();
        }

        public function draw():void {
            this.graphics.clear();

            if (!_fromContact || !_toContact || !_fromContact.atom || !_toContact.atom) {
                return;
            }

            var fromPos:Point = getGlobalContactPosition(_fromContact);
            var toPos:Point = getGlobalContactPosition(_toContact);
            var container:Sprite = getLinkContainer();
            if (!container) return;

            var localFrom:Point = container.globalToLocal(fromPos);
            var localTo:Point = container.globalToLocal(toPos);

            var lineColor:uint = _isHighlighted ? HIGHLIGHT_COLOR : LINE_COLOR;
            if (_fromContact.value === true) lineColor = 0x00FF00;

            drawStraightLine(localFrom, localTo, lineColor);
        }

        private function getLinkContainer():Sprite {
            if (!_parentWindow) return null;
            return _parentWindow.tracksLayer ||
                   _parentWindow.overlayLayer ||
                   _parentWindow.contentLayer;
        }

        private function getGlobalContactPosition(contact:Contact):Point {
            var view:ContactView = findContactView(contact);
            if (view && view.stage) return view.localToGlobal(new Point(0, 0));

            if (!contact.atom) return new Point(100, 100);
            var mgr:AtomManager = AtomManager.getInstance();
            var data:Object = mgr.getAtomById(contact.atom.id);
            if (!data || !data.view) return new Point(100, 100);

            var atomView:AtomView = data.view;
            var isInput:Boolean = contact.type === Contact.TYPE_INPUT;
            var xPos:Number = isInput ? 0 : atomView.width;
            return atomView.localToGlobal(new Point(xPos, atomView.height / 2));
        }

        private function findContactView(contact:Contact):ContactView {
            if (!contact.atom) return null;
            var mgr:AtomManager = AtomManager.getInstance();
            var data:Object = mgr.getAtomById(contact.atom.id);
            if (!data || !data.view) return null;

            var view:AtomView = data.view;
            for (var i:int = 0; i < view.numChildren; i++) {
                var child:* = view.getChildAt(i);
                if (child is ContactView) {
                    var contactView:ContactView = child as ContactView;
                    if (contactView.contact === contact) {
                        return contactView;
                    }
                }
            }
            return null;
        }

        private function drawStraightLine(fromPos:Point, toPos:Point, color:uint):void {
            this.graphics.lineStyle(LINE_THICKNESS, color, LINE_ALPHA);
            this.graphics.moveTo(fromPos.x, fromPos.y);
            this.graphics.lineTo(toPos.x, toPos.y);
        }

        private function generateConnectionId():String {
            var a1:String = _fromContact.atom ? _fromContact.atom.id : "unknown";
            var a2:String = _toContact.atom ? _toContact.atom.id : "unknown";
            return "contact_link_" + a1 + "_" + a2 + "_" + new Date().getTime();
        }

        public function updateVisual():void {
            draw();
        }

        public function isConnectedToAtom(atomId:String):Boolean {
            return (_fromContact.atom && _fromContact.atom.id === atomId) ||
                   (_toContact.atom && _toContact.atom.id === atomId);
        }

        public function isConnectedToContact(c:Contact):Boolean {
            return _fromContact === c || _toContact === c;
        }

        public function getConnectionInfo():Object {
            return {
                from: _fromContact.name,
                to: _toContact.name,
                id: _connectionId,
                active: _fromContact.value === true
            };
        }

        public function dispose():void {
            LinkRegistry.getInstance().unregisterLink(this);
            this.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
            this.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
            this.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
            this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            if (_toContact && _toContact.source === _fromContact) {
                _toContact.unsubscribe();
            }

            this.graphics.clear();
            if (this.parent) this.parent.removeChild(this);

            _fromContact = null;
            _toContact = null;
            _parentWindow = null;
        }

        public function get fromContact():Contact { return _fromContact; }
        public function get toContact():Contact { return _toContact; }
        public function get connectionId():String { return _connectionId; }
        public function get isHighlighted():Boolean { return _isHighlighted; }
        public function get parentWindow():Window { return _parentWindow; }
    }
}
