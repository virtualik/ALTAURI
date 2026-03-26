package core.base;
import core.types.ContactType;
/**
* CONDUCTOR PORT v1.4 (Logic Mode Support)
* Пробрасывающий элемент. Пара контактов, соединяющих внешнюю и внутреннюю стороны сборки.
*
* v1.4 Changes:
* - Removed auto-linking in constructor.
* - Assembly now manages links to support Logic Mode (Unit Delay).
*/
class ConductorPort
{
	public var name(default, null):String;
	public var type(default, null):ContactType;
// Контакт, смотрящий ВНЕ
	public var external(default, null):Contact;
// Контакт, смотрящий ВНУТРЬ
	public var internal(default, null):Contact;
	public function new(name:String, type:ContactType, defaultValue:Dynamic = null)
	{
		this.name = name;
		// === FIX: Гарантируем что type никогда не будет null ===
		this.type = (type == null) ? ContactType.UNDEFINED : type;
		if (type == INPUT)
		{
			// ВХОД СБОРКИ:
			external = new Contact(defaultValue, INPUT, name);
			internal = new Contact(defaultValue, OUTPUT, name + "_int");
		}
		else
		{
			// ВЫХОД СБОРКИ:
			internal = new Contact(defaultValue, INPUT, name + "_int");
			external = new Contact(defaultValue, OUTPUT, name);
		}
	}
	/**
	* Properly dispose the port and its contacts.
	*/
	public function dispose():Void
	{
		if (external != null && internal != null)
		{
			external.unlink(internal);
			internal.unlink(external);
		}
		if (external != null)
		{
			external.dispose();
		}
		if (internal != null)
		{
			internal.dispose();
		}
		external = null;
		internal = null;
	}
}