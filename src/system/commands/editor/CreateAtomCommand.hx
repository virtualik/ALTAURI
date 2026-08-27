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
 * CREATE ATOM COMMAND v1.5 (Self-Containment Guards + Paste State Replication)
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
// v1.4: SELF-CONTAINMENT GUARD — placing a blueprint inside itself (via a
// stale registry alias key) drove the Assembly constructor into infinite
// recursion (Test 1 stack overflow, 2026-08-24). Identity compare catches
// every alias of the same live Blueprint object.
//
// v1.5 (WP-2 Paste Semantics):
//  - INDIRECT containment guard: placing an ANCESTOR assembly inside its
//    descendant (template cycle X→Y→X) drove the same stack-overflow class;
//    now caught transitively (alias-proof), same clean ABORT as v1.4.
//  - GHOST-FIX reorder: the factory call now runs BEFORE the AtomDef is
//    pushed into the blueprint — a factory failure (e.g. pasting a stale
//    clipboard entry whose blueprint was deleted from the library) no
//    longer leaks a ghost AtomDef into the save.
//  - undo() no-ops for commands whose execution aborted — no phantom
//    ATOM_DELETED emission for an atom that was never created.
//  - New optional trailing args (initialValues, visualMode): paste now
//    replicates the source instance's state (toggle position, assembly
//    internalStates, driver configs) and the node's visual mode.
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

    // v1.5: Instance-state replication for paste
    private var _initialValues:Dynamic;
    private var _visualMode:String;

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
     * @param initialValues       Optional per-instance state snapshot (paste).
     *                            Fed to AssemblyFactory.createAtom →
     *                            restoreState. displayName must be stripped
     *                            by the caller — the naming path owns names.
     * @param visualMode          Optional NodeVisualMode string ("LIGHT" /
     *                            "MEDIUM" / "HEAVY") persisted to the AtomDef
     *                            so the pasted node renders like the source.
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
        ?isPaste:Bool = false,
        ?initialValues:Dynamic = null,
        ?visualMode:String = null
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
        _initialValues = initialValues;
        _visualMode = visualMode;
    }

        override private function executeInternal():Void
        {
                // ═══ v1.4: SELF-CONTAINMENT GUARD (alias-proof). ═══
                var registryBp = library.AtomRegistry.get(_typeId);
                if (registryBp != null && registryBp == _blueprint)
                {
                        trace('CreateAtomCommand: ABORTED — "${_typeId}" cannot be placed inside itself (blueprint identity match).');
                        return;
                }

                // ═══ v1.5: INDIRECT SELF-CONTAINMENT GUARD (template cycle kill). ═══
                // The v1.4 guard above catches only DIRECT self-placement (X
                // inside X). Placing an ANCESTOR inside its DESCENDANT (X inside
                // Y, where an instance of Y lives inside X) creates a template
                // cycle X→Y→X: the Assembly constructor recurses infinitely
                // (the Test 1 stack-overflow class). Reachable via paste (the
                // clipboard stores global typeIds) AND via the Add menu (the
                // library provider hides only the CURRENT blueprint, not its
                // ancestors). Abort when the blueprint being placed transitively
                // contains the target context blueprint.
                if (registryBp != null && !registryBp.isNative
                        && _containsBlueprint(_blueprint, registryBp, 0))
                {
                        trace('CreateAtomCommand: ABORTED — "${_typeId}" transitively contains "${_blueprint.id}" (template cycle X→Y→X).');
                        return;
                }

                if (_instanceId == null) {
                        _instanceId = utils.UID.generate();
                }
                // v1.5 GHOST-FIX REORDER: create the instance FIRST; push the
                // AtomDef only after the factory succeeds. The old order pushed
                // the def before construction — a factory failure left a ghost
                // AtomDef in the blueprint: the exact corruption class that
                // Assembly v2.10 self-heals at load (and that never should be
                // written in the first place).
                if (_atomInstance == null) {
                        _atomInstance = AssemblyFactory.createAtom(_typeId, _instanceId, _initialValues);
                        if (_atomInstance == null) {
                                trace('CreateAtomCommand ERROR: Factory failed to create $_typeId');
                                return;
                        }
                }
                if (_atomDef == null) {
                        _atomDef = { instanceId: _instanceId, typeId: _typeId, x: _posX, y: _posY };
                        if (_visualMode != null) {
                                _atomDef.visualMode = _visualMode;
                        }
                }
                if (!_blueprint.internalAtoms.contains(_atomDef)) {
                        _blueprint.internalAtoms.push(_atomDef);
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
                //
                // v1.5: _initialValues (paste state snapshot) arrives with its
                // displayName STRIPPED by EditorActionHandler, so the
                // restoreState inside the factory never sets a name — the
                // bumped unique name generated below always wins, exactly as
                // before v1.5.
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
                        atomId: _instanceId,
                        x: _posX,
                        y: _posY,
                        atom: _atomInstance,
                        visualMode: _atomDef.visualMode // v1.5 (WP-2): optional — paste visual-mode replication; null = default
                });
                complete();
        }

    override public function undo():Void {
        // v1.5: no-op when execution aborted (factory failure or containment
        // guards): nothing was inserted, so neither a removal nor an
        // ATOM_DELETED emission is warranted. The command still sits on the
        // undo stack (UndoManager pushes unconditionally) — undoing it just
        // falls through to the previous command's history entry.
        if (_atomDef == null
                || (!_blueprint.internalAtoms.contains(_atomDef)
                    && _assembly.internalAtoms.get(_instanceId) == null)) {
            return;
        }
        _blueprint.internalAtoms.remove(_atomDef);

        var inst = _assembly.internalAtoms.get(_instanceId);
        if (inst != null) {
            if (Std.isOfType(inst, IDisposable)) {
                try { cast(inst, IDisposable).dispose(); } catch (e:Dynamic) { trace('Error disposing atom: $e'); }
            }
            _assembly.internalAtoms.remove(_instanceId);
        }

        _atomInstance = null;

        Impulsys.quickEmit(EventType.ATOM_DELETED, {assemblyId: _assembly.id, atomId: _instanceId});
    }

    /**
     * v1.5: Does `from` (transitively, via internalAtoms typeIds) reference
     * `target`? Alias-proof: a registry key pointing at the same Blueprint
     * object counts as a reference. Depth cap 64 sits far beyond any
     * legitimate assembly nesting and stops pathological walks; corrupted
     * self-referencing data that slips past the cap is still caught by the
     * AssemblyFactory v1.5 construction cycle guard at instantiation time.
     */
    private function _containsBlueprint(target:Blueprint, from:Blueprint, depth:Int):Bool
    {
        if (target == null || from == null || from.internalAtoms == null) return false;
        if (depth > 64) return false;
        for (def in from.internalAtoms)
        {
            if (def == null || def.typeId == null) continue;
            if (def.typeId == target.id) return true;
            var sub:Blueprint = library.AtomRegistry.get(def.typeId);
            if (sub == null || sub.isNative) continue;
            if (sub == target || sub.id == target.id) return true;
            if (_containsBlueprint(target, sub, depth + 1)) return true;
        }
        return false;
    }

    override public function getDescription():String return 'Create Atom $_typeId';
}
