#!/usr/bin/env python3
"""
Collect Classes - Scan directory recursively and merge all .hx files into one.
Replaces the old Adobe Air tool.

This script walks through the specified directory and all subdirectories,
finds all files with .hx extension, and concatenates their contents into
a single output text file with clear separators between files.
"""

import os
import sys
from pathlib import Path
from typing import Callable, Dict, Any, List
from datetime import datetime
import tkinter as tk
from tkinter import filedialog

# Script metadata (required by main.py)
NAME = "Collect Classes"
DESCRIPTION = "Scan directory recursively and merge all .hx files into one text file"

# Folders to exclude from scanning
EXCLUDED_FOLDERS = {
    'node_modules',
    '.git',
    'bin',
    'obj',
    '.haxelib',
    '.idea',
    '.vscode',
    '.svn',
    'dist',
    'build',
    '__pycache__',
    '.hg',
    'CVS'
}


def prompt_input(root: tk.Tk) -> str:
    """
    Open folder selection dialog.
    
    @param root Tkinter root window
    @return Selected folder path or None if cancelled
    """
    folder_path = filedialog.askdirectory(
        parent=root,
        title="Select Source Folder (containing .hx files)",
        initialdir=os.path.expanduser("~")
    )
    return folder_path if folder_path else None


def execute(input_path: str, log: Callable[[str], None]) -> Dict[str, Any]:
    """
    Main execution function.

    Scans the specified directory recursively for .hx files and merges
    them into a single output file.

    @param input_path Path to directory to scan (or file - will use parent folder)
    @param log Logging function for output messages

    @return Dictionary with execution results and statistics

    @raises FileNotFoundError If the path does not exist
    @raises ValueError If the path is not a directory
    """
    input_path_obj = Path(input_path)

    # If a file was selected, use its parent directory
    if input_path_obj.is_file():
        log(f"File selected: {input_path_obj.name}")
        log(f"Using parent directory: {input_path_obj.parent}")
        input_dir = input_path_obj.parent
    elif input_path_obj.is_dir():
        input_dir = input_path_obj
    else:
        raise FileNotFoundError(f"Path not found: {input_path}")

    # Validate input path
    if not input_dir.exists():
        raise FileNotFoundError(f"Directory not found: {input_dir}")

    if not input_dir.is_dir():
        raise ValueError(
            f"Expected a directory, but got a file: {input_dir}\n"
            f"Please select a folder containing .hx files."
        )

    log(f"Scanning directory: {input_dir}")
    log(f"Excluded folders: {', '.join(sorted(EXCLUDED_FOLDERS))}")

    # Find all .hx files
    hx_files: List[Path] = []
    skipped_folders: List[str] = []

    for root_dir, dirs, files in os.walk(input_dir):
        # Modify dirs in-place to exclude unwanted folders
        dirs[:] = [d for d in dirs if d not in EXCLUDED_FOLDERS]

        # Track skipped folders for logging
        root_path = Path(root_dir)
        for excluded in EXCLUDED_FOLDERS:
            if excluded in dirs:
                skipped_path = root_path / excluded
                skipped_folders.append(str(skipped_path.relative_to(input_dir)))

        # Collect .hx files
        for file in files:
            if file.endswith('.hx'):
                hx_files.append(Path(root_dir) / file)

    # Log skipped folders
    if skipped_folders:
        log(f"Skipped {len(skipped_folders)} excluded folder(s)")

    if not hx_files:
        raise ValueError(f"No .hx files found in {input_dir}")

    # Sort files for deterministic output (alphabetical by relative path)
    hx_files.sort(key=lambda p: p.relative_to(input_dir))

    log(f"Found {len(hx_files)} .hx file(s)")

    # Collect content
    collected_content: List[str] = []
    total_lines = 0
    total_chars = 0
    separator = "=" * 80

    for hx_file in hx_files:
        try:
            content = hx_file.read_text(encoding='utf-8')
            lines = content.count('\n') + 1
            chars = len(content)
            total_lines += lines
            total_chars += chars

            # Add file header
            relative_path = hx_file.relative_to(input_dir)
            collected_content.append(f"\n{separator}")
            collected_content.append(f"// FILE: {relative_path}")
            collected_content.append(f"// Lines: {lines} | Chars: {chars}")
            collected_content.append(f"{separator}\n")
            collected_content.append(content)

            log(f"  ✓ {relative_path} ({lines} lines)")

        except Exception as e:
            log(f"  ✗ {hx_file.name}: Could not read - {e}")

    # Generate output filename
    output_path = input_dir.parent / f"{input_dir.name}_all_classes.txt"

    # Write output file
    log(f"\nWriting output: {output_path}")
    output_text = '\n'.join(collected_content)
    output_path.write_text(output_text, encoding='utf-8')

    # Get output file size
    output_size = output_path.stat().st_size

    # Statistics
    stats = {
        'input_directory': str(input_dir),
        'output_file': str(output_path),
        'files_processed': len(hx_files),
        'total_lines': total_lines,
        'total_chars': total_chars,
        'output_size_bytes': output_size,
        'output_size_mb': round(output_size / (1024 * 1024), 2),
        'skipped_folders': len(skipped_folders),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }

    # Log summary
    log(f"\n{'=' * 60}")
    log(f"COLLECTION COMPLETE")
    log(f"{'=' * 60}")
    log(f"  Files processed:  {stats['files_processed']}")
    log(f"  Total lines:      {stats['total_lines']:,}")
    log(f"  Total chars:      {stats['total_chars']:,}")
    log(f"  Output size:      {stats['output_size_mb']} MB")
    log(f"  Skipped folders:  {stats['skipped_folders']}")
    log(f"  Output file:      {output_path.name}")
    log(f"{'=' * 60}")

    return stats


if __name__ == '__main__':
    # Standalone execution support
    def print_log(msg: str):
        print(msg)

    if len(sys.argv) < 2:
        print("Usage: python collect_classes.py <directory_or_file>")
        print("\nExamples:")
        print("  python collect_classes.py C:\\Projects\\ALTAURI\\src")
        print("  python collect_classes.py C:\\Projects\\ALTAURI\\src\\Main.hx")
        sys.exit(1)

    try:
        result = execute(sys.argv[1], print_log)
        print(f"\nDone! Output: {result['output_file']}")
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)