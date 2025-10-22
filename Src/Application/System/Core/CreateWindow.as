package Src.Application.System.Core {
    import flash.display.StageDisplayState;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;

    import Src.Application.System.Core.Command;
    import Src.Application.System.Modules.Windows.BaseWindow;
    import Src.Application.System.Modules.Windows.EditorWindow;
    import Src.Application.System.Modules.Windows.DeviceWindow;

    /**
     * Window creation command
     * Creates and configures application windows
     * 
     * Provides unified interface for window creation through command pattern
     * Handles configuration and setup of different window types
     */
    public class CreateWindow extends Command {
        private var _windowType:String;
        private var _config:Object;
        private var _createdWindow:BaseWindow;

        public function CreateWindow(windowType:String, config:Object = null) {
            super();
            _windowType = windowType;
            _config = config || {};
        }

        /**
         * Execute command - create and configure window
         */
        override protected function executeInternal():void {
            switch (_windowType) {
                case "Editor":
                    _createdWindow = new EditorWindow(_config.alpha || true);
                    break;
                case "Device":
                    _createdWindow = new DeviceWindow(_config.alpha || false);
                    break;
                default:
                    // Unknown window type - complete without creating window
                    complete();
                    return;
            }

            // Apply configuration
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

            complete();
        }

        /**
         * Get created window reference
         * @return BaseWindow - reference to created window
         */
        public function get content():BaseWindow {
            return _createdWindow;
        }
    }
}
