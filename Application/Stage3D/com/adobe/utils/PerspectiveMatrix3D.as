package com.adobe.utils {
    import flash.geom.Matrix3D;
    import flash.geom.Vector3D;

    /** Extended Matrix3D for camera and projection matrices */
    public class PerspectiveMatrix3D extends Matrix3D {
        /** Create perspective matrix */
        public function PerspectiveMatrix3D(v:Vector.<Number> = null) {
            super(v);
        }

        /** Set left-handed look-at matrix */
        public function lookAtLH(eye:Vector3D, at:Vector3D, up:Vector3D):void {
            var _z:Vector3D = at.clone();
            _z.subtract(eye);
            _z.normalize();
            _z.w = 0.0;

            var _x:Vector3D = up.clone();
            crossProductTo(_x, _z);
            _x.normalize();
            _x.w = 0.0;

            var _y:Vector3D = _z.clone();
            crossProductTo(_y, _x);
            _y.w = 0.0;

            var _w:Vector3D = new Vector3D(
                _x.dotProduct(eye),
                _y.dotProduct(eye),
                _z.dotProduct(eye),
                1.0
            );

            copyRowFrom(0, _x);
            copyRowFrom(1, _y);
            copyRowFrom(2, _z);
            copyRowFrom(3, _w);
        }

        /** Set right-handed look-at matrix */
        public function lookAtRH(eye:Vector3D, at:Vector3D, up:Vector3D):void {
            var _z:Vector3D = eye.clone();
            _z.subtract(at);
            _z.normalize();
            _z.w = 0.0;

            var _x:Vector3D = up.clone();
            crossProductTo(_x, _z);
            _x.normalize();
            _x.w = 0.0;

            var _y:Vector3D = _z.clone();
            crossProductTo(_y, _x);
            _y.w = 0.0;

            var _w:Vector3D = new Vector3D(
                _x.dotProduct(eye),
                _y.dotProduct(eye),
                _z.dotProduct(eye),
                1.0
            );

            copyRowFrom(0, _x);
            copyRowFrom(1, _y);
            copyRowFrom(2, _z);
            copyRowFrom(3, _w);
        }

        /** Set perspective projection matrix */
        public function perspectiveFieldOfViewRH(fieldOfViewY:Number, aspectRatio:Number, zNear:Number, zFar:Number):void {
            var yScale:Number = 1.0 / Math.tan(fieldOfViewY / 2.0);
            var xScale:Number = yScale / aspectRatio;
            this.copyRawDataFrom(Vector.<Number>([
                xScale, 0.0, 0.0, 0.0,
                0.0, yScale, 0.0, 0.0,
                0.0, 0.0, zFar / (zNear - zFar), -1.0,
                0.0, 0.0, (zNear * zFar) / (zNear - zFar), 0.0
            ]));
        }

        /** Calculate cross product between two vectors */
        private function crossProductTo(a:Vector3D, b:Vector3D):void {
            var w:Vector3D = new Vector3D(
                a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x,
                1.0
            );
            a.copyFrom(w);
        }
    }
}
