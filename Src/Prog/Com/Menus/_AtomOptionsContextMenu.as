package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Com.Atoms.Core.Atom;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;

    /**
     * Context menu for atom operations (delete, properties, etc.)
     * Provides options for managing individual atoms in the editor
     */
    public class AtomOptionsContextMenu extends BaseContextMenu {
        private var _targetAtom:Atom;

        /**
         * Constructs an AtomOptionsContextMenu instance
         * @param globalClickPos - global stage coordinates of the click
         * @param targetAtom - atom that the menu operates on
         */
        public function AtomOptionsContextMenu(globalClickPos:Point, targetAtom:Atom) {
            super();
            _targetAtom = targetAtom;

            // Build menu UI
            graphics.beginFill(0x333333, 0.3);
            graphics.drawRect(-5, 0, 160, 60);
            graphics.endFill();

            // Delete item
            var deleteItem:AtomContextMenuItem = new AtomContextMenuItem("delete", "Delete Atom", "Danger");
            deleteItem.y = 5;
            deleteItem.addEventListener(MouseEvent.CLICK, onDeleteClick);
            addChild(deleteItem);

            // Properties item (for future use)
            var propsItem:AtomContextMenuItem = new AtomContextMenuItem("properties", "Properties", "Info");
            propsItem.y = 27;
            propsItem.addEventListener(MouseEvent.CLICK, onPropertiesClick);
            addChild(propsItem);

            // Position menu
            this.x = globalClickPos.x;
            this.y = globalClickPos.y;
        }

        /**
         * Handles delete menu item click
         * Emits impulse to request atom deletion
         */
        private function onDeleteClick(event:MouseEvent):void {
            close();
            MultiPulsator.emit(new Impulse("ATOM_DELETE_REQUEST", {
                atom: _targetAtom
            }));
        }

        /**
         * Handles properties menu item click
         * Emits impulse to request atom properties dialog (future feature)
         */
        private function onPropertiesClick(event:MouseEvent):void {
            close();
            MultiPulsator.emit(new Impulse("ATOM_PROPERTIES_REQUEST", {
                atom: _targetAtom
            }));
        }
    }
}
