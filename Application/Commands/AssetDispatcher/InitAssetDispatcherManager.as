package Application.Commands.AssetDispatcher
{
    import Application.Commands.Command;
    import Application.Managers.AssetDispatcherManager;
    import Application.Managers.DataManager;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Init Asset Dispatcher Manager Command
     * Initializes and registers AssetDispatcherManager in DataManager
     */
    public class InitAssetDispatcherManager extends Command
    {
        /**
         * Execute command internal logic
         */
        override protected function executeInternal():void
        {
            var manager:AssetDispatcherManager = AssetDispatcherManager.getInstance();
            DataManager.registerData(AssetDispatcherManager.DATA_MANAGER_KEY, manager);
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "InitAssetDispatcherManager: Course initialized."
            }));
            complete();
        }
    }
}
