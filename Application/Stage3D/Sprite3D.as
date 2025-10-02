package Application.Stage3D {
    import flash.display.MovieClip;
    import flash.display3D.Context3D;
    import flash.display3D.VertexBuffer3D;
    import flash.display3D.IndexBuffer3D;
    import flash.display3D.textures.Texture;
    import flash.geom.Matrix3D;
    import flash.display.BitmapData;
    import flash.geom.Matrix;
    import flash.geom.Rectangle;

    /**
	 * 3D sprite with animated texture from MovieClip
	 */
    public class Sprite3D extends SceneNode {
        private var _movieClip:MovieClip;
        private var _texture:Texture;
        private var _bitmapData:BitmapData;
        private var _width:Number;
        private var _height:Number;
        private var _textureWidth:int;
        private var _textureHeight:int;
        private var _context3D:Context3D;

        /** Create 3D sprite from MovieClip */
        public function Sprite3D(context3D:Context3D, movieClip:MovieClip, width:Number, height:Number) {
            super(new Matrix3D(), 0xFFFFFF, null, null, null);

            this._context3D = context3D;
            this._movieClip = movieClip;
            this._width = width;
            this._height = height;

            _textureWidth = getNextPowerOfTwo(width);
            _textureHeight = getNextPowerOfTwo(height);

            trace("Sprite3D: Original size: " + width + "x" + height + ", Texture size: " + _textureWidth + "x" + _textureHeight);

            _bitmapData = new BitmapData(_textureWidth, _textureHeight, true, 0x00000000);
            _texture = context3D.createTexture(_textureWidth, _textureHeight, "bgra", false);

            createGeometry();
            updateTexture();
            texture = _texture;
        }

        /** Get next power of two for texture size */
        private function getNextPowerOfTwo(value:Number):int {
            var result:int = 2;
            while (result < value) {
                result *= 2;
            }
            return Math.min(result, 2048);
        }

        /** Create sprite geometry */
        private function createGeometry():void {
            var hw:Number = _width / 2;
            var hh:Number = _height / 2;

            var uScale:Number = _width / _textureWidth;
            var vScale:Number = _height / _textureHeight;

            var vertices:Vector.<Number> = Vector.<Number>([
                -hw, -hh, 0,  0, vScale,
                 hw, -hh, 0,  uScale, vScale,
                 hw,  hh, 0,  uScale, 0,
                -hw,  hh, 0,  0, 0
            ]);

            var indices:Vector.<uint> = Vector.<uint>([0, 1, 2, 0, 2, 3]);

            vertexBuffer = _context3D.createVertexBuffer(4, 5);
            vertexBuffer.uploadFromVector(vertices, 0, 4);

            indexBuffer = _context3D.createIndexBuffer(6);
            indexBuffer.uploadFromVector(indices, 0, 6);
        }

        /** Update texture from MovieClip */
        public function updateTexture():void {
            _bitmapData.fillRect(_bitmapData.rect, 0x00000000);
            var matrix:Matrix = new Matrix();
            matrix.translate((_textureWidth - _width) / 2, (_textureHeight - _height) / 2);
            _bitmapData.draw(_movieClip, matrix);
            _texture.uploadFromBitmapData(_bitmapData);
        }

        /** Update animation frame */
        public function updateAnimation():void {
            updateTexture();
        }

        /** Get transform matrix */
        override public function getTransform():Matrix3D {
            return transform;
        }

        /** Clean up resources */
        public function dispose():void {
            if (_texture) _texture.dispose();
            if (_bitmapData) _bitmapData.dispose();
            if (vertexBuffer) vertexBuffer.dispose();
            if (indexBuffer) indexBuffer.dispose();
        }

        /** Get sprite width */
        public function get width():Number { return _width; }
        
        /** Get sprite height */
        public function get height():Number { return _height; }
        
        /** Get texture width */
        public function get textureWidth():int { return _textureWidth; }
        
        /** Get texture height */
        public function get textureHeight():int { return _textureHeight; }
    }
}
