#!/usr/bin/env python3
"""
ALTAURI Tools - Unified Code Processing Toolkit
Main GUI interface for all code processing operations.

Architecture:
┌─────────────────────────────────────────────────────────────────────────┐
│  ALTAURI Tools - Code Processing Toolkit                                │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Operations                                                       │  │
│  │  ┌──────────────────────┬──────────────────────────────────────┐  │  │
│  │  │  [▶ Clean Comments]  │  Description:                        │  │  │
│  │  │  [  Collect Classes] │  Remove comments and blank lines     │  │  │
│  │  │  [  Unpack Classes]  │  from Haxe code. Safely ignores      │  │  │
│  │  │  [  Analyze Deps...] │  comment markers inside strings.     │  │  │
│  │  │                      │                                      │  │  │
│  │  │                      │            [ Execute ]               │  │  │
│  │  └──────────────────────┴──────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Progress: Ready                                                  │  │
│  │  [████████████████████████████████████████████████████████████]   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Output Log                                                       │  │
│  │  ...                                                              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│  Status: Select an operation to begin                                   │
└─────────────────────────────────────────────────────────────────────────┘
"""

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import os
import sys
from pathlib import Path
from typing import Dict, Any
import importlib.util
import threading


class AltauriTools:
    """Main application class for ALTAURI code processing tools."""

    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("ALTAURI Tools - Code Processing Toolkit")
        self.root.geometry("1000x750")
        self.root.minsize(800, 600)

        # State
        self.scripts: Dict[str, Dict[str, Any]] = {}
        self.selected_script_key: str = ""
        self.script_buttons: Dict[str, ttk.Button] = {}

        # Setup UI
        self._setup_ui()

        # Load scripts
        self._load_scripts()

    def _setup_ui(self):
        """Initialize the user interface."""

        # Main container with padding
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # Configure grid weights
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(2, weight=1)

        # === OPERATIONS (Split Pane) ===
        ops_frame = ttk.LabelFrame(main_frame, text="Operations", padding="10")
        ops_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(0, 10))
        ops_frame.columnconfigure(0, weight=1)
        ops_frame.rowconfigure(0, weight=1)

        # PanedWindow for resizable split between buttons and description
        paned = ttk.PanedWindow(ops_frame, orient=tk.HORIZONTAL)
        paned.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # Left Pane: Script Buttons
        btn_frame = ttk.Frame(paned, padding="5")
        paned.add(btn_frame, weight=1)

        self.ops_container = ttk.Frame(btn_frame)
        self.ops_container.pack(fill=tk.BOTH, expand=True)

        # Right Pane: Description + Execute Button
        desc_frame = ttk.Frame(paned, padding="5")
        paned.add(desc_frame, weight=3)

        ttk.Label(desc_frame, text="Description:", font=('Segoe UI', 10, 'bold')).pack(anchor=tk.W, pady=(0, 5))
        
        self.desc_text = scrolledtext.ScrolledText(
            desc_frame, 
            height=10, 
            wrap=tk.WORD, 
            state=tk.DISABLED,
            font=('Consolas', 10)
        )
        self.desc_text.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        # Execute Button
        self.execute_btn = ttk.Button(
            desc_frame,
            text="[ Execute ]",
            command=self._on_execute_click,
            state=tk.DISABLED
        )
        self.execute_btn.pack(anchor=tk.E)

        # === PROGRESS ===
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="10")
        progress_frame.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=(0, 10))
        progress_frame.columnconfigure(0, weight=1)

        self.progress_var = tk.StringVar(value="Ready")
        ttk.Label(progress_frame, textvariable=self.progress_var).grid(row=0, column=0, sticky=tk.W)

        self.progress_bar = ttk.Progressbar(progress_frame, mode='indeterminate')
        self.progress_bar.grid(row=1, column=0, sticky=(tk.W, tk.E), pady=(5, 0))

        # === OUTPUT LOG ===
        log_frame = ttk.LabelFrame(main_frame, text="Output Log", padding="10")
        log_frame.grid(row=2, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)

        self.log_text = scrolledtext.ScrolledText(log_frame, height=15, wrap=tk.WORD, font=('Consolas', 9))
        self.log_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.log_text.config(state=tk.DISABLED)

        # === STATUS BAR ===
        status_frame = ttk.Frame(main_frame)
        status_frame.grid(row=3, column=0, sticky=(tk.W, tk.E), pady=(10, 0))

        self.status_var = tk.StringVar(value="Select a script, then click [ Execute ]")
        ttk.Label(status_frame, textvariable=self.status_var, foreground="gray").grid(row=0, column=0, sticky=tk.W)

    def _load_scripts(self):
        """Dynamically load all scripts from the scripts/ directory."""
        scripts_dir = Path(__file__).parent / "scripts"

        self._log(f"Looking for scripts in: {scripts_dir}")
        self._log(f"Scripts directory exists: {scripts_dir.exists()}")

        if not scripts_dir.exists():
            self._log(f"Warning: Scripts directory not found: {scripts_dir}")
            return

        # Clear existing buttons
        for widget in self.ops_container.winfo_children():
            widget.destroy()
        self.script_buttons.clear()

        # Load scripts
        script_files = list(sorted(scripts_dir.glob("*.py")))
        self._log(f"Found {len(script_files)} Python files")

        for script_file in script_files:
            if script_file.name.startswith("_"):
                self._log(f"Skipping: {script_file.name}")
                continue

            try:
                self._log(f"Attempting to load: {script_file.name}")
                spec = importlib.util.spec_from_file_location(script_file.stem, script_file)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)

                # Check if module has required attributes
                has_name = hasattr(module, 'NAME')
                has_execute = hasattr(module, 'execute')

                if has_name and has_execute:
                    # Extract description
                    description = getattr(module, 'DESCRIPTION', '')
                    if not description and module.__doc__:
                        # Fallback to docstring if DESCRIPTION is missing
                        doc_lines = module.__doc__.strip().split('\n')
                        description = '\n'.join(doc_lines[:5])

                    self.scripts[script_file.stem] = {
                        'name': module.NAME,
                        'description': description,
                        'execute': module.execute,
                        'prompt_input': getattr(module, 'prompt_input', None),
                        'module': module
                    }

                    # Create button
                    btn = ttk.Button(
                        self.ops_container,
                        text=f"  {module.NAME}",
                        command=lambda key=script_file.stem: self._on_script_select(key)
                    )
                    btn.pack(fill=tk.X, pady=2, padx=5)
                    self.script_buttons[script_file.stem] = btn

                    self._log(f"✓ Loaded script: {module.NAME}")
                else:
                    self._log(f" Script missing required attributes (NAME/execute)")

            except Exception as e:
                import traceback
                self._log(f"✗ Error loading {script_file.name}: {e}")
                self._log(f"Traceback: {traceback.format_exc()}")

    def _on_script_select(self, script_key: str):
        """Handle script button click: update description and enable Execute button."""
        script = self.scripts.get(script_key)
        if not script:
            return

        # Update UI selection state
        self.selected_script_key = script_key
        for key, btn in self.script_buttons.items():
            if key == script_key:
                btn.config(text=f"▶ {script['name']}")
            else:
                btn.config(text=f"  {self.scripts[key]['name']}")

        # Update description panel
        self.desc_text.config(state=tk.NORMAL)
        self.desc_text.delete(1.0, tk.END)
        self.desc_text.insert(tk.END, script['description'])
        self.desc_text.config(state=tk.DISABLED)

        # Enable Execute button
        self.execute_btn.config(state=tk.NORMAL)
        self.status_var.set(f"Selected: {script['name']} — click [ Execute ] to run")

    def _on_execute_click(self):
        """Handle Execute button click: prompt for input and run the script."""
        if not self.selected_script_key:
            messagebox.showwarning("No Script", "Please select a script first.")
            return

        self._run_script(self.selected_script_key)

    def _run_script(self, script_key: str):
        """Execute a script after getting input path from the script itself."""
        script = self.scripts.get(script_key)
        if not script:
            messagebox.showerror("Error", f"Script not found: {script_key}")
            return

        # Ask the script module to prompt for input (file or folder)
        input_path = None
        if script['prompt_input']:
            input_path = script['prompt_input'](self.root)
        else:
            self._log(f"Warning: {script['name']} has no prompt_input() method")

        if input_path is None:
            self._log(f"Operation cancelled by user")
            return

        # Disable buttons during execution
        self._set_ui_state(False)
        self.progress_var.set(f"Running: {script['name']}...")
        self.progress_bar.start()

        # Run in thread to keep UI responsive
        thread = threading.Thread(
            target=self._execute_script_thread,
            args=(script, input_path)
        )
        thread.daemon = True
        thread.start()

    def _execute_script_thread(self, script: Dict[str, Any], input_path: str):
        """Execute script in background thread."""
        try:
            self._log(f"\n{'='*60}")
            self._log(f"Starting: {script['name']}")
            self._log(f"Input: {input_path}")
            self._log(f"{'='*60}\n")

            # Execute the script
            result = script['execute'](input_path, self._log)

            # Capture result value to avoid late-binding issues
            self.root.after(0, lambda res=result: self._on_script_complete(script['name'], res))

        except Exception as e:
            # Capture error message IMMEDIATELY before 'e' goes out of scope
            error_msg = str(e)
            self.root.after(0, lambda err=error_msg: self._on_script_error(script['name'], err))

    def _on_script_complete(self, script_name: str, result: Any):
        """Handle script completion."""
        self.progress_bar.stop()
        self.progress_var.set("Ready")
        self._set_ui_state(True)

        self._log(f"\n✓ {script_name} completed successfully")
        if result:
            self._log(f"Result: {result}")

        self.status_var.set(f"Last operation: {script_name} - Success")
        messagebox.showinfo("Success", f"{script_name} completed successfully!")

    def _on_script_error(self, script_name: str, error: str):
        """Handle script error."""
        self.progress_bar.stop()
        self.progress_var.set("Error")
        self._set_ui_state(True)

        self._log(f"\n✗ {script_name} failed: {error}")
        self.status_var.set(f"Last operation: {script_name} - Error")
        messagebox.showerror("Error", f"{script_name} failed:\n{error}")

    def _set_ui_state(self, enabled: bool):
        """Enable or disable UI elements."""
        state = 'normal' if enabled else 'disabled'

        for widget in self.ops_container.winfo_children():
            widget.config(state=state)
        
        # Also disable/enable the Execute button
        self.execute_btn.config(state=state)

    def _log(self, message: str):
        """Add message to log (thread-safe)."""
        def _append():
            self.log_text.config(state=tk.NORMAL)
            self.log_text.insert(tk.END, message + "\n")
            self.log_text.see(tk.END)
            self.log_text.config(state=tk.DISABLED)

        self.root.after(0, _append)


def main():
    """Main entry point."""
    root = tk.Tk()
    
    # Apply a modern theme if available
    style = ttk.Style()
    available_themes = style.theme_names()
    if 'clam' in available_themes:
        style.theme_use('clam')
    elif 'vista' in available_themes:
        style.theme_use('vista')
        
    app = AltauriTools(root)
    root.mainloop()


if __name__ == '__main__':
    main()
