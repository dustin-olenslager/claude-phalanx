#!/usr/bin/env node
/**
 * stale-main-gate.js -- PreToolUse(Bash): never branch from a stale main.
 *
 * repo-fresh.sh WARNS at SessionStart; this is the mechanical half. When a command
 * creates a branch or worktree (`git checkout -b`, `git switch -c`, `git worktree add`)
 * and the local main is BEHIND origin/main, the call is denied with the exact fix,
 * unless the command explicitly bases itself on `origin/<main>`. Warn-only under
 * PHALANX_WARN=1. Inert when: not a git repo, no origin/<main> ref (never fetched),
 * `.phalanx-no-fresh` in the repo, or PHALANX_NO_FRESH=1.
 *
 * Does NOT fetch (speed); it trusts the origin/<main> ref repo-fresh refreshed at
 * session start. It cannot see commits pushed since then -- that window is small and
 * the alternative (a network call on every Bash) is not.
 */
const cp = require("child_process");
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");

const input = H.readInput();
if (input.tool_name !== "Bash") process.exit(0);
const cmd = (input.tool_input && input.tool_input.command) || "";
const CREATE = /\bgit\b[^|;&\n]*\b(checkout\s+(-b|-B)|switch\s+(-c|-C)|worktree\s+add)\b/;
if (!CREATE.test(cmd)) process.exit(0);
if (process.env.PHALANX_NO_FRESH === "1") process.exit(0);

const cwd = H.effectiveCwd(cmd, input.cwd || process.cwd());
const sh = (args) => {
  try { return cp.execFileSync("git", args, { cwd, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] }).toString().trim(); }
  catch { return null; }
};
const top = sh(["rev-parse", "--path-format=absolute", "--git-common-dir"]);
if (!top) process.exit(0);
const root = path.dirname(top);
if (fs.existsSync(path.join(root, ".phalanx-no-fresh"))) process.exit(0);

let main = (sh(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) || "").replace(/^origin\//, "");
if (!main) main = sh(["show-ref", "-q", "refs/heads/main"]) !== null ? "main" : "master";
if (sh(["show-ref", "-q", `refs/remotes/origin/${main}`]) === null) process.exit(0);
if (new RegExp(`\\borigin/${main.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(cmd)) process.exit(0);

const behind = parseInt(sh(["rev-list", "--count", `${main}..origin/${main}`]) || "0", 10);
if (!behind) process.exit(0);

const reason =
  `stale-main-gate: local ${main} is ${behind} commit(s) behind origin/${main} -- branching from it ` +
  `reproduces old code. Fix: git checkout ${main} && git pull --ff-only origin ${main}   ` +
  `(or base the new branch on origin/${main} explicitly). Per-repo opt-out: touch .phalanx-no-fresh`;
if (process.env.PHALANX_WARN === "1") H.decide("PreToolUse", "allow", "WARN " + reason);
H.decide("PreToolUse", "deny", reason);
