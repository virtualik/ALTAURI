package Src.Commands {
    import flash.geom.Point;
    import Src.Atom.Core.Atom;
    import Src.Atom.Core.AtomView;
    import Src.Atom.Core.AtomFactory;
    import Src.Managers.AtomManager;
    import Src.Managers.WindowsManager;
    import Src.Windows.Window;
    import flash.display.DisplayObject;

    public class CreateAtom extends Command {
        private var _atomType:String;
        private var _position:Point;
        private var _windowType:String;
        private var _name:String;
        private var _createdAtom:Atom;
        private var _createdView:AtomView;
        private var _targetWindow:Window;

        public function CreateAtom(
            atomType:String,
            position:Point,
            windowType:String = "Editor",
            name:String = null
        ) {
            super(0, "CreateAtom: " + atomType);
            _atomType = atomType;
            _position = position.clone();
            _windowType = windowType;
            _name = name;
        }

        override protected function executeInternal():void {
            try {
                var atomInfo:Object = AtomFactory.createAtom(_atomType, _position, _windowType, _name);
                if (!atomInfo || !atomInfo.atom || !atomInfo.view) {
                    throw new Error("AtomFactory failed to create atom: " + _atomType);
                }

                _createdAtom = atomInfo.atom;
                _createdView = atomInfo.view;

                _targetWindow = WindowsManager.getInstance().findWindow(_windowType);
                if (!_targetWindow) {
                    throw new Error("Window not found: " + _windowType);
                }

                AtomManager.getInstance().addAtomToWindow(_windowType, _createdAtom, _createdView);

                complete();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(
                    CommandErrorEvent.ERROR,
                    "CreateAtomCommand failed: " + error.message
                ));
            }
        }

        public function undo():void {
            if (_createdAtom && _targetWindow) {
                AtomManager.getInstance().removeAtom(_createdAtom.id);
            }
        }

        public function get createdAtom():Atom {
            return _createdAtom;
        }

        public function get createdView():AtomView {
            return _createdView;
        }
    }
}
