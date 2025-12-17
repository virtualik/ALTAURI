// src/ui/LoadCombinedFilePanel.as
package src.ui {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;
    import flash.events.Event;
    import src.parsers.ClassSplitter;
    import flash.net.FileFilter;
    
    public class LoadCombinedFilePanel extends Sprite {
        private var _log:LogOutput;
        private var _splitter:ClassSplitter;
        private var _loadBtn:Sprite;
        private var _statusText:TextField;
        
        public function LoadCombinedFilePanel(log:LogOutput, projectRoot:String) {
            _log = log;
            _splitter = new ClassSplitter(log, projectRoot);
            setupUI();
        }
        
        private function setupUI():void {
            // Кнопка загрузки
            _loadBtn = createButton("📁 Загрузить объединённый файл", 0xFF9900);
            _loadBtn.x = 20;
            _loadBtn.y = 20;
            _loadBtn.addEventListener(MouseEvent.CLICK, onLoadClicked);
            addChild(_loadBtn);
            
            // Статус
            _statusText = new TextField();
            _statusText.width = 400;
            _statusText.height = 60;
            _statusText.x = 20;
            _statusText.y = 70;
            _statusText.defaultTextFormat = new TextFormat("Arial", 12, 0x333333);
            _statusText.text = "Выберите файл с объединёнными классами";
            addChild(_statusText);
        }
        
        private function createButton(label:String, color:uint):Sprite {
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(color);
            btn.graphics.drawRoundRect(0, 0, 250, 40, 10, 10);
            btn.graphics.endFill();
            
            var tf:TextField = new TextField();
            tf.text = label;
            tf.width = 250;
            tf.height = 40;
            tf.selectable = false;
            tf.y = 10;
            var fmt:TextFormat = new TextFormat("Arial", 14, 0xFFFFFF);
            fmt.align = "center";
            tf.setTextFormat(fmt);
            tf.defaultTextFormat = fmt;
            
            btn.addChild(tf);
            btn.buttonMode = true;
            btn.useHandCursor = true;
            
            return btn;
        }
        
        private function onLoadClicked(event:MouseEvent):void {
            var file:File = new File();
            file.addEventListener(Event.SELECT, onFileSelected);
            file.browse([new FileFilter("ActionScript files", "*.as;*.txt")]);
        }
        
        private function onFileSelected(event:Event):void {
            var file:File = event.target as File;
            _statusText.text = "Загружаю: " + file.name;
            
            try {
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.READ);
                var content:String = stream.readUTFBytes(stream.bytesAvailable);
                stream.close();
                
                _log.append("📄 Загружен файл: " + file.nativePath + 
                           " (" + content.length + " символов)\n");
                
                // Запускаем разбор и сохранение
                _splitter.splitAndSave(content, function(success:Boolean):void {
                    _statusText.text = success ? 
                        "✅ Файлы успешно сохранены!" : 
                        "❌ Ошибка при сохранении файлов";
                });
                
            } catch (error:Error) {
                _log.append("❌ Ошибка при загрузке файла: " + error.message + "\n");
                _statusText.text = "Ошибка: " + error.message;
            }
        }
    }
}