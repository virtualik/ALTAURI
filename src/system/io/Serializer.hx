package system.io;

import haxe.Json;
import core.data.Blueprint;

/**
 * SERIALIZER v1.0
 * Responsible for converting Blueprints and Assembly states into JSON strings
 * and restoring them back.
 */
class Serializer {

    /**
     * Converts a Blueprint to a JSON string.
     */
    public static function blueprintToJson(bp:Blueprint):String {
        var data:Dynamic = {
            id: bp.id,
            name: bp.name,
            category: bp.category,
            pins: bp.pins,
            internalAtoms: bp.internalAtoms,
            internalConnections: bp.internalConnections
            // Note: 'logic' is NOT saved. It's looked up by ID in AtomRegistry.
        };

        return Json.stringify(data, null, "  "); // Pretty print
    }

    /**
     * Restores a Blueprint from a JSON string.
     * NOTE: This creates a "hollow" blueprint if logic is not linked.
     * Factory must use AtomRegistry to fill logic.
     */
    public static function jsonToBlueprint(json:String):Blueprint {
        var data:Dynamic = Json.parse(json);

        var bp = new Blueprint(
            data.id,
            data.name,
            cast data.pins, // Cast to Array<PinDef>
            null, // Logic is null here, will be linked by Factory
            cast data.internalAtoms,
            cast data.internalConnections,
            data.category
        );

        return bp;
    }
}