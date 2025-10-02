package Application.Stage3D {
    import flash.geom.Matrix3D;
    import flash.geom.Vector3D;
    import Application.Stage3D.Quaternion;
    import Application.MultiPulsator.MultiPulsator;
    import Application.MultiPulsator.Impulse;

    /** 
	 * Virtual camera for 3D scene with orbit/free-look modes
	 */
    public class Camera {
        private var _position:Vector3D;
        private var _target:Vector3D;
        private var _orientation:Quaternion;

        private var _fov:Number = Math.PI / 3;
        private var _near:Number = 0.01;
        private var _far:Number = 1000.0;

        private var _yaw:Number = 0;
        private var _pitch:Number = 0;
        private var _roll:Number = 0;
        private var _distance:Number = 10;

        private var _mode:String = "orbit";

        /** Create camera with default orbit mode */
        public function Camera() {
            _position = new Vector3D(0, 0, _distance);
            _target = new Vector3D(0, 0, 50);
            _orientation = new Quaternion();
            updateFromAngles();

            MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                message: "Camera: [INFO] Camera initialized in orbit mode"
            }));
        }

        /** Set camera mode: orbit or free-look */
        public function setMode(mode:String):void {
            if (mode == "orbit" || mode == "free-look") {
                _mode = mode;
                updateFromAngles();

                MultiPulsator.emit(new Impulse("LOG_MESSAGE", {
                    message: "Camera: [INFO] Camera mode changed to: " + _mode
                }));
            }
        }

        /** Get current camera mode */
        public function getMode():String {
            return _mode;
        }

        /** Update camera rotation angles */
        public function updateRotation(deltaYaw:Number, deltaPitch:Number, deltaRoll:Number = 0):void {
            _yaw += deltaYaw;
            _pitch += deltaPitch;
            _roll += deltaRoll;

            // Limit pitch to avoid flip
            var limit:Number = Math.PI / 2 - 0.01;
            _pitch = Math.max(-limit, Math.min(_pitch, limit));

            updateFromAngles();
        }

        /** Update camera zoom distance */
        public function updateZoom(delta:Number):void {
            _distance -= delta * 10.05;
            _distance = Math.max(2, Math.min(_distance, 100));
            updateFromAngles();
        }

        /** Move camera position */
        public function updatePosition(dx:Number = 0, dy:Number = 0, dz:Number = 0):void {
            var forward:Vector3D = getForward();
            var right:Vector3D = getRight();
            var up:Vector3D = getUp();

            var delta:Vector3D = new Vector3D();
            delta.x = right.x * dx + up.x * dy + forward.x * dz;
            delta.y = right.y * dx + up.y * dy + forward.y * dz;
            delta.z = right.z * dx + up.z * dy + forward.z * dz;

            _position.incrementBy(delta);

            if (_mode == "orbit") {
                _target.incrementBy(delta);
            } else {
                updateFromAngles();
            }
        }

        /** Update camera from current angles */
        private function updateFromAngles():void {
            var qYaw:Quaternion = Quaternion.fromAxisAngle(Vector3D.Y_AXIS, _yaw);
            var qPitch:Quaternion = Quaternion.fromAxisAngle(Vector3D.X_AXIS, _pitch);
            var qRoll:Quaternion = Quaternion.fromAxisAngle(Vector3D.Z_AXIS, _roll);

            _orientation = qYaw.multiply(qPitch).multiply(qRoll);
            _orientation.normalize();

            var forward:Vector3D = _orientation.multiplyVectorByQuat(new Vector3D(0, 0, -1));
            var offset:Vector3D;
            if (_mode == "orbit") {
                offset = forward.clone();
                offset.scaleBy(_distance);
                _position = _target.subtract(offset);
            } else {
                offset = forward.clone();
                offset.scaleBy(_distance);
                _target = _position.add(offset);
            }
        }

        /** Get view matrix for rendering */
        public function getViewMatrix():Matrix3D {
            var eye:Vector3D = _position.clone();
            var center:Vector3D = _target.clone();
            var up:Vector3D = new Vector3D(0, 1, 0);

            var z:Vector3D = eye.subtract(center);
            z.normalize();

            var x:Vector3D = up.crossProduct(z);
            x.normalize();

            var y:Vector3D = z.crossProduct(x);
            y.normalize();

            return new Matrix3D(Vector.<Number>([
                x.x, y.x, z.x, 0,
                x.y, y.y, z.y, 0,
                x.z, y.z, z.z, 0,
                -x.dotProduct(eye), -y.dotProduct(eye), -z.dotProduct(eye), 1
            ]));
        }

        /** Get projection matrix for rendering */
        public function getProjectionMatrix(aspect:Number):Matrix3D {
            var yScale:Number = 1 / Math.tan(_fov / 2);
            var xScale:Number = yScale / aspect;

            return new Matrix3D(Vector.<Number>([
                xScale, 0, 0, 0,
                0, yScale, 0, 0,
                0, 0, -(_far + _near) / (_far - _near), -1,
                0, 0, -2 * _far * _near / (_far - _near), 0
            ]));
        }

        /** Get forward direction vector */
        public function getForward():Vector3D {
            return _orientation.multiplyVectorByQuat(new Vector3D(0, 0, -1));
        }

        /** Get right direction vector */
        public function getRight():Vector3D {
            return _orientation.multiplyVectorByQuat(new Vector3D(1, 0, 0));
        }

        /** Get up direction vector */
        public function getUp():Vector3D {
            return _orientation.multiplyVectorByQuat(new Vector3D(0, 1, 0));
        }

        /** Get camera position */
        public function getPosition():Vector3D { return _position.clone(); }
        
        /** Set camera position */
        public function setPosition(pos:Vector3D):void {
            _position = pos.clone();
            updateFromAngles();
        }

        /** Get camera target */
        public function getTarget():Vector3D { return _target.clone(); }
        
        /** Set camera target */
        public function setTarget(tgt:Vector3D):void {
            _target = tgt.clone();
            updateFromAngles();
        }

        /** Get field of view */
        public function getFov():Number { return _fov; }
        
        /** Set field of view */
        public function setFov(fov:Number):void { _fov = fov; }

        /** Get camera distance */
        public function getDistance():Number { return _distance; }
        
        /** Set camera distance */
        public function setDistance(dist:Number):void {
            _distance = dist;
            updateFromAngles();
        }

        /** Get yaw angle */
        public function getYaw():Number { return _yaw; }
        
        /** Get pitch angle */
        public function getPitch():Number { return _pitch; }
        
        /** Get roll angle */
        public function getRoll():Number { return _roll; }
    }
}
