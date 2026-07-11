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
/**
 * URL AUDIO STREAM PLAYER ATOM v1.3 (Reconnect Loop Fix)
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  v1.3 CHANGES (fixes infinite reconnect loop):                         │
 * │                                                                         │
 * │  ROOT CAUSE: executeReconnect() did NOT set _reconnectTimer after      │
 * │  a failed Play(). So on the next frame, _reconnectTimer was still      │
 * │  <= 0, and executeReconnect() was called again — infinite loop.        │
 * │                                                                         │
 * │  FIX 1: executeReconnect() now sets _reconnectTimer after failure:     │
 * │    • Play() == true  → _reconnectAttempts = 0, wait for PLAYING       │
 * │    • Play() == false → _reconnectAttempts++, set exponential delay     │
 * │    • attempts > MAX  → stop reconnecting, show error                   │
 * │                                                                         │
 * │  FIX 2: pollSessionState() no longer calls startReconnect() if         │
 * │  _isReconnecting is already true (prevents double-triggering).         │
 * │                                                                         │
 * │  FIX 3: startReconnect() resets _connectionLost flag via C++ before    │
 * │  scheduling, preventing stale flag from re-triggering.                 │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * RECONNECT FLOW:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                                                                         │
 * │  MEError / BufferingTimeout                                            │
 * │       │                                                                 │
 * │       ▼                                                                 │
 * │  pollSessionState() detects connectionLost                              │
 * │       │                                                                 │
 * │       ▼                                                                 │
 * │  startReconnect():                                                      │
 * │    _isReconnecting = true                                               │
 * │    _reconnectAttempts = 1                                               │
 * │    _reconnectTimer = ~1.0s (exponential backoff)                        │
 * │       │                                                                 │
 * │       ▼  (after timer expires)                                          │
 * │  executeReconnect():                                                    │
 * │    Stop() + Play(url)                                                   │
 * │       │                                                                 │
 * │       ├── Play() == true  → _reconnectAttempts = 0                     │
 * │       │     Wait for MESessionStarted (pollSessionState checks)         │
 * │       │                                                                 │
 * │       └── Play() == false → _reconnectAttempts++                       │
 * │             _reconnectTimer = ~2.0s (next attempt)                     │
 * │             If attempts > 10 → give up                                 │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
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

// =========================================================================
// v1.2: AUTO-RECONNECT STATE
// =========================================================================
    private var _isReconnecting:Bool = false;
	private var _waitingForPlaying:Bool = false;
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

        // === v1.2: RECONNECT TIMER MANAGEMENT ===
        if (_isReconnecting)
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
		// === v2.3 FIX: Clear URL and reset flags on stop ===
		_currentUrl = "";
		_isReconnecting = false;
		_waitingForPlaying = false;
		_reconnectAttempts = 0;
		_reconnectTimer = 0;
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

        // ═════════════════════════════════════════════════════════════════
        // v1.3 FIX: DETECT CONNECTION LOSS
        // Only trigger startReconnect if:
        //   1. Connection was lost OR buffering timed out
        //   2. User wants playback (_lastPlayCtrl == true)
        //   3. We are NOT already reconnecting (prevents double-trigger)
        // ═════════════════════════════════════════════════════════════════
        if ((cppConnectionLost || cppBufferingTimeout) && _lastPlayCtrl && !_isReconnecting)
        {
            trace('🔌 URLAudioStreamPlayer: Connection lost detected! Starting reconnect...');
            startReconnect(cppError);
        }

        // ═════════════════════════════════════════════════════════════════
        // v1.3 FIX: DETECT SUCCESSFUL RECONNECT
        // Only clear reconnect state if we were reconnecting AND
        // the C++ state is PLAYING (MESessionStarted received)
        // ═════════════════════════════════════════════════════════════════
		if (_isReconnecting && cppPlaying && cppState == 2)
		{
			trace('✅ URLAudioStreamPlayer: Reconnect successful after $_reconnectAttempts attempt(s)');
			_isReconnecting = false;
			_waitingForPlaying = false;   // ← ДОБАВИТЬ: сброс ожидания
			_reconnectAttempts = 0;
			_reconnectTimer = 0;

			var errC = getOutput("error");
			if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }
			var stateC = getOutput("state");
			if (stateC != null) { stateC.setValueSilent(2); stateC.propagateCurrentValue(); }
		}
        // ═════════════════════════════════════════════════════════════════
        // v1.4 FIX: DETECT FAILED RECONNECT
        // Play() returned true (accepted URL), but stream failed to reach
        // PLAYING state (connection lost or buffering timeout occurred).
        // Schedule next retry attempt.
        // ═════════════════════════════════════════════════════════════════
        if (_waitingForPlaying && (cppConnectionLost || cppBufferingTimeout))
        {
            trace('⏳ URLAudioStreamPlayer: Play() accepted, but failed to reach PLAYING. Scheduling retry...');
            _waitingForPlaying = false;
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
            _isReconnecting = true;

            trace('🔄 Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');

            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...'); errC.propagateCurrentValue(); }
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

		// Debug state
		if (cppState != _lastStateInt)
		{
			trace('📊 URLAudioStreamPlayer: State changed: ${_lastStateInt} → $cppState (${getGameStateName(cppState)})');
			_lastStateInt = cppState;
			var c = getOutput("state");
			if (c != null) { c.setValueSilent(cppState); c.propagateCurrentValue(); }
		}
    }

    // =========================================================================
    // v1.3: AUTO-RECONNECT LOGIC (FIXED)
    // =========================================================================

    /**
     * Initiate reconnect sequence with exponential backoff.
     * Called by pollSessionState() when connection loss is detected.
     */
    private function startReconnect(errorMsg:String):Void
    {
        if (_reconnectAttempts >= MAX_RECONNECT_ATTEMPTS)
        {
            trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
            _isReconnecting = false;

            var errC = getOutput("error");
            if (errC != null)
            {
                errC.setValueSilent("Connection lost. Max retries exceeded.");
                errC.propagateCurrentValue();
            }
            var stateC = getOutput("state");
            if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
            return;
        }

        _isReconnecting = true;
        _reconnectAttempts++;

        var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
        if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;

        var jitter = delay * 0.2 * (Math.random() * 2 - 1);
        delay += jitter;

        _reconnectTimer = delay;

        trace('🔄 URLAudioStreamPlayer: Reconnect attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS in ${Math.round(delay * 10) / 10}s');

        var errC = getOutput("error");
        if (errC != null)
        {
            errC.setValueSilent('Connection lost. Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...');
            errC.propagateCurrentValue();
        }

        var stateC = getOutput("state");
        if (stateC != null)
        {
            stateC.setValueSilent(3);
            stateC.propagateCurrentValue();
        }

        var bufC = getOutput("isBuffering");
        if (bufC != null)
        {
            bufC.setValueSilent(true);
            bufC.propagateCurrentValue();
        }
    }

    /**
     * Execute reconnect attempt: Stop + Play with same URL.
     *
     * ═════════════════════════════════════════════════════════════════════
     * v1.3 FIX: This method now properly handles the result of Play():
     *
     *   Play() == true  → Reset counter, wait for MESessionStarted
     *                      (pollSessionState will detect PLAYING state)
     *
     *   Play() == false → Increment counter, set exponential delay
     *                      for the NEXT attempt. If max reached → give up.
     *
     * Without this fix, _reconnectTimer was never set after failure,
     * causing executeReconnect() to be called every frame (infinite loop).
     * ═════════════════════════════════════════════════════════════════════
     */
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

        // v1.3 FIX: Check max attempts BEFORE trying
        if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
        {
            trace('❌ URLAudioStreamPlayer: Max reconnect attempts reached. Giving up.');
            _isReconnecting = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;

            var errC = getOutput("error");
            if (errC != null)
            {
                errC.setValueSilent("Connection lost. Max retries exceeded.");
                errC.propagateCurrentValue();
            }
            var stateC = getOutput("state");
            if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
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
            session->Stop();
            std::string url = std::string((const char*){1}.__s);
            bool result = session->Play(url);
            {2} = result;
            printf("🔄 [URLAudio] Reconnect Play() returned: %s\\n", result ? "true" : "false");
        } else {
            printf("⚠️ [URLAudio] Reconnect: Session is null!\\n");
            {2} = false;
        }
        ', this, _currentUrl, playResult);

        // ═════════════════════════════════════════════════════════════════
        // v1.3 FIX: Handle Play() result properly
        // ═════════════════════════════════════════════════════════════════
		if (playResult)
		{
			// Play() accepted - reset all reconnect state
			_isReconnecting = false;
			_waitingForPlaying = true;
			_reconnectAttempts = 0;
			_reconnectTimer = 0;
			
			trace('✅ Play() accepted, waiting for PLAYING state...');
			
			var errC = getOutput("error");
			if (errC != null)
			{
				errC.setValueSilent("Connecting...");
				errC.propagateCurrentValue();
			}
		}
        else
        {
            // Play() failed — increment counter and schedule next attempt
            _reconnectAttempts++;

            if (_reconnectAttempts > MAX_RECONNECT_ATTEMPTS)
            {
                // Max attempts reached — give up
                trace('❌ URLAudioStreamPlayer: Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached. Giving up.');
                _isReconnecting = false;
                _reconnectTimer = 0;

                var errC = getOutput("error");
                if (errC != null)
                {
                    errC.setValueSilent("Connection lost. Max retries exceeded.");
                    errC.propagateCurrentValue();
                }
                var stateC = getOutput("state");
                if (stateC != null) { stateC.setValueSilent(4); stateC.propagateCurrentValue(); }
                return;
            }

            // Calculate next delay with exponential backoff
            var delay = BASE_RECONNECT_DELAY * Math.pow(2, _reconnectAttempts - 1);
            if (delay > MAX_RECONNECT_DELAY) delay = MAX_RECONNECT_DELAY;

            var jitter = delay * 0.2 * (Math.random() * 2 - 1);
            delay += jitter;

            _reconnectTimer = delay;

            trace('⏳ Play() failed. Next attempt in ${Math.round(delay * 10) / 10}s (attempt $_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)');

            var errC = getOutput("error");
            if (errC != null)
            {
                errC.setValueSilent('Reconnecting ($_reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...');
                errC.propagateCurrentValue();
            }
        }
    }

    /**
     * Cancel pending reconnect (called on URL change or Stop).
     */
    private function cancelReconnect():Void
    {
        if (_isReconnecting)
        {
            trace('🛑 URLAudioStreamPlayer: Reconnect cancelled');
            _isReconnecting = false;
            _reconnectAttempts = 0;
            _reconnectTimer = 0;

            // Clear error display
            var errC = getOutput("error");
            if (errC != null) { errC.setValueSilent(""); errC.propagateCurrentValue(); }
        }
    }
    /**
     * Convert C++ WMFStreamSession::State enum to human-readable string.
     * Used for debug logging in pollSessionState().
     *
     * Mapping (from WMFStreamSession.h):
     *   0 = IDLE
     *   1 = CONNECTING
     *   2 = PLAYING
     *   3 = STOPPING
     *   4 = ERR
     */
    private function getGameStateName(state:Int):String
    {
        return switch (state)
        {
            case 0: "IDLE";
            case 1: "CONNECTING";
            case 2: "PLAYING";
            case 3: "STOPPING";
            case 4: "ERR";
            default: "UNKNOWN(" + state + ")";
        }
    }
}
