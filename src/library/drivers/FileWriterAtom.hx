package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;
import StringBuf;

// Платформо-зависимые импорты
#if html5
import js.Syntax;
#else
import sys.io.File;
import sys.io.FileOutput;
import sys.io.FileSeek;
import core.io.NativeDialog;
#end

/**
 * FILE WRITER ATOM v1.3 (Этап 4a-4, Task 146)
 * ============================================================================
 * Двуязычные порции: [write]/[append] принимают String | Bytes | Cargo.
 *   · String — прежняя текстовая семантика (writeString, легаси);
 *   · Bytes  — сырые байты: writeFullBytes, байт-в-байт (md5 1:1);
 *   · Cargo  — распаковка по kind (bytes → сырые байты; text → UTF-8 строка).
 * Провод FileReader.bytes → FileWriter.write пишет бинарные файлы без
 * единой конверсии — закрывает полевой баг-репорт Alik (fft.png калечился
 * текстовой трубой: магия PNG → C9 90 4E 47, U+FFFD по всему телу).
 * Семантика режимов НЕ тронута: Write = снапшот последней порции,
 * Append = дописывание в конец (FIX B..G, Task 140 живы).
 * ============================================================================
 */
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
    /** v1.3: байтовые порции fallback-режима (Blob из частей при скачивании). */
    private var _fallbackByteParts:Array<Bytes> = null;
    #end

    #if html5
    // FILE SYSTEM ACCESS API FIELDS
    private var _fileHandle:Dynamic = null;
    private var _stream:Dynamic = null;
    private var _appendBaseSize:Int = 0;   // v1.2: размер файла до открытия (Append)
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
     * Native: core.io.NativeDialog — наш comdlg32-мост (Этап 3; Task 141).
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
        
        // v1.2.1 (Task 141): диалог — на нашем мосту core.io.NativeDialog
        // (comdlg32, Этап 3), НЕ на lime-диалог: в реальной библиотеке
        // Станции нет browse-методов (выдуманы в Task 140, пойманы
        // компилятором Super A), а её onOpen типизирован lime.utils.Resource.
        // Мост возвращает ТОЛЬКО путь (семантика FIX A жива) и, в отличие от
        // выдуманного browse-метода, ПРЕДЗАПОЛНЯЕТ имя файла (аргумент name).
        if (!NativeDialog.isSupported())
        {
            self.setError('Native file dialog is not supported on this target');
            return;
        }
        
        var pickedPath:String = NativeDialog.saveFile(
            "Select File to Write",
            name,
            "",
            "Text Files (*.txt;*.log;*.csv;*.dat)|*.txt;*.log;*.csv;*.dat|All Files (*.*)|*.*",
            "txt");
        
        if (pickedPath == null || pickedPath == "")
        {
            trace('FileWriterAtom: File dialog cancelled by user.');
            return;
        }
        
        self._filePath = pickedPath;
        self._suggestedFileName = haxe.io.Path.withoutDirectory(pickedPath); // Оставляем только имя файла
        
        try {
            var shouldAppend = (self._mode == MODE_APPEND);
            // v1.2 FIX B (Task 140): File.write(path, binary) — второй аргумент
            // это БИНАРНЫЙ флаг, а НЕ «дописывать»! Передача shouldAppend
            // открывала файл с ОБРЕЗКОЙ (fopen "wb") — Append терял
            // содержимое. Для дописывания — File.append (fopen "ab").
            if (shouldAppend) {
                self._stream = sys.io.File.append(self._filePath, true);
                self._stream.seek(0, SeekEnd);
                self._fileSize = self._stream.tell();
            } else {
                self._stream = sys.io.File.write(self._filePath, true);
                self._fileSize = 0;
            }
            self._isOpenFlag = true;
            self._writeCount = 0;
            self.updateOutputs();
            
            trace('FileWriterAtom: Native file opened at: ${self._filePath} (Mode: ${shouldAppend ? "Append" : "Write/Truncate"})');
        } catch(e:Dynamic) {
            self.setError('Native file error: $e. Path: ${self._filePath}');
        }
        #end
        }

    #if html5
    private function initFallbackMode(fileName:String):Void
    {
        _isFallbackMode = true;
        _fallbackBuffer = new StringBuf();
        _fallbackByteParts = [];   // v1.3: параллельный байтовый буфер
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
        // v1.2 FIX E (Task 140): createWritable() по умолчанию ОБРЕЗАЕТ файл —
        // тот же класс бага, что File.write(path, binary) в нативной ветке.
        // Append-режим: keepExistingData=true + база размера для seek.
        var opts:Dynamic = (_mode == MODE_APPEND) ? { keepExistingData: true } : { };
        untyped handle.createWritable(opts).then(function(stream:Dynamic) {
            if (self._mode == MODE_APPEND) {
                untyped handle.getFile().then(function(f:Dynamic) {
                    self._appendBaseSize = untyped f.size;
                    self.onStreamOpened(stream);
                })['catch'](function(err:Dynamic) {
                    self.onStreamOpenError(err);
                });
            } else {
                self.onStreamOpened(stream);
            }
        })['catch'](function(err:Dynamic) {
            self.onStreamOpenError(err);
        });
    }

    private function onStreamOpened(stream:Dynamic):Void
    {
        if (_isDisposed) return;
        _stream = stream;
        _isOpenFlag = true;
        // v1.2 FIX F (Task 140): Append-режим начинает с существующего размера.
        _fileSize = (_mode == MODE_APPEND) ? _appendBaseSize : 0;
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
        if (!_isFallbackMode) return;
        var fileName = _suggestedFileName;
        #if html5
        // v1.3: если копились байтовые порции — скачиваем бинарным Blob'ом;
        // иначе — прежний текстовый путь (легаси).
        if (_fallbackByteParts != null && _fallbackByteParts.length > 0)
        {
            var parts:Array<Dynamic> = [for (b in _fallbackByteParts) b.getData()];
            Syntax.code(
                "var blob = new Blob({0}, { type: 'application/octet-stream' });
                var url = URL.createObjectURL(blob);
                var a = document.createElement('a');
                a.href = url;
                a.download = {1};
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);", parts, fileName);
            return;
        }
        #end
        if (_fallbackBuffer == null) return;
        var content = _fallbackBuffer.toString();
        if (content.length == 0) return;
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
                _fallbackByteParts = [];   // v1.3: снапшот чистит и байтовый буфер
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
                // В режиме WRITE каждая запись заменяет файл (снапшот последней записи).
                // v1.2 FIX C (Task 140): File.write(path, false) открывал файл в ТЕКСТОВОМ
                // режиме (второй аргумент — binary, не «перезапись»): на Windows "\n"
                // молча превращался в "\r\n". Теперь честный binary — байты 1:1.
                _stream.close();
                _stream = File.write(_filePath, true);
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

    /**
     * v1.3 (Этап 4a-4): записать СЫРЫЕ БАЙТЫ — writeFullBytes, никакой строковой
     * конверсии. Зеркало writeData по семантике режимов: Write = снапшот
     * (переоткрытие с обрезкой), Append = строго в конец (SeekEnd).
     */
    private function writeBytesData(data:Bytes):Void
    {
        if (_isDisposed || !_isOpenFlag || data == null || data.length == 0) return;

        #if html5
        if (_isFallbackMode)
        {
            if (_mode == MODE_WRITE)
            {
                _fallbackByteParts = [];
                _fallbackBuffer = new StringBuf();   // байтовый снапшот вытесняет текст
            }
            _fallbackByteParts.push(data);
            _fileSize += data.length;
            onWriteComplete(data.length);
            return;
        }
        if (_stream == null) return;
        var self = this;
        var buf:Dynamic = data.getData();
        if (_mode == MODE_WRITE)
        {
            untyped _stream.seek(0).then(function() {
                return untyped _stream.truncate(0);
            }).then(function() {
                return untyped _stream.write(buf);
            }).then(function() {
                self.onWriteComplete(data.length);
            })['catch'](function(err:Dynamic) {
                self.onWriteError(err);
            });
        }
        else
        {
            untyped _stream.seek(_fileSize).then(function() {
                return untyped _stream.write(buf);
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
                // Снапшот последней порции — зеркало writeData (FIX C: binary=true)
                _stream.close();
                _stream = File.write(_filePath, true);
                _fileSize = 0;
            }
            _stream.writeFullBytes(data, 0, data.length);
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

    /** v1.3 (Этап 4a-4): дописать СЫРЫЕ БАЙТЫ в конец (зеркало appendData). */
    private function appendBytesData(data:Bytes):Void
    {
        if (_isDisposed || !_isOpenFlag || data == null || data.length == 0) return;

        #if html5
        if (_isFallbackMode)
        {
            _fallbackByteParts.push(data);
            _fileSize += data.length;
            onWriteComplete(data.length);
            return;
        }
        if (_stream == null) return;
        var self = this;
        var buf:Dynamic = data.getData();
        untyped _stream.seek(_fileSize).then(function() {
            return untyped _stream.write(buf);
        }).then(function() {
            self.onWriteComplete(data.length);
        })['catch'](function(err:Dynamic) {
            self.onWriteError(err);
        });
        #else
        if (_stream == null) return;
        try {
            // КРИТИЧНО: SeekEnd гарантирует запись строго в конец файла
            _stream.seek(0, SeekEnd);
            _stream.writeFullBytes(data, 0, data.length);

            _fileSize = _stream.tell();
            onWriteComplete(data.length);

            // КРИТИЧНО: Принудительно сбрасываем буфер на диск
            _stream.flush();
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    /**
     * v1.3 (Этап 4a-4): ДВУЯЗЫЧНОЕ потребление порции на [write]/[append].
     * Cargo распаковывается по kind; голые Bytes пишутся как есть; String —
     * прежняя текстовая семантика (легаси). Возвращает true, если порция
     * потреблена (вход следует очистить — идиома П1 «принял — очисти»).
     */
    private function consumePortion(portion:Dynamic, append:Bool):Bool
    {
        if (portion == null) return false;

        if (Cargo.isCargo(portion))
        {
            var c:Cargo = cast portion;
            if (c.data == null || c.size == 0) return false;
            if (c.kind == Cargo.KIND_BYTES)
            {
                var b:Bytes = cast c.data;
                if (b.length == 0) return false;
                if (append) appendBytesData(b); else writeBytesData(b);
            }
            else
            {
                var s:String = Std.string(c.data);
                if (s == "") return false;
                if (append) appendData(s); else writeData(s);
            }
            return true;
        }

        if (Std.isOfType(portion, Bytes))
        {
            var b:Bytes = cast portion;
            if (b.length == 0) return false;
            if (append) appendBytesData(b); else writeBytesData(b);
            return true;
        }

        var s2:String = Std.string(portion);
        if (s2 == "") return false;
        if (append) appendData(s2); else writeData(s2);
        return true;
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
            _fallbackByteParts = [];   // v1.3: чистим и байтовый буфер
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
            // v1.2 FIX D (Task 140): binary=true — единый байтовый режим (см. writeData).
            _stream = File.write(_filePath, true); // Truncates file
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
            // v1.3 (Этап 4a-4): вход двуязычен — String | Bytes | Cargo.
            // КРИТИЧНО: Очищаем контакт после потребления, чтобы порция
            // записалась только один раз (иначе 60 Гц-спам записью).
            if (consumePortion(writeC.value, false))
            {
                writeC.setValueSilent(null);
            }
        }

        var appendC = getInput("append");
        if (appendC != null && appendC.value != null)
        {
            if (consumePortion(appendC.value, true))
            {
                appendC.setValueSilent(null);
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
