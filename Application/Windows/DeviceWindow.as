package Application.Windows {
    import flash.system.Capabilities;
    import Application.Windows.Components.DeviceWindowContent;

    /**
     * Device Window - target device or emulator visualization
     * Window for displaying and interacting with target device or emulator
     */
    public class DeviceWindow extends BaseWindow {
        /**
         * Device Window constructor
         * Creates device window with standard system chrome and fixed positioning
         * @param alpha - transparency flag (not used for standard chrome)
         */
        public function DeviceWindow(alpha:Boolean):void {
            super("Device", "Device Window", alpha, "standard");

            this.movingAlloved = false;
        }

        /**
         * Initialize device scene
         * Overrides base method for device-specific graphic content
         */
        override protected function initializeScene():void {
            super.initializeScene();

            _sceneCover.graphics.lineStyle(3, 0xffffcc, 0.0);
            _sceneCover.graphics.beginFill(0x077770, 1.0);
            _sceneCover.graphics.drawRect(0, 0,
                Capabilities.screenResolutionX - 1,
                Capabilities.screenResolutionY - 1);
            _sceneCover.graphics.endFill();

            _sceneCover.name = "Face";

            _content = new DeviceWindowContent(_sceneCover, this.stage);
        }
    }
}
