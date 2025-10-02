package Application.Commands.Windows {
    import flash.display.StageDisplayState;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;

    import Application.Commands.Command;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Windows.BaseWindow;
    import Application.Windows.EditorWindow;
    import Application.Windows.DeviceWindow;
    import Application.Windows.ConsoleWindow;

    /**
     * Window creation command
     * Creates and configures application windows
     */
    public class Window extends Command {
        private var _windowType:String;
        private var _config:Object;
        private var _createdWindow:BaseWindow;

        public function Window(windowType:String, config:Object = null) {
            super();
            _windowType = windowType;
            _config = config || {};
        }

        override protected function executeInternal():void {
            switch (_windowType) {
                case "Console":
                    _createdWindow = new ConsoleWindow(_config.alpha || false);
                    break;
                case "Editor":
                    _createdWindow = new EditorWindow(_config.alpha || true);
                    break;
                case "Device":
                    _createdWindow = new DeviceWindow(_config.alpha || false);
                    break;
                default:
                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        message: "Window: [ERROR] Unknown window type: " + _windowType
                    }));
                    complete();
                    return;
            }

            if (_config.x != undefined) _createdWindow.x = _config.x;
            if (_config.y != undefined) _createdWindow.y = _config.y;
            if (_config.width != undefined) _createdWindow.width = _config.width;
            if (_config.height != undefined) _createdWindow.height = _config.height;

            if (_config.title != undefined) _createdWindow.title = _config.title;

            _createdWindow.stage.scaleMode = StageScaleMode.NO_SCALE;
            _createdWindow.stage.align = StageAlign.TOP_LEFT;

            _createdWindow.visible = _config.visible !== false;

            if (_config.fullscreen) {
                _createdWindow.stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
            }

            if (_config.visible !== false) {
                _createdWindow.activate();
            }

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Window: [INFO] Command: create " + _windowType + " window - complete"
            }));

            complete();
        }

        public function get content():BaseWindow {
            return _createdWindow;
        }
    }
}
