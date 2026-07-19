package system.commands.editor;

import system.commands.base.Command;
import core.data.Blueprint;
import core.base.Assembly;
import core.base.Atom;
import core.base.IDisposable;
import core.base.AssemblyFactory;
import core.logic.Impulsys;
import core.logic.EventType;

/**
 * CREATE ATOM COMMAND v1.3 (Paste-Aware + Global Naming)
 *
 * v1.3 CHANGES:
 *  - Constructor extended to 9 args to support paste-aware naming:
 *      (blueprint, assembly, typeId, ?instanceId, x, y,
 *       ?isNameTaken, ?desiredDisplayName, ?isPaste)
 *  - Uses new 4-arg AssemblyFactory.generateUniqueDisplayName with
 *    intelligent "_N" suffix parsing for paste operations.
 *  - When isPaste == true and desiredDisplayName == "Foo_2":
 *      → result = "Foo_3" (bumps from parsed number, not "Foo_2_1")
 *  - When isPaste == false and desiredDisplayName is null:
 *      → uses typeId's registry name as base (e.g., "Button")
 *  - Registers final displayName in NamingService before insertion.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │   CreateAtomCommand                                                     │
 * │                                                                         │
 * │   ┌─────────────────────────────────────────────────────────────────┐   │
 * │   │  execute():                                                     │   │
 * │   │  - Generate instanceId if not provided (UID.generate())         │   │
 * │   │  - Create AtomDef with position                                 │   │
 * │   │  - Add AtomDef to blueprint.internalAtoms                       │   │
 * │   │  - Create atom instance via AssemblyFactory                     │   │
 * │   │  - Resolve globally-unique displayName (v1.3)                   │   │
 * │   │  - Register displayName in NamingService                        │   │
 * │   │  - Add instance to assembly.internalAtoms                       │   │
 * │   │  - Emit ATOM_RESTORED event                                     │   │
 * │   │                                                                 │   │
 * │   │  undo():                                                        │   │
 * │   │  - Remove AtomDef from blueprint                                │   │
 * │   │  - Dispose atom instance (also unregisters name)                │   │
 * │   │  - Remove instance from assembly                                │   │
 * │   │  - Emit ATOM_DELETED event                                      │   │
 * │   └─────────────────────────────────────────────────────────────────┘   │
 * │                                                                         │
 * │   Paste Flow (v1.3):                                                    │
 * │   ─────────────────                                                     │
 * │   1. EditorActionHandler.copySelection() stores displayName per atom    │
 * │   2. EditorActionHandler.pasteSelection() calls this command with:      │
 * │      - desiredDisplayName = source atom's displayName                   │
 * │      - isPaste = true                                                   │
 * │   3. generateUniqueDisplayName() parses existing "_N" suffix and        │
 * │      bumps to next free slot (e.g., "Foo_2" → "Foo_3")                  │
 * │   4. Final name is registered in NamingService                          │
 * │                                                                         │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class CreateAtomCommand extends Command {
    private var _blueprint:Blueprint;
    private var _assembly:Assembly;
    private var _typeId:String;
    private var _instanceId:String;
    private var _posX:Float;
    private var _posY:Float;
    private var _atomDef:core.data.Blueprint.AtomDef;
    private var _atomInstance:Atom;

    // v1.3: Paste-aware naming support
    private var _isNameTaken:(String, ?String) -> Bool;
    private var _desiredDisplayName:String;
    private var _isPaste:Bool;

    /**
     * Create a new atom at specified position.
     *
     * @param blueprint           Parent blueprint (where AtomDef will be added)
     * @param assembly            Parent assembly (where instance will live)
     * @param typeId              Atom type ID from AtomRegistry
     * @param instanceId          Optional runtime ID (auto-generated if null)
     * @param x                   Canvas X position
     * @param y                   Canvas Y position
     * @param isNameTaken         Optional global uniqueness predicate.
     *                            If null, NamingService.isInstanceNameTaken is used.
     * @param desiredDisplayName  Optional desired display name (for paste).
     *                            If null, base name is derived from registry.
     * @param isPaste             If true, forces "_N" suffix and bumps from
     *                            any existing suffix in desiredDisplayName.
     */
    public function new(
        blueprint:Blueprint,
        assembly:Assembly,
        typeId:String,
        ?instanceId:String,
        x:Float,
        y:Float,
        ?isNameTaken:(String, ?String) -> Bool,
        ?desiredDisplayName:String = null,
        ?isPaste:Bool = false
    ) {
        super();
        _blueprint = blueprint;
        _assembly = assembly;
        _typeId = typeId;
        _instanceId = instanceId;
        _posX = x;
        _posY = y;
        _isNameTaken = isNameTaken;
        _desiredDisplayName = desiredDisplayName;
        _isPaste = isPaste;
    }

        override private function executeInternal():Void
        {
                if (_instanceId == null) {
                        _instanceId = utils.UID.generate();
                }
                if (_atomDef == null) {
                        _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
                }
                if (!_blueprint.internalAtoms.contains(_atomDef)) {
                        _blueprint.internalAtoms.push(_atomDef);
                }
                if (_atomInstance == null) {
                        _atomInstance = AssemblyFactory.createAtom(_typeId, _instanceId);
                        if (_atomInstance == null) {
                                trace('CreateAtomCommand ERROR: Factory failed to create $_typeId');
                                return;
                        }
                }

                // ═══════════════════════════════════════════════════════════════════
                // v1.3: Generate GLOBALLY unique display name + register in NamingService
                // ═══════════════════════════════════════════════════════════════════
                // Only for newly created atoms (not restored from save).
                // Restored atoms get their displayName from initialState via restoreState()
                // and are registered by Assembly._createInternalInstances().
                //
                // Three cases handled:
                //   (a) Paste with desiredDisplayName="Foo_2" → "Foo_3" (bumped)
                //   (b) Paste with desiredDisplayName="Foo"    → "Foo_1" (forced suffix)
                //   (c) Create with desiredDisplayName=null    → "Button" (or "Button_1" if taken)
                //
                // The predicate defaults to NamingService.isInstanceNameTaken
                // if caller didn't supply one (e.g., legacy 6-arg callers).
                // ═══════════════════════════════════════════════════════════════════
                if (_atomInstance.displayName == null || _atomInstance.displayName == _atomInstance.type) {
                        // v1.3: Predicate signature is (String, ?String) -> Bool — matches both
                        // NamingService.isInstanceNameTaken and EditorContext.isNameTakenGlobally
                        // directly, no adapter needed.
                        var predicate:(String, ?String) -> Bool = (_isNameTaken != null)
                                ? _isNameTaken
                                : core.logic.NamingService.isInstanceNameTaken;
                        var uniqueName = AssemblyFactory.generateUniqueDisplayName(
                                _typeId,
                                predicate,
                                _desiredDisplayName,
                                _isPaste
                        );
                        _atomInstance.displayName = uniqueName;
                }
                // Register (defensively — if for some reason displayName was set by
                // constructor, still ensure global uniqueness before insertion)
                core.logic.NamingService.registerInstanceName(_atomInstance.displayName, _instanceId);

                _assembly.internalAtoms.set(_instanceId, _atomInstance);
                Impulsys.quickEmit(EventType.ATOM_RESTORED, {
                        assemblyId: _assembly.id,
                        id: _instanceId,
                        x: _posX,
                        y: _posY,
                        atom: _atomInstance
                });
                complete();
        }

    override public function undo():Void {
        _blueprint.internalAtoms.remove(_atomDef);

        var inst = _assembly.internalAtoms.get(_instanceId);
        if (inst != null) {
            if (Std.isOfType(inst, IDisposable)) {
                try { cast(inst, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing atom: $e'); }
            }
            _assembly.internalAtoms.remove(_instanceId);
        }

        _atomInstance = null;

        Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, id: _instanceId});
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}