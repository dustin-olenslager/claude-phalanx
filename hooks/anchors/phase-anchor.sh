#!/usr/bin/env bash
# SessionStart: read <project>/.claude-state.json and inject ONLY the active
# mode/phase (CLAUDE.md §15). Token economy: the model loads one phase's team,
# not the whole org. No state file -> instruct STEP 1 inference.
node -e '
const fs = require("fs");
const PH = {
  build:   ["brainstorm","research","architecture","plan","design","implement","review","security","verify","commit","memory"],
  maintain:["comprehend","characterize","plan-change","implement","review","security","verify","commit","memory"],
  optimize:["baseline","profile","hypothesize","implement","benchmark","verify","commit","memory"]
};
let s = null;
try { s = JSON.parse(fs.readFileSync(process.cwd() + "/.claude-state.json", "utf8")); } catch {}
let ctx;
if (!s || !s.mode) {
  ctx = "PHALANX ACTIVE but NO .claude-state.json in this project (cwd=" + process.cwd() + "). STEP 1: infer mode. Empty/near-empty repo -> mode=build, phase=brainstorm. Existing code+git history -> ASK ONE question (Maintain=change existing, or Optimize=perf), then write .claude-state.json {mode,phase,flags}. Phases: build[" + PH.build.join(",") + "]; maintain[" + PH.maintain.join(",") + "]; optimize[" + PH.optimize.join(",") + "]. Load ONLY the active phase skill (STEP 2). Optimize REQUIRES observability (§12) to already exist.";
} else {
  const seq = PH[s.mode] || [];
  const i = seq.indexOf(s.phase);
  const next = (i >= 0 && i < seq.length - 1) ? seq[i + 1] : "(end-of-mode)";
  ctx = "PHALANX (CLAUDE.md §15) — mode=" + s.mode + " phase=" + (s.phase || "?") + " next=" + next + ". Load ONLY this phase team/skill per the STEP 2 map; do NOT pull guidance for other phases (that is the token lever). Advance only when this phase exit-gate is met. Overrides: /mode build|maintain|optimize, /phase <id>, /phase next. Always-on regardless of phase: caveman (§0), Clean Architecture (§3/§14), observability (§12), adversarial review (§16).";
}
process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx } }));
'
