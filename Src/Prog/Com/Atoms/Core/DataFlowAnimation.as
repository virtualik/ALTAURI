package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.events.Event;

    /**
     * Visual animation system for data flow visualization along tracks.
     * Creates particle effects and animations to show data movement between pins.
     *
     * @class DataFlowAnimation
     * @extends Sprite
     * @public
     */
    public class DataFlowAnimation extends Sprite {
        
        /** Collection of active flow particles */
        private var _particles:Array;
        
        /** Animation state flag */
        private var _isAnimating:Boolean = false;
        
        /** Reference to track manager for coordinate calculations */
        private var _trackManager:TrackManager;

        /**
         * Creates a new DataFlowAnimation instance.
         */
        public function DataFlowAnimation() {
            _particles = [];
            this.mouseEnabled = false;
            this.mouseChildren = false;
            _trackManager = TrackManager.getInstance();
        }

        /**
         * Starts the data flow animation between two pins.
         * Creates visual particles moving from source to target.
         *
         * @public
         * @param {Pin} fromPin - Source pin (output)
         * @param {Pin} toPin - Target pin (input)
         * @param {*} value - Data value for particle styling
         */
        public function animate(fromPin:Pin, toPin:Pin, value:*):void {
            _isAnimating = true;
            clearParticles();
            
            // Get global pin positions
            var fromPos:Point = _trackManager.getGlobalPinPosition(fromPin);
            var toPos:Point = _trackManager.getGlobalPinPosition(toPin);
            
            // Convert to local coordinates
            var localFrom:Point = this.parent.globalToLocal(fromPos);
            var localTo:Point = this.parent.globalToLocal(toPos);

            // Create particles based on value type
            createParticles(localFrom, localTo, value);
            
            // Start animation loop
            this.addEventListener(Event.ENTER_FRAME, updateAnimation);
        }

        /**
         * Creates visual particles for the data flow animation.
         * Particle count and color are determined by data value type.
         *
         * @private
         * @param {Point} fromPos - Start position in local coordinates
         * @param {Point} toPos - End position in local coordinates
         * @param {*} value - Data value for styling
         */
        private function createParticles(fromPos:Point, toPos:Point, value:*):void {
            var particleCount:int = getParticleCount(value);
            var color:uint = getParticleColor(value);
            
            for (var i:int = 0; i < particleCount; i++) {
                var particle:FlowParticle = new FlowParticle();
                particle.initialize(fromPos, toPos, color, i * 0.3);
                _particles.push(particle);
                this.addChild(particle);
            }
        }

        /**
         * Updates the animation frame for all active particles.
         *
         * @private
         * @param {Event} event - ENTER_FRAME event
         */
        private function updateAnimation(event:Event):void {
            var activeParticles:int = 0;
            
            for (var i:int = _particles.length - 1; i >= 0; i--) {
                var particle:FlowParticle = _particles[i];
                
                if (particle.isComplete) {
                    this.removeChild(particle);
                    _particles.splice(i, 1);
                } else {
                    particle.update();
                    activeParticles++;
                }
            }
            
            // Stop animation when all particles are complete
            if (activeParticles === 0) {
                this.removeEventListener(Event.ENTER_FRAME, updateAnimation);
                _isAnimating = false;
            }
        }

        /**
         * Determines the number of particles based on data value type.
         *
         * @private
         * @param {*} value - Data value to analyze
         * @return {int} Number of particles to create
         */
        private function getParticleCount(value:*):int {
            if (value === true || value === false) return 1;
            if (typeof value == "number") return Math.min(3, Math.abs(value));
            return 2;
        }

        /**
         * Determines particle color based on data value type.
         *
         * @private
         * @param {*} value - Data value to analyze
         * @return {uint} Particle color value
         */
        private function getParticleColor(value:*):uint {
            if (value === true) return 0xFFFFCC;    // Green for true
            if (value === false) return 0xFF0000;   // Red for false
            if (typeof value == "number") return 0x0088FF; // Blue for numbers
            return 0xFFFFFF; // White for other types
        }

        /**
         * Clears all active particles from the animation.
         *
         * @private
         */
        private function clearParticles():void {
            for each (var particle:FlowParticle in _particles) {
                if (this.contains(particle)) {
                    this.removeChild(particle);
                }
            }
            _particles = [];
        }

        /**
         * Cleans up animation resources and stops all activity.
         *
         * @public
         */
        public function dispose():void {
            _isAnimating = false;
            this.removeEventListener(Event.ENTER_FRAME, updateAnimation);
            clearParticles();
            _trackManager = null;
        }

        /**
         * Checks if animation is currently running.
         *
         * @public
         * @return {Boolean} True if animation is active
         */
        public function get isAnimating():Boolean {
            return _isAnimating;
        }
    }
}
