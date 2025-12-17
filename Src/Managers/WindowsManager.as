package Src.Managers {
    import flash.events.Event;
    import flash.system.Capabilities;
    import Src.Impulsys.Impulsys;
    import Src.Impulsys.Impulse;
    import Src.Windows.Window;
    import Src.Commands.InvokeFunction;
    import Src.Commands.ICommand;
    import Src.Main;

    public class WindowsManager {
        private static var _instance:WindowsManager;
        public var nativeWindow:Window;
        public var editorWindow:Window;
        public var deviceWindow:Window;
        private static var _isDesktop:Boolean = Capabilities.os.indexOf("Windows") >= 0 ||
                                               Capabilities.os.indexOf("Mac") >= 0 ||
                                               Capabilities.os.indexOf("Linux") >= 0;

        public static function getInstance():WindowsManager {
            if (!_instance) {
                _instance = new WindowsManager();
            }
            return _instance;
        }

        public static function createWindows():void {
            var manager:WindowsManager = getInstance();
            manager.nativeWindow = Main.root.stage.nativeWindow as Window;

            if (_isDesktop) {
                manager.editorWindow = new Window("Editor", {
                    x: 100, y: 100, width: 1100, height: 600, title: "Editor"
                });
                manager.editorWindow.activate();

                manager.deviceWindow = new Window("Device", {
                    x: 1200, y: 100, width: 640, height: 480, title: "Device"
                });
                manager.deviceWindow.activate();
            } else {
                manager.editorWindow = new Window("Editor", {
                    title: "Editor"
                });
                manager.editorWindow.activate();
            }

            Impulsys.emit(new Impulse("APP_WINDOWS_READY", {
                windows: manager.getAllWindows(),
                platform: _isDesktop ? "desktop" : "mobile"
            }));
        }

        public function findWindow(type:String):Window {
			if (type == null) return null;

            switch(type.toLowerCase()) {
                case "editor": return editorWindow;
                case "device": return deviceWindow;
                case "native": return nativeWindow;
                default: return null;
            }
        }

        public function closeAllWindows():void {
            if (editorWindow) editorWindow.close();
            if (deviceWindow) deviceWindow.close();
        }

        public function getAllWindows():Object {
            return {
                native: nativeWindow,
                editor: editorWindow,
                device: deviceWindow
            };
        }

        public static function Run():ICommand {
            return new InvokeFunction(createWindows);
        }
    }
}
