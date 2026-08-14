"use strict";
/*
 * adapters/memory/obsidian.js — Obsidian-vault memory adapter (ADR-0004).
 *
 * Reads/writes memory as markdown files inside an Obsidian vault (the Harold /
 * GSD file-memory convention: kebab-case .md + YAML frontmatter), so the same
 * core use-cases work whether memory is JSONL, a vault, or sqlite.
 */
const fs = require("fs");
const path = require("path");
const { normalize, slugify } = require("../../core/domain/memory-item.js");

// A memory file inside the vault: name.md with frontmatter type/summary/at/tags.
function filePath(vault, name) {
  return path.join(vault, slugify(name) + ".md");
}

function readFile(file) {
  const text = fs.readFileSync(file, "utf8");
  const fm = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(text);
  const body = fm ? fm[2] : text;
  const meta = {};
  if (fm) {
    for (const line of fm[1].split("\n")) {
      const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line.trim());
      if (m) meta[m[1]] = m[2].replace(/^"|"$/g, "");
    }
  }
  return { name: path.basename(file, ".md"), type: meta.type, summary: meta.summary, at: meta.at, tags: meta.tags ? meta.tags.split(",") : [], content: body.trim() };
}

function add(vault, item) {
  const n = normalize(item);
  const file = filePath(vault, n.name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const front = `---\ntype: ${n.type}\nsummary: "${n.summary.replace(/"/g, "'")}"\nat: ${n.at}\ntags: ${n.tags.join(",")}\n---\n\n`;
  fs.writeFileSync(file, front + n.content + "\n", "utf8");
  return n;
}

function all(vault) {
  if (!fs.existsSync(vault)) return [];
  const out = [];
  for (const f of fs.readdirSync(vault)) {
    if (!f.endsWith(".md")) continue;
    try { out.push(readFile(path.join(vault, f))); } catch { /* skip unreadable */ }
  }
  return out;
}

function search(vault, query, opts) {
  const q = String(query || "").trim().toLowerCase();
  const items = all(vault);
  if (!q) return items;
  const limit = opts && opts.limit;
  return items
    .filter((i) => (i.name + " " + i.summary + " " + i.content + " " + (i.tags || []).join(" ")).toLowerCase().includes(q))
    .slice(0, limit || items.length);
}

// Uniform store-object contract (see jsonl.js store()). Bind a vault.
function store(vault) {
  return {
    add: (item) => add(vault, item),
    all: (opts) => all(vault),
    search: (q, opts) => search(vault, q, opts),
  };
}

module.exports = { add, all, search, filePath, store };