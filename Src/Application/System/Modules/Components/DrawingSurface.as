package Src.Application.System.Modules.Components {
    import flash.display.Sprite;
    import flash.display.DisplayObject;
    import flash.utils.getDefinitionByName;

    import Src.Application.System.MultiPulsator.MultiPulsator;
    import Src.Application.System.MultiPulsator.Impulse;

    /**
     * Drawing Surface - canvas for editor graphics
     * Provides drawing surface with background and dynamic elements
     * 
     * Core canvas component for editor with bitmap caching
     * and dynamic element management capabilities
     */
    public class DrawingSurface extends Sprite {
        private var dynamicBackFace:Sprite = new Sprite();
        private var backgroundAsset:Sprite;

        /**
         * Drawing Surface constructor
         */
        public function DrawingSurface() {
            this.cacheAsBitmap = true;
            this.cacheAsBitmapMatrix = null;
            this.mouseEnabled = false;
            init();
        }

        /**
         * Initialize drawing surface
         * Creates background asset and dynamic back face
         */
        private function init():void {
            try {
                var assetClass:Class = getDefinitionByName("drawingSurface") as Class;
                backgroundAsset = new assetClass() as Sprite;
                if (backgroundAsset) {
                    this.addChild(backgroundAsset);
                }
            } catch (e:Error) {
                // Fallback to standard background if asset not found
                backgroundAsset = new Sprite();
                backgroundAsset.graphics.beginFill(0x00ccff, 0.5);
                backgroundAsset.graphics.drawRect(-1000, -500, 2000, 1000);
                backgroundAsset.graphics.endFill();
                this.addChild(backgroundAsset);
            }

            dynamicBackFace.cacheAsBitmap = true;
            dynamicBackFace.mouseEnabled = false;
            dynamicBackFace.name = "CubeBackFace";
            this.addChild(dynamicBackFace);
        }

        /**
         * Add element to drawing surface
         * @param element - display object to add
         * @return DisplayObject - added element
         */
        public function addElement(element:DisplayObject):DisplayObject {
            return dynamicBackFace.addChild(element);
        }

        /**
         * Clear drawing surface
         * Removes all elements from dynamic back face
         */
        public function clear():void {
            while (dynamicBackFace.numChildren > 0) {
                dynamicBackFace.removeChildAt(0);
            }
        }

        /**
         * Remove element from drawing surface
         * @param element - display object to remove
         * @return DisplayObject - removed element
         */
        public function removeElement(element:DisplayObject):DisplayObject {
            if (dynamicBackFace.contains(element)) {
                return dynamicBackFace.removeChild(element);
            }
            return null;
        }

        /**
         * Get dynamic back face sprite
         * @return Sprite - dynamic back face reference
         */
        public function getDynamicBackFace():Sprite {
            return dynamicBackFace;
        }

        /**
         * Update bitmap cache
         * Refreshes bitmap caching for performance
         */
        public function updateCache():void {
            this.cacheAsBitmap = false;
            this.cacheAsBitmap = true;
        }
    }
}
