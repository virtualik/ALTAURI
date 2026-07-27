// FILE: library/drivers/FileWriterAtom.hx
#if html5
package library.drivers;

import core.base.Atom;
import core.base.Contact;
import core.types.ContactType;
import core.types.ContactType.*;
import system.managers.DriverManager;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                     FILE WRITER ATOM v1.1                                 ║
 * ║          (HTML5 File System Access API — Main Thread)                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  Non-blocking file writer for HTML5 target using File System Access API.  ║
 * ║  Operates entirely on the main thread via Promises to avoid               ║
 * ║  DataCloneError associated with transferring FileSystemFileHandle         ║
 * ║  to Web Workers.                                                          ║
 * ║                                                                           ║
 * ║  Architecture:                                                            ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐  ║
 * ║  │                     FileWriterAtom                                  │  ║
 * ║  │                                                                     │  ║
 * ║  │  A) COMPUTE MODULE (Main Thread):                                   │  ║
 * ║  │     ─────────────────────────────────                               │  ║
 * ║  │     1. readInputs()                                                 │  ║
 * ║  │        - Detect open/close/flush/clear pulses                       │  ║
 * ║  │        - Route write/append data to stream                          │  ║
 * ║  │     2. updatePulseTimers(dt)                                        │  ║
 * ║  │        - Auto-reset written/errorTick pulses                        │  ║
 * ║  │                                                                     │  ║
 * ║  │  B) DATABANK (Haxe State):                                          │  ║
 * ║  │     ─────────────────────                                           │  ║
 * ║  │     _isOpenFlag, _fileSize, _writeCount, _mode, _enabled            │  ║
 * ║  │     _suggestedFileName, _lastError, _pendingOpen                    │  ║
 * ║  │     _fileHandle, _stream (Dynamic JS objects)                       │  ║
 * ║  │                                                                     │  ║
 * ║  │  C) BATCHED DRIVER UPDATE PATTERN:                                  │  ║
 * ║  │     ─────────────────────────────                                   │  ║
 * ║  │     Phase 1: setValueSilent() for all outputs                       │  ║
 * ║  │     Phase 2: propagateCurrentValue() once per output                │  ║
 * ║  │     → Reduces TickGenerator load from O(N×M) to O(N+M)              │  ║
 * ║  │                                                                     │  ║
 * ║  │  D) INPUTS:                                                         │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     open      (Bool pulse)  — show file picker dialog              │  ║
 * ║  │     close     (Bool pulse)  — close file & flush buffer            │  ║
 * ║  │     write     (String)      — write data (mode-dependent)          │  ║
 * ║  │     append    (String)      — ALWAYS append to end                 │  ║
 * ║  │     clear     (Bool pulse)  — truncate file to zero                │  ║
 * ║  │     flush     (Bool pulse)  — force buffer flush to disk           │  ║
 * ║  │     enabled   (Bool)        — master enable switch                 │  ║
 * ║  │     mode      (Int)         — 0=Write, 1=Append                    │  ║
 * ║  │     fileName  (String)      — suggested file name                  │  ║
 * ║  │                                                                     │  ║
 * ║  │  E) OUTPUTS:                                                        │  ║
 * ║  │     ────────                                                        │  ║
 * ║  │     isOpen    (Bool)        — file is open                         │  ║
 * ║  │     written   (Bool pulse)  — data flushed to disk                 │  ║
 * ║  │     writeCount(Int)         — total write operations               │  ║
 * ║  │     fileSize  (Int)         — current file size in bytes           │  ║
 * ║  │     error     (String)      — last error message                   │  ║
 * ║  │     errorTick (Bool pulse)  — error occurred                       │  ║
 * ║  └─────────────────────────────────────────────────────────────────────┘  ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     DATA FLOW PIPELINE                                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  1. User clicks "Open" in Widget                                          ║
 * ║       │                                                                   ║
 * ║       ▼                                                                   ║
 * ║  2. Widget calls atom.showFilePicker() (synchronous user gesture)         ║
 * ║       │                                                                   ║
 * ║       ▼                                                                   ║
 * ║  3. Browser shows native Save File dialog                                 ║
 * ║       │                                                                   ║
 * ║       ├──► Cancel: onFilePickerCancelled() → reset state                  ║
 * ║       │                                                                   ║
 * ║       └──► Select: onFileSelected(handle)                                 ║
 * ║                │                                                          ║
 * ║                ▼                                                          ║
 * ║           handle.createWritable() → onStreamOpened(stream)                ║
 * ║                │                                                          ║
 * ║                ▼                                                          ║
 * ║           _isOpenFlag = true, updateOutputs()                             ║
 * ║                                                                           ║
 * ║  4. Upstream Atom (e.g., ComPortAtom) sends data to "append" contact      ║
 * ║       │                                                                   ║
 * ║       ▼                                                                   ║
 * ║  5. readInputs() detects "append" value change                            ║
 * ║       │                                                                   ║
 * ║       ▼                                                                   ║
 * ║  6. appendData(data) → _stream.seek(_fileSize).write(data)               ║
 * ║       │                                                                   ║
 * ║       ▼                                                                   ║
 * ║  7. onWriteComplete(bytes) → updateOutputs() + written pulse              ║
 * ║                                                                           ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                     HAXE PARSER WORKAROUND                                ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║                                                                           ║
 * ║  The `.catch()` method on JS Promises conflicts with the Haxe `catch`     ║
 * ║  keyword, causing "String should be Int" parser errors.                   ║
 * ║                                                                           ║
 * ║  SOLUTION: Wrap the entire Promise chain in an `untyped { ... }` block    ║
 * ║  and use `['catch']` for the error handler. This disables Haxe's type     ║
 * ║  inference and keyword checking for that specific block, allowing the     ║
 * ║  JS Promise API to be called natively.                                    ║
 * ║                                                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
class FileWriterAtom extends Atom implements system.managers.Driver
{
	// =========================================================================
	// CONSTANTS
	// =========================================================================
	/** Duration of pulse outputs (written, errorTick) in seconds */
	private static inline var PULSE_DURATION:Float = 0.05;
	/** Write mode: overwrite file on each write */
	private static inline var MODE_WRITE:Int = 0;
	/** Write mode: always append to end of file */
	private static inline var MODE_APPEND:Int = 1;

	// =========================================================================
	// STATE (DATABANK)
	// =========================================================================
	/** Is file currently open */
	private var _isOpenFlag:Bool = false;
	/** Current file size in bytes */
	private var _fileSize:Int = 0;
	/** Total write operations count */
	private var _writeCount:Int = 0;
	/** Current write mode (0=Write, 1=Append) */
	private var _mode:Int = MODE_APPEND;
	/** Master enable flag */
	private var _enabled:Bool = true;
	/** Suggested file name for picker dialog */
	private var _suggestedFileName:String = "output.txt";
	/** Last error message */
	private var _lastError:String = "";
	/** Pending open request (waiting for user gesture) */
	private var _pendingOpen:Bool = false;

	// =========================================================================
	// FILE SYSTEM ACCESS API FIELDS
	// =========================================================================
	/** FileSystemFileHandle reference */
	private var _fileHandle:Dynamic = null;
	/** FileSystemWritableFileStream reference */
	private var _stream:Dynamic = null;

	// =========================================================================
	// PULSE TIMERS
	// =========================================================================
	private var _writtenTimer:Float = 0.0;
	private var _errorTimer:Float = 0.0;

	// =========================================================================
	// CONSTRUCTOR
	// =========================================================================
	public function new(id:String)
	{
		super(
			// === INPUTS ===
			[
				new Contact(false, INPUT, "open"),
				new Contact(false, INPUT, "close"),
				new Contact("", INPUT, "write"),
				new Contact("", INPUT, "append"),
				new Contact(false, INPUT, "clear"),
				new Contact(false, INPUT, "flush"),
				new Contact(true, INPUT, "enabled"),
				new Contact(MODE_APPEND, INPUT, "mode"),
				new Contact("output.txt", INPUT, "fileName")
			],
			// === OUTPUTS ===
			[
				new Contact(false, OUTPUT, "isOpen"),
				new Contact(false, OUTPUT, "written"),
				new Contact(0, OUTPUT, "writeCount"),
				new Contact(0, OUTPUT, "fileSize"),
				new Contact("", OUTPUT, "error"),
				new Contact(false, OUTPUT, "errorTick")
			],
			null,
			id,
			"FileWriterAtom",
			true // isActive = true → register in DriverManager
		);
		init();
	}

	// =========================================================================
	// DRIVER INTERFACE
	// =========================================================================
	override public function init():Void
	{
		trace('FileWriterAtom: Initialized (Main Thread, no Worker)');
	}

	override public function update(dt:Float):Void
	{
		if (_isDisposed) return;
		readInputs();
		updatePulseTimers(dt);
	}

	override public function dispose():Void
	{
		// Close file if open
		if (_isOpenFlag)
		{
			closeFile();
		}
		_fileHandle = null;
		_stream = null;
		DriverManager.getInstance().unregister(this.id);
		super.dispose();
	}

	// =========================================================================
	// FILE OPERATIONS
	// =========================================================================
	/**
	 * Show file picker dialog and open file for writing.
	 *
	 * CRITICAL: Must be called synchronously from a user gesture (e.g., button click).
	 * The browser will block showSaveFilePicker() if called from non-user code.
	 *
	 * @param suggestedName Suggested file name for the dialog
	 */
	public function showFilePicker(?suggestedName:String = null):Void
	{
		if (_isDisposed) return;
		var name = suggestedName != null ? suggestedName : _suggestedFileName;

		#if html5
		var pickerOptions:Dynamic = {
			suggestedName: name,
			types: [
				{
					description: "Text Files",
					accept: {
						"text/plain": [".txt", ".log", ".csv", ".dat"]
					}
				}
			]
		};

		// HAXE PARSER WORKAROUND:
		// Wrap entire Promise chain in `untyped { ... }` and use `['catch']`
		// to prevent Haxe from interpreting `.catch` as a keyword or array index.
		var self = this;
		untyped {
			window.showSaveFilePicker(pickerOptions)
				.then(function(handle) { self.onFileSelected(handle); })
				['catch'](function(err) { self.onFilePickerCancelled(err); });
		}
		#end
	}

	/**
	 * Called when user selects a file in the picker dialog.
	 * Opens writable stream and updates state.
	 *
	 * @param handle FileSystemFileHandle from showSaveFilePicker
	 */
	private function onFileSelected(handle:Dynamic):Void
	{
		if (_isDisposed) return;
		_fileHandle = handle;

		var self = this;
		untyped handle.createWritable().then(function(stream:Dynamic) {
			self.onStreamOpened(stream);
		})['catch'](function(err:Dynamic) {
			self.onStreamOpenError(err);
		});
	}

	/**
	 * Called when writable stream is successfully opened.
	 */
	private function onStreamOpened(stream:Dynamic):Void
	{
		if (_isDisposed) return;
		_stream = stream;
		_isOpenFlag = true;
		_fileSize = 0;
		_writeCount = 0;
		updateOutputs();
		trace('FileWriterAtom: File opened successfully');
	}

	/**
	 * Called when stream open fails.
	 */
	private function onStreamOpenError(err:Dynamic):Void
	{
		if (_isDisposed) return;
		var errMsg = (err != null && err.message != null) ? Std.string(err.message) : "Unknown error";
		setError('Failed to open stream: $errMsg');
	}

	/**
	 * Called when user cancels the file picker dialog.
	 */
	private function onFilePickerCancelled(err:Dynamic):Void
	{
		if (_isDisposed) return;
		_pendingOpen = false;
		trace('FileWriterAtom: File picker cancelled');
	}

	/**
	 * Write data to file (mode-dependent).
	 *
	 * In MODE_WRITE: truncates file and writes fresh data.
	 * In MODE_APPEND: appends data to end of file.
	 *
	 * @param data String data to write
	 */
	private function writeData(data:String):Void
	{
		if (_isDisposed || _stream == null || !_isOpenFlag) return;
		if (data == null || data == "") return;

		var self = this;
		if (_mode == MODE_WRITE)
		{
			// Truncate and write
			untyped _stream.seek(0).then(function() {
				return untyped _stream.truncate(0);
			}).then(function() {
				return untyped _stream.write(data);
			}).then(function() {
				self.onWriteComplete(data.length);
			})['catch'](function(err:Dynamic) {
				self.onWriteError(err);
			});
		}
		else
		{
			// Append: seek to end and write
			untyped _stream.seek(_fileSize).then(function() {
				return untyped _stream.write(data);
			}).then(function() {
				self.onWriteComplete(data.length);
			})['catch'](function(err:Dynamic) {
				self.onWriteError(err);
			});
		}
	}

	/**
	 * Append data to end of file (mode-independent).
	 *
	 * @param data String data to append
	 */
	private function appendData(data:String):Void
	{
		if (_isDisposed || _stream == null || !_isOpenFlag) return;
		if (data == null || data == "") return;

		var self = this;
		untyped _stream.seek(_fileSize).then(function() {
			return untyped _stream.write(data);
		}).then(function() {
			self.onWriteComplete(data.length);
		})['catch'](function(err:Dynamic) {
			self.onWriteError(err);
		});
	}

	/**
	 * Flush stream buffer to disk.
	 */
	private function flushBuffer():Void
	{
		if (_isDisposed || _stream == null || !_isOpenFlag) return;

		var self = this;
		untyped _stream.flush().then(function() {
			trace('FileWriterAtom: Stream flushed');
		})['catch'](function(err:Dynamic) {
			self.onWriteError(err);
		});
	}

	/**
	 * Clear file contents (truncate to zero).
	 */
	private function clearFile():Void
	{
		if (_isDisposed || _stream == null || !_isOpenFlag) return;

		var self = this;
		untyped _stream.seek(0).then(function() {
			return untyped _stream.truncate(0);
		}).then(function() {
			self._fileSize = 0;
			self._writeCount = 0;
			self.updateOutputs();
			trace('FileWriterAtom: File cleared');
		})['catch'](function(err:Dynamic) {
			self.onWriteError(err);
		});
	}

	/**
	 * Close file and flush remaining buffer.
	 */
	private function closeFile():Void
	{
		if (_isDisposed || _stream == null || !_isOpenFlag) return;

		var self = this;
		untyped _stream.close().then(function() {
			self._stream = null;
			self._isOpenFlag = false;
			self.updateOutputs();
			trace('FileWriterAtom: File closed');
		})['catch'](function(err:Dynamic) {
			self.onWriteError(err);
		});
	}

	// =========================================================================
	// WRITE CALLBACKS
	// =========================================================================
	/**
	 * Called when write operation completes successfully.
	 */
	private function onWriteComplete(bytesWritten:Int):Void
	{
		if (_isDisposed) return;
		_fileSize += bytesWritten;
		_writeCount++;
		updateOutputs();

		// Emit written pulse
		var writtenOut = getOutput("written");
		if (writtenOut != null)
		{
			writtenOut.value = true;
			_writtenTimer = PULSE_DURATION;
		}
	}

	/**
	 * Called when write operation fails.
	 */
	private function onWriteError(err:Dynamic):Void
	{
		if (_isDisposed) return;
		var errMsg = (err != null && err.message != null) ? Std.string(err.message) : "Unknown error";
		setError('Write error: $errMsg');
	}

	// =========================================================================
	// INPUT READING
	// =========================================================================
	/**
	 * Read input contacts and dispatch operations.
	 *
	 * Pulse inputs (open, close, clear, flush) are auto-reset to false.
	 */
	private function readInputs():Void
	{
		if (_isDisposed) return;

		// Master enable
		var enabledC = getInput("enabled");
		if (enabledC != null && enabledC.value != null)
		{
			_enabled = (enabledC.value == true);
		}
		if (!_enabled) return;

		// Mode
		var modeC = getInput("mode");
		if (modeC != null && modeC.value != null)
		{
			var newMode = Std.int(modeC.value);
			if (newMode == MODE_WRITE || newMode == MODE_APPEND)
			{
				_mode = newMode;
			}
		}

		// File name
		var fileNameC = getInput("fileName");
		if (fileNameC != null && fileNameC.value != null)
		{
			_suggestedFileName = Std.string(fileNameC.value);
		}

		// Open (pulse) — requires user gesture
		var openC = getInput("open");
		if (openC != null && openC.value == true)
		{
			openC.value = false;
			_pendingOpen = true;
			showFilePicker(_suggestedFileName);
		}

		// Write (data)
		var writeC = getInput("write");
		if (writeC != null && writeC.value != null)
		{
			var data = Std.string(writeC.value);
			if (data != "")
			{
				writeData(data);
			}
		}

		// Append (data) — ALWAYS appends
		var appendC = getInput("append");
		if (appendC != null && appendC.value != null)
		{
			var data = Std.string(appendC.value);
			if (data != "")
			{
				appendData(data);
				appendC.setValueSilent("");
			}
		}

		// Clear (pulse)
		var clearC = getInput("clear");
		if (clearC != null && clearC.value == true)
		{
			clearC.value = false;
			clearFile();
		}

		// Flush (pulse)
		var flushC = getInput("flush");
		if (flushC != null && flushC.value == true)
		{
			flushC.value = false;
			flushBuffer();
		}

		// Close (pulse)
		var closeC = getInput("close");
		if (closeC != null && closeC.value == true)
		{
			closeC.value = false;
			closeFile();
		}
	}

	// =========================================================================
	// OUTPUT UPDATES (BATCHED DRIVER UPDATE PATTERN)
	// =========================================================================
	/**
	 * Update all output contacts with current state.
	 *
	 * Phase 1: setValueSilent() for all outputs (no propagation)
	 * Phase 2: propagateCurrentValue() once per output
	 * → Reduces TickGenerator load from O(N×M) to O(N+M)
	 */
	private function updateOutputs():Void
	{
		var isOpenOut = getOutput("isOpen");
		var writeCountOut = getOutput("writeCount");
		var fileSizeOut = getOutput("fileSize");

		// Phase 1: Silent writes
		if (isOpenOut != null) isOpenOut.setValueSilent(_isOpenFlag);
		if (writeCountOut != null) writeCountOut.setValueSilent(_writeCount);
		if (fileSizeOut != null) fileSizeOut.setValueSilent(_fileSize);

		// Phase 2: Single propagation per output
		if (isOpenOut != null) isOpenOut.propagateCurrentValue();
		if (writeCountOut != null) writeCountOut.propagateCurrentValue();
		if (fileSizeOut != null) fileSizeOut.propagateCurrentValue();
	}

	/**
	 * Set error state and emit error pulse.
	 *
	 * @param msg Error message
	 */
	private function setError(msg:String):Void
	{
		if (_isDisposed) return;
		_lastError = msg;
		var errorOut = getOutput("error");
		if (errorOut != null)
		{
			errorOut.setValueSilent(msg);
			errorOut.propagateCurrentValue();
		}
		var errorTickOut = getOutput("errorTick");
		if (errorTickOut != null)
		{
			errorTickOut.value = true;
			_errorTimer = PULSE_DURATION;
		}
		trace('FileWriterAtom ERROR: $msg');
	}

	// =========================================================================
	// PULSE TIMERS
	// =========================================================================
	/**
	 * Update pulse timers for written and errorTick outputs.
	 */
	private function updatePulseTimers(dt:Float):Void
	{
		if (_isDisposed) return;

		if (_writtenTimer > 0)
		{
			_writtenTimer -= dt;
			if (_writtenTimer <= 0)
			{
				var c = getOutput("written");
				if (c != null) c.value = false;
			}
		}
		if (_errorTimer > 0)
		{
			_errorTimer -= dt;
			if (_errorTimer <= 0)
			{
				var c = getOutput("errorTick");
				if (c != null) c.value = false;
			}
		}
	}

	// =========================================================================
	// PUBLIC API (for Widget)
	// =========================================================================
	/**
	 * Check if file is currently open.
	 */
	public function isOpen():Bool return _isOpenFlag;

	/**
	 * Get current file size in bytes.
	 */
	public function getFileSize():Int return _fileSize;

	/**
	 * Get total write operations count.
	 */
	public function getWriteCount():Int return _writeCount;

	/**
	 * Get current write mode.
	 */
	public function getMode():Int return _mode;

	/**
	 * Set write mode.
	 */
	public function setMode(mode:Int):Void
	{
		if (mode == MODE_WRITE || mode == MODE_APPEND) _mode = mode;
	}

	/**
	 * Get suggested file name.
	 */
	public function getSuggestedFileName():String return _suggestedFileName;

	/**
	 * Check if there's a pending open request.
	 */
	public function hasPendingOpen():Bool return _pendingOpen;
}
#end