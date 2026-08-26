package editor;

import core.base.Assembly;
import core.base.Atom;
import core.base.Contact;
import core.base.ConductorPort;
import core.data.Blueprint.ConnectionPoint;
import core.types.ContactType;

/**
 * PORT NAME RESOLVER v1.0
 * ═══════════════════════════════════════════════════════════════════════════
 * EXTRACTED FROM EditorContext v2.13 — Episod A of the Editor de-god-ification.
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Stateless utility for resolving ConductorPort references from blueprint
 * ConnectionPoints against live Assembly port sets, accounting for the full
 * historical zoo of name-drift scenarios accumulated in EditorContext:
 *
 *   1. exact externalName match (the trivial case)
 *   2. internalName match (the "stale parent name" case — GroupAtoms wrote
 *      internalName; refreshExternalPortNames renamed the port to a semantic
 *      externalName; the parent blueprint never caught up)
 *   3. simple suffix match ("X_requestedName" against externalName)
 *   4. PROGRESSIVE suffix match (v2.11 — semantic-name drift survivor:
 *      nested atom renamed between pop cycles)
 *   5. LEGACY ALIAS match (v2.13 — pre-stable-naming port names like
 *      "Button_out", "incoming_1" resolving to migrated stable ports)
 *
 * Plus the inverse direction: resolving a ConnectionPoint {atomId, contactName}
 * to a live Contact on a parent assembly (SELF port or internal atom input/
 * output).
 *
 * Plus: remapParentConnectionsToPortNames — rewrites parent blueprint
 * ConnectionDefs in-place so endpoint contactNames track the child's
 * refreshed externalNames. Mirrors what a save→load cycle would have
 * produced in memory (load-symmetry invariant).
 *
 * ALL methods are pure: caller passes the parent assembly explicitly,
 * gets a Contact / ConductorPort / Bool back. No EditorContext dependency,
 * no Impulsys, no subscriptions, no global state.
 *
 * Migration guide for EditorContext callers:
 *   ─ resolveContactInParent(point)                     → _portResolver.resolveContactInParent(point, currentAssembly)
 *   ─ resolveContactInParent(point, ctx)                → _portResolver.resolveContactInParent(point, ctx)
 *   ─ resolveAssemblyInParent(atomId)                   → _portResolver.resolveAssemblyInParent(atomId, currentAssembly)
 *   ─ resolveAssemblyInParent(atomId, ctx)              → _portResolver.resolveAssemblyInParent(atomId, ctx)
 *   ─ findPortByContactSuffix(asm, name, type)           → _portResolver.findPortByContactSuffix(asm, name, type)
 *   ─ findPortByProgressiveSuffix(asm, name)            → _portResolver.findPortByProgressiveSuffix(asm, name, null)
 *   ─ findPortByProgressiveSuffix(asm, name, type)      → _portResolver.findPortByProgressiveSuffix(asm, name, type)
 *   ─ _resolveChildPort(name, asm, byInternal)          → _portResolver.resolveChildPort(name, asm, byInternal)
 *   ─ _connRefersTo(atomId, childAsm)                   → _portResolver.connRefersTo(atomId, childAsm, currentAssembly)
 *   ─ remapParentConnectionsToPortNames(childAsm)       → _portResolver.remapParentConnectionsToPortNames(childAsm, currentAssembly)
 */
class PortNameResolver
{
        public function new() {}

        // ═══════════════════════════════════════════════════════════════════
        // PORT LOOKUPS ON A CHILD ASSEMBLY
        // ═══════════════════════════════════════════════════════════════════

        /**
         * Find a port on the target Assembly whose externalName matches
         * the requested name, falling back to a simple suffix pattern.
         *
         * Used when parent.bp.internalConnections references a port by its
         * OLD externalName (e.g., "Pass_in"), but refreshExternalPortNames()
         * has changed the port's externalName to a longer composed form
         * (e.g., "Custom_Assembly_1_Pass_in"). We match by suffix to find
         * the right port.
         *
         * Heuristic:
         *   - Exact match: externalName == requestedName (preferred)
         *   - Suffix match: externalName ends with "_" + requestedName
         *   - Type filter: only consider ports of the requested type
         *
         * @param asm           Target assembly
         * @param requestedName The contactName from parent's blueprint
         * @param type          Expected port type (INPUT or OUTPUT)
         * @return Matching ConductorPort or null
         */
        public function findPortByContactSuffix(asm:Assembly, requestedName:String, type:ContactType):ConductorPort
        {
                if (asm == null || asm.ports == null) return null;

                // 1. exact match
                for (p in asm.ports)
                {
                        if (p != null && p.externalName == requestedName && p.type == type)
                        {
                                return p;
                        }
                }

                // 2. suffix match ("X_requestedName")
                // Haxe String has no endsWith() method — use StringTools.endsWith().
                var suffix = "_" + requestedName;
                for (p in asm.ports)
                {
                        if (p == null || p.externalName == null) continue;
                        if (p.type != type) continue;
                        if (StringTools.endsWith(p.externalName, suffix))
                        {
                                return p;
                        }
                }

                return null;
        }

        /**
         * PROGRESSIVE suffix matching — the weapon against semantic port-name
         * drift (EditorContext v2.11).
         *
         * Port externalNames are composed from the connected atom's
         * displayName ("Custom_Assembly_2_Com_Port_close"). When that
         * displayName changes between pop cycles, the parent blueprint
         * keeps the OLD composed name. Exact / internalName / full-suffix
         * matchers all fail on such drift.
         *
         * This matcher strips leading tokens of the requested name, one at
         * a time, and at each level collects the ports (of the requested
         * type, when given) whose externalName ends with "_" + tail. The
         * FIRST level with EXACTLY ONE candidate wins — the match is
         * unambiguous.
         *
         *   requested: "Custom_Assembly_2_Com_Port_close"
         *   ports:      "Custom_Assembly_1_Com_Port_close" ... (unique tails)
         *   level tail "Com_Port_close" -> unique -> MATCH
         *
         * Ambiguity at every level returns null (never mis-wire), with a trace.
         *
         * @param asm           Target assembly
         * @param requestedName Stale contactName from the parent blueprint
         * @param type          Optional port type filter (INPUT / OUTPUT)
         * @return The uniquely matching ConductorPort or null
         */
        public function findPortByProgressiveSuffix(asm:Assembly, requestedName:String, ?type:Null<ContactType>):ConductorPort
        {
                if (asm == null || asm.ports == null || requestedName == null) return null;

                var tokens:Array<String> = requestedName.split("_");
                if (tokens.length < 2) return null; // nothing to strip

                // Walk from the longest tail to the shortest, dropping one
                // leading token per level. Stop at the tail of length 1
                // (shorter tails are too generic to be trusted).
                var level:Int = 1;
                while (level < tokens.length - 1)
                {
                        var tail:String = tokens.slice(level).join("_");
                        var suffix:String = "_" + tail;
                        var candidate:ConductorPort = null;
                        var count:Int = 0;
                        for (p in asm.ports)
                        {
                                if (p == null || p.externalName == null) continue;
                                if (type != null && p.type != type) continue;
                                if (p.externalName == requestedName) continue; // exact tried already
                                if (StringTools.endsWith(p.externalName, suffix))
                                {
                                        candidate = p;
                                        count++;
                                        if (count > 1) break; // ambiguous — stop early
                                }
                        }
                        if (count == 1)
                        {
                                trace('🔄 Progressive suffix match: "${requestedName}" ~ "${candidate.externalName}" (tail "${tail}")');
                                return candidate;
                        }
                        level++;
                }
                trace('⚠️ Progressive suffix match: no unique port for "${requestedName}"');
                return null;
        }

        /**
         * Resolve a child port by contactName, in priority order:
         *   1. exact externalName
         *   2. internalName (the common stale-name case)
         *   3. LEGACY ALIAS (pre-stable-naming name, v2.13)
         *   4. simple suffix "_name"
         *   5. progressive suffix (v2.11)
         *
         * @param contactName  The contactName from the parent blueprint
         * @param childAsm     The assembly whose ports we are searching
         * @param byInternal   Pre-built lookup: internalName → ConductorPort
         *                     (caller builds this once for efficiency when
         *                     iterating multiple connections against the
         *                     same child — see remapParentConnectionsToPortNames)
         */
        public function resolveChildPort(contactName:String, childAsm:Assembly, byInternal:Map<String, ConductorPort>):ConductorPort
        {
                if (childAsm == null || childAsm.ports == null) return null;

                // 1. Exact externalName
                for (port in childAsm.ports)
                {
                        if (port != null && port.externalName == contactName) return port;
                }
                // 2. internalName (the common stale-name case)
                if (byInternal != null && byInternal.exists(contactName)) return byInternal.get(contactName);
                // 3. v2.13: LEGACY ALIAS — pre-stable-naming port names
                //    ("Button_out", "incoming_1") resolve to the migrated
                //    stable port. remapParentConnectionsToPortNames() then
                //    rewrites the connection in place, so the alias heals
                //    itself out of the blueprint after first resolution.
                var aliasPort = childAsm.getPortByAnyName(contactName);
                if (aliasPort != null) return aliasPort;
                // 4. Suffix "_name"
                var suffix = "_" + contactName;
                for (port in childAsm.ports)
                {
                        if (port != null && port.externalName != null
                                && StringTools.endsWith(port.externalName, suffix)) return port;
                }
                // 5. v2.11: PROGRESSIVE suffix — semantic names drift when
                //    the nested atom gets renamed.
                return findPortByProgressiveSuffix(childAsm, contactName, null);
        }

        // ═══════════════════════════════════════════════════════════════════
        // CONNECTION ENDPOINTS AGAINST A PARENT ASSEMBLY
        // ═══════════════════════════════════════════════════════════════════

        /**
         * Does the connection atomId (runtime or template) refer to the
         * given child assembly, when resolved against the parent's idMap?
         *
         * @param atomId    The atomId as stored in the blueprint ConnectionDef
         * @param childAsm  The candidate child assembly
         * @param parentAsm The parent assembly whose idMap resolves templates → runtime
         */
        public function connRefersTo(atomId:String, childAsm:Assembly, parentAsm:Assembly):Bool
        {
                if (atomId == null || childAsm == null || parentAsm == null) return false;
                if (atomId == childAsm.id) return true;
                var realAtomId = parentAsm.idMap.get(atomId);
                if (realAtomId == null) realAtomId = atomId;
                return realAtomId == childAsm.id;
        }

        /**
         * Resolve an atomId (template or runtime) to an Assembly instance
         * in the parent's internalAtoms.
         *
         * @param atomId  The atomId from a blueprint ConnectionDef
         * @param ctx      The parent assembly whose internalAtoms + idMap to use
         * @return The Assembly instance, or null if the atom is not an Assembly
         *         or does not exist in ctx.
         */
        public function resolveAssemblyInParent(atomId:String, ctx:Assembly):Assembly
        {
                if (atomId == null || atomId == "SELF") return null;
                if (ctx == null) return null;
                var realAtomId = ctx.idMap.get(atomId);
                if (realAtomId == null) realAtomId = atomId;
                var obj = ctx.internalAtoms.get(realAtomId);
                if (obj == null) return null;
                if (Std.isOfType(obj, Assembly))
                {
                        return cast(obj, Assembly);
                }
                return null;
        }

        /**
         * Resolves a Contact in the context of the parent assembly.
         *
         * Leverages the existing Atom.getInput/getOutput methods, which
         * already know how to find Assembly ports by their externalName.
         *
         * @param point  ConnectionPoint {atomId, contactName}
         *              If atomId == "SELF": resolves against the parent's
         *              own wall ports (port.internal contact).
         *              Otherwise: resolves against the referenced atom's
         *              getInput/getOutput.
         * @param ctx    The parent assembly whose internalAtoms + idMap + ports
         *               to use. Mandatory — this is a stateless utility.
         * @return The live Contact, or null if the ConnectionPoint cannot
         *         be resolved against the current parent state.
         */
        public function resolveContactInParent(point:ConnectionPoint, ctx:Assembly):Contact
        {
                if (point == null || ctx == null) return null;
                if (point.atomId == "SELF")
                {
                        var port = ctx.ports.get(point.contactName);
                        return port != null ? port.internal : null;
                }
                else
                {
                        // Resolve Template ID to Runtime ID
                        var realAtomId = ctx.idMap.get(point.atomId);
                        if (realAtomId == null) realAtomId = point.atomId;

                        var obj = ctx.internalAtoms.get(realAtomId);
                        if (obj == null) return null;

                        var atom:Atom = cast obj;

                        // getInput and getOutput search by Contact.name.
                        // For Assemblies, external contacts are registered with externalName.
                        // For simple atoms, contacts are registered with their standard name.
                        // This perfectly matches the contactName stored in the parent's blueprint!
                        var c = atom.getInput(point.contactName);
                        if (c != null) return c;

                        return atom.getOutput(point.contactName);
                }
        }

        // ═══════════════════════════════════════════════════════════════════
        // PARENT-SIDE BLUEPRINT REMAP
        // ═══════════════════════════════════════════════════════════════════

        /**
         * Remap PARENT blueprint connection contactNames to the actual
         * (refreshed) external port names of the child assembly.
         *
         * WHY THIS EXISTS (EditorContext v2.7 — exit-crash forensics):
         * Assembly.refreshExternalPortNames() renames the child's ports
         * (PinDef.externalName + recreated ConductorPort), but the PARENT's
         * blueprint.internalConnections still references the OLD contactName
         * (often the port's internalName, e.g. "outgoing_1", while the port
         * is now called "Mini_Audio_Capture_buffer"). Reconstruction then
         * fails to resolve contacts ("cOut=null → FAILED to link"), wires
         * vanish, and the app later crashes on the inconsistent graph.
         * A save→load cycle works fine because the DISK file stores the
         * refreshed externalName — this remap restores the SAME consistency
         * in memory (load-symmetry).
         *
         * Matching strategy per connection endpoint that references the
         * child assembly (by runtime or template id):
         *   1. exact externalName match → OK, nothing to do
         *   2. contactName == port.internalName → remap (the common case:
         *      parent connections created before the first refresh, or via
         *      GroupAtoms which stores internalName)
         *   3. suffix match: externalName ends with "_" + contactName → remap
         *
         * @param childAsm   The assembly whose ports were just refreshed
         * @param parentAsm  The assembly whose blueprint.internalConnections
         *                   will be remapped in-place
         */
        public function remapParentConnectionsToPortNames(childAsm:Assembly, parentAsm:Assembly):Void
        {
                if (childAsm == null || childAsm.ports == null) return;
                if (parentAsm == null || parentAsm.blueprint == null) return;
                var bp = parentAsm.blueprint;
                if (bp == null || bp.internalConnections == null) return;

                // Build lookup: internalName → ConductorPort
                var byInternal = new Map<String, ConductorPort>();
                for (port in childAsm.ports)
                {
                        if (port != null && port.internalName != null)
                        {
                                byInternal.set(port.internalName, port);
                        }
                }

                var remapped = 0;
                for (conn in bp.internalConnections)
                {
                        // TO side references the child?
                        if (conn.to.atomId != "SELF" && connRefersTo(conn.to.atomId, childAsm, parentAsm))
                        {
                                var port = resolveChildPort(conn.to.contactName, childAsm, byInternal);
                                if (port != null && port.externalName != conn.to.contactName)
                                {
                                        trace('🔄 remap to: "${conn.to.contactName}" → "${port.externalName}"');
                                        conn.to.contactName = port.externalName;
                                        remapped++;
                                }
                        }
                        // FROM side references the child?
                        if (conn.from.atomId != "SELF" && connRefersTo(conn.from.atomId, childAsm, parentAsm))
                        {
                                var port = resolveChildPort(conn.from.contactName, childAsm, byInternal);
                                if (port != null && port.externalName != conn.from.contactName)
                                {
                                        trace('🔄 remap from: "${conn.from.contactName}" → "${port.externalName}"');
                                        conn.from.contactName = port.externalName;
                                        remapped++;
                                }
                        }
                }
                if (remapped > 0)
                {
                        trace('🔄 remapParentConnectionsToPortNames: remapped $remapped endpoint names for "${childAsm.blueprint.id}"');
                }
        }
}
