# ALTAURI

**A visual environment for assembling working programs — without writing code.**

*A program is not written. It is assembled.*

> **Status: work in progress.** ALTAURI is under active development. The core works and runs real tasks today, but the project is far from its final version — the application, the atom library, the website and the documentation all have known gaps that are being fixed. This is natural for the stage the project is at, and it is stated here on purpose.

ALTAURI is an open-source execution environment for computational graphs. Instead of writing source code, you place typed blocks — **Atoms** — on a schematic, connect their contacts with wires, and run the graph directly. The same schematic can be turned into a **device panel** — a ready-to-use instrument built from live widgets.

The project exists because for decades the bridge between an idea and a running program has been source code — syntax, brackets, debugging. For an engineer that is routine; for a creator it is a wall. ALTAURI returns programming to its physical essence: blocks, connections, cause and effect.

---

## Try it now

- **Live demo in the browser (no installation):** https://virtualik.github.io/ATOMICA/
  - *Module 1 — Signal Routing:* direct control with visual feedback.
  - *Module 2 — COM Port Management with logging:* a working editor with a serial-port atom, text area and file writer.
  - *Module 3 — Multi-Device Signal Routing:* buttons, a toggle and an LED wired together.
- **Downloads** (Windows / Linux / Android): https://github.com/virtualik/ATOMICA/releases

The browser demos run the same ALTAURI runtime, compiled to HTML5. Module 2 is the most complete demonstration today; Modules 1 and 3 are minimal sketches that will grow.

## Building from source

The codebase is written in [Haxe](https://haxe.org/) on top of [OpenFL/Lime](https://openfl.org/) and compiles to native desktop/mobile targets and to HTML5 — from one codebase, without forking the logic. **Haxe** is a reliable open source technology and is free to use.

```bash
# prerequisites: Haxe 4.x, OpenFL and Lime installed via haxelib
haxelib install openfl
haxelib run lime setup

# HTML5 build (opens in a browser)
haxelib run lime build html5

# native builds
haxelib run lime build windows
haxelib run lime build linux
haxelib run lime build android
```

Build artifacts are placed in `bin/` (see `project.xml` for target configuration: `ALTAURI_Windows`, `ALTAURI_Linux`, `ALTAURI_Android`, `ALTAURI_Web`).

## How it works

**Atoms.** An atom is a self-contained typed component with three parts: a *databank* (its data contacts), a *compute core* (its behavior) and a *face* (its widget in the device panel). Everything — a button, an oscilloscope, a serial port — is an atom.

**Contacts and wires.** Atoms communicate through **contacts**: when a contact's value changes, the change propagates along wires to every connected input. The runtime is a deterministic 60 Hz tick engine with a prioritized scheduler (user input → logic → UI), so propagation never blocks the interface.

**Blueprints.** A schematic is a *blueprint* — a JSON structure that is the single source of truth for what the program is. Projects are saved as `.altauri` files; reusable schematics are loaded from `.atom` files. Composite atoms (**Assemblies**) nest other atoms inside themselves, so a tested fragment becomes a new building block.

**Dual view.** The same blueprint is shown two ways: the **editor** (design surface) and the **device panel** (live widgets). One key press switches between building the instrument and using it.

**Export.** A schematic can be exported as a standalone selfrun application — a finished instrument that carries its own graph.

**Distribution.** The WebSocket atom makes a remote atom indistinguishable from a local one: the runtime does not know that a contact's peer is across the network. The graph topology abstracts distribution.

📐 **Full architecture map:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — every class mapped onto a domain → layer → pack hierarchy (153 classes, 7 domains). Design patterns and principles: [docs/ARCHITECTURE_PATTERNS.md](docs/ARCHITECTURE_PATTERNS.md). Russian editions: [ARCHITECTURE_RU.md](docs/ARCHITECTURE_RU.md) · [ARCHITECTURE_PATTERNS_RU.md](docs/ARCHITECTURE_PATTERNS_RU.md).

### The atom library today

Logic and UI: `Button`, `Led`, `Toggle`, `TextInput`, `TextArea`, `Relay`, `PassThrough`, `Buffering`, `Picture`, `DataStorage`
Measurement and I/O: `Oscilloscope`, `SignalGenerator` (SIN/SQR/SAW/TRI/NOI), `MiniAudio`, `SystemVUMeter`, `FFT`, `URLAudioStreamPlayer`, `ComPort`, `FileReader`, `FileWriter`
Composition: `Assembly` (a composite atom built from other atoms)

## What makes it different

|                     | Typical no-code tools          | ALTAURI                                            |
| ------------------- | ------------------------------ | -------------------------------------------------- |
| What the graph does | Generates or configures code   | **Is executed directly, deterministically**  |
| Runtime model       | Event-driven, hidden           | Fixed 60 Hz tick engine, observable                |
| Editing ↔ runtime  | Two modes, a rebuild step      | **One blueprint, two synchronized views**    |
| Target              | Web pages or a single platform | One codebase → native desktop, mobile and browser |
| Distribution        | Separate infrastructure        | A WebSocket atom — remote contacts look local     |

Existing efforts compared honestly: **Node-RED** executes JavaScript functions rather than the graph itself; **Unreal Blueprints** are locked to the engine; **Max/MSP** is closed-source and desktop-only; **LabVIEW** is proprietary and licensed per seat. ALTAURI takes the visual-graph idea and executes it as a first-class runtime.

## Status — what works today

* Data flows from contact to contact across the graph.
* Atoms are created on the schematic; widgets appear in the device panel.
* Save/load of projects (`.altauri`), Undo/Redo (Command pattern), reusable `.atom` blueprints.
* Export to a standalone selfrun application.
* Build targets configured for **Windows, Linux, Android and HTML5**; the runtime is field-tested on Windows and in the browser.

## Known limitations

This list is kept on purpose — the project does not pretend to be finished:

* Deleting a wire does not yet remove the underlying contact link; wire deletion via the menu is not implemented.
* The menus (editor and device panel) need a rework.
* Window behavior (system requirements, rescaling on window resize) is being refined.
* Whole families of atoms are missing: most UI atoms, and text/RegEx/array processing atoms.
* No headless/CLI runtime yet.
* The website itself is a work in progress.

## Roadmap

**Near term** (current engineering focus):

1. Window behavior per system requirements; proper rescaling of the editor contents on window resize.
2. Fix wire/contact deletion semantics; rework the editor and device-panel menus.
3. Improve atom responsiveness.
4. New UI atoms; new Text / RegEx / Array atoms.
5. Atomic unity across platforms (with some platform-specific atoms).

**Proposed next phase** (prepared for a funding application):

* A protocol-atom pack — HTTP/HTTPS, MQTT, CoAP — each driver-atom validated on at least two physical devices, with tests and CI.
* A public internet demonstration: sensor → ALTAURI graph → WebSocket → browser panel.
* An accessibility pilot: non-programmers assemble working devices; the published metric is *time-to-first-working-instrument*.

**Longer term:**

* Headless runtime for CLI execution.
* The same graph running unchanged from desktop to single-board computers and microcontrollers.

## Repository layout

```
src/          Haxe source code (core, editor, library, system, ui, utils)
site/         Source of the project website (github.io)
assets/       Runtime assets
libs/         Native libraries and drivers
project.xml   OpenFL/Lime build configuration
templates/    Blueprint templates
```

## A note on AI-assisted development

ALTAURI is human-led: the architecture, design decisions and priorities are the author's. Generative language models are used in a deliberately defined role — a **secretary and language referent**: translation, error correction, stylistic cleanup, boilerplate, and stress-testing of ideas. Every line is human-reviewed before commit, and strategic decisions follow a documented three-voice practice: AI analysis → the author's judgment → a frozen written record. Where assistance is substantive, it is disclosed in the commit history.

## License and naming

* All code is released under the **GNU Affero General Public License v3** (see [LICENSE](LICENSE)). The AGPL network clause is chosen deliberately: the runtime is distributed by nature, and the license keeps cloud forks open.
* **Naming.** "ALTAURI" and "ATOMICA" are working titles, not registered trademarks. A name-availability search is still ahead; if either name turns out to be taken, the project will rename without hesitation — the code, the formats and the ideas matter more than the label.

## Contact

* Website and live demo: https://virtualik.github.io/ATOMICA/
* Questions, collaboration, support: altauri.impulsys@gmail.com

---

*BiOCYBER LAB · Lviv · 2026 · ALTAURI is looking for financial support to continue development — the work described above is ongoing.*
