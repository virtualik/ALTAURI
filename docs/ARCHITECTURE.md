# ALTAURI — Architecture Map

**Edition v3.0 (code-verified) — 2026-09-06.**
This document maps every class of the ALTAURI application onto a domain → layer → subgroup → pack hierarchy. It was fully re-verified against the source tree (`src/`, 153 `.hx` files) on 2026-09-06; every class listed below exists in the repository today, and five phantom entries from the previous edition were removed.

> **Companion documents:** [ARCHITECTURE_PATTERNS.md](ARCHITECTURE_PATTERNS.md) — the design patterns and principles behind this structure.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ALTAURI APPLICATION — 153 classes                    │
│                                                                             │
│  1. CORE DOMAIN (24)                                                        │
│     ├── Infrastructure Layer (6)                                            │
│     ├── Logic & Events Layer (7)                                            │
│     ├── Data Layer (4)                                                      │
│     └── Lab I/O & Standalone Layer (7)  [NEW]                               │
│                                                                             │
│  2. VIEW DOMAIN (23)                                                        │
│     ├── View Infrastructure (4)                                             │
│     ├── Standard Widgets (7)                                                │
│     ├── Complex & Driver Widgets (6)                                        │
│     └── Streaming & File Widgets (6)  [expanded]                            │
│                                                                             │
│  3. LIBRARY DOMAIN (21)                                                     │
│     ├── Electro / Logic Atoms (10)                                          │
│     ├── Hardware & Stream Drivers (7)                                       │
│     ├── File & Storage Drivers (3)  [NEW]                                   │
│     └── Registry (1)                                                        │
│                                                                             │
│  4. EDITOR DOMAIN (18)                                                      │
│     ├── Rendering Core (3)                                                  │
│     ├── Interaction & Viewport (4)                                          │
│     ├── Context, Theme & Actions (5)                                        │
│     └── Blueprint & Support Tools (6)  [NEW]                                │
│                                                                             │
│  5. SYSTEM DOMAIN (20)                                                      │
│     ├── Command Pattern (3)                                                 │
│     ├── Editor Commands (11)                                                │
│     ├── Managers (5)                                                        │
│     └── Project I/O (1)                                                     │
│                                                                             │
│  6. UI DOMAIN (37)                                                          │
│     ├── Device Display (5)                                                  │
│     ├── Dialogs (3)                                                         │
│     ├── Components (2)                                                      │
│     ├── Context Menu — Data / Providers / UI (18)                           │
│     ├── HMI Widgets (3)                                                     │
│     └── Platform & Visual Modes (6)                                         │
│                                                                             │
│  7. ECS (7)  ·  UTILITIES (2)  ·  BOOTSTRAP (1)                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. CORE DOMAIN (24 classes)

The deterministic heart of the system: atoms, contacts, the 60 Hz tick engine, the event bus, blueprint serialization — plus the standalone-export and self-run machinery.

### Infrastructure Layer — PACK 1A/1B/1C (6)

| Class                         | Role                                                                   |
| ----------------------------- | ---------------------------------------------------------------------- |
| `core.base.Atom`            | The fundamental logic unit, independent of the rendering engine        |
| `core.base.Assembly`        | Composite atom (container) — assemblies nest other atoms              |
| `core.base.AssemblyFactory` | Central factory creating atoms or assemblies by type                   |
| `core.base.ConductorPort`   | Bidirectional gateway linking an internal contact to the outside world |
| `core.base.Contact`         | Connection point that carries values, protected against oscillation    |
| `core.base.IDisposable`     | Interface for objects requiring explicit resource release              |

### Logic & Events Layer — PACK 2A/2B/2C (7)

| Class                        | Role                                                                |
| ---------------------------- | ------------------------------------------------------------------- |
| `core.logic.TickGenerator` | The single control center of the simulation, fixed 60 Hz timestep   |
| `core.logic.Impulsys`      | Static event bus for global component communication                 |
| `core.logic.LockFreeQueue` | Lock-free SPSC queue for safe cross-thread task passing             |
| `core.logic.EventType`     | Type-safe event enumerations (abstract enum)                        |
| `core.logic.Impulse`       | Event data container (type + payload)                               |
| `core.logic.NamingService` | Global singleton guaranteeing unique atom and blueprint names       |
| `core.logic.PortNaming`    | [NEW] Stable wall-port naming: Inlet / Arrival / Departure / Outlet |

### Data Layer — PACK 1D (4)

| Class                      | Role                                                                                      |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| `core.data.Blueprint`    | Serializable definition of an assembly's structure                                        |
| `core.types.Cargo`       | [NEW] The portion-cargo contract for the contact network (String / Bytes / typed payload) |
| `core.types.ContactType` | Enum defining the data flow direction                                                     |
| `core.types.Priority`    | Priority levels for simulation task queues                                                |

### Lab I/O & Standalone Layer — [NEW] (7)

The machinery behind the one-click standalone export and the self-run mode (a schematic packed into the executable's tail and booted from it):

| Class                         | Role                                                                       |
| ----------------------------- | -------------------------------------------------------------------------- |
| `core.io.DeviceExporter`    | Exports the current device/assembly to a standalone artifact               |
| `core.io.LabCLI`            | Command-line interface: headless inspection and packing of blueprint files |
| `core.io.NativeDialog`      | Native open/save file dialogs (native targets)                             |
| `core.io.PathCanon`         | Path canonicalization and safety checks (`samePath`, `isInsideDir`)    |
| `core.io.PayloadTail`       | Reads and validates the blueprint payload appended to an executable        |
| `core.io.PayloadTailWriter` | Packs a blueprint into the executable's tail                               |
| `core.io.TailStartup`       | Installs and boots the application from an appended payload                |

---

## 2. VIEW DOMAIN (23 classes)

Everything the user sees: the base widget class, its registry, and the full widget set — from buttons and LEDs to oscilloscopes and COM-port panels.

### View Infrastructure — PACK 3A (4)

| Class                               | Role                                                        |
| ----------------------------------- | ----------------------------------------------------------- |
| `core.view.DeviceView`            | Base class of all widgets — the "face" of an atom          |
| `core.view.DeviceViewRegistry`    | Singleton registry enforcing "one atom = one widget"        |
| `core.view.DeviceWidgetFactory`   | Factory creating the right widget (DeviceView) by atom type |
| `core.view.InlineParameterEditor` | Inline parameter editor rendered on the node body           |

### Standard Widgets — PACK 3B-1 (7)

| Class                         | Role                                                            |
| ----------------------------- | --------------------------------------------------------------- |
| `core.view.ButtonWidget`    | Button widget sending an impulse on press (user input → model) |
| `core.view.LEDWidget`       | Round LED indicator for boolean or analog signals               |
| `core.view.ToggleWidget`    | ON/OFF toggle with race-condition protection                    |
| `core.view.TextInputWidget` | Text/number input field with parse-on-Enter commit              |
| `core.view.TextAreaWidget`  | Multiline field with custom scrollbars, word wrap, auto-scroll  |
| `core.view.TextWidget`      | Display (and optional editing) of contact values                |
| `core.view.PanelWidget`     | Container widget for an Assembly, showing its ports             |

### Complex & Driver Widgets — PACK 3B-2 (6)

| Class                               | Role                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------- |
| `core.view.OscilloscopeWidget`    | Real-time signal oscilloscope (linear/circular)                         |
| `core.view.FFTWidget`             | Spectrum analyzer with a logarithmic frequency scale                    |
| `core.view.SignalGeneratorWidget` | Interactive signal generator panel (frequency, mode, quantization, LED) |
| `core.view.MiniAudioWidget`       | Audio capture with VU meter, clip indicator, Gain/Quantum controls      |
| `core.view.ComPortWidget`         | COM-port control panel (open, send/receive, DTR, RX/TX/ERR indicators)  |
| `core.view.SystemVUMeterWidget`   | Stereo system-audio VU meter (WASAPI) with dBFS and clip indicators     |

### Streaming & File Widgets — PACK 3C + [NEW] (6)

| Class                                    | Role                                                                   |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| `core.view.WebSocketWidget`            | WebSocket client panel (URL, connect/disconnect, send/receive)         |
| `core.view.URLAudioStreamPlayerWidget` | URL audio player with playback and volume controls                     |
| `core.view.FileReaderWidget`           | [NEW] File picker and file reading controls for the FileReader atom    |
| `core.view.FileWriterWidget`           | [NEW] File writer controls incl. the HTML5 Blob-fallback download path |
| `core.view.DataStorageWidget`          | [NEW] Data storage buffer controls (read/clear/status)                 |
| `core.view.PictureWidget`              | [NEW] Picture display widget performing the BitmapData decode          |

---

## 3. LIBRARY DOMAIN (21 classes)

The atom palette itself — the ready-made blocks users assemble into instruments.

### Electro / Logic Atoms — PACK 4A + 4D/4E (10)

| Class                                | Role                                                       |
| ------------------------------------ | ---------------------------------------------------------- |
| `library.electro.ButtonAtom`       | Two-state button atom, driven by the TickGenerator         |
| `library.electro.LedAtom`          | Passive indicator atom with no processing logic            |
| `library.electro.ToggleAtom`       | Switch with instant-reset (race condition) protection      |
| `library.electro.RelayAtom`        | Relay (gate) — passes the signal only while enabled       |
| `library.electro.TextInputAtom`    | Passive atom for string/number input                       |
| `library.electro.TextAreaAtom`     | Passive atom for multiline input with scroll configuration |
| `library.electro.PassThroughAtom`  | Instant pass-through of a value from input to output       |
| `library.electro.OscilloscopeAtom` | Active driver atom sampling signals on a time basis        |
| `library.electro.FFTAtom`          | Spectral analysis driver (Cooley-Tukey radix-2 FFT)        |
| `library.electro.BufferingAtom`    | Sample buffering with the Zero-GC pattern                  |

### Hardware & Stream Drivers — PACK 4B-2 + 4F (7)

| Class                                                            | Role                                                                                                                     |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `library.drivers.MiniAudioAtom`                                                              | Audio capture driver via MiniAudio (microphone/loopback)                                                                 |
| `library.drivers.ComPortAtom`                                                                | COM-port driver with a background read thread and DTR control                                                            |
| `library.drivers.SignalGenerator`                                                            | Signal generator with amplitude quantization (SIN/SQR/SAW/TRI/NOI)                                                       |
| `library.drivers.SystemVUMeterAtom`                                                          | Stereo VU meter via Windows WASAPI                                                                                       |
| `library.drivers.URLAudioStreamPlayerAtom`                                                   | URL audio player via WMF with auto-reconnect                                                                             |
| `library.drivers.WebSocketAtom`                                                              | WebSocket client driver (WinHTTP on C++, native on HTML5)                                                                |
| `library.drivers.PictureAtom`                                                                | [NEW] Visual consumer of the binary pipe: validates image headers, holds picture bytes and transform pins for the widget |

### File & Storage Drivers — [NEW] (3)

| Class                                                            | Role                                                                                                                |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `library.drivers.FileReaderAtom`                                                             | [NEW] File reader: native open dialog or HTML5 picker; decodes to text or bytes and pushes to the graph             |
| `library.drivers.FileWriterAtom`                                                             | [NEW] File writer with WRITE/APPEND modes; native file streams or the HTML5 Blob-fallback download path             |
| `library.drivers.DataStorageAtom`                                                            | [NEW] Data storage: accepts data portions on [data], holds a canonical buffer, releases non-destructively on [read] |

### Registry — PACK 4C (1)

| Class                    | Role                                                          |
| ------------------------ | ------------------------------------------------------------- |
| `library.AtomRegistry` | Registry of all atom blueprints; initializes the native atoms |

---

## 4. EDITOR DOMAIN (18 classes)

The schematic editor: canvas, interaction, viewport, and the blueprint tooling that was progressively extracted from the former god-class.

### Rendering Core — PACK 5A (3)

| Class                   | Role                                                       |
| ----------------------- | ---------------------------------------------------------- |
| `editor.NodeEditor`   | Coordinator of visual editing: nodes, wires, camera        |
| `editor.NodeView`     | Visual representation of an atom on the canvas, with ports |
| `editor.WireRenderer` | Wire rendering (Bezier / Straight / Corners)               |

### Interaction & Viewport — PACK 5B (4)

| Class                            | Role                                                             |
| -------------------------------- | ---------------------------------------------------------------- |
| `editor.SelectionManager`      | Selection logic + lasso                                          |
| `editor.GroupSelectionManager` | Clean ID list for the selection (nodes + wires)                  |
| `editor.ViewportManager`       | Pan, zoom, visibility culling with lazy activation               |
| `editor.EditorCameraStore`     | [NEW] Camera state persistence per assembly (restore on revisit) |

### Context, Theme & Actions — PACK 5C (5)

| Class                          | Role                                                                      |
| ------------------------------ | ------------------------------------------------------------------------- |
| `editor.EditorContext`       | Stack of open editors, background locking, cross-assembly navigation      |
| `editor.EditorState`         | Global editor state (zoom, pan) for component coordination                |
| `editor.EditorTheme`         | Centralized store of all editor visual constants                          |
| `editor.EditorActionHandler` | Schematic modification logic via Undo/Redo commands                       |
| `editor.ContextMenuManager`  | Context-menu manager, subscribing to impulses and delegating to providers |

### Blueprint & Support Tools — [NEW] (6)

Classes extracted from the former `EditorContext` god-class during the de-god-ification refactoring (Episodes A–D):

| Class                            | Role                                                               |
| -------------------------------- | ------------------------------------------------------------------ |
| `editor.PortNameResolver`      | [NEW] Resolves port display names for the editor canvas            |
| `editor.BlueprintSynchronizer` | [NEW] Synchronizes runtime mutations back into the blueprint       |
| `editor.AssemblyReconstructor` | [NEW] Rebuilds assemblies from blueprints                          |
| `editor.EditorEntry`           | [NEW] Per-stack entry type for the EditorContext editor stack      |
| `editor.EditorTooltip`         | [NEW] Hover tooltips for ports and wires (stable naming companion) |
| `editor.EditorVisuals`         | [NEW] Editor visual constants extracted from the context           |

---

## 5. SYSTEM DOMAIN (20 classes)

Commands, managers, and project file I/O.

### Command Pattern — PACK 6A (3)

| Class                                 | Role                                                            |
| ------------------------------------- | --------------------------------------------------------------- |
| `system.commands.base.Command`      | Abstract base class of the command infrastructure               |
| `system.commands.base.ICommand`     | Base interface for all commands (execute, undo, getDescription) |
| `system.commands.base.MacroCommand` | Container command executing/undoing a group of commands as one  |

### Editor Commands — PACK 6B (11)

| Class                                               | Role                                               |
| --------------------------------------------------- | -------------------------------------------------- |
| `system.commands.editor.CreateAtomCommand`        | Creates an atom on the canvas                      |
| `system.commands.editor.DeleteAtomCommand`        | Deletes an atom, keeping a snapshot for undo       |
| `system.commands.editor.ConnectCommand`           | Connects two contacts with a wire                  |
| `system.commands.editor.DeleteWiresCommand`       | Deletes the selected wires                         |
| `system.commands.editor.MoveNodeCommand`          | Moves a node (updates blueprint coordinates)       |
| `system.commands.editor.MovePortCommand`          | [NEW] Moves a port (updates blueprint coordinates) |
| `system.commands.editor.AddPortCommand`           | Adds a new port to an Assembly                     |
| `system.commands.editor.RemovePortCommand`        | Removes a port and its connections                 |
| `system.commands.editor.GroupAtomsCommand`        | Groups the selected atoms into a new Assembly      |
| `system.commands.editor.CreateNewAssemblyCommand` | Creates an empty assembly context                  |
| `system.commands.editor.GroupAtomsSnapshot`       | Full data container for group undo/redo            |

### Managers — PACK 7A (5)

| Class                                | Role                                                          |
| ------------------------------------ | ------------------------------------------------------------- |
| `system.managers.DriverManager`    | Manager of active drivers (update loops)                      |
| `system.managers.ProjectManager`   | File system, paths, save/load; blueprint sanitization at load |
| `system.managers.UndoManager`      | Command history for undo/redo                                 |
| `system.managers.ResourceRegistry` | [NEW] Registry of runtime resources with cleanup checks       |
| `system.managers.Driver`           | Base interface for all hardware/protocol drivers              |

### Project I/O — [NEW placement] (1)

| Class                   | Role                                               |
| ----------------------- | -------------------------------------------------- |
| `system.io.ProjectIO` | Safe file operations with correct listener cleanup |

---

## 6. UI DOMAIN (37 classes)

The user interface: device display, dialogs, components, the two-panel context menu, HMI widgets, and platform integration.

### Device Display — PACK 8A (5)

| Class               | Role                                                           |
| ------------------- | -------------------------------------------------------------- |
| `ui.DevicePanel`  | Built-in device panel inside the main window, with native drag |
| `ui.DeviceWindow` | Separate OS window for device display                          |
| `ui.DeviceCard`   | Card holding a DeviceView inside the panel/window              |
| `ui.TitleBar`     | [NEW] Custom window title bar (editor toolbar host)            |
| `ui.ResizeGrip`   | [NEW] Window resize grip                                       |

### Dialogs — PACK 8B (3)

| Class                   | Role                                                           |
| ----------------------- | -------------------------------------------------------------- |
| `ui.PropertiesWindow` | Atom properties window (logic, parameters, oscilloscope shape) |
| `ui.SettingsPanel`    | Application settings panel (ECS, wire types, visual mode)      |
| `ui.TextInputPopup`   | Popup for text input or confirmation                           |

### Components — PACK 8C (2)

| Class                  | Role                                         |
| ---------------------- | -------------------------------------------- |
| `ui.ButtonComponent` | Base button component (square, 40×40)       |
| `ui.TextComponent`   | Simple text display bound to a contact value |

### Context Menu — PACK 8F/8G/8H (18)

| Class                                                | Role                                               |
| ---------------------------------------------------- | -------------------------------------------------- |
| `ui.contextmenu.data.MenuCategory`                 | Category model for the sidebar                     |
| `ui.contextmenu.data.MenuEntry`                    | Menu item model (command, atom, assembly)          |
| `ui.contextmenu.data.MenuEntryProvider`            | Interface for menu content providers               |
| `ui.contextmenu.data.RecentMenuTracker`            | Singleton tracker of recent user actions           |
| `ui.contextmenu.providers.AtomLibraryProvider`     | Provides the atom list from the registry           |
| `ui.contextmenu.providers.AssemblyLibraryProvider` | Provides the user assembly list                    |
| `ui.contextmenu.providers.EditorCommandsProvider`  | Provides editor commands (Delete, Group, Add Port) |
| `ui.contextmenu.ContextMenu`                       | Main context-menu container (sidebar + content)    |
| `ui.contextmenu.CategorySidebar`                   | Left/right panel with category buttons             |
| `ui.contextmenu.CategoryItem`                      | Visual category representation                     |
| `ui.contextmenu.ContentPanel`                      | Right panel with search and content                |
| `ui.contextmenu.MenuItem`                          | Menu item (List and Grid modes)                    |
| `ui.contextmenu.MenuItemGrid`                      | Grid container for menu items                      |
| `ui.contextmenu.SearchBar`                         | Search field with live filtering                   |
| `ui.contextmenu.RecentSection`                     | "Recent actions" section                           |
| `ui.contextmenu.MenuBoundsCalculator`              | Smart menu positioning within the stage            |
| `ui.contextmenu.SidebarPosition`                   | Sidebar position enum (LEFT, RIGHT)                |
| `ui.contextmenu.DisplayMode`                       | Item display mode enum (LIST, GRID)                |

### HMI Widgets — PACK 8D (3)

| Class                        | Role                                                  |
| ---------------------------- | ----------------------------------------------------- |
| `ui.widgets.IHMIWidget`    | Interface for all HMI controls                        |
| `ui.widgets.NumberInput`   | Number input with validation, subscribed to a contact |
| `ui.widgets.NumberDisplay` | Number display subscribed to a contact                |

### Platform & Visual Modes — PACK 8E (6)

| Class                   | Role                                                           |
| ----------------------- | -------------------------------------------------------------- |
| `ui.WindowController` | Windows-specific: transparency, blur, opacity, layered windows |
| `ui.WindowGlyphs`     | [NEW] Window control glyphs for the custom title bar           |
| `ui.WireType`         | Wire style enum (BEZIER, STRAIGHT, CORNERS)                    |
| `ui.DisplayConfig`    | [NEW] Global display-mode configuration (editor ↔ device)     |
| `ui.NodeVisualMode`   | [NEW] Node visual mode enum (LIGHT, MEDIUM, HEAVY)             |
| `ui.ResizeGrip`*      | *(listed under Device Display)*                              |

---

## 7. ECS, UTILITIES & BOOTSTRAP (10 classes)

### ECS — Hybrid Rendering Layer (7)

| Class                                | Role                                                         |
| ------------------------------------ | ------------------------------------------------------------ |
| `ecs.ECS`                          | Facade for the whole hybrid render-ECS layer (single import) |
| `ecs.core.World`                   | Minimal World used only for rendering                        |
| `ecs.core.RenderSystem`            | The single place where all visual updates happen             |
| `ecs.core.Query`                   | Efficient type-safe ECS query system                         |
| `ecs.core.ComponentStorage`        | Sparse-set component storage, cache-friendly                 |
| `ecs.components.PositionComponent` | Pure data position component (x, y)                          |
| `ecs.components.VisualComponent`   | Component holding the OpenFL sprite reference                |

### Utilities (2)

| Class          | Role                                                                              |
| -------------- | --------------------------------------------------------------------------------- |
| `utils.UID`  | Unique ID generator for atoms and wires                                           |
| `utils.Trap` | [NEW] Native C++ injection utility for the Windows build (`@:cppFileCode` host) |

### Bootstrap (1)

| Class    | Role                                                                 |
| -------- | -------------------------------------------------------------------- |
| `Main` | Application entry point: initialization, window setup, demo pipeline |

---

## Statistics

| Metric               | Map v2.0 (2026-07) | Map v3.0 (this edition, verified)                                                                                      | Δ        |
| -------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------- | --------- |
| Domains              | 7                  | 7                                                                                                                      | 0         |
| Files in `src/`    | 125 (claimed)      | **153** (counted)                                                                                                | +28       |
| Library atoms        | 19 listed          | **20 listed + composite Assembly = 21**                                                                          | corrected |
| Context-menu classes | 18                 | 18                                                                                                                     | 0         |
| Phantom entries      | —                 | **5 removed**: NETRadioPlayerAtom, ComEnumeratorAtom, NETRadioPlayerWidget, ComEnumeratorWidget, AssemblyMonitor | cleaned   |
| New classes vs v2.0  | —                 | **32 added** (File I/O & storage atoms+widgets, Picture pipeline, Lab I/O layer, editor tooling, platform UI)    | +32       |

## Key Observations

1. **Single responsibility** — every subgroup solves exactly one problem (Time System → timing; Event Bus → communication; Naming System → uniqueness).
2. **Minimal cross-domain dependencies** — `CORE ← VIEW ← LIBRARY ← EDITOR`, with `SYSTEM` and `UI` closing the cycle from above.
3. **Abstraction layers** — Infrastructure (foundation), Logic (algorithms), Interface (user interaction).
4. **Design patterns in use** — Command (undo/redo), Factory, Singleton (registries), Observer (Impulsys), MVC (Atom/DeviceView/NodeEditor), Provider (menu content), Strategy (menu entry modes). See [ARCHITECTURE_PATTERNS.md](ARCHITECTURE_PATTERNS.md) for the full catalogue.

## Document History

| Edition                     | Date                 | Changes                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| v2.0 (internal)             | 2026-07              | Author's internal architecture map (RU)                                                                                                                                                                                                                                                                                                                                              |
| **v3.0 (EN, public)** | **2026-09-06** | Re-verified against the source tree: 153 classes counted; 5 phantom entries removed (NETRadioPlayerAtom, ComEnumeratorAtom, NETRadioPlayerWidget, ComEnumeratorWidget, AssemblyMonitor); 32 new classes added (file/storage/picture pipeline, Lab I/O layer, editor tooling extracted from the context god-class); counts corrected; translated to English for the public repository |
