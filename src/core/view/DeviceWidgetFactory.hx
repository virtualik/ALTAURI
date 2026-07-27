package core.view;
import core.base.Atom;
import core.base.Assembly;
import core.data.Blueprint;
#if cpp
	import core.view.MiniAudioWidget;
	import core.view.ComPortWidget;
	import core.view.ComEnumeratorWidget;
	import core.view.NETRadioPlayerWidget;
	import core.view.SystemVUMeterWidget;
	import core.view.FFTWidget;
#end
/**
* DEVICE WIDGET FACTORY v1.1
* Factory for creating DeviceView (Atom's Face).
*
* Completely separated from Atom logic.
* Determines which widget to create based on atom type or Blueprint.
*
* Architecture "Atom is Databank & Compute Core":
* ┌─────────────────────────────────────────────────────────────────────────┐
* │   Atom (Databank + Compute)                                             │
* │         │                                                               │
* │         │ DeviceWidgetFactory.create(atom)                              │
* │         ▼                                                               │
* │   ┌─────────────────────────────────────────────────────────────────┐   │
* │   │ DeviceWidgetFactory                                             │   │
* │   │                                                                 │   │
* │   │ switch (atom.type) {                                            │   │
* │   │     case "Oscilloscope": return new OscilloscopeWidget(atom);   │   │
* │   │     case "Button": return new ButtonWidget(atom);               │   │
* │   │     case "Toggle": return new ToggleWidget(atom);               │   │
* │   │     case "LED": return new LEDWidget(atom);                     │   │
* │   │     case "TextInput": return new TextInputWidget(atom);         │   │
* │   │     case "AudioIn": return new OscilloscopeWidget(atom, "samples"); │
* │   │     default: return new TextWidget(atom);                       │   │
* │   │ }                                                               │   │
* │   └─────────────────────────────────────────────────────────────────┘   │
* │         │                                                               │
* │         ▼                                                               │
* │   DeviceView (Atom's Face)                                              │
* │   - Subscribes to Atom's Contact                                        │
* │   - Displays data from Atom's Databank                                  │
* │   - DOES NOT store business data                                        │
* └─────────────────────────────────────────────────────────────────────────┘
*/
class DeviceWidgetFactory
{
	/**
	* Create DeviceView for atom.
	*
	* This is the ENTRY POINT for creating Atom's Face.
	*
	* PRINCIPLE: One atom = one widget.
	* Use DeviceViewRegistry.getOrCreate() instead of calling this method directly.
	*
	* @param atom Atom for which widget is created
	* @return DeviceView or null if atom null or type not supported
	*/
	public static function create(atom:Atom):DeviceView
	{
		if (atom == null) return null;
		try {
// 1. First check Assembly (this prevents recursion)
			if (Std.isOfType(atom, Assembly))
			{
				var asm:Assembly = cast(atom, Assembly);
				return createForAssembly(asm);
			}
// 2. Native atoms - by type
			return createByAtomType(atom);
		}
		catch (e:Dynamic)
		{
			trace('DeviceWidgetFactory: Error creating widget for atom "${atom.name}": $e');
			return null;
		}
	}
	/**
	* Create widget for Assembly by blueprint.deviceType.
	*/
	private static function createForAssembly(asm:Assembly):DeviceView
	{
		if (asm == null || asm.blueprint == null) return null;
		var bp = asm.blueprint;
		var deviceType:String = bp.deviceType;
// If deviceType not specified - PanelWidget (container)
		if (deviceType == null || deviceType == "")
		{
			return new PanelWidget(asm);
		}
// Determine by deviceType
		return switch (deviceType.toLowerCase())
		{
			case "led", "indicator", "light":
				new LEDWidget(asm, getContactName(bp, "in"));
			case "toggle", "switch":
				new ToggleWidget(asm, getContactName(bp, "out"));
			case "button", "push":
				new ButtonWidget(asm, getContactName(bp, "out"));
			case "text", "display", "label":
				new TextWidget(asm, getContactName(bp, "value"));
			case "panel", "container", "group":
				new PanelWidget(asm);
			case "oscilloscope", "scope":
				new OscilloscopeWidget(asm, "in");
			case "fftatom", "fft spectrum":
				new FFTWidget(asm);
			case "textinput":
				new TextInputWidget(asm);
			case "textarea":
				new TextAreaWidget(asm);
				#if cpp
			case "miniaudioatom", "mini audio capture":
				new MiniAudioWidget(asm);
				#end
			case "signalgenerator":
				new SignalGeneratorWidget(asm);
				#if cpp
			case "comport", "com port":
				new ComPortWidget(asm);
			case "comenumerator", "com enumerator":
				new ComEnumeratorWidget(asm);
				#end
				#if html5
				return new core.view.FileWriterWidget(asm);
				#else
				return new TextWidget(asm);
				#end
				#if cpp
			case "netradio", "netradioplayer":
				new NETRadioPlayerWidget(asm);
			case "urlplayer", "url audio player", "urlaudioplayer":
				new URLAudioStreamPlayerWidget(asm);
			
			case "filewriter", "file writer":
				#end
			default:
// Try to find class by name
				createByClassName(deviceType, asm);
		}
	}
	/**
	* Create widget by atom type (for native atoms).
	*/
	private static function createByAtomType(atom:Atom):DeviceView
	{
		if (atom == null) return null;
		var type = atom.type.toLowerCase();
		return switch (type)
		{
			case "led", "led indicator":
				new LEDWidget(atom, "in");
			case "button", "push button":
				new ButtonWidget(atom, "out");
			case "toggle", "switch":
				new ToggleWidget(atom, "out");
			case "textinput":
				new TextInputWidget(atom);
			case "textarea":
				new TextAreaWidget(atom);
			case "oscilloscope":
				new OscilloscopeWidget(atom, "in");
			case "fftatom", "fft spectrum":
				new FFTWidget(atom);
				#if cpp
				case "audioin", "audioinput", "audio":
				new OscilloscopeWidget(atom, "samples");
			case "systemvumeteratom", "system vu meter", "vumeter":
				new SystemVUMeterWidget(atom);
				#end
			case "relay":
			// Show output "out"
				new TextWidget(atom, "out", false);
			case "signalgenerator":
				new SignalGeneratorWidget(atom);

			case "comportatom", "com port":
				new ComPortWidget(atom);
			#if cpp
				case "comenumeratoratom", "com enumerator":
				new ComEnumeratorWidget(atom);
			case "websocketatom", "websocket":
				new WEBSocketWidget(atom);
			case "netradioplayeratom", "net radio player":
				new NETRadioPlayerWidget(atom);
			case "miniaudioatom", "mini audio capture":
				new MiniAudioWidget(atom);
			case "urlaudioplayeratom", "url audio player":
				new URLAudioStreamPlayerWidget(atom);
				#end
			case "filewriteratom", "file writer":
				#if html5
				return new core.view.FileWriterWidget(atom);
				#else
				return new TextWidget(atom);
				#end
			default:
// Universal widget - text display
				new TextWidget(atom);
		}
	}
	/**
	* Attempt to create widget by class name.
	* Allows extending system without changing Factory.
	*/
	private static function createByClassName(className:String, atom:Atom):DeviceView
	{
		var fullClassName = "core.view." + className;
		try {
			var cls = Type.resolveClass(fullClassName);
			if (cls != null)
			{
				var instance = Type.createInstance(cls, [atom]);
				if (Std.isOfType(instance, DeviceView))
				{
					return cast(instance, DeviceView);
				}
			}
		}
		catch (e:Dynamic)
		{
// Ignore errors - return fallback
		}
// Fallback - universal widget
		return new TextWidget(atom);
	}
	/**
	* Find contact name in Blueprint.
	* Used to determine contact for display.
	*/
	private static function getContactName(bp:Blueprint, defaultName:String):String
	{
		if (bp == null || bp.pins == null) return defaultName;
// Search exact match
		for (pin in bp.pins)
		{
			if (pin.name == defaultName) return pin.name;
		}
// Take first available
		for (pin in bp.pins)
		{
			if (pin.name != null) return pin.name;
		}
		return defaultName;
	}
	/**
	* Check if atom type is supported.
	*/
	public static function isSupported(atomType:String):Bool
	{
		if (atomType == null) return false;
		var type = atomType.toLowerCase();
		return switch (type)
		{
			case "led" | "button" | "toggle" | "oscilloscope" | "fftatom" | "textinput" |
					"audioin" | "audioinput" | "relay" | "conductor" |
					"universalgen" | "signalgen" | "fpsmonitor" | "frametime":
				true;
			default:
// Check Assembly
				true; // PanelWidget as fallback
		}
	}
}