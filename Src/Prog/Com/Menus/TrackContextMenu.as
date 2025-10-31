package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.Track;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;


    /**
     * Context menu for track operations
     */
    public class TrackContextMenu extends BaseContextMenu {
        private var _targetTrack:Track;

        public function TrackContextMenu(globalClickPos:Point, targetTrack:Track) {
            super();
            _targetTrack = targetTrack;

            graphics.beginFill(0x333333, 0.3);
            graphics.drawRect(-5, 0, 160, 32);
            graphics.endFill();

            var deleteItem:AtomContextMenuItem = new AtomContextMenuItem("delete_track", "Delete Track", "Danger");
            deleteItem.y = 5;
            deleteItem.addEventListener(MouseEvent.CLICK, onDeleteClick);
            addChild(deleteItem);

            this.x = globalClickPos.x;
            this.y = globalClickPos.y;
        }

        private function stopPropagation(event:MouseEvent):void {
            event.stopPropagation();
            event.stopImmediatePropagation();
        }

        private function onDeleteClick(event:MouseEvent):void {
            event.stopPropagation(); // Останавливаем всплытие
            close();
            MultiPulsator.emit(new Impulse("TRACK_DELETE_REQUEST", {
                track: _targetTrack
            }));
        }
    }
}
