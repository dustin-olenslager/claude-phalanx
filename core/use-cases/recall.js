"use strict";
/*
 * core/use-cases/recall.js — query memory (ADR-0004).
 * Pure orchestration over a memory-store port supplied by the caller, so the
 * use-case never touches fs directly. Adapter: adapters/memory/.
 */
const { normalize } = require("../domain/memory-item.js");

// recall(store, query, opts) -> array of normalized memory items.
// store.search(q, opts) -> items[] (adapter contract). Best-effort: no store ->
// empty result, never throws.
function recall(store, query, opts) {
  const q = String(query || "").trim();
  if (!store || typeof store.search !== "function") return [];
  const items = store.search(q, opts || {});
  return (Array.isArray(items) ? items : []).map(normalize);
}

// All memory, newest first (delegate ordering to the adapter when it can).
function recallAll(store, opts) {
  if (!store || typeof store.all !== "function") return [];
  const items = store.all(opts || {});
  return (Array.isArray(items) ? items : []).map(normalize);
}

module.exports = { recall, recallAll };