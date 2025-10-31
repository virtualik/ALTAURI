package Src.Prog.Com.Logics {

    import Src.Prog.Com.Atoms.Core.BaseAtom;
    import Src.Prog.Com.Atoms.Core.Pin;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import flash.utils.Dictionary;

    import Src.Prog.Com.Logics.Behaviors.ButtonAtomBehavior;


    /**
     * Manages the behaviors associated with different atom types.
     * Stores and provides IAtomBehavior instances based on the atom type.
     * Integrates with AtomFactory and ConnectionManager to handle pin changes and device interactions.
     */
    public class AtomICScriptManager {
        private static var _instance:AtomICScriptManager;
        private var _behaviors:Dictionary;

        /**
         * Initializes the AtomICScriptManager and subscribes to device interaction impulses.
         */
        public function AtomICScriptManager() {
            _behaviors = new Dictionary();
            MultiPulsator.subscribeToImpulse("DEVICE_ATOM_INTERACTION", onDeviceAtomInteraction);
        }

        /**
         * Gets the singleton instance of the AtomICScriptManager.
         * Creates the instance if it does not exist.
         * @return The singleton AtomICScriptManager instance.
         */
        public static function getInstance():AtomICScriptManager {
            if (!_instance) {
                _instance = new AtomICScriptManager();
            }
            return _instance;
        }

        /**
         * Registers a behavior for a specific atom type.
         * @param atomType The type of the atom (e.g., "Counter").
         * @param behavior The behavior instance to register.
         */
        public function registerBehavior(atomType:String, behavior:IAtomBehavior):void {
            _behaviors[atomType] = behavior;
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "AtomICScriptManager",
                message: "Registered behavior for: " + atomType
            }));
        }

        /**
         * Gets the behavior associated with a specific atom type.
         * @param atomType The type of the atom.
         * @return The registered behavior instance, or null if not found.
         */
        public function getBehavior(atomType:String):IAtomBehavior {
            return _behaviors[atomType];
        }

        /**
         * Invokes the behavior for an atom when one of its input pins changes.
         * @param atom The atom whose pin changed.
         * @param changedPin The pin that changed.
         * @return A new atom instance if the behavior modified it, or the original atom otherwise.
         */
        public function handlePinChange(atom:BaseAtom, changedPin:Pin):BaseAtom {
            if (changedPin.type != Pin.TYPE_INPUT) {
                return atom; // Only inputs trigger behavior
            }
            var behavior:IAtomBehavior = getBehavior(atom.type);
            if (behavior) {
                return behavior.onInputPinChanged(atom, changedPin);
            }
            return atom;
        }

        /**
         * Handles device interaction impulses (e.g., button press/release).
         */
        private function onDeviceAtomInteraction(impulse:Impulse):void {
            var atom:BaseAtom = impulse.data.atom;
            var interactionType:String = impulse.data.interactionType;

            if (!atom) return;

            var behavior:IAtomBehavior = getBehavior(atom.type);
            if (behavior) {
                handleDeviceInteraction(behavior, atom, interactionType);
            }
        }

        /**
         * Executes the appropriate behavior based on the type of device interaction.
         */
        private function handleDeviceInteraction(behavior:IAtomBehavior, atom:BaseAtom, interactionType:String):void {
            switch(interactionType) {
                case "button_press":
                    if (behavior is ButtonAtomBehavior) {
                        var newAtom:BaseAtom = ButtonAtomBehavior(behavior).setPressed(atom, true);
                        updateAtomAndPropagate(newAtom);
					}
                    break;

                case "button_release":
                    if (behavior is ButtonAtomBehavior) {
                        var releasedAtom:BaseAtom = ButtonAtomBehavior(behavior).setPressed(atom, false);
                        updateAtomAndPropagate(releasedAtom);
                    }
                    break;
            }
        }

        /**
         * Updates the atom in the AtomManager and propagates the change.
         */
        private function updateAtomAndPropagate(newAtom:BaseAtom):void {
            var atomManager:AtomManager = AtomManager.getInstance();
            if (atomManager) {
                atomManager.updateAtom(newAtom);
            }
        }
    }
}
