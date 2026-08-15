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
const H = require('./lib/phalanx-hook.js');
const HERE = __dirname;

const readStdin = H.readStdin;
function allow() { process.exit(0); }
const out = (decision, reason) => H.decide('PreToolUse', decision, reason);

const OFF = path.join(HERE, '.ts-arch-off');
const WARN_ONLY = process.env.PHALANX_WARN === '1';

let input = {};
try { input = JSON.parse(readStdin() || '{}'); } catch { allow(); }
if (fs.existsSync(OFF)) allow();

// §14 descoped to per-repo OPT-IN (2026-07-23): the always-on global hard-block was
// ceremony-per-token that fought §9 (no premature abstraction) — it forced Effect+CleanArch
// on throwaway scripts. Enforcement now applies ONLY inside a repo that opts in with a
// `.ts-arch-on` marker (walk the edited file's dir tree, then the session cwd tree). This
// check gates the Edit/Write BLOCK only — Skill flag-recording below still always runs so a
// consulted skill is remembered for the opt-in repos. Global `.ts-arch-off` still force-off.
function optedIn(fp) {
  const starts = [];
  if (fp) { try { starts.push(path.dirname(path.resolve(fp))); } catch {} }
  if (input.cwd) starts.push(input.cwd);
  starts.push(process.cwd());
  for (const s of starts) {
    let d = s;
    try {
      for (let i = 0; i < 40 && d; i++) {
        if (fs.existsSync(path.join(d, '.ts-arch-on'))) return true;
        const p = path.dirname(d);
        if (p === d) break;
        d = p;
      }
    } catch {}
  }
  return false;
}

const tool = input.tool_name || '';
const ti = input.tool_input || {};
const stateDir = H.stateDir('/tmp/phalanx-tsarch', input.session_id);
const { hasFlag, setFlag } = H.flagHelpers(stateDir);

if (tool === 'Skill') {
  const name = (ti.skill || ti.name || '') + '';
  if (/effect/i.test(name)) setFlag('effect');
  if (/clean-?architecture|clean-?arch/i.test(name)) setFlag('ca');
  allow();
}

if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  const TS = H.TS;
  if (!(H.CODE.test(fp) && !H.metaRe(HERE).test(fp))) allow();
  if (!optedIn(fp)) allow(); // per-repo opt-in: no `.ts-arch-on` in scope -> no enforcement

  const missing = [];
  if (!hasFlag('ca')) missing.push('clean-architecture — Fix → consult the skill, then retry: deps inward, business rules free of IO/frameworks, ports+adapters, DTO boundaries, one composition root; enforce at verify via arch-enforce.');
  if (TS.test(fp) && !hasFlag('effect')) missing.push('effect-ts — Fix → consult the skill, then retry: Effect<A,E,R>, tryPromise over await, Data.TaggedError, Effect.Service/Layer DI, Schema at boundaries, runPromise/runFork at one entrypoint.');

  if (missing.length) {
    const msg = 'TS/arch gate (§14): code edit blocked — consult skill(s) first: ' + missing.join('; ') + '. Override: touch ' + OFF + ' ("stop effect" / "stop clean-arch").';
    return WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg);
  }
  allow();
}

allow();
