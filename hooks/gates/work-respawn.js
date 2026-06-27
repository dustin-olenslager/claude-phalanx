#!/usr/bin/env node
"use strict";
// Stop hook: in-session respawn driver. When Claude finishes a turn during an
// active loop, decide whether to continue. Works in Desktop/CLI/IDE alike -- no
// external process needed.
// One-shot (PHALANX_ONESHOT=1, e.g. the Telegram bot): suppressed entirely --
// the orchestrator's in-run loop drives the single seeded task to green within
// one run; no cross-turn continuation, no backlog walking.
const fs = require("fs");
const path = require("path");
const H = require("./lib/phalanx-hook.js");

const CLAUDE_DIR = __dirname;

function cont(reason) {
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
  process.exit(0);
}
function stop() { process.exit(0); }
const readInput = H.readInput;

// A supervisor (run-work.sh) relaunches fresh `claude -p` passes itself; when one
// is live, this session must just END (the supervisor continues) -- never block to
// drive the same session on, and never emit a "/clear" instruction (item 4).
const supervisorActive = H.supervisorActive;

// On a context-ceiling RESPAWN in a bare interactive session (no supervisor yet),
// hand off to a detached supervisor instead of asking a human to /clear -- it
// relaunches fresh `claude -p` passes from PROGRESS.md until the backlog is done.
function launchSupervisor(dir) {
  const sup = path.join(CLAUDE_DIR, "supervisord.sh");
  try {
    if (!fs.existsSync(sup)) return false;
    const ch = require("child_process").spawn("bash", [sup, "start", "-r", dir], {
      detached: true, stdio: "ignore", cwd: dir,
    });
    ch.unref();
    return true;
  } catch { return false; }
}

const input = readInput();
const cwd = input.cwd || process.cwd();

const ONESHOT = process.env.PHALANX_ONESHOT === "1";
if (ONESHOT) stop();
if (supervisorActive(cwd)) stop();

// Guard against infinite loops.
if (input.stop_hook_active) stop();

if (H.killSwitched(cwd, CLAUDE_DIR)) stop();

try { fs.readFileSync(path.join(cwd, "TASKS.md"), "utf8"); } catch { stop(); }
const open = H.openTaskCount(cwd);
if (open === 0) stop();

// Authoritative human-halt sentinel (item 1): control flow must NOT depend on a
// tail/slice window of append-only PROGRESS.md -- a verbose pass can push the
// BLOCKED line out of view. Honor the sentinel file first, then the (whole-file)
// PROGRESS.md scan as a detector, materializing the sentinel on first sight.
try {
  if (fs.existsSync(path.join(cwd, ".claude-runs", "BLOCKED"))) stop();
} catch {}
try {
  const p = fs.readFileSync(path.join(cwd, "PROGRESS.md"), "utf8");
  if (/BLOCKED/.test(p)) {
    try {
      fs.mkdirSync(path.join(cwd, ".claude-runs"), { recursive: true });
      const m = p.match(/.*BLOCKED.*/);
      fs.writeFileSync(path.join(cwd, ".claude-runs", "BLOCKED"), (m ? m[0] : "BLOCKED") + "\n");
    } catch {}
    stop();
  }
} catch {}

// Strike the RESPAWN marker after acting on it (item 5) so a one-shot directive
// can't re-fire on every subsequent turn. Append a STRUCK note; the next read sees
// "RESPAWN-DONE" and ignores it. Matches only an un-struck RESPAWN.
function strikeRespawn() {
  try {
    const pp = path.join(cwd, "PROGRESS.md");
    const p = fs.readFileSync(pp, "utf8");
    if (/RESPAWN(?!-DONE)/.test(p)) {
      fs.appendFileSync(pp, `\n<!-- RESPAWN-DONE ${new Date().toISOString()} -- respawn handled, marker struck -->\n`);
    }
  } catch {}
}

// Active only if the most recent RESPAWN is NOT already struck by a later DONE
// (shared reader; same standard window).
const respawn = H.respawnActive(H.readRepoFile(cwd, "PROGRESS.md"));

if (respawn) {
  // Auto-escalate: launch a detached supervisor to carry the loop to done with no
  // human /clear. (No supervisor is active -- supervisorActive() stopped us above.)
  // Fall back to the manual nudge only if the supervisor can't be launched.
  if (launchSupervisor(cwd)) { strikeRespawn(); stop(); }
  // Manual nudge: gate on stop_hook_active so it isn't re-emitted every turn when
  // the launch keeps failing (item 5). stop_hook_active is already handled above,
  // so reaching here means this is the first emission -- strike to prevent re-fire.
  strikeRespawn();
  cont(
    `Context ceiling was hit. You've checkpointed to PROGRESS.md. Run /clear to reset context, ` +
    `then resume the /work loop from PROGRESS.md. ${open} task(s) remain. Do not summarize -- just continue.`
  );
}

cont(
  `Autonomous loop still active -- ${open} open task(s) remain in TASKS.md. ` +
  `Finish ONLY the task you are on and its verify; do not start another backlog item mid-turn. ` +
  `When it is green and checked off, pull the next. Do not stop to ask unless genuinely BLOCKED ` +
  `(then write BLOCKED: <reason> to PROGRESS.md). No end-of-turn summary -- keep working.`
);
