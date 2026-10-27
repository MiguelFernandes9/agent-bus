#!/usr/bin/env python3
"""Generate the project map for the current repo / worktree.

Canonical home: ~/.claude/project-map/bin (shared by every repo, like the
agent-bus). All outputs live inside the git dir, so nothing touches the
working tree and nothing can ever be committed:

  enable marker + config : <git-common-dir>/project-map/   (shared per clone)
      exclude            : one top-level dir name per line, kept out of map
  outputs (per worktree) : <git-dir>/project-map/PROJECT_MAP.md + summary.md

Discovers non-ignored Python files via git (so .gitignore is respected),
AST-parses them (extract.py) and renders a directory tree plus a symbol
listing with signatures / docstrings (render.py). Driven by the global
SessionStart / prompt / post-edit hooks; also runnable by hand (refresh.sh).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract import FileInfo, Symbol, parse_file                    # noqa: E402
from render import build_tree, render_full, render_summary          # noqa: E402


def _git(args: list, cwd: str | None = None) -> str:
    out = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                         text=True)
    if out.returncode != 0:
        sys.exit(f"project-map: git {' '.join(args)} failed")
    return out.stdout.strip()


def excludes(common: str) -> set:
    path = os.path.join(common, "project-map", "exclude")
    try:
        with open(path, encoding="utf-8") as fh:
            return {ln.strip().rstrip("/") for ln in fh if ln.strip()}
    except OSError:
        return set()


def src_files(root: str, skip: set, globs: list) -> list:
    """Tracked + untracked-not-ignored source files, sorted and de-duped."""
    found = []
    for args in (["git", "ls-files", *globs],
                 ["git", "ls-files", "--others", "--exclude-standard",
                  *globs]):
        r = subprocess.run(args, cwd=root, capture_output=True, text=True)
        found += [p for p in r.stdout.splitlines() if p]
    keep = [p for p in set(found)
            if p.split("/", 1)[0] not in skip and not p.endswith(".d.ts")]
    return sorted(keep)


def parse_ts(root: str, rels: list) -> list:
    """Parse TS files via extract_ts.js using the repo's own typescript pkg.

    Falls back to tree-only entries (one shared error note) when node or the
    repo's typescript package is unavailable.
    """
    if not rels:
        return []
    note = "ts symbols skipped: node + a repo `typescript` package needed"
    try:
        proc = subprocess.run(
            ["node", os.path.join(HERE, "extract_ts.js"), root],
            input="\n".join(rels), capture_output=True, text=True)
    except OSError:
        proc = None
    if proc is None or proc.returncode != 0:
        return [FileInfo(path=r, error=note) for r in rels]
    files = []
    for fd in json.loads(proc.stdout or "[]"):
        fi = FileInfo(path=fd["path"], module_doc=fd.get("module_doc", ""),
                      error=fd.get("error", ""))
        for sd in fd.get("symbols", []):
            fi.symbols.append(Symbol(**sd))
        files.append(fi)
    return files


def _write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main() -> None:
    root = _git(["rev-parse", "--show-toplevel"])
    common = _git(["rev-parse", "--path-format=absolute",
                   "--git-common-dir"], cwd=root)
    # Enable marker: a repo is mapped only after map-init.sh created this dir.
    if not os.path.isdir(os.path.join(common, "project-map")):
        sys.exit(0)
    gitdir = _git(["rev-parse", "--absolute-git-dir"], cwd=root)
    out_dir = os.path.join(gitdir, "project-map")
    map_path = os.path.join(out_dir, "PROJECT_MAP.md")

    skip = excludes(common)
    py_paths = src_files(root, skip, ["*.py"])
    ts_paths = src_files(root, skip, ["*.ts", "*.tsx"])

    files = []
    for rel in py_paths:
        try:
            with open(os.path.join(root, rel), encoding="utf-8") as fh:
                src = fh.read()
        except OSError:
            continue
        files.append(parse_file(rel, src))
    files += parse_ts(root, ts_paths)
    files.sort(key=lambda f: f.path)

    paths = sorted(py_paths + ts_paths)
    tree = build_tree(paths)
    _write(map_path, render_full(files, tree, map_path))
    _write(os.path.join(out_dir, "summary.md"),
           render_summary(files, tree, map_path))

    n_sym = sum(len(f.symbols) for f in files)
    print(f"project-map: {len(files)} files, {n_sym} symbols -> {map_path}")


if __name__ == "__main__":
    main()
