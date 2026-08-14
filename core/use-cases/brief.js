"use strict";
/*
 * core/use-cases/brief.js — turn a raw request into a structured brief.
 * Pure. The front door of every build: an intent + constraints -> brief.
 */

// Produce a brief from a request string. Heuristic extraction is intentionally
// light — the agent enriches it; this just guarantees a stable shape.
function brief(request, { title } = {}) {
  const text = String(request || "").trim();
  return {
    title: (title || "").trim() || firstLine(text) || "untitled",
    intent: text,
    status: "drafted",
  };
}

function firstLine(text) {
  const i = text.indexOf("\n");
  const head = (i === -1 ? text : text.slice(0, i)).trim();
  return head.slice(0, 80);
}

module.exports = { brief };