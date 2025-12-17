// src/ui/LogOutput.as
package src.ui {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.Event;
    
    public class LogOutput extends Sprite {
        private var _logField:TextField;
        private var _scrollPosition:int = 0;
        
        public function LogOutput() {
            setupUI();
        }
        
        private function setupUI():void {
            // Фон
            graphics.beginFill(0xF0F0F0);
            graphics.drawRect(0, 0, 800, 400);
            graphics.endFill();
            
            // Граница
            graphics.lineStyle(1, 0xCCCCCC);
            graphics.drawRect(0, 0, 800, 400);
            
            // Текстовое поле
            _logField = new TextField();
            _logField.width = 780;
            _logField.height = 380;
            _logField.x = 10;
            _logField.y = 10;
            _logField.multiline = true;
            _logField.wordWrap = true;
            _logField.selectable = true;
            _logField.defaultTextFormat = new TextFormat("Consolas", 11, 0x000000);
            _logField.text = "=== Class Splitter Log ===\n\n";
            
            addChild(_logField);
        }
        
        public function append(text:String):void {
            _logField.appendText(text);
            
            // Автопрокрутка
            _logField.scrollV = _logField.maxScrollV;
        }
        
        public function clear():void {
            _logField.text = "=== Class Splitter Log ===\n\n";
        }
        
        public function get text():String {
            return _logField.text;
        }
    }
}