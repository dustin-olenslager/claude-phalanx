---
description: Inspect this repository and adapt the dropped-in Claude config kit to it — fill placeholders, prune modules that do not apply, and ask at most five questions.
argument-hint: "[--yes to accept all defaults] [--strict|--relaxed] [subdir if the project root is not cwd]"
---

# Adapt this Claude setup to this project

You are wiring a generic Claude Code configuration kit into a real repository. Your job is to **infer
almost everything and ask almost nothing**. A question you could have answered by reading a lockfile
is a bug.

## Hard rules (read before doing anything)

- **This command edits configuration only.** In scope: `CLAUDE.md`, `.claude/**`, `docs/claude/**`,
  `.gitignore` (append-only). In scope also: `AGENTS.md`, and the generated tool mirrors it emits —
  `.github/copilot-instructions.md`, `.cursor/rules/`, `.clinerules/`, `.windsurf/rules/`, `GEMINI.md`,
  `CONVENTIONS.md` — plus `scripts/` (the `sync-agents.sh` mechanism and `scripts/templates/`).
  Out of scope, always: application source, tests, schema, CI configs,
  `package.json`/`pyproject.toml`/etc. If adapting seems to require a source change, report it in
  Phase 5 instead of doing it. Sole exception: if the user accepts the coverage scaffold (Q6), you
  may **create** the two new tooling files it names — never modify existing source, manifests, or CI.
- **A pre-existing `CLAUDE.md` or `AGENTS.md` is the user's, not yours.** Merge into it; never
  overwrite. Their rule wins on every conflict, and every conflict gets reported in Phase 5.
- **Never leave an unfilled `{{PLACEHOLDER}}`.** An unfillable rule is worse than a deleted rule: it
  teaches the model that this file contains noise, and it starts skimming the rules that *are* real.
  If you cannot fill a token with a verified value, delete the bullet, the block, or the whole file.
- **Make no claim you have not checked.** Every command you write into `CLAUDE.md` must be one you
  found in the project's own script/task table, or one you ran to confirm it exists.

---

## Phase 1 — Detect, don't ask

Inspect the repo and write down each finding plus its implication. Do all of this before asking anything.

**Ecosystem and package manager.** Look for `package.json`, `pyproject.toml`, `requirements.txt`,
`go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`, `*.csproj`, `pom.xml`, `build.gradle(.kts)`,
`mix.exs`. The lockfile decides the package manager, not the README: `package-lock.json`→npm,
`yarn.lock`→yarn, `pnpm-lock.yaml`→pnpm, `bun.lockb`→bun, `poetry.lock`→poetry, `uv.lock`→uv,
`Gemfile.lock`→bundler. Two lockfiles is itself a finding — surface it, do not pick silently.

**The real command table.** Read `scripts` in `package.json`, `[tool.poetry.scripts]`/`[project.scripts]`,
`Makefile` targets, `Justfile`, `Taskfile.yml`, `mise.toml`, `cargo` aliases, `mix` aliases.
Extract the actual invocations for: dev, build, test, lint, format, typecheck, migration generate,
migration apply, coverage/enforcement checks. **Prefer the project's own script alias over the raw
tool** (`{{PKG_MANAGER}} run test` beats `vitest run`) — the alias survives tool swaps.
**No scripts table is not "no command"** — many ecosystems (Python especially) run tools directly.
Fall back to the ecosystem-native invocation, verified against the dev-dependency list: `uv run pytest`,
`uv run mypy`, `uv run ruff check`, `poetry run pytest`, `go test ./...`, `go vet ./...`, `cargo test`,
`cargo clippy`, `bundle exec rspec`, `dotnet test`. Only delete a command's rule when the *capability*
genuinely does not exist in the project (no test framework installed at all) — the test and typecheck
commands feed the kit's non-negotiable pre-commit gates, so deleting them is a last resort, not a
convenience.

**Monorepo shape.** `workspaces` in `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `nx.json`,
`lerna.json`, `[workspace]` in `Cargo.toml`, `go.work`, Gradle `settings.gradle`. Record the member
list and how a command is scoped to one member (workspace flag, filter flag, task runner). **When
workspaces exist, read each member package's scripts too, not just the root's** — the real test or
migration command often lives only in a member. For all-workspace commands, prefer the runner form
the repo already uses: `pnpm -r test`, `npm run test -ws`, `turbo run test`, `nx run-many -t test`.
Only keep `MODULE:monorepo` if there is genuinely more than one member.

**Framework fingerprints — from dependencies, not folder names.** UI (React, Vue, Svelte, Angular,
Next, Nuxt, Remix), server (Express, Fastify, NestJS, Django, FastAPI, Flask, Rails, Laravel, Gin,
Spring), mobile/desktop (React Native, Electron, Tauri), AI/LLM SDKs. A framework in `devDependencies`
only is probably tooling, not the app.

**Architecture layer map.** The kit's foundational module, `.claude/rules/clean-architecture.md`,
needs its four layers mapped to real directories. Infer from structure: domain from `src/domain`,
`src/core`, `src/entities`; use cases from `src/application`, `src/usecases`, `src/services`;
adapters from `src/adapters`, `src/api`, `src/controllers`, `src/routes`; infrastructure from
`src/infrastructure`, `src/platform`, `src/db`, `src/config` — or the feature-sliced equivalent
(per-feature folders holding entity, use-case, and adapter files, plus a shared platform directory).
Confirm each candidate by sampling its files' imports, not by its name. **If the repo does not follow
Clean Architecture** — business rules in route handlers or UI components, ORM models imported
everywhere — do not pretend otherwise. Record the directories that most nearly play each role *and*
the concrete evidence of non-conformance (which files hold business logic in which outer layer, with
counts); both feed Phase 2 and Phase 5.

**Architecture-boundary linter.** Look for `.dependency-cruiser.*`, `.importlinter`/`[importlinter]`,
an ArchUnit test, `.go-arch-lint.yml`, NetArchTest. If present, fill `{{ARCH_CHECK_CMD}}` from it and
keep `MODULE:arch`. If absent, the kit does NOT generate a config (it would be layout-coupled and
rewritten) — drop `MODULE:arch` and report the arch gate as a recommended manual setup step.

**Data layer.** ORM/migration tooling (Drizzle, Prisma, TypeORM, Knex, Alembic, Django migrations,
ActiveRecord, Ecto, golang-migrate, Flyway, EF Core) plus the real location of the schema file and
migrations directory — confirm by listing, never by convention. Record the tool's dangerous
"sync schema directly" command (`db:push`, `prisma db push`, `schema:sync`) so the database rules can
forbid it by name. **The apply command you pick for `{{MIGRATE_APPLY_CMD}}` must actually have the
property the database rules assert of it: forward-only, non-interactive, never drops data.** Prefer
the deploy-grade form over the dev-grade one — `prisma migrate deploy`, not `prisma migrate dev`
(which can prompt to reset and drop the database); `drizzle-kit migrate`, not `push`; `alembic
upgrade head`, not `downgrade`. If the toolchain has no such safe command, fill with the closest
safe form and flag the residual risk in the Phase 5 report.

**Tests.** Framework (vitest, jest, pytest, go test, cargo test, rspec, JUnit, xUnit) and where tests
actually live — colocated next to source, a top-level `tests/`, a mirrored `__tests__/` tree. Sample
real paths; the convention you find beats the convention you expect.

**CI.** `.github/workflows/*`, `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`,
`Jenkinsfile`, `.buildkite/`. Record which of typecheck/lint/test/coverage/migration-integrity CI
already enforces — a rule that mirrors an existing CI gate is high-value; a rule about a gate that
does not exist is aspiration, so mark it as such or cut it.

**Default branch.** `git symbolic-ref refs/remotes/origin/HEAD`, falling back to `git remote show
origin`, then to the current branch. Do not assume `main`.

**UI layer and styling.** Presence of a UI at all, then the styling approach: Tailwind, CSS Modules,
styled-components/emotion, vanilla CSS, a component library (shadcn/ui `components.json`, MUI,
Chakra), and the icon library. No UI ⇒ delete `MODULE:frontend` and `MODULE:design-system`.

**Linters, formatters, hooks.** ESLint/Biome/Prettier/Ruff/Black/gofmt/rustfmt/RuboCop configs,
`.editorconfig`, and pre-commit hooks (`.husky/`, `lefthook.yml`, `.pre-commit-config.yaml`).
Whatever a hook already enforces does not need to be a rule.

**Existing memory files and docs home.** `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.cursorrules`,
`.github/copilot-instructions.md`, any `.claude/` that predates the kit — these are inputs to a merge,
never things to overwrite. Also check whether `docs/` already has a convention worth folding into
rather than scaffolding a fresh `docs/claude/` tree beside it.

**Running change log.** Detect `CHANGELOG.md`/`HISTORY.md` and whether either carries an
`## [Unreleased]` (or equivalent running) section. This decides the worklog target: an existing
running log is REUSED as the worklog; only a repo with none gets a fresh `docs/claude/worklog.md`.
Never create a second parallel log.

**Existing provider files.** `AGENTS.md`, `.cursor/rules/`, `.clinerules/`, `.windsurf/rules/`,
`.github/copilot-instructions.md`, `GEMINI.md`, `CONVENTIONS.md`. A pre-existing `AGENTS.md` is a
merge input (theirs wins), never an overwrite — same doctrine as `CLAUDE.md`.

---

## Phase 2 — Ask at most five questions, in one batch

State your inferences first, as a compact table the user can skim and correct. Then ask **one message**
containing at most five questions, each with a default in brackets, and tell the user that replying
"yes" or "all good" accepts every default. Never interrogate from scratch; never ask serially.

Ask only what inspection genuinely cannot answer:

1. **One sentence: what is this project and who uses it?** (No default — this is the one thing no
   tool can infer. If the user skips it, write a one-line description from the README's first
   paragraph and mark it `TODO: confirm`.)
2. **Design reference product** — only if a UI was detected. `[default: no design reference; keep the
   generic density/spacing rules]`. Naming a reference (a product whose aesthetic to match) is what
   makes UI rules enforceable rather than decorative.
3. **Change-approval protocol: strict or relaxed?** `[default: strict — describe the change and wait
   for approval before editing]`. Relaxed = proceed on small, obviously-scoped edits; still describe
   first for anything structural. Honor `--strict`/`--relaxed` if passed as an argument and skip this.
4. **Optional modules to keep**, presented as your recommendation with detection evidence, e.g.
   "keep database (Alembic + `migrations/` found) and frontend (React + Tailwind); drop ai,
   monorepo, design-system." `[default: as listed]`
5. **The single most ambiguous detection result** — two lockfiles, two test directories, no test
   script, an existing `CLAUDE.md` whose rules conflict with the kit's. Ask about the one that matters
   most; put the rest in the Phase 5 report. **If the layer mapping is what is ambiguous** (the repo
   does not conform to Clean Architecture and the best-effort map required judgment), this question
   takes the slot: *"adopt Clean Architecture as the target and note the gaps [default], or map
   current reality only?"* Default = the map names where each layer *should* live and the gap report
   says what is not extracted yet; the alternative maps only what exists today.
6. **Endpoint-coverage enforcement** — only if the project has an HTTP/RPC surface and Phase 1 found
   no existing coverage-enforcement script. *"Scaffold the endpoint-test coverage check (a ~30-line
   script that walks the route manifest and fails on any route file without a matching test, plus its
   allowlist file seeding the current gaps)?"* `[default: yes]`. If no, the testing rules' coverage
   block is rewritten to target-mode wording instead (see Phase 3).

Questions 2, 5, and 6 are conditional — ask them only when their condition holds. If more than five
would qualify, ask the five most consequential, take defaults for the rest, and list those
auto-defaults in the Phase 5 report.

If `--yes` was passed, skip the round entirely, take every default, and list every assumption in the
Phase 5 report so the user can audit what they auto-accepted.

---

## Phase 3 — Fill and prune

Work in this order; it is the order that avoids leaving orphans.

1. **Resolve every module fence.** Grep the tree for `MODULE:` to enumerate the ids actually present
   (`database`, `frontend`, `api`, `ai`, `monorepo`, `design-system`, `project-conventions`,
   `project-layers`, and any others). For each id that does not apply, remove the
   `<!-- MODULE:x --> … <!-- /MODULE:x -->` block — content *and* both comment markers — everywhere
   it appears. **For each module you keep, strip the two marker comments too and keep only the
   content**: the fences are adapt-time scaffolding, and leaving them behind makes Phase 4's
   zero-`MODULE:` check impossible. Some blocks are always-keep and say so in their marker — read the
   marker before deleting. `project-layers` (in `clean-architecture.md`) is KEEP-always: fill its four
   tokens, delete the two illustration layouts below the table as its marker instructs, then strip
   its markers like any other kept fence.
2. **Delete the rules files those modules own**, and in the same edit delete their `@` import lines
   from `CLAUDE.md` plus the one-line comment above each import. An `@` import pointing at a deleted
   file is a silent failure — the guidance is simply gone and nothing says so. **Never delete
   `clean-architecture.md`, `workflow.md`, or `quality-bar.md`** — they are stack-independent and
   apply to every project; `clean-architecture.md` is the module the others inherit from. Adapt its
   layer map instead.
3. **Delete agents that cannot apply here** (a UI-review agent in a headless service, a database
   agent with no database). Keep the general-purpose reviewers. When unsure, keep — an unused agent
   costs nothing until invoked, unlike an unfillable rule.
4. **Fill every remaining placeholder** with a verified value. The canonical registry:

   | Token | Filled from |
   |---|---|
   | `{{PROJECT_NAME}}` | manifest name, else repo directory name |
   | `{{ONE_LINE_DESCRIPTION}}` | Q1 answer, else README first paragraph |
   | `{{CORE_PILLARS}}` | Q1 answer — the 2–4 standards every feature is judged against |
   | `{{DEFAULT_BRANCH}}` | `origin/HEAD` |
   | `{{PKG_MANAGER}}` | lockfile |
   | `{{LANGUAGE_RUNTIME}}` | `engines`, `.nvmrc`, `.tool-versions`, `requires-python`, `go` directive, `rust-toolchain` |
   | `{{INSTALL_CMD}}` `{{DEV_CMD}}` `{{BUILD_CMD}}` `{{TEST_CMD}}` `{{LINT_CMD}}` `{{FORMAT_CMD}}` `{{TYPECHECK_CMD}}` | the script table (prefer the project's own alias); else the verified ecosystem-native invocation from Phase 1 |
   | `{{COVERAGE_CHECK_CMD}}` | the existing enforcement script; else the Q6 scaffold's invocation; else (Q6 declined) rewrite the coverage block to target-mode wording — a plan, not a claim of live CI machinery |
   | `{{CLIENT_STACK}}` `{{SERVER_STACK}}` `{{DATABASE_STACK}}` | framework fingerprints, one short line each |
   | `{{MONOREPO_LAYOUT}}` | workspace config — member list plus the scoping form (workspace flag / filter / task runner) |
   | `{{PROJECT_STRUCTURE}}` `{{TEST_DIR}}` `{{ENDPOINT_SRC_DIR}}` | a real two-level listing, annotated — never an assumed tree |
   | `{{DOMAIN_DIR}}` `{{USECASE_DIR}}` `{{ADAPTER_DIR}}` `{{INFRA_DIR}}` | the architecture layer map (Phase 1) + Q5 if ambiguous; in a non-conforming repo, the nearest-role directory — the gap goes in the Phase 5 report, never in the map silently |
   | `{{UI_PRIMITIVES_DIR}}` `{{DOMAIN_COMPONENTS_DIR}}` `{{PAGES_DIR}}` | verified UI directory listings |
   | `{{SCHEMA_FILE}}` `{{MIGRATE_GEN_CMD}}` `{{MIGRATE_APPLY_CMD}}` | ORM detection; the apply command must be the forward-only, non-interactive form (Phase 1) |
   | `{{EXPORT_STYLE}}` `{{FILE_NAMING}}` `{{IMPORT_ALIAS}}` | majority pattern in existing source (sample ≥10 files; state the sample size) |
   | `{{SHARED_CONSTANTS_PATH}}` `{{API_WRAPPER}}` `{{DATA_ACCESS_LAYER}}` `{{DATA_FETCH_LIB}}` | the real modules, if they exist; else delete the row |
   | `{{UI_FRAMEWORK}}` `{{STYLING_SYSTEM}}` `{{ICON_LIBRARY}}` `{{ICON_SIZE}}` | dependencies + existing component code |
   | `{{DESIGN_REFERENCE}}` `{{AESTHETIC_FAMILY}}` `{{CHROME_WEIGHT}}` `{{PALETTE_STRATEGY}}` `{{DENSITY}}` `{{MOTION_INTENSITY}}` | Q2, else the dominant pattern in existing components |
   | `{{DEFAULT_TEXT_SIZE}}` `{{SECTION_HEADER}}` `{{FIELD_LABEL}}` `{{FIELD_VALUE}}` `{{SECTION_PADDING}}` `{{ELEMENT_GAP}}` `{{BORDER_TREATMENT}}` | the literal class strings or tokens most used in existing UI code |

   The registry is a guide, not the authority: **grep the tree for every `{{…}}` token that actually
   exists** and resolve each one by the same ladder — detect, else ask (within the five), else delete.
   `{{DOUBLE_BRACES}}` and `{{TOKEN}}` are prose references to the convention itself, living inside
   setup instruction comments; delete those whole comments once the file is filled.
5. **Endpoint-coverage enforcement** (projects with an HTTP/RPC surface). If Phase 1 found an existing
   enforcement script, fill `{{COVERAGE_CHECK_CMD}}` with it and keep the coverage block as-is. If
   none exists and Q6 was accepted (the default), create exactly two new files — the check script
   (walk the route manifest, fail on any route file lacking a matching test) and its allowlist seeded
   with the current gaps — fill `{{COVERAGE_CHECK_CMD}}` with the script's invocation, and report the
   one-line wiring the user must do themselves (script-table entry, CI job). If Q6 was declined,
   rewrite the coverage block into target-mode wording so it describes the intended discipline without
   asserting CI machinery that is not there — a rule claiming a check that does not run is a bluff.
6. **Merge, if a `CLAUDE.md` already existed.** Keep their file as the spine and their section order.
   Append kit sections that add something new. Where a kit rule and a theirs cover the same ground,
   keep theirs verbatim and record the difference for the report. Never delete a line they wrote.
7. **Scaffold `docs/claude/`** only if absent: the in-progress queue, the completed log, and area
   folders matching the modules you kept — no folders for work that does not exist.
8. **Scaffold the plan artifacts** (with the `docs/claude/` scaffold, only if absent): create
   `roadmap.md` from the kit template (keep the example row for the user to delete). For the worklog,
   use the Phase 1 decision — if a reusable `CHANGELOG`/`HISTORY` `[Unreleased]` log exists, point the
   contract at it and do NOT create `worklog.md`; otherwise create `worklog.md`.
9. **Generate the provider-neutral hub — run this LAST, after the rules are filled and pruned (steps
   1–8).** Copy the kit's `AGENTS.md` template, fill `{{PROJECT_NAME}}` (its only placeholder), keep its
   `<!-- PANOPLY:RULES:BEGIN/END -->` markers, then run `sh scripts/sync-agents.sh`. The generator emits
   **self-contained** tool mirrors — each one inlines the `MIRROR` preamble followed by the full body of
   every surviving `.claude/rules/*.md` module (`.cursor/rules/` gets one `.mdc` per module plus a
   preamble file; `.github/copilot-instructions.md`, `GEMINI.md`, `CONVENTIONS.md`, `.clinerules/`,
   `.windsurf/rules/` each get one concatenated file) — and refills `AGENTS.md`'s `PANOPLY:RULES` block
   with the same bodies, so no tool is left a bare pointer to `.claude/rules/`. Run it AFTER pruning so a
   deleted module never gets inlined (a stale rule inlined everywhere is worse than a missing one). If an
   `AGENTS.md` already existed, MERGE (theirs wins, same as `CLAUDE.md`): keep their content, append the
   onboarding contract + `MIRROR` block + the `PANOPLY:RULES` markers + the sync note, then run the
   script. Add `@AGENTS.md` to `CLAUDE.md` (Edit 1 of the CLAUDE.md changes).
10. **Wire the enforcement plane.** Copy `scripts/templates/ci-verify.yml` and
    `scripts/templates/pre-commit` in place, filling their `<CMD>` slots from the Key Commands table.
    **Then run the branch protection init script interactively:** `sh scripts/init-repo-protection.sh`.
    This script uses `gh` CLI to configure branch protection on the default branch (require PR, require
    `verify` check, no force-push, no direct push). It prompts for confirmation and reports success/
    failure. If `gh` is unavailable or unauthenticated, it prints manual instructions and exits 0.
    Include the script's outcome in the Phase 5 report.
    **The CI template now includes the expert-review gate** (`check-expert-review.sh`) and the docs gate
    (`check-docs.sh`) by default — verify both jobs are present in the copied workflow.
11. **Append to `.gitignore`** if missing: `.claude/settings.local.json`, `CLAUDE.local.md`.

---

## Phase 4 — Verify before reporting

Run these and fix what they find. Do not report success on an unverified step.

- **No surviving tokens.** Grep for `{{` and for `MODULE:` across `CLAUDE.md`, `.claude/rules/`,
  `.claude/agents/`, and `docs/` — **explicitly excluding `.claude/commands/`**, whose files describe
  the conventions and so legitimately contain both strings. Both greps must return zero hits: fences
  are stripped from kept modules too (Phase 3 step 1), so zero genuinely means done. Any hit is a
  Phase 3 failure — go back and fill or delete it.
- **No orphaned imports.** Every `@path/to/file.md` in `CLAUDE.md` resolves to a file that exists.
  Every rules file that exists is imported by exactly one line in `CLAUDE.md`.
- **Every command is real.** For each command string you wrote into any config file, confirm it
  appears in the project's script/task table — or, for an ecosystem-native fallback, that its tool is
  in the dependency list; where cheap, run the read-only ones (typecheck, lint, `--help`) to prove
  they work. Never run migrations or anything touching a database to verify.
- **Every path is real.** Each directory or file path referenced in the config exists on disk.
- **The layer map is complete and real.** All four of `{{DOMAIN_DIR}}` `{{USECASE_DIR}}`
  `{{ADAPTER_DIR}}` `{{INFRA_DIR}}` are filled, each mapped directory exists on disk, and the two
  illustration layouts in `clean-architecture.md` have been deleted. Under "adopt as target", a
  planned-but-absent directory gets its row marked `target:` so the map never claims a directory
  that is not there — **never create directories**; that is a source change and out of scope.
- **Provider hub wired.** `AGENTS.md` exists, `{{PROJECT_NAME}}` filled, `CLAUDE.md` contains
  `@AGENTS.md`, and `sh scripts/sync-agents.sh --check` exits clean. `AGENTS.md`'s read-order paths all
  resolve on disk (`roadmap.md`, `in-progress.md`, the worklog target, the rule modules it names).
- **Mirrors are self-contained, not pointers.** Every generated mirror inlines the full rule bodies —
  spot-check by grepping a distinctive sentence from `clean-architecture.md` and confirming it appears
  verbatim in `.github/copilot-instructions.md`, `GEMINI.md`, and a `.cursor/rules/*.mdc`. No mirror
  should say only "the canonical rules live in `.claude/rules/`" — that is the bug this generator fixes.
- **Plan artifacts present.** `roadmap.md` exists; the worklog target exists (either `worklog.md` or a
  `CHANGELOG`/`HISTORY` `[Unreleased]` section) — exactly one, never both.
- **Nothing outside scope changed.** `git status --porcelain` must show changes only under
  `CLAUDE.md`, `.claude/`, `docs/claude/`, `.gitignore`, `AGENTS.md`, the generated tool-mirror paths
  (`.github/copilot-instructions.md`, `.cursor/`, `.clinerules/`, `.windsurf/`, `GEMINI.md`,
  `CONVENTIONS.md`), and `scripts/`. If anything else is dirty and you touched it, revert it and say so.
- **Length discipline.** `CLAUDE.md` stays under ~120 lines; it loads into every context window.
  If it is longer, move depth into a rules module rather than trimming the "why" from rules.

---

## Phase 5 — Report

Output, in this order and nothing more:

1. **Files changed** — created / modified / deleted, with line counts. Note that nothing outside the
   config scope was touched.
2. **Inferred vs asked** — a two-column list. For each inference, the evidence (`pnpm-lock.yaml` ⇒
   pnpm). This is what lets the user spot a wrong guess in ten seconds.
3. **Deleted** — every module, rules file, agent, and import removed, each with its one-line reason.
4. **Conflicts and unknowns** — every place a pre-existing rule disagreed with a kit rule (theirs was
   kept), every ambiguity you resolved by default, every rule you deleted for lack of a verified value.
5. **Architecture gaps** — a prominent section whenever the repo does not conform to the layer map
   as filled. State which mapping mode was chosen (target-with-gaps vs current-reality), then each
   concrete gap with evidence: "route handlers in `<dir>` contain business rules (N files, e.g.
   `<path>`); the domain layer is aspirational until extracted", "ORM models imported directly by
   `<layer>` in N files", "no import-boundary lint rule yet (`clean-architecture.md` checklist
   item 1)". Do not fix any of these — they are source changes, out of scope here.
6. **The 2–3 highest-value things only a human can add**, chosen for this repo, not generic advice:
   the invariant that is invisible in the code (what must never happen in this system), the
   deploy/release path and what is dangerous about it, the decision that keeps getting re-litigated,
   the directory newcomers always misuse. Name the exact file and section where each belongs.
7. **Worklog target** — state which was chosen: "reusing `CHANGELOG` `[Unreleased]`" vs "created
   `docs/claude/worklog.md`".
8. **Provider mirrors** — list the tool files emitted; note the source of truth is `AGENTS.md` and the
    fix for any drift is `sh scripts/sync-agents.sh` (wire `--check` into pre-commit/CI).
9. **Branch protection** — report the outcome of `init-repo-protection.sh`: "configured" / "skipped (no gh)" / "skipped (user declined)" / "failed (reason)". If configured, note that `verify` check is now required on `{{DEFAULT_BRANCH}}`.
10. **Expert-review gate** — report whether `check-expert-review.sh` is wired into the CI template and pre-commit hook. Note the trivial escape hatches (PR label "trivial", commit prefix "trivial:", 1-file ≤15-line no-schema change).
11. **Enforcement status** — if branch protection configured and `verify` check required, enforcement is BINDING. Otherwise, enforcement is ADVISORY: manual step needed to enable branch protection on `{{DEFAULT_BRANCH}}` and mark `ci-verify` checks required. Until then, `.claude/settings.json` binds only Claude and cross-tool guardrails are doc-level prose.
12. **Architecture gate** — if no boundary linter exists, name it as a recommended setup: the per-stack tool (`clean-architecture.md` → Enforcement) encoding the filled layer map, started in report-only.

Close by telling the user to run `/audit-claude-setup` in a few months — a stale rule is read exactly
as confidently as a true one.
