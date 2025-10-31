package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;

    /**
     * IAtomView interface - contract for atom visual representations.
     * Defines the methods that all atom view classes must implement.
     */
    public interface IAtomView {
        /**
         * Initialize the view with a specific atom.
         * @param atom - The BaseAtom instance this view represents.
         */
        function initWithAtom(atom:BaseAtom):void;

        /**
         * Handle the completion of an asset load.
         * @param assetUrl - The URL of the loaded asset.
         * @param assetData - The loaded asset data.
         */
        function onAssetLoadComplete(assetUrl:String, assetData:*):void;

        /**
         * Handle an error during asset loading.
         * @param assetUrl - The URL of the asset that failed to load.
         * @param errorMessage - The error message describing the failure.
         */
        function onAssetLoadError(assetUrl:String, errorMessage:String):void;

        /**
         * Update the visual representation of the atom based on its current state.
         */
        function updateVisuals():void;

        /**
         * Bring this atom view to the front of its parent's display list.
         */
        function bringToFront():void;

        /**
         * Handle the start of a drag operation.
         * @param mousePos - The mouse position when dragging started.
         */
        function onDragStart(mousePos:Point):void;

        /**
         * Handle the movement during a drag operation.
         * @param mousePos - The current mouse position during dragging.
         */
        function onDrag(mousePos:Point):void;

        /**
         * Handle the end of a drag operation.
         * @param mousePos - The mouse position when dragging ended.
         */
        function onDragEnd(mousePos:Point):void;

        /**
         * Get the BaseAtom instance this view represents.
         * @return BaseAtom - The associated atom instance.
         */
        function get parentAtom():BaseAtom;
    }
}