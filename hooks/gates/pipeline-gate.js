#!/usr/bin/env node
/*
 * PreToolUse gate — app-build pipeline (CLAUDE.md §13/§15).
 *  - Flags "planned" when a planning skill runs; "verified" when a verify/test/
 *    typecheck/lint skill or shell command runs.
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
if (fs.existsSync(OFF)) allow();

const tool = input.tool_name || '';
const ti = input.tool_input || {};
const cwd = input.cwd || process.cwd();
const stateDir = H.stateDir('/tmp/phalanx-pipeline', input.session_id);
const { hasFlag, setFlag } = H.flagHelpers(stateDir);
// Single WRITER of the cross-pass verify flag (repo+branch keyed under .claude-runs/);
// loop-integrity-gate only reads it. Set it alongside the session-scoped flag so a
// verify survives a fresh supervisor pass (new session id).
const markVerified = () => { setFlag('verified'); H.markVerified(cwd); };

const PLAN_SKILLS = /(phased-plan|system-design|write-spec|brainstorm|product-management|^adr$|adr-kit|deep-research|maintain-mode|optimize-loop|web-mobile-parity)/i;
const VERIFY_SKILLS = /(^verify$|^run$|playwright|arch-enforce|web-mobile-parity)/i;
// test runners, typecheck (tsc --noEmit), and lint runners all count toward verify.
const VERIFY_CMD = H.VERIFY_CMD;

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (PLAN_SKILLS.test(name)) setFlag('planned');
  if (VERIFY_SKILLS.test(name)) markVerified();
  allow();
}

if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (VERIFY_CMD.test(cmd)) markVerified();
  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd) && !hasFlag('verified')) {
    const msg = 'Pipeline gate (§13): commit blocked — no verify ran this session. Fix → run a test runner, `tsc --noEmit`, a lint (eslint/biome/ruff/golangci-lint/clippy), arch-enforce, or a Playwright E2E, then retry the commit. Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (isCode && !hasFlag('planned')) {
    const msg = 'Pipeline gate (§13): code edit blocked — no plan/spec this session. Fix → run phased-plan / system-design / write-spec (or maintain-mode / optimize-loop, or adr for architecture), then retry the edit. Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
