// src/core/FileScanner.as
package src.core {
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.Dictionary;
    import src.ui.LogOutput;
    import flash.utils.setTimeout;

    public class FileScanner {
        private var _log:LogOutput;
        public var fileContents:Dictionary = new Dictionary();
        public var fileCount:int = 0;

        public function FileScanner(log:LogOutput) {
            _log = log;
        }

        public function loadFolders(folders:Array):void {
            fileContents = new Dictionary();
            fileCount = 0;
            _log.append("Scanning folders...\n");
            for each (var folderPath:String in folders) {
                scanFolder(new File(folderPath));
            }
            _log.append("✅ Loaded " + fileCount + " .as files.\n");
        }

        private function scanFolder(dir:File):void {
            if (!dir.isDirectory) return;
            try {
                var files:Array = dir.getDirectoryListing();
                for each (var f:File in files) {
                    if (f.isDirectory) {
                        scanFolder(f);
                    } else if (f.extension && f.extension.toLowerCase() == "as") {
                        var content:String = readFile(f);
                        if (content !== null) {
                            fileContents[f.nativePath] = content;
                            fileCount++;
                        }
                    }
                }
            } catch (e:Error) {
                _log.append("[ERROR] Access denied: " + dir.nativePath + "\n");
            }
        }

        private function readFile(file:File):String {
            var stream:FileStream = new FileStream();
            try {
                stream.open(file, FileMode.READ);
                var content:String = stream.readUTFBytes(stream.bytesAvailable);
                stream.close();
                return content;
            } catch (e:Error) {
                _log.append("[ERROR] Failed to read: " + file.nativePath + "\n");
                return null;
            }
            return content;
        }

        public function applyRegexReplace(pattern:String, replacement:String):void {
            try {
                var regex:RegExp = new RegExp(pattern, "g");
                var changed:int = 0;
                for (var path:String in fileContents) {
                    var old:String = fileContents[path];
                    var replaced:String = old.replace(regex, replacement);
                    if (old != replaced) {
                        fileContents[path] = replaced;
                        changed++;
                    }
                }
                _log.append("✅ Applied regex: " + changed + " files modified.\n");
            } catch (e:Error) {
                _log.append("[ERROR] Regex error: " + e.message + "\n");
            }
        }

        public function saveAllFiles(fileManager:FileManager, onComplete:Function):void {
            var paths:Array = [];
            for (var path:String in fileContents) paths.push(path);
            saveNext(paths, 0, fileManager, onComplete);
        }

        private function saveNext(paths:Array, i:int, fm:FileManager, onComplete:Function):void {
            if (i >= paths.length) {
                onComplete();
                return;
            }
            var path:String = paths[i];
            var content:String = fileContents[path];
            fm.writeFile(path, content, function(msg:String):void {
                _log.append(msg);
                setTimeout(function():void {
                    saveNext(paths, i + 1, fm, onComplete);
                }, 10);
            });
        }
    }
}