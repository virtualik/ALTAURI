package Src.Prog.Com.Atoms.Core {
    import flash.utils.Dictionary;
    import Src.Prog.Core.Managers.AtomManager;

    public class TrackRegistry {
        private static var _instance:TrackRegistry;
        private var _activeTracks:Vector.<Track>;
        private var _tracksById:Dictionary;

        public function TrackRegistry() {
            if (_instance) throw new Error("TrackRegistry is singleton");
            _activeTracks = new Vector.<Track>();
            _tracksById = new Dictionary();
        }

        public static function getInstance():TrackRegistry {
            if (!_instance) _instance = new TrackRegistry();
            return _instance;
        }

        public function registerTrack(track:Track):void {
            if (!_tracksById[track.connectionId]) {
                _activeTracks.push(track);
                _tracksById[track.connectionId] = track;
            }
        }

        public function unregisterTrack(track:Track):void {
            var index:int = _activeTracks.indexOf(track);
            if (index !== -1) _activeTracks.splice(index, 1);
            delete _tracksById[track.connectionId];
        }

        public function getTracksByAtom(atom:Atom):Vector.<Track> {
            var result:Vector.<Track> = new Vector.<Track>();
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToAtom(atom.id)) result.push(track);
            }
            return result;
        }

        public function getTracksByPin(pin:Pin):Vector.<Track> {
            var result:Vector.<Track> = new Vector.<Track>();
            for each (var track:Track in _activeTracks) {
                if (track.isConnectedToPin(pin)) result.push(track);
            }
            return result;
        }

        public function getAtomByPin(pin:Pin):Atom {
            var atomManager:AtomManager = AtomManager.getInstance();
            var allAtoms:Array = atomManager.getAtomsForWindow("Editor");
            
            for each (var atomData:Object in allAtoms) {
                var atom:Atom = atomData.atom;
                for each (var inputPin:Pin in atom.inputs) {
                    if (inputPin === pin) return atom;
                }
                for each (var outputPin:Pin in atom.outputs) {
                    if (outputPin === pin) return atom;
                }
            }
            return null;
        }

        public function getAtomView(atom:Atom):AtomView {
            var atomManager:AtomManager = AtomManager.getInstance();
            return atomManager.getAtomView(atom);
        }

        // УДАЛЯЕМ проблемный метод findPinView - переносим логику в Pin
        public function getAllTracks():Vector.<Track> {
            return _activeTracks.slice();
        }
    }
}
