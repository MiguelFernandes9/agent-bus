#!/usr/bin/env python3
"""AST extraction for the project map: source -> symbol structures.

Pure parsing, no output rendering. ``generate.py`` drives file discovery and
writes the map; ``render.py`` turns these structures into markdown.
Call-graph extraction was deliberately dropped: the LSP (pyright) answers
"who calls/references X" precisely, so the map only does discovery.
"""
from __future__ import annotations

import ast
from dataclasses import dataclass, field

_FUNC = (ast.FunctionDef, ast.AsyncFunctionDef)


@dataclass
class Symbol:
    kind: str                 # "function" | "method" | "class"
    name: str
    qualname: str
    lineno: int
    signature: str = ""       # "(a, b=1) -> int"   (functions / methods)
    doc: str = ""             # first docstring line, truncated
    decorators: list = field(default_factory=list)
    bases: list = field(default_factory=list)    # classes only
    parent: str = ""          # owning class name, "" if top-level
    kw: str = "def"           # rendered keyword: def/function/const/interface/…


@dataclass
class FileInfo:
    path: str
    module_doc: str = ""
    symbols: list = field(default_factory=list)
    error: str = ""


def _first_doc_line(node) -> str:
    doc = ast.get_docstring(node, clean=True)
    if not doc:
        return ""
    line = next((ln.strip() for ln in doc.splitlines() if ln.strip()), "")
    return line[:90]


def _signature(node) -> str:
    sig = f"({ast.unparse(node.args)})"
    if node.returns is not None:
        sig += f" -> {ast.unparse(node.returns)}"
    return sig


def _unparse_all(nodes) -> list:
    out = []
    for n in nodes:
        try:
            out.append(ast.unparse(n))
        except Exception:
            pass
    return out


def _func_symbol(node, kind: str, parent: str) -> Symbol:
    qual = f"{parent}.{node.name}" if parent else node.name
    return Symbol(
        kind=kind, name=node.name, qualname=qual, lineno=node.lineno,
        signature=_signature(node), doc=_first_doc_line(node),
        decorators=_unparse_all(node.decorator_list), parent=parent,
    )


def _class_symbols(node) -> list:
    cls = Symbol(
        kind="class", name=node.name, qualname=node.name, lineno=node.lineno,
        doc=_first_doc_line(node), decorators=_unparse_all(node.decorator_list),
        bases=_unparse_all(node.bases),
    )
    out = [cls]
    for child in node.body:
        if isinstance(child, _FUNC):
            out.append(_func_symbol(child, "method", node.name))
    return out


def parse_file(path: str, src: str) -> FileInfo:
    fi = FileInfo(path=path)
    try:
        tree = ast.parse(src, filename=path)
    except SyntaxError as exc:
        fi.error = f"SyntaxError: {exc}"
        return fi
    fi.module_doc = _first_doc_line(tree)
    for node in tree.body:
        if isinstance(node, _FUNC):
            fi.symbols.append(_func_symbol(node, "function", ""))
        elif isinstance(node, ast.ClassDef):
            fi.symbols.extend(_class_symbols(node))
    return fi
