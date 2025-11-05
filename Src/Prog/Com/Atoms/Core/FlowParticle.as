package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;

    /**
     * Individual particle for data flow animation.
     * Represents a single unit of data moving along a track.
     *
     * @class FlowParticle
     * @extends Sprite
     * @public
     */
    public class FlowParticle extends Sprite {
        
        /** Start position of the particle */
        private var _startPos:Point;
        
        /** End position of the particle */
        private var _endPos:Point;
        
        /** Current animation progress (0 to 1) */
        private var _progress:Number;
        
        /** Animation speed multiplier */
        private var _speed:Number;
        
        /** Particle color based on data type */
        private var _color:uint;
        
        /** Completion state flag */
        private var _isComplete:Boolean;

        /**
         * Initializes the particle with animation parameters.
         *
         * @public
         * @param {Point} startPos - Starting position
         * @param {Point} endPos - Ending position
         * @param {uint} color - Particle color
         * @param {Number} delay - Animation delay in seconds
         */
        public function initialize(startPos:Point, endPos:Point, color:uint, delay:Number = 0):void {
            _startPos = startPos;
            _endPos = endPos;
            _color = color;
            _progress = -delay; // Negative progress for delayed start
            _speed = 3; // Base animation speed
            _isComplete = false;
            
            draw();
        }

        /**
         * Draws the visual representation of the particle.
         *
         * @private
         */
        private function draw():void {
            this.graphics.clear();
            this.graphics.beginFill(_color, 1.0);
            this.graphics.drawCircle(0, 0, 2);
            this.graphics.endFill();
        }

        /**
         * Updates the particle position and animation state.
         *
         * @public
         */
        public function update():void {
            if (_isComplete) return;
            
            _progress += 0.016 * _speed; // Assuming 60fps
            
            if (_progress < 0) {
                // Still in delay phase
                return;
            }
            
            if (_progress >= 1) {
                // Animation complete
                _progress = 1;
                _isComplete = true;
            }
            
            // Calculate current position using linear interpolation
            var currentX:Number = _startPos.x + (_endPos.x - _startPos.x) * _progress;
            var currentY:Number = _startPos.y + (_endPos.y - _startPos.y) * _progress;
            
            this.x = currentX;
            this.y = currentY;
            
            // Optional: Add scale or alpha effects
            this.scaleX = this.scaleY = 1 + Math.sin(_progress * Math.PI) * 0.5;
            this.alpha = 1 - (_progress * 0.5); // Fade out towards end
        }

        /**
         * Checks if the particle animation is complete.
         *
         * @public
         * @return {Boolean} True if animation is finished
         */
        public function get isComplete():Boolean {
            return _isComplete;
        }
    }
}
