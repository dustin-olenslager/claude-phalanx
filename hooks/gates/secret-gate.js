#!/usr/bin/env node
/*
 * PreToolUse gate — secret scan (CLAUDE.md §13 security phase).
 * Two layers:
 *  1. WRITE-TIME (Edit/Write/MultiEdit): scan the content about to hit disk and
 *     block a hard-coded credential before it's even written.
 *  2. COMMIT-TIME (Bash `git commit`): scan the STAGED diff with gitleaks (then
 *     trufflehog) if installed, else a regex fallback; deny with file:line.
 * SECURITY gate: ALWAYS hard-blocks. Unlike the discipline gates (pipeline,
 * loop-integrity) this does NOT honor PHALANX_WARN -- a leaked credential is not
 * a warn-able lint. The only off switch is <CLAUDE_DIR>/.secret-scan-off, which
 * lives OUTSIDE the agent-writable repo tree (__dirname === CLAUDE_DIR), so the
 * agent cannot `touch` its own bypass inside the repo it is editing.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const H = require('./lib/phalanx-hook.js');
const HERE = __dirname;

const readStdin = H.readStdin;
function allow() { process.exit(0); }
const out = (decision, reason) => H.decide('PreToolUse', decision, reason);

// Off switch MUST live under CLAUDE_DIR (HERE), never the agent-writable repo.
const OFF = path.join(HERE, '.secret-scan-off');
// SECURITY gate: always deny on a hit. PHALANX_WARN downgrades discipline gates,
// NOT this one -- a hard-coded credential is non-bypassable by env.
const block = (msg) => out('deny', msg);

let input = {};
try { input = JSON.parse(readStdin() || '{}'); } catch { allow(); }
if (fs.existsSync(OFF)) allow();

const tool = input.tool_name || '';
const ti = input.tool_input || {};

const RULES = [
  ['AWS access key id', /\bAKIA[0-9A-Z]{16}\b/],
  ['AWS secret access key', /aws_secret_access_key\s*[:=]\s*['"]?[0-9a-zA-Z/+]{40}['"]?/i],
  ['Private key block', /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----/],
  ['GitHub token', /\bgh[pousr]_[0-9A-Za-z]{20,}\b/],
  ['Slack token', /\bxox[baprs]-[0-9A-Za-z-]{10,}\b/],
  ['Stripe live key', /\bsk_live_[0-9a-zA-Z]{16,}\b/],
  ['Google API key', /\bAIza[0-9A-Za-z_\-]{35}\b/],
  ['Generic hardcoded secret', /(?:api[_-]?key|secret|token|password|passwd|client[_-]?secret|access[_-]?token)\s*[:=]\s*['"][^'"\s${}]{16,}['"]/i],
];
function isSecretLine(line) {
  if (/process\.env|import\.meta\.env|os\.environ|getenv|System\.getenv|Deno\.env|<[^>]+>|\$\{|YOUR_|REPLACE|EXAMPLE|placeholder|xxxx|\.\.\./i.test(line)) return false;
  return RULES.some(([, re]) => re.test(line));
}
function labelFor(line) { for (const [l, re] of RULES) if (re.test(line)) return l; return 'secret'; }

// A `cd <dir> &&` chain or `git -C <dir>` prefix in the command targets a repo
// other than the harness's own cwd (e.g. `cd /workspace/depona && git commit ...`
// while the payload cwd is still /workspace) -- resolve the REAL target dir so
// the scan runs where the commit actually happens, not wherever the hook fired.
function resolveTargetCwd(cmd, payloadCwd) {
  const dashC = cmd.match(/\bgit\s+-C\s+(\S+)/);
  if (dashC) {
    const dir = dashC[1].replace(/^['"]|['"]$/g, '');
    return path.isAbsolute(dir) ? dir : path.resolve(payloadCwd, dir);
  }
  let cwd = payloadCwd;
  for (const m of cmd.matchAll(/(?:^|&&)\s*cd\s+(\S+)\s*(?=&&|$)/g)) {
    const dir = m[1].replace(/^['"]|['"]$/g, '');
    cwd = path.isAbsolute(dir) ? dir : path.resolve(cwd, dir);
  }
  return cwd;
}

// ---- COMMIT-TIME ------------------------------------------------------------
if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (!/\bgit\b[^\n]*\bcommit\b/.test(cmd)) allow();
  let cwd = resolveTargetCwd(cmd, input.cwd || process.cwd());
  const have = (bin) => { try { execSync('command -v ' + bin, { stdio: 'ignore' }); return true; } catch { return false; } };

  // Resolve + validate the actual repo root before scanning anything. A git
  // error here (not a work tree, unsupported flag on an old git, ...) is an
  // honest "can't scan" condition -- NOT a leak finding, so report it as such
  // and fail closed instead of misattributing it to gitleaks/trufflehog.
  try {
    cwd = execSync('git rev-parse --show-toplevel', { cwd, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' }).trim();
  } catch (e) {
    const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
    return block('Secret-scan gate: could not resolve a git repo at ' + cwd + ' — blocking fail-closed (the secret scan cannot run).\n' + o.split('\n').slice(0, 6).join('\n') + '\nFix → run the commit from inside the intended repo, or check the `cd`/`-C` prefix. Override: touch ' + OFF + '.');
  }

  // 1) gitleaks (preferred)
  if (have('gitleaks')) {
    try { execSync('gitleaks protect --staged --no-banner', { cwd, stdio: 'pipe' }); allow(); }
    catch (e) {
      const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
      // Only a genuine leak report blocks here; any other nonzero exit (git
      // version mismatch, transient tool error, ...) falls through to the
      // next layer instead of being mis-reported as "secrets found".
      if (/leaks? found|leaks? detected|"RuleID"|"Description"/i.test(o)) {
        return block('Secret-scan gate: commit blocked — gitleaks flagged staged secrets.\n' + o.split('\n').slice(0, 12).join('\n') + '\nOverride: touch ' + OFF + '.');
      }
    }
  }
  // 2) trufflehog (best-effort; only a clean finding blocks)
  if (have('trufflehog')) {
    try { execSync('trufflehog --no-update git file://' + cwd + ' --since-commit HEAD --fail --no-verification', { cwd, stdio: 'pipe' }); /* no finding */ }
    catch (e) {
      const o = ((e.stdout && e.stdout.toString()) || '');
      if (/found|verified|detector/i.test(o)) return block('Secret-scan gate: commit blocked — trufflehog flagged staged secrets.\n' + o.split('\n').slice(0, 12).join('\n') + '\nOverride: touch ' + OFF + '.');
      // else: trufflehog errored for another reason -> fall through to regex.
    }
  }
  // 3) regex fallback over the staged diff. cwd is already a validated repo
  // root at this point, so a failure here is a genuine scan failure, not a
  // missing repo -- fail closed with an honest reason rather than allow silently.
  let diff;
  try { diff = execSync('git diff --cached --unified=0', { cwd, encoding: 'utf8' }); }
  catch (e) {
    const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
    return block('Secret-scan gate: could not read the staged diff at ' + cwd + ' — blocking fail-closed (the secret scan cannot run).\n' + o.split('\n').slice(0, 6).join('\n') + '\nOverride: touch ' + OFF + '.');
  }
  if (!diff) allow(); // nothing staged
  const hits = [];
  let file = '?', line = 0;
  for (const raw of diff.split('\n')) {
    if (raw.startsWith('+++ b/')) { file = raw.slice(6); continue; }
    const hm = raw.match(/^@@ -\d+(?:,\d+)? \+(\d+)/);
    if (hm) { line = parseInt(hm[1], 10); continue; }
    if (raw.startsWith('+') && !raw.startsWith('+++')) {
      const body = raw.slice(1);
      if (isSecretLine(body)) hits.push(file + ':' + line + ' — ' + labelFor(body));
      line++;
    } else if (!raw.startsWith('-')) { line++; }
  }
  if (hits.length) return block('Secret-scan gate: commit blocked — hard-coded credential(s) in the staged diff:\n  ' + hits.slice(0, 20).join('\n  ') + '\nFix → unstage the secret, move it to an env var / secret store, then re-stage and commit. Override: touch ' + OFF + '.');
  allow();
}

// ---- WRITE-TIME -------------------------------------------------------------
if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(tool)) {
  const fp = (ti.file_path || ti.notebook_path || '') + '';
  if (/(\.example$|\.sample$|\.dist$|\.template$|\.lock$)/i.test(fp)) allow();
  let text = '';
  if (typeof ti.content === 'string') text += ti.content + '\n';
  if (typeof ti.new_string === 'string') text += ti.new_string + '\n';
  if (Array.isArray(ti.edits)) for (const e of ti.edits) if (e && typeof e.new_string === 'string') text += e.new_string + '\n';
  if (!text) allow();
  const hits = [];
  for (const l of text.split('\n')) if (isSecretLine(l)) hits.push(labelFor(l));
  if (hits.length) {
    const uniq = [...new Set(hits)];
    return block('Secret-scan gate: write blocked — looks like a hard-coded credential (' + uniq.join(', ') + ') in ' + (fp || 'this content') + '. Fix → replace the literal with an env/secret-store reference (process.env.X, import.meta.env, os.environ). Never write a credential to disk. Override: touch ' + OFF + '.');
  }
  allow();
}

allow();
