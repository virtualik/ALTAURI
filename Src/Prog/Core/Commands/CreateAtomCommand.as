// Src/Prog/Core/Commands/CreateAtomCommand.as
package Src.Prog.Core.Commands {
    import flash.geom.Point;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Com.Atoms.Core.AtomView;
    import Src.Prog.Com.Atoms.Core.AtomFactory;
    import Src.Prog.Core.Managers.AtomManager;
    import Src.Prog.Core.Managers.WindowsManager;
    import Src.Prog.Core.Window;
    import flash.display.DisplayObject;

    /**
     * Command to create and place an atom in a specific window.
     * Encapsulates the entire atom creation process:
     * - Factory instantiation
     * - View creation
     * - Registration in AtomManager
     * - Display list integration
     *
     * Supports undo/redo (future), logging, and composition.
     *
     * @class CreateAtomCommand
     * @extends Command
     */
    public class CreateAtomCommand extends Command {
        private var _atomType:String;
        private var _position:Point;
        private var _windowType:String;
        private var _name:String;

        private var _createdAtom:Atom;
        private var _createdView:AtomView;
        private var _targetWindow:Window;

        /**
         * Constructor.
         *
         * @param {String} atomType - Type of atom to create (e.g., "Button")
         * @param {Point} position - Position in contentLayer coordinates
         * @param {String} windowType - Target window ("Editor", "Device")
         * @param {String} name - Optional display name
         */
        public function CreateAtomCommand(
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

        /**
         * Execute the command: create atom and register it.
         */
        override protected function executeInternal():void {
            try {
                // 1. Create atom + view via factory
                var atomInfo:Object = AtomFactory.createAtom(_atomType, _position, _windowType, _name);
                if (!atomInfo || !atomInfo.atom || !atomInfo.view) {
                    throw new Error("AtomFactory failed to create atom: " + _atomType);
                }

                _createdAtom = atomInfo.atom;
                _createdView = atomInfo.view;

                // 2. Find target window
                _targetWindow = WindowsManager.getInstance().findWindow(_windowType);
                if (!_targetWindow) {
                    throw new Error("Window not found: " + _windowType);
                }

                // 3. Register in AtomManager (which also adds to display list)
                AtomManager.getInstance().addAtomToWindow(_windowType, _createdAtom, _createdView);

                trace("CreateAtomCommand: SUCCESS — " + _atomType + " at " + _position);
                complete();
            } catch (error:Error) {
                dispatchEvent(new CommandErrorEvent(
                    CommandErrorEvent.ERROR,
                    "CreateAtomCommand failed: " + error.message
                ));
            }
        }

        /**
         * Undo the command (future implementation).
         * Currently just a stub — you can extend it later.
         */
        public function undo():void {
            if (_createdAtom && _targetWindow) {
                AtomManager.getInstance().removeAtom(_createdAtom.id);
                trace("CreateAtomCommand: undone — " + _createdAtom.type);
            }
        }

        /**
         * Get the created atom (for chaining or inspection).
         * @return {Atom} The newly created atom, or null if not executed.
         */
        public function get createdAtom():Atom {
            return _createdAtom;
        }

        /**
         * Get the created view.
         * @return {AtomView} The view, or null if not executed.
         */
        public function get createdView():AtomView {
            return _createdView;
        }
    }
}
