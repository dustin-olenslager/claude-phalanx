"use strict";
/*
 * adapters/state/fs.js — filesystem adapter for the unified state (ADR-0004).
 * Reads/writes <project>/.claude-state.json. Never throws on read (missing or
 * corrupt -> normalized default); the composition root decides what to write.
 */
const fs = require("fs");
const path = require("path");
const { STATE_FILE, serialize, parse } = require("../../core/domain/state.js");

function read(cwd) {
  try {
    const text = fs.readFileSync(path.join(cwd, STATE_FILE), "utf8");
    return parse(text);
  } catch {
    return parse("");
  }
}

function write(cwd, state) {
  fs.mkdirSync(cwd, { recursive: true });
  fs.writeFileSync(path.join(cwd, STATE_FILE), serialize(state), "utf8");
  return read(cwd);
}

function pathOf(cwd) { return path.join(cwd, STATE_FILE); }

module.exports = { read, write, pathOf };