package utils;

/**
 * UID GENERATOR v1.1
 * Generates unique identifiers for Atoms and Wires.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   UID (Static)                                                          │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  Methods:                                                       │   │
 * │   │  - generate()      → "id_XXXXXXXX" (8 hex chars)                │   │
 * │   │  - generateShort() → "XXXX" (4 hex chars)                       │   │
 * │   │                                                                 │   │
 * │   │  Format:                                                        │   │
 * │   │  - Characters: 0-9, a-f (hexadecimal)                           │   │
 * │   │  - Prefix: "id_" for full IDs                                   │   │
 * │   │  - No prefix for short IDs                                      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Usage:                                                                │
 * │   ───────                                                               │
 * │   var atomId = UID.generate();       // "id_a3f7b2c1"                   │
 * │   var shortId = UID.generateShort(); // "f2a1"                          │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
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