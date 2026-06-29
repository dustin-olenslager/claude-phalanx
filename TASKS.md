# TASKS

Four additive harness optimizations (Code Factory + OpenAI harness-engineering).
Unifying primitive: ONE versioned `policy/risk-policy.json`; gates READ it.
Hard constraint: `git pull && install.sh` = IDENTICAL behavior for existing
installs unless they opt in. New behavior ships behind its own flag, safe default.
Do NOT edit `claude-md/sections.md`. No push/deploy without operator go.

- [x] (req:NEW) Item 3 — Gates as teachers: each gate block ALSO emits a concrete
      remediation recipe (what failed + the fix). Pure addition; must NOT change
      WHETHER any gate fires. Seeds the policy file (`remediation`). Flag: always-on
      (text-only, no decision change).
- [x] (req:NEW) Item 2 — Risk-routed pipeline: classifier reads `riskTierRules` +
      `mergePolicy` from the policy contract (gates READ it, never hardcoded). HIGH →
      full gate depth, LOW → fast path. Default policy reproduces current gating
      exactly; routing opt-in via `.risk-routing-on`. Fail-safe: missing/bad policy → HIGH.
- [x] (req:NEW) Item 4 — Cleanup/GC loop: opt-in maintain scan for drift + stale docs,
      opens fix-up PRs, updates quality grades. Flag `.gc-on`, default off. NEVER a hard
      merge gate. Standalone scan (not an inline §15 phase — avoids the phase-list door).
- [x] (req:NEW) Item 5 — First-class evidence: per-worktree boot + committed
      test/browser evidence tied to head SHA. Flag `.evidence-on`, default off. SOFT gate
      only — must NOT become required for `verify` to pass (honor graceful degradation).

Order: 3 → 2 → 4 → 5. Each: `node --check` new gates + run `install.sh` verify
sims green. Commit on this branch ONLY if sims ran green this turn.

- [x] (req:NEW) Fix context-budget false ceiling — `hooks/gates/context-budget.js` used a
      hardcoded 200k window + raw transcript `bytes/3.5` (counts the fixed system prompt +
      CLAUDE.md dump), reading 63%→200% vs the real ~17% gauge, stampeding premature
      checkpoint/handoff. Fix: prefer the REAL usage signal (last transcript `usage` line);
      env/derived window (`PHALANX_CTX_WINDOW`, default ~1M); byte estimate as fallback only.
      Stays PostToolUse advisory (never blocks); keeps supervisor + one-shot behavior.
      Extend `install.sh` sim: a normal-size transcript must NOT trip the ceiling.

- [x] (req:NEW) No-babysit auto-handoff: (1) headless auth — `run-work.sh` sources
      `$CLAUDE_DIR/.headless-env` (CLAUDE_CODE_OAUTH_TOKEN) so supervised `claude -p`
      passes don't 401; (2) on-trip auto-escalate — `work-respawn.js` launches a
      detached supervisor on a ceiling RESPAWN instead of nagging a human to /clear;
      (3) proactive watch cron + repo registry. Verify: `node --check` + install
      self-test green (new sim `respawn:auto-escalate`).

## Backlog hardening (from Herald hand-off §5)
- [x] (req:NEW) §5.3 install-guards: don't clobber a pre-existing global core.hooksPath; PHALANX_FORCE_GUARDS stash+restore; PHALANX_NO_GUARDS honored
- [x] (req:NEW) §5.2 unify TASKS/PROGRESS parsing into one tasks-state reader (lib js + scripts bash); refactor gates to pure decide() shells

- [x] (req:NEW) Add loop-integrity rule 5e: block a loop agent raw `git push` to main unless the target repo has .phalanx-automerge opt-in. — shipped PR #15, awaiting human merge
- [x] (req:NEW) Generalized loop access: $CLAUDE_DIR/.loop-access.env (0600) sourced onto the claude-exec env in run-work.sh so a user can wire arbitrary creds (Cloudflare/etc); ship .example + gitignore + README + install chmod. MCP/browser/e2e/SSH already inherited. — already shipped as commit 7486d10

- [x] (req:NEW) notify /tmp isolation — case-guard in scripts/notify.sh so a repo under /tmp logs locally but never hits a real sink; scripts/test-notify-isolation.sh wired into verify.sh; chmod +x notify.sh (run-work.sh:114 skips non-exec copy → guard never ran). Hot-patch live copies + Herald stray-topic cleanup deferred (external/creds, separate op). — PR pending

- [x] (req:NEW) notify hardening: run-work.sh invoke `bash "$NOTIFY"` + `[ -f ]` (drop exec-bit dep); notify.sh realpath + /private/tmp + trailing-slash TMPDIR in the /tmp guard; +2 test cases. — done
