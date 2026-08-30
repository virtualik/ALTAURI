package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;

// Платформо-зависимые импорты (зеркало FileWriterAtom)
#if html5
import js.Syntax;
#else
import sys.io.File;
import sys.FileSystem;
import core.io.NativeDialog;
#end

/**
 * FILE READER ATOM v1.1 (Этап 4a-1 Task 140 + Этап 4a-4 Task 146)
 * ============================================================================
 * ЗЕРКАЛО FileWriterAtom: та же архитектура, те же идиомы, перевёрнутая
 * семантика (запись → чтение). Spec: SPEC_STAGE4A_FILEREADER.md.
 *
 * Architecture: "Atom is Databank & Compute Core"
 *   open/close/read (импульсы) → диалог/диск → data/bytes/fileName/size (+тики)
 *
 * ДВА КАНАЛА ВЫДАЧИ (v1.1, Этап 4a-4 «БИНАРНАЯ ТРУБА»):
 *   · [data]  (String) — ЛЕГАСИ-текстовый канал (File.getContent). Для текстовых
 *     файлов честен; БИНАРНЫЕ файлы калечит UTF-8-конверсия рантайма (hxcpp):
 *     полевой баг-репорт Alik fft.png — магия PNG 89 50 4E 47 превращается
 *     в C9 90 4E 47, тело обрастает U+FFFD. Канал оставлен для совместимости
 *     (TextArea и прочие текстовые потребители), для бинарного — [bytes].
 *   · [bytes] (Cargo)   — ЧИСТЫЙ байтовый канал (File.getBytes, БЕЗ конверсий):
 *     Cargo{kind:bytes, data:Bytes, fileName, size} — байт-в-байт md5 1:1.
 *     DataStorageAtom v1.0 распаковывает Cargo сам (kind+fileName в подарок),
 *     FileWriterAtom v1.3 принимает Cargo/Bytes на [write]/[append].
 *
 * СЕМАНТИКА (см. SPEC §2):
 *   · open  → нативный диалог выбора (NativeDialog.openFile — ТОЛЬКО путь,
 *     никаких побочных эффектов; брат FileWriter v1.2.1, Task 141) → файл
 *     читается с диска немедленно → эмит выходов + readTick.
 *   · read  → перечитать последний выбранный путь с диска (без диалога).
 *   · close → выгрузить данные (data="", bytes=null, fileName="", size=0,
 *     isOpen=false); ПУТЬ ПОМНИТСЯ: read после close перечитает тот же файл.
 *
 * ЧТО READER НЕ ДЕЛАЕТ (важно): НЕ хранит содержимое в схеме/хвосте —
 * файл читается с диска в рантайме; прибор без файла рядом даёт честную
 * ошибку. Вбирание данных в прибор — DataStorageAtom (Этап 4a-2).
 *
 * Персистентность: сессионная (как у Писателя) — путь между сеансами не
 * сохраняется.
 * ============================================================================
 */
class FileReaderAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;

    // STATE (DATABANK)
    private var _isOpenFlag:Bool = false;      // файл загружен
    private var _readCount:Int = 0;            // число успешных чтений
    private var _enabled:Bool = true;
    private var _lastError:String = "";
    private var _pendingOpen:Bool = false;

    #if html5
    // FILE SYSTEM ACCESS API FIELDS
    private var _fileHandle:Dynamic = null;
    #else
    // NATIVE FILE SYSTEM FIELDS
    private var _filePath:String = null;       // полный путь последнего выбора
    #end

    // PULSE TIMERS
    private var _readTickTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [   // INPUTS (зеркальный стиль FileWriterAtom)
                new Contact(false, INPUT, "open"),
                new Contact(false, INPUT, "close"),
                new Contact(false, INPUT, "read"),
                new Contact(true, INPUT, "enabled")
            ],
            [   // OUTPUTS
                new Contact(false, OUTPUT, "isOpen"),
                new Contact("", OUTPUT, "data"),      // легаси-текст (UTF-8 конверсия)
                new Contact(null, OUTPUT, "bytes"),    // v1.1: Cargo — чистые байты (md5 1:1)
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
        #if html5
        _fileHandle = null;
        #end

        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    /**
     * Show open-file picker; on selection the file is loaded immediately.
     * HTML5: File System Access API (+ legacy <input type="file"> fallback).
     * Native: core.io.NativeDialog.openFile (мост Этапа 3) — ТОЛЬКО путь.
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
        // v1.0.1 (Task 141): зеркально FileWriter v1.2.1 — мост
        // core.io.NativeDialog.openFile (GetOpenFileNameW, Этап 3): в реальной
        // lime-библиотеке Станции нет browse-метода открытия (выдумка Task 140),
        // а её onOpen типизирован lime.utils.Resource — поймано компилятором
        // Super A. openFile возвращает ТОЛЬКО путь (никаких побочных эффектов).
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
        // v1.1 (Этап 4a-4): сначала arrayBuffer (чистые байты для [bytes]),
        // затем text() (легаси [data]; браузерный UTF-8-декод с заменой —
        // семантика прежняя, чтобы текстовые потребители не заметили смену)
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
        // v1.1: читаем ArrayBuffer (чистые байты), текст — TextDecoder'ом
        // (замена невалидных последовательностей = семантика f.text())
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
                        {0}(text, buf, f.size, f.name);
                    };
                    reader.onerror = function(ev) { {1}('Legacy read error'); };
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
        // html5: fileName-выход несёт ИМЯ (полного пути FSA не даёт)
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

            // v1.1 (Этап 4a-4): ДВА канала выдачи.
            // Чистые байты — File.getBytes, БЕЗ строковых конверсий (md5 1:1;
            // полевой урок fft.png: текстовая труба калечила бинарные файлы).
            // Легаси-текст — File.getContent, прежняя семантика [data] для
            // текстовых потребителей (TextArea и пр.).
            var raw:Bytes = File.getBytes(_filePath);
            var content:String = File.getContent(_filePath);
            var size:Int = raw.length;

            _isOpenFlag = true;
            _readCount++;

            // fileName-выход несёт ПОЛНЫЙ путь (для графа); виджет покажет имя
            updateOutputs(content, raw, _filePath, size);
            pulseRead();

            trace('FileReaderAtom: Loaded $_filePath ($size bytes)');
        } catch(e:Dynamic) {
            setError('Read error: $e');
        }
    }
    #end

    /** Перечитать последний выбранный файл с диска (без диалога). */
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
        // Данные выгружаются; ПУТЬ ПОМНИТСЯ (read после close перечитает файл)
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

        // v1.1: карго-рейс (П2 — последняя порция живёт на выходе; каждый read —
        // СВЕЖИЙ Bytes → повторная выдача не глотится дедупом по ссылке)
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

    // ── Публичный доступ (зеркало Писателя) ────────────────────────────────
    public function isOpen():Bool return _isOpenFlag;
    public function getReadCount():Int return _readCount;
    public function hasPendingOpen():Bool return _pendingOpen;

    #if !html5
    public function getFilePath():String return _filePath;
    #end
}
