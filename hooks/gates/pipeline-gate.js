#!/usr/bin/env node
/*
 * PreToolUse gate — app-build pipeline (CLAUDE.md §13/§15).
 *  - Flags "planned" when a planning skill runs.
 *  - Does NOT flag "verified": a PreToolUse hook runs BEFORE the command, so it can only
 *    observe intent. The verify flag is written by `phalanx-verify` on a real exit 0.
 *  - Blocks code edits until a plan/spec exists ("no code before plan").
 *  - Blocks `git commit` until a verify ran ("no commit before verify").
 * Hard-block by default; set env PHALANX_WARN=1 for warn-only.
 * Off switch: <CLAUDE_DIR>/.pipeline-off (this file is installed INTO CLAUDE_DIR,
 * so __dirname === CLAUDE_DIR). "stop pipeline".
 */
const fs = require('fs');
const path = require('path');
const H = require('./lib/phalanx-hook.js');
const HERE = __dirname;

const readStdin = H.readStdin;
function allow() { process.exit(0); }
const out = (decision, reason) => H.decide('PreToolUse', decision, reason);

const OFF = path.join(HERE, '.pipeline-off');
const WARN_ONLY = process.env.PHALANX_WARN === '1';

let input = {};
try { input = JSON.parse(readStdin() || '{}'); } catch { allow(); }
// .pipeline-off disables only the BLOCKING, never the flag WRITES below. pipeline-gate
// is the single writer of the cross-pass verify flag (.claude-runs/verified.<branch>) that
// loop-integrity-gate rule 5c reads; short-circuiting here starved 5c and deadlocked
// automerge fleet-wide when .pipeline-off is set (observed 2026-07-02, /workspace/depona).
const OFF_SET = fs.existsSync(OFF);

const tool = input.tool_name || '';
const ti = input.tool_input || {};
const cwd = input.cwd || process.cwd();
const stateDir = H.stateDir('/tmp/phalanx-pipeline', input.session_id);
const { hasFlag, setFlag } = H.flagHelpers(stateDir);
// Single WRITER of the cross-pass verify flag (repo+branch keyed under .claude-runs/);
// loop-integrity-gate only reads it. Set it alongside the session-scoped flag so a
// verify survives a fresh supervisor pass (new session id).
// The verify flag is NO LONGER written here. A PreToolUse hook fires BEFORE the command
// runs, so writing it here recorded INTENT, not OUTCOME: `pnpm test` marked the branch
// green whether the suite passed, failed, or died at startup. The single writer is now
// `phalanx-verify`, which records the child's exit code (see scripts/phalanx-verify).
// This gate only READS the flag.
const verified = () => H.verifyFlagFresh(cwd);
const VERIFY_BIN = path.join(HERE, 'bin', 'phalanx-verify');

const PLAN_SKILLS = /(phased-plan|system-design|write-spec|brainstorm|product-management|^adr$|adr-kit|deep-research|maintain-mode|optimize-loop|web-mobile-parity)/i;

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (PLAN_SKILLS.test(name)) setFlag('planned');
  allow();
}

if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (!OFF_SET && /\bgit\b[^\n]*\bcommit\b/.test(cmd) && !verified()) {
    const msg = 'Pipeline gate (§13): commit blocked — no verify exited 0 for this branch. Fix → re-run the check THROUGH the recorder so its exit code is what counts: `' + VERIFY_BIN + ' pnpm verify` (or the same wrapper around your test/typecheck/lint/e2e command), then retry the commit. Running the command bare no longer marks the branch green — only exit 0 through phalanx-verify does. Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (!OFF_SET && isCode && !hasFlag('planned')) {
    const msg = 'Pipeline gate (§13): code edit blocked — no plan/spec this session. Fix → run phased-plan / system-design / write-spec (or maintain-mode / optimize-loop, or adr for architecture), then retry the edit. Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
