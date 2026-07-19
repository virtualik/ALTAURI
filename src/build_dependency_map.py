from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\Users\ViRTUALiK\Desktop\GITHub_projects\ALTAURI\src")
OUT_MD = ROOT / "dependency_map.md"
OUT_JSON = ROOT / "dependencies.json"
OUT_DOT = ROOT / "dependency_graph.dot"

PACKAGE_RE = re.compile(r"^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)\s*;", re.MULTILINE)
IMPORT_RE = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*(?:\.\*)?)\s*;", re.MULTILINE)
USING_RE = re.compile(r"^\s*using\s+([A-Za-z_][A-Za-z0-9_.]*(?:\.\*)?)\s*;", re.MULTILINE)
IDENT_RE_TEMPLATE = r"(?<![A-Za-z0-9_]){name}(?![A-Za-z0-9_])"

BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_RE = re.compile(r"//.*?$", re.MULTILINE)
STRING_RE = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", re.DOTALL)


def rel_posix(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def module_of(rel: str) -> str:
    return rel[:-3].replace("/", ".") if rel.endswith(".hx") else rel.replace("/", ".")


def folder_of(rel: str) -> str:
    return rel.split("/", 1)[0] if "/" in rel else "(root)"


def strip_noise(text: str) -> str:
    text = BLOCK_COMMENT_RE.sub(" ", text)
    text = LINE_COMMENT_RE.sub(" ", text)
    text = STRING_RE.sub('""', text)
    return text


def main() -> None:
    hx_files = sorted(ROOT.rglob("*.hx"))
    nodes = [rel_posix(p) for p in hx_files]
    node_set = set(nodes)

    module_to_rel = {module_of(rel): rel for rel in nodes}
    type_index: dict[str, list[str]] = defaultdict(list)
    for rel in nodes:
        type_index[Path(rel).stem].append(rel)

    package_by_rel: dict[str, str] = {}
    explicit_imports: dict[str, list[str]] = {}
    explicit_usings: dict[str, list[str]] = {}
    clean_text_by_rel: dict[str, str] = {}

    for path in hx_files:
        rel = rel_posix(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        package_match = PACKAGE_RE.search(text)
        package_by_rel[rel] = package_match.group(1) if package_match else ""
        explicit_imports[rel] = IMPORT_RE.findall(text)
        explicit_usings[rel] = USING_RE.findall(text)
        clean_text_by_rel[rel] = strip_noise(text)

    def resolve_import(import_path: str) -> list[str]:
        if import_path.endswith(".*"):
            prefix = import_path[:-2]
            return sorted(rel for module, rel in module_to_rel.items() if module == prefix or module.startswith(prefix + "."))
        exact = module_to_rel.get(import_path)
        return [exact] if exact else []

    def resolve_type(type_name: str, from_rel: str, imported_modules: set[str], wildcard_prefixes: list[str]) -> str | None:
        candidates = type_index.get(type_name, [])
        if not candidates:
            return None

        from_pkg = package_by_rel.get(from_rel, "")

        for candidate in candidates:
            if module_of(candidate) in imported_modules:
                return candidate

        for candidate in candidates:
            module = module_of(candidate)
            if any(module == prefix or module.startswith(prefix + ".") for prefix in wildcard_prefixes):
                return candidate

        same_pkg = [candidate for candidate in candidates if package_by_rel.get(candidate, "") == from_pkg]
        if len(same_pkg) == 1:
            return same_pkg[0]

        if len(candidates) == 1:
            return candidates[0]

        return None

    edges: set[tuple[str, str, str]] = set()

    for rel in nodes:
        imported_modules = {imp for imp in explicit_imports[rel] if not imp.endswith(".*")}
        wildcard_prefixes = [imp[:-2] for imp in explicit_imports[rel] if imp.endswith(".*")]
        wildcard_prefixes += [use[:-2] for use in explicit_usings[rel] if use.endswith(".*")]

        for imp in explicit_imports[rel] + explicit_usings[rel]:
            for target in resolve_import(imp):
                if target != rel:
                    edges.add((rel, target, "import"))

        own_stem = Path(rel).stem
        for type_name in sorted(type_index.keys()):
            if type_name == own_stem:
                continue
            if re.search(IDENT_RE_TEMPLATE.format(name=re.escape(type_name)), clean_text_by_rel[rel]):
                target = resolve_type(type_name, rel, imported_modules, wildcard_prefixes)
                if target and target != rel:
                    edges.add((rel, target, "reference"))

    edge_list = sorted(edges)
    folder_edges_counter = Counter((folder_of(src), folder_of(dst)) for src, dst, _kind in edge_list)
    out_counter = Counter(src for src, _dst, _kind in edge_list)
    in_counter = Counter(dst for _src, dst, _kind in edge_list)
    folder_out_counter = Counter(folder_of(src) for src, _dst, _kind in edge_list)
    folder_in_counter = Counter(folder_of(dst) for _src, dst, _kind in edge_list)

    adjacency: dict[str, list[dict[str, str]]] = defaultdict(list)
    for src, dst, kind in edge_list:
        adjacency[src].append({"to": dst, "kind": kind})

    payload = {
        "generatedAt": datetime.now().isoformat(timespec="seconds"),
        "root": str(ROOT),
        "nodeCount": len(nodes),
        "edgeCount": len(edge_list),
        "nodes": [
            {
                "file": rel,
                "folder": folder_of(rel),
                "module": module_of(rel),
                "package": package_by_rel.get(rel, ""),
                "imports": explicit_imports.get(rel, []),
                "usings": explicit_usings.get(rel, []),
                "outDegree": out_counter.get(rel, 0),
                "inDegree": in_counter.get(rel, 0),
            }
            for rel in nodes
        ],
        "edges": [{"from": src, "to": dst, "kind": kind} for src, dst, kind in edge_list],
        "folderEdges": [
            {"from": src, "to": dst, "count": count}
            for (src, dst), count in sorted(folder_edges_counter.items())
        ],
    }
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    dot_lines = [
        "digraph dependencies {",
        "  rankdir=LR;",
        "  graph [overlap=false, splines=true];",
        "  node [shape=box, fontsize=10];",
    ]
    for rel in nodes:
        dot_lines.append(f'  "{rel}";')
    for src, dst, kind in edge_list:
        style = "solid" if kind == "import" else "dashed"
        dot_lines.append(f'  "{src}" -> "{dst}" [style={style}];')
    dot_lines.append("}")
    OUT_DOT.write_text("\n".join(dot_lines) + "\n", encoding="utf-8")

    def md_escape(text: str) -> str:
        return text.replace("|", "\\|")

    def mermaid_id(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_]", "_", text)

    top_hubs = sorted(nodes, key=lambda rel: (out_counter.get(rel, 0) + in_counter.get(rel, 0), rel), reverse=True)[:20]
    top_hub_edges = [
        (src, dst, kind)
        for src, dst, kind in edge_list
        if src in top_hubs and dst in top_hubs
    ][:80]

    lines: list[str] = []
    lines.append("# Dependency Map")
    lines.append("")
    lines.append(f"Generated: {payload['generatedAt']}")
    lines.append(f"Root: `{ROOT}`")
    lines.append(f"Files: {len(nodes)} `.hx`")
    lines.append(f"Edges: {len(edge_list)}")
    lines.append("")
    lines.append("## High-level folder graph")
    lines.append("")
    lines.append("```mermaid")
    lines.append("graph LR")
    for (src, dst), count in sorted(folder_edges_counter.items()):
        if count:
            lines.append(f"  {mermaid_id(src)}[\"{src}\"] -->|{count}| {mermaid_id(dst)}[\"{dst}\"]")
    lines.append("```")
    lines.append("")
    lines.append("## Folder dependency counts")
    lines.append("")
    lines.append("| From | To | Edges |")
    lines.append("|---|---:|---:|")
    for (src, dst), count in sorted(folder_edges_counter.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {md_escape(src)} | {md_escape(dst)} | {count} |")
    lines.append("")
    lines.append("## Folder in/out summary")
    lines.append("")
    lines.append("| Folder | Outgoing | Incoming | Total |")
    lines.append("|---|---:|---:|---:|")
    all_folders = sorted(set(folder_out_counter) | set(folder_in_counter))
    for folder in all_folders:
        outgoing = folder_out_counter.get(folder, 0)
        incoming = folder_in_counter.get(folder, 0)
        lines.append(f"| {md_escape(folder)} | {outgoing} | {incoming} | {outgoing + incoming} |")
    lines.append("")
    lines.append("## Main hubs by total degree")
    lines.append("")
    lines.append("| File | Out | In | Total | Folder |")
    lines.append("|---|---:|---:|---:|---|")
    for rel in top_hubs:
        lines.append(
            f"| `{md_escape(rel)}` | {out_counter.get(rel, 0)} | {in_counter.get(rel, 0)} | "
            f"{out_counter.get(rel, 0) + in_counter.get(rel, 0)} | {md_escape(folder_of(rel))} |"
        )
    lines.append("")
    lines.append("## Main hub subgraph")
    lines.append("")
    lines.append("```mermaid")
    lines.append("graph LR")
    for src, dst, _kind in top_hub_edges:
        lines.append(f"  {mermaid_id(src)}[\"{src}\"] --> {mermaid_id(dst)}[\"{dst}\"]")
    lines.append("```")
    lines.append("")
    lines.append("## Full adjacency")
    lines.append("")
    for rel in nodes:
        outgoing = adjacency.get(rel, [])
        if not outgoing:
            continue
        lines.append(f"### `{rel}`")
        for item in outgoing:
            lines.append(f"- `{item['to']}` ({item['kind']})")
        lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")

    print(f"files={len(nodes)}")
    print(f"edges={len(edge_list)}")
    print(f"markdown={OUT_MD}")
    print(f"json={OUT_JSON}")
    print(f"dot={OUT_DOT}")


if __name__ == "__main__":
    main()
