package core.data;
import core.types.ContactType;

// --- Type Definitions (Module Level) ---
typedef PinDef = {
	name: String,
	type: ContactType,
	?defaultValue: Dynamic,
	?dataType: String,
	
	// === НОВОЕ: Метаданные для визуализации (v3.2) ===
	// Все поля опциональны для обратной совместимости
	?priority: ParameterPriority,      // CRITICAL, IMPORTANT, OPTIONAL, INTERNAL
	?visibleInEditor: Bool,            // Показывать ли inline редактор
	?label: String,                    // Краткая подпись (если null, использовать name)
	?editable: Bool                    // Можно ли редактировать inline (default: true)
}

// === НОВЫЙ ENUM (v3.2) ===
enum ParameterPriority {
	CRITICAL;    // Всегда показывать (основной выход)
	IMPORTANT;   // Показывать в Editor (частота, режим)
	OPTIONAL;    // Только в Properties (тонкая настройка)
	INTERNAL;    // Никогда не показывать (технические контакты)
}

typedef AtomDef = {
	instanceId: String,
	typeId: String,
	?x: Float,
	?y: Float,
	?values: Dynamic // <--- НОВОЕ: Хранит состояние атома (например, {value: "Some Text"})
}

typedef ConnectionPoint = {
	atomId: String,
	contactName: String
}

typedef ConnectionDef = {
	from: ConnectionPoint,
	to: ConnectionPoint
}

// --- Main Class ---
/**
* Blueprint Data Structure.
* Defines the schematic of an Atom or Assembly.
*
* v3.2 Changes:
* - ADDED: ParameterPriority enum for inline editor visibility control
* - ADDED: Metadata fields to PinDef (priority, visibleInEditor, label, editable)
*/
class Blueprint {
	public var id:String;
	public var name:String;
	public var category:String;
	public var deviceType:String;  // Тип устройства для DeviceView: "led", "toggle", "button", "text", "panel"
	public var isNative:Bool = false;  // true = системная сборка, нельзя редактировать
	public var pins(default, null):Array<PinDef>;
	public var internalAtoms(default, null):Array<AtomDef>;
	public var internalConnections(default, null):Array<ConnectionDef>;
	public var logic(default, null):Array<Dynamic> -> Array<Dynamic>;
	public var isActive:Bool = false; // Флаг активности
	
	public function new(
		id:String,
		name:String,
		pins:Array<PinDef>,
		?logic:Array<Dynamic> -> Array<Dynamic>,
		?internalAtoms:Array<AtomDef>,
		?internalConnections:Array<ConnectionDef>,
		?category:String = "General"
	) {
		this.id = id;
		this.name = name;
		this.pins = pins;
		this.logic = logic;
		this.internalAtoms = (internalAtoms != null) ? internalAtoms : [];
		this.internalConnections = (internalConnections != null) ? internalConnections : [];
		this.category = category;
	}
}