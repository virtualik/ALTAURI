package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;

    /**
     * Temporary track for drag operations
     */
    public class TempTrack extends Sprite {
        private var _startPos:Point;
        
        public function TempTrack(startPos:Point) {
            _startPos = startPos;
            super();
        }
        
        public function update(currentPos:Point):void {
            this.graphics.clear();
            this.graphics.lineStyle(2, 0x00FF00, 0.8);
            this.graphics.moveTo(_startPos.x, _startPos.y);
            this.graphics.lineTo(currentPos.x, currentPos.y);
        }
        
        public function get startPos():Point {
            return _startPos;
        }
    }
}
