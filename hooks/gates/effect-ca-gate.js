#!/usr/bin/env node
/*
 * PreToolUse gate — typed-error standard + Clean Architecture (CLAUDE.md §14/§3).
 *  - Flags "lang" when the per-language typed-error skill runs (effect-ts for TS).
 *  - Flags "ca" when the clean-architecture skill runs.
 *  - Blocks ANY code edit until clean-architecture was consulted this session.
 *  - Blocks TypeScript edits (.ts/.tsx/.mts/.cts) until effect-ts was consulted.
 * Hard-block by default; PHALANX_WARN=1 for warn-only.
 * Off switch: <CLAUDE_DIR>/.ts-arch-off ("stop effect" / "stop clean-arch").
 * __dirname === CLAUDE_DIR (installed there).
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

const OFF = path.join(HERE, '.ts-arch-off');
const WARN_ONLY = process.env.PHALANX_WARN === '1';

// Item 3 (gates as teachers): remediation recipes from the policy contract
// (<CLAUDE_DIR>/risk-policy.json); missing file/key -> inline fallback. Read-only:
// never changes whether the gate fires, only the help text.
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
const stateDir = path.join('/tmp/phalanx-tsarch', sid);
const flag = (n) => path.join(stateDir, n);
const setFlag = (n) => { try { fs.mkdirSync(stateDir, { recursive: true }); fs.writeFileSync(flag(n), '1'); } catch {} };
const hasFlag = (n) => { try { return fs.existsSync(flag(n)); } catch { return false; } };

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (/effect/i.test(name)) setFlag('effect');
  if (/clean-?architecture|clean-?arch/i.test(name)) setFlag('ca');
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|dart|py|go|rs|java|kt|kts|sql|vue|svelte|rb|php|c|h|cpp|hpp|cs|swift|scala|ex|exs)$/i;
  const TS = /\.(ts|tsx|mts|cts)$/i;
  const esc = HERE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const META = new RegExp('(^' + esc + '|/\\.claude/|^/tmp/|/node_modules/|/\\.git/|/dist/|/build/)');
  if (!(CODE.test(fp) && !META.test(fp))) allow();

  const missing = [];
  if (!hasFlag('ca')) missing.push(rx('effect-ca:ca', 'clean-architecture — Fix → consult the skill, then retry: deps inward, business rules free of IO/frameworks, ports+adapters, DTO boundaries, one composition root; enforce at verify via arch-enforce.'));
  if (TS.test(fp) && !hasFlag('effect')) missing.push(rx('effect-ca:effect', 'effect-ts — Fix → consult the skill, then retry: Effect<A,E,R>, tryPromise over await, Data.TaggedError, Effect.Service/Layer DI, Schema at boundaries, runPromise/runFork at one entrypoint.'));

  if (missing.length) {
    const msg = 'TS/arch gate (§14): code edit blocked — consult skill(s) first: ' + missing.join('; ') + '. Override: touch ' + OFF + ' ("stop effect" / "stop clean-arch").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
