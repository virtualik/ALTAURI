package Application.Commands.AtomLinker {
    import Application.Commands.Command;
    import Application.AtomLinker.Core.Track;
    import Application.Managers.ConnectionManager;

    /**
     * Create Track Command - creates track between pins
     * Handles track creation through ConnectionManager
     */
    public class CreateTrackCommand extends Command {
        private var _fromPin:Pin;
        private var _toPin:Pin;
        private var _track:Track;

        /**
         * Create Track Command constructor
         * @param fromPin - source pin
         * @param toPin - target pin
         */
        public function CreateTrackCommand(fromPin:Pin, toPin:Pin) {
            _fromPin = fromPin;
            _toPin = toPin;
        }

        /**
         * Execute command internal logic
         */
        override protected function executeInternal():void {
            _track = ConnectionManager.getInstance().createTrack(_fromPin, _toPin);
            complete();
        }

        /**
         * Get created track
         * @return Track - created track
         */
        public function get track():Track {
            return _track;
        }
    }
}
