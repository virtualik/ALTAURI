package Application.Stage3D {
    import flash.display3D.Context3D;
    import flash.display3D.textures.Texture;
    import flash.display.BitmapData;
    import flash.geom.Matrix3D;
    import flash.geom.Vector3D;
    import flash.display.MovieClip;
	
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /**
	 * Manages 3D scene objects and resources
	 */
    public class SceneManager {
        private var context3D:Context3D;
        private var nodes:Vector.<SceneNode> = new Vector.<SceneNode>();
        private var grids:Vector.<SceneNode> = new Vector.<SceneNode>();
        private var gridTexture:Texture;
        private var sprites:Vector.<Sprite3D> = new Vector.<Sprite3D>();

        /** Create scene manager with 3D context */
        public function SceneManager(context3D:Context3D) {
            this.context3D = context3D;
        }

        /** Initialize basic scene */
        public function initScene():void {
            var centerNode:SceneNode = SceneNode.createCube(context3D, 1, 0xFF0000);
            nodes.push(centerNode);
            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "SceneManager: [INFO] Scene initialized"
            }));

        }

        /** Initialize grid planes */
        public function initGrids(gridClass:Class):void {
            var bmpData:BitmapData = new gridClass(256, 256) as BitmapData;

            var size:int = 1;
            while (size < bmpData.width || size < bmpData.height) {
                size *= 2;
            }
            if (bmpData.width != size || bmpData.height != size) {
                var resized:BitmapData = new BitmapData(size, size, true, 0x00000000);
                resized.draw(bmpData);
                bmpData.dispose();
                bmpData = resized;
				MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
					message: "Grid texture resized to: " + size + "x" + size
				}));

            }

            gridTexture = context3D.createTexture(bmpData.width, bmpData.height, "bgra", false);
            gridTexture.uploadFromBitmapData(bmpData);
            bmpData.dispose();

            var gridSize:Number = 100;
            var step:Number = 10;

            var gridXY:SceneNode = SceneNode.createGridPlane(context3D, gridSize, step, gridTexture, new Matrix3D());
            grids.push(gridXY);

            var matXZ:Matrix3D = new Matrix3D();
            matXZ.appendRotation(90, Vector3D.X_AXIS);
            var gridXZ:SceneNode = SceneNode.createGridPlane(context3D, gridSize, step, gridTexture, matXZ);
            grids.push(gridXZ);

            var matYZ:Matrix3D = new Matrix3D();
            matYZ.appendRotation(90, Vector3D.Y_AXIS);
            var gridYZ:SceneNode = SceneNode.createGridPlane(context3D, gridSize, step, gridTexture, matYZ);
            grids.push(gridYZ);
        }

        /** Add 3D sprite to scene */
        public function addSprite3D(movieClip:MovieClip, width:Number, height:Number):Sprite3D {
            var actualWidth:Number = width > 0 ? width : movieClip.width;
            var actualHeight:Number = height > 0 ? height : movieClip.height;

            var sprite:Sprite3D = new Sprite3D(context3D, movieClip, actualWidth, actualHeight);
            sprites.push(sprite);
            return sprite;
        }

        /** Get all sprites in scene */
        public function getSprites():Vector.<Sprite3D> {
            return sprites;
        }

        /** Update sprite animations */
        public function updateAnimations():void {
            for each (var sprite:Sprite3D in sprites) {
                sprite.updateAnimation();
            }
        }

        /** Add node to scene */
        public function addNode(node:SceneNode):void {
            nodes.push(node);
        }

        /** Get all scene nodes */
        public function getNodes():Vector.<SceneNode> {
            return nodes;
        }

        /** Get all grid nodes */
        public function getGridNodes():Vector.<SceneNode> {
            return grids;
        }

        /** Get 3D context */
        public function getContext3D():Context3D {
            return context3D;
        }

        /** Get grid texture */
        public function getGridTexture():Texture {
            return gridTexture;
        }
    }
}