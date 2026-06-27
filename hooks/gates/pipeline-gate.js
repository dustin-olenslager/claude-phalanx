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
const HERE = __dirname;

function readStdin() { try { return fs.readFileSync(0, 'utf8'); } catch { return ''; } }
function allow() { process.exit(0); }
function out(decision, reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: decision, permissionDecisionReason: reason },
  }));
  process.exit(0);
}

const OFF = path.join(HERE, '.pipeline-off');
const WARN_ONLY = process.env.PHALANX_WARN === '1';

// Item 3 (gates as teachers): remediation recipes live in the policy contract
// (<CLAUDE_DIR>/risk-policy.json). Missing file/key -> the inline fallback. Reading
// the policy NEVER changes whether a gate fires -- only the help text it emits.
let POLICY = {};
try { POLICY = JSON.parse(fs.readFileSync(path.join(HERE, 'risk-policy.json'), 'utf8')); } catch {}
const rx = (k, fallback) => {
  const r = POLICY && POLICY.remediation && POLICY.remediation[k];
  return (typeof r === 'string' && r.trim()) ? r : fallback;
};

let input = {};
try { input = JSON.parse(readStdin() || '{}'); } catch { allow(); }
if (fs.existsSync(OFF)) allow();

const tool = input.tool_name || '';
const ti = input.tool_input || {};
const sid = (input.session_id || 'nosess').replace(/[^a-zA-Z0-9_-]/g, '');
const stateDir = path.join('/tmp/phalanx-pipeline', sid);
const flag = (n) => path.join(stateDir, n);
const setFlag = (n) => { try { fs.mkdirSync(stateDir, { recursive: true }); fs.writeFileSync(flag(n), '1'); } catch {} };
const hasFlag = (n) => { try { return fs.existsSync(flag(n)); } catch { return false; } };

const PLAN_SKILLS = /(phased-plan|system-design|write-spec|brainstorm|product-management|^adr$|adr-kit|deep-research|maintain-mode|optimize-loop|web-mobile-parity)/i;
const VERIFY_SKILLS = /(^verify$|^run$|playwright|arch-enforce|web-mobile-parity)/i;
// test runners, typecheck (tsc --noEmit), and lint runners all count toward verify.
const VERIFY_CMD = /(playwright|\be2e\b|vitest|jest|flutter\s+test|pytest|\bgo\s+test\b|cargo\s+test|npm\s+(run\s+)?test|pnpm\s+(run\s+)?test|yarn\s+test|cypress|\btsc\b|--noEmit|typecheck|eslint|biome|\bruff\b|golangci-lint|clippy|\blint\b|depcruise|dependency-cruiser|import-linter|archunit|\bverify\b)/i;

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (PLAN_SKILLS.test(name)) setFlag('planned');
  if (VERIFY_SKILLS.test(name)) setFlag('verified');
  allow();
}

if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (VERIFY_CMD.test(cmd)) setFlag('verified');
  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd) && !hasFlag('verified')) {
    const msg = 'Pipeline gate (§13): commit blocked — no verify ran this session. ' + rx('pipeline:no-verify', 'Fix → run a test runner, `tsc --noEmit`, a lint (eslint/biome/ruff/golangci-lint/clippy), arch-enforce, or a Playwright E2E, then retry the commit.') + ' Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|dart|py|go|rs|java|kt|kts|sql|vue|svelte|rb|php|c|h|cpp|hpp|cs|swift|scala|ex|exs)$/i;
  const esc = HERE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const META = new RegExp('(^' + esc + '|/\\.claude/|^/tmp/|/node_modules/|/\\.git/|/dist/|/build/)');
  const isCode = CODE.test(fp) && !META.test(fp);
  if (isCode && !hasFlag('planned')) {
    const msg = 'Pipeline gate (§13): code edit blocked — no plan/spec this session. ' + rx('pipeline:no-plan', 'Fix → run phased-plan / system-design / write-spec (or maintain-mode / optimize-loop, or adr for architecture), then retry the edit.') + ' Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
