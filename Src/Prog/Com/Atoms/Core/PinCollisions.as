package Src.Prog.Com.Atoms.Core {
    import flash.geom.Point;
    import Src.Prog.Core.Impulsys.Impulsys;
    import Src.Prog.Core.Impulsys.Impulse;
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.setTimeout;
    import Src.Prog.Core.Windows.Window;

    /**
     * Handles all collision detection and automatic connection management for a single Pin.
     * Enhanced with zoom-independent collision detection and debug visualization.
     *
     * @internal This class is a private component of Pin (composition pattern)
     */
    internal class PinCollisions {

        private var _owner:Pin;
        private var _currentCollisions:Vector.<Pin> = new Vector.<Pin>();
        private var _autoTracks:Vector.<Track> = new Vector.<Track>();
        private var _debugEnabled:Boolean = true; // временно включено для отладки

        public function PinCollisions(owner:Pin) {
            _owner = owner;
        }

        // =========================================================================
        // PUBLIC API
        // =========================================================================

        public function updateCollisionsDuringDrag():void {
            if (!_owner.atom) return;

            var current:Vector.<Pin> = findNearbyPins();
            handleCollisionChanges(current);
        }

        public function forceClearCollisions():void {
            _currentCollisions = new Vector.<Pin>();
        }

        public function cleanupInactiveAutoConnections():void {
            var track:Track;
            var toRemove:Vector.<Track> = new Vector.<Track>();

            for each ( track in _autoTracks) {
                var otherPin:Pin = (_owner.type === Pin.TYPE_OUTPUT) ? track.toPin : track.fromPin;

                if (!otherPin || !otherPin.atom) {
                    toRemove.push(track);
                    continue;
                }

                var thisView:PinView = _owner.findPinViewInternal(_owner);
                var otherView:PinView = _owner.findPinViewInternal(otherPin);

                if (!thisView || !otherView || !arePinsColliding(thisView, otherView)) {
                    toRemove.push(track);
                }
            }

            for each ( track in toRemove) {
                track.dispose();
                removeTrackFromAutoTracks(track);
            }
        }

        public function forceClearAllAutoConnections():void {
            for each (var track:Track in _autoTracks) {
                track.dispose();
            }
            _autoTracks = new Vector.<Track>();
        }

        // =========================================================================
        // ENHANCED COLLISION DETECTION (ZOOM-INDEPENDENT)
        // =========================================================================

        private function findNearbyPins():Vector.<Pin> {
            var nearby:Vector.<Pin> = new Vector.<Pin>();
            var thisView:PinView = _owner.findPinViewInternal(_owner);
            if (!thisView || !thisView.stage) return nearby;

            var allPins:Vector.<Pin> = _owner.getAllPinsInWindowInternal();

            for each (var other:Pin in allPins) {
                if (other === _owner || other.atom === _owner.atom) continue;

                var valid:Boolean = false;
                if (_owner.type === Pin.TYPE_INPUT && other.type === Pin.TYPE_OUTPUT) {
                    valid = _owner.isValidConnection(other, _owner);
                } else if (_owner.type === Pin.TYPE_OUTPUT && other.type === Pin.TYPE_INPUT) {
                    valid = _owner.isValidConnection(_owner, other);
                }
                if (!valid) continue;

                var otherView:PinView = _owner.findPinViewInternal(other);
                if (!otherView) continue;

                if (arePinsColliding(thisView, otherView)) {
                    nearby.push(other);
                }
            }
            return nearby;
        }

        /**
         * Enhanced collision detection using canvas-local coordinates for zoom-independence
         */
        private function arePinsColliding(a:PinView, b:PinView):Boolean {
            if (!a.stage || !b.stage) return false;
            
            // Get parent window for coordinate transformation
            var window:Window = _owner.getParentWindow();
            if (!window || !window.canvas) return false;
            
            var canvas:Sprite = window.canvas;
            
            // Get global positions of pin centers
            var globalA:Point = a.localToGlobal(new Point(0, 0));
            var globalB:Point = b.localToGlobal(new Point(0, 0));
            
            // Convert to canvas-local coordinates (zoom-independent)
            var localA:Point = canvas.globalToLocal(globalA);
            var localB:Point = canvas.globalToLocal(globalB);
            
            // Calculate distance in logical coordinates
            var distance:Number = Point.distance(localA, localB);
            
            // Collision radius = sum of hit area radii (5 + 5 = 10)
            var collisionRadius:Number = 10;
            var isColliding:Boolean = distance <= collisionRadius;
            
            // Debug visualization
            if (_debugEnabled) {
                drawDebugCollision(a, b, distance, isColliding);
            }
            
            return isColliding;
        }

        /**
         * Debug visualization for collision detection
         */
        private function drawDebugCollision(a:PinView, b:PinView, distance:Number, isColliding:Boolean):void {
            var window:Window = _owner.getParentWindow();
            if (!window || !window.overlayLayer) return;
            
            var debugLine:Sprite = new Sprite();
            var posA:Point = a.localToGlobal(new Point(0, 0));
            var posB:Point = b.localToGlobal(new Point(0, 0));
            
            // Draw connection line
            debugLine.graphics.lineStyle(1, isColliding ? 0x00FF00 : 0xFF0000, 0.7);
            debugLine.graphics.moveTo(posA.x, posA.y);
            debugLine.graphics.lineTo(posB.x, posB.y);
            
            // Add distance text
            var tf:TextField = new TextField();
            tf.text = distance.toFixed(1);
            tf.textColor = isColliding ? 0x00FF00 : 0xFF0000;
            tf.x = (posA.x + posB.x) / 2;
            tf.y = (posA.y + posB.y) / 2;
            tf.selectable = false;
            tf.background = true;
            tf.backgroundColor = 0x000000;
            
            var format:TextFormat = new TextFormat();
            format.size = 10;
            format.font = "Consolas";
            tf.setTextFormat(format);
            
            window.overlayLayer.addChild(debugLine);
            window.overlayLayer.addChild(tf);
            
            // Auto-remove after 2 seconds
            setTimeout(function():void {
                if (debugLine.parent) debugLine.parent.removeChild(debugLine);
                if (tf.parent) tf.parent.removeChild(tf);
            }, 2000);
        }

        private function handleCollisionChanges(current:Vector.<Pin>):void {
            for each (var newPin:Pin in current) {
                if (_currentCollisions.indexOf(newPin) === -1) {
                    onCollisionStart(newPin);
                }
            }

            for (var i:int = _currentCollisions.length - 1; i >= 0; i--) {
                var oldPin:Pin = _currentCollisions[i];
                if (current.indexOf(oldPin) === -1) {
                    onCollisionEnd(oldPin);
                }
            }

            _currentCollisions = current;
        }

        private function onCollisionStart(otherPin:Pin):void {
            if (_owner.type === Pin.TYPE_OUTPUT && otherPin.type === Pin.TYPE_INPUT) {
                createAutoConnection(otherPin);
            } else if (_owner.type === Pin.TYPE_INPUT && otherPin.type === Pin.TYPE_OUTPUT) {
                otherPin.createAutoConnection(_owner);
            }

            Impulsys.emit(new Impulse("PIN_COLLISION_STARTED", { pin1: _owner, pin2: otherPin }));
        }

        private function onCollisionEnd(otherPin:Pin):void {
            if (_owner.type === Pin.TYPE_OUTPUT && otherPin.type === Pin.TYPE_INPUT) {
                removeAutoConnection(otherPin);
            } else if (_owner.type === Pin.TYPE_INPUT && otherPin.type === Pin.TYPE_OUTPUT) {
                otherPin.removeAutoConnection(_owner);
            }

            Impulsys.emit(new Impulse("PIN_COLLISION_ENDED", { pin1: _owner, pin2: otherPin }));
        }

        // =========================================================================
        // AUTO-CONNECTION MANAGEMENT
        // =========================================================================

        internal function createAutoConnection(targetPin:Pin):void {
            if (_owner.type !== Pin.TYPE_OUTPUT) return;
            if (!_owner.isValidConnection(_owner, targetPin)) return;
            if (hasExistingConnection(_owner, targetPin)) return;

            try {
                var track:Track = _owner.finalizeTrackCreation(targetPin);
                _autoTracks.push(track);
                Impulsys.emit(new Impulse("AUTO_CONNECTION_CREATED", { fromPin: _owner, toPin: targetPin, track: track }));
            } catch (e:Error) {
                trace("Auto-connection failed: " + e.message);
            }
        }

        internal function removeAutoConnection(targetPin:Pin):void {
            var track:Track = findAutoTrackBetween(_owner, targetPin) ||
                              findAutoTrackBetween(targetPin, _owner);
            if (track) {
                track.dispose();
                removeTrackFromAutoTracks(track);
            }
        }

        private function findAutoTrackBetween(a:Pin, b:Pin):Track {
            for each (var t:Track in _autoTracks) {
                if ((t.fromPin === a && t.toPin === b) || (t.fromPin === b && t.toPin === a)) {
                    return t;
                }
            }
            return null;
        }

        private function removeTrackFromAutoTracks(track:Track):void {
            var i:int = _autoTracks.indexOf(track);
            if (i !== -1) _autoTracks.splice(i, 1);
        }

        private function hasExistingConnection(fromPin:Pin, toPin:Pin):Boolean {
            var reg:TrackRegistry = TrackRegistry.getInstance();
            if (!reg) return false;

            var tracks:Vector.<Track> = reg.getTracksByPin(toPin);
            for each (var t:Track in tracks) {
                if (t.fromPin === fromPin && t.toPin === toPin) return true;
            }
            return false;
        }

        // =========================================================================
        // PUBLIC ACCESSORS
        // =========================================================================

        public function get collidingPins():Vector.<Pin> { return _currentCollisions.concat(); }
        public function get autoTracks():Vector.<Track> { return _autoTracks.concat(); }
    }
}