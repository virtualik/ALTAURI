#!/usr/bin/env python3
"""
Clean Comments - Remove comments and empty lines from Haxe code.
Safely ignores comment markers inside string literals.
"""

import re
import sys
from pathlib import Path
from typing import Callable, Dict, Any

# Script metadata (required by main.py)
NAME = "Clean Comments"
DESCRIPTION = "Remove comments and blank lines to analyze pure code size"

def execute(input_file: str, log: Callable[[str], None]) -> Dict[str, Any]:
    """
    Main execution function.
    """
    input_path = Path(input_file)
    
    if not input_path.exists():
        raise FileNotFoundError(f"File not found: {input_file}")
    
    log(f"Reading file: {input_path}")
    content = input_path.read_text(encoding='utf-8')
    
    log("Removing comments and blank lines...")
    cleaned_content = remove_comments_and_blanks(content)
    
    # Generate output filename
    output_path = input_path.parent / f"{input_path.stem}_clean{input_path.suffix}"
    
    log(f"Writing output: {output_path}")
    output_path.write_text(cleaned_content, encoding='utf-8')
    
    # Statistics
    original_lines = len(content.split('\n'))
    cleaned_lines = len(cleaned_content.split('\n'))
    removed_lines = original_lines - cleaned_lines
    percent_removed = (removed_lines / original_lines * 100) if original_lines > 0 else 0
    
    # Count actual code lines (non-empty, non-comment)
    code_lines = sum(1 for line in cleaned_content.split('\n') if line.strip())
    
    stats = {
        'input_file': str(input_path),
        'output_file': str(output_path),
        'original_lines': original_lines,
        'cleaned_lines': cleaned_lines,
        'pure_code_lines': code_lines,
        'removed_lines': removed_lines,
        'percent_removed': round(percent_removed, 1)
    }
    
    log(f"\n{'=' * 60}")
    log(f"CLEANING COMPLETE")
    log(f"{'=' * 60}")
    log(f"  Original lines:     {stats['original_lines']:,}")
    log(f"  Lines after clean:  {stats['cleaned_lines']:,}")
    log(f"  Pure code lines:    {stats['pure_code_lines']:,}")
    log(f"  Removed (comments/blank): {stats['removed_lines']:,} ({percent_removed:.1f}%)")
    log(f"  Output saved to:    {output_path.name}")
    log(f"{'=' * 60}")
    
    return stats


def remove_comments_and_blanks(content: str) -> str:
    """
    Remove single-line (//), multi-line (/* */) comments, and blank lines.
    Crucially, it preserves '//' or '/*' if they are inside string literals.
    """
    # Regex explanation:
    # Group 1: String literals (double or single quotes, handling escapes)
    # Group 2: Single-line comments
    # Group 3: Multi-line comments
    pattern = r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|(//.*?$)|(/\*.*?\*/)'
    
    def replacer(match):
        # If Group 1 matched (it's a string), keep it exactly as is
        if match.group(1):
            return match.group(1)
        # If Group 2 or 3 matched (it's a comment), replace with empty string
        return ''
    
    # Apply regex with MULTILINE (for ^ and $) and DOTALL (for /* ... */)
    no_comments = re.sub(pattern, replacer, content, flags=re.MULTILINE | re.DOTALL)
    
    # Remove blank lines and lines with only whitespace
    lines = no_comments.split('\n')
    cleaned_lines = [line for line in lines if line.strip() != '']
    
    return '\n'.join(cleaned_lines)


if __name__ == '__main__':
    # Standalone execution support
    def print_log(msg: str):
        print(msg)
    
    if len(sys.argv) < 2:
        print("Usage: python clean_comments.py <input_file>")
        print("\nExample:")
        print("  python clean_comments.py src_all_classes.txt")
        sys.exit(1)
    
    try:
        result = execute(sys.argv[1], print_log)
        print(f"\nDone! Output: {result['output_file']}")
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)