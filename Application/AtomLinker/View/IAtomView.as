package Application.AtomLinker.View {
    import Application.AtomLinker.Core.BaseAtom;
    import flash.geom.Point;

    /**
     * IAtomView interface - contract for atom visual representations
     */
    public interface IAtomView {
        function initWithAtom(atom:BaseAtom):void;
        function onAssetLoadComplete(assetUrl:String, assetData:*):void;
        function onAssetLoadError(assetUrl:String, errorMessage:String):void;
        function updateVisuals():void;
        function onDragStart(mousePos:Point):void;
        function onDrag(mousePos:Point):void;
        function onDragEnd(mousePos:Point):void;
    }
}
