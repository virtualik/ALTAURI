package Application.Stage3D {
    import flash.geom.Matrix3D;
    import flash.geom.Vector3D;
    import flash.display3D.Context3D;
    import flash.display.MovieClip;

    /** 3D sprite that always faces camera */
    public class BillboardSprite3D extends Sprite3D {
        private var _camera:Camera;

        /** Create billboard sprite with camera reference */
        public function BillboardSprite3D(context3D:Context3D, movieClip:MovieClip, width:Number, height:Number, camera:Camera) {
            super(context3D, movieClip, width, height);
            this._camera = camera;
        }

        /** Get transform matrix always facing camera */
        override public function getTransform():Matrix3D {
            var billboardMatrix:Matrix3D = transform.clone();

            // Get direction from sprite to camera
            var toCamera:Vector3D = _camera.getPosition().subtract(transform.position);
            toCamera.normalize();

            // Create orientation matrix
            var up:Vector3D = new Vector3D(0, 1, 0);
            var right:Vector3D = up.crossProduct(toCamera);
            right.normalize();
            up = toCamera.crossProduct(right);
            up.normalize();

            // Set orientation
            billboardMatrix.copyRowFrom(0, right);
            billboardMatrix.copyRowFrom(1, up);
            billboardMatrix.copyRowFrom(2, toCamera);

            return billboardMatrix;
        }
    }
}
