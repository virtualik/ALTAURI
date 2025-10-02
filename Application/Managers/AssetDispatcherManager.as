package Application.Managers
{
    import Application.Managers.DataManager;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;
    import Application.Commands.AssetDispatcher.LoadAssetCommand;
    import Application.Commands.ICommand;
    import Application.Commands.AssetDispatcher.InitAssetDispatcherManager;

    /**
     * Asset Dispatcher Manager - handles asset loading requests via impulse system
     */
    public class AssetDispatcherManager
    {
        public static const DATA_MANAGER_KEY:String = "AssetDispatcherManager";
        private static var _instance:AssetDispatcherManager;

        /**
         * Constructor - subscribes to asset loading impulses
         */
        public function AssetDispatcherManager()
        {
            MultiPulsator.subscribeToImpulse("ASSET_LOAD_REQUEST", onLoadAssetRequest);
        }

        /**
         * Get singleton instance
         */
        public static function getInstance():AssetDispatcherManager
        {
            if (!_instance) {
                _instance = new AssetDispatcherManager();
            }
            return _instance;
        }

        /**
         * Handle asset load request impulse
         */
        private function onLoadAssetRequest(impulse:Impulse):void
        {
            var url:String = impulse.data.url;
            var type:String = impulse.data.type;
            var target:Object = impulse.data.target;

            if (!url || !type || !target) {
                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "[AssetDispatcherManager] ERROR: Bad request."
                }));
                return;
            }

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "[AssetDispatcherManager] Dispatching load: " + url
            }));
            var loadCommand:LoadAssetCommand = new LoadAssetCommand(url, type, target);
            loadCommand.execute();
        }

        /**
         * Factory method for initialization command
         */
        public static function Run():Application.Commands.ICommand
        {
            return new InitAssetDispatcherManager();
        }
    }
}