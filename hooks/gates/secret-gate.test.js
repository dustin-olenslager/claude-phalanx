"use strict";
// Standalone: `node hooks/gates/secret-gate.test.js`.
// The gate is a stdin/stdout hook, so each case spawns it and reads the verdict:
// no output = allow, a deny payload = block.
const assert = require("assert");
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const GATE = path.join(__dirname, "secret-gate.js");

function decide(tool, cwd, toolInput) {
  const payload = JSON.stringify({ tool_name: tool, cwd, tool_input: toolInput });
  const out = execFileSync(process.execPath, [GATE], { input: payload, encoding: "utf8" });
  if (!out.trim()) return { verdict: "allow", reason: "" };
  return { verdict: "block", reason: JSON.parse(out).hookSpecificOutput.permissionDecisionReason };
}
const verdict = (tool, cwd, toolInput) => decide(tool, cwd, toolInput).verdict;

const git = (repo, ...args) =>
  execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });

const repo = fs.mkdtempSync(path.join(os.tmpdir(), "secret-gate-"));
execFileSync("git", ["init", "--quiet", repo]);
git(repo, "config", "user.email", "t@t.io");
git(repo, "config", "user.name", "t");
fs.writeFileSync(path.join(repo, "ok.txt"), "clean=1\n");
git(repo, "add", "ok.txt");

// --- trigger: what RUNS, not what the command carries -----------------------

// a heredoc whose body discusses committing is data, not a commit. Before this was
// fixed the gate matched inside the body, then hard-failed because the hook cwd was
// not a work tree -- blocking a call that never touched git.
const heredoc =
  "cat > /tmp/x.ps1 <<'PSEOF'\ncd C:/repo\ngit add .\ngit commit -m \"chore: pins\"\nPSEOF\nbash /tmp/run.sh";
assert.strictEqual(verdict("Bash", "/workspace", { command: heredoc }), "allow");

// a commit dispatched to another machine has no local index to scan, so blocking it
// protects nothing
assert.strictEqual(
  verdict("Bash", "/workspace", { command: 'ssh host "cd /r && git commit -m x"' }),
  "allow"
);
assert.strictEqual(
  verdict("Bash", "/workspace", { command: "docker exec c git commit -m x" }),
  "allow"
);

// --- fail closed: a real local commit still has to resolve and scan ---------

assert.strictEqual(verdict("Bash", "/nonexistent-dir", { command: "git commit -m x" }), "block");
assert.strictEqual(verdict("Bash", repo, { command: "git commit -m x" }), "allow");
assert.strictEqual(
  verdict("Bash", "/workspace", { command: "cd " + repo + " && git commit -m x" }),
  "allow"
);

// a path the shell has not expanded yet cannot be resolved statically, so it still
// fails closed -- but the block should say WHY, since that one is fixable by the author
const varPath = decide("Bash", "/workspace", { command: "cd $D && git commit -m x" });
assert.strictEqual(varPath.verdict, "block");
assert.ok(/shell variable or substitution/.test(varPath.reason));

const litPath = decide("Bash", "/workspace", { command: "cd /nowhere-at-all && git commit -m x" });
assert.strictEqual(litPath.verdict, "block");
assert.ok(!/shell variable or substitution/.test(litPath.reason));

// a staged credential is still a hard block. Built at runtime so this file holds no
// literal that would trip the gate's own write-time layer or the repo's secret scan.
const awsKey = "AKIA" + "IOSFODNN7XJQEXTR";
fs.writeFileSync(path.join(repo, "leak.txt"), 'aws_key = "' + awsKey + '"\n');
git(repo, "add", "leak.txt");
assert.strictEqual(verdict("Bash", repo, { command: "git commit -m x" }), "block");
git(repo, "rm", "--quiet", "--cached", "leak.txt");
fs.rmSync(path.join(repo, "leak.txt"));

// --- write-time layer is untouched ------------------------------------------

const pem = "-----BEGIN RSA " + "PRIVATE KEY-----";
assert.strictEqual(verdict("Write", "/workspace", { file_path: "/tmp/k.pem", content: pem + "\nabc" }), "block");
assert.strictEqual(
  verdict("Write", "/workspace", { file_path: "/tmp/n.md", content: "how to git commit safely" }),
  "allow"
);
assert.strictEqual(verdict("Bash", "/workspace", { command: "ls -la" }), "allow");

fs.rmSync(repo, { recursive: true, force: true });
console.log("secret-gate.test.js ok");
