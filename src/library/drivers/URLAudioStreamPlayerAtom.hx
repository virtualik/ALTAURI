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
@:headerCode('
#include "../../../../include/WMFStreamSession.h"
#include <string>
#include <map>
#include <mutex>
')
@:cppFileCode('
static std::map<void*, WMFStreamSession*> _urlaudio_sessions;
static std::mutex _urlaudio_sessions_mutex;
')
class URLAudioStreamPlayerAtom extends Atom implements system.managers.Driver
{
    private var _lastUrl:String = "";
    private var _currentUrl:String = "";
    private var _lastPlayCtrl:Bool = false;
    private var _volume:Float = 1.0;
    private var _lastState:Int = 0;
    private var _lastBuffering:Bool = false;
    private var _lastError:String = "";

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
                _lastUrl = newUrl;
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
                _lastPlayCtrl = newPlay;
                if (newPlay)
                {
                    startPlayback();
                }
                else
                {
                    stopPlayback();
                }
            }
        }
    }

    private function startPlayback():Void
    {
        if (_lastUrl == "" || _lastUrl == null) return;

        _currentUrl = _lastUrl;

        untyped __cpp__('
            WMFStreamSession* session = nullptr;
            {
                std::lock_guard<std::mutex> lock(_urlaudio_sessions_mutex);
                auto it = _urlaudio_sessions.find((void*){0}.mPtr);
                if (it != _urlaudio_sessions.end()) session = it->second;
            }
            if (session) {
                std::string url = std::string((const char*){1}.__s);
                session->Play(url);
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
            }
        ', this, cppPlaying, cppBuffering, cppError, cppState);

        if (cppPlaying != _lastState)
        {
            _lastState = cppPlaying ? 1 : 0;
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

        if (cppState != _lastState)
        {
            var c = getOutput("state");
            if (c != null) { c.setValueSilent(cppState); c.propagateCurrentValue(); }
        }
    }
}