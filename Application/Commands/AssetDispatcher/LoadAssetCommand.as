package Application.Commands.AssetDispatcher
{
    import Application.Commands.Command;
    import flash.display.Loader;
    import flash.display.BitmapData;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.net.URLRequest;
    import flash.system.LoaderContext;
    import flash.utils.ByteArray;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
     * Load Asset Command - handles asset loading operations
     * Supports image loading and delivers results to target objects
     */
    public class LoadAssetCommand extends Command
    {
        public var assetUrl:String;
        public var assetType:String;
        public var targetObject:Object;
        private var _urlLoader:Object;
        private var _imageLoader:Loader;

        /**
         * Load Asset Command constructor
         * @param url - asset URL
         * @param type - asset type
         * @param target - target object for callbacks
         */
        public function LoadAssetCommand(url:String, type:String, target:Object)
        {
            super();
            this.assetUrl = url;
            this.assetType = type;
            this.targetObject = target;
        }

        /**
         * Execute command internal logic
         */
        override protected function executeInternal():void
        {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "LoadAssetCommand: Starting: " + assetUrl
            }));

            switch(assetType.toUpperCase())
            {
                case "IMAGE":
                    loadImage();
                    break;
                default:
                    dispatchError("Unsupported type: " + assetType);
                    break;
            }
        }

        /**
         * Load image asset
         */
        private function loadImage():void
        {
            _imageLoader = new Loader();
            _imageLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onImageLoadComplete);
            _imageLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
            _imageLoader.load(new URLRequest(assetUrl));
        }

        /**
         * Handle image load complete
         */
        private function onImageLoadComplete(e:Event):void
        {
            var bitmapData:BitmapData = new BitmapData(_imageLoader.width, _imageLoader.height);
            bitmapData.draw(_imageLoader);
            deliverResult(bitmapData);
        }

        /**
         * Handle load error
         */
        private function onLoadError(e:IOErrorEvent):void
        {
            dispatchError("IOError: " + e.text);
        }

        /**
         * Deliver result to target object
         * @param data - loaded asset data
         */
        private function deliverResult(data:*):void
        {
            if (targetObject && "onAssetLoadComplete" in targetObject)
            {
                targetObject["onAssetLoadComplete"](assetUrl, data);
            }
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "LoadAssetCommand: Success: " + assetUrl
            }));
            complete();
        }

        /**
         * Dispatch error to target object
         * @param message - error message
         */
        private function dispatchError(message:String):void
        {
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "LoadAssetCommand: ERROR: " + message
            }));
            if (targetObject && "onAssetLoadError" in targetObject)
            {
                targetObject["onAssetLoadError"](assetUrl, message);
            }
            complete();
        }
    }
}
