package Application {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.Event;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.desktop.NativeApplication;
    import flash.display.NativeWindow;

    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Managers.LoggingManager;
    import Application.Commands.SerialCommand;
    import Application.Commands.Data.RegisterData;
    import Application.Managers.Director;
    import Application.Managers.Stage3DManager;

    /**
     * Main application class - entry point
     * Initializes system, manages application lifecycle, coordinates components via Director
     * Handles system events and implements graceful shutdown through impulses
     */
    public class MainSystem extends Sprite {
        // Singleton instance
        public static var root:MainSystem = null;

        // Console text field for debugging
        public var consoleTextField:TextField;

        /**
         * Constructor - initializes root instance and prepares for stage
         */
        public function MainSystem() {
            if (MainSystem.root == null) {
                MainSystem.root = this;
            }

            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        /**
         * Handler when added to stage - called when app is fully loaded and ready
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            // Subscribe to impulses
            MultiPulsator.subscribeToImpulse("APP_CLOSE", reactor_APP_CLOSE);
            MultiPulsator.subscribeToImpulse("ENTER_FRAME", reactor_ENTER_FRAME);
            MultiPulsator.subscribeToImpulse("STAGE_RESIZE", reactor_STAGE_RESIZE);
            MultiPulsator.subscribeToImpulse("APP_READY", reactor_APP_READY);

            // Stage configuration
            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.nativeWindow.title = "Native Window";

            // Event handlers
            stage.nativeWindow.addEventListener(Event.ACTIVATE, onWindowActivate);
            stage.nativeWindow.addEventListener(Event.CLOSING, onWindowClose);
            stage.addEventListener(Event.RESIZE, onStageResize);

            // Start initialization
            init();
        }

        /**
         * Stage resize handler
         */
        private function onStageResize(e:Event):void {
            MultiPulsator.emit(new Impulse("STAGE_RESIZE", {
                width: stage.stageWidth,
                height: stage.stageHeight
            }));
        }

        /**
         * Stage resize reactor
         */
        private function reactor_STAGE_RESIZE(impulse:Impulse):void {
            var manager:Stage3DManager = Stage3DManager.getInstance();
            if (manager && manager.isInitialized) {
                manager.handleResize(impulse.data.width, impulse.data.height);
            }
        }

        /**
         * App ready reactor
         */
        private function reactor_APP_READY(impulse:Impulse):void {
            startRenderLoop();
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "MainSystem",
                message: "ℹ️ Render loop started"
            }));
        }

        /**
         * Enter frame reactor
         */
        private function reactor_ENTER_FRAME(impulse:Impulse):void {
            var manager:Stage3DManager = Stage3DManager.getInstance();
            if (manager && manager.isInitialized && manager.context3D) {
                manager.handleInput();
                manager.render();
            }
        }

        /**
         * Start main render loop
         */
        private function startRenderLoop():void {
            addEventListener(Event.ENTER_FRAME, onEnterFrame);
        }

        /**
         * Enter frame handler
         */
        private function onEnterFrame(e:Event):void {
            MultiPulsator.emit(new Impulse("ENTER_FRAME"));
        }

        /**
         * Application initialization
         * Starts system construction process via Director
         */
        private function init():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "MainSystem",
                message: "ℹ️ Building System started"
            }));
            Director.Start();
        }

        /**
         * Window activate handler
         * Called when app window becomes active
         */
        public function onWindowActivate(event:Event):void {
            // stage.nativeWindow.visible = false;
        }

        /**
         * Window close handler
         * Implements graceful shutdown through impulse system
         */
        public function onWindowClose(event:Event):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                level: "INFO",
                source: "MainSystem",
                message: "ℹ️ Application shutting down"
            }));
            MultiPulsator.emit(new Impulse("APP_CLOSE"));

        }

        /**
         * App close reactor
         * Handles APP_CLOSE impulse - properly terminates application
         */
        private static function reactor_APP_CLOSE(impulse:Impulse):void {
            NativeApplication.nativeApplication.exit();
        }
    }
}
