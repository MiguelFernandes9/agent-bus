#!/usr/bin/env node
// AST extraction for TypeScript files, using the TARGET REPO's own
// `typescript` package (standard devDependency of any TS project) so the
// canonical tooling carries no node_modules of its own.
//
//   node extract_ts.js <repo-root>   (file list on stdin, one per line)
//
// stdout: JSON array of {path, module_doc, symbols, error}, mirroring the
// Python extract.py structures. Exit 3 = repo has no typescript package
// (generate.py then emits tree-only entries for .ts files).
'use strict';
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
if (!root) {
  console.error('usage: extract_ts.js <repo-root> < files');
  process.exit(2);
}

let ts;
try {
  ts = require(require.resolve('typescript', { paths: [root] }));
} catch {
  process.exit(3);
}

const rels = fs.readFileSync(0, 'utf8').split('\n').filter(Boolean);

function docOf(node) {
  const jd = node.jsDoc;
  if (!jd || !jd.length) return '';
  const c = jd[jd.length - 1].comment;
  const text = typeof c === 'string' ? c : '';
  const line = text.split('\n').map((s) => s.trim()).find(Boolean) || '';
  return line.slice(0, 90);
}

function sigOf(node, sf) {
  if (!node.parameters) return '';
  const ps = node.parameters.map((p) => p.getText(sf)).join(', ');
  const ret = node.type ? ` -> ${node.type.getText(sf)}` : '';
  return `(${ps})${ret}`.slice(0, 120);
}

function lineOf(node, sf) {
  return sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1;
}

function sym(kind, kw, name, parent, node, sf, extra) {
  return Object.assign(
    {
      kind, kw, name,
      qualname: parent ? `${parent}.${name}` : name,
      lineno: lineOf(node, sf),
      signature: '', doc: docOf(node),
      decorators: [], bases: [], parent: parent || '',
    },
    extra || {},
  );
}

function classSymbols(node, sf) {
  const name = node.name ? node.name.text : '(anonymous)';
  const bases = [];
  for (const h of node.heritageClauses || [])
    for (const t of h.types) bases.push(t.getText(sf));
  const out = [sym('class', 'class', name, '', node, sf, { bases })];
  for (const m of node.members) {
    let mname = null;
    if (ts.isConstructorDeclaration(m)) mname = 'constructor';
    else if (ts.isMethodDeclaration(m) && m.name) mname = m.name.getText(sf);
    if (mname === null) continue;
    out.push(sym('method', '', mname, name, m, sf,
                 { signature: sigOf(m, sf) }));
  }
  return out;
}

function fileInfo(rel) {
  let src;
  try {
    src = fs.readFileSync(path.join(root, rel), 'utf8');
  } catch (e) {
    return { path: rel, module_doc: '', symbols: [], error: String(e) };
  }
  const sf = ts.createSourceFile(rel, src, ts.ScriptTarget.Latest, true);
  const symbols = [];
  for (const node of sf.statements) {
    if (ts.isFunctionDeclaration(node) && node.name) {
      symbols.push(sym('function', 'function', node.name.text, '', node, sf,
                       { signature: sigOf(node, sf) }));
    } else if (ts.isClassDeclaration(node)) {
      symbols.push(...classSymbols(node, sf));
    } else if (ts.isInterfaceDeclaration(node)) {
      symbols.push(sym('interface', 'interface', node.name.text, '', node, sf));
    } else if (ts.isTypeAliasDeclaration(node)) {
      symbols.push(sym('type', 'type', node.name.text, '', node, sf));
    } else if (ts.isEnumDeclaration(node)) {
      symbols.push(sym('enum', 'enum', node.name.text, '', node, sf));
    } else if (ts.isVariableStatement(node)) {
      for (const d of node.declarationList.declarations) {
        if (!ts.isIdentifier(d.name) || !d.initializer) continue;
        const init = d.initializer;
        if (ts.isArrowFunction(init) || ts.isFunctionExpression(init)) {
          symbols.push(sym('function', 'const', d.name.text, '', d, sf,
                           { signature: sigOf(init, sf), doc: docOf(node) }));
        }
      }
    }
  }
  return { path: rel, module_doc: '', symbols, error: '' };
}

process.stdout.write(JSON.stringify(rels.map(fileInfo)));
