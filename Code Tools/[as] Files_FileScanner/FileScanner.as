package {
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import fl.controls.TextArea;
    import flash.errors.IOError;

    /**
     * СКАНЕР ФАЙЛОВ - КЛАСС ДЛЯ ОБРАБОТКИ И ЧТЕНИЯ .AS ФАЙЛОВ
     *
     * Расширенная версия с поддержкой выбора конкретных классов
     */
    public class FileScanner {
        // Константы для расширений файлов
        private static const AS_EXTENSION:String = "as";
        private static const FILE_SEPARATOR:String = " ";

        private var textArea:TextArea;
        private var outputText:String;
        private var processedFilesCount:int;
        private var classListCache:Array; // ДОБАВЛЕНО: кэш списка классов

        /**
         * КОНСТРУКТОР СКАНЕРА
         */
        public function FileScanner(textArea:TextArea) {
            this.textArea = textArea;
            this.outputText = "";
            this.processedFilesCount = 0;
            this.classListCache = []; // ИНИЦИАЛИЗАЦИЯ кэша
        }

        /**
         * ПОЛУЧЕНИЕ СПИСКА ВСЕХ .AS ФАЙЛОВ В ДИРЕКТОРИИ
         */
        public function getClassList(directoryPath:String):Array {
            resetScanState();
            classListCache = [];

            var directory:File = new File(directoryPath);

            if (isValidDirectory(directory)) {
                scanForClassFiles(directory);
            }

            return classListCache;
        }

        /**
         * РЕКУРСИВНЫЙ ПОИСК .AS ФАЙЛОВ ДЛЯ СПИСКА
         */
        private function scanForClassFiles(directory:File):void {
            try {
                var files:Array = directory.getDirectoryListing();

                for each (var file:File in files) {
                    if (file.isDirectory) {
                        // Рекурсивно сканируем подпапки
                        scanForClassFiles(file);
                    } else if (isActionScriptFile(file)) {
                        // Добавляем .as файлы в список
                        classListCache.push(file.nativePath);
                    }
                }
            } catch (error:Error) {
                // Игнорируем ошибки доступа при сканировании для списка
                trace("Ошибка доступа к директории при сканировании для списка: " + directory.nativePath);
            }
        }

        /**
         * СОЗДАНИЕ ФАЙЛА ТОЛЬКО ИЗ ВЫБРАННЫХ КЛАССОВ
         */
        public function createFileFromSelectedClasses(directoryPath:String, selectedClasses:Array):void {
            resetScanState();

            var directory:File = new File(directoryPath);

            if (!isValidDirectory(directory)) {
                outputText = "Ошибка: Указанный путь не существует или не является папкой.";
                updateTextArea();
                return;
            }

            try {
                // Обрабатываем только выбранные классы
                for each (var classPath:String in selectedClasses) {
                    var file:File = new File(classPath);
                    if (file.exists && isActionScriptFile(file)) {
                        readAndProcessFile(file);
                    }
                }

                addScanSummary();
                updateTextArea();
            } catch (error:Error) {
                outputText = "Критическая ошибка при обработке: " + error.message;
                updateTextArea();
            }
        }

        /**
         * СБРОС СОСТОЯНИЯ ПЕРЕД НОВЫМ СКАНИРОВАНИЕМ
         */
        private function resetScanState():void {
            outputText = "";
            processedFilesCount = 0;
        }

        /**
         * ПРОВЕРКА ВАЛИДНОСТИ ДИРЕКТОРИИ
         */
        private function isValidDirectory(directory:File):Boolean {
            return directory.exists && directory.isDirectory;
        }

        /**
         * ПРОВЕРКА НА ACTIONSCRIPT ФАЙЛ
         */
        private function isActionScriptFile(file:File):Boolean {
            return file.extension && file.extension.toLowerCase() === AS_EXTENSION;
        }

        /**
         * ЧТЕНИЕ И ОБРАБОТКА ФАЙЛА
         */
        private function readAndProcessFile(file:File):void {
            try {
                var fileContent:String = readFileContent(file);

                if (fileContent !== null) {
                    appendFileToOutput(file, fileContent);
                    processedFilesCount++;
                }
            } catch (error:Error) {
                appendErrorToOutput(file, error.message);
            }
        }

        /**
         * ЧТЕНИЕ СОДЕРЖИМОГО ФАЙЛА
         */
        private function readFileContent(file:File):String {
            var stream:FileStream = null;
            var content:String = null;

            try {
                stream = new FileStream();
                stream.open(file, FileMode.READ);
                content = stream.readUTFBytes(stream.bytesAvailable);

                // Нормализуем переносы строк
                content = normalizeLineBreaks(content);

            } catch (error:Error) {
                content = null;
            } finally {
                if (stream) {
                    try {
                        stream.close();
                    } catch (closeError:Error) {
                        // Игнорируем ошибки закрытия
                    }
                }
            }

            return content;
        }

        /**
         * НОРМАЛИЗАЦИЯ ПЕРЕНОСОВ СТРОК
         */
        private function normalizeLineBreaks(content:String):String {
            if (!content) return "";

            content = content.replace(/\r\n/g, "\n");
            content = content.replace(/\r/g, "\n");
            content = content.replace(/\n{3,}/g, "\n\n");
            content = content.replace(/[ \t]+\n/g, "\n");
            content = content.replace(/^\s+|\s+$/g, "");

            return content;
        }

        /**
         * ДОБАВЛЕНИЕ ИНФОРМАЦИИ О ФАЙЛЕ В ВЫВОД
         */
        private function appendFileToOutput(file:File, content:String):void {
            outputText += content;

            if (!content.match(/\n$/)) {
                outputText += "\n";
            }

            outputText += FILE_SEPARATOR + "\n";
        }

        /**
         * ДОБАВЛЕНИЕ ИНФОРМАЦИИ ОБ ОШИБКЕ В ВЫВОД
         */
        private function appendErrorToOutput(file:File, errorMessage:String):void {
            outputText += "Ошибка чтения файла: " + file.nativePath + " (" + errorMessage + ")\n";
            outputText += FILE_SEPARATOR + "\n";
        }

        /**
         * ДОБАВЛЕНИЕ СВОДКИ СКАНИРОВАНИЯ
         */
        private function addScanSummary():void {
            if (processedFilesCount > 0) {
                outputText += "Всего файлов/классов: " + processedFilesCount + "\n";
            } else {
                outputText += "\n=== ФАЙЛЫ НЕ НАЙДЕНЫ ===\n";
                outputText += "Не удалось обработать выбранные файлы\n";
            }
        }

        /**
         * ОБНОВЛЕНИЕ ТЕКСТОВОГО ПОЛЯ
         */
        private function updateTextArea():void {
            if (textArea) {
                textArea.text = outputText;
                textArea.verticalScrollPosition = 0;
            }
        }

        /**
         * ПОЛУЧЕНИЕ КОЛИЧЕСТВА ОБРАБОТАННЫХ ФАЙЛОВ
         */
        public function get processedFiles():int {
            return processedFilesCount;
        }

        /**
         * ОЧИСТКА РЕЗУЛЬТАТОВ
         */
        public function clear():void {
            resetScanState();
            classListCache = [];
            updateTextArea();
        }

        /**
         * СТАРЫЙ МЕТОД ДЛЯ ОБРАТНОЙ СОВМЕСТИМОСТИ
         */
        public function scanDirectory(directoryPath:String):void {
            // Для обратной совместимости - создаем файл из всех классов
            var allClasses:Array = getClassList(directoryPath);
            createFileFromSelectedClasses(directoryPath, allClasses);
        }
    }
}