package Src.Prog.Com.Atoms.Contact.Interaction {

	import Src.Prog.Com.Atoms.Core.Atom;
	import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.View.ContactView;
    import Src.Prog.Com.Atoms.Contact.View.Link;
    import Src.Prog.Core.Windows.Window;
    import Src.Prog.Core.Managers.AtomManager;
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;

    /**
     * Manages visual dragging for contact connections.
     * Enhanced to support dragging from BOTH input and output contacts.
     */
    public class VisualDragManager {
        
        private var _sourceContact:Contact;
        private var _tempLink:Sprite;
        private var _parentWindow:Window;
        private var _searchingForInput:Boolean = true;  // По умолчанию ищем вход
        
        /**
         * Starts visual drag from a contact.
         * Now supports BOTH input and output contacts.
         */
        public function startDragFromContact(sourceContact:Contact):void {
            trace("🔄 VisualDragManager started from: " + sourceContact.name + 
                  " at (" + sourceContact.type + ")");
            
            _sourceContact = sourceContact;
            _parentWindow = findParentWindow(sourceContact);
            
            if (!_parentWindow) {
                trace("❌ VisualDragManager: No parent window found");
                return;
            }
            
            // Определяем что ищем в зависимости от типа исходного контакта
            if (_sourceContact.type === Contact.TYPE_OUTPUT) {
                _searchingForInput = true;  // Ищем вход для подключения
                trace("🔍 Searching for INPUT contact (dragging from OUTPUT)");
            } else {
                _searchingForInput = false; // Ищем выход для подключения  
                trace("🔍 Searching for OUTPUT contact (dragging from INPUT)");
            }
            
            setupVisuals();
            setupInteractions();
            
            trace("✅ VisualDragManager started successfully");
        }
        
        /**
         * Sets up temporary visual link.
         */
        private function setupVisuals():void {
            var startPos:Point = getGlobalContactPosition(_sourceContact);
            
            if (!_parentWindow.overlayLayer) {
                trace("❌ VisualDragManager: No overlayLayer found");
                return;
            }
            
            var localStart:Point = _parentWindow.overlayLayer.globalToLocal(startPos);
            
            _tempLink = new Sprite();
            _tempLink.graphics.lineStyle(3, _searchingForInput ? 0x00AAFF : 0xFFAA00, 0.8);
            _tempLink.graphics.moveTo(localStart.x, localStart.y);
            _tempLink.graphics.lineTo(localStart.x, localStart.y); // Изначально точка
            
            _parentWindow.overlayLayer.addChild(_tempLink);
            trace("✅ VisualDragManager visuals setup complete");
        }
        
        /**
         * Sets up mouse interactions.
         */
        private function setupInteractions():void {
            var stage:* = _parentWindow.stage;
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_MOVE, handleMouseMove);
                stage.addEventListener(MouseEvent.MOUSE_UP, handleMouseUp);
                trace("✅ VisualDragManager interactions setup complete");
            }
        }
        
        /**
         * Handles mouse movement to update temp link.
         */
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
        
        /**
         * Handles mouse up to finalize connection.
         */
		private function handleMouseUp(event:MouseEvent):void {
			trace("🎯 VisualDragManager: Mouse up - finalizing connection");
			
			// 🔥 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Проверяем что контакты еще существуют
			if (!_sourceContact) {
				trace("❌ _sourceContact is null, cannot finalize");
				cleanup();
				return;
			}
			
			// Находим контакт под курсором
			var targetContact:Contact = findContactUnderMouse(event.stageX, event.stageY);
			
			// Очищаем временную визуализацию
			cleanup();
			
			if (!targetContact) {
				trace("❌ No target contact found under mouse");
				return;
			}
			
			if (targetContact === _sourceContact) {
				trace("❌ Cannot connect contact to itself");
				return;
			}
			
			// 🔥 Проверяем что контакты валидны
			if (!_sourceContact.atom || !targetContact.atom) {
				trace("❌ One or both contacts have no parent atom");
				return;
			}
			
			// Проверяем валидность соединения в зависимости от типа исходного контакта
			if (_sourceContact.type === Contact.TYPE_OUTPUT && 
				targetContact.type === Contact.TYPE_INPUT) {
				// OUTPUT → INPUT: стандартное соединение
				trace("🔗 Creating OUTPUT → INPUT connection");
				createConnection(_sourceContact, targetContact);
			}
			else if (_sourceContact.type === Contact.TYPE_INPUT && 
					 targetContact.type === Contact.TYPE_OUTPUT) {
				// INPUT → OUTPUT: инвертированное соединение (целевой контакт создает соединение к нам)
				trace("🔗 Creating INPUT ← OUTPUT connection (inverted)");
				createConnection(targetContact, _sourceContact);
			}
			else {
				trace("❌ Invalid connection types");
				trace("   Source: " + _sourceContact.type + ", Target: " + targetContact.type);
			}
		}
        
        /**
         * Creates a connection between two contacts.
         */
		private function createConnection(fromContact:Contact, toContact:Contact):void {
			trace("🔗 Attempting connection: " + fromContact.name + " → " + toContact.name);
			
			// Убедимся что контакты принадлежат разным атомам
			if (fromContact.atom && toContact.atom && 
				fromContact.atom.id === toContact.atom.id) {
				trace("❌ Cannot connect contacts of the same atom");
				return;
			}
			
			// Создаем Link
			try {
				var link:Link = LinkCreator.getInstance().createConnection(fromContact, toContact);
				if (link) {
					trace("✅ Connection created successfully!");
					// ... события
				}
			} catch (error:Error) {
				trace("❌ Failed to create link: " + error.message);
			} finally {
				// 🔥 Теперь очищаем _sourceContact
				_sourceContact = null;
			}
		}
        
        /**
         * Finds contact under mouse position.
         */
        private function findContactUnderMouse(stageX:Number, stageY:Number):Contact {
            var mousePoint:Point = new Point(stageX, stageY);
            var allContacts:Vector.<Contact> = getAllContactsInWindow();
            
            var closestContact:Contact = null;
            var minDistance:Number = Number.MAX_VALUE;
            
            for each (var contact:Contact in allContacts) {
                if (contact === _sourceContact) continue;
                
                var contactView:ContactView = findContactView(contact);
                if (!contactView) continue;
                
                // Проверяем коллизию
                if (contactView.hitTestPoint(stageX, stageY, true)) {
                    var center:Point = contactView.localToGlobal(new Point(0, 0));
                    var distance:Number = Point.distance(mousePoint, center);
                    
                    // Проверяем тип контакта (что мы ищем)
                    var isValidTarget:Boolean = false;
                    
                    if (_searchingForInput) {
                        // Ищем вход - target должен быть INPUT
                        isValidTarget = contact.type === Contact.TYPE_INPUT;
                    } else {
                        // Ищем выход - target должен быть OUTPUT  
                        isValidTarget = contact.type === Contact.TYPE_OUTPUT;
                    }
                    
                    if (isValidTarget && distance < minDistance) {
                        closestContact = contact;
                        minDistance = distance;
                    }
                }
            }
            
            if (closestContact) {
                trace("✅ Valid target contact found: " + closestContact.name);
            }
            
            return closestContact;
        }
        
		/**
		 * Gets all contacts in the current window.
		 */
		private function getAllContactsInWindow():Vector.<Contact> {
			var allContacts:Vector.<Contact> = new Vector.<Contact>();

			if (!_parentWindow) return allContacts;

			var atomManager:AtomManager = AtomManager.getInstance();
			var atoms:Array = atomManager.getAtomsForWindow(_parentWindow.windowType);

			for each (var atomData:Object in atoms) {
				var atom:Atom = atomData.atom;
				if (atom) {
					// 🔥 ИСПРАВЛЕНИЕ: Правильное объединение Array и Vector
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
        
        /**
         * Finds ContactView for a contact.
         */
        private function findContactView(contact:Contact):ContactView {
            if (!contact || !contact.atom) return null;
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);
            
            if (!atomData || !atomData.view) return null;
            
            var atomView:AtomView = atomData.view;
            if (!atomView.stage) return null;
            
            // Ищем ContactView среди детей AtomView
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
        
        /**
         * Gets global position of a contact.
         */
        private function getGlobalContactPosition(contact:Contact):Point {
            var contactView:ContactView = findContactView(contact);
            if (contactView && contactView.stage) {
                return contactView.localToGlobal(new Point(0, 0));
            }
            
            // Fallback: use atom position
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
            
            return new Point(100, 100); // Ultimate fallback
        }
        
        /**
         * Finds parent window for a contact.
         */
        private function findParentWindow(contact:Contact):Window {
            if (!contact || !contact.atom) return null;
            
            var atomManager:AtomManager = AtomManager.getInstance();
            var atomData:Object = atomManager.getAtomById(contact.atom.id);
            
            if (!atomData || !atomData.view) return null;
            
            var atomView:AtomView = atomData.view;
            return atomView.stage ? atomView.stage.nativeWindow as Window : null;
        }
				
		/**
		 * Cleans up temporary visuals and interactions.
		 */
		private function cleanup():void {
			trace("🧹 Cleaning up VisualDragManager...");
			
			// Удаляем временную визуализацию
			if (_tempLink && _tempLink.parent) {
				_tempLink.parent.removeChild(_tempLink);
				_tempLink = null;
			}
			
			// Удаляем слушатели событий
			if (_parentWindow && _parentWindow.stage) {
				_parentWindow.stage.removeEventListener(MouseEvent.MOUSE_MOVE, handleMouseMove);
				_parentWindow.stage.removeEventListener(MouseEvent.MOUSE_UP, handleMouseUp);
			}
			
			// 🔥 НЕ очищаем _sourceContact здесь - он нужен для handleMouseUp!
			// Он будет очищен после создания соединения
			_parentWindow = null;
			
			trace("✅ VisualDragManager cleanup complete");
		}
    }
}