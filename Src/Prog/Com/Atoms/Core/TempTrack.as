package Src.Prog.Com.Atoms.Core {
    import flash.display.Sprite;
    import flash.geom.Point;

    public class TempTrack extends Sprite {
        private var _startPos:Point;
		public var searchingForInput:Boolean = false;
		public var searchingForOutput:Boolean = false;
		
        public function TempTrack(startPos:Point) {
            _startPos = startPos;
            super();
			
			// Убедимся, что TempTrack не блокирует события
			this.mouseEnabled = true;
			this.mouseChildren = false;
			this.tabEnabled = false;
			this.tabChildren = false;
        }

        public function update(currentPos:Point):void {
            this.graphics.clear();
            this.graphics.lineStyle(3, searchingForInput ? 0x00AAFF : 0xFFAA00, 0.8);
            this.graphics.moveTo(_startPos.x, _startPos.y);
            this.graphics.lineTo(currentPos.x, currentPos.y);
        }

        public function get startPos():Point {
            return _startPos;
        }
    }
}
