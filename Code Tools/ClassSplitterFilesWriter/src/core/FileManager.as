// src/core/FileManager.as
package src.core {
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;
    import flash.desktop.NativeProcess;
    import flash.desktop.NativeProcessStartupInfo;
    import flash.events.ProgressEvent;
    import flash.events.NativeProcessExitEvent;
    import flash.events.IOErrorEvent;

    public class FileManager {
        private var _projectRoot:String;

        public function FileManager(projectRoot:String) {
            _projectRoot = projectRoot;
        }

        public function writeFile(path:String, content:String, callback:Function):void {
            if (NativeProcess.isSupported) {
                var startup:NativeProcessStartupInfo = new NativeProcessStartupInfo();
                var exe:File = File.applicationDirectory.resolvePath("fileWriter.exe");
                startup.executable = exe;
                startup.arguments = new <String>[path, content];
                var process:NativeProcess = new NativeProcess();
                process.start(startup);
                process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, function(e:ProgressEvent):void {
                    var out:String = process.standardOutput.readUTFBytes(process.standardOutput.bytesAvailable);
                    callback("[Native] " + out);
                });
                process.addEventListener(NativeProcessExitEvent.EXIT, function(e:NativeProcessExitEvent):void {
                    if (e.exitCode != 0) callback("[ERROR] Exit code: " + e.exitCode + "\n");
                });
            } else {
                // fallback
                var file:File = new File(path);
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.WRITE);
                stream.writeUTFBytes(content);
                stream.close();
                callback("[Saved] " + path + "\n");
            }
        }
    }
}