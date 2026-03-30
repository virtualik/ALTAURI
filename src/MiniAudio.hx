#if cpp
@:buildXml('
    <target id="haxe">
        <compilerflag value="/Iinclude"/>
    </target>
')
@:include("miniaudio.h")
extern class MiniAudio
{
    // === CONSTANTS (enum values as Int) ===
    @:native("ma_device_type_capture") 
    public static var DEVICE_TYPE_CAPTURE(default, never):Int;
    
    @:native("ma_format_f32")
    public static var FORMAT_F32(default, never):Int;
    
    @:native("MA_SUCCESS")
    public static var SUCCESS(default, never):Int;

    // === CONTEXT ===
    @:native("ma_context_init")
    public static function contextInit(
        backends:cpp.RawPointer<cpp.Void>,
        backendCount:cpp.UInt32,
        config:cpp.RawPointer<cpp.Void>,
        context:cpp.RawPointer<cpp.Void>
    ):Int;

    @:native("ma_context_uninit")
    public static function contextUninit(context:cpp.RawPointer<cpp.Void>):Void;

    // === DEVICE CONFIG ===
    // Возвращаем структуру по значению (не указатель!)
    @:native("ma_device_config_init")
    public static function deviceConfigInit(deviceType:Int):MaDeviceConfig;
    
    @:native("ma_device_config_init_capture")
    public static function deviceConfigInitCapture(deviceType:Int):MaDeviceConfig;

    // === DEVICE ===
    @:native("ma_device_init")
    public static function deviceInit(
        context:cpp.RawPointer<cpp.Void>,
        config:cpp.RawPointer<MaDeviceConfig>,
        device:cpp.RawPointer<cpp.Void>
    ):Int;

    @:native("ma_device_start")
    public static function deviceStart(device:cpp.RawPointer<cpp.Void>):Int;

    @:native("ma_device_stop")
    public static function deviceStop(device:cpp.RawPointer<cpp.Void>):Int;

    @:native("ma_device_uninit")
    public static function deviceUninit(device:cpp.RawPointer<cpp.Void>):Void;
    
    // === CALLBACK REGISTRATION (через void* + cast) ===
    @:native("ma_device_set_data_callback")
    public static function deviceSetDataCallback(
        device:cpp.RawPointer<cpp.Void>,
        callback:cpp.RawPointer<cpp.Void>,
        pUserData:cpp.RawPointer<cpp.Void>
    ):Void;
}

// === OPAQUE STRUCTS (только указатели, без @:structAccess) ===
@:native("ma_context") @:unreflective extern class MaContext {}
@:native("ma_device") @:unreflective extern class MaDevice {}
@:native("ma_config") @:unreflective extern class MaConfig {}

// === FLATTENED STRUCT for ma_device_config ===
// miniaudio использует вложенные структуры, но Haxe не поддерживает
// @:structAccess с вложенными @:structAccess классами.
// Поэтому "расплющиваем" поля через суффиксы.
@:native("ma_device_config") @:structAccess @:unreflective extern class MaDeviceConfig
{
    // Основные поля
    var deviceType:Int;
    var sampleRate:cpp.UInt32;
    var periodSizeInFrames:cpp.UInt32;
    var periodSizeInMilliseconds:cpp.UInt32;
    var periods:cpp.UInt32;
    var performanceProfile:cpp.UInt32;
    var noPreSilencedOutputBuffer:cpp.UInt32;
    var noClip:cpp.UInt32;
    var noFixedSizedCallback:cpp.UInt32;
    
    // === FLATTENED capture.* поля ===
    var capture_format:Int;
    var capture_channels:cpp.UInt32;
    var capture_shareMode:Int;
    
    // === FLATTENED playback.* поля ===
    var playback_format:Int;
    var playback_channels:cpp.UInt32;
    var playback_shareMode:Int;
    
    // Callback как void* (реальная сигнатура слишком сложна для extern)
    var dataCallback:cpp.RawPointer<cpp.Void>;
    var pUserData:cpp.RawPointer<cpp.Void>;
    
    // Вспомогательные методы для установки значений (опционально, для удобства)
    @:native("capture_format") public function set_capture_format(v:Int):Void;
    @:native("capture_channels") public function set_capture_channels(v:cpp.UInt32):Void;
    @:native("playback_format") public function set_playback_format(v:Int):Void;
    @:native("playback_channels") public function set_playback_channels(v:cpp.UInt32):Void;
}

// === CALLBACK TYPE (для документации, не используется напрямую в extern) ===
// typedef MaDataCallback = cpp.Function<cpp.Void, 
//     cpp.RawPointer<MaDevice>, 
//     cpp.RawPointer<cpp.Void>, 
//     cpp.ConstRawPointer<cpp.Void>, 
//     cpp.UInt32>;
#end