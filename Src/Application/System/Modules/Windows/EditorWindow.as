package Src.Application.System.Modules.Windows {
    import flash.system.Capabilities;
    
    import Src.Application.System.Modules.Windows.BaseWindow;
    import Src.Application.System.Modules.Components.EditorWindowContent;

    /**
     * Editor Window - main application workspace
     * Main schematic editor window for creating and editing electrical circuits
     * 
     * Primary workspace for application with drawing surface
     * and editing capabilities for schematic design
     */
    public class EditorWindow extends BaseWindow {
        /**
         * Editor Window constructor
         * Creates editor window with standard system chrome
         * @param alpha - transparency flag (not used for standard chrome)
         */
        public function EditorWindow(alpha:Boolean):void {
            super("Editor", "Editor Window", alpha, "standard");
        }

        /**
         * Initialize editor scene
         * Overrides base method for editor-specific graphic content
         */
        override protected function initializeScene():void {
            super.initializeScene();

            _sceneCover.graphics.lineStyle(3, 0xffffcc, 0.0);
            _sceneCover.graphics.beginFill(0x006699, 1.0);
            _sceneCover.graphics.drawRect(0, 0,
                Capabilities.screenResolutionX - 1,
                Capabilities.screenResolutionY - 1);
            _sceneCover.graphics.endFill();

            _content = new EditorWindowContent(_sceneCover, this.stage);
        }
    }
}
