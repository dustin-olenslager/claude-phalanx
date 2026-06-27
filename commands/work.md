---
description: Start/resume the autonomous work loop. Reads PROGRESS.md (resume) then TASKS.md (next job), dispatches the orchestrator, runs until backlog empty or a real blocker.
---

Autonomous mode. Drive work without asking me to pick tasks.

## Startup sequence
1. If ./PROGRESS.md exists and contains a `RESPAWN` line or unfinished state: RESUME from it first. Read it, reconstruct where the last session stopped, clear the RESPAWN marker, continue that task before pulling a new one.
2. Read ./.claude-state.json. Missing → infer per §15 STEP 1 (empty repo→build/brainstorm; existing→ask maintain-or-optimize ONCE, write the file).
3. Read TASKS.md at the repo root (`git rev-parse --show-toplevel`). If a concrete request came WITH this invocation, seed it: append `- [ ] (req:NEW) <request>` (create TASKS.md if missing), then proceed. Only on a BARE `/work` in a repo with no request and no TASKS.md: copy the template, tell me to fill it, and stop.

## Run
4. Spawn the `orchestrator` subagent. It owns the dispatch loop (pick task → decompose → spawn workers → verify → check off → next).
5. Honor every gate (pipeline, standards, secret) and the context-budget hook. On RESPAWN: orchestrator checkpoints to PROGRESS.md and stops; tell me to re-run /work in a fresh session (or it auto-continues if the loop wrapper is running).
6. Git: full autonomy per orchestrator spec — branch per task, commit, push, open PR. Commit ONLY if a verify/test ran green this turn (the loop self-polices even when the global pipeline gate is muted). MERGE on green ONLY in repos that opted in with a `.phalanx-automerge` marker (else open a PR); then run `.phalanx-deploy` if the repo defines one. The merge-into-main gate is non-bypassable — never on red. See the orchestrator's "Merge + deploy on green" section.

## Stop conditions (report, don't spin)
- TASKS.md backlog empty → summarize what shipped, stop.
- Real blocker (missing creds, ambiguous spec, failing external dep) → write a `BLOCKED: <reason>` line to PROGRESS.md, state it in ≤3 lines, stop. (The outer run-work loop watches for BLOCKED and halts for the human.)
- Context ceiling → checkpoint + stop per hook.

Caveman comms throughout. No progress narration mid-loop — only the final report or a blocker.
