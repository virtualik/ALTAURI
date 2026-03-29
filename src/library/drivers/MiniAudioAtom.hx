package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.logic.TickGenerator;
import core.types.ContactType.*;
import system.managers.DriverManager;
import audio.MiniAudio;

/**
 * MINI AUDIO ATOM v1.1 (Thread-Safe & Optimized Batching)
 *
 * Двойное назначение:
 *   А) Захват аудиопотока с квантованием → Contact "sample"
 *   Б) Источник точного тактирования    → Contact "tick"
 *
 * Потоки и Межпоточный обмен (v1.1):
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   OS Audio Thread                    Main Thread (TickGenerator)        │
 * │                                                                         │
 * │   audioCallback()                                                      │
 * │     ├─ Обработка буфера                                                │
 * │     ├─ Квантование                                                     │
 * │     └─ scheduleNextTick() ──────► LockFreeQueue (безопасная передача)   │
 * │                                       │                                │
 * │                                       ▼                                │
 * │                               flushPendingInputs()                     │
 * │                                       │                                │
 * │                                       ▼                                │
 * │                               Выполнение замыкания:                    │
 * │                                 ├─ setValueSilent() x7 (мгновенно)     │
 * │                                 └─ propagateCurrentValue() x N (раз)   │
 * │                                                                      │
 * │   readInputs()  ◄──────────────── DriverManager.update() (безопасно)   │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * Входные контакты (настройки):
 *   "mode"     Int    0=mic, 1=loopback, 2=file
 *   "quantum"  Float  шаг квантования 0.001..1.0
 *   "gain"     Float  усиление 0.0..4.0
 *   "channel"  Int    0=mix, 1=left, 2=right
 *   "rate"     Int    0=44100, 1=48000, 2=96000
 *
 * Выходные контакты:
 *   "sample"   Float  квантованная выборка -1..1
 *   "changed"  Bool   импульс при смене кванта
 *   "rms"      Float  среднеквадратичный уровень 0..1
 *   "clip"     Bool   перегрузка
 *   "tick"     Bool   импульс каждый аудиобуфер (такт)
 *   "level"    Float  уровень в dBFS
 *   "device"   String имя устройства
 */
class MiniAudioAtom extends Atom implements system.managers.Driver
{
    // =========================================================================
    // КОНСТАНТЫ
    // =========================================================================

    private static inline var MIN_QUANTUM:Float  = 0.001;
    private static inline var MAX_QUANTUM:Float  = 1.0;
    private static inline var CLIP_THRESHOLD:Float = 0.99;
    private static inline var PULSE_DURATION:Float = 0.05;

    private static inline var MODE_MIC:Int      = 0;
    private static inline var MODE_LOOPBACK:Int = 1;

    private static var SAMPLE_RATES:Array<Int> = [44100, 48000, 96000];

    // =========================================================================
    // MINIAUDIO СОСТОЯНИЕ
    // =========================================================================

    private var _device:MaDevice;
    private var _context:MaContext;
    private var _deviceReady:Bool = false;

    // =========================================================================
    // ПАРАМЕТРЫ (читаются из входных контактов)
    // =========================================================================

    private var _mode:Int        = MODE_MIC;
    private var _quantum:Float   = 0.01;
    private var _gain:Float      = 1.0;
    private var _channel:Int     = 0;      // 0=mix
    private var _sampleRateIdx:Int = 0;    // индекс в SAMPLE_RATES

    // =========================================================================
    // СОСТОЯНИЕ КВАНТОВАНИЯ
    // =========================================================================

    private var _lastQuantum:Float   = 0.0;
    private var _isFirstSample:Bool  = true;

    // =========================================================================
    // RMS БУФЕР (кольцевой, заполняется из аудиопотока)
    // =========================================================================

    private static inline var RMS_BUFFER_SIZE:Int = 1024;
    private var _rmsBuffer:Array<Float>;
    private var _rmsIndex:Int = 0;
    private var _rmsSum:Float = 0.0;

    // =========================================================================
    // PULSE ТАЙМЕРЫ
    // =========================================================================

    private var _changedTimer:Float = 0.0;
    private var _tickTimer:Float    = 0.0;
    private var _clipTimer:Float    = 0.0;

    // =========================================================================
    // КОНСТРУКТОР
    // =========================================================================

    public function new(id:String)
    {
        super(
            [ // === ВХОДЫ (настройки) ===
                new Contact(MODE_MIC, INPUT, "mode"),
                new Contact(0.01,     INPUT, "quantum"),
                new Contact(1.0,      INPUT, "gain"),
                new Contact(0,        INPUT, "channel"),
                new Contact(0,        INPUT, "rate")
            ],
            [ // === ВЫХОДЫ ===
                new Contact(0.0,   OUTPUT, "sample"),
                new Contact(false, OUTPUT, "changed"),
                new Contact(0.0,   OUTPUT, "rms"),
                new Contact(false, OUTPUT, "clip"),
                new Contact(false, OUTPUT, "tick"),
                new Contact(0.0,   OUTPUT, "level"),
                new Contact("",    OUTPUT, "device")
            ],
            null,  // нет process функции — всё через Driver.update()
            id,
            "MiniAudioAtom",
            true   // isActive → регистрируемся в DriverManager
        );

        var sampleOut = getOutput("sample");
        if (sampleOut != null) sampleOut.ignoreOscillation = true;

        _rmsBuffer = [for (i in 0...RMS_BUFFER_SIZE) 0.0];

        trace('MiniAudioAtom: Created (id: $id)');
    }

    // =========================================================================
    // DRIVER INTERFACE
    // =========================================================================

    override public function init():Void
    {
        readInputs();
        openDevice();
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        readInputs();
        updatePulseTimers(dt);
    }

    override public function dispose():Void
    {
        closeDevice();
        DriverManager.getInstance().unregister(this.id);
        super.dispose(); // Устанавливает _isDisposed = true (volatile)
        trace('MiniAudioAtom: Disposed');
    }

    // =========================================================================
    // ОТКРЫТИЕ / ЗАКРЫТИЕ УСТРОЙСТВА
    // =========================================================================

    private function openDevice():Void
    {
        var err = MiniAudio.contextInit(null, 0, null,
            cpp.RawPointer.addressOf(_context));

        if (err != MaResult.MA_SUCCESS)
        {
            trace('MiniAudioAtom: context init failed');
            setDeviceNameOutput("ERROR: no context");
            return;
        }

        var sampleRate = SAMPLE_RATES[_sampleRateIdx];

        var config = MiniAudio.deviceConfigInit(
            _mode == MODE_LOOPBACK
                ? MaDeviceType.Loopback
                : MaDeviceType.Capture
        );

        config.sampleRate         = sampleRate;
        config.periodSizeInFrames = 256;
        config.capture.format     = MaFormat.f32;
        config.capture.channels   = 2;
        config.dataCallback       = cpp.Callable.fromStaticFunction(audioCallback);
        config.pUserData          = cpp.RawPointer.fromHandle(this);

        err = MiniAudio.deviceInit(
            cpp.RawPointer.addressOf(_context),
            cpp.RawPointer.addressOf(config),
            cpp.RawPointer.addressOf(_device)
        );

        if (err != MaResult.MA_SUCCESS)
        {
            trace('MiniAudioAtom: device init failed: $err');
            setDeviceNameOutput("ERROR: no device");
            MiniAudio.contextUninit(cpp.RawPointer.addressOf(_context));
            return;
        }

        err = MiniAudio.deviceStart(cpp.RawPointer.addressOf(_device));
        if (err != MaResult.MA_SUCCESS)
        {
            trace('MiniAudioAtom: device start failed');
            MiniAudio.deviceUninit(cpp.RawPointer.addressOf(_device));
            MiniAudio.contextUninit(cpp.RawPointer.addressOf(_context));
            return;
        }

        _deviceReady = true;

        setDeviceNameOutput(
            _mode == MODE_LOOPBACK ? "Loopback" : "Capture @ " + sampleRate + "Hz"
        );

        trace('MiniAudioAtom: Device opened. Mode=$_mode, Rate=$sampleRate');
    }

    private function closeDevice():Void
    {
        if (!_deviceReady) return;
        MiniAudio.deviceStop(cpp.RawPointer.addressOf(_device));
        MiniAudio.deviceUninit(cpp.RawPointer.addressOf(_device));
        MiniAudio.contextUninit(cpp.RawPointer.addressOf(_context));
        _deviceReady = false;
    }

    // =========================================================================
    // AUDIO CALLBACK (аудио поток ОС)
    // =========================================================================

    /**
     * Вызывается СТРОГО каждые periodSizeInFrames сэмплов.
     * Правила: никаких аллокаций, блокировок, trace.
     */
    private static function audioCallback(
        device:cpp.RawPointer<MaDevice>,
        output:cpp.RawPointer<cpp.Void>,
        input:cpp.RawPointer<cpp.Void>,
        frames:cpp.UInt32
    ):Void
    {
        var self:MiniAudioAtom = cpp.RawPointer.toHandle(
            untyped __cpp__('{0}->pUserData', device)
        );
        
        // v7.0: Чтение volatile флага безопасно
        if (self == null || self._isDisposed) return;

        var samples:cpp.Pointer<cpp.Float32> = cast input;
        if (samples == null) return;

        var bufferSample:Float = 0.0;
        var rmsAccum:Float     = 0.0;
        var clip:Bool          = false;

        var i = 0;
        while (i < frames)
        {
            var left:Float  = samples[i * 2]     * self._gain;
            var right:Float = samples[i * 2 + 1] * self._gain;

            var mono:Float = switch (self._channel)
            {
                case 1:  left;
                case 2:  right;
                default: (left + right) * 0.5;
            }

            if (mono >  1.0) { mono =  1.0; clip = true; }
            if (mono < -1.0) { mono = -1.0; clip = true; }

            rmsAccum += mono * mono;
            bufferSample = mono;
            i++;
        }

        var bufferMean = rmsAccum / frames;
        self._rmsSum -= self._rmsBuffer[self._rmsIndex];
        self._rmsBuffer[self._rmsIndex] = bufferMean;
        self._rmsSum += bufferMean;
        self._rmsIndex = (self._rmsIndex + 1) % RMS_BUFFER_SIZE;
        var rms = Math.sqrt(self._rmsSum / RMS_BUFFER_SIZE);

        var quantum   = self._quantum;
        var quantized = Math.round(bufferSample / quantum) * quantum;
        if (quantized >  1.0) quantized =  1.0;
        if (quantized < -1.0) quantized = -1.0;

        var changed = (!self._isFirstSample && quantized != self._lastQuantum);
        self._lastQuantum  = quantized;
        self._isFirstSample = false;

        // Снэпшот данных для замыкания
        var snapSample  = quantized;
        var snapRms     = rms;
        var snapClip    = clip;
        var snapChanged = changed;

        // v1.1: Передача через LockFreeQueue (потокобезопасно)
        TickGenerator.getInstance().scheduleNextTick(function()
        {
            if (self._isDisposed) return;

            // ============================================================
            // v5.8 PROTOCOL: БАТЧЕВОЕ ОБНОВЛЕНИЕ БЕЗ НАГРУЗКИ НА ОЧЕРЕДЬ
            // ============================================================
            
            // 1. Тихо заполняем все выходы (setValueSilent не триггерит TickGenerator)
            var sampleOut = self.getOutput("sample");
            if (sampleOut != null) sampleOut.setValueSilent(snapSample);

            var rmsOut = self.getOutput("rms");
            if (rmsOut != null) rmsOut.setValueSilent(snapRms);

            var levelOut = self.getOutput("level");
            if (levelOut != null)
            {
                var db = snapRms > 0.0001
                    ? 20.0 * Math.log(snapRms) / Math.log(10)
                    : -120.0;
                levelOut.setValueSilent(db);
            }

            // 2. Управление импульсами (остается через обычный сеттер, 
            //    так как это происходит редко и не грузит систему)
            var tickOut = self.getOutput("tick");
            if (tickOut != null)
            {
                tickOut.value = true; 
                self._tickTimer = PULSE_DURATION;
            }

            if (snapChanged)
            {
                var changedOut = self.getOutput("changed");
                if (changedOut != null)
                {
                    changedOut.value = true;
                    self._changedTimer = PULSE_DURATION;
                }
            }

            if (snapClip)
            {
                var clipOut = self.getOutput("clip");
                if (clipOut != null)
                {
                    clipOut.value = true;
                    self._clipTimer = PULSE_DURATION;
                }
            }

            // 3. Единая точка распространения для непрерывных данных
            // Вызываем propagation вручную только для тех контактов, 
            // которые действительно могут иметь связи (sample, rms, level)
            if (sampleOut != null) sampleOut.propagateCurrentValue();
            if (rmsOut != null) rmsOut.propagateCurrentValue();
            if (levelOut != null) levelOut.propagateCurrentValue();
        });
    }

    // =========================================================================
    // PULSE ТАЙМЕРЫ (главный поток)
    // =========================================================================

    private function updatePulseTimers(dt:Float):Void
    {
        if (_tickTimer > 0)
        {
            _tickTimer -= dt;
            if (_tickTimer <= 0) { var c = getOutput("tick"); if (c != null) c.value = false; }
        }

        if (_changedTimer > 0)
        {
            _changedTimer -= dt;
            if (_changedTimer <= 0) { var c = getOutput("changed"); if (c != null) c.value = false; }
        }

        if (_clipTimer > 0)
        {
            _clipTimer -= dt;
            if (_clipTimer <= 0) { var c = getOutput("clip"); if (c != null) c.value = false; }
        }
    }

    // =========================================================================
    // ЧТЕНИЕ ВХОДОВ
    // =========================================================================

    private function readInputs():Void
    {
        var modeC    = getInput("mode");
        var quantumC = getInput("quantum");
        var gainC    = getInput("gain");
        var channelC = getInput("channel");
        var rateC    = getInput("rate");

        if (modeC    != null && modeC.value    != null) _mode        = Std.int(modeC.value);
        if (gainC    != null && gainC.value    != null) _gain        = gainC.value;
        if (channelC != null && channelC.value != null) _channel     = Std.int(channelC.value);
        
        if (rateC != null && rateC.value != null)
        {
            var idx = Std.int(rateC.value);
            // v1.1: Защита от выхода за пределы массива SAMPLE_RATES
            if (idx >= 0 && idx < SAMPLE_RATES.length) _sampleRateIdx = idx;
        }

        if (quantumC != null && quantumC.value != null)
        {
            var q:Float = quantumC.value;
            if (q >= MIN_QUANTUM && q <= MAX_QUANTUM) _quantum = q;
        }
    }

    // =========================================================================
    // УТИЛИТЫ
    // =========================================================================

    private function setDeviceNameOutput(name:String):Void
    {
        var c = getOutput("device");
        if (c != null) c.value = name;
    }

    public function restart():Void
    {
        closeDevice();
        _isFirstSample = true;
        _rmsSum = 0.0;
        _rmsIndex = 0;
        for (i in 0...RMS_BUFFER_SIZE) _rmsBuffer[i] = 0.0;
        openDevice();
    }
}