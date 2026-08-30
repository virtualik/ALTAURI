package core.types;

import haxe.io.Bytes;

/**
 * CARGO v1.0 (Этап 4a-2, Task 145)
 * ============================================================================
 * Договор ПОРЦИОННЫХ перевозок по контактной сети ALTAURI.
 *
 * ДОКТРИНА ПРОВОДОВ (решение автора, Task 143-144):
 *   Слой 1 «ЭЛЕКТРИЧЕСТВО» — голые Bool/Int/Float/String: дедуп по значению,
 *     inline-прозрачность, ~95% контактов. Существующая библиотека НЕ трогается.
 *   Слой 2 «КАРГО-РЕЙСЫ» — этот класс: тяжёлые/самодекватные порции данных
 *     (содержимое файла, будущие изображения/аудио-чанки) едут в ЯВНОМ
 *     контейнере, несущем о себе всё: вид данных, имя, размер, mime.
 *   Слой 3 «СОБЫТИЯ» — шина Impulsys (payload-объекты, вне графовой сети).
 *
 * Принцип: «карго — для порций, электричество — для состояний».
 *
 * ЗАЧЕМ КОНТЕЙНЕР, ЕСЛИ Dynamic УЖЕ НЕСЁТ ССЫЛКУ (без сериализации)?
 *   · kind ЯВЕН: приёмник не гадает, текст это или байты (никакого
 *     type-sniffing на приёме);
 *   · fileName/mime едут БЕСПЛАТНО (FileReader v1.1 подарит Хранилищу имя);
 *   · toString() читаем в трассах и логах (не «[object Object]»);
 *   · конструирование только через фабрики text()/bytes() — size считается
 *     сам и не может соврать.
 *
 * ПРАВИЛА ГИГИИНЫ ТЯЖЁЛОГО ГРУЗА (П1-П4, SPEC_STAGE4A_DATASTORAGE §5):
 *   П1 поглотитель очищает вход после принятия;
 *   П2 источник держит последнюю порцию на выходе (RAM: один экземпляр);
 *   П3 по проводам — ссылки; копия лишь при повторной выдаче (Bytes.copy);
 *   П4 сериализация — только осознанно (getPersistentState + CAP).
 *
 * Уроки, зашитые в дизайн: TextArea v1.3 «Memory exhausted» (неограниченный
 * рост — враг; здесь порция НЕНАРАСТАЮЩАЯ по построению), Contact v5.14
 * (лимитов размера в проводе нет — дисциплина на совести поглотителей).
 * ============================================================================
 */
class Cargo
{
    /** Вид груза: текстовая порция (data:String). */
    public static inline var KIND_TEXT:String = "text";
    /** Вид груза: байтовая порция (data:haxe.io.Bytes). */
    public static inline var KIND_BYTES:String = "bytes";

    /** Вид груза: KIND_TEXT | KIND_BYTES. */
    public var kind(default, null):String;
    /** Тело груза: String (text) | haxe.io.Bytes (bytes). По проводам — ссылка. */
    public var data(default, null):Dynamic;
    /** Имя, если порция родом из файла (FileReader v1.1+); "" — безымянная. */
    public var fileName(default, null):String;
    /** Честный размер тела: длина UTF-8 (text) или длина байтов (bytes). */
    public var size(default, null):Int;
    /** Опциональный mime («image/png», «text/plain»...); "" — не указан. */
    public var mime(default, null):String;

    /**
     * Приватный конструктор: карго рождается только фабриками text()/bytes(),
     * чтобы size всегда соответствовал телу (нельзя «создать» рассинхрон).
     */
    private function new(kind:String, data:Dynamic, fileName:String, size:Int, mime:String)
    {
        this.kind = kind;
        this.data = data;
        this.fileName = (fileName != null) ? fileName : "";
        this.size = size;
        this.mime = (mime != null) ? mime : "";
    }

    /** Текстовая порция. size = длина UTF-8 (байты, не кодовые единицы). */
    public static function text(s:String, ?fileName:String = "", ?mime:String = ""):Cargo
    {
        if (s == null) s = "";
        return new Cargo(KIND_TEXT, s, fileName, Bytes.ofString(s).length, mime);
    }

    /** Байтовая порция. size = длина тела. */
    public static function bytes(b:Bytes, ?fileName:String = "", ?mime:String = ""):Cargo
    {
        if (b == null) b = Bytes.alloc(0);
        return new Cargo(KIND_BYTES, b, fileName, b.length, mime);
    }

    /** Это карго? (приёмники двуязычны: карго распаковывается, голое — по флагу). */
    public static function isCargo(v:Dynamic):Bool
    {
        return v != null && Std.isOfType(v, Cargo);
    }

    /** Читаемая трасса: «Cargo(bytes, 20480, 'photo.png')». */
    public function toString():String
    {
        var namePart:String = (fileName != null && fileName != "") ? ", '" + fileName + "'" : "";
        return "Cargo(" + kind + ", " + size + namePart + ")";
    }
}
