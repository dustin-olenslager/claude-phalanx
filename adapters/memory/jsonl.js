"use strict";
/*
 * adapters/memory/jsonl.js — append-only JSONL memory store (ADR-0004).
 *
 * Default memory adapter. One item per line. Zero-dep, no index to rebuild —
 * good enough for a single-operator memory. Search is a linear scan, which is
 * fine at this scale; swap the adapter (obsidian/sqlite) without touching core.
 */
const fs = require("fs");
const path = require("path");
const { normalize, slugify } = require("../../core/domain/memory-item.js");

// Open the store, creating dirs as needed. Returns the file path.
function open(dir) {
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, "memory.jsonl");
}

// Append one normalized item. Returns the normalized item.
function add(dir, item) {
  const n = normalize(item);
  const file = open(dir);
  fs.appendFileSync(file, JSON.stringify(n) + "\n", "utf8");
  return n;
}

// Read all items (newest last, in append order).
function all(dir) {
  const file = open(dir);
  if (!fs.existsSync(file)) return [];
  const out = [];
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line)); } catch { /* skip corrupt line */ }
  }
  return out;
}

// Substring search over name/summary/content/tags. Case-insensitive.
function search(dir, query, opts) {
  const q = String(query || "").trim().toLowerCase();
  const items = all(dir);
  if (!q) return items;
  const limit = opts && opts.limit;
  return items
    .filter((i) => (i.name + " " + i.summary + " " + i.content + " " + (i.tags || []).join(" ")).toLowerCase().includes(q))
    .slice(0, limit || items.length);
}

// Delete by name slug. Returns true if removed.
function remove(dir, name) {
  const target = slugify(name);
  const file = open(dir);
  const lines = fs.readFileSync(file, "utf8").split("\n").filter(Boolean);
  const kept = lines.filter((l) => { try { return slugify(JSON.parse(l).name) !== target; } catch { return false; } });
  if (kept.length === lines.length) return false;
  fs.writeFileSync(file, kept.join("\n") + (kept.length ? "\n" : ""), "utf8");
  return true;
}

// Uniform store-object contract (matches core/ports + use-cases): a ready-made
// handle bound to a dir. Prefer this over the raw functions in the CLI/harness.
function store(dir) {
  return {
    add: (item) => add(dir, item),
    all: (opts) => all(dir),
    search: (q, opts) => search(dir, q, opts),
    remove: (name) => remove(dir, name),
  };
}

module.exports = { open, add, all, search, remove, store };