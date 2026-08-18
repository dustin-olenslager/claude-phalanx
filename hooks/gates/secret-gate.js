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
const { execSync, execFileSync } = require('child_process');
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

// The dir the `git commit` will actually run in — NOT necessarily the hook cwd.
// 2026-07-04 false block: hook cwd=/workspace (no work tree) while the command was
// `cd /workspace/depona && git commit …`; gitleaks ran `git diff --staged` outside a
// work tree, git errored ("unknown option `staged'": diff degrades to --no-index
// mode there), and the error was reported as "staged secrets". Honor the last
// `cd <dir>` before the commit and a `git -C <dir> … commit` form.
function commitDir(cmd, cwd) {
  let dir = cwd;
  const gi = cmd.search(/\bgit\b[^\n]*\bcommit\b/);
  const cdRe = /(?:^|&&|;|\|\||\n)\s*cd\s+("([^"]*)"|'([^']*)'|[^\s;&|]+)/g;
  let m;
  while ((m = cdRe.exec(cmd)) && m.index < gi) dir = m[2] || m[3] || m[1];
  const c = /\bgit\s+-C\s+("([^"]*)"|'([^']*)'|[^\s;&|]+)\s+[^\n]*\bcommit\b/.exec(cmd);
  if (c) dir = c[2] || c[3] || c[1];
  return path.isAbsolute(dir) ? dir : path.resolve(cwd, dir);
}
// Work-tree root of dir, or null when dir is not inside one (never a false "cwd").
function workTreeRoot(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'],
      { encoding: 'utf8', timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch { return null; }
}

// ---- COMMIT-TIME ------------------------------------------------------------
if (tool === 'Bash') {
  const cmd = (ti.command || '') + '';
  if (!/\bgit\b[^\n]*\bcommit\b/.test(cmd)) allow();
  const cwd = input.cwd || process.cwd();
  const repo = workTreeRoot(commitDir(cmd, cwd));
  // Fail closed but HONEST: an unresolvable repo is a resolution failure, never a
  // leak finding. (A commit that dodges resolution would dodge the scan too.)
  if (!repo) return block('Secret-scan gate: commit blocked — could not resolve the git work tree for this commit (cwd=' + cwd + '), so the staged diff was NOT scanned. This is a repo-resolution failure, not a leak finding. Fix → run the commit as `cd <repo> && git commit …` with a literal path (or from inside the repo) so the gate can scan it. Override: touch ' + OFF + '.');
  const have = (bin) => { try { execSync('command -v ' + bin, { stdio: 'ignore' }); return true; } catch { return false; } };

  // 1) gitleaks (preferred). Only a real leak verdict blocks here; a git/gitleaks
  //    error (no "leaks found"/"Finding:" in the output) falls through to the
  //    other scanners instead of masquerading as a finding.
  if (have('gitleaks')) {
    try { execSync('gitleaks protect --staged --no-banner', { cwd: repo, stdio: 'pipe' }); allow(); }
    catch (e) {
      const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
      if (/leaks found: [1-9]|(^|\n)\s*Finding:/i.test(o)) return block('Secret-scan gate: commit blocked — gitleaks flagged staged secrets.\n' + o.split('\n').slice(0, 12).join('\n') + '\nFix → unstage the secret, move it to an env var / secret store, then re-stage and commit. Override: touch ' + OFF + '.');
    }
  }
  // 2) trufflehog (best-effort; only a clean finding blocks)
  if (have('trufflehog')) {
    try { execFileSync('trufflehog', ['--no-update', 'git', 'file://' + repo, '--since-commit', 'HEAD', '--fail', '--no-verification'], { cwd: repo, stdio: 'pipe' }); /* no finding */ }
    catch (e) {
      const o = ((e.stdout && e.stdout.toString()) || '');
      if (/found|verified|detector/i.test(o)) return block('Secret-scan gate: commit blocked — trufflehog flagged staged secrets.\n' + o.split('\n').slice(0, 12).join('\n') + '\nFix → unstage the secret, move it to an env var / secret store, then re-stage and commit. Override: touch ' + OFF + '.');
      // else: trufflehog errored for another reason -> fall through to regex.
    }
  }
  // 3) regex fallback over the staged diff
  // "Nothing staged" never throws here (git exits 0 with empty stdout) -- that
  // case is handled by the `if (!diff) allow()` below. A throw means the diff
  // itself could not be read, which must fail closed, not silently allow.
  let diff;
  try { diff = execSync('git diff --cached --unified=0', { cwd: repo, encoding: 'utf8' }); }
  catch (e) {
    const o = ((e.stdout && e.stdout.toString()) || '') + ((e.stderr && e.stderr.toString()) || '');
    return block('Secret-scan gate: commit blocked — could not read the staged diff for this commit (repo=' + repo + '), so it was NOT scanned. This is a diff-read failure, not a leak finding.\n' + o.split('\n').slice(0, 12).join('\n') + '\nFix → resolve the git error above, then re-stage and commit. Override: touch ' + OFF + '.');
  }
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
