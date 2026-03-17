package utils;

/**
 * UID Generator v1.1
 * Generates unique identifiers for Atoms and Wires.
 */
class UID {

    /**
     * Generates a random unique ID string.
     * Format: "id_XXXXXXXX" (8 random hex chars)
     */
    public static function generate():String {
        var chars = "0123456789abcdef";
        var str = "id_";
        for (i in 0...8) {
            str += chars.charAt(Std.random(chars.length));
        }
        return str;
    }

    /**
     * Generates a short ID (4 chars).
     * Format: "XXXX" (4 random hex chars)
     */
    public static function generateShort():String {
        var chars = "0123456789abcdef";
        var str = "";
        for (i in 0...4) {
            str += chars.charAt(Std.random(chars.length));
        }
        return str;
    }
}
