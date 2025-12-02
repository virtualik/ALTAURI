package Src.Prog.Com.Atoms.Contact.Interaction {
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Core.ContactManager;
    import Src.Prog.Com.Atoms.Contact.View.Link;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;

    /**
     * Создает и управляет соединениями между контактами.
     * Координирует создание логических подписок и визуальных Links.
     * 
     * @class LinkCreator
     */
    public class LinkCreator {
        
        private static var _instance:LinkCreator;
        private var _contactManager:ContactManager;

        /**
         * Приватный конструктор для singleton.
         */
        public function LinkCreator() {
            if (_instance) {
                throw new Error("LinkCreator is singleton. Use getInstance() instead.");
            }
            
            _contactManager = ContactManager.getInstance();
        }

        /**
         * Получает singleton instance создателя соединений.
         * 
         * @return LinkCreator - Единственный экземпляр
         */
        public static function getInstance():LinkCreator {
            if (!_instance) {
                _instance = new LinkCreator();
            }
            return _instance;
        }

        /**
         * Создает соединение между двумя контактами.
         * Выполняет проверки, создает логическую подписку и визуальный Link.
         * 
         * @param fromContact - Исходный контакт (выход)
         * @param toContact - Целевой контакт (вход)
         * @return Link - Созданный визуальный Link или null при ошибке
         */
        public function createConnection(fromContact:Contact, toContact:Contact):Link {
            // Проверяем базовые условия
            if (!fromContact || !toContact) {
                trace("LinkCreator: One of contacts is null");
                return null;
            }

            if (fromContact.type !== Contact.TYPE_OUTPUT || toContact.type !== Contact.TYPE_INPUT) {
                trace("LinkCreator: Invalid contact types - must be OUTPUT -> INPUT");
                return null;
            }

            // Проверяем, не создаст ли соединение цикл
            if (_contactManager.wouldCreateCycle(fromContact, toContact)) {
                trace("LinkCreator: Connection would create a cycle");
                return null;
            }

            // Создаем логическое соединение (подписку)
            var subscriptionSuccess:Boolean = toContact.subscribeTo(fromContact);
            if (!subscriptionSuccess) {
                trace("LinkCreator: Failed to create subscription");
                return null;
            }

            // Создаем визуальное соединение
            var link:Link = new Link(fromContact, toContact);

            // Уведомляем систему о создании соединения
            Impulsys.emit(new Impulse("LINK_CREATED", {
                fromContact: fromContact,
                toContact: toContact,
                link: link
            }));

            trace("LinkCreator: Connection created successfully - " + 
                  fromContact.name + " -> " + toContact.name);

            return link;
        }

        /**
         * Удаляет соединение между контактами.
         * Разрывает логическую подписку и удаляет визуальный Link.
         * 
         * @param link - Визуальный Link для удаления
         */
        public function removeConnection(link:Link):void {
            if (!link) return;

            var fromContact:Contact = link.fromContact;
            var toContact:Contact = link.toContact;

            // Разрываем логическое соединение
            toContact.unsubscribe();

            // Удаляем визуальный Link
            link.dispose();

            // Уведомляем систему об удалении соединения
            Impulsys.emit(new Impulse("LINK_REMOVED", {
                fromContact: fromContact,
                toContact: toContact,
                link: link
            }));

            trace("LinkCreator: Connection removed - " + 
                  fromContact.name + " -> " + toContact.name);
        }

        /**
         * Удаляет все соединения, связанные с указанным контактом.
         * 
         * @param contact - Контакт, для которого удаляем все соединения
         */
        public function removeAllConnectionsForContact(contact:Contact):void {
            if (!contact) return;

            // Для входа: разрываем соединение с источником
            if (contact.type === Contact.TYPE_INPUT) {
                contact.unsubscribe();
            }
            // Для выхода: разрываем соединения со всеми подписчиками
            else if (contact.type === Contact.TYPE_OUTPUT) {
                contact.unsubscribe();
            }

            // Визуальные Links будут удалены через систему событий
            // при вызове unsubscribe на контактах

            trace("LinkCreator: Removed all connections for contact - " + contact.name);
        }
    }
}