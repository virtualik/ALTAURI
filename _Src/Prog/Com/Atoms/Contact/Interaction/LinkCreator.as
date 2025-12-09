package Src.Prog.Com.Atoms.Contact.Interaction {
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Core.ContactManager;
    import Src.Prog.Com.Atoms.Contact.View.Link;

    /**
     * Создает соединения между контактами.
     * Упрощенная версия.
     */
    public class LinkCreator {

        private static var _instance:LinkCreator;

        public static function getInstance():LinkCreator {
            if (!_instance) {
                _instance = new LinkCreator();
            }
            return _instance;
        }

        /**
         * Создает соединение между двумя контактами.
         */
        public function createConnection(fromContact:Contact, toContact:Contact):Link {
            if (!fromContact || !toContact) {
                trace("LinkCreator: One of contacts is null");
                return null;
            }

            if (fromContact.type !== Contact.TYPE_OUTPUT || toContact.type !== Contact.TYPE_INPUT) {
                trace("LinkCreator: Invalid contact types - must be OUTPUT -> INPUT");
                return null;
            }

            // Проверяем циклы
            if (ContactManager.getInstance().wouldCreateCycle(fromContact, toContact)) {
                trace("LinkCreator: Connection would create a cycle");
                return null;
            }

            try {
                var link:Link = new Link(fromContact, toContact);
                trace("✅ LinkCreator: Connection created - " + fromContact.name + " -> " + toContact.name);
                return link;
            } catch (error:Error) {
                trace("❌ LinkCreator: Failed to create link: " + error.message);
                return null;
            }
			return null;
        }

        /**
         * Удаляет соединение.
         */
        public function removeConnection(link:Link):void {
            if (link) {
                link.dispose();
            }
        }
    }
}