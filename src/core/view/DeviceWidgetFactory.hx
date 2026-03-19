package core.view;
import core.base.Atom;
import core.base.Assembly;
import core.data.Blueprint;
import core.view.TextInputWidget;

/**
* DEVICE WIDGET FACTORY v1.5 (Full Restore & Oscilloscope Fix)
* Factory for creating DeviceView by type or Blueprint.
* Completely separated from Atom logic.
*
* v1.5 Changes:
* - Fixed Oscilloscope contact name to "in"
* - Restored full factory logic including custom class resolution
*/
class DeviceWidgetFactory {
	/**
	* Create a DeviceView for an atom by its type.
	*/
	public static function create(atom:Atom):DeviceView {
		if (atom == null) return null;
		try {
			// 1. FIRST check if Assembly (this prevents recursion)
			if (Std.isOfType(atom, Assembly)) {
				var asm:Assembly = cast(atom, Assembly);
				return createForAssembly(asm);
			}
			// 2. Determine by atom type (Native Atoms)
			return createByAtomType(atom);
		} catch (e:Dynamic) {
			trace('Error creating DeviceView: $e');
			return null;
		}
	}

	/**
	* Create a DeviceView for Assembly by blueprint.deviceType.
	*/
	private static function createForAssembly(asm:Assembly):DeviceView {
		if (asm == null || asm.blueprint == null) return null;
		var bp = asm.blueprint;
		var deviceType:String = bp.deviceType;
		if (deviceType == null || deviceType == "") {
			return new PanelWidget(asm);
		}
		return switch (deviceType.toLowerCase()) {
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
			case "textinput":
				new TextInputWidget(asm);
			case "audioinput", "audio":
				new OscilloscopeWidget(asm, "samples");
				
			default:
				createByClassName(deviceType, asm);
		}
	}

	/**
	* Create a DeviceView by atom type.
	*/
	private static function createByAtomType(atom:Atom):DeviceView {
		if (atom == null) return null;
		var type = atom.type.toLowerCase();
		return switch (type) {
			case "led", "led indicator":
				new LEDWidget(atom, "in");
			case "button", "push button":
				new ButtonWidget(atom, "out");
			case "toggle", "switch":
				new ToggleWidget(atom, "out");
			case "oscilloscope":
				new OscilloscopeWidget(atom, "in");
			case "textinput":
				new TextInputWidget(atom);
			case "audioinput", "audio":
				new OscilloscopeWidget(atom, "samples");
			case "relay":
				// Show output "out".
				new TextWidget(atom, "out", false);
			case "conductor":
				new ConductorWidget(atom);
				
				default:
				// Universal widget - text display
				new TextWidget(atom);
		}
	}

	/**
	* Attempt to create a widget by class name.
	*/
	private static function createByClassName(className:String, atom:Atom):DeviceView {
		var fullClassName = "core.view." + className;
		try {
			var cls = Type.resolveClass(fullClassName);
			if (cls != null) {
				var instance = Type.createInstance(cls, [atom]);
				if (Std.isOfType(instance, DeviceView)) {
					return cast(instance, DeviceView);
				}
			}
		} catch (e:Dynamic) { }
		// Fallback
		return new TextWidget(atom);
	}

	private static function getContactName(bp:Blueprint, defaultName:String):String {
		if (bp == null || bp.pins == null) return defaultName;
		for (pin in bp.pins) {
			if (pin.name == defaultName) return pin.name;
		}
		for (pin in bp.pins) {
			if (pin.name != null) return pin.name;
		}
		return defaultName;
	}
}