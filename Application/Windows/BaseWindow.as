package Application.Windows {
    import flash.display.NativeWindow;
    import flash.display.NativeWindowInitOptions;
    import flash.display.NativeWindowSystemChrome;
    import flash.display.NativeWindowType;
    import flash.display.Sprite;
    import flash.display.StageQuality;
    import flash.events.Event;
    import flash.events.NativeWindowDisplayStateEvent;

    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Base Window class - foundation for all application windows
     * Provides common functionality for all application windows
     */
    public class BaseWindow extends NativeWindow {
        public var _sceneCover:Sprite;
        public var movingAlloved:Boolean;
        public var options:NativeWindowInitOptions;
        protected var _windowTitle:String;
        protected var _windowType:String;
        protected var _content:Object;

        /**
         * Base Window constructor
         * @param windowType - window type for identification
         * @param title - window title
         * @param transparent - window transparency flag
         * @param systemChromeType - system chrome type ("standard" or "none")
         */
        public function BaseWindow(windowType:String, title:String, transparent:Boolean,
                                 systemChromeType:String = "standard"):void {
            _windowType = windowType;
            _windowTitle = title;

            options = new NativeWindowInitOptions();
            options.type = NativeWindowType.NORMAL;

            switch(systemChromeType.toLowerCase()) {
                case "none":
                    options.systemChrome = NativeWindowSystemChrome.NONE;
                    options.transparent = transparent;
                    break;
                case "standard":
                default:
                    options.systemChrome = NativeWindowSystemChrome.STANDARD;
                    options.transparent = false;
                    break;
            }

            super(options);

            this.title = title;
            this.alwaysInFront = true;
            this.movingAlloved = true;

            addEventListener(Event.ACTIVATE, onWindowActivate);
            addEventListener(Event.CLOSING, onWindowClose);
            addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, onDisplayStateChange);
        }

        /**
         * Window activate handler
         * Called when window becomes active
         */
        public function onWindowActivate(event:Event):void {
            if (!_sceneCover) {
                initializeScene();
            }

            if (_windowType == "Console") {
                MultiPulsator.emit(new Impulse("CONSOLE_WINDOW_READY", {
                    message: event.currentTarget.content
                }));
            }
        }

        /**
         * Window close handler
         * Called when window is being closed
         */
        public function onWindowClose(event:Event):void {
            MultiPulsator.emit(new Impulse("APP_CLOSE"));

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: _windowType + "Window: [INFO] Application shutdown"
            }));
        }

        /**
         * Initialize window scene
         * Creates basic graphic container and sets up scene
         */
        protected function initializeScene():void {
            _sceneCover = new Sprite();
            _sceneCover.name = "BackPlate";

            stage.quality = StageQuality.BEST;

            stage.addChild(_sceneCover);
        }

        /**
         * Window display state change handler
         * Called when window state changes (normal, minimized, maximized)
         */
        protected function onDisplayStateChange(event:NativeWindowDisplayStateEvent):void {
        }

        /**
         * Window content accessor
         * @return Object - window content or null if not set
         */
        public function get content():Object {
            return _content;
        }
    }
}
