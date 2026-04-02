package library;
import core.data.Blueprint;
import core.types.ContactType;

/**
* Atom Registry v2.2 (Fixed Driver Registration)
* Stores and manages blueprints for all atom types.
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
		reg("LED", "LED Indicator", [{name: "in", type: INPUT, dataType: "bool"}], null, "led", true, false); // isActive = false
		reg("Toggle", "Toggle Switch", [{name: "out", type: OUTPUT, dataType: "bool"}], null, "toggle");
		reg("TextInput", "Text Input", [{name: "set", type: INPUT, dataType: "string"},	{name: "out", type: OUTPUT, dataType: "string"}		], null, "textinput");
		reg("Relay", "Relay", [
		{name: "signal", type: INPUT, dataType: "any"},
		{name: "control", type: INPUT, dataType: "bool"},
		{name: "out", type: OUTPUT, dataType: "any"}
		], null, "relay");

		// Logic

		// Active Drivers (Must be registered with isActive=true)
		reg("SignalGenerator", "Signal Generator", [
			{name: "freq", type: INPUT, defaultValue: 1.0, dataType: "float"},
			{name: "quantum", type: INPUT, defaultValue: 0.1, dataType: "float"},
			{name: "mode", type: INPUT, defaultValue: 3, dataType: "int"},
			{name: "out", type: OUTPUT, dataType: "float"},
			{name: "changed", type: OUTPUT, dataType: "bool"}
		], null, "panel", true, true); // isActive = true

		reg("AudioIn", "Audio Input", [
		{name: "samples", type: OUTPUT, dataType: "array"},
		{name: "level", type: OUTPUT, dataType: "float"}
		], null, "oscilloscope", true, true); // isActive = true

		reg("MiniAudioAtom", "Mini Audio Capture", [
            // Входные контакты (настройки)
            {name: "mode",     type: INPUT,  defaultValue: 2,    dataType: "int"},
            {name: "quantum",  type: INPUT,  defaultValue: 0.01, dataType: "float"},
            {name: "gain",     type: INPUT,  defaultValue: 1.0,  dataType: "float"},
            {name: "channel",  type: INPUT,  defaultValue: 0,    dataType: "int"},
            {name: "rate",     type: INPUT,  defaultValue: 0,    dataType: "int"},
            
            // Выходные контакты
            {name: "sample",   type: OUTPUT, dataType: "float"},
            {name: "changed",  type: OUTPUT, dataType: "bool"},
            {name: "rms",      type: OUTPUT, dataType: "float"},
            {name: "clip",     type: OUTPUT, dataType: "bool"},
            {name: "tick",     type: OUTPUT, dataType: "bool"},
            {name: "level",    type: OUTPUT, dataType: "float"},
            {name: "device",   type: OUTPUT, dataType: "string"}
        ], null, "miniaudio", true, true); // isActive = true - КРИТИЧНО!
		
		// Passive Displays
		reg("Oscilloscope", "Oscilloscope", [
		{name: "in", type: INPUT, dataType: "array"}
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