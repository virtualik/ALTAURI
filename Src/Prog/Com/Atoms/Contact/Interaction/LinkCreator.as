package Src.Prog.Com.Atoms.Contact.Interaction {
    import Src.Prog.Com.Atoms.Contact.Core.Contact;
    import Src.Prog.Com.Atoms.Contact.Core.ContactManager;
    import Src.Prog.Com.Atoms.Contact.View.Link;

    public class LinkCreator {
        private static var _instance:LinkCreator;

        public static function getInstance():LinkCreator {
            if (!_instance) {
                _instance = new LinkCreator();
            }
            return _instance;
        }

        public function createConnection(fromContact:Contact, toContact:Contact):Link {
            if (!fromContact || !toContact) {
                return null;
            }

            if (fromContact.type !== Contact.TYPE_OUTPUT || toContact.type !== Contact.TYPE_INPUT) {
                return null;
            }

            if (ContactManager.getInstance().wouldCreateCycle(fromContact, toContact)) {
                return null;
            }

            try {
                var link:Link = new Link(fromContact, toContact);
                return link;
            } catch (error:Error) {
                return null;
            }
			return null;
        }

        public function removeConnection(link:Link):void {
            if (link) {
                link.dispose();
            }
        }
    }
}
