#!/usr/bin/env node
"use strict";
// UserPromptSubmit hook: terse per-prompt reinforcement that the Phalanx loop is
// the default engine for code-writing requests. Robust against drift in long
// sessions. Stays SILENT (zero tokens) when:
//   - either kill switch is set (<repo>/.work-off or <CLAUDE_DIR>/.work-off);
//   - the prompt reads as a question / read-only ask (deterministic floor);
//   - the prompt shows no code-mutation intent.
// Does NOT restate the full decision tree (that lives in the SessionStart
// injection); one line only, to respect token-conservation rules.
const H = require("./lib/phalanx-hook.js");

const CLAUDE_DIR = __dirname;

const emit = (ctx) => H.emit("UserPromptSubmit", ctx);
const readInput = H.readInput;

const input = readInput();
const cwd = input.cwd || process.cwd();
const prompt = (input.prompt || "").trim();

if (H.killSwitched(cwd, CLAUDE_DIR)) emit("");

// If a loop is already live (open TASKS.md items), one terse re-anchor and done.
const open = H.openTaskCount(cwd);
if (open > 0) {
  emit("Phalanx loop active: keep driving the seeded task(s) via the orchestrator; do not hand-code outside the loop.");
}

// Deterministic floor: read-only / question prompts never trigger.
if (/^(what|why|how|explain|show|list|read|where|who|when|is |are |does |should |can you explain|\?)/i.test(prompt)) emit("");

// Per-request opt-out: caller explicitly wants this one handled inline.
if (/\b(inline|quick fix|no loop)\b/i.test(prompt)) emit("");

// Coarse code-mutation intent. Only reinforce when the prompt looks like it
// asks for a repo file to change; otherwise stay silent.
if (!/\b(add|fix|implement|refactor|build|edit|rename|move|migrate|wire|hook up|create|make|remove|delete|drop|revert|bump|upgrade|downgrade|scaffold|update|change|tweak|adjust|patch|set up|replace|convert|swap|disable|enable)\b/i.test(prompt)) emit("");

emit(
  "Phalanx: if this needs a repo file changed, seed it as '- [ ] (req:NEW) ...' in TASKS.md (repo root) " +
  "and drive ONLY that task via the orchestrator (phase -> workers -> verify -> commit on task/<slug> if verify is green). " +
  "Trivial single-file edit -> inline. Words-only answer -> reply normally, no loop."
);
