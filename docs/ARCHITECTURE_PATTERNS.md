# ALTAURI: Architecture Patterns & Design Principles

This document describes the key architectural decisions, patterns and principles behind ALTAURI. It serves as a reference for development, onboarding of new contributors, and preservation of architectural integrity as the system scales.

> **Companion document:** [ARCHITECTURE.md](ARCHITECTURE.md) — the full architecture map (domains, layers, packs, classes).
> **Edition:** v2.0 (EN), 2026-09-06

---

## 1. Structural Patterns

### Dual Naming (External/Internal)

`ConductorPort` stores two names for one port:

- `externalName`: visible to the parent; used in the parent's `bp.internalConnections` and in `atom.getInput()`.
- `internalName`: visible inside the assembly; used as the key in `Assembly.ports` and as `SELF.xxx` inside that assembly's `bp.internalConnections`.

**Purpose:** isolates the two naming systems and prevents collisions across assembly nesting and hot reloads.

### Gateway Topology

`ConductorPort` acts as a gateway with a deterministic flow direction:

- For INPUT: signal flows `external → internal → atom.input`.
- For OUTPUT: signal flows `atom.output → internal → external`.

Direct `external → atom` connections are forbidden (v2.0 fix), which prevents signal duplication and infinite loops ("Delta Topology").

### Template/Runtime ID Duality

- **Template ID:** stable (stored in `bp.internalAtoms[i].instanceId`); survives application restarts.
- **Runtime ID:** regenerated on every instantiation via `UID.generate()`.

The `_idMap` in Assembly stores the mapping (templateId → runtimeId) and is used for translation in both directions: when saving to disk (runtime → template) and when loading (`_createInternalInstances` fills the map as template → runtime).

### Databank Architecture (Atom as Compute Core)

An atom is simultaneously:

- **(A) A compute core:** the `_process` function or a `Driver` interface implementation.
- **(B) A data bank:** contacts (`Contact`) as value storage.
- **(C) The source of truth:** the widget (`DeviceView`) is the "face" — it stores no business data and only reads/writes to the Atom. The widget can be destroyed and recreated — the data survives.

### One Atom = One Face

`DeviceViewRegistry` (singleton) guarantees that exactly one `DeviceView` exists per `atom.id`. The widget migrates between containers (`NodeView ↔ DevicePanel/Window`), but the instance remains the same — only `parent` and `scale` change.

### ECS Hybrid

The `ecs` package exists (`Entity/Component/Storage/Query/RenderSystem/World`) but is used hybridly with the traditional `Atom→Assembly` hierarchy. ECS handles positioning and culling, not business logic. This preserves the benefits of ECS for rendering without complicating the computation graph.

### Blueprint as Single Source of Truth (BP-SSOT)

A Blueprint is not just a description — it is the single source of truth for the schematic's structure. Runtime objects (`Assembly`, `Atom`, `Contact`) are merely a projection of the Blueprint. Any structural mutation is first recorded in the Blueprint (via a Command), and only then reflected in the runtime through synchronization (`rebuildInternalConnections`, `updateFromBlueprint`). This guarantees that the state on disk, in memory and on screen can always be brought to consistency.

### Zero-GC Audio Pipeline

For audio drivers (`MiniAudioAtom`, `BufferingAtom`) there is a strict ban on allocations during `update(dt)` or the audio callback. Pre-allocated ping-pong buffers, `LockFreeQueue` for cross-thread data transfer, and the batched propagation pattern (`setValueSilent` + single `propagateCurrentValue`) are used. A GC pause = an audio glitch, so memory is managed manually and predictably.

### NamingService Global Uniqueness

`NamingService` is a static singleton ensuring global uniqueness of atom display names and Blueprint names across all open editor contexts. Two independent namespaces:

- **Instance names:** `_instanceNames:Map<String, String>` (name → atomId). Automatic `_N` suffix on conflicts.
- **Blueprint names:** delegated to `AtomRegistry` for uniqueness checks.

**Used by:** `CreateAtomCommand` (v1.3, paste-aware naming via `generateUniqueDisplayName()`), `GroupAtomsCommand` (v3.7, `resolveUniqueBlueprintName()`), `NodeView` (v3.4, inline name editing via `resolveUniqueInstanceName()`), `Main.saveNewNamedAssembly()`.

### Provider Pattern for Context Menu

The v2.0 context menu uses the Provider pattern for dynamic content:

- **Interface:** `MenuEntryProvider` with `getEntries()`, `getCategory()`, `supportsSearch()`
- **Concrete providers:** `AtomLibraryProvider` (atoms from `AtomRegistry`), `AssemblyLibraryProvider` (user assemblies), `EditorCommandsProvider` (editor commands — Delete, Group, Add Port)
- **Benefit:** extensibility without modifying the menu core. New categories are added by creating a new provider.

### Category-Based Navigation

The two-panel context menu architecture:

- **`CategorySidebar`:** left/right panel with category buttons (Recent, Editor, Atoms, Assemblies)
- **`ContentPanel`:** right panel with the selected category's content
- **`SidebarPosition` enum:** configurable sidebar position (LEFT, RIGHT)
- The last active category is highlighted automatically when the menu opens

### Icon Resolution Pattern

`AtomRegistry.iconId` provides lazy icon loading:

- **PNG icon support:** each atom can have an associated icon
- **Fallback graphics:** if the icon is missing, a standard placeholder is drawn
- **Lazy loading:** icons load only on first display
- **Caching:** loaded icons are cached in `DeviceViewRegistry`

### Feature Detection + Sync User Gesture + Blob Fallback (HTML5)

For cross-browser compatibility of HTML5 atoms (notably `FileWriterAtom`) on older browsers (Android 9 / Chrome 126), a three-level pattern is used:

1. **Feature Detection:** check for the API before calling it. If `window.showSaveFilePicker` is absent, switch to fallback mode.
2. **Sync User Gesture:** call `showFilePicker()` synchronously from the mouse event handler. Asynchronous delivery via a Contact loses the gesture context, and the browser blocks the dialog.
3. **Blob Fallback:** use Blob + `URL.createObjectURL` + a dynamic `<a>` tag to download the file on older browsers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ FLOW: Feature Detection + Sync User Gesture + Blob Fallback                 │
│                                                                             │
│ User clicks "Select" button                                                 │
│  └──► Sync call: writerAtom.showFilePicker()                                │
│       ├──► Feature Detection: window.showSaveFilePicker != null?            │
│       │     ├──► YES: native Save File dialog → onFileSelected()            │
│       │     └──► NO: initFallbackMode() → _isFallbackMode = true            │
│  Data arrives via the "append" contact → appendData()                       │
│       ├──► fallback: _fallbackBuffer.add(data)                              │
│       └──► native: _stream.seek().write(data)                               │
│ User clicks "Close" → closeFile()                                           │
│       ├──► fallback: triggerFallbackDownload() (Blob → <a> click)           │
│       └──► native: _stream.close()                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Why the synchronous call matters:**

- ✗ WRONG: Button click → contact value → `update()` → `readInputs()` → `showFilePicker()` — the browser blocks the dialog (no user gesture context).
- ✓ CORRECT: Button click → `writerAtom.showFilePicker()` (sync) — the dialog opens.

---

## 2. Behavioral Patterns

### Command + Snapshot (Undo/Redo)

Every user operation (`ConnectCommand`, `GroupAtomsCommand`, `DeleteAtomCommand`, `MoveNodeCommand`, etc.) implements `Command` with `executeInternal()` and `undo()`. For complex operations (e.g., atom grouping) a dedicated `GroupAtomsSnapshot` class captures the "before" and "after" state for correct undo.

### MacroCommand

Composition of several commands into one transaction (`MacroCommand.addCommand(...)` → `execute()` runs all). Used, for example, to delete a group of atoms together with their wires, or for batch move operations.

### Event Bus (Impulsys)

The static `Impulsys` event bus with typed `EventType`s. Any component can `subscribeToImpulse` / `quickEmit`. It decouples `NodeEditor`, `NodeView`, `WireRenderer`, `Main`, `DevicePanel` etc. — they never reference each other directly, communicating via impulses (`ATOM_DELETED`, `ASSEMBLY_PORTS_CHANGED`, `REDRAW_WIRES`, `PORT_REMOVED`, `CANVAS_RIGHT_CLICKED`).

### Listener Reference Identity

Handlers are stored in named class fields (`_onPortDragStart`, `_onRedrawWires`, etc.) rather than created as inline anonymous functions. This is critical because `Array.remove()` uses reference equality — a freshly created anonymous function would never match the original, and `removeImpulse` would silently fail. (Fixed in `NodeEditor` v4.5.)

### Reattach Pattern

When an object is reconstructed (`dispose` + `createAtom` with the same ID), existing Views are not recreated but "reattached" to the new instance via `reattachToAtom(newAtom)`. This preserves the NodeView's canvas position, its selection state, and the parent's `Map<String, NodeView>` references.

### Load-Symmetric Reconstruction

Any state-mutating path (exiting an assembly, undo/redo, hot reload) must bring the system to the same state as a load-from-disk path. Implemented via full rebuild (`dispose` + `AssemblyFactory.createAtom`) instead of partial updates (`updateFromBlueprint`).

### Pre-Save Sync

Before disk serialization, sync methods align the in-memory blueprint with what should be on disk (`prepareCurrentAssemblyForSave` → `refreshExternalPortNames` + `syncDisplayNamesToBlueprint` + `syncConnectionsToTemplateIds` + `registerBlueprint`). Guarantees disk and memory consistency.

### Hot-Start Initialization

Two-phase assembly initialization:

1. `isInitializing = true` + all atoms and connections created with `suppressPropagation = true` (no signals flow).
2. `_processPendingSignals()` unfreezes the atoms and runs the final synchronization via `scheduleNextTick`. Prevents a "cold start" with null values and first-pass oscillation.

### Active Driver Registration

Atoms flagged `isActive` register in `DriverManager` and receive a per-frame `update(dt)`. This is for active components (`MiniAudioAtom`, `SignalGenerator`, `ComPortAtom`) that generate data independently of input signals.

### State Restoration via Template ID

`getPersistentState()` / `restoreState()` use the Template ID as the key in `internalStates`, not the Runtime ID. This guarantees nested states survive a JSON save/load cycle (the Runtime ID is regenerated on every load).

### Batched Driver Update Pattern

Active drivers (`MiniAudioAtom`, `SystemVUMeterAtom`, `FFTAtom`) use two-phase output: phase 1 — `setValueSilent()` for all output contacts (no propagation trigger); phase 2 — a single `propagateCurrentValue()` per contact. This reduces TickGenerator load from O(N×M) to O(N+M), where N is outputs and M is subscribers.

### Edge Detection for UI Events

Events that trigger heavy redraws (`OSCILOSCOPE_SHAPE_CHANGED`, `ASSEMBLY_PORTS_CHANGED`) are emitted only when the value actually changes, not every frame. Implemented by comparing the new value with a cached old value before emitting. Prevents an avalanche of redundant redraws in stable states.

### Broadcast Storm Prevention

With deep assembly nesting (N levels), every `REDRAW_WIRES` emit triggered N concurrent `rebuildAll()` calls — O(N) work per event, causing UI freezes.

**Solution:** `NodeEditor.isActive` flag. `EditorContext.push()` sets the parent's `isActive = false`. `EditorContext.pop()` restores it to `true` + `forceFullRedraw()`. Handlers early-return when `!isActive`.

### Paste-Aware Naming

`AssemblyFactory.generateUniqueDisplayName()` (v1.3) parses the existing `_N` suffix from the desired name. When `isPaste == true`, the suffix is forced to increment from the parsed number (e.g., `"Foo_2"` → `"Foo_3"`, not `"Foo_2_1"`). When `isPaste == false`, the base name is used as-is if free.

### Wire Hit Sprite Selection

Wire sprites were drawn as a single line with thickness `WIRE_THICKNESS` (2–3px), making selection nearly impossible at zoom-out.

**Solution (v1.6):** each wire now consists of TWO sprites:

- `hitSprite`: invisible (alpha=0), thick (12px), `mouseEnabled=true` — receives all click events.
- `sprite`: visible, thin, `mouseEnabled=false` — drawn on top, purely visual.

### Native Windows Drag with Tick Injection

`SendMessage(WM_NCLBUTTONDOWN, HTCAPTION)` blocks the Haxe thread until mouse-up, freezing the UI during window drag.

**Solution (v3.7):** `SetTimer(15ms)` → `_dp_DragTimerProc` → `_onDragTick()` → force Lime logic cycle + OpenFL render + `SwapBuffers`. Achieves ~60 FPS during native drag.

### DevicePanel Maximize/Restore Callback Architecture

`DevicePanel` is a Sprite inside the Main Window — it cannot resize the OS window directly. `Main.hx` owns the `lime.ui.Window` reference.

**Solution (v3.8):** `onToggleMaximize` callback. DevicePanel sends the request → Main.hx controls the OS window → `setMaximizedState()` updates the button icon.

### Recent Actions Tracking

`RecentMenuTracker` — a singleton tracking the user's recent actions:

- **FIFO history:** stores the last N actions (default 10)
- **Auto-record:** records actions automatically via `Impulsys` (`ATOM_CREATED`, `ASSEMBLY_CREATED`, `ATOMS_GROUPED`)
- **RecentSection:** displays the history in the context menu
- **Quick access:** the user can quickly repeat a recent action

### Smart Menu Positioning

`MenuBoundsCalculator` provides smart context-menu positioning:

- **Stage bounds clamping:** the menu never leaves the stage
- **Overflow handling:** if the menu doesn't fit on the right, it opens on the left (and vice versa)
- **Vertical adjustment:** if the menu is too tall, it shifts upward
- Guarantees the menu is always fully visible

### Search & Filter Pattern

`SearchBar` provides real-time menu filtering:

- **Instant filtering** on every keystroke
- **Placeholder text:** "Search atoms..."
- **Focus styling** for the active search field
- **Case-insensitive;** multi-field search (name, category, description)

### Display Mode Switching

The `DisplayMode` enum switches display modes:

- **LIST mode:** vertical list for commands (Delete, Group, Add Port)
- **GRID mode:** a 3–4 column grid for atoms and assemblies
- Runtime switching: the mode is determined automatically by content type
- **`MenuItemGrid`:** a grid container with a configurable column count

---

## 3. Safety Patterns

### Topology Guard / Transaction

`TickGenerator.isTopologyLocked()` is set during graph mutations (`GroupAtoms`, `Undo/Redo`, port deletion). During the lock, `Contact._receiveValue` and `propagateCurrentValue` skip propagation and defer the task via `tg.deferTopologyTask(...)`. Prevents use-after-free when an atom is disposed mid-signal-pass.

### Safety Net / Defensive Sanitization

On three levels:

1. `ProjectManager._sanitizeConnections` removes ghost connections from JSON at load time.
2. `Assembly._createInternalConnections` logs and removes links with unresolvable atomIds.
3. `WireRenderer.rebuildAll` removes sprites for links missing from the blueprint.

Each level is the last line of defense before the next. "Defense in Depth".

### Quarantine System

`Assembly` has `_isInQuarantine` and `_quarantineReason`. Allows temporarily isolating a problematic assembly (e.g., on cycle detection or infinite oscillation) without destroying it.

### Oscillation Protection

`Contact` tracks `_changeCount` within an `OSCILLATION_WINDOW` (1 second). If changes exceed `CHANGES_PER_SECOND_LIMIT` (600), the contact is marked `_oscillationBlocked = true` and stops propagating. Additionally, `MAX_PROPAGATION_DEPTH = 100` guards against infinite recursion.

### @:volatile Disposal Flag

`Atom._isDisposed` is marked `@:volatile`, which on the C++ target forces the thread to always read the value from RAM, not a register. Critical for the audio thread (`MiniAudioAtom`), which checks `_isDisposed` in its callback — without `@:volatile` the compiler could cache `false` in a thread register, and after a `dispose()` on the main thread the audio thread would keep running with a stale flag.

### Stage-Aware Rendering

`getPortPosition` returns `null` if the port sprite is not on stage. `WireRenderer.getWirePoint` does the same for SELF ports. Wires with null endpoints are skipped in `rebuildAll()` and drawn on the next cycle once the ports are staged. (Fixed in `NodeView` v3.5.3 and `WireRenderer` v1.5.)

### Reentrancy-safe Guards

Flags like `_isActivating` in `DeviceView` prevent recursive activation; `_isScheduled` in `Atom` prevents double-queueing; `_isLoading` in `ProjectIO` ignores duplicate load calls.

### Safe Dispose Pattern (WinHTTP / WMF)

For blocking C++ calls (`WinHttpReadData`, `MFPlay.Stop`), a forced unlock from the main thread precedes `join()`:

- `RP_CancelRequest()` → `WinHttpCloseHandle(hRequest)` → `WinHttpReadData()` returns an error → the worker thread exits cleanly.
- `isMfStopped` flag + polling in `update(dt)` → guarantees STA apartment usage without `haxe.Timer.delay`.

### Circuit Breaker for Nested Assemblies

Protection against circular references A→B→A during `resolveContact` / `getTemplateId`. Implemented via a nesting-depth counter (`MAX_NESTING_DEPTH = 10`) plus an explicit check `asm.blueprint.id == currentBpId` before entering. On overflow — returns `null` + a trace warning. Already present in `GroupAtomsCommand.validateNoCircularReference()` and `hasCircularReference()`.

### Interactive Target Guard

`NodeView.isInteractiveTarget(target)` walks up the display list from the event target to the NodeView, checking whether any ancestor is an interactive element (DeviceView, InlineParameterEditor, INPUT TextField). Prevents node drag when clicking on widgets.

### Mouse Event Isolation

`DeviceView.addMouseIsolation()` adds a `MOUSE_DOWN` listener that calls `stopPropagation()`, preventing the parent `NodeView` from starting a drag when the user interacts with a widget. Defense-in-depth with `isInteractiveTarget()`.

### Blueprint Sanitization (v2.4)

`ProjectManager._sanitizeConnections()` removes ghost connections at load time. A connection is "ghost" if it references a non-existent atomId or SELF port. The first line of defense against corrupted save files.

### Memory Management Patterns

The memory-leak prevention system:

**Correct dispose order:**

1. `DeviceView.dispose()` — unsubscribe from Impulsys, remove from DeviceViewRegistry
2. `Contact.unsubscribe()` — remove all subscribers
3. `Atom.dispose()` — release resources, mark `_isDisposed = true`
4. `AssemblyFactory.cleanup()` — remove from registries

**Leak checks:**

- `Impulsys.getListenerCount()` — monitor subscriber count
- `DeviceViewRegistry.getCount()` — verify active widget count
- `NamingService.getInstanceCount()` — verify registered name count

**Automated tests:**

- create/dispose cycles to verify no leaks
- registry cleanup checks after atom deletion
- memory monitoring during long sessions

---

## 4. ALTAURI-Specific Patterns

### Logic vs Analog Mode

`Atom.isLogic` determines timing:

- `true` (Digital): output changes are scheduled to the next tick (unit delay, like real logic).
- `false` (Analog): outputs update immediately.

Assemblies with internal atoms are forced to `isLogic = true`.

### Spatial Sorting

`GroupAtomsCommand` sorts new ports by the Y coordinate of the internal atom (fallback: X, then contactName). Ports on the Assembly boundary appear in the same vertical order as the atoms on the schematic.

### Mode Toggle with State Sync

Editor ↔ Device Panel switching:

- `syncDevicePanelToCache()` / `restoreDevicePanelFromCache()`
- Hide/show layers
- Restore/clear widgets
- Close the separate window (if open)

The cache preserves the positions and sizes of all DeviceCards, so returning to a mode restores the user's exact layout.

### Inline Parameter Editor

For contacts without wires, `NodeView` shows an inline editor right on the port (`_inlineEditors`). When the contact receives a wire, the editor hides. This provides UI for parameter setup without opening a separate window.

### Deferred Sync Wave

`_processPendingSignals` schedules the final sync via `TickGenerator.scheduleNextTick`, which:

- (a) re-propagates `external → internal` for INPUT ports,
- (b) synchronizes OUTPUT ports.

A two-pass scheme: the first pass creates atoms and connections, the second aligns values.

### Hybrid Stack + Camera State Map

`EditorContext._stack` (the array of open editors) + `_cameraStates:Map<blueprintId, {x,y,zoom}>`. When the user enters an assembly they have visited before, the camera restores to the exact position of the last visit.

### Force Render During Native Drag

During a native Windows drag (`SendMessage` blocks the thread), OpenFL skips rendering because no `ENTER_FRAME` events fire. `_onDragTick()` manually triggers:

1. `app.onUpdate.dispatch(15)` — Lime logic cycle
2. `stage.__renderDirty = true` — mark the stage dirty
3. `win.onRender.dispatch(ctx)` — force a GL back-buffer draw
4. `SwapBuffers(wglGetCurrentDC())` — present the frame

Achieves ~60 FPS during drag.

### Absolute Position Drag Model

Haxe-side window drag uses an absolute position model to prevent flicker:

- Store `_mouseStartX/Y` at drag start
- On each `MOUSE_MOVE`: compute `dx = currentMouseX - startMouseX`
- Call `onWindowDrag(dx, dy)` → Main.hx sets `win.x = startX + dx`

Avoids accumulated rounding errors that cause visual jitter.

### DeviceView Lifecycle

The DeviceView lifecycle in the system:

**Creation:**

1. `DeviceWidgetFactory.createView(atom)` — create the widget by atom type
2. `DeviceViewRegistry.register(atom.id, view)` — register in the singleton
3. `view.initialize()` — initialization, contact subscriptions

**Migration:**

- The widget can move between containers: `NodeView` ↔ `DevicePanel` ↔ `DeviceWindow`
- Migration via `view.setParent(newContainer)` — only the parent changes, the instance persists
- `DeviceViewRegistry` guarantees exactly one widget per `atom.id`

**Removal:**

1. `Atom.dispose()` → emit `ATOM_DELETED`
2. `DeviceViewRegistry.unregister(atom.id)` — remove from the registry
3. `view.dispose()` — unsubscribe from Impulsys, release resources
4. `view.removeFromParent()` — remove from the display list

**Reattach:**

- On atom reconstruction (dispose + createAtom with the same ID) the widget is not recreated
- `view.reattachToAtom(newAtom)` — reconnects to the new instance
- Position, selection state and all subscriptions are preserved

### Dual Panel Layout

The two-panel context menu architecture:

**Structure:**

```
┌─────────────────────────────────────────────┐
│  CategorySidebar  │    ContentPanel         │
│  ┌─────────────┐  │  ┌───────────────────┐  │
│  │ Recent      │  │  │ SearchBar         │  │
│  │ Editor      │  │  ├───────────────────┤  │
│  │ Atoms       │  │  │ RecentSection     │  │
│  │ Assemblies  │  │  │ (if any)          │  │
│  └─────────────┘  │  ├───────────────────┤  │
│                   │  │ MenuItemGrid      │  │
│                   │  │ or List           │  │
│                   │  └───────────────────┘  │
└─────────────────────────────────────────────┘
```

**Configuration:**

- `SidebarPosition.LEFT` — sidebar on the left (default)
- `SidebarPosition.RIGHT` — sidebar on the right
- `DisplayMode.LIST` — vertical list for commands
- `DisplayMode.GRID` — grid for atoms/assemblies

**Interaction:**

- Category click → ContentPanel updates
- Search → filters the current category
- Item click → action executes

---

## 5. Prospective Patterns (Roadmap v3.0+)

| Pattern                                            | Problem                                                                                                           | Solution                                                                                                                                           | Status         |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Memento Pattern for Assembly State                 | `GroupAtomsSnapshot` stores raw data but cannot serialize/restore itself independently of the command           | Extract snapshot logic into a dedicated `AssemblyMemento` class with `save()` / `restore()`; the command becomes a thin wrapper              | 🎯 v3.0 target |
| Topology Versioning                                | No way to tell whether an assembly's topology changed between save/load                                           | Add `topologyHash:Int` to Blueprint (CRC32 of pins + internalAtoms + internalConnections); on load compare — if equal, skip sanitization        | 🎯 v3.1 target |
| Graceful Degradation for Missing Widgets           | If `DeviceViewRegistry` cannot create a widget, `NodeView` shows an empty spot                                | Fallback: minimal placeholder sprite with the atom's name — the user sees the atom exists even if the widget is broken                            | 💡 Proposed    |
| Automated Integration Tests for Topology Mutations | Manual testing of exit-from-assembly + signal propagation is slow and error-prone                                 | A headless test set that automatically: builds an assembly, adds wires, exits, feeds a signal, verifies no crash and correct rendering             | 💡 Proposed    |
| ECS Full Integration                               | ECS is currently used only for rendering (hybrid); business logic still uses the traditional Atom→Assembly graph | Migrate the compute graph to ECS systems; atoms become entities, contacts become components. Enables parallel processing and better cache locality | 🔮 Future      |
| Hot-Reload Blueprint                               | Currently requires full dispose + recreate to apply blueprint changes                                             | Implement incremental blueprint diffing — mutate only changed atoms/connections; preserve runtime state for unchanged atoms                       | 🔮 Future      |
| Context Menu Keyboard Navigation                   | The context menu is mouse-only; keyboard users cannot navigate categories or select items                         | Arrow-key navigation between categories, Enter to select, Escape to close; focus management for accessibility                                      | 💡 Proposed    |
| Undo/Redo Visual Feedback                          | Users cannot see what will be undone/redone before executing                                                      | Show a preview of the undo/redo action (highlight affected atoms, show the command description in the status bar)                                  | 💡 Proposed    |
| Assembly Template System                           | Creating similar assemblies requires manual recreation each time                                                  | Implement assembly templates with parameterized inputs; users instantiate templates with custom values                                             | 🔮 Future      |

---

## 6. Document Versioning

| Version            | Date                 | Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------ | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0                | 2026-07-18           | Initial architecture patterns document based on ALTAURI v2.x codebase                                                                                                                                                                                                                                                                                                                                                                                                |
| 1.1                | 2026-07-18           | Added supplementary patterns: BP-SSOT, Zero-GC Audio Pipeline, Batched Driver Update, Edge Detection, Circuit Breaker                                                                                                                                                                                                                                                                                                                                                |
| 1.2                | 2026-07-20           | Full actualization for the v2.9 codebase. Added: NamingService Global Uniqueness, Broadcast Storm Prevention, Paste-Aware Naming, Wire Hit Sprite Selection, Native Windows Drag with Tick Injection, DevicePanel Maximize/Restore Callback Architecture, Interactive Target Guard, Mouse Event Isolation, Blueprint Sanitization, Force Render During Native Drag, Absolute Position Drag Model. Roadmap updated with ECS Full Integration and Hot-Reload Blueprint |
| 1.3                | 2026-07-21           | Context Menu v2.0 patterns: Provider Pattern, Category-Based Navigation, Icon Resolution, Recent Actions Tracking, Smart Menu Positioning, Search & Filter, Display Mode Switching. Memory Management Patterns section added. DeviceView Lifecycle documented. Dual Panel Layout architecture added                                                                                                                                                                  |
| 1.4                | 2026-07-22           | Added Feature Detection + Sync User Gesture + Blob Fallback pattern for HTML5 cross-browser compatibility (Android 9 / Chrome 126)                                                                                                                                                                                                                                                                                                                                   |
| **2.0 (EN)** | **2026-09-06** | **English edition: translated from the internal v1.4, verified against the current source tree (all referenced mechanisms spot-checked), restructured for the public repository**                                                                                                                                                                                                                                                                              |

---

## A Note for Developers

This document is alive. When a new architectural pattern is introduced or an existing one is significantly modified — please update the relevant section and add a record to the versioning table. Architectural discipline is the key to ALTAURI's scalability.

### Key principles for new developers

1. **BP-SSOT always first** — any structural mutation starts with the Blueprint, then syncs into the runtime.
2. **NamingService for uniqueness** — never create atoms/assemblies with duplicate names. Always use `resolveUniqueInstanceName()` / `resolveUniqueBlueprintName()`.
3. **Impulsys for communication** — avoid direct references between components; use the event bus.
4. **Command for mutations** — all schematic changes must be undoable. Implement via the Command pattern.
5. **Zero-GC for audio** — no allocations in the audio thread. Use pre-allocated buffers.
6. **Dispose correctly** — follow the order: DeviceView → Contact → Atom → Registry. Check for leaks via `getListenerCount()`.
7. **Reattach, don't recreate** — when reconstructing an atom use `reattachToAtom()`, not widget recreation.
8. **Memory leaks are enemy #1** — always check `DeviceViewRegistry.getCount()` and `Impulsys.getListenerCount()` after create/dispose cycles.

### Checklist for new patterns

Before introducing a new pattern, verify:

- [ ] The pattern does not duplicate an existing one
- [ ] The pattern solves a concrete problem (not "for the future")
- [ ] The pattern is compatible with BP-SSOT and NamingService
- [ ] The pattern does not violate Zero-GC for audio streams
- [ ] The pattern has a clear lifecycle (creation → use → disposal)
- [ ] The pattern has been tested for memory leaks
- [ ] Documentation updated (this file + code comments)
