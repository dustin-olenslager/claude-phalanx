# Completed Features

The shipped log. One entry per feature, newest first. Read this before proposing work — it is the
cheapest way to avoid rebuilding something that already exists.

Add an entry when a feature is tested and signed off, at the same time you move its folder into
`<area>/completed/`.

## Entry format

```markdown
### <Feature name> — YYYY-MM-DD
- **What shipped:** one or two sentences, in terms of what a user or caller can now do.
- **Area:** `<area>`
- **Archived plan:** `<area>/completed/<feature>/<renamed-file>.md`
- **Notable decisions:** anything that constrains future work; link the ADR in `architecture.md`.
- **Known gaps:** what was deliberately left out, so the next person does not read it as a bug.
```

---

### EXAMPLE — Paginated records list — 2026-01-15
- **What shipped:** the records table loads a page at a time with server-side filtering and sort,
  replacing the load-everything fetch.
- **Area:** `ui`
- **Archived plan:** `ui/completed/records-list/server-side-pagination.md`
- **Notable decisions:** cursor-based paging over offset — see ADR-0004 in `architecture.md`.
- **Known gaps:** no saved filter presets; deferred, tracked in `in-progress.md` under Parked.

_Delete the example entry once the first real feature ships._

---

<!-- New entries go directly below this line, newest first. -->

### Drift audit checks tracked-ness, not just existence — 2026-09-21
- **What shipped:** `scripts/plan-contract-drift.sh` now fails a repo whose plan docs or agent kit
  exist on disk but were never committed, and names the file class that is missing — a hard `KIT`
  column (≥1 tracked `.claude/rules/` module **and** tracked `scripts/sync-agents.sh`),
  `UNTRACKED` / `MISSING` states for `AGENTS` and `MIRROR`, plus non-fatal `soft:` notes for the gaps
  that have legitimate exceptions. Locked in by `scripts/test-plan-contract-drift.sh` (7 cases, runs
  inside `scripts/verify.sh`).
- **Area:** `shared-plan-contract`
- **Archived plan:** none — one PR, the follow-up to "This repo's own Panoply kit is versioned in git"
  below, which is the gap that motivated it.
- **Notable decisions:** three findings are deliberately **soft** — reported, never failing:
  `queue-untracked` (PANOPLY §1a calls `in-progress.md` a *generated view* that is never committed;
  frame-forge honours that literally, 12 repos commit it anyway), `settings-untracked`, and
  `gates-not-wired` / `no-ci-workflow` (levio + plexo wire the gates into `ci.yml` rather than a
  `verify.yml`, and fylo has a *recorded operator decision* not to wire them at all). A hard rule
  that a documented exception already violates is a rule the whole fleet learns to ignore.
- **Known gaps:** the audit reads each repo's **current checkout** (index + HEAD), so a repo parked on
  a feature branch is audited as that branch, not as its default. Fleet state at landing: 13/13
  conform; soft notes on claude-phalanx / fonto / frame-forge / fylo (gates not wired) and pushd
  (`settings.json` untracked). claude-phalanx's own note cleared later the same day when its `contract`
  CI job landed; fonto / frame-forge / fylo and pushd still carry theirs. Still advisory — nothing
  gates a merge on it.

### This repo's own Panoply kit is versioned in git — 2026-09-21
- **What shipped:** the **43 kit files** claude-phalanx had been running on *untracked* are now
  committed, so a fresh clone gets the governance every sibling repo already has: `AGENTS.md`,
  `CLAUDE.md`, `GEMINI.md`, `CONVENTIONS.md`; `.claude/rules/` ×9, `.claude/agents/` ×6,
  `.claude/commands/` ×3, `.claude/settings.json` (the Claude permission gate) +
  `settings.local.json.example`; the generated mirrors (`.cursor/rules/` ×10, `.clinerules/`,
  `.windsurf/`, `.github/copilot-instructions.md`); and the vendored kit scripts
  (`sync-agents.sh`, `check-docs.sh`, `check-expert-review.sh`, `init-repo-protection.sh`,
  `templates/ci-verify.yml`, `templates/pre-commit`).
- **Area:** `shared-plan-contract`
- **Archived plan:** none — surfaced by the 2026-09-20 fleet repair arc and landed as one PR.
- **Notable decisions:** `check-expert-review.sh` was fixed on the way in, because committing it
  unmodified would have reddened the `static` job: it assigned a `reason` variable it never read
  (SC2034, warning severity — exactly what `ci.yml` gates on; the helper already prints each missing
  item, so nothing is lost), and its closing `[ "$fail" -eq 0 ] && echo OK` left the real exit code
  to `set -e` with `exit "$fail"` unreachable. Both are explicit now.
  **Correction, same day, verified against `/workspace/panoply` @ `c1216b7`:** the claim first recorded
  here — that upstream needed these two fixes backported or the next `adapt` would reintroduce them —
  was **backwards**. Upstream's `check-expert-review.sh` is *newer* than the copy this repo had been
  running: it already prints `$reason` in its failure message (no dead variable, no SC2034), carries a
  documented `SC2126` disable for the `grep | wc -l` count, makes persona sign-offs **opt-in** via
  `EXPERT_REVIEW_REQUIRE_SIGNOFFS=1` instead of arming whenever `gh` happens to be authenticated, and
  accepts any checklist item under `docs/claude/**` rather than demanding a separate `checklist.md`
  with an *unchecked* item. So the divergence runs the other way — this repo's vendored copy was
  stale, and the next `adapt` **fixes** it rather than regressing it. Reconciling the vendored kit is
  queued in `in-progress.md` row 1.
- **Known gaps:** *both follow-ups shipped later the same day (2026-09-21)* — `ci.yml` now runs a
  `contract` job (`sync-agents.sh --check` on every PR/push, `check-docs.sh --since <PR base>` on
  PRs), and `plan-contract-drift.sh` now audits tracked-ness with its own test suite, so this class of
  gap cannot recur silently. Still open: nothing in `ci.yml` is **required** — the repo is public with
  no branch protection and no rulesets, so all three jobs are report-only (an operator decision;
  protection *is* available on the free plan for a public repo, unlike the private
  joeybuilt-official repos). `check-expert-review.sh` is still wired nowhere in this repo — and per the
  correction above, the vendored copy is **behind upstream**, as are `sync-agents.sh`,
  `templates/ci-verify.yml` and `templates/pre-commit`; `scripts/check-plan-home.sh` is missing here
  entirely. Queued as `in-progress.md` row 1.

### One shared plan-doc contract across harnesses — 2026-09-17
- **What shipped:** both OpenCode and Claude Code now load `/workspace/PANOPLY-OPTIMIZATION.md` as
  the single canonical plan-home contract, and `scripts/plan-contract-drift.sh` audits every repo in
  the §2 map for missing/untracked plan docs — read-only, advisory, exit 1 on drift.
- **Area:** `shared-plan-contract`
- **Archived plan:** `shared-plan-contract/plan.md`
- **Notable decisions:** OpenCode loads the contract via its `instructions` field (config reloads
  only on restart); Claude via a `core.md` section (not the managed Phalanx block, which
  `install.sh` overwrites). The script is advisory, not a CI gate yet.
- **Known gaps:** the 14-repo baseline shows 3 drift classes unfixed (6 repos with untracked
  `docs/claude/`; fylo/levio/nexalog broken `AGENTS.md`; pushd missing MIRROR block). Repair is a
  follow-up, deliberately not done this pass (some repos have active worktrees).

### Phalanx config layer ported to opencode — 2026-09-17
- **What shipped:** an opencode session in this workspace now has Phalanx's focused subagents
  (`implementer`, `orchestrator`, `researcher`, `verifier`), its five review personas
  (`backend-architect`, `code-reviewer`, `cto-review`, `security-engineer`, `software-architect`),
  and three commands (`/work`, `/work-loop`, `/assess-stack`) available globally — the same working
  discipline the Claude Code kit provides, with no per-repo re-typing.
- **Area:** `opencode-port`
- **Archived plan:** `opencode-port/plan.md`
- **Notable decisions:** the 14 Phalanx `skills/*` were already auto-loaded by opencode from
  `/config/.claude/skills/`, so only agents + personas + commands needed porting. Opencode loads
  config once at startup — new agents/commands require a restart. `audit-claude-setup` and
  `adapt-claude-setup` were deliberately NOT ported: they audit Claude Code's own config tree.
- **Known gaps:** `core/`, `adapters/`, and the `hooks/` gate+anchor scripts are not ported — the
  Claude Code hook protocol does not map 1:1 to opencode plugin hooks. Candidate for a follow-up.
