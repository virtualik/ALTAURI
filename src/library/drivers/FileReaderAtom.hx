package library.drivers;



import core.base.Atom;

import core.base.Contact;

import core.types.ContactType;

import core.types.ContactType.*;

import core.types.Cargo;

import system.managers.DriverManager;

import haxe.io.Bytes;



// Platform-dependent imports (a mirror of FileWriterAtom)
#if html5

import js.Syntax;

#else

import sys.io.File;

import sys.FileSystem;

import core.io.NativeDialog;

#end



/**

 *  * FILE READER ATOM v1.1 (Stage 4a-1 Task 140 + Stage 4a-4 Task 146)
 * ============================================================================

 *  * A MIRROR of FileWriterAtom: the same architecture, the same idioms, the flipped
 *  * semantics (write -> read). Spec: SPEC_STAGE4A_FILEREADER.md.
 *

 * Architecture: "Atom is Databank & Compute Core"

 *  *   open/close/read (impulses) -> dialog/disk -> data/bytes/fileName/size (+ticks)
 *

 *  * TWO OUTPUT CHANNELS (v1.1, Stage 4a-4 "THE BINARY PIPE"):
 *  *   - [data]  (String) - the LEGACY text channel (File.getContent). Honest for text
 *  *     files; BINARY files are mangled by the runtime UTF-8 conversion (hxcpp):
 *  *     the field bug report Alik fft.png - the PNG magic 89 50 4E 47 turns
 *  *     into C9 90 4E 47, the body grows U+FFFD. The channel is kept for compatibility
 *  *     (TextArea and other text consumers); for binary - [bytes].
 *  *   - [bytes] (Cargo)   - the CLEAN byte channel (File.getBytes, NO conversions):
 *  *     Cargo{kind:bytes, data:Bytes, fileName, size} - byte-by-byte md5 1:1.
 *  *     DataStorageAtom v1.0 unpacks Cargo itself (kind+fileName as a gift),
 *  *     FileWriterAtom v1.3 accepts Cargo/Bytes on [write]/[append].
 *

 *  * SEMANTICS (see SPEC §2):
 *  *   - open  -> the native selection dialog (NativeDialog.openFile - ONLY the path,
 *  *     no side effects; the brother of FileWriter v1.2.1, Task 141) -> the file
 *  *     is read from disk immediately -> the outputs emit + readTick.
 *  *   - read  -> re-read the last selected path from disk (without a dialog).
 *  *   - close -> unload the data (data="", bytes=null, fileName="", size=0,
 *  *     isOpen=false); THE PATH IS REMEMBERED: read after close re-reads the same file.
 *

 *  * WHAT READER DOES NOT DO (important): it does NOT store the content in the schematic/tail -
 *  * the file is read from disk at runtime; an instrument without the file nearby gives an honest
 *  * error. Ingesting data into the instrument - DataStorageAtom (Stage 4a-2).
 *

 *  * Persistence: session-based (like the Writer) - the path is not kept between sessions.
 * (translated - see the EN section)
 * ============================================================================

 */

class FileReaderAtom extends Atom implements system.managers.Driver

{

    private static inline var PULSE_DURATION:Float = 0.05;



    // STATE (DATABANK)

    private var _isOpenFlag:Bool = false;      //     private var _isOpenFlag:Bool = false;      // the file is loaded
    private var _readCount:Int = 0;            //     private var _readCount:Int = 0;            // the number of successful reads
    private var _enabled:Bool = true;

    private var _lastError:String = "";

    private var _pendingOpen:Bool = false;



    #if html5

    // FILE SYSTEM ACCESS API FIELDS

    private var _fileHandle:Dynamic = null;

    #else

    // NATIVE FILE SYSTEM FIELDS

    private var _filePath:String = null;       //     private var _filePath:String = null;       // the full path of the last selection
    #end



    // PULSE TIMERS

    private var _readTickTimer:Float = 0.0;

    private var _errorTimer:Float = 0.0;



    public function new(id:String)

    {

        super(

            [   //             [   // INPUTS (the mirrored FileWriterAtom style)
                new Contact(false, INPUT, "open"),

                new Contact(false, INPUT, "close"),

                new Contact(false, INPUT, "read"),

                new Contact(true, INPUT, "enabled")

            ],

            [   // OUTPUTS

                new Contact(false, OUTPUT, "isOpen"),

                new Contact("", OUTPUT, "data"),      //                 new Contact("", OUTPUT, "data"),      // legacy text (a UTF-8 conversion)
                new Contact(null, OUTPUT, "bytes"),    //                 new Contact(null, OUTPUT, "bytes"),    // v1.1: Cargo - clean bytes (md5 1:1)
                new Contact("", OUTPUT, "fileName"),

                new Contact(0, OUTPUT, "size"),

                new Contact(0, OUTPUT, "readCount"),

                new Contact("", OUTPUT, "error"),

                new Contact(false, OUTPUT, "readTick"),

                new Contact(false, OUTPUT, "errorTick")

            ],

            null,

            id,

            "FileReaderAtom",

            true

        );

        init();

    }



    override public function init():Void

    {

        trace('FileReaderAtom: Initialized (Main Thread)');



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

        #if html5

        _fileHandle = null;

        #end



        DriverManager.getInstance().unregister(this.id);

        super.dispose();

    }



    /**

     * Show open-file picker; on selection the file is loaded immediately.

     * HTML5: File System Access API (+ legacy <input type="file"> fallback).

     *      * Native: core.io.NativeDialog.openFile (the Stage 3 bridge) - ONLY the path.
     */

    public function showFilePicker():Void

    {

        if (_isDisposed) return;



        #if html5

        var self = this;

        untyped {

            if (js.Browser.window.showOpenFilePicker != null)

            {

                var pickerOptions:Dynamic = {

                    multiple: false,

                    types: [

                        {

                            description: "All Files",

                            accept: { "*/*": [] }

                        }

                    ]

                };

                js.Browser.window.showOpenFilePicker(pickerOptions)

                    .then(function(handles:Array<Dynamic>) {

                        if (handles != null && handles.length > 0) self.onFileSelected(handles[0]);

                    })

                    ['catch'](function(err:Dynamic) { self.onPickerCancelled(err); });

            }

            else

            {

                self.initLegacyInput();

            }

        }

        #else

        // NATIVE TARGET (Windows / Linux / Android)

        // v1.0.1 (Task 141): mirrored from FileWriter v1.2.1 - the bridge
        // core.io.NativeDialog.openFile (GetOpenFileNameW, Stage 3): the real
        // lime Station library has no open browse method (invented in Task 140),
        // and its onOpen is typed lime.utils.Resource - caught by the compiler
        // Super A. openFile returns ONLY the path (no side effects).
        if (!NativeDialog.isSupported())

        {

            setError('Native file dialog is not supported on this target');

            return;

        }



        var pickedPath:String = NativeDialog.openFile(

            "Select File to Read",

            "All Files (*.*)|*.*|Text Files (*.txt;*.log;*.csv;*.dat)|*.txt;*.log;*.csv;*.dat",

            "");



        if (pickedPath == null || pickedPath == "")

        {

            trace('FileReaderAtom: File dialog cancelled by user.');

            return;

        }



        _filePath = pickedPath;

        loadCurrentFile();

        #end

    }



    #if html5

    private function onFileSelected(handle:Dynamic):Void

    {

        if (_isDisposed) return;

        _fileHandle = handle;

        readFromHandle(handle);

    }



    private function readFromHandle(handle:Dynamic):Void

    {

        var self = this;

        // v1.1 (Stage 4a-4): first arrayBuffer (clean bytes for [bytes]),
        // then text() (the legacy [data]; the browser UTF-8 decode with replacement -
        // the semantics are the same, so text consumers do not notice the change)
        untyped handle.getFile().then(function(f:Dynamic) {

            var size:Int = untyped f.size;

            untyped f.arrayBuffer().then(function(buf:Dynamic) {

                var raw:Bytes = Bytes.ofData(buf);

                untyped f.text().then(function(text:String) {

                    self.onLoadComplete(text, raw, size, untyped f.name);

                })['catch'](function(err:Dynamic) {

                    self.setError('Read error: ${Std.string(err)}');

                });

            })['catch'](function(err:Dynamic) {

                self.setError('Read error: ${Std.string(err)}');

            });

        })['catch'](function(err:Dynamic) {

            self.setError('File access error: ${Std.string(err)}');

        });

    }



    private function initLegacyInput():Void

    {

        // FALLBACK (legacy browsers): <input type="file"> + FileReader API.

        // v1.1: we read ArrayBuffer (clean bytes), text via TextDecoder
        // (replacing invalid sequences = the semantics of f.text())
        var self = this;

        Syntax.code("

            var input = document.createElement('input');

            input.type = 'file';

            input.onchange = function(e) {

                if (input.files && input.files.length > 0) {

                    var f = input.files[0];

                    var reader = new FileReader();

                    reader.onload = function(ev) {

                        var buf = ev.target.result;

                        var text = new TextDecoder('utf-8').decode(buf);

                        ({0})(text, buf, f.size, f.name);

                    };

                    reader.onerror = function(ev) { ({1})('Legacy read error'); };

                    reader.readAsArrayBuffer(f);

                }

            };

            input.click();

        ", function(text:String, buf:Dynamic, size:Int, name:String) {

            self.onLoadComplete(text, Bytes.ofData(buf), size, name);

        }, function(msg:String) {

            self.setError(msg);

        });

    }



    private function onPickerCancelled(err:Dynamic):Void

    {

        if (_isDisposed) return;

        _pendingOpen = false;

        trace('FileReaderAtom: File picker cancelled');

    }



    private function onLoadComplete(text:String, raw:Bytes, size:Int, name:String):Void

    {

        if (_isDisposed) return;

        _isOpenFlag = true;

        _readCount++;

        // html5: the fileName output carries the NAME (FSA gives no full path)
        updateOutputs(text, raw, name, size);

        pulseRead();

        trace('FileReaderAtom: Loaded ($size bytes)');

    }

    #end



    #if !html5

    private function loadCurrentFile():Void

    {

        if (_isDisposed) return;



        if (_filePath == null || _filePath == "")

        {

            setError("no file selected — use open first");

            return;

        }



        try {

            if (!FileSystem.exists(_filePath))

            {

                setError('File not found: $_filePath');

                return;

            }



            // v1.1 (Stage 4a-4): TWO output channels.
            // Clean bytes - File.getBytes, NO string conversions (md5 1:1;
            // the field lesson fft.png: the text pipe mangled binary files).
            // Legacy text - File.getContent, the former [data] semantics for
            // text consumers (TextArea etc.).
            var raw:Bytes = File.getBytes(_filePath);

            var content:String = File.getContent(_filePath);

            var size:Int = raw.length;



            _isOpenFlag = true;

            _readCount++;



            // The fileName output carries the FULL path (for the graph); the widget shows the name
            updateOutputs(content, raw, _filePath, size);

            pulseRead();



            trace('FileReaderAtom: Loaded $_filePath ($size bytes)');

        } catch(e:Dynamic) {

            setError('Read error: $e');

        }

    }

    #end



    /** Re-read the last selected file from disk (without a dialog). */
    public function rereadFile():Void

    {

        if (_isDisposed) return;



        #if html5

        if (_fileHandle != null)

        {

            readFromHandle(_fileHandle);

        }

        else

        {

            setError("no file selected — use open first");

        }

        #else

        loadCurrentFile();

        #end

    }



    private function closeFile():Void

    {

        if (_isDisposed) return;

        if (!_isOpenFlag) return;



        _isOpenFlag = false;

        // The data is unloaded; THE PATH IS REMEMBERED (read after close re-reads the file)
        updateOutputs("", null, "", 0);

        trace('FileReaderAtom: File closed (data unloaded, path retained)');

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



        var openC = getInput("open");

        if (openC != null && openC.value == true)

        {

            openC.value = false;

            _pendingOpen = true;

            showFilePicker();

        }



        var readC = getInput("read");

        if (readC != null && readC.value == true)

        {

            readC.value = false;

            rereadFile();

        }



        var closeC = getInput("close");

        if (closeC != null && closeC.value == true)

        {

            closeC.value = false;

            closeFile();

        }

    }



    private function updateOutputs(data:String, raw:Bytes, fileName:String, size:Int):Void

    {

        var isOpenOut = getOutput("isOpen");

        var dataOut = getOutput("data");

        var bytesOut = getOutput("bytes");

        var fileNameOut = getOutput("fileName");

        var sizeOut = getOutput("size");

        var readCountOut = getOutput("readCount");



        if (isOpenOut != null) { isOpenOut.setValueSilent(_isOpenFlag); isOpenOut.propagateCurrentValue(); }

        if (dataOut != null) { dataOut.setValueSilent(data); dataOut.propagateCurrentValue(); }



        // v1.1: the cargo race (P2 - the last portion lives on the output; each read is
        // FRESH Bytes -> a repeated issue is not swallowed by the reference dedup)
        if (bytesOut != null)

        {

            var cargo:Dynamic = (raw != null) ? Cargo.bytes(raw, fileName) : null;

            bytesOut.setValueSilent(cargo);

            bytesOut.propagateCurrentValue();

        }



        if (fileNameOut != null) { fileNameOut.setValueSilent(fileName); fileNameOut.propagateCurrentValue(); }

        if (sizeOut != null) { sizeOut.setValueSilent(size); sizeOut.propagateCurrentValue(); }

        if (readCountOut != null) { readCountOut.setValueSilent(_readCount); readCountOut.propagateCurrentValue(); }

    }



    private function pulseRead():Void

    {

        if (_isDisposed) return;

        var c = getOutput("readTick");

        if (c != null)

        {

            c.value = true;

            _readTickTimer = PULSE_DURATION;

        }

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

        trace('FileReaderAtom ERROR: $msg');

    }



    private function updatePulseTimers(dt:Float):Void

    {

        if (_isDisposed) return;



        if (_readTickTimer > 0)

        {

            _readTickTimer -= dt;

            if (_readTickTimer <= 0)

            {

                var c = getOutput("readTick");

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



    // - Public access (the mirror of the Writer) -----------------------------
    public function isOpen():Bool return _isOpenFlag;

    public function getReadCount():Int return _readCount;

    public function hasPendingOpen():Bool return _pendingOpen;



    #if !html5

    public function getFilePath():String return _filePath;

    #end

}

