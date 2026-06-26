#!/usr/bin/env node
/*
 * Idempotent CLAUDE.md merge. Replaces the managed block between the
 * PHALANX markers if present; otherwise appends it. Operator's own content
 * outside the markers is never touched.
 * argv: <claudeMdPath> <sectionsPath>
 */
import fs from 'node:fs';

const [, , targetPath, sectionsPath] = process.argv;
if (!targetPath || !sectionsPath) {
  console.error('usage: merge-claude-md.mjs <CLAUDE.md> <sections.md>');
  process.exit(2);
}

const BEGIN = '<!-- PHALANX:BEGIN';
const END = 'PHALANX:END -->';
const block = fs.readFileSync(sectionsPath, 'utf8').trim();
let cur = '';
try { cur = fs.readFileSync(targetPath, 'utf8'); } catch {}

let next;
const b = cur.indexOf(BEGIN);
const e = cur.indexOf(END);
if (b !== -1 && e !== -1 && e > b) {
  next = cur.slice(0, b) + block + cur.slice(e + END.length);
} else {
  next = (cur.trim() ? cur.trimEnd() + '\n\n' : '') + block + '\n';
}
fs.writeFileSync(targetPath, next);
console.log((b !== -1 ? 'updated' : 'appended') + ' PHALANX block -> ' + targetPath);
