#!/usr/bin/env node
"use strict";
// SessionStart hook: make the Phalanx loop the DEFAULT engine for code work.
// Three outcomes, in order:
//   1. open TASKS.md items + BLOCKED in PROGRESS.md  -> pause, surface blocker
//   2. open TASKS.md items                           -> resume the active loop
//   3. no open items (fresh request incoming)        -> inject the STANDING RULE
// Silenced by either kill switch:
//   <repo>/.work-off (per-repo) or <CLAUDE_DIR>/.work-off (global).
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");

const CLAUDE_DIR = __dirname;

const emit = (ctx) => H.emit("SessionStart", ctx);
const readInput = H.readInput;

const input = readInput();
const cwd = input.cwd || process.cwd();
const ONESHOT = process.env.PHALANX_ONESHOT === "1";

if (H.killSwitched(cwd, CLAUDE_DIR)) emit("");

// Single source of truth for loop state (lib/phalanx-hook.js) -- replaces the
// blocked/respawn/risk re-parses that were duplicated here.
const { open, blocked, respawn, riskLine } = H.tasksState(cwd);

// A stale BLOCKED line must NOT smother a brand-new request -- only suppress
// when there is actually open work to be blocked on.
if (open > 0 && blocked) {
  emit("AUTONOMOUS LOOP paused: PROGRESS.md has a BLOCKED line. Surface the blocker to the user and wait -- do not auto-start.");
}

// Operator-risk tripwire (item 7): an open task -- OR a checkpoint note in
// PROGRESS.md -- implying an irreversible / destructive / data-continuity change
// must NOT auto-run. Surface it and make the loop confirm (write BLOCKED) first.
if (open > 0 && riskLine) {
  emit("AUTONOMOUS LOOP: a data-risk / irreversible-change flag is present (TASKS.md or PROGRESS.md) -- \"" + riskLine.slice(0, 160) + "\". Do NOT auto-execute it. Confirm with the operator; if it is destructive or irreversible, write 'BLOCKED: <reason, needs operator confirm>' to PROGRESS.md and halt. Other safe tasks proceed normally.");
}

if (open > 0) {
  const resume = respawn ? " A RESPAWN checkpoint exists in PROGRESS.md -- resume from it first." : "";
  const scope = ONESHOT
    ? "Work ONLY the top task to green this run, then STOP and report -- do not walk the rest of the backlog."
    : "Work the top task to green, commit it, check it off, continue to the next.";
  emit(
    `AUTONOMOUS LOOP ACTIVE -- ${open} open task(s) in TASKS.md.${resume} ` +
    `Begin the /work loop now WITHOUT waiting for a command: read PROGRESS.md (resume) then TASKS.md, ` +
    `spawn the orchestrator subagent. ${scope} Commit on a task/<slug> branch ONLY if a verify/test ran green this turn. ` +
    `Honor all gates and the 45% context ceiling. ` +
    `To stop: user says "stop loop", or touch ./.work-off (this repo) or ${CLAUDE_DIR.replace(/\\/g,"/")}/.work-off (everywhere).`
  );
}

// open === 0: no seeded task. Inject the standing rule so the NEXT request that
// needs a file changed enters the loop automatically.
emit(
  "PHALANX LOOP = DEFAULT ENGINE FOR CODE WORK THIS SESSION.\n\n" +
  "TRIGGER TEST (apply per request): does fulfilling it REQUIRE creating, modifying, " +
  "or deleting a file in this repo (code, test, config, schema, build, infra-as-code, " +
  "or shipped docs)?\n" +
  "- YES -> run the loop: (1) append the request VERBATIM as a '- [ ] (req:NEW) ...' line " +
  "to TASKS.md at the repo root (git rev-parse --show-toplevel; create the file if missing); " +
  "(2) drive THAT task via the orchestrator subagent (phase -> workers -> verify -> commit on " +
  "task/<slug> ONLY if a verify/test ran green this turn; otherwise leave changes uncommitted and report). " +
  "Do NOT hand-code a one-off outside the loop.\n" +
  "- NO (the complete answer is words only -- an explanation, opinion, plan, review, yes/no, or a " +
  "code snippet shown for discussion and not written to disk) -> answer normally. Do NOT touch " +
  "TASKS.md, do NOT start the loop.\n\n" +
  "This is about OUTCOME, not phrasing. 'can you make the button blue?' is YES. A terse imperative " +
  "('fix the bug', 'refactor X', 'rename Y', 'bump the dep', 'revert', 'wire up Z') is YES and is " +
  "itself the complete task -- seed it verbatim. 'explain X', 'what would you change?', 'is X installed?', " +
  "'why is this failing?' are NO -- words-only.\n" +
  "DIAGNOSTIC -> FIX: answer a 'why/what/is' read-only FIRST; the moment the request is to APPLY the fix, " +
  "THAT request is the seed -> enter the loop.\n" +
  "TRIVIAL FAST-PATH: a single-file edit under ~15 changed lines with an obvious local check (typo, copy, " +
  "comment, version/config value, import fix) may be done INLINE -- no TASKS.md, no orchestrator, no branch. " +
  "Reserve the full loop for multi-file / multi-step / plan-needed / branch-worthy work. Per-request opt-out: " +
  "'inline' / 'quick fix' / 'no loop' -> handle directly this turn.\n" +
  (ONESHOT ? "ONE-SHOT (non-interactive): seed and drive ONLY the current request's task, never the backlog; do not write RESPAWN.\n" : "") +
  "If TASKS.md already has open '- [ ]' items, resume/continue them. " +
  "Honor BLOCKED/RESPAWN as before. Stop: 'stop loop' or touch ./.work-off / " +
  CLAUDE_DIR.replace(/\\/g,"/") + "/.work-off."
);
