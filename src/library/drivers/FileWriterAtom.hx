package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;
import StringBuf;

// Платформо-зависимые импорты
#if html5
import js.Syntax;
#else
import sys.io.File;
import sys.io.FileOutput;
import sys.io.FileSeek;
import lime.ui.FileDialog;
#end

class FileWriterAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;
    private static inline var MODE_WRITE:Int = 0;
    private static inline var MODE_APPEND:Int = 1;

    // STATE (DATABANK)
    private var _isOpenFlag:Bool = false;
    private var _fileSize:Int = 0;
    private var _writeCount:Int = 0;
    private var _mode:Int = MODE_APPEND;
    private var _enabled:Bool = true;
    private var _suggestedFileName:String = "output.txt";
    private var _lastError:String = "";
    private var _pendingOpen:Bool = false;

    // FALLBACK MECHANISM (For Android 9 / Chrome < 130)
    private var _isFallbackMode:Bool = false;
    private var _fallbackBuffer:StringBuf = null;

    #if html5
    // FILE SYSTEM ACCESS API FIELDS
    private var _fileHandle:Dynamic = null;
    private var _stream:Dynamic = null;
    #else
    // NATIVE FILE SYSTEM FIELDS
    private var _filePath:String = null;
    private var _stream:FileOutput = null;
    #end

    // PULSE TIMERS
    private var _writtenTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [
                new Contact(false, INPUT, "open"),
                new Contact(false, INPUT, "close"),
                new Contact("", INPUT, "write"),
                new Contact("", INPUT, "append"),
                new Contact(false, INPUT, "clear"),
                new Contact(false, INPUT, "flush"),
                new Contact(true, INPUT, "enabled"),
                new Contact(MODE_APPEND, INPUT, "mode"),
                new Contact("output.txt", INPUT, "fileName")
            ],
            [
                new Contact(false, OUTPUT, "isOpen"),
                new Contact(false, OUTPUT, "written"),
                new Contact(0, OUTPUT, "writeCount"),
                new Contact(0, OUTPUT, "fileSize"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "FileWriterAtom",
            true
        );
        init();
    }

    override public function init():Void
    {
        trace('FileWriterAtom: Initialized (Main Thread)');
		
        // Регистрируем атом, чтобы DriverManager вызывал update(dt) и readInputs()
        DriverManager.getInstance().register(this);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;
        readInputs();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        if (_isOpenFlag)
        {
            closeFile();
        }
        
        #if html5
        _fileHandle = null;
        _fallbackBuffer = null;
        #end
        
        _stream = null;
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    /**
     * Show file picker dialog.
     * HTML5: Uses File System Access API.
     * Native: Uses lime.ui.FileDialog.
     */
    public function showFilePicker(?suggestedName:String = null):Void
    {
        if (_isDisposed) return;
        var name = suggestedName != null ? suggestedName : _suggestedFileName;
        _suggestedFileName = name;

        #if html5
        var self = this;
        untyped {
            if (js.Browser.window.showSaveFilePicker != null)
            {
                self._isFallbackMode = false;
                var pickerOptions:Dynamic = {
                    suggestedName: name,
                    types: [
                        {
                            description: "Text Files",
                            accept: { "text/plain": [".txt", ".log", ".csv", ".dat"] }
                        }
                    ]
                };
                js.Browser.window.showSaveFilePicker(pickerOptions)
                    .then(function(handle) { self.onFileSelected(handle); })
                    ['catch'](function(err) { self.onFilePickerCancelled(err); });
            }
            else
            {
                self.initFallbackMode(name);
            }
        }
		/*#else // если использую указанный прямой путь к файлу
        // NATIVE TARGET (Windows / Android)
        var self = this;
        
        // 1. КРИТИЧНО: Используем абсолютный путь, чтобы избежать проблем с правами доступа 
        // и скрытой записи в папку с exe-файлом или системные директории.
        #if sys
        self._filePath = sys.FileSystem.absolutePath(name);
        
        // 2. Гарантируем, что родительская папка существует (избегаем ошибок "Path not found")
        // ИСПРАВЛЕНО: используем haxe.io.Path.directory вместо sys.FileSystem.directory
        var dir:String = haxe.io.Path.directory(self._filePath);
        if (dir != null && dir != "" && !sys.FileSystem.exists(dir)) {
            try {
                sys.FileSystem.createDirectory(dir);
            } catch(e:Dynamic) {
                self.setError('Cannot create directory: $e');
                return;
            }
        }
        #else
        self._filePath = name;
        #end

        try {
            // 3. КРИТИЧНО: Учитываем режим! false = перезапись (Write), true = добавление (Append)
            var shouldAppend = (self._mode == MODE_APPEND);
            self._stream = File.write(self._filePath, shouldAppend);
            
            self._isOpenFlag = true;
            
            // Если открыли в режиме добавления, синхронизируем размер с реальным положением курсора
            if (shouldAppend) {
                self._fileSize = self._stream.tell();
            } else {
                self._fileSize = 0;
            }
            
            self._writeCount = 0;
            self.updateOutputs();
            
            trace('FileWriterAtom: Native file opened at: ${self._filePath} (Mode: ${shouldAppend ? "Append" : "Write/Truncate"})');
            
        } catch(e:Dynamic) {
            self.setError('Native file error: $e. Path: ${self._filePath}');
        }
        #end*/
		#else // если использую File Picker Dialog
        // NATIVE TARGET (Windows / Linux / Android)
        var self = this;
        
        // Создаем нативный диалог выбора файла
        var dialog = new lime.ui.FileDialog();
        
        // ИСПРАВЛЕНО: Используем .add() вместо присваивания =
        dialog.onSave.add(function(path:String) {
            if (path == null || path == "") return;
            
            self._filePath = path;
            self._suggestedFileName = haxe.io.Path.withoutDirectory(path); // Оставляем только имя файла
            
            try {
                var shouldAppend = (self._mode == MODE_APPEND);
                self._stream = sys.io.File.write(self._filePath, shouldAppend);
                
                self._isOpenFlag = true;
                if (shouldAppend) {
                    self._fileSize = self._stream.tell();
                } else {
                    self._fileSize = 0;
                }
                self._writeCount = 0;
                self.updateOutputs();
                
                trace('FileWriterAtom: Native file opened at: ${self._filePath} (Mode: ${shouldAppend ? "Append" : "Write/Truncate"})');
            } catch(e:Dynamic) {
                self.setError('Native file error: $e. Path: ${self._filePath}');
            }
        });
        
        // ИСПРАВЛЕНО: Используем .add() вместо присваивания =
        dialog.onCancel.add(function() {
            trace('FileWriterAtom: File dialog cancelled by user.');
        });

        // Вызываем нативное окно "Сохранить как"
        // Параметры: 
        // 1. data (передаем "", чтобы Lime не пытался сам записать мусор, мы сделаем это через sys.io.File)
        // 2. defaultPath (имя файла по умолчанию)
        // 3. title (заголовок окна)
        // 4. filter (фильтр расширений)
        dialog.save("", name, "Select File to Write", "Text Files (*.txt)|*.txt|All Files (*.*)|*.*");
        #end
	}

    #if html5
    private function initFallbackMode(fileName:String):Void
    {
        _isFallbackMode = true;
        _fallbackBuffer = new StringBuf();
        _isOpenFlag = true;
        _fileSize = 0;
        _writeCount = 0;
        updateOutputs();
        trace('FileWriterAtom: Opened in Fallback (Blob Storage) Mode for legacy Android/Chrome');
    }

    private function onFileSelected(handle:Dynamic):Void
    {
        if (_isDisposed) return;
        _fileHandle = handle;
        var self = this;
        untyped handle.createWritable().then(function(stream:Dynamic) {
            self.onStreamOpened(stream);
        })['catch'](function(err:Dynamic) {
            self.onStreamOpenError(err);
        });
    }

    private function onStreamOpened(stream:Dynamic):Void
    {
        if (_isDisposed) return;
        _stream = stream;
        _isOpenFlag = true;
        _fileSize = 0;
        _writeCount = 0;
        updateOutputs();
        trace('FileWriterAtom: File opened via FSA API');
    }

    private function onStreamOpenError(err:Dynamic):Void
    {
        if (_isDisposed) return;
        var errMsg = (err != null && err.message != null) ? Std.string(err.message) : "Unknown error";
        setError('Failed to open stream: $errMsg');
    }

    private function onFilePickerCancelled(err:Dynamic):Void
    {
        if (_isDisposed) return;
        _pendingOpen = false;
        trace('FileWriterAtom: File picker cancelled');
    }

    private function triggerFallbackDownload():Void
    {
        if (!_isFallbackMode || _fallbackBuffer == null) return;
        var content = _fallbackBuffer.toString();
        if (content.length == 0) return;
        var fileName = _suggestedFileName;
        Syntax.code(
            "var blob = new Blob([{0}], { type: 'text/plain;charset=utf-8' });
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url;
            a.download = {1};
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);", content, fileName);
    }
    #end

    private function writeData(data:String):Void
    {
        if (_isDisposed || !_isOpenFlag || data == null || data == "") return;

        #if html5
        if (_isFallbackMode)
        {
            if (_mode == MODE_WRITE)
            {
                _fallbackBuffer = new StringBuf();
                _fallbackBuffer.add(data);
                _fileSize = data.length;
            }
            else
            {
                _fallbackBuffer.add(data);
                _fileSize += data.length;
            }
            onWriteComplete(data.length);
            return;
        }
        if (_stream == null) return;
        var self = this;
        if (_mode == MODE_WRITE)
        {
            untyped _stream.seek(0).then(function() {
                return untyped _stream.truncate(0);
            }).then(function() {
                return untyped _stream.write(data);
            }).then(function() {
                self.onWriteComplete(data.length);
            })['catch'](function(err:Dynamic) {
                self.onWriteError(err);
            });
        }
        else
        {
            untyped _stream.seek(_fileSize).then(function() {
                return untyped _stream.write(data);
            }).then(function() {
                self.onWriteComplete(data.length);
            })['catch'](function(err:Dynamic) {
                self.onWriteError(err);
            });
        }
        #else
        if (_stream == null) return;
        try {
            if (_mode == MODE_WRITE) {
                // В режиме WRITE мы обязаны перезаписать файл. 
                // В Haxe самый надежный способ - закрыть и открыть с флагом false.
                _stream.close();
                _stream = File.write(_filePath, false); 
                _fileSize = 0;
            }
            _stream.writeString(data);
            _fileSize = _stream.tell();
            onWriteComplete(data.length);
            
            _stream.flush();
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    private function appendData(data:String):Void
    {
        if (_isDisposed || !_isOpenFlag || data == null || data == "") return;

        #if html5
        if (_isFallbackMode)
        {
            _fallbackBuffer.add(data);
            _fileSize += data.length;
            onWriteComplete(data.length);
            return;
        }
        if (_stream == null) return;
        var self = this;
        untyped _stream.seek(_fileSize).then(function() {
            return untyped _stream.write(data);
        }).then(function() {
            self.onWriteComplete(data.length);
        })['catch'](function(err:Dynamic) {
            self.onWriteError(err);
        });
        #else
        if (_stream == null) return;
        try {
            // КРИТИЧНО: SeekEnd гарантирует, что мы пишем строго в конец файла, 
            // независимо от того, что хранится в переменной _fileSize.
            _stream.seek(0, SeekEnd);
            _stream.writeString(data);
            
            // Обновляем размер после записи
            _fileSize = _stream.tell();
            onWriteComplete(data.length);
            
            // КРИТИЧНО: Принудительно сбрасываем буфер на диск
            _stream.flush();
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    private function flushBuffer():Void
    {
        if (_isDisposed || !_isOpenFlag) return;

        #if html5
        if (_isFallbackMode)
        {
            triggerFallbackDownload();
            trace('FileWriterAtom: Fallback buffer flushed to browser download');
            return;
        }
        if (_stream == null) return;
        var self = this;
        untyped _stream.flush().then(function() {
            trace('FileWriterAtom: Stream flushed');
        })['catch'](function(err:Dynamic) {
            self.onWriteError(err);
        });
        #else
        if (_stream == null) return;
        try {
            _stream.flush();
            trace('FileWriterAtom: Native stream flushed');
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    private function clearFile():Void
    {
        if (_isDisposed || !_isOpenFlag) return;

        #if html5
        if (_isFallbackMode)
        {
            _fallbackBuffer = new StringBuf();
            _fileSize = 0;
            _writeCount = 0;
            updateOutputs();
            trace('FileWriterAtom: Fallback buffer cleared');
            return;
        }
        if (_stream == null) return;
        var self = this;
        untyped _stream.seek(0).then(function() {
            return untyped _stream.truncate(0);
        }).then(function() {
            self._fileSize = 0;
            self._writeCount = 0;
            self.updateOutputs();
            trace('FileWriterAtom: File cleared');
        })['catch'](function(err:Dynamic) {
            self.onWriteError(err);
        });
        #else
        if (_stream == null) return;
        try {
            _stream.close();
            _stream = File.write(_filePath, false); // Truncates file
            _fileSize = 0;
            _writeCount = 0;
            updateOutputs();
            
            // КРИТИЧНО: Сбрасываем очистку на диск немедленно
            _stream.flush();
            trace('FileWriterAtom: Native file cleared');
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    private function closeFile():Void
    {
        if (_isDisposed || !_isOpenFlag) return;

        #if html5
        if (_isFallbackMode)
        {
            triggerFallbackDownload();
            _fallbackBuffer = null;
            _isOpenFlag = false;
            updateOutputs();
            trace('FileWriterAtom: Fallback file closed & downloaded');
            return;
        }
        if (_stream == null) return;
        var self = this;
        untyped _stream.close().then(function() {
            self._stream = null;
            self._isOpenFlag = false;
            self.updateOutputs();
            trace('FileWriterAtom: File closed');
        })['catch'](function(err:Dynamic) {
            self.onWriteError(err);
        });
        #else
        if (_stream == null) return;
        try {
            _stream.close();
            _stream = null;
            _isOpenFlag = false;
            updateOutputs();
            trace('FileWriterAtom: Native file closed');
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    private function onWriteComplete(bytesWritten:Int):Void
    {
        if (_isDisposed) return;
        #if !html5
        // Native file size is updated during write via tell()
        #else
        if (!_isFallbackMode) _fileSize += bytesWritten;
        #end
        _writeCount++;
        updateOutputs();

        var writtenOut = getOutput("written");
        if (writtenOut != null)
        {
            writtenOut.value = true;
            _writtenTimer = PULSE_DURATION;
        }
    }

    private function onWriteError(err:Dynamic):Void
    {
        if (_isDisposed) return;
        var errMsg = (err != null && err.message != null) ? Std.string(err.message) : Std.string(err);
        setError('Write error: $errMsg');
    }

    private function readInputs():Void
    {
        if (_isDisposed) return;

        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null)
        {
            _enabled = (enabledC.value == true);
        }
        if (!_enabled) return;

        var modeC = getInput("mode");
        if (modeC != null && modeC.value != null)
        {
            var newMode = Std.int(modeC.value);
            if (newMode == MODE_WRITE || newMode == MODE_APPEND)
            {
                _mode = newMode;
            }
        }

        var fileNameC = getInput("fileName");
        if (fileNameC != null && fileNameC.value != null)
        {
            _suggestedFileName = Std.string(fileNameC.value);
        }

        var openC = getInput("open");
        if (openC != null && openC.value == true)
        {
            openC.value = false;
            _pendingOpen = true;
            showFilePicker(_suggestedFileName);
        }

        var writeC = getInput("write");
        if (writeC != null && writeC.value != null)
        {
            var data = Std.string(writeC.value);
            if (data != "")
            {
                writeData(data);
                // КРИТИЧНО: Очищаем контакт, чтобы данные записались только один раз,
                // иначе атом будет спамить записью 60 раз в секунду и вешать браузер
                writeC.setValueSilent("");
            }
        }

        var appendC = getInput("append");
        if (appendC != null && appendC.value != null)
        {
            var data = Std.string(appendC.value);
            if (data != "")
            {
                appendData(data);
                appendC.setValueSilent("");
            }
        }

        var clearC = getInput("clear");
        if (clearC != null && clearC.value == true)
        {
            clearC.value = false;
            clearFile();
        }

        var flushC = getInput("flush");
        if (flushC != null && flushC.value == true)
        {
            flushC.value = false;
            flushBuffer();
        }

        var closeC = getInput("close");
        if (closeC != null && closeC.value == true)
        {
            closeC.value = false;
            closeFile();
        }
    }

    private function updateOutputs():Void
    {
        var isOpenOut = getOutput("isOpen");
        var writeCountOut = getOutput("writeCount");
        var fileSizeOut = getOutput("fileSize");

        if (isOpenOut != null) isOpenOut.setValueSilent(_isOpenFlag);
        if (writeCountOut != null) writeCountOut.setValueSilent(_writeCount);
        if (fileSizeOut != null) fileSizeOut.setValueSilent(_fileSize);

        if (isOpenOut != null) isOpenOut.propagateCurrentValue();
        if (writeCountOut != null) writeCountOut.propagateCurrentValue();
        if (fileSizeOut != null) fileSizeOut.propagateCurrentValue();
    }

    private function setError(msg:String):Void
    {
        if (_isDisposed) return;
        _lastError = msg;
        var errorOut = getOutput("error");
        if (errorOut != null)
        {
            errorOut.setValueSilent(msg);
            errorOut.propagateCurrentValue();
        }
        var errorTickOut = getOutput("errorTick");
        if (errorTickOut != null)
        {
            errorTickOut.value = true;
            _errorTimer = PULSE_DURATION;
        }
        trace('FileWriterAtom ERROR: $msg');
    }

    private function updatePulseTimers(dt:Float):Void
    {
        if (_isDisposed) return;

        if (_writtenTimer > 0)
        {
            _writtenTimer -= dt;
            if (_writtenTimer <= 0)
            {
                var c = getOutput("written");
                if (c != null) c.value = false;
            }
        }
        if (_errorTimer > 0)
        {
            _errorTimer -= dt;
            if (_errorTimer <= 0)
            {
                var c = getOutput("errorTick");
                if (c != null) c.value = false;
            }
        }
    }
    
    public function isOpen():Bool return _isOpenFlag;
    public function getFileSize():Int return _fileSize;
    public function getWriteCount():Int return _writeCount;
    public function getMode():Int return _mode;
    public function setMode(mode:Int):Void
    {
        if (mode == MODE_WRITE || mode == MODE_APPEND) _mode = mode;
    }
    public function getSuggestedFileName():String return _suggestedFileName;
    public function hasPendingOpen():Bool return _pendingOpen;
}