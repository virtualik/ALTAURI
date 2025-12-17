package Src.Contact.Interaction {

	import Src.Atom.Core.Atom;
	import Src.Atom.Core.AtomView;
    import Src.Contact.Core.Contact;
    import Src.Contact.View.ContactView;
    import Src.Contact.View.Link;
    import Src.Windows.Window;
    import Src.Managers.AtomManager;
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Impulsys.Impulsys;
    import Src.Impulsys.Impulse;

    public class VisualDragManager {
        private var _sourceContact:Contact;
        private var _tempLink:Sprite;
        private var _parentWindow:Window;
        private var _searchingForInput:Boolean = true;

        public function startDragFromContact(sourceContact:Contact):void {
            _sourceContact = sourceContact;
            _parentWindow = findParentWindow(sourceContact);

            if (!_parentWindow) {
                return;
            }

            if (_sourceContact.type === Contact.TYPE_OUTPUT) {
                _searchingForInput = true;
            } else {
                _searchingForInput = false;
            }

            setupVisuals();
            setupInteractions();
        }

        private function setupVisuals():void {
            var startPos:Point = getGlobalContactPosition(_sourceContact);

            if (!_parentWindow.overlayLayer) {
                return;
            }

            var localStart:Point = _parentWindow.overlayLayer.globalToLocal(startPos);

            _tempLink = new Sprite();
            _tempLink.graphics.lineStyle(3, _searchingForInput ? 0x00AAFF : 0xFFAA00, 0.8);
            _tempLink.graphics.moveTo(localStart.x, localStart.y);
            _tempLink.graphics.lineTo(localStart.x, localStart.y);

            _parentWindow.overlayLayer.addChild(_tempLink);
        }

        private function setupInteractions():void {
            var stage:* = _parentWindow.stage;
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_MOVE, handleMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, handleMouseUp);
            }
        }

        private function handleMouseMove(event:MouseEvent):void {
            if (!_tempLink || !_parentWindow.overlayLayer) return;

            var localPos:Point = _parentWindow.overlayLayer.globalToLocal(
                new Point(event.stageX, event.stageY)
            );

            _tempLink.graphics.clear();
            _tempLink.graphics.lineStyle(3, _searchingForInput ? 0x00AAFF : 0xFFAA00, 0.8);

            var startPos:Point = getGlobalContactPosition(_sourceContact);
            var localStart:Point = _parentWindow.overlayLayer.globalToLocal(startPos);

            _tempLink.graphics.moveTo(localStart.x, localStart.y);
            _tempLink.graphics.lineTo(localPos.x, localPos.y);
        }

		private function handleMouseUp(event:MouseEvent):void {
			if (!_sourceContact) {
				cleanup();
				return;
			}

			var targetContact:Contact = findContactUnderMouse(event.stageX, event.stageY);
			cleanup();

			if (!targetContact) {
				return;
			}

			if (targetContact === _sourceContact) {
				return;
			}

			if (!_sourceContact.atom || !targetContact.atom) {
				return;
			}

			if (_sourceContact.type === Contact.TYPE_OUTPUT &&
				targetContact.type === Contact.TYPE_INPUT) {
				createConnection(_sourceContact, targetContact);
			}
			else if (_sourceContact.type === Contact.TYPE_INPUT &&
					 targetContact.type === Contact.TYPE_OUTPUT) {
				createConnection(targetContact, _sourceContact);
			}
		}

		private function createConnection(fromContact:Contact, toContact:Contact):void {
			if (fromContact.atom && toContact.atom &&
				fromContact.atom.id === toContact.atom.id) {
				return;
			}

			try {
				var link:Link = LinkCreator.getInstance().createConnection(fromContact, toContact);
				if (link) {
				}
			} catch (error:Error) {
			} finally {
				_sourceContact = null;
			}
		}

        private function findContactUnderMouse(stageX:Number, stageY:Number):Contact {
            var mousePoint:Point = new Point(stageX, stageY);
            var allContacts:Vector.<Contact> = getAllContactsInWindow();

            var closestContact:Contact = null;
            var minDistance:Number = Number.MAX_VALUE;

            for each (var contact:Contact in allContacts) {
                if (contact === _sourceContact) continue;

                var contactView:ContactView = findContactView(contact);
                if (!contactView) continue;

                if (contactView.hitTestPoint(stageX, stageY, true)) {
                    var center:Point = contactView.localToGlobal(new Point(0, 0));
                    var distance:Number = Point.distance(mousePoint, center);

                    var isValidTarget:Boolean = false;

                    if (_searchingForInput) {
                        isValidTarget = contact.type === Contact.TYPE_INPUT;
                    } else {
                        isValidTarget = contact.type === Contact.TYPE_OUTPUT;
                    }

                    if (isValidTarget && distance < minDistance) {
                        closestContact = contact;
                        minDistance = distance;
                    }
                }
            }

            return closestContact;
        }

		private function getAllContactsInWindow():Vector.<Contact> {
			var allContacts:Vector.<Contact> = new Vector.<Contact>();

			if (!_parentWindow) return allContacts;

			var atomManager:AtomManager = AtomManager.getInstance();
			var atoms:Array = atomManager.getAtomsForWindow(_parentWindow.windowType);

			for each (var atomData:Object in atoms) {
				var atom:Atom = atomData.atom;
				if (atom) {
					for each (var input:Contact in atom.contactInputs) {
						allContacts.push(input);
					}
					for each (var output:Contact in atom.contactOutputs) {
						allContacts.push(output);
					}
				}
			}

			return allContacts;
		}

        private function findContactView(contact:Contact):ContactView {
            if (!contact || !contact.atom) return null;

            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);

            if (!atomData || !atomData.view) return null;

            var atomView:AtomView = atomData.view;
            if (!atomView.stage) return null;

            for (var i:int = 0; i < atomView.numChildren; i++) {
                var child:* = atomView.getChildAt(i);
                if (child is ContactView) {
                    var contactView:ContactView = child as ContactView;
                    if (contactView.contact === contact) {
                        return contactView;
                    }
                }
            }

            return null;
        }

        private function getGlobalContactPosition(contact:Contact):Point {
            var contactView:ContactView = findContactView(contact);
            if (contactView && contactView.stage) {
                return contactView.localToGlobal(new Point(0, 0));
            }

            if (contact.atom) {
                var atomManager:AtomManager = AtomManager.getInstance();
                var atomData:Object = atomManager.getAtomById(contact.atom.id);
                if (atomData && atomData.view) {
                    var atomView:AtomView = atomData.view;
                    if (atomView.stage) {
                        return atomView.localToGlobal(new Point(
                            contact.type === Contact.TYPE_INPUT ? 0 : atomView.width,
                            atomView.height / 2
                        ));
                    }
                }
            }

            return new Point(100, 100);
        }

        private function findParentWindow(contact:Contact):Window {
            if (!contact || !contact.atom) return null;

            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);

            if (!atomData || !atomData.view) return null;

            var atomView:AtomView = atomData.view;
            return atomView.stage ? atomView.stage.nativeWindow as Window : null;
        }

		private function cleanup():void {
			if (_tempLink && _tempLink.parent) {
				_tempLink.parent.removeChild(_tempLink);
				_tempLink = null;
			}

			if (_parentWindow && _parentWindow.stage) {
				_parentWindow.stage.removeEventListener(MouseEvent.MOUSE_MOVE, handleMouseMove);
				_parentWindow.stage.removeEventListener(MouseEvent.MOUSE_UP, handleMouseUp);
			}

			_parentWindow = null;
		}
    }
}
