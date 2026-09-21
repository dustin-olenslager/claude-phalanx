---
description: Check whether CLAUDE.md and the .claude rules still match this codebase — stale commands, dead paths, contradicted rules, missing modules, layer-map drift — and output a prioritized fix list.
argument-hint: "[--fix to apply the fixes after showing the list] [--since <git-ref> to scope drift detection]"
---

# Audit this Claude setup against reality

Configuration rots. Scripts get renamed, directories move, a database or a UI shows up months after
setup, and the rules file keeps asserting the old world with total confidence. A stale rule is read
exactly as confidently as a true one — that is what makes it expensive.

**Default mode is read-only.** Investigate, then output a prioritized fix list and stop. Apply changes
only if `--fix` was passed, or after the user asks for specific items by number. Even with `--fix`,
touch configuration only: `CLAUDE.md`, `.claude/**`, `docs/claude/**`. Never application source.

If `--since <ref>` is given, use `git diff --name-status <ref>..HEAD` to focus on what moved; otherwise
audit the whole tree.

---

## Check 1 — Do the referenced commands still exist?

Extract every command string from `CLAUDE.md` and `.claude/rules/*.md` (backticked commands, anything
after "run", anything in a fenced block). For each, confirm it exists in the project's current script
or task table (`package.json` scripts, `Makefile`, `Justfile`, `Taskfile.yml`, `pyproject.toml`,
`mix.exs`, cargo aliases). Classify each:

- **Gone** — the script no longer exists. Highest severity: the model will run it, get an error, and
  improvise a substitute. Find the likely successor by name similarity and propose it.
- **Renamed** — a script with a different name now does the job. Propose the rename.
- **Wrong scoping** — the command is right but the workspace/filter flag no longer matches the current
  workspace layout.
- **Package manager drift** — the rules say one package manager, the lockfile now says another.
  The lockfile wins.

Also check the reverse direction: a script that clearly belongs in the rules but is absent from them
(a new `typecheck`, `lint:fix`, `check:*` gate, or migration script).

## Check 2 — Do the referenced paths still exist?

Every file and directory path named in the config must exist on disk. Flag:

- Dead paths — schema file moved, `src/` became `app/`, a rules file references a deleted module.
- **Orphaned `@` imports** in `CLAUDE.md` pointing at rules files that no longer exist. The guidance
  silently disappears; nothing errors.
- **Un-imported rules files** — a file in `.claude/rules/` that no `@` line imports is dead weight
  that the user believes is active.
- Agents in `.claude/agents/` referencing tools, paths, or stack elements that no longer exist.
- Directory-structure sections in `CLAUDE.md` that no longer match the real tree. Compare against an
  actual listing, two levels deep, and diff it.

## Check 3 — Do any rules contradict the actual codebase?

This is the highest-value check and the one only a reading agent can do. Sample real code and compare
against what the rules assert. Look for:

- **Convention claims that lost the vote.** The rules say named exports / a file-naming scheme / an
  import alias; sample at least 20 current source files and count. If the codebase has moved, report
  the actual ratio and ask which direction to fix — the rule may be aspirational and worth keeping,
  or it may be a fossil. Do not silently rewrite the rule.
- **Layering claims.** The rules say all API calls go through a wrapper, or no raw SQL in handlers, or
  all DB access goes through one layer. Grep for direct violations and report counts with example
  paths. A rule violated in fifty places is not being enforced by anyone.
- **Test-location claims.** The rules describe where tests live; check where they actually live now.
- **CI claims.** The rules say CI enforces a gate — open the CI config and confirm that job still
  exists and still runs on the relevant events. A rule citing a deleted CI job is a bluff, and models
  and humans both eventually notice.
- **Forbidden-command claims.** The rules forbid a destructive command; confirm the command still
  exists in that form, and that the safe alternative they name still exists too.
- **Default branch.** Compare the rules' branch name to `origin/HEAD`.
- **Stack facts.** Frameworks, runtime version, and ORM named in the rules versus current
  dependencies and version pins.

For each contradiction report: the rule (file + line), the evidence against it, and the two options —
update the rule, or fix the code — with a recommendation.

## Check 4 — Is the docs queue stale?

- `docs/claude/in-progress.md`: are the listed items still in progress? Cross-check each against
  recent git history and against `completed`/archive folders. An item whose work merged months ago
  should have moved. Report each stale entry with the commit or PR that appears to have shipped it.
- Plan documents whose feature has shipped but which were never archived to the area's `completed/`
  folder — the archival step that always gets skipped in the excitement of shipping.
- Docs referencing files, routes, or components that no longer exist.
- Area folders that are empty, and active work with no area folder at all.
- The completed log not mentioning anything from the last several months, which usually means the
  whole lifecycle has quietly stopped being used — worth saying out loud rather than patching.
- **Worklog currency.** Take the newest dated line in the worklog (`worklog.md`, or the `CHANGELOG`
  `[Unreleased]` section if that is the target), then run
  `git log --no-merges --since=<that date> --name-only` and list commits that touched
  source/config/schema/shipped-docs but added no worklog line in the same commit. Each is a
  same-change-contract miss — report the SHAs. Typo/format-only commits are exempt (they earn no line).
- **Roadmap currency** — three cross-file consistency checks, all drift-to-report (never a judgment call):
  (a) every `roadmap.md` **Now** initiative has a live `in-progress.md` row or a `completed-features.md`
  entry dated after it entered Now — otherwise it is stale;
  (b) every active queue row and every recent completed entry rolls up to exactly one initiative —
  surface orphans (a row with no `roadmap.md` initiative);
  (c) no contradiction: nothing in **Shipped** still has open queue rows, and nothing fully shipped is
  still sitting in **Now**. Report the drift and the single reconciling edit.
  Severity mapping: stale roadmap band / lagging worklog = **P1**; orphan queue row = **P2**.
- **Shipped-but-unlogged — the log lags reality without being fully dead.** The bullet above catches a
  lifecycle that fully stopped; this catches the subtler, more common case where features kept
  shipping but the log fell behind. Diff work merged since the newest `completed-features.md` entry
  (`--since <ref>` if given) against the completed log and `in-progress.md`, and flag each gap: a
  feature whose commits merged but has no completed-log entry, or that still sits in `in-progress.md`
  marked active — name the merging commit/PR for each. Also flag an active `in-progress.md` row or
  plan item carrying no `Next step`/handoff. This is the after-the-fact backstop for `documentation.md`
  ("When to write" → handoff-on-pause and "shipped-but-unlogged counts as not done"); a log that lags
  reality is read as confidently as a true one.
- **Exempt from all of the above: `docs/claude/reports/`** — the append-only dated archive of
  command-generated reports (`/assess-stack --save` output). Old reports referencing since-removed
  elements are history serving trend comparison, not staleness; never flag, archive, or prune them.

## Check 5 — Has the stack outgrown the rules?

Re-run the detection from `/adapt-claude-setup` Phase 1 and diff it against which modules are actually
present in the config. Flag every stack element that has **no corresponding rules module**:

- A database, ORM, or migrations directory added since setup, with no database rules module — the
  most dangerous gap, because migration safety rules are exactly the ones whose absence is expensive.
- A UI added since setup, with no frontend or design-system module.
- An HTTP/RPC surface added since setup, with no API rules module.
- An LLM SDK added since setup, with no AI module.
- The repo became a monorepo (workspaces added) and commands in the rules are still unscoped.
- A CI provider added since setup, with no rules describing what it gates.
- Conversely: **modules whose subject is gone.** Database rules with no database left, UI rules in a
  service that dropped its frontend. Propose deletion, with the evidence.

Also check the harness config itself: `.claude/settings.json` deny entries that no longer match any
real command (harmless), and destructive commands the current stack allows that the deny list never
learned about (not harmless) — a new ORM's schema-push command, a new deploy CLI.

- **AGENTS.md present and bridged.** `AGENTS.md` exists at the repo root and `CLAUDE.md` imports it
  (`@AGENTS.md`). If absent → **P0**: the entire non-Claude onboarding path is missing — every tool
  other than Claude has no front door.
- **Deny-list ↔ guardrails sync.** Compare the destructive-command categories in `.claude/settings.json`
  `deny` (force-push, `db:push`/`reset`/`drop` and ORM equivalents, `curl | sh`, publish/deploy,
  secret reads) against the `MUST NOT` list in the `AGENTS.md` `MIRROR` block. A deny entry with no
  corresponding cross-tool `MUST NOT` (e.g. Check 5 added a new ORM's push command to the deny list
  but the guardrails never learned it) → **P1**: the Claude gate and the cross-tool doctrine have
  diverged, and `sync-agents.sh` will propagate the stale block to every mirror. Fix = add the line to
  `AGENTS.md` and re-run `sh scripts/sync-agents.sh`.

## Check 6 — Has the layer map drifted?

`clean-architecture.md` maps four layers to directories (`{{DOMAIN_DIR}}`, `{{USECASE_DIR}}`,
`{{ADAPTER_DIR}}`, `{{INFRA_DIR}}` as filled at adapt time). Audit the map against the code, read-only:

- **The four mapped directories still exist.** A renamed or deleted layer directory makes every
  import rule in that file point at nothing — same severity as a dead `@` import.
- **Sample imports across the boundaries.** Read the import blocks of files in the mapped domain and
  use-case directories (sample at least 20 per layer, or all if fewer) and count inward-pointing
  violations: domain files importing use-case/adapter/infra modules or any framework/ORM/HTTP/SDK
  package; use-case files importing adapter/infra modules or those packages. Type-only and decorator
  imports count — they still bind the layer to a vendor. Report the count per boundary with example
  file paths, not just a verdict. Zero is the only passing score, but a trend matters too: if a
  previous audit reported a count, say which direction it moved.
- **Is the boundary automated yet?** Checklist item 1 in `clean-architecture.md` says to add an
  import-boundary lint rule or architecture test once the map is filled. Look for one (import-boundary
  lint plugins, dependency-graph linters, architecture-test libraries) in the lint config and CI. If
  none exists, flag it: every violation you counted above is a review argument that a lint rule would
  have made a CI failure.
- **Is the gate wired, not just installed?** A dependency-boundary linter present in the dev
  dependencies but absent from the pre-commit gate and required CI is decoration. Confirm
  `{{ARCH_CHECK_CMD}}` is in the `CLAUDE.md` Key Commands table AND runs as a required CI check
  (`scripts/templates/ci-verify.yml` copied to `.github/workflows/`). A config that exists but nothing
  runs → **P1**: the check that never runs.
- **Aspirational rows that never landed.** A layer row marked `target:` at adapt time whose directory
  is still empty months later is a decision to surface, not to silently keep printing.

## Check 7 — Is the provider hub still wired and in sync?

The cross-tool layer rots like any other config. Read-only unless `--fix`.

- **Read-order resolves.** Every path named in `AGENTS.md`'s onboarding read-order and every
  `.claude/rules/*.md` it points at exists on disk. A dead pointer here is as bad as a dead `@` import
  → **P0** if `AGENTS.md` names a rule file that was pruned.
- **Mirrors in sync.** Run `sh scripts/sync-agents.sh --check`. Any `STALE` mirror → **P1** (a
  hand-edited or drifted tool file now contradicts `AGENTS.md`; fix = re-run the script). A mirror with
  its `GENERATED … DO NOT EDIT` header removed (edited by hand) → **P1**, with the note that edits
  belong in `AGENTS.md`.
- **Inline doctrine matches source.** The three inline claims in `AGENTS.md` still match their source
  rules: the dependency rule vs `clean-architecture.md`, the same-change update contract vs
  `documentation.md`, the guardrails vs `settings.json` deny (see Check 5). Divergence → **P2**.

---

## Output — a prioritized fix list

One table, ordered by severity, nothing else before it:

- **P0 — actively misleading.** Commands that no longer exist, dead `@` imports, layer-map rows
  pointing at directories that are gone, forbidden-command rules that no longer name the real
  dangerous command, missing database/migration rules for a database that now exists. These cause
  wrong actions, not just noise.
- **P1 — drifted.** Renamed scripts, moved paths, structure sections that no longer match, stale
  in-progress entries, contradicted convention rules, inward-pointing import violations across the
  layer boundaries (report the counts; fixing them is source work the user schedules, not a `--fix`
  item).
- **P2 — missing coverage.** New stack elements with no module, un-imported rules files, unarchived
  shipped plans, deny-list gaps, no import-boundary lint rule despite counted violations.
- **P3 — hygiene.** Empty folders, redundant rules already enforced by a pre-commit hook or linter,
  `CLAUDE.md` drifting over ~120 lines.

Each row: severity, the file and line, what is wrong, the evidence you checked, and the proposed fix
as a concrete edit. Number the rows so the user can reply "do 1, 4, and 7."

Then two short closing notes:

- **Verified clean** — what you checked that was fine, so the user knows the scope of the audit.
- **Judgment calls left to the user** — every contradiction where the right answer might be to change
  the code rather than the rule. Do not decide those; that is a product decision wearing a
  configuration costume.

If `--fix` was passed, apply P0 and P1 items, re-run Check 1 and Check 2 to confirm the fixes hold,
then list P2/P3 as still-open and stop. Never apply a Check 3 contradiction fix automatically — you
would be picking a side in a decision that belongs to the user.
