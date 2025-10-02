package Application.Stage3D {
    import flash.geom.Vector3D;

    /**
     * Quaternion for 3D rotations
     * Avoids gimbal lock in camera system
     */
    public class Quaternion {
        public var x:Number;
        public var y:Number;
        public var z:Number;
        public var w:Number;

        /** Create quaternion with components */
        public function Quaternion(x:Number = 0, y:Number = 0, z:Number = 0, w:Number = 1) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.w = w;
        }

        /** Normalize quaternion to unit length */
        public function normalize():void {
            var magnitude:Number = Math.sqrt(x * x + y * y + z * z + w * w);
            if (magnitude > 0) {
                x /= magnitude;
                y /= magnitude;
                z /= magnitude;
                w /= magnitude;
            }
        }

        /** Multiply this quaternion by another */
        public function multiply(other:Quaternion):Quaternion {
            var q:Quaternion = new Quaternion();
            q.w = w * other.w - x * other.x - y * other.y - z * other.z;
            q.x = w * other.x + x * other.w + y * other.z - z * other.y;
            q.y = w * other.y - x * other.z + y * other.w + z * other.x;
            q.z = w * other.z + x * other.y - y * other.x + z * other.w;
            return q;
        }

        /** Create quaternion from axis and angle */
        public static function fromAxisAngle(axis:Vector3D, angle:Number):Quaternion {
            var q:Quaternion = new Quaternion();
            var sin:Number = Math.sin(angle / 2);
            q.x = axis.x * sin;
            q.y = axis.y * sin;
            q.z = axis.z * sin;
            q.w = Math.cos(angle / 2);
            q.normalize();
            return q;
        }

        /** Multiply vector by this quaternion */
        public function multiplyVectorByQuat(v:Vector3D):Vector3D {
            var qVec:Vector3D = new Vector3D(x, y, z);
            var uv:Vector3D = qVec.crossProduct(v);
            var uuv:Vector3D = qVec.crossProduct(uv);

            uv.scaleBy(2.0 * w);
            uuv.scaleBy(2.0);

            return new Vector3D(
                v.x + uv.x + uuv.x,
                v.y + uv.y + uuv.y,
                v.z + uv.z + uuv.z
            );
        }

        /** Create copy of this quaternion */
        public function clone():Quaternion {
            return new Quaternion(x, y, z, w);
        }

        /** Convert to string representation */
        public function toString():String {
            return "[Quaternion x=" + x + " y=" + y + " z=" + z + " w=" + w + "]";
        }
    }
}