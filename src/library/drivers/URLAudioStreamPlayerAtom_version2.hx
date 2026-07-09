package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType.*;
import system.managers.DriverManager;

@:buildXml('
<target id="haxe">
    <lib name="mf.lib" />
    <lib name="mfplat.lib" />
    <lib name="mfuuid.lib" />
    <lib name="ole32.lib" />
    <lib name="shlwapi.lib" />
</target>
')
@:cppFileCode('
#include "../../../../include/WMFStreamSession.h"
#include <string>
#include <map>
#include <mutex>

#ifdef ERROR
#undef ERROR
#endif
#ifdef interface
#undef interface
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif
#ifdef TRUE
#undef TRUE
#endif
#ifdef FALSE
#undef FALSE
#endif
#ifdef CALLBACK
#undef CALLBACK
#endif
#ifdef WINAPI
#undef WINAPI
#endif
#ifdef CONST
#undef CONST
#endif
#ifdef _WIN32_
#undef _WIN32_
#endif
#ifdef WIN32_LEAN_AND_MEAN
#undef WIN32_LEAN_AND_MEAN
#endif
#ifdef NOMINMAX
#undef NOMINMAX
#endif

static std::map<void*, WMFStreamSession*> _urlaudio_sessions;
static std::mutex _urlaudio_sessions_mutex;
')
class URLAudioStreamPlayerAtom extends Atom implements system.managers.Driver
{
    private var _lastUrl:String = "";
    private var _currentUrl:String = "";
    private var _lastPlayCtrl:Bool = false;
    private var _volume:Float = 1.0;
    private var _lastPlayingState:Bool = false;
    private var _lastBuffering:Bool = false;
    private var _lastError:String = "";
    private var _lastStateInt:Int = 0;

    private var _isReconnecting:Bool = false;
    private var _waitingForPlaying:Bool = false; // НОВЫЙ ФЛАГ: ожидаем ответа от асинхронного Play()
    private var _reconnectAttempts:Int = 0;
    private var _reconnectTimer:Float = 0.0;
    private static inline var MAX_RECONNECT_ATTEMPTS:Int = 10;
    private static inline var BASE_RECONNECT_DELAY:Float = 1.0;
    private static inline var MAX_RECONNECT_DELAY:Float = 30.0;
    private static inline var BUFFERING_TIMEOUT_SEC:Float = 15.0;

    public function new(id:String)
    {
        super(
            [
                new Contact("", INPUT, "url"),
                new Contact(false, INPUT, "play"),
                new Contact(1.0, INPUT, "volume")
            ],
            [
                new Contact(false, OUTPUT, "isPlaying"),
                new Contact(false, OUTPUT, "isBuffering"),
                new Contact("", OUTPUT, "error"),
                new Contact(0, OUTPUT, "state")
            ],
            null, id, "URLAudioStreamPlayer", true
        );
        init();
    }

    override public function init():Void
    {
        untyped __cpp__('
            WMFStreamSession* session = new WMFStreamSession();
            {
                std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                _urlaudio_sessions[(void*){0}.mPtr] = session;
            }
        ', this);
    }

    override public function update(dt:Float):Void
    {
        if (_isDisposed) return;

        readInputs();
        pollSessionState();

        // === RECONNECT TIMER MANAGEMENT ===
        // Таймер тикает ТОЛЬКО если мы не ждем завершения асинхронного Play()
        if (_isReconnecting && !_waitingForPlaying)
        {
            _reconnectTimer -= dt;
            if (_reconnectTimer <= 0)
            {
                executeReconnect();
            }
        }
    }

    override public function dispose():Void
    {
        untyped __cpp__('
            WMFStreamSession* session = nullptr;
            {
                std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                auto it = _urlaudio_sessions.find((void*){0}.mPtr);
                if (it != _urlaudio_sessions.end()) {
                    session = it->second;
                    _urlaudio_sessions.erase(it);
                }
            }
            if (session) {
                session->Stop();
                delete session;
            }
        ', this);
        DriverManager.getInstance().unregister(this.id);
        super.dispose();
    }

    private function readInputs():Void
    {
        var urlC = getInput("url");
        if (urlC != null && urlC.value != null)
        {
            var newUrl:String = Std.string(urlC.value);
            if (newUrl != _lastUrl)
            {
                trace('🎵 URLAudioStreamPlayer: URL changed: "${_lastUrl}" → "${newUrl}"');
                _lastUrl = newUrl;

                cancelReconnect();

                untyped __cpp__('
                WMFStreamSession* session = nullptr;
                {
                    std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                    auto it = _urlaudio_sessions.find((void*){0}.mPtr);
                    if (it != _urlaudio_sessions.end()) session = it->second;
                }
                if (session) {
                    session->Stop();
                }
                ', this);
            }
        }

        var volC = getInput("volume");
        if (volC != null && volC.value != null)
        {
            var newVol:Float = Std.parseFloat(Std.string(volC.value));
            if (!Math.isNaN(newVol) && newVol >= 0.0 && newVol <= 2.0 && newVol != _volume)
            {
                _volume = newVol;
                untyped __cpp__('
                    WMFStreamSession* session = nullptr;
                    {
                        std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                        auto it = _urlaudio_sessions.find((void*){0}.mPtr);
                        if (it != _urlaudio_sessions.end()) session = it->second;
                    }
                    if (session) session->SetVolume({1});
                ', this, _volume);
            }
        }

        var playC = getInput("play");
        if (playC != null && playC.value != null)
        {
            var newPlay:Bool = (playC.value == true);
            if (newPlay != _lastPlayCtrl)
            {
                trace('🎵 URLAudioStreamPlayer: Play control changed: ${_lastPlayCtrl} → ${newPlay}');
                _lastPlayCtrl = newPlay;

                if (newPlay)
                {
                    cancelReconnect();
                    startPlayback();
                }
                else
                {
                    cancelReconnect();
                    stopPlayback();
                }
            }
        }
    }

    private function startPlayback():Void
    {
        trace('🎵 URLAudioStreamPlayer: startPlayback() called, URL="${_lastUrl}"');

        if (_lastUrl == "" || _lastUrl == null)
        {
            trace('⚠️ URLAudioStreamPlayer: URL is empty, cannot start playback');
            return;
        }

        _currentUrl = _lastUrl;
        trace('🎵 URLAudioStreamPlayer: Starting playback for URL: ${_currentUrl}');

        untyped __cpp__('
        WMFStreamSession* session = nullptr;
        {
            std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
            auto it = _urlaudio_sessions.find((void*){0}.mPtr);
            if (it != _urlaudio_sessions.end()) session = it->second;
        }
        if (session) {
            std::string url = std::string((const char*){1}.__s);
            printf("🎵 Calling session->Play() with URL: %s\\n", url.c_str());
            bool result = session->Play(url);
            printf("🎵 session->Play() returned: %s\\n", result ? "true" : "false");
        } else {
            printf("⚠️ URLAudioStreamPlayer: Session is null!\\n");
        }
        ', this, _currentUrl);
    }

    private function stopPlayback():Void
    {
        untyped __cpp__('
            WMFStreamSession* session = nullptr;
            {
                std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                auto it = _urlaudio_sessions.find((void*){0}.mPtr);
                if (it != _urlaudio_sessions.end()) session = it->second;
            }
            if (session) {
                session->Stop();
            }
        ', this);
    }

    private function pollSessionState():Void
    {
        var cppPlaying:Bool = false;
        var cppBuffering:Bool = false;
        var cppError:String = "";
        var cppState:Int = 0;
        var cppConnectionLost:Bool = false;
        var cppBufferingTimeout:Bool = false;

        untyped __cpp__('
        WMFStreamSession* session = nullptr;
        {
            std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
            auto it = _urlaudio_sessions.find((void*){0}.mPtr);
            if (it != _urlaudio_sessions.end()) session = it->second;
        }
        if (session) {
            {1} = session->IsPlaying();
            {2} = session->IsBuffering();
            {3} = ::String(session->GetErrorMessage().c_str());
            {4} = (int)session->GetState();
            {5} = session->CheckAndResetConnectionLost();
            {6} = session->CheckBufferingTimeout({7});
        }
        ', this, cppPlaying, cppBuffering, cppError, cppState,
           cppConnectionLost, cppBufferingTimeout, Std.int(BUFFERING_TIMEOUT_SEC * 1000));

        // 1. INITIAL CONNECTION LOSS DETECTION
        if ((cppConnectionLost || cppBufferingTimeout) && _lastPlayCtrl && !_isReconnecting)
        {
            trace('🔌 URLAudioStreamPlayer: Connection lost detected! Starting reconnect...');
            startReconnect(cppError);
        }

        // 2. FAILED RECONNECT (Play() was called, but stream failed or timed out)
        if (_waitingForPlaying && (cppConnectionLost || cppBufferingTimeout))
        {
            trace('⏳ URLAudioStreamPlayer: Play() accepted, but failed to reach PLAYING. Scheduling retry...');
            _waitingForPlaying = false; // Отключаем ожидание, снова запускаем таймер
            _reconnectAttempts++;

            if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
            {
                trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
                _isReconnecting = false;
                _reconnectTimer = 0;

                var errC = getOutput("error");
                if (errC != null) { errC.setValueSilent("Connection lost. Max retries exceeded."); errC.propagateCurrentValue(); }
                var stateC = getOutput("state");
                if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
                return;
            }

            var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
            if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;
            var jitter = delay * 0.2 * (Math.random() * 2 - 1);
            delay += jitter;
            _reconnectTimer = delay;

            trace('🔄 Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');
            
            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...'); errC.propagateCurrentValue(); }
        }

        // 3. SUCCESSFUL RECONNECT
        if (_isReconnecting && cppPlaying && cppState == 2)
        {
            trace('✅ URLAudioStreamPlayer: Reconnect successful after $_reconnectAttempts attempt(s)');
            _isReconnecting = false;
            _waitingForPlaying = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;

            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }
            var stateC = getOutput("state");
            if (stateC != null) { stateC.setValueSilent(2); stateC.propagateCurrentValue(); }
        }

        // === Update output contacts ===
        if (cppPlaying != _lastPlayingState)
        {
            _lastPlayingState = cppPlaying;
            var c = getOutput("isPlaying");
            if (c != null) { c.setValueSilent(cppPlaying); c.propagateCurrentValue(); }
        }

        if (cppBuffering != _lastBuffering)
        {
            _lastBuffering = cppBuffering;
            var c = getOutput("isBuffering");
            if (c != null) { c.setValueSilent(cppBuffering); c.propagateCurrentValue(); }
        }

        if (cppError != _lastError)
        {
            _lastError = cppError;
            var c = getOutput("error");
            if (c != null) { c.setValueSilent(cppError); c.propagateCurrentValue(); }
        }

        if (cppState != _lastStateInt)
        {
            _lastStateInt = cppState;
            var c = getOutput("state");
            if (c != null) { c.setValueSilent(cppState); c.propagateCurrentValue(); }
        }
    }

    private function startReconnect(errorMsg:String):Void
    {
        if (_reconnectAttempts >= MAX_RECONNECT_ATTEMPTS)
        {
            trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
            _isReconnecting = false;

            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent("Connection lost. Max retries exceeded."); errC.propagateCurrentValue(); }
            var stateC = getOutput("state");
            if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
            return;
        }

        _isReconnecting = true;
        _waitingForPlaying = false;
        _reconnectAttempts++;

        var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
        if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;
        var jitter = delay * 0.2 * (Math.random() * 2 - 1);
        delay += jitter;
        _reconnectTimer = delay;

        trace('🔄 URLAudioStreamPlayer: Reconnect attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS in ${Math.round(delay * 10) / 10}s');

        var errC = getOutput("error");
        if (errC != null) { errC.setValueSilent('Connection lost. Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...'); errC.propagateCurrentValue(); }
        var stateC = getOutput("state");
        if (stateC != null) { stateC.setValueSilent(3); stateC.propagateCurrentValue(); }
        var bufC = getOutput("isBuffering");
        if (bufC != null) { bufC.setValueSilent(true); bufC.propagateCurrentValue(); }
    }

    private function executeReconnect():Void
    {
        if (_currentUrl == "" || _currentUrl == null)
        {
            trace('⚠️ URLAudioStreamPlayer: Cannot reconnect - no URL');
            _isReconnecting = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;
            return;
        }

        trace('🔄 URLAudioStreamPlayer: Executing reconnect attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS for URL: $_currentUrl');

        var playResult:Bool = false;

        untyped __cpp__('
        WMFStreamSession* session = nullptr;
        {
            std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
            auto it = _urlaudio_sessions.find((void*){0}.mPtr);
            if (it != _urlaudio_sessions.end()) session = it->second;
        }
        if (session) {
            // УБРАНО: session->Stop(); 
            // Play() сам вызывает TeardownSession(), который быстро и безопасно очищает старую сессию.
            // Вызов Stop() тут приводил к 1-секундным зависаниям, так как синхронно ждал MESessionClosed.
            std::string url = std::string((const char*){1}.__s);
            bool result = session->Play(url);
            {2} = result;
            printf("🔄 [URLAudio] Reconnect Play() returned: %s\\n", result ? "true" : "false");
        } else {
            printf("⚠️ [URLAudio] Reconnect: Session is null!\\n");
            {2} = false;
        }
        ', this, _currentUrl, playResult);

        if (playResult)
        {
            // Play() вернул true. Это значит WMF принял URL и начал асинхронное подключение.
            // Мы НЕ сбрасываем _reconnectAttempts и НЕ ставим таймер в 0.
            // Мы просто переводим класс в режим ожидания.
            _waitingForPlaying = true; 
            trace('✅ Play() accepted, waiting for PLAYING state...');
        }
        else
        {
            // Play() сразу вернул false (синхронная ошибка, например DNS не резолвится).
            // Планируем следующую попытку.
            _reconnectAttempts++;

            if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
            {
                trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
                _isReconnecting = false;
                _reconnectTimer = 0;

                var errC = getOutput("error");
                if (errC != null) { errC.setValueSilent("Connection lost. Max retries exceeded."); errC.propagateCurrentValue(); }
                var stateC = getOutput("state");
                if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
                return;
            }

            var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
            if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;
            var jitter = delay * 0.2 * (Math.random() * 2 - 1);
            delay += jitter;
            _reconnectTimer = delay;

            trace('⏳ Play() failed. Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');

            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...'); errC.propagateCurrentValue(); }
        }
    }

    private function cancelReconnect():Void
    {
        if (_isReconnecting)
        {
            trace('🛑 URLAudioStreamPlayer: Reconnect cancelled');
            _isReconnecting = false;
            _waitingForPlaying = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;

            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }
        }
    }
}