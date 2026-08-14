"use strict";
/*
 * core/domain/memory-item.js — the unified memory-item shape (ADR-0004).
 *
 * Consolidates the GSD file-memory (kebab-case md + frontmatter) and the Phalanx
 * MEMORY.md index into one pure model. Adapters serialize this to their backing
 * store (jsonl, obsidian vault, sqlite). Pure, zero-dep.
 */

const TYPES = ["user", "feedback", "project", "reference"];

// One memory item. `content` holds the fact; `summary` is the one-line index
// entry. `at` is an absolute date (ISO). `tags` optional.
function normalize(item) {
  const raw = item && typeof item === "object" ? item : {};
  const type = TYPES.includes(raw.type) ? raw.type : "reference";
  return {
    name: String(raw.name || "untitled").trim(),
    type,
    content: String(raw.content || "").trim(),
    summary: String(raw.summary || "").trim(),
    at: String(raw.at || new Date().toISOString().slice(0, 10)),
    tags: Array.isArray(raw.tags) ? raw.tags.map(String) : [],
  };
}

// Flatten a name for file/adapter keys: kebab-case, no slashes/spaces.
function slugify(name) {
  return String(name || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

module.exports = { TYPES, normalize, slugify };