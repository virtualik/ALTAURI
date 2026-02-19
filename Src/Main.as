package Src {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.Event;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.desktop.NativeApplication;
    import flash.display.NativeWindow;
    import Src.Impulsator.Impulsys;
    import Src.Impulsator.Impulse;
    import Src.Commands.SerialCommand;
    import Src.Commands.RegisterData;
    import Src.Managers.Director;

    public class Main extends Sprite {
        public static var root:Main = null;

        public function Main() {
            if (Main.root == null) {
                Main.root = this;
            }
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        private function onAddedToStage(event:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

            Impulsys.subscribeToImpulse("APP_CLOSE", reactor_APP_CLOSE);
            Impulsys.subscribeToImpulse("ENTER_FRAME", reactor_ENTER_FRAME);
            Impulsys.subscribeToImpulse("STAGE_RESIZE", reactor_STAGE_RESIZE);
            Impulsys.subscribeToImpulse("APP_READY", reactor_APP_READY);

            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.nativeWindow.title = "Native Window";

            stage.nativeWindow.addEventListener(Event.ACTIVATE, onWindowActivate);
            stage.nativeWindow.addEventListener(Event.CLOSING, onWindowClose);
            stage.addEventListener(Event.RESIZE, onStageResize);

            init();
        }

        private function onStageResize(e:Event):void {
            Impulsys.emit(new Impulse("STAGE_RESIZE", {
                width: stage.stageWidth,
                height: stage.stageHeight
            }));
        }

        private function reactor_STAGE_RESIZE(impulse:Impulse):void {
        }

        private function reactor_APP_READY(impulse:Impulse):void {
            startRenderLoop();
        }

        private function reactor_ENTER_FRAME(impulse:Impulse):void {
        }

        private function startRenderLoop():void {
            addEventListener(Event.ENTER_FRAME, onEnterFrame);
        }

        private function onEnterFrame(e:Event):void {
            Impulsys.emit(new Impulse("ENTER_FRAME"));
        }

        private function init():void {
            Director.Run();
        }

        public function onWindowActivate(event:Event):void {
        }

        public function onWindowClose(event:Event):void {
            Impulsys.emit(new Impulse("APP_CLOSE"));
        }

        private static function reactor_APP_CLOSE(impulse:Impulse):void {
            NativeApplication.nativeApplication.exit();
        }
    }
}
