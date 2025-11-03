package Src.Prog.Com.Menus {
    import flash.geom.Point;
    import flash.events.MouseEvent;
    import Src.Prog.Core.MultiPulsator.MultiPulsator;
    import Src.Prog.Core.MultiPulsator.Impulse;
    import Src.Prog.Com.Atoms.Data.AtomDefinitions;
    import Src.Prog.Com.Atoms.Core.AtomFactory;

    /**
     * Context menu for creating atoms - uses only registered atom definitions
     */
    public class AtomCreationContextMenu extends BaseContextMenu {
        private var _clickPosition:Point;

        public function AtomCreationContextMenu(localClickPos:Point, canvasPos:Point) {
            super();
            _clickPosition = canvasPos;
            this.x = localClickPos.x;
            this.y = localClickPos.y;
            
            buildMenuFromDefinitions();
        }

        /**
         * Build menu from AtomDefinitions
         */
        private function buildMenuFromDefinitions():void {
            var atomTypes:Array = getOrganizedAtomTypes();
            
            trace("AtomCreationContextMenu: Building menu with " + atomTypes.length + " registered atom types");

            // Calculate menu size
            var menuHeight:Number = 5 + 20 * atomTypes.length;
            var menuWidth:Number = 180; // Wider to accommodate categories

            // Draw menu background
            graphics.beginFill(0x333333, 0.95);
            graphics.lineStyle(1, 0x666666);
            graphics.drawRect(0, 0, menuWidth, menuHeight);
            graphics.endFill();

            var y:Number = 5;
            var currentCategory:String = "";

            // Create menu items organized by category
            for (var i:int = 0; i < atomTypes.length; i++) {
                var atomType:Object = atomTypes[i];
                
                // Add category separator if category changed
                if (atomType.category != currentCategory) {
                    if (currentCategory != "") {
                        y += 2; // Space before next category
                    }
                    currentCategory = atomType.category;
                }

                var item:AtomContextMenuItem = new AtomContextMenuItem(
                    atomType.type,
                    atomType.name,
                    atomType.category
                );
                item.y = y;
                item.width = menuWidth - 10;
                item.addEventListener(MouseEvent.CLICK, createItemClickHandler(atomType.type));
                addChild(item);
                
                y += 20;
            }

            trace("AtomCreationContextMenu: Menu built successfully");
        }

        /**
         * Get atom types organized by category
         */
        private function getOrganizedAtomTypes():Array {
            var result:Array = [];
            
            try {
                // Get all registered types
                var supportedTypes:Array = AtomDefinitions.getSupportedTypes();
                
                for each (var atomType:String in supportedTypes) {
                    var definition:Object = AtomDefinitions.getAtomDefinition(atomType);
                    if (definition) {
                        result.push({
                            type: atomType,
                            name: definition.displayName || atomType,
                            category: definition.category || "General"
                        });
                    }
                }
                
                // Sort by category and then by name
                result.sortOn(["category", "name"]);
                
            } catch (error:Error) {
                trace("ERROR: Failed to get atom types from definitions: " + error.message);
                result = getFallbackTypes();
            }
            
            return result;
        }

        /**
         * Fallback types if definitions are unavailable
         */
        private function getFallbackTypes():Array {
            trace("WARNING: Using fallback atom types");
            return [
                {type: "Button", name: "Button", category: "Input"},
                {type: "Counter", name: "Counter", category: "Logic"},
                {type: "NumberDisplay", name: "Number Display", category: "Output"}
            ];
        }

        /**
         * Create click handler for menu item
         */
        private function createItemClickHandler(atomType:String):Function {
            return function(event:MouseEvent):void {
                var item:AtomContextMenuItem = event.currentTarget as AtomContextMenuItem;
                trace("AtomCreationContextMenu: Selected - " + atomType + " at " + _clickPosition);
                
                // Validate atom type before creating
                if (!AtomFactory.canCreateAtom(atomType)) {
                    trace("ERROR: Cannot create invalid atom type: " + atomType);
                    close();
                    return;
                }
                
                close();
                
                MultiPulsator.emit(new Impulse("ATOM_CONTEXT_MENU_SELECTED", {
                    atomType: atomType,
                    position: _clickPosition,
                    source: "AtomCreationContextMenu"
                }));
            };
        }

        /**
         * Debug menu contents
         */
        public function debugMenuContents():void {
            trace("=== MENU CONTENTS ===");
            var atomTypes:Array = getOrganizedAtomTypes();
            for each (var atomType:Object in atomTypes) {
                trace(" - " + atomType.category + " / " + atomType.name + " (" + atomType.type + ")");
            }
            trace("=== END MENU CONTENTS ===");
        }
    }
}
