package Src.Prog {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.Event;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.desktop.NativeApplication;
    import flash.display.NativeWindow;

    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import Src.Prog.Core.Commands.SerialCommand;
    import Src.Prog.Core.Commands.RegisterData;
    import Src.Prog.Core.Managers.Director;

    /**
     * Main application class - entry point
     * Initializes system, manages application lifecycle, coordinates components via Director
     * Handles system events and implements graceful shutdown through impulses
     */
    public class Main extends Sprite {
        // Singleton instance
        public static var root:Main = null;

        /**
         * Constructor - initializes root instance and prepares for stage
         */
        public function Main() {
            if (Main.root == null) {
                Main.root = this;
            }
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        /**
         * Handler when added to stage - called when app is fully loaded and ready
         */
        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            // Subscribe to impulses
            Impulsys.subscribeToImpulse("APP_CLOSE", reactor_APP_CLOSE);
            Impulsys.subscribeToImpulse("ENTER_FRAME", reactor_ENTER_FRAME);
            Impulsys.subscribeToImpulse("STAGE_RESIZE", reactor_STAGE_RESIZE);
            Impulsys.subscribeToImpulse("APP_READY", reactor_APP_READY);

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
            Impulsys.emit(new Impulse("STAGE_RESIZE", {
                width: stage.stageWidth,
                height: stage.stageHeight
            }));
        }

        /**
         * Stage resize reactor
         */
        private function reactor_STAGE_RESIZE(impulse:Impulse):void {
            trace("reactor_STAGE_RESIZE");
        }

        /**
         * App ready reactor
         */
        private function reactor_APP_READY(impulse:Impulse):void {
            startRenderLoop();
        }

        /**
         * Enter frame reactor
         */
        private function reactor_ENTER_FRAME(impulse:Impulse):void {
            // Implementation for enter frame reactor
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
            Impulsys.emit(new Impulse("ENTER_FRAME"));
        }

        /**
         * Application initialization
         * Starts system construction process via Director
         */
        private function init():void {
            Director.Run();
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
            Impulsys.emit(new Impulse("APP_CLOSE"));
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