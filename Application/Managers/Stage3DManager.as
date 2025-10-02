package Application.Managers {
    import flash.display.Stage3D;
    import flash.display.Stage;
    import flash.display3D.Context3D;
    import flash.events.Event;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Stage3D.SceneManager;
    import Application.Stage3D.Camera;
    import Application.Stage3D.Renderer;
    import Application.Stage3D.InputController;
    import Application.Commands.ICommand;
    import Application.Commands.Utils.InvokeFunction;
    import Application.Commands.Stage3D.InitStage3D;
    import Application.Commands.Utils.WaitForCondition;
    import Application.Commands.Stage3D.ConfigureBackBuffer;
    import Application.Commands.Stage3D.Create3DScene;
    import Application.Commands.Stage3D.Create3DGrids;
    import Application.Commands.SerialCommand;
    import Application.Commands.Events.CommandErrorEvent;
    import Application.MainSystem;

    /**
     * Stage3D Manager - centralized 3D rendering management
     * Provides unified interface for managing entire Stage3D infrastructure
     * 
     * Main functions:
     * - Stage3D component lifecycle management
     * - Coordination between 3D objects
     * - 3D system access for other modules
     * - Error handling and state recovery
     */
    public class Stage3DManager {
        private static var _instance:Stage3DManager;
        public var stage3D:Stage3D;
        public var context3D:Context3D;
        public var sceneManager:SceneManager;
        public var camera:Camera;
        public var renderer:Renderer;
        public var inputController:InputController;
        private var _isInitialized:Boolean = false;

        /**
         * Singleton access
         */
        public static function getInstance():Stage3DManager {
            if (!_instance) {
                _instance = new Stage3DManager();
            }
            return _instance;
        }

        /**
         * Initialize Stage3D system
         */
        public function initialize(stage3D:Stage3D):void {
            this.stage3D = stage3D;
        }

        /**
         * Create 3D scene
         */
        public function createScene():void {
            if (!context3D) {
                context3D = DataManager.getData("CONTEXT3D") as Context3D;

                if (!context3D) {
                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        message: "Stage3DManager: [ERROR] Attempt to create scene without context"
                    }));
                    throw new Error("Stage3D context not available for scene creation");
                }
            }

            sceneManager = new SceneManager(context3D);
            sceneManager.initScene();

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3DManager: [INFO] 3D scene created"
            }));
        }

        /**
         * Create camera and renderer
         */
        public function createCameraAndRenderer(stage:Stage):void {
            if (!context3D) {
                context3D = DataManager.getData("CONTEXT3D") as Context3D;

                if (!context3D) {
                    dispatchError("Attempt to create camera without context");
                    throw new Error("Stage3D context not available for camera creation");
                }
            }

            if (!sceneManager) {
                dispatchError("Attempt to create camera without scene");
                throw new Error("Scene not initialized for camera creation");
            }

            camera = new Camera();
            camera.setMode("free-look");

            renderer = new Renderer(context3D, camera, sceneManager, stage);
            inputController = new InputController(stage, camera);

            _isInitialized = true;

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3DManager: [INFO] Camera and renderer created"
            }));

            MultiPulsator.emit(new Impulse("STAGE3D_SYSTEM_READY"));
        }

        /**
         * Create grids
         */
        public function createGrids(gridClass:Class):void {
            if (!sceneManager) {
                dispatchError("Attempt to create grids without initialized scene");
                return;
            }

            try {
                sceneManager.initGrids(gridClass);

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "Stage3DManager: [INFO] Grids created"
                }));
            } catch (error:Error) {
                dispatchError("Grid creation error: " + error.message);
            }
        }

        /**
         * Handle resize
         */
        public function handleResize(width:int, height:int):void {
            if (context3D && context3D.driverInfo != "Disposed") {
                try {
                    context3D.configureBackBuffer(width, height, 4, true);

                    MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                        message: "Stage3DManager: [INFO] Dimensions updated: " + width + "x" + height
                    }));
                } catch (error:Error) {
                    dispatchError("Resize error: " + error.message);
                }
            }
        }

        /**
         * Execute render
         */
        public function render():void {
            if (!_isInitialized || !renderer || !context3D || context3D.driverInfo == "Disposed") {
                return;
            }
            try {
                renderer.render();
            } catch (error:Error) {
                dispatchError("Rendering error: " + error.message);
            }
        }

        /**
         * Handle input
         */
        public function handleInput():void {
            if (!_isInitialized || !inputController) {
                return;
            }
            inputController.tick(1.0);
        }

        /**
         * Check readiness
         */
        public function get isInitialized():Boolean {
            return _isInitialized;
        }

        /**
         * Dispatch error message
         */
        private function dispatchError(message:String):void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3DManager: [ERROR] " + message
            }));
        }

        /**
         * Clean up resources
         */
        public function dispose():void {
            if (sceneManager) {
                // Clean scene resources
            }

            _isInitialized = false;

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3DManager: [INFO] Resources released"
            }));
        }

        /**
         * Factory method for Stage3D initialization command
         * Creates and returns sequential Stage3D initialization command
         */
        public static function Run():ICommand {
            return new SerialCommand(0,
                new InvokeFunction(initStage3DProcedure),
                new WaitForCondition(function():Boolean {
                    return DataManager.getData("CONTEXT3D") != null;
                }, 10000, 100),
                new ConfigureBackBuffer(
                    MainSystem.root.stage.stageWidth,
                    MainSystem.root.stage.stageHeight,
                    4,
                    true
                ),
                new Create3DScene(),
                new Create3DGrids(GridTextureBitmapData),
                new InvokeFunction(setupCameraProcedure)
            );
        }

        /**
         * Stage3D initialization procedure
         */
        private static function initStage3DProcedure():void {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Stage3DManager: [INFO] Initializing Stage3D system"
            }));

            var stage3D:Stage3D = MainSystem.root.stage.stage3Ds[0];
            var stage3DManager:Stage3DManager = Stage3DManager.getInstance();
            stage3DManager.initialize(stage3D);

            var initStage3DCmd:InitStage3D = new InitStage3D(stage3D);
            initStage3DCmd.execute();
        }

        /**
         * Camera and renderer setup procedure
         */
        private static function setupCameraProcedure():void {
            var manager:Stage3DManager = Stage3DManager.getInstance();
            var context3D:Context3D = DataManager.getData("CONTEXT3D") as Context3D;

            if (context3D) {
                manager.context3D = context3D;
                var mainStage:Stage = MainSystem.root.stage as Stage;
                manager.createCameraAndRenderer(mainStage);

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "Stage3DManager: [INFO] Camera and renderer configured"
                }));

                MultiPulsator.emit(new Impulse("STAGE3D_SYSTEM_READY"));
            } else {
                throw new Error("Stage3D context not available for camera creation");
            }
        }
    }
}
