#!/usr/bin/env node
/*
 * PreToolUse gate — secret scan (CLAUDE.md §13 security phase).
 * Two layers:
 *  1. WRITE-TIME (Edit/Write/MultiEdit): scan the content about to hit disk and
 *     block a hard-coded credential before it's even written.
 *  2. COMMIT-TIME (Bash `git commit`): scan the STAGED diff with gitleaks (then
 *     trufflehog) if installed, else a regex fallback; deny with file:line.
 * Hard-block by default; PHALANX_WARN=1 for warn-only.
 * Off switch: <CLAUDE_DIR>/.secret-scan-off. __dirname === CLAUDE_DIR.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const HERE = __dirname;

function readStdin() { try { return fs.readFileSync(0, 'utf8'); } catch { return ''; } }
function allow() { process.exit(0); }
function out(decision, reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: decision, permissionDecisionReason: reason },
  }));
  process.exit(0);
}

const OFF = path.join(HERE, '.secret-scan-off');
const WARN_ONLY = process.env.PHALANX_WARN === '1';
const block = (msg) => (WARN_ONLY ? out('allow', '⚠ ' + msg) : out('deny', msg));

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

// ---- COMMIT-TIME ------------------------------------------------------------
if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (!/\bgit\b[^\n]*\bcommit\b/.test(cmd)) allow();
  const cwd = input.cwd || process.cwd();
  const have = (bin) => { try { execSync('command -v ' + bin, { stdio: 'ignore' }); return true; } catch { return false; } };

  // 1) gitleaks (preferred)
  if (have('gitleaks')) {
    try { execSync('gitleaks protect --staged --no-banner', { cwd, stdio: 'pipe' }); allow(); }
    catch (e) {
      const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
      return block('Secret-scan gate: commit blocked — gitleaks flagged staged secrets.\n' + o.split('\n').slice(0, 12).join('\n') + '\nOverride: touch ' + OFF + '.');
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
  // 3) regex fallback over the staged diff
  let diff;
  try { diff = execSync('git diff --cached --unified=0', { cwd, encoding: 'utf8' }); }
  catch { allow(); } // not a git repo / nothing staged
  if (!diff) allow();
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
  if (hits.length) return block('Secret-scan gate: commit blocked — hard-coded credential(s) in the staged diff:\n  ' + hits.slice(0, 20).join('\n  ') + '\nMove to env/secret store. Override: touch ' + OFF + '.');
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
    return block('Secret-scan gate: write blocked — looks like a hard-coded credential (' + uniq.join(', ') + ') in ' + (fp || 'this content') + '. Use an env var / secret store. Override: touch ' + OFF + '.');
  }
  allow();
}

allow();
