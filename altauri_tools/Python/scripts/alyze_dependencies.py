#!/usr/bin/env python3
"""
Analyze Dependencies - Scan Haxe files and analyze import dependencies.

Builds a dependency graph from import statements and generates reports:
- Text report with metrics (in-degree, out-degree)
- DOT graph for Graphviz visualization
- Cycle detection (circular dependencies)
- God-class detection (high in-degree)
- Unused file detection (no imports)

Architecture:
┌─────────────────────────────────────────────────────────────────────────┐
│  Input:  Directory containing .hx files                                 │
│                                                                         │
│  Process:                                                               │
│  1. Scan all .hx files recursively                                      │
│  2. Parse import statements                                             │
│  3. Build dependency graph (adjacency list)                             │
│  4. Calculate metrics:                                                  │
│     - in-degree (how many files import this file)                       │
│     - out-degree (how many files this file imports)                     │
│  5. Detect cycles (DFS-based)                                           │
│  6. Generate reports:                                                   │
│     - Text report with statistics                                       │
│     - DOT graph for Graphviz                                            │
│                                                                         │
│  Output:                                                                │
│  - dependencies_report.txt (text report)                                │
│  - dependencies_graph.dot (Graphviz graph)                              │
│  - Console output with summary                                          │
│                                                                         │
│  Metrics:                                                               │
│  - Total files analyzed                                                 │
│  - Total dependencies                                                   │
│  - Average dependencies per file                                        │
│  - God classes (in-degree > threshold)                                  │
│  - Cyclic dependencies (cycles detected)                                │
│  - Unused files (no imports, not imported)                              │
│                                                                         │
─────────────────────────────────────────────────────────────────────────

Usage:
  python analyze_dependencies.py <directory> [output_dir]

Examples:
  python analyze_dependencies.py src
  python analyze_dependencies.py src ./analysis_output
"""

import os
import re
import sys
from pathlib import Path
from typing import Callable, Dict, Any, List, Set, Tuple
from datetime import datetime
from collections import defaultdict
import tkinter as tk
from tkinter import filedialog


# Script metadata (required by main.py)
NAME = "Analyze Dependencies"
DESCRIPTION = "Analyze import dependencies between Haxe files"

# Regex patterns
# Matches: import package.ClassName;
# Also matches: import package.ClassName.*;
RE_IMPORT = re.compile(
    r'^\s*import\s+([A-Za-z_][\w.]*(?:\.\*)?)\s*;',
    re.MULTILINE
)

# Matches: package X.Y.Z;
RE_PACKAGE = re.compile(
    r'^\s*package\s+([A-Za-z_][\w.]*)\s*;',
    re.MULTILINE
)

# Matches: class/interface/enum/typedef AbstractName
RE_CLASS_DECL = re.compile(
    r'^\s*(?:class|interface|enum|typedef|abstract)\s+([A-Za-z_]\w*)',
    re.MULTILINE
)

# Threshold for "God class" detection
GOD_CLASS_THRESHOLD = 10


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
    
    Analyzes dependencies in the specified directory.
    
    @param input_path Path to directory to scan
    @param log Logging function
    
    @return Dictionary with execution results
    """
    input_dir = Path(input_path)
    
    if not input_dir.exists():
        raise FileNotFoundError(f"Directory not found: {input_path}")
    
    if not input_dir.is_dir():
        raise ValueError(f"Expected a directory: {input_path}")
    
    log(f"Scanning directory: {input_dir}")
    
    # Output directory
    output_dir = input_dir.parent / f"{input_dir.name}_dependencies"
    output_dir.mkdir(parents=True, exist_ok=True)
    log(f"Output directory: {output_dir}")
    
    # Step 1: Find all .hx files
    log("\n=== Step 1: Finding .hx files ===")
    hx_files = []
    for root, dirs, files in os.walk(input_dir):
        # Skip common non-source directories
        dirs[:] = [d for d in dirs if d not in ['node_modules', '.git', 'bin', 'obj', '.haxelib']]
        for file in files:
            if file.endswith('.hx'):
                hx_files.append(Path(root) / file)
    
    if not hx_files:
        raise ValueError(f"No .hx files found in {input_dir}")
    
    log(f"Found {len(hx_files)} .hx file(s)")
    
    # Step 2: Parse imports and build graph
    log("\n=== Step 2: Parsing imports ===")
    dependency_graph = {}  # file_path -> set of imported files
    file_packages = {}     # file_path -> package name
    file_classes = {}      # file_path -> class name
    
    for hx_file in hx_files:
        try:
            content = hx_file.read_text(encoding='utf-8')
            
            # Extract package
            package_match = RE_PACKAGE.search(content)
            package = package_match.group(1) if package_match else ""
            file_packages[hx_file] = package
            
            # Extract class name
            class_match = RE_CLASS_DECL.search(content)
            class_name = class_match.group(1) if class_match else hx_file.stem
            file_classes[hx_file] = class_name
            
            # Extract imports
            imports = set()
            for import_match in RE_IMPORT.finditer(content):
                import_path = import_match.group(1)
                # Convert package.ClassName to file path
                imported_file = resolve_import(import_path, input_dir, hx_files)
                if imported_file and imported_file != hx_file:
                    imports.add(imported_file)
            
            dependency_graph[hx_file] = imports
            
            if len(imports) > 0:
                log(f"  ✓ {hx_file.relative_to(input_dir)}: {len(imports)} imports")
            else:
                log(f"  ○ {hx_file.relative_to(input_dir)}: no imports")
                
        except Exception as e:
            log(f"  ✗ Error reading {hx_file}: {e}")
    
    # Step 3: Calculate metrics
    log("\n=== Step 3: Calculating metrics ===")
    metrics = calculate_metrics(dependency_graph, input_dir)
    
    # Step 4: Detect cycles
    log("\n=== Step 4: Detecting cycles ===")
    cycles = find_cycles(dependency_graph)
    
    # Step 5: Generate reports
    log("\n=== Step 5: Generating reports ===")
    
    # Text report
    text_report_path = output_dir / "dependencies_report.txt"
    generate_text_report(
        text_report_path,
        dependency_graph,
        metrics,
        cycles,
        file_packages,
        file_classes,
        input_dir,
        log
    )
    
    # DOT graph
    dot_report_path = output_dir / "dependencies_graph.dot"
    generate_dot_graph(
        dot_report_path,
        dependency_graph,
        metrics,
        input_dir,
        log
    )
    
    # Summary
    stats = {
        'total_files': len(hx_files),
        'total_dependencies': sum(len(imports) for imports in dependency_graph.values()),
        'avg_dependencies': metrics['avg_out_degree'],
        'god_classes': len(metrics['god_classes']),
        'cycles_found': len(cycles),
        'unused_files': len(metrics['unused_files']),
        'text_report': str(text_report_path),
        'dot_report': str(dot_report_path),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    log(f"\n{'=' * 60}")
    log(f"ANALYSIS COMPLETE")
    log(f"{'=' * 60}")
    log(f"  Total files:         {stats['total_files']}")
    log(f"  Total dependencies:  {stats['total_dependencies']}")
    log(f"  Avg dependencies:    {stats['avg_dependencies']:.1f}")
    log(f"  God classes:         {stats['god_classes']}")
    log(f"  Cycles found:        {stats['cycles_found']}")
    log(f"  Unused files:        {stats['unused_files']}")
    log(f"  Text report:         {text_report_path.name}")
    log(f"  DOT graph:           {dot_report_path.name}")
    log(f"{'=' * 60}")
    
    return stats


def resolve_import(import_path: str, base_dir: Path, hx_files: List[Path]) -> Path:
    """
    Resolve import path to actual file path.
    
    @param import_path Import path (e.g., "core.base.Atom")
    @param base_dir Base directory
    @param hx_files List of all .hx files
    @return Resolved file path or None
    """
    # Convert package.ClassName to relative path
    # core.base.Atom -> core/base/Atom.hx
    parts = import_path.split('.')
    
    # Handle wildcard imports (package.*)
    if parts[-1] == '*':
        parts = parts[:-1]
        # Find all files in this package
        package_path = base_dir / Path(*parts)
        matching_files = [f for f in hx_files if f.parent == package_path]
        return matching_files[0] if matching_files else None
    
    # Regular import
    relative_path = Path(*parts)
    hx_path = relative_path.with_suffix('.hx')
    
    # Try to find in hx_files
    for f in hx_files:
        if f.as_posix().endswith(hx_path.as_posix()):
            return f
    
    return None


def calculate_metrics(dependency_graph: Dict[Path, Set[Path]], base_dir: Path) -> Dict[str, Any]:
    """
    Calculate dependency metrics.
    
    @param dependency_graph Dependency graph
    @param base_dir Base directory
    @return Dictionary with metrics
    """
    # Calculate in-degree (how many files import this file)
    in_degree = defaultdict(int)
    out_degree = {}
    
    for file, imports in dependency_graph.items():
        out_degree[file] = len(imports)
        for imported_file in imports:
            in_degree[imported_file] += 1
    
    # Calculate average out-degree
    total_out = sum(out_degree.values())
    avg_out = total_out / len(out_degree) if out_degree else 0
    
    # Find God classes (high in-degree)
    god_classes = [
        (file, degree)
        for file, degree in in_degree.items()
        if degree >= GOD_CLASS_THRESHOLD
    ]
    god_classes.sort(key=lambda x: x[1], reverse=True)
    
    # Find unused files (no imports, not imported)
    all_files = set(dependency_graph.keys())
    imported_files = set(in_degree.keys())
    files_with_imports = {f for f, imports in dependency_graph.items() if len(imports) > 0}
    
    unused_files = all_files - imported_files - files_with_imports
    
    return {
        'in_degree': dict(in_degree),
        'out_degree': out_degree,
        'avg_out_degree': avg_out,
        'god_classes': god_classes,
        'unused_files': unused_files
    }


def find_cycles(dependency_graph: Dict[Path, Set[Path]]) -> List[List[Path]]:
    """
    Find all cycles in the dependency graph using DFS.
    
    @param dependency_graph Dependency graph
    @return List of cycles (each cycle is a list of files)
    """
    cycles = []
    visited = set()
    rec_stack = set()
    path = []
    
    def dfs(node: Path):
        visited.add(node)
        rec_stack.add(node)
        path.append(node)
        
        for neighbor in dependency_graph.get(node, set()):
            if neighbor not in visited:
                dfs(neighbor)
            elif neighbor in rec_stack:
                # Found a cycle
                cycle_start = path.index(neighbor)
                cycle = path[cycle_start:] + [neighbor]
                cycles.append(cycle)
        
        path.pop()
        rec_stack.remove(node)
    
    for node in dependency_graph:
        if node not in visited:
            dfs(node)
    
    return cycles


def generate_text_report(
    output_path: Path,
    dependency_graph: Dict[Path, Set[Path]],
    metrics: Dict[str, Any],
    cycles: List[List[Path]],
    file_packages: Dict[Path, str],
    file_classes: Dict[Path, str],
    base_dir: Path,
    log: Callable[[str], None]
):
    """
    Generate text report with dependency analysis.
    
    @param output_path Output file path
    @param dependency_graph Dependency graph
    @param metrics Calculated metrics
    @param cycles Detected cycles
    @param file_packages File to package mapping
    @param file_classes File to class mapping
    @param base_dir Base directory
    @param log Logging function
    """
    lines = []
    lines.append("=" * 80)
    lines.append("DEPENDENCY ANALYSIS REPORT")
    lines.append("=" * 80)
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"Base directory: {base_dir}")
    lines.append("")
    
    # Summary
    lines.append("=" * 80)
    lines.append("SUMMARY")
    lines.append("=" * 80)
    lines.append(f"Total files analyzed: {len(dependency_graph)}")
    lines.append(f"Total dependencies: {sum(len(imports) for imports in dependency_graph.values())}")
    lines.append(f"Average dependencies per file: {metrics['avg_out_degree']:.1f}")
    lines.append(f"God classes (in-degree >= {GOD_CLASS_THRESHOLD}): {len(metrics['god_classes'])}")
    lines.append(f"Cyclic dependencies: {len(cycles)}")
    lines.append(f"Unused files: {len(metrics['unused_files'])}")
    lines.append("")
    
    # God classes
    if metrics['god_classes']:
        lines.append("=" * 80)
        lines.append("GOD CLASSES (high in-degree)")
        lines.append("=" * 80)
        lines.append(f"{'File':<50} {'In-Degree':<10}")
        lines.append("-" * 80)
        for file, degree in metrics['god_classes']:
            # FIX: Convert Path to string before formatting with alignment specifier
            rel_path_str = str(file.relative_to(base_dir))
            lines.append(f"{rel_path_str:<50} {degree:<10}")
        lines.append("")
    
    # Cycles
    if cycles:
        lines.append("=" * 80)
        lines.append("CYCLIC DEPENDENCIES")
        lines.append("=" * 80)
        for i, cycle in enumerate(cycles, 1):
            lines.append(f"\nCycle #{i}:")
            for j, file in enumerate(cycle):
                # FIX: Convert Path to string
                rel_path_str = str(file.relative_to(base_dir))
                arrow = " → " if j < len(cycle) - 1 else " → (back to start)"
                lines.append(f"  {rel_path_str}{arrow}")
        lines.append("")
    
    # Unused files
    if metrics['unused_files']:
        lines.append("=" * 80)
        lines.append("UNUSED FILES (no imports, not imported)")
        lines.append("=" * 80)
        for file in sorted(metrics['unused_files']):
            # FIX: Convert Path to string
            rel_path_str = str(file.relative_to(base_dir))
            lines.append(f"  {rel_path_str}")
        lines.append("")
    
    # Detailed dependency list
    lines.append("=" * 80)
    lines.append("DETAILED DEPENDENCIES")
    lines.append("=" * 80)
    lines.append("")
    
    for file in sorted(dependency_graph.keys()):
        # FIX: Convert Path to string
        rel_path_str = str(file.relative_to(base_dir))
        package = file_packages.get(file, "")
        class_name = file_classes.get(file, "")
        imports = dependency_graph[file]
        
        lines.append(f"File: {rel_path_str}")
        lines.append(f"  Package: {package}")
        lines.append(f"  Class: {class_name}")
        lines.append(f"  Imports ({len(imports)}):")
        
        if imports:
            for imported_file in sorted(imports):
                # FIX: Convert Path to string
                imported_rel_str = str(imported_file.relative_to(base_dir))
                lines.append(f"    - {imported_rel_str}")
        else:
            lines.append("    (none)")
        
        lines.append("")
    
    # Write to file
    output_path.write_text('\n'.join(lines), encoding='utf-8')
    log(f"  ✓ Text report: {output_path}")


def generate_dot_graph(
    output_path: Path,
    dependency_graph: Dict[Path, Set[Path]],
    metrics: Dict[str, Any],
    base_dir: Path,
    log: Callable[[str], None]
):
    """
    Generate DOT graph for Graphviz visualization.
    
    @param output_path Output file path
    @param dependency_graph Dependency graph
    @param metrics Calculated metrics
    @param base_dir Base directory
    @param log Logging function
    """
    lines = []
    lines.append("digraph dependencies {")
    lines.append("  rankdir=LR;")
    lines.append("  node [shape=box, style=filled, fillcolor=lightblue];")
    lines.append("  edge [color=gray];")
    lines.append("")
    
    # Create node IDs (sanitize paths)
    def sanitize_path(path: Path) -> str:
        return "node_" + str(path.relative_to(base_dir)).replace('/', '_').replace('\\', '_').replace('.', '_')
    
    # Add nodes
    god_class_files = {file for file, _ in metrics['god_classes']}
    
    for file in dependency_graph:
        node_id = sanitize_path(file)
        # FIX: Convert Path to string
        rel_path_str = str(file.relative_to(base_dir))
        class_name = file_classes.get(file, "")
        
        # Color coding
        if file in god_class_files:
            fill_color = "red"
        elif len(dependency_graph[file]) == 0:
            fill_color = "yellow"
        else:
            fill_color = "lightblue"
        
        label = f"{class_name}\\n{rel_path_str}"
        lines.append(f'  {node_id} [label="{label}", fillcolor={fill_color}];')
    
    lines.append("")
    
    # Add edges
    for file, imports in dependency_graph.items():
        from_id = sanitize_path(file)
        for imported_file in imports:
            to_id = sanitize_path(imported_file)
            lines.append(f"  {from_id} -> {to_id};")
    
    lines.append("}")
    
    # Write to file
    output_path.write_text('\n'.join(lines), encoding='utf-8')
    log(f"  ✓ DOT graph: {output_path}")
    log(f"    (Use Graphviz to visualize: dot -Tpng {output_path.name} -o graph.png)")

if __name__ == '__main__':
    def print_log(msg: str):
        print(msg)
    
    if len(sys.argv) < 2:
        print("Usage: python analyze_dependencies.py <directory> [output_dir]")
        print("\nExamples:")
        print("  python analyze_dependencies.py src")
        print("  python analyze_dependencies.py src ./analysis_output")
        sys.exit(1)
    
    try:
        result = execute(sys.argv[1], print_log)
        print(f"\nDone! Reports saved to: {result['text_report']}")
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)
