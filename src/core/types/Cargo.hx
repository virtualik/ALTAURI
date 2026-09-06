package core.types;

import haxe.io.Bytes;

/**
 * CARGO v1.0 (Stage 4a-2, Task 145)
 * ============================================================================
 * The contract of PORTION transportation over the ALTAURI contact network.
 *
 * THE WIRE DOCTRINE (the author decision, Task 143-144):
 *   Layer 1 ELECTRICITY - bare Bool/Int/Float/String: value dedup,
 *     inline transparency, ~95% of contacts. The existing library is NOT touched.
 *   Layer 2 CARGO RUNS - this class: heavy/self-contained data portions
 *     (file contents, future image/audio chunks) ride in an EXPLICIT
 *     container carrying everything about itself: the data kind, name, size, mime.
 *   Layer 3 EVENTS - the Impulsys bus (payload objects, outside the graph network).
 *
 * The principle: cargo for portions, electricity for states.
 *
 * WHY A CONTAINER IF Dynamic ALREADY CARRIES A REFERENCE (without serialization)?
 *   · the kind is EXPLICIT: the receiver does not guess whether it is text or bytes (no
 *     type-sniffing on reception);
 *   · fileName/mime ride for FREE (FileReader v1.1 gifts the name to Storage);
 *   · toString() is readable in traces and logs (not [object Object]);
 *   · construction only via the text()/bytes() factories - the size is computed
 *     itself and cannot lie.
 *
 * HEAVY CARGO HYGIENE RULES (P1-P4, SPEC_STAGE4A_DATASTORAGE §5):
 *   P1 the consumer clears the input after accepting;
 *   P2 the source keeps the last portion on the output (RAM: one instance);
 *   P3 over wires - references; a copy only on re-issue (Bytes.copy);
 *   P4 serialization - only deliberately (getPersistentState + CAP).
 *
 * Lessons wired into the design: TextArea v1.3 Memory exhausted (unlimited
 * growth is the enemy; here the portion is NON-GROWING by construction), Contact v5.14
 * (there are no size limits on the wire - the discipline is the consumers' responsibility).
 * ============================================================================
 */
class Cargo
{
    /** The cargo kind: a text portion (data:String). */
    public static inline var KIND_TEXT:String = "text";
    /** The cargo kind: a byte portion (data:haxe.io.Bytes). */
    public static inline var KIND_BYTES:String = "bytes";

    /** The cargo kind: KIND_TEXT | KIND_BYTES. */
    public var kind(default, null):String;
    /** The cargo body: String (text) | haxe.io.Bytes (bytes). Over wires - a reference. */
    public var data(default, null):Dynamic;
    /** The name if the portion came from a file (FileReader v1.1+); "" - unnamed. */
    public var fileName(default, null):String;
    /** The honest body size: the UTF-8 length (text) or the byte length (bytes). */
    public var size(default, null):Int;
    /** An optional mime (image/png, text/plain...); "" - not specified. */
    public var mime(default, null):String;

    /**
     * A private constructor: cargo is born only via the text()/bytes() factories,
     * so the size always matches the body (you cannot create a desync).
     */
    private function new(kind:String, data:Dynamic, fileName:String, size:Int, mime:String)
    {
        this.kind = kind;
        this.data = data;
        this.fileName = (fileName != null) ? fileName : "";
        this.size = size;
        this.mime = (mime != null) ? mime : "";
    }

    /** A text portion. size = the UTF-8 length (bytes, not code units). */
    public static function text(s:String, ?fileName:String = "", ?mime:String = ""):Cargo
    {
        if (s == null) s = "";
        return new Cargo(KIND_TEXT, s, fileName, Bytes.ofString(s).length, mime);
    }

    /** A byte portion. size = the body length. */
    public static function bytes(b:Bytes, ?fileName:String = "", ?mime:String = ""):Cargo
    {
        if (b == null) b = Bytes.alloc(0);
        return new Cargo(KIND_BYTES, b, fileName, b.length, mime);
    }

    /** Is this cargo? (the receivers are bilingual: cargo is unpacked, bare goes by the flag). */
    public static function isCargo(v:Dynamic):Bool
    {
        return v != null && Std.isOfType(v, Cargo);
    }

    /** A readable trace: Cargo(bytes, 20480, photo.png). */
    public function toString():String
    {
        var namePart:String = (fileName != null && fileName != "") ? ", '" + fileName + "'" : "";
        return "Cargo(" + kind + ", " + size + namePart + ")";
    }
}
