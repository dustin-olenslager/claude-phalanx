# PROGRESS — DONE

All 4 harness optimizations shipped on branch `task/harness-4opts` (NOT pushed/merged).

- d1a482b — Item 3 gates-as-teachers (remediation recipes from policy)
- 6cfaaac — Item 2 risk-routed pipeline (policy riskTierRules; `.risk-routing-on`)
- 77f047b — Item 4 opt-in GC/cleanup loop (`scripts/gc-scan.sh`; `.gc-on`)
- 5bad9bf — Item 5 opt-in first-class evidence (`scripts/evidence.sh`; `.evidence-on`)

Verify: clean-room `install.sh` self-test 50/50 PASS, 0 FAIL. All flags default OFF
== existing installs byte-identical after `git pull && install.sh`. sections.md untouched.
No RESPAWN/BLOCKED — backlog drained (TASKS.md all [x]).

## 2026-06-29 checkpoint — rule 5e (raw main-push gate) NOT YET DONE
WHY: operator-approved. Gap: a loop agent ran an ungated raw push-to-main + manual prod deploy
on pushd. The loop-integrity gate only catches the merge-subcommand, and is inert in repos with
no TASKS.md (e.g. pushd). v1.7.5 (flock single-instance) already shipped+live; THIS is the leftover.
DO: in hooks/gates/loop-integrity-gate.js, right AFTER `const cwd = ...` and BEFORE the
`if (!tasksTxt) allow()` inert early-out, add rule 5e:
  - loopAgent = env PHALANX_SUPERVISOR==='1' || PHALANX_ONESHOT==='1'
  - if loopAgent && tool Bash && H.PUSH_MAIN matches cmd && NOT H.GIT_MERGE matches cmd:
      tgt = a `-C <path>` in the cmd, else cwd
      if NOT H.autoMergeEnabled(tgt): return out deny "5e: loop agent landing <tgt> to main needs
      the .phalanx-automerge opt-in; open a PR instead. Non-bypassable."
  (matchers PUSH_MAIN/GIT_MERGE + autoMergeEnabled/repoRoot already exist in lib/phalanx-hook.js)
  The exact drafted code is in the assistant transcript for this turn.
KNOWN REFINEMENT while doing it: PUSH_MAIN/GIT_MERGE over-match literal text in echo/heredoc bodies
(this very checkpoint write got 5c-denied). Tighten the matchers to ignore quoted/heredoc content,
or anchor to a real command position.
TEST: install.sh sim — fire the gate with PHALANX_SUPERVISOR=1 + a Bash cmd that lands main in a
repo with NO marker => deny; WITH the marker => allow; and with NO loopAgent env => allow.
SHIP: node --check + verify.sh + self-test green -> PR -> merge -> tag v1.7.6 -> cp live to /config/.claude/.
NOTE: edit was 5a-blocked until claude-phalanx/TASKS.md seeded (now has the (req:NEW) 5e line) — check
it off when 5e ships. claude-phalanx is BLOCKED so the watcher skips it; a human / fresh /work resumes.

## 2026-06-29 checkpoint B — loop-access feature (uncommitted, secret-clean)
Operator ask: "Phalanx must have access to everything I do; land it + deploy; NO secrets to the public repo."
STAGED (dirty on main, 4 files only): README.md, install.sh, scripts/run-work.sh, .loop-access.env.example.
- Feature: $CLAUDE_DIR/.loop-access.env (0600) → ACCESS_KV → injected via `env` prefix onto the
  two `claude -p` invocations only. Generalizes .headless-env/.loop-git-env. bash -n + functional test green.
- Already hot-patched live to /config/.claude/run-work.sh.
- This-instance creds wired in /config/.claude/.loop-access.env (OUTSIDE repo): GH, ssh hive,
  CLOUDFLARE_API_TOKEN (`phalanx-loop`, Tunnel:Edit+DNS:Edit+CachePurge:Purge, verified active), TUNNEL_TOKEN.
SECRET SAFETY: real .loop-access.env / .loop-git-env / .headless-env all live under /config/.claude, NOT the
  repo. .gitignore covers .claude-runs/ (untracked, 0 files). Run leak-scan before any publish anyway.
FINISH (fresh ctx): leak-scan → install.sh self-test green → branch+commit the 4 files → land to main
  (.phalanx-automerge ABSENT; operator-authorized) → publish → reinstall for BOTH CLAUDE_DIRs
  (/config/.claude done-ish; /home/cc/.claude needs it).
SCOPE DECISION for operator: "everything" may also include task/harness-4opts (unmerged) + rule 5e (above).
  Confirm whether to publish those too, or only loop-access. Repo currently BLOCKED — clear .claude-runs/BLOCKED to resume.
ACCESS PARITY TODO: tools/MCP/ssh/docker are inherited; only secrets need wiring (GH+CF+tunnel done).
  Still verify: list MCP servers; flag interactively-authed ones absent in headless (chrome/gmail/claude.ai).

<!-- RESPAWN 2026-06-29T14:59:27.116Z ctx~394% -- checkpoint state above, STOP, resume fresh -->

<!-- RESPAWN-DONE 2026-06-29T18:21:44.281Z -- respawn handled, marker struck -->

## 2026-06-29 rule 5e — DONE
Shipped PR #15 (task/rule-5e). Implements:
- Rule 5e in loop-integrity-gate.js: loop agents blocked from raw push to main without .phalanx-automerge.
- stripQuotedContent() in lib/phalanx-hook.js: strips heredoc/quoted content before PUSH_MAIN test (fixes 5c false-positive on checkpoint writes).
Verify: node --check OK + install.sh 0 new failures. Generalized loop access (7486d10) checked off as already shipped. Backlog empty.
