#!/usr/bin/env python3
"""
Unpack Classes - Extract individual .hx files from a merged text file.

Reads a single merged file (e.g., src_all_classes.txt) and reconstructs
the original directory structure based on // FILE: markers produced
by collect_classes.py.

Architecture:
┌─────────────────────────────────────────────────────────────────────────┐
│  Input:  merged .txt file (created by collect_classes.py)               │
│         Contains // FILE: path/to/Class.hx markers                      │
│                                                                         │
│  Process:                                                               │
│  1. Read entire file                                                    │
│  2. Split by // FILE: markers                                           │
│  3. For each block:                                                     │
│     a. Extract path from marker                                         │
│     b. Strip metadata header lines                                      │
│     c. Write to output_dir/path/Class.hx                                │
│  4. Report statistics                                                   │
│                                                                         │
│  Output: folder tree mirroring the original package structure           │
└─────────────────────────────────────────────────────────────────────────┘

Usage:
  python unpack_classes.py <merged_file> [output_dir]

Examples:
  python unpack_classes.py src_all_classes.txt
  python unpack_classes.py src_all_classes.txt ./src_restored
"""

import os
import re
import sys
from pathlib import Path
from typing import Callable, Dict, Any, List
from datetime import datetime
import tkinter as tk
from tkinter import filedialog


# Script metadata (required by main.py)
NAME = "Unpack Classes"
DESCRIPTION = "Extract individual .hx files from a merged text file"

# Regex patterns
# Matches: // FILE: path\to\Class.hx   OR   // FILE: path/to/Class.hx
RE_FILE_MARKER = re.compile(r'^//\s*FILE:\s*(.+?)\s*$', re.MULTILINE)

# Separator line used by collect_classes.py (e.g., "========...")
RE_SEPARATOR = re.compile(r'^[=]{10,}\s*$')


def prompt_input(root: tk.Tk) -> str:
    """
    Open file selection dialog.
    
    @param root Tkinter root window
    @return Selected file path or None if cancelled
    """
    file_path = filedialog.askopenfilename(
        parent=root,
        title="Select Merged Text File to Unpack",
        filetypes=[
            ("Text files", "*.txt"),
            ("All files", "*.*")
        ],
        initialdir=os.path.expanduser("~")
    )
    return file_path if file_path else None


def execute(input_file: str, log: Callable[[str], None]) -> Dict[str, Any]:
    """
    Main execution function.
    """
    input_path = Path(input_file)

    if not input_path.exists():
        raise FileNotFoundError(f"File not found: {input_file}")

    if input_path.is_dir():
        raise ValueError(
            f"Expected a file, but got a directory: {input_file}\n"
            f"Please provide the path to the merged .txt file."
        )

    log(f"Reading merged file: {input_path}")
    content = input_path.read_text(encoding='utf-8')
    log(f"File size: {len(content):,} chars, {content.count(chr(10)):,} lines")

    # Determine output directory (next to input file by default)
    output_dir = input_path.parent / f"{input_path.stem}_unpacked"
    log(f"Output directory: {output_dir}")

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Split by markers
    blocks = _split_by_markers(content)

    if not blocks:
        raise ValueError(
            "No // FILE: markers found in the file.\n"
            "This file was not created by collect_classes.py.\n"
            "Please use a file that contains // FILE: markers."
        )

    log(f"Found {len(blocks)} class block(s)")

    # Process each block
    extracted: List[Dict[str, Any]] = []
    errors: List[str] = []
    duplicates: List[str] = []

    for block in blocks:
        try:
            result = _process_block(block, output_dir, log)
            if result['status'] == 'ok':
                extracted.append(result)
            elif result['status'] == 'duplicate':
                duplicates.append(result['message'])
                extracted.append(result)
            else:
                errors.append(result['message'])
        except Exception as e:
            errors.append(f"Block error: {e}")
            log(f"   Error processing block: {e}")

    # Statistics
    stats = {
        'input_file': str(input_path),
        'output_dir': str(output_dir),
        'total_blocks': len(blocks),
        'extracted': len(extracted),
        'duplicates': len(duplicates),
        'errors': len(errors),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }

    log(f"\n{'=' * 60}")
    log(f"UNPACK COMPLETE")
    log(f"{'=' * 60}")
    log(f"  Blocks:      {stats['total_blocks']}")
    log(f"  Extracted:   {stats['extracted']}")
    log(f"  Duplicates:  {stats['duplicates']}")
    log(f"  Errors:      {stats['errors']}")
    log(f"  Output:      {output_dir}")
    log(f"{'=' * 60}")

    if errors:
        log(f"\nErrors:")
        for err in errors[:10]:
            log(f"   {err}")
        if len(errors) > 10:
            log(f"  ... and {len(errors) - 10} more")

    return stats


# =============================================================================
# MARKER-BASED SPLITTING
# =============================================================================

def _split_by_markers(content: str) -> List[Dict[str, str]]:
    """
    Split content by // FILE: markers.
    
    Each block has:
      - path: original relative path from marker (e.g., "core\\base\\Assembly.hx")
      - content: the code between this marker and the next
    """
    matches = list(RE_FILE_MARKER.finditer(content))
    if not matches:
        return []

    blocks = []
    for i, match in enumerate(matches):
        path = match.group(1).strip()
        path = path.replace('\\', '/')

        start = match.end()

        # Skip ALL metadata header lines added by collect_classes.py
        while start < len(content):
            line_end = content.find('\n', start)
            if line_end == -1:
                line = content[start:]
            else:
                line = content[start:line_end]

            stripped = line.strip()

            if (RE_SEPARATOR.match(stripped) or
                stripped == '' or
                stripped.startswith('// Lines:') or
                stripped.startswith('// FILE:')):
                start = line_end + 1 if line_end != -1 else len(content)
                continue
            break

        # End at next marker or EOF
        if i + 1 < len(matches):
            end = matches[i + 1].start()
            # Trim trailing separator/blank lines before the next marker
            while end > start:
                prev_nl = content.rfind('\n', start, end)
                if prev_nl == -1:
                    segment = content[start:end]
                else:
                    segment = content[prev_nl + 1:end]

                stripped_seg = segment.strip()
                if RE_SEPARATOR.match(stripped_seg) or stripped_seg == '':
                    end = prev_nl if prev_nl != -1 else start
                    continue
                break
        else:
            end = len(content)

        block_content = content[start:end].strip('\n')
        if block_content:
            blocks.append({
                'path': path,
                'content': block_content
            })

    return blocks


# =============================================================================
# BLOCK PROCESSING
# =============================================================================

def _process_block(
    block: Dict[str, str],
    output_dir: Path,
    log: Callable[[str], None]
) -> Dict[str, Any]:
    """
    Process a single class block: determine final path, write file.
    """
    original_path = block['path']
    content = block['content']

    # Normalize path separators
    normalized_path = original_path.replace('\\', '/')

    # Ensure .hx extension
    if not normalized_path.lower().endswith('.hx'):
        normalized_path += '.hx'

    # Sanitize: remove any ".." or absolute path tricks
    parts = [p for p in normalized_path.split('/') if p and p != '.']
    safe_path = '/'.join(parts)

    # Build full output path
    out_file = output_dir / safe_path

    # Handle duplicates
    if out_file.exists():
        stem = out_file.stem
        suffix = out_file.suffix
        parent = out_file.parent
        counter = 1
        while out_file.exists():
            out_file = parent / f"{stem}_{counter}{suffix}"
            counter += 1
        status = 'duplicate'
        message = f"Duplicate: {original_path} -> {out_file.relative_to(output_dir)}"
    else:
        status = 'ok'
        message = f"OK: {out_file.relative_to(output_dir)}"

    # Create parent directories
    out_file.parent.mkdir(parents=True, exist_ok=True)

    # Write file
    out_file.write_text(content, encoding='utf-8')

    log(f"   {message}")

    return {
        'status': status,
        'original_path': original_path,
        'output_path': str(out_file.relative_to(output_dir)),
        'size': len(content),
        'message': message
    }


# =============================================================================
# CLI ENTRY POINT
# =============================================================================

if __name__ == '__main__':
    def print_log(msg: str):
        print(msg)

    if len(sys.argv) < 2:
        print("Usage: python unpack_classes.py <merged_file> [output_dir]")
        print("\nExamples:")
        print("  python unpack_classes.py src_all_classes.txt")
        print("  python unpack_classes.py src_all_classes.txt ./src_restored")
        sys.exit(1)

    input_path = sys.argv[1]
    try:
        result = execute(input_path, print_log)
        print(f"\nDone! Output: {result['output_dir']}")
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)
