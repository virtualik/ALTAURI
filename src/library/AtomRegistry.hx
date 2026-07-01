package library;

import core.data.Blueprint;
import core.data.Blueprint.ParameterPriority;
import core.types.ContactType;

/**
* Atom Registry v2.3 (Inline Editor Metadata)
* Stores and manages blueprints for all atom types.
*
* v2.3 Changes:
* - ADDED: ParameterPriority metadata to PinDef for inline editor visibility
*/
class AtomRegistry
{
	private static var _initialized:Bool = false;
	private static var _blueprints:Map<String, Blueprint> = new Map();
	public static var customLibraryPath:String = "";
	
	private static function reg(id:String, name:String, pins:Array<core.data.Blueprint.PinDef>, ?logic, ?deviceType:String = null, ?isNative:Bool = true, ?isActive:Bool = false)
	{
		var bp = new Blueprint(id, name, pins, null);
		bp.deviceType = deviceType;
		bp.isNative = isNative;
		bp.isActive = isActive;
		_blueprints.set(id, bp);
	}
	
	public static function getAllIds():Array<String>
	{
		return [for (key in _blueprints.keys()) key];
	}
	
	public static function initialize():Void
	{
		if (_initialized) return;
		
		// --- Native Atoms Registration ---
		// Electro / UI
		reg("Button", "Push Button", [{name: "out", type: OUTPUT, dataType: "bool"}], null, "button");
		reg("LED", "LED Indicator", [{name: "in", type: INPUT, dataType: "bool"}], null, "led", true, false);
		reg("Toggle", "Toggle Switch", [{name: "out", type: OUTPUT, dataType: "bool"}], null, "toggle");
		reg("TextInput", "Text Input", [{name: "set", type: INPUT, dataType: "string"}, {name: "out", type: OUTPUT, dataType: "string"}], null, "textinput");
		reg("Relay", "Relay", [{name: "signal", type: INPUT, dataType: "any"},{name: "control", type: INPUT, dataType: "bool"}, {name: "out", type: OUTPUT, dataType: "any"}], null, "relay");
		
		// Active Drivers
		reg("SignalGenerator", "Signal Generator", [
			{name: "freq", type: INPUT, defaultValue: 1.0, dataType: "float", priority: IMPORTANT, label: "Freq", visibleInEditor: true},
			{name: "quantum", type: INPUT, defaultValue: 0.1, dataType: "float", priority: OPTIONAL, visibleInEditor: false},
			{name: "mode", type: INPUT, defaultValue: 3, dataType: "int", priority: IMPORTANT, label: "Mode", visibleInEditor: true},
			{name: "out", type: OUTPUT, dataType: "float", priority: CRITICAL},
			{name: "changed", type: OUTPUT, dataType: "bool", priority: OPTIONAL}
		], null, "panel", true, true);
		
		reg("MiniAudioAtom", "Mini Audio Capture", [
			{name: "mode",     type: INPUT,  defaultValue: 1,    dataType: "int",     priority: IMPORTANT, label: "Mode"},
			{name: "quantum",  type: INPUT,  defaultValue: 0.01, dataType: "float",   priority: OPTIONAL},
			{name: "gain",     type: INPUT,  defaultValue: 1.0,  dataType: "float",   priority: IMPORTANT, label: "Gain"},
			{name: "channel",  type: INPUT,  defaultValue: 0,    dataType: "int",     priority: OPTIONAL},
			{name: "rate",     type: INPUT,  defaultValue: 0,    dataType: "int",     priority: OPTIONAL},
			{name: "sample",   type: OUTPUT, dataType: "float",  priority: CRITICAL},
			{name: "changed",  type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
			{name: "rms",      type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "RMS"},
			{name: "clip",     type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
			{name: "tick",     type: OUTPUT, dataType: "bool",   priority: INTERNAL},
			{name: "level",    type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "Level"},
			{name: "device",   type: OUTPUT, dataType: "string", priority: OPTIONAL}
		], null, "miniaudio", true, true);
		
		reg("SystemVUMeterAtom", "System Stereo VU Meter", [
			{name: "mode",     type: INPUT,  defaultValue: 0,    dataType: "int",   priority: IMPORTANT, label: "Source"},
			{name: "peakL",    type: OUTPUT, dataType: "float",  priority: CRITICAL, label: "Peak L"},
			{name: "peakR",    type: OUTPUT, dataType: "float",  priority: CRITICAL, label: "Peak R"},
			{name: "peakMono", type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "Peak Mono"},
			{name: "percentL", type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "% L"},
			{name: "percentR", type: OUTPUT, dataType: "int",    priority: IMPORTANT, label: "% R"},
			{name: "dB_L",     type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "dB L"},
			{name: "dB_R",     type: OUTPUT, dataType: "float",  priority: IMPORTANT, label: "dB R"},
			{name: "channels", type: OUTPUT, dataType: "int",    priority: OPTIONAL, label: "Channels"},
			{name: "active",   type: OUTPUT, dataType: "bool",   priority: OPTIONAL},
			{name: "clipL",    type: OUTPUT, dataType: "bool",   priority: OPTIONAL, label: "Clip L"},
			{name: "clipR",    type: OUTPUT, dataType: "bool",   priority: OPTIONAL, label: "Clip R"}
		], null, "vumeter", true, true);
		
		reg("ComPortAtom", "COM Port", [
			{name: "portName",  type: INPUT,  defaultValue: "COM1", dataType: "string", priority: IMPORTANT, label: "Port"},
			{name: "baudRate",  type: INPUT,  defaultValue: 9600,   dataType: "int",    priority: IMPORTANT, label: "Baud"},
			{name: "open",      type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
			{name: "close",     type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
			{name: "send",      type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
			{name: "txData",    type: INPUT,  defaultValue: "",     dataType: "string", priority: OPTIONAL},
			{name: "setDTR",    type: INPUT,  defaultValue: false,  dataType: "bool",   priority: OPTIONAL},
			{name: "isOpen",    type: OUTPUT, dataType: "bool",     priority: CRITICAL},
			{name: "rxData",    type: OUTPUT, dataType: "string",   priority: IMPORTANT, label: "RX"},
			{name: "rxTick",    type: OUTPUT, dataType: "bool",     priority: INTERNAL},
			{name: "txTick",    type: OUTPUT, dataType: "bool",     priority: INTERNAL},
			{name: "error",     type: OUTPUT, dataType: "string",   priority: IMPORTANT, label: "Error"},
			{name: "errorTick", type: OUTPUT, dataType: "bool",     priority: INTERNAL}
		], null, "comport", true, true);
		
		reg("ComEnumeratorAtom", "COM Enumerator", [
			{name: "ports", type: OUTPUT, dataType: "string", priority: CRITICAL}
		], null, "comenumerator", true, true);
		
		// Passive Displays
		reg("Oscilloscope", "Oscilloscope", [
			{name: "in", type: INPUT, dataType: "array", priority: CRITICAL}
		], null, "oscilloscope");
		
		_initialized = true;
	}
	
	public static function get(id:String):Blueprint
	{
		return _blueprints.get(id);
	}
	
	public static function registerBlueprint(id:String, bp:Blueprint):Void
	{
		_blueprints.set(id, bp);
	}
	
	public static function remove(id:String):Bool
	{
		if (_blueprints.exists(id))
		{
			_blueprints.remove(id);
			trace('AtomRegistry: Removed $id');
			return true;
		}
		trace('AtomRegistry: $id not found for removal');
		return false;
	}
	
	public static function exists(id:String):Bool
	{
		return _blueprints.exists(id);
	}
	
	public static function scanFolder(path:String):Void
	{
		#if sys
		if (!sys.FileSystem.exists(path))
		{
			try
			{
				sys.FileSystem.createDirectory(path);
			}
			catch (e:Dynamic)
			{
				trace("Error creating library dir: " + e);
			}
			return;
		}
		trace("Scanning library folder: " + path);
		for (file in sys.FileSystem.readDirectory(path))
		{
			if (StringTools.endsWith(file, ".atom"))
			{
				var fullPath = path + "/" + file;
				loadAtomFile(fullPath);
			}
		}
		#end
	}
	
	public static function loadAtomFile(fullPath:String):Bool
	{
		#if sys
		try {
			var content = sys.io.File.getContent(fullPath);
			var json = haxe.Json.parse(content);
			var rawBp:Dynamic = json.blueprint;
			var pins:Array<core.data.Blueprint.PinDef> = [];
			if (rawBp.pins != null)
			{
				var seenNames = new Map<String, Bool>();
				for (p in (cast(rawBp.pins, Array<Dynamic>)))
				{
					var pinName = Std.string(p.name);
					if (!seenNames.exists(pinName))
					{
						pins.push(
						{
							name: pinName,
							type: _parseContactType(p.type),
							defaultValue: p.defaultValue,
							dataType: Std.string(p.dataType)
						});
						seenNames.set(pinName, true);
					}
				}
			}
			var conns:Array<core.data.ConnectionDef> = [];
			if (rawBp.internalConnections != null)
			{
				for (c in (cast(rawBp.internalConnections, Array<Dynamic>)))
				{
					conns.push(
					{
						from: { atomId: Std.string(c.from.atomId), contactName: Std.string(c.from.contactName) },
						to: { atomId: Std.string(c.to.atomId), contactName: Std.string(c.to.contactName) }
					});
				}
			}
			var atoms:Array<core.data.AtomDef> = [];
			if (rawBp.internalAtoms != null)
			{
				for (a in (cast(rawBp.internalAtoms, Array<Dynamic>)))
				{
					atoms.push(
					{
						instanceId: Std.string(a.instanceId),
						typeId: Std.string(a.typeId),
						x: a.x,
						y: a.y,
						values: a.values
					});
				}
			}
			var bp = new Blueprint(
				Std.string(rawBp.id),
				Std.string(rawBp.name),
				pins,
				null,
				atoms,
				conns,
				Std.string(rawBp.category)
			);
			if (rawBp.deviceType != null)
			{
				bp.deviceType = Std.string(rawBp.deviceType);
			}
			bp.isNative = false;
			registerBlueprint(bp.id, bp);
			trace("Library loaded: " + bp.id);
			return true;
		}
		catch (e:Dynamic)
		{
			trace("Failed to load atom: " + fullPath + " | Error: " + e);
			return false;
		}
		#else
		return false;
		#end
	}
	
	private static function _parseContactType(val:Dynamic):ContactType
	{
		if (Std.isOfType(val, ContactType)) return val;
		if (Std.isOfType(val, String))
		{
			switch (Std.string(val))
			{
				case "INPUT": return INPUT;
				case "OUTPUT": return OUTPUT;
				case "BIDIRECTIONAL": return BIDIRECTIONAL;
				default: return UNDEFINED;
			}
		}
		if (Std.isOfType(val, Int) || Std.isOfType(val, Float))
		{
			switch (Std.int(val))
			{
				case 0: return INPUT;
				case 1: return OUTPUT;
				case 2: return BIDIRECTIONAL;
				default: return UNDEFINED;
			}
		}
		return UNDEFINED;
	}
}