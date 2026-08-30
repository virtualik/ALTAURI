package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import core.types.Cargo;
import system.managers.DriverManager;
import haxe.io.Bytes;

/**
 * DATA STORAGE ATOM v1.0 (Этап 4a-2, Task 145)
 * ============================================================================
 * АТОМ-ХРАНИЛИЩЕ: вбирает в себя порции данных, приходящие на вход [data]
 * ИЗ ГРАФА (решение автора, Task 143), хранит их в едином каноническом
 * буфере (haxe.io.Bytes) и выдаёт по команде [read] — неразрушающе (ROM).
 * Spec: SPEC_STAGE4A_DATASTORAGE.md.
 *
 * Architecture: "Atom is Databank & Compute Core"
 *   data-порции (String|Bytes|Cargo) → банк → status всегда, тело по [read]
 *
 * СЕМАНТИКА (см. SPEC §2):
 *   · enabled — ВПУСКНОЙ ГЕЙТ, default FALSE (решение автора: «карман по
 *     умолчанию застёгнут»). Гасит ТОЛЬКО приём; [clear] и [read] живы всегда.
 *   · data — единая порция. Голое значение трактуется по контакту [isBytes]
 *     (false = текст, true = байты — переключатель автора, идиома «mode» у
 *     FileWriter); Cargo распаковывается сам (kind внутри, fileName в подарок).
 *     Замещение: новая порция ЗАМЕНЯЕТ старую (append — будущая эпоха).
 *   · clear — буфер в пусто (kind=empty, size=0, storeCount=0 — зеркало
 *     FileWriter.clearFile: очистка сбрасывает счётчики).
 *   · read — выдать тело: text (UTF-8, только kind=text) + bytes (копия —
 *     потребитель не испортит банк) + readTick. Неразрушающе.
 *   · Порядок в кадре: enabled → clear → data → read (сначала протереть,
 *     потом принять, потом выдать).
 *
 * ЧТО STORAGE НЕ ДЕЛАЕТ (важно): НЕ трогает диск, НЕ зовёт диалоги, НЕ знает
 * путей — ни одного платформо-зависимого ветвления, самый чистый атом семьи.
 * Весь ввод приходит по проводам; FileReader v1.0 уже кормит его текстом.
 *
 * ПЕРСИСТЕНТНОСТЬ (хвост [P] Export — решение автора, Task 143): первый
 * персистящий атом файловой тройки. getPersistentState → {enabled, kind,
 * size, storeCount, fileName, data:base64} → atomDef.values → blueprint JSON
 * → хвост ПО СУЩЕСТВУЮЩИМ рельсам Этапов 1-3 (экспортёр не менялся вовсе).
 * Гигиена П4: свыше maxTailPayload (8 МБ) в хвост едут только метаданные +
 * truncated:true — безлимитный карман опасен (урок TextArea v1.3
 * «Memory exhausted»); данные в рантайме живут до перезапуска.
 * ============================================================================
 */
class DataStorageAtom extends Atom implements system.managers.Driver
{
    private static inline var PULSE_DURATION:Float = 0.05;

    /** Kind: банк пуст. */
    private static inline var KIND_EMPTY:String = "empty";
    /** Kind: содержимое трактуется как UTF-8 текст. */
    private static inline var KIND_TEXT:String = "text";
    /** Kind: содержимое — байты (opaque binary). */
    private static inline var KIND_BINARY:String = "binary";

    /**
     * CAP хвоста [P] в СЫРЫХ байтах (~×1.37 в base64). Публичный статик —
     * управляем из тестов и будущих настроек; свыше — state.truncated=true.
     */
    public static var maxTailPayload:Int = 8 * 1024 * 1024;

    // STATE (DATABANK) — единый канонический буфер
    private var _buffer:Bytes = null;        // null = банк пуст
    private var _kind:String = KIND_EMPTY;   // empty | text | binary
    private var _fileName:String = "";       // из Cargo (если был); "" у голых порций
    private var _storeCount:Int = 0;         // число принятых порций (сброс clear'ом)
    private var _enabled:Bool = false;       // впускной гейт; DEFAULT FALSE (автор)
    private var _lastError:String = "";

    // PULSE TIMERS
    private var _storedTickTimer:Float = 0.0;
    private var _readTickTimer:Float = 0.0;
    private var _errorTimer:Float = 0.0;

    public function new(id:String)
    {
        super(
            [   // INPUTS
                new Contact(false, INPUT, "enabled"),
                new Contact(null, INPUT, "data"),
                new Contact(false, INPUT, "isBytes"),
                new Contact(false, INPUT, "clear"),
                new Contact(false, INPUT, "read")
            ],
            [   // OUTPUTS
                new Contact(false, OUTPUT, "hasData"),
                new Contact(KIND_EMPTY, OUTPUT, "kind"),
                new Contact("", OUTPUT, "text"),
                new Contact(null, OUTPUT, "bytes"),
                new Contact("", OUTPUT, "fileName"),
                new Contact(0, OUTPUT, "size"),
                new Contact(0, OUTPUT, "storeCount"),
                new Contact("", OUTPUT, "error"),
                new Contact(false, OUTPUT, "storedTick"),
                new Contact(false, OUTPUT, "readTick"),
                new Contact(false, OUTPUT, "errorTick")
            ],
            null,
            id,
            "DataStorageAtom",
            true
        );
        init();
    }

    override public function init():Void
    {
        trace('DataStorageAtom: Initialized (Main Thread)');

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
        _buffer = null;
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    // ── Приём порции ─────────────────────────────────────────────────────────

    /**
     * Принять порцию в банк. Три языка входа:
     *  1. Cargo — самодекватная посылка: kind внутри, fileName в подарок,
     *     [isBytes] игнорируется;
     *  2. голый Bytes — трактовка по [isBytes] (флаг говорит, ЧТО это за байты);
     *  3. голый String (и прочее через Std.string) — по [isBytes];
     *     строка в байтовом режиме честно конвертируется в UTF-8 байты.
     * Пустые порции ("" / 0 байт) — шум проводов, игнорируются молча.
     */
    private function storePortion(portion:Dynamic):Void
    {
        if (Cargo.isCargo(portion))
        {
            var c:Cargo = cast portion;
            if (c.data == null || c.size == 0)
            {
                setError('empty cargo rejected: ${c}');
                return;
            }
            if (c.kind == Cargo.KIND_BYTES)
            {
                _buffer = cast c.data;                 // ссылка (П3: без копий в пути)
                _kind = KIND_BINARY;
            }
            else
            {
                _buffer = Bytes.ofString(Std.string(c.data)); // свежие UTF-8 байты
                _kind = KIND_TEXT;
            }
            _fileName = c.fileName;
            acceptPortion();
            return;
        }

        var isBytesC = getInput("isBytes");
        var asBytes:Bool = (isBytesC != null && isBytesC.value == true);

        if (Std.isOfType(portion, Bytes))
        {
            _buffer = cast portion;                    // ссылка (П3)
            _kind = asBytes ? KIND_BINARY : KIND_TEXT; // флаг ТРАКТУЕТ байты (автор)
        }
        else if (Std.isOfType(portion, String))
        {
            if (asBytes)
            {
                // Толерантная конверсия: строка в байтовом режиме → UTF-8 байты
                trace('DataStorageAtom: String portion in bytes mode — converting to UTF-8 bytes');
            }
            _buffer = Bytes.ofString(cast portion);
            _kind = asBytes ? KIND_BINARY : KIND_TEXT;
        }
        else
        {
            // Толерантность: числа/прочее — строковое представление как текст
            var s:String = Std.string(portion);
            if (s == "") return;
            trace('DataStorageAtom: non-string portion (${portion}) — stored as text');
            _buffer = Bytes.ofString(s);
            _kind = KIND_TEXT;
        }

        _fileName = ""; // голая порция имени не несёт
        acceptPortion();
    }

    /** Финализация приёма: счётчик, статус-волна, импульс. */
    private function acceptPortion():Void
    {
        _storeCount++;
        pushStatus(false);
        pulseStored();
        trace('DataStorageAtom: stored ${_buffer.length} bytes (kind=$_kind, stores=$_storeCount)');
    }

    // ── Выдача и очистка ─────────────────────────────────────────────────────

    /** Выдать содержимое банка: text (UTF-8, только kind=text) + bytes (копия). */
    private function emitContents():Void
    {
        if (_buffer == null || _buffer.length == 0)
        {
            setError("storage is empty — nothing to read");
            return;
        }

        var textOut = getOutput("text");
        if (textOut != null)
        {
            var s:String = (_kind == KIND_TEXT) ? _buffer.getString(0, _buffer.length) : "";
            textOut.setValueSilent(s);
            textOut.propagateCurrentValue();
        }

        var bytesOut = getOutput("bytes");
        if (bytesOut != null)
        {
            // П3: копия при выдаче — потребитель не испортит банк, а повторная
            // выдача того же тела не будет проглочена дедупом по ссылке.
            // (копия — sub(0, length): у haxe.io.Bytes в 4.3 нет copy())
            bytesOut.setValueSilent(_buffer.sub(0, _buffer.length));
            bytesOut.propagateCurrentValue();
        }

        pulseRead();
    }

    /** Буфер в пусто. Зеркало FileWriter.clearFile: сброс и счётчиков тоже. */
    private function clearBuffer():Void
    {
        if (_buffer == null) return; // и так пусто — тишина

        _buffer = null;
        _kind = KIND_EMPTY;
        _fileName = "";
        _storeCount = 0;

        var textOut = getOutput("text");
        if (textOut != null) { textOut.setValueSilent(""); textOut.propagateCurrentValue(); }
        var bytesOut = getOutput("bytes");
        if (bytesOut != null) { bytesOut.setValueSilent(Bytes.alloc(0)); bytesOut.propagateCurrentValue(); }

        pushStatus(false);
        trace('DataStorageAtom: buffer cleared');
    }

    // ── Обработка входов (каждый кадр) ───────────────────────────────────────

    private function readInputs():Void
    {
        if (_isDisposed) return;

        // 1. enabled — впускной гейт (гасит ТОЛЬКО приём)
        var enabledC = getInput("enabled");
        if (enabledC != null && enabledC.value != null)
        {
            _enabled = (enabledC.value == true);
        }

        // 2. clear — жив и при закрытом гейте
        var clearC = getInput("clear");
        if (clearC != null && clearC.value == true)
        {
            clearC.value = false;
            clearBuffer();
        }

        // 3. data — приём порции (гейтится enabled)
        var dataC = getInput("data");
        if (dataC != null && dataC.value != null)
        {
            var portion:Dynamic = dataC.value;
            var noise:Bool = (portion == null)
                || (Std.isOfType(portion, String) && portion == "")
                || (Std.isOfType(portion, Bytes) && portion.length == 0);
            if (!noise)
            {
                // Идиома П1 «принял — очисти»: гасим ДО обработки, чтобы
                // следующий кадр не принял порцию дважды (урок FileWriter.write)
                dataC.setValueSilent(null);
                if (_enabled)
                {
                    storePortion(portion);
                }
                else
                {
                    trace('DataStorageAtom: gate closed — portion passed by');
                }
            }
        }

        // 4. read — жив и при закрытом гейте; в кадре ПОСЛЕ приёма
        var readC = getInput("read");
        if (readC != null && readC.value == true)
        {
            readC.value = false;
            emitContents();
        }
    }

    // ── Статусные выходы ─────────────────────────────────────────────────────

    /**
     * Разнести статус: hasData/kind/size/storeCount/fileName.
     * silent=true — восстановление: провода ещё не связаны, link() разнесёт
     * значения сам при построении (дисциплина Load-Symmetric Reconstruction).
     */
    private function pushStatus(silent:Bool):Void
    {
        var has:Bool = (_buffer != null && _buffer.length > 0);
        setOut("hasData", has, silent);
        setOut("kind", _kind, silent);
        setOut("size", has ? _buffer.length : 0, silent);
        setOut("storeCount", _storeCount, silent);
        setOut("fileName", _fileName, silent);
    }

    private function setOut(name:String, value:Dynamic, silent:Bool):Void
    {
        var c = getOutput(name);
        if (c == null) return;
        c.setValueSilent(value);
        if (!silent) c.propagateCurrentValue();
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
        trace('DataStorageAtom ERROR: $msg');
    }

    private function pulseStored():Void
    {
        if (_isDisposed) return;
        var c = getOutput("storedTick");
        if (c != null)
        {
            c.value = true;
            _storedTickTimer = PULSE_DURATION;
        }
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

    private function updatePulseTimers(dt:Float):Void
    {
        if (_isDisposed) return;

        if (_storedTickTimer > 0)
        {
            _storedTickTimer -= dt;
            if (_storedTickTimer <= 0)
            {
                var c = getOutput("storedTick");
                if (c != null) c.value = false;
            }
        }
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

    // ── ПЕРСИСТЕНТНОСТЬ (хвост [P]; шов Atom.hx:375) ─────────────────────────

    /**
     * Сохранение состояния в values-JSON схемы → хвост прибора.
     * Все поля JSON-безопасны (bool/int/string); data — base64 строки.
     * Свыше maxTailPayload — только метаданные + truncated:true (гигиена П4).
     */
    override public function getPersistentState():Dynamic
    {
        var state:Dynamic = super.getPersistentState();
        if (state == null) state = {};

        state.enabled = _enabled;
        state.storeCount = _storeCount;
        state.kind = _kind;
        state.size = (_buffer != null) ? _buffer.length : 0;
        state.fileName = _fileName;

        if (_buffer != null && _buffer.length > 0)
        {
            if (_buffer.length <= maxTailPayload)
            {
                state.data = haxe.crypto.Base64.encode(_buffer);
            }
            else
            {
                state.truncated = true;
            }
        }
        return state;
    }

    /**
     * Восстановление из values-JSON (толерантное): нет поля — банк пуст;
     * битый base64 — банк пуст + честная ошибка, прибор НЕ падает.
     * Статус разносится ТИХО (silent) — провода построятся позже.
     */
    override public function restoreState(state:Dynamic):Void
    {
        super.restoreState(state);
        if (state == null) return;

        if (Reflect.hasField(state, "enabled")) _enabled = (state.enabled == true);
        if (Reflect.hasField(state, "storeCount")) _storeCount = Std.int(state.storeCount);
        _fileName = Reflect.hasField(state, "fileName") ? Std.string(state.fileName) : "";

        _buffer = null;
        _kind = KIND_EMPTY;

        if (Reflect.hasField(state, "data"))
        {
            try
            {
                var b:Bytes = haxe.crypto.Base64.decode(Std.string(state.data));
                if (b.length > 0)
                {
                    _buffer = b;
                    var k:String = Std.string(state.kind);
                    _kind = (k == KIND_TEXT || k == KIND_BINARY) ? k : KIND_BINARY;
                }
            }
            catch (e:Dynamic)
            {
                _buffer = null;
                _kind = KIND_EMPTY;
                setError('restore failed: corrupt base64 payload');
            }
        }
        else if (Reflect.hasField(state, "truncated"))
        {
            setError('payload was truncated on export — data not restored');
        }

        pushStatus(true);
        trace('DataStorageAtom: state restored (kind=$_kind, size=${_buffer != null ? _buffer.length : 0})');
    }

    // ── Публичный доступ (зеркало семьи) ─────────────────────────────────────
    public function hasData():Bool return (_buffer != null && _buffer.length > 0);
    public function getStoreCount():Int return _storeCount;
    public function getKind():String return _kind;
    public function getFileName():String return _fileName;
    public function isEnabled():Bool return _enabled;
    /** Копия тела банка (для будущих потребителей вроде PictureAtom); null если пусто. */
    public function getBufferCopy():Bytes return (_buffer != null) ? _buffer.sub(0, _buffer.length) : null;
}
