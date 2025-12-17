package src {
    import flash.display.Sprite;
    import src.ui.LogOutput;
    import src.ui.LoadCombinedFilePanel;
    import flash.text.TextField;
    import flash.filesystem.File; // ДОБАВЛЕНО

    public class ClassSplitterApp extends Sprite {
        private var _log:LogOutput;
        private var _splitterPanel:LoadCombinedFilePanel;

        public function ClassSplitterApp() {
            // Создаём лог
            _log = new LogOutput();
            _log.x = 20;
            _log.y = 150;
            addChild(_log);

            // Создаём панель загрузки
            // Используем папку Root в той же директории
            var appDir:File = File.applicationDirectory;
            var projectRoot:String = appDir.nativePath + File.separator + "Root";
            
            // Создаем папку Root если её нет
            var rootDir:File = new File(projectRoot);
            if (!rootDir.exists) {
                rootDir.createDirectory();
            }
            
            _splitterPanel = new LoadCombinedFilePanel(_log, projectRoot);
            addChild(_splitterPanel);

            // Инструкция
            var info:TextField = new TextField();
            info.width = 600;
            info.height = 200;
            info.x = 450;
            info.y = 20;
            info.multiline = true;
            info.wordWrap = true;
            info.text = "Инструкция:\n" +
                       "1. Нажми кнопку 'Загрузить объединённый файл'\n" +
                       "2. Выбери файл со всеми классами вместе\n" +
                       "3. Программа автоматически:\n" +
                       "   - Создаст папку Root в директории приложения\n" +
                       "   - Создаст все нужные подпапки\n" +
                       "   - Найдёт все package объявления\n" +
                       "   - Извлечёт каждый класс\n" +
                       "   - Сохранит в отдельные файлы по нужным путям\n\n" +
                       "Формат файла должен быть как в очищенном коде,\n" +
                       "где каждый класс начинается с package Src.Prog...\n\n" +
                       "Папка назначения: " + projectRoot;
            addChild(info);
        }
    }
}