package Src.Prog.Com.Atoms.Contact.Core {
    import flash.utils.Dictionary;
    import Src.Prog.Com.Atoms.Contact.View.Link;

    public class LinkRegistry {
        private static var _instance:LinkRegistry;
        private var _activeLinks:Array;
        private var _linksById:Dictionary;

        public function LinkRegistry() {
            if (_instance) throw new Error("LinkRegistry is singleton. Use getInstance() instead.");
            _activeLinks = new Array();
            _linksById = new Dictionary();
        }

        public static function getInstance():LinkRegistry {
            if (!_instance) _instance = new LinkRegistry();
            return _instance;
        }

        public function registerLink(link:Link):void {
            if (!_linksById[link.connectionId]) {
                _activeLinks.push(link);
                _linksById[link.connectionId] = link;
            }
        }

        public function unregisterLink(link:Link):void {
            var index:int = _activeLinks.indexOf(link);
            if (index !== -1) _activeLinks.splice(index, 1);
            if (_linksById[link.connectionId]) {
                delete _linksById[link.connectionId];
            }
        }

        public function getLinksByAtom(atomId:String):Array {
            var result:Array = new Array();
            for each (var link:Link in _activeLinks) {
                if (link.isConnectedToAtom(atomId)) {
                    result.push(link);
                }
            }
            return result;
        }

        public function getLinksByContact(contact:Contact):Array {
            var result:Array = new Array();
            for each (var link:Link in _activeLinks) {
                if (link.fromContact === contact || link.toContact === contact) {
                    result.push(link);
                }
            }
            return result;
        }

        public function getAllLinks():Array {
            return _activeLinks.slice();
        }

        public function getActiveLinkCount():int {
            return _activeLinks.length;
        }
    }
}
