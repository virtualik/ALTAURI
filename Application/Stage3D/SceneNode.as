package Application.Stage3D {
    import flash.display3D.*;
    import flash.geom.Matrix3D;
    import flash.display3D.textures.Texture;

    /**
	 * Base 3D scene object with geometry
	 */
    public class SceneNode {
        public var transform:Matrix3D;
        public var color:uint;
        public var vertexBuffer:VertexBuffer3D;
        public var indexBuffer:IndexBuffer3D;
        public var texture:Texture = null;

        /** Create scene node with geometry */
        public function SceneNode(transform:Matrix3D, color:uint, vb:VertexBuffer3D, ib:IndexBuffer3D, texture:Texture = null) {
            this.transform = transform;
            this.color = color;
            this.vertexBuffer = vb;
            this.indexBuffer = ib;
            this.texture = texture;
        }

        /** Get transform matrix */
        public function getTransform():Matrix3D {
            return transform;
        }

        /** Create cube geometry */
        public static function createCube(context:Context3D, size:Number, color:uint):SceneNode {
            var hs:Number = size * 0.5;

            var vertices:Vector.<Number> = Vector.<Number>([
                -hs, -hs, -hs,
                 hs, -hs, -hs,
                 hs,  hs, -hs,
                -hs,  hs, -hs,
                -hs, -hs,  hs,
                 hs, -hs,  hs,
                 hs,  hs,  hs,
                -hs,  hs,  hs
            ]);

            var indices:Vector.<uint> = Vector.<uint>([
                0, 1, 2, 0, 2, 3,
                4, 6, 5, 4, 7, 6,
                0, 3, 7, 0, 7, 4,
                1, 5, 6, 1, 6, 2,
                0, 4, 5, 0, 5, 1,
                3, 2, 6, 3, 6, 7
            ]);

            var vb:VertexBuffer3D = context.createVertexBuffer(vertices.length / 3, 3);
            vb.uploadFromVector(vertices, 0, vertices.length / 3);

            var ib:IndexBuffer3D = context.createIndexBuffer(indices.length);
            ib.uploadFromVector(indices, 0, indices.length);

            var transform:Matrix3D = new Matrix3D();
            return new SceneNode(transform, color, vb, ib);
        }

        /** Create grid plane geometry */
        public static function createGridPlane(context:Context3D, size:Number, step:Number, texture:Texture, transform:Matrix3D):SceneNode {
            var hs:Number = size / 2;
            var uvScale:Number = size / step;

            var vertices:Vector.<Number> = Vector.<Number>([
                -hs, -hs, 0,  0, uvScale,
                 hs, -hs, 0,  uvScale, uvScale,
                 hs,  hs, 0,  uvScale, 0,
                -hs,  hs, 0,  0, 0
            ]);

            var indices:Vector.<uint> = Vector.<uint>([0, 1, 2, 0, 2, 3]);

            var vb:VertexBuffer3D = context.createVertexBuffer(4, 5);
            vb.uploadFromVector(vertices, 0, 4);

            var ib:IndexBuffer3D = context.createIndexBuffer(6);
            ib.uploadFromVector(indices, 0, 6);

            return new SceneNode(transform, 0xFFFFFF, vb, ib, texture);
        }
    }
}
