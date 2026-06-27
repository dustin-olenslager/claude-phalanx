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

// Item 3 (gates as teachers): remediation recipes live in the policy contract
// (<CLAUDE_DIR>/risk-policy.json). Missing file/key -> the inline fallback. Reading
// the policy NEVER changes whether a gate fires -- only the help text it emits.
let POLICY = {};
try { POLICY = JSON.parse(fs.readFileSync(path.join(HERE, 'risk-policy.json'), 'utf8')); } catch {}
const rx = (k, fallback) => {
  const r = POLICY && POLICY.remediation && POLICY.remediation[k];
  return (typeof r === 'string' && r.trim()) ? r : fallback;
};

// Item 2 (risk routing). OFF by default == today's behavior: full gate depth on
// EVERY change. Opt in with BOTH the machine-local switch <CLAUDE_DIR>/.risk-routing-on
// (mirrors .pipeline-off) AND policy.riskRouting.enabled:true (the versioned master).
// When on, a change whose target matches a policy riskTierRule of tier "LOW" takes the
// fast path (skips the plan/verify pre-req). Missing/bad policy or no match -> HIGH.
const ROUTING_ON = (() => {
  try { return fs.existsSync(path.join(HERE, '.risk-routing-on')) && !!POLICY && !!POLICY.riskRouting && POLICY.riskRouting.enabled === true; }
  catch { return false; }
})();
function tierOf(target) {
  try {
    const rules = (POLICY && Array.isArray(POLICY.riskTierRules)) ? POLICY.riskTierRules : [];
    for (const r of rules) {
      if (!r || typeof r.match !== 'string') continue;
      let re; try { re = new RegExp(r.match); } catch { continue; }
      if (re.test(target)) return r.tier === 'LOW' ? 'LOW' : 'HIGH';
    }
  } catch {}
  return 'HIGH'; // fail-safe: unknown/none -> full depth
}
const isLow = (target) => ROUTING_ON && tierOf(target) === 'LOW';
function stagedAllLow(cwd) {
  if (!ROUTING_ON) return false;
  try {
    const out = require('child_process').execFileSync('git', ['diff', '--cached', '--name-only'], { cwd, timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    const files = out ? out.split('\n').filter(Boolean) : [];
    return files.length > 0 && files.every((f) => tierOf(f) === 'LOW');
  } catch { return false; }
}

let input = {};
try { input = JSON.parse(readStdin() || '{}'); } catch { allow(); }
if (fs.existsSync(OFF)) allow();

const tool = input.tool_name || '';
const ti = input.tool_input || {};
const stateDir = H.stateDir('/tmp/phalanx-pipeline', input.session_id);
const { hasFlag, setFlag } = H.flagHelpers(stateDir);

const PLAN_SKILLS = /(phased-plan|system-design|write-spec|brainstorm|product-management|^adr$|adr-kit|deep-research|maintain-mode|optimize-loop|web-mobile-parity)/i;
const VERIFY_SKILLS = /(^verify$|^run$|playwright|arch-enforce|web-mobile-parity)/i;
// test runners, typecheck (tsc --noEmit), and lint runners all count toward verify.
const VERIFY_CMD = H.VERIFY_CMD;

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (PLAN_SKILLS.test(name)) setFlag('planned');
  if (VERIFY_SKILLS.test(name)) setFlag('verified');
  allow();
}

if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (VERIFY_CMD.test(cmd)) setFlag('verified');
  if (/\bgit\b[^\n]*\bcommit\b/.test(cmd) && !hasFlag('verified') && !stagedAllLow(input.cwd || process.cwd())) {
    const msg = 'Pipeline gate (§13): commit blocked — no verify ran this session. ' + rx('pipeline:no-verify', 'Fix → run a test runner, `tsc --noEmit`, a lint (eslint/biome/ruff/golangci-lint/clippy), arch-enforce, or a Playwright E2E, then retry the commit.') + ' Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const isCode = H.CODE.test(fp) && !H.metaRe(HERE).test(fp);
  if (isCode && !hasFlag('planned') && !isLow(fp)) {
    const msg = 'Pipeline gate (§13): code edit blocked — no plan/spec this session. ' + rx('pipeline:no-plan', 'Fix → run phased-plan / system-design / write-spec (or maintain-mode / optimize-loop, or adr for architecture), then retry the edit.') + ' Override: touch ' + OFF + ' ("stop pipeline").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
