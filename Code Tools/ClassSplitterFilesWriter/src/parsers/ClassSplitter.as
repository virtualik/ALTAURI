package src.parsers {
    import src.core.FileManager;
    import src.ui.LogOutput;
    import flash.utils.setTimeout;
    import flash.filesystem.File;

    public class ClassSplitter {
        private var _log:LogOutput;
        private var _fileManager:FileManager;
        private var _projectRoot:String;

        public function ClassSplitter(log:LogOutput, projectRoot:String) {
            _log = log;
            _projectRoot = projectRoot;
            _fileManager = new FileManager(projectRoot);
        }

        public function splitAndSave(combinedContent:String, callback:Function):void {
            _log.append("🔍 Начинаю разбор объединённого файла...\n");
            
            try {
                // Находим все package объявления
                var packages:Array = extractPackages(combinedContent);
                
                if (packages.length == 0) {
                    _log.append("❌ Не найдено ни одного package объявления\n");
                    callback(false);
                    return;
                }
                
                _log.append("✅ Найдено " + packages.length + " классов\n");
                
                // Логируем первые 3 пакета для отладки
                for (var i:int = 0; i < Math.min(packages.length, 3); i++) {
                    var pkg:Object = packages[i];
                    _log.append("Package " + i + ": " + 
                               (pkg.className || "нет имени") + " -> " + 
                               (pkg.filePath || "нет пути") + "\n");
                }
                
                // Сначала создаем все папки
                createFoldersForPackages(packages);
                
                // Затем сохраняем файлы
                savePackages(packages, 0, callback);
                
            } catch (error:Error) {
                _log.append("❌ ОШИБКА в splitAndSave: " + error.message + "\n");
                callback(false);
            }
        }
        
        private function createFoldersForPackages(packages:Array):void {
            var folders:Object = {};
            
            for each (var pkg:Object in packages) {
                if (pkg.filePath) {
                    var folderPath:String = getFolderPath(pkg.filePath);
                    if (folderPath && !folders[folderPath]) {
                        folders[folderPath] = true;
                        createDirectory(folderPath);
                    }
                }
            }
        }
        
        private function getFolderPath(filePath:String):String {
            if (!filePath) return "";
            var lastSlash:int = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
            if (lastSlash > 0) {
                return filePath.substring(0, lastSlash);
            }
            return "";
        }
        
        private function createDirectory(path:String):void {
            try {
                var dir:File = new File(path);
                if (!dir.exists) {
                    dir.createDirectory();
                    _log.append("📁 Создана папка: " + path + "\n");
                }
            } catch (error:Error) {
                _log.append("⚠️ Не удалось создать папку " + path + ": " + error.message + "\n");
            }
        }

        private function extractPackages(content:String):Array {
            var packages:Array = [];
            var lines:Array = content.split("\n");
            var currentPackage:Object = null;
            var braceCount:int = 0;
            var inPackage:Boolean = false;
            var packageContent:String = "";
            var linesInPackage:Array = [];
            
            for (var i:int = 0; i < lines.length; i++) {
                var line:String = lines[i];
                var trimmedLine:String = trimString(line);
                
                // Ищем начало package
                if (trimmedLine.indexOf("package ") == 0) {
                    // Если мы уже внутри package, сохраняем предыдущий
                    if (currentPackage != null) {
                        currentPackage.content = packageContent;
                        currentPackage.lines = linesInPackage;
                        currentPackage.className = findClassNameInLines(linesInPackage);
                        // ОБНОВЛЕНО: Устанавливаем имя файла на основе имени класса
                        if (currentPackage.className && currentPackage.packagePath) {
                            currentPackage.filePath = packagePathToFilePath(currentPackage.packagePath, currentPackage.className);
                        }
                        packages.push(currentPackage);
                    }
                    
                    // Создаём новый package
                    currentPackage = parsePackageLine(line);
                    packageContent = line + "\n";
                    braceCount = 0;
                    inPackage = true;
                    linesInPackage = [trimmedLine];
                    
                    // Начинаем считать скобки
                    braceCount += countChar(line, '{');
                    braceCount -= countChar(line, '}');
                    
                } else if (inPackage && currentPackage != null) {
                    // Добавляем строку к содержимому
                    packageContent += line + "\n";
                    linesInPackage.push(trimmedLine);
                    
                    // Считаем скобки
                    braceCount += countChar(line, '{');
                    braceCount -= countChar(line, '}');
                    
                    // Проверяем, закончился ли package
                    if (braceCount <= 0 && trimmedLine != "") {
                        // Package закончился
                        currentPackage.content = packageContent;
                        currentPackage.lines = linesInPackage;
                        currentPackage.className = findClassNameInLines(linesInPackage);
                        // ОБНОВЛЕНО: Устанавливаем имя файла
                        if (currentPackage.className && currentPackage.packagePath) {
                            currentPackage.filePath = packagePathToFilePath(currentPackage.packagePath, currentPackage.className);
                        }
                        packages.push(currentPackage);
                        
                        // Сбрасываем состояние
                        currentPackage = null;
                        inPackage = false;
                        packageContent = "";
                        braceCount = 0;
                        linesInPackage = [];
                    }
                }
            }
            
            // Добавляем последний package
            if (currentPackage != null) {
                currentPackage.content = packageContent;
                currentPackage.lines = linesInPackage;
                currentPackage.className = findClassNameInLines(linesInPackage);
                // ОБНОВЛЕНО: Устанавливаем имя файла
                if (currentPackage.className && currentPackage.packagePath) {
                    currentPackage.filePath = packagePathToFilePath(currentPackage.packagePath, currentPackage.className);
                }
                packages.push(currentPackage);
            }
            
            return packages;
        }
        
        private function findClassNameInLines(lines:Array):String {
            if (!lines) return null;
            
            for each (var line:String in lines) {
                var classMatch:Array = line.match(/\b(class|interface)\s+(\w+)\b/);
                if (classMatch && classMatch.length > 2) {
                    return classMatch[2];
                }
            }
            return null;
        }

        private function parsePackageLine(line:String):Object {
            var result:Object = {};

            // Извлекаем путь из package
            var packageMatch:Array = line.match(/package\s+([^{]+)/);
            if (packageMatch && packageMatch.length > 1) {
                var packagePath:String = trimString(packageMatch[1]);
                // Убираем точку с запятой если есть
                if (packagePath.charAt(packagePath.length - 1) == ';') {
                    packagePath = packagePath.substring(0, packagePath.length - 1);
                }
                result.packagePath = packagePath;
                // Не устанавливаем filePath здесь - дождемся имени класса
            }
            
            return result;
        }

        // ОБНОВЛЕННЫЙ МЕТОД: теперь принимает packagePath И className
        private function packagePathToFilePath(packagePath:String, className:String):String {
            // Преобразуем package com.example в путь к папке
            var folderPath:String = packagePath.replace(/\./g, "/");
            
            // Добавляем имя файла с расширением .as
            var filePath:String = folderPath + File.separator + className + ".as";
            
            // Возвращаем полный путь
            return _projectRoot + File.separator + filePath;
        }
	
        private function trimString(str:String):String {
            if (str == null) return "";
            return str.replace(/^\s+|\s+$/g, "");
        }
        
        private function countChar(str:String, char:String):int {
            var count:int = 0;
            for (var i:int = 0; i < str.length; i++) {
                if (str.charAt(i) == char) {
                    count++;
                }
            }
            return count;
        }
        
        private function savePackages(packages:Array, index:int, callback:Function):void {
            if (index >= packages.length) {
                _log.append("✅ Все файлы успешно сохранены!\n");
                callback(true);
                return;
            }
            
            var packageInfo:Object = packages[index];
            var filePath:String = packageInfo.filePath;
            var content:String = packageInfo.content;
            
            if (!filePath || !content) {
                _log.append("⚠️ Пропущен некорректный package: " + 
                           (packageInfo.className || "unknown") + 
                           " (package: " + (packageInfo.packagePath || "none") + ")\n");
                setTimeout(function():void {
                    savePackages(packages, index + 1, callback);
                }, 10);
                return;
            }
            
            _log.append("💾 Сохраняю: " + packageInfo.className + 
                       " -> " + filePath + "\n");
            
            _fileManager.writeFile(filePath, content, function(msg:String):void {
                _log.append(msg);
                setTimeout(function():void {
                    savePackages(packages, index + 1, callback);
                }, 50);
            });
        }
    }
}