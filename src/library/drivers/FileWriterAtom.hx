package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;
import StringBuf;

// Platform-dependent imports
#if html5
import js.Syntax;
#else
import sys.io.File;
import sys.io.FileOutput;
import sys.io.FileSeek;
import core.io.NativeDialog;
#end

/**
 *  * FILE WRITER ATOM v1.3 (Stage 4a-4, Task 146)
 * ============================================================================
 *  * Bilingual portions: [write]/[append] accept String | Bytes | Cargo.
 *  *   - String - the legacy text semantics (writeString, legacy);
 *  *   - Bytes  - raw bytes: writeFullBytes, byte-by-byte (md5 1:1);
 *  *   - Cargo  - unpacking by kind (bytes -> raw bytes; text -> a UTF-8 string).
 *  * The FileReader.bytes -> FileWriter.write wire writes binary files without
 *  * a single conversion - it closes the field bug report Alik (fft.png was mangled
 *  * by the text pipe: the PNG magic -> C9 90 4E 47, U+FFFD all over the body).
 *  * The mode semantics are untouched: Write = a snapshot of the last portion,
 *  * Append = appending to the end (FIX B..G, Task 141 alive).
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
    /** v1.3: byte portions of the fallback mode (a Blob from parts when downloading). */
    private var _fallbackByteParts:Array<Bytes> = null;
    #end

    #if html5
    // FILE SYSTEM ACCESS API FIELDS
    private var _fileHandle:Dynamic = null;
    private var _stream:Dynamic = null;
    private var _appendBaseSize:Int = 0;   //     private var _appendBaseSize:Int = 0;   // v1.2: the file size before opening (Append)
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
                
        // Register the atom so DriverManager calls update(dt) and readInputs()
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
     *      * Native: core.io.NativeDialog - our comdlg32 bridge (Stage 3; Task 141).
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
                                /*#else // if I use the specified direct file path
        // NATIVE TARGET (Windows / Android)
        var self = this;
        
        // 1. CRITICAL: use an absolute path to avoid permission problems
        // and hidden writes into the exe folder or system directories.
        #if sys
        self._filePath = sys.FileSystem.absolutePath(name);
        
        // 2. Ensure the parent folder exists (avoiding "Path not found" errors)
        // FIXED: use haxe.io.Path.directory instead of sys.FileSystem.directory
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
            // 3. CRITICAL: mind the mode! false = overwrite (Write), true = append (Append)
            var shouldAppend = (self._mode == MODE_APPEND);
            self._stream = File.write(self._filePath, shouldAppend);
            
            self._isOpenFlag = true;
            
            // If opened in append mode, sync the size with the real cursor position
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
                #else //                 #else // if using the File Picker Dialog
        // NATIVE TARGET (Windows / Linux / Android)
        var self = this;
        
        // v1.2.1 (Task 141): the dialog is on our bridge core.io.NativeDialog
        // (comdlg32, Stage 3), NOT on the lime dialog: the real Station
        // library has no browse methods (invented in Task 140, caught
        // by the Super A compiler), and its onOpen is typed lime.utils.Resource.
        // The bridge returns ONLY the path (the FIX A semantics alive) and, unlike
        // the invented browse method, PRE-FILLS the file name (the name argument).
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
        self._suggestedFileName = haxe.io.Path.withoutDirectory(pickedPath); //         self._suggestedFileName = haxe.io.Path.withoutDirectory(pickedPath); // Keep only the file name
        
        try {
            var shouldAppend = (self._mode == MODE_APPEND);
            // v1.2 FIX B (Task 140): File.write(path, binary) - the second argument
            // is the BINARY flag, NOT "append"! Passing shouldAppend
            // opened the file with TRUNCATION (fopen "wb") - Append lost
            // content. For appending - File.append (fopen "ab").
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
        _fallbackByteParts = [];   //         _fallbackByteParts = [];   // v1.3: a parallel byte buffer
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
        // v1.2 FIX E (Task 140): createWritable() by default TRUNCATES the file -
        // the same bug class as File.write(path, binary) in the native branch.
        // Append mode: keepExistingData=true + a base size for seek.
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
        // v1.2 FIX F (Task 140): Append mode starts from the existing size.
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
        // v1.3: if byte portions were collected - download as a binary Blob;
        // otherwise - the legacy text path.
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
                _fallbackByteParts = [];   //                 _fallbackByteParts = [];   // v1.3: the snapshot clears the byte buffer too
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
                // In WRITE mode every write replaces the file (a snapshot of the last write).
                // v1.2 FIX C (Task 140): File.write(path, false) opened the file in TEXT
                // mode (the second argument is binary, not "overwrite"): on Windows "\n"
                // silently turned into "\r\n". Now honest binary - bytes 1:1.
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
     *      * v1.3 (Stage 4a-4): write RAW BYTES - writeFullBytes, no string
     *      * conversion. A mirror of writeData by mode semantics: Write = a snapshot
     *      * (reopen with truncation), Append = strictly to the end (SeekEnd).
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
                _fallbackBuffer = new StringBuf();   //                 _fallbackBuffer = new StringBuf();   // the byte snapshot displaces text
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
                // The snapshot of the last portion - a mirror of writeData (FIX C: binary=true)
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
            // CRITICAL: SeekEnd guarantees we write strictly to the end of the file,
            // regardless of what the _fileSize variable stores.
            _stream.seek(0, SeekEnd);
            _stream.writeString(data);
            
            // Update the size after writing
            _fileSize = _stream.tell();
            onWriteComplete(data.length);
            
            // CRITICAL: Force-flush the buffer to disk
            _stream.flush();
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    /** v1.3 (Stage 4a-4): append RAW BYTES to the end (a mirror of appendData). */
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
            // CRITICAL: SeekEnd guarantees writing strictly to the end of the file
            _stream.seek(0, SeekEnd);
            _stream.writeFullBytes(data, 0, data.length);

            _fileSize = _stream.tell();
            onWriteComplete(data.length);

            // CRITICAL: Force-flush the buffer to disk
            _stream.flush();
        } catch(e:Dynamic) {
            onWriteError(e);
        }
        #end
    }

    /**
     *      * v1.3 (Stage 4a-4): BILINGUAL consumption of the portion on [write]/[append].
     *      * Cargo is unpacked by kind; bare Bytes are written as is; String -
     *      * the legacy text semantics (legacy). Returns true if the portion
     *      * was consumed (the input should be cleared - the P1 idiom "accepted - clear").
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
            _fallbackByteParts = [];   //             _fallbackByteParts = [];   // v1.3: we clear the byte buffer too
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
            // v1.2 FIX D (Task 140): binary=true - a unified byte mode (see writeData).
            _stream = File.write(_filePath, true); // Truncates file
            _fileSize = 0;
            _writeCount = 0;
            updateOutputs();
            
            // CRITICAL: Flush the clearing to disk immediately
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
            // v1.3 (Stage 4a-4): the input is bilingual - String | Bytes | Cargo.
            // CRITICAL: Clear the contact after consumption so the portion
            // is written only once (otherwise 60 Hz write spam).
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
