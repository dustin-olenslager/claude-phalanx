---
description: Assess whether this project's languages, frameworks, and infrastructure are still the right choices — support status, currency, fit, and exit cost — using live research, never training-data memory. Report only; changes nothing.
argument-hint: "[--focus <element>] [--save to persist the report for trend tracking]"
---

# Assess this project's stack

`/audit-claude-setup` asks whether the *rules* still match the stack. This command asks the prior
question: whether the *stack* still deserves the project. It is the review nobody schedules — an
element goes EOL, drifts three major versions behind, or slides into maintenance mode, and every
day it stays invisible the exit gets more expensive.

**Hard rules, before anything else:**

- **Read-only.** This command changes nothing — no installs, no upgrades, no config edits, no source
  edits. Its entire output is a report (plus one report file if `--save`). Acting on the report is
  work the user schedules.
- **Never assert stack health from memory.** Your training data is months-to-years stale, which is
  exactly the failure mode this command exists to catch. Every health claim — an EOL date, a latest
  version, a maintenance-mode status, a successor project — must come from a live web search
  performed during this run. If web research is unavailable entirely, say so and stop; a
  from-memory assessment is worse than none, because it will be confidently wrong about precisely
  the things that changed.
- **A citation is not automatically true.** A stale blog post retrieved today satisfies "live
  search" and still launders a wrong EOL date into an authoritative-looking row. So: prefer primary
  sources — the project's own release/EOL/security pages, the package registry, the repository's
  releases and advisories, `endoflife.date` — over news, and news over blogs. Record **two dates
  per claim**: when you checked, and when the source itself was published or last updated. Any
  claim that drives a P0 or P1 needs a primary source or two independent sources. When the search
  runs but finds nothing authoritative for an element, mark that element **`unverified — no
  authoritative source found`**: an unverified element can never be rated P0/P1 *or* "verified
  healthy" — it gets its own bucket in the report, visibly.
- **"Best" is contextual.** The question is never "what is the best framework" — it is "is this
  element still the right choice *for this project's* pillars, domain, scale, and team." Boring,
  old, and well-fitted is a passing grade, not a finding. An element is flagged for concrete risk
  (unsupported, unpatched, abandoned, fighting the domain), never for being unfashionable.

If `--focus <element>` was given: Step 1 still runs in full (it is cheap and repo-local, and
Step 3's duplication check is meaningless without the whole inventory — a focused run on a dying
library must still notice its successor is already in the tree). Steps 2 and 4 then run for the
focused element only, at full depth.

---

## Step 1 — Inventory (no judgment yet)

Enumerate the stack from what the repo actually declares, not what the docs claim: manifests and
lockfiles (all ecosystems present), runtime pins (`.nvmrc`, `.python-version`, `rust-toolchain`,
engine fields), CI images and actions, Dockerfiles and base images, infra manifests. For each
element record: name, role (runtime / framework / ORM / build tool / test runner / infra — derived
from how the repo actually uses it, not from what you remember the package being), the **exact
pinned version**, and where it is declared.

Scope honestly — the boundary of the inventory is itself a judgment, so make it visible:

- Include transitive-but-load-bearing elements: the database version in the Docker image counts,
  the message broker counts, the CI runner image counts.
- **Print the exclusion list too**, one line of reason per excluded element ("leaf utility, no
  I/O, 40 LOC surface"). An element excluded silently is invisible to every later step, and the
  closing "verified healthy" note would then be claiming coverage it does not have.
- **Never exclude from memory anything in an advisory-prone class** — crypto, auth, parsing and
  serialization, anything touching the network — without a live advisory check first. "I remember
  it being a trivial utility" is exactly the stale judgment the hard rule exists to block.

This table plus the exclusion list is the scope of everything below.

## Step 2 — Health check (live research, per element)

For each in-scope element, research and record — each claim with source, source's own
publication/updated date, and date-checked:

- **Support status** — is the pinned version inside its support window? EOL date, LTS schedule,
  security-patch policy. **Any EOL element in the production path — runtime, framework, ORM,
  database, or any component handling external input — is automatically the report's top
  severity.** Build-time-only tools rate lower.
- **Currency** — the current stable version, how many majors behind the pin is, and whether the
  intervening majors carry security fixes or only features. "Behind" alone is not a finding;
  "behind a security boundary" is.
- **Maintenance signal** — date of last release, release cadence over the past year, open unpatched
  advisories against the pinned version, whether the maintainers have declared maintenance mode or
  named a successor.
- **Trajectory** — direction, not fashion: is the ecosystem investing or exiting? A named successor
  from the same maintainers, a framework whose plugin ecosystem is visibly unmaintained, a vendor
  sunsetting a product line. Cite evidence, not sentiment.

## Step 3 — Fit check (against this project, not a leaderboard)

Read `CLAUDE.md`'s project overview and pillars, then judge each element against what the project
actually is. Evidence lives in the repo:

- **Strain** — is the project fighting the element? Grep for the signals: monkey-patching,
  `HACK`/`workaround` comments clustered around one dependency, wrapper layers whose only job is
  hiding an API the team dislikes, `> **Build note:**` entries in `docs/claude/` plans and
  `key-patterns.md` gotchas blaming the same element repeatedly. Count and cite; three scattered
  workarounds are a data point, one is not — **except a vendored patch, a long-lived fork, or a
  pinned-with-overrides dependency, which is always a finding on its own**: it blocks every future
  upgrade, and reproducing or abandoning the patched behavior belongs in Step 4's exit estimate.
- **Mismatch** — an element sized wrong for the project's stated scale or domain, in either
  direction: a distributed-systems stack under a single-team CRUD app, or a scripting-grade tool
  carrying a load it visibly cannot (report the evidence: timeouts, retries, size limits hit).
- **Duplication** — two elements doing one job (two HTTP clients, two state libraries, two test
  runners) with no recorded reason. One of them is exit-candidate by default. This check always
  runs against the full Step 1 inventory, `--focus` or not.
- **The passing grade, stated explicitly** — for every element that is supported, current enough,
  maintained, and unstrained: say so in one line. The report must make "keep everything" a
  legitimate outcome, or it becomes a migration generator.

## Step 4 — Exit-cost check (the Clean Architecture dividend)

For each element flagged in Steps 2–3, measure how expensive replacement would actually be — this is
where the dependency discipline in `clean-architecture.md` pays out or its absence gets priced.
Import-grep is the starting instrument, not the whole method:

- **Importable elements** (libraries, ORMs, SDKs): grep the element's imports across the repo,
  count importing files, and name which mapped layers they sit in (`{{DOMAIN_DIR}}`,
  `{{USECASE_DIR}}`, `{{ADAPTER_DIR}}`, `{{INFRA_DIR}}`).
  - **Behind a port** — imports confined to adapters and infrastructure: the swap is an
    adapters-only diff. Estimate it in files touched, and say which port interfaces stay unchanged.
  - **Bled inward** — imports appearing in domain or use-case files: the honest estimate is
    port-extraction first, swap second. Report both numbers separately — and note that the bleed is
    itself a `clean-architecture.md` checklist violation the next `/audit-claude-setup` should be
    counting, whatever the user decides about migrating.
- **Non-importable elements** (the database, the broker, CI actions, base images) show zero
  imports by definition — an import-grep that prices a database swap at "0 files" is the method
  failing, not the swap being free. Grep the real coupling channels instead: config, compose, and
  infra files; migration files and dialect-specific SQL; CI workflows; serialized formats and
  stored data. **Data migration cost is its own line** — schema, history, and volume — never
  folded into a file count.
- **Convention-coupled frameworks** (autoloading, settings objects, file-layout routing, test
  globals): the coupling is not import statements. Count the files participating in the
  convention — routes by layout, settings modules, lifecycle hooks — and say so.
- **If the layer map has `target:` rows** (the repo does not conform to the architecture yet), the
  behind-a-port/bled-inward dichotomy does not apply — there is no port boundary to be behind.
  Say that plainly, classify every flagged element as **port-extraction-first by definition**, and
  use the coupling counts above as the extraction scope. Do not report "adapters-only" against an
  adapter layer that does not exist.
- **Vendored patches and forks** (from Step 3): add the cost of reproducing or abandoning the
  patched behavior on the replacement. This often dominates the import count.
- The estimate names the **kind of work**, not just a number: "38 one-line import swaps" and
  "3 files of deep semantic coupling plus a data migration" must not read as the same size.
- An expensive exit is not an argument for staying forever; it is an argument for extracting the
  port *now*, while the element still works, instead of during the eventual forced migration.

## Trend — always, before writing anything

If `docs/claude/reports/` holds prior stack assessments, read the most recent **full** assessment
(never a `-focus-` report) and report movement per element — resolved, unchanged, worsened, newly
appeared. This runs on every invocation, `--save` or not; the trend between two dated reports is
the strongest signal this command produces. Where the old report's facts have themselves rotted
(an element removed since, a source superseded), say so rather than diffing against fiction.

## Output — ranked report

One table, ordered by severity, then the details:

- **P0 — unsupported in the production path.** EOL runtime, framework, ORM, database, or any
  component handling external input; or an unpatched security advisory against the pinned version.
  These are risks the project is carrying today.
- **P1 — exit clock running.** Maintenance mode, announced successor, security-relevant majors
  behind, vendor sunset with a date. Not on fire; getting more expensive every quarter.
- **P2 — fit strain.** Counted workarounds, vendored patches, sized-wrong elements, unexplained
  duplication.
- **P3 — watchlist.** Trajectory concerns with evidence but no present cost. Re-check next run.
- **Unverified** — elements with no authoritative source found. Listed separately, never rated,
  never "healthy". Say what was searched and what came back.

Each row: severity, element, pinned vs current, the finding in one sentence, source + both dates
(published, checked), and the exit cost from Step 4 (adapters-only / port-extraction-first /
coupling-channel estimate, with the kind of work named).

For every P0 and P1, present the decision in `quality-bar.md`'s format — **stay** vs **migrate** as
two honestly-costed options with a recommendation — and stop there. Do not begin either option;
that decision routes through the normal change-approval workflow like any other structural change.

Close with two notes, same as the audit: **verified healthy** (every element that passed, with the
Step 1 exclusion list restated so the scope is visible) and **judgment calls left to the user**.

If `--save` was passed, persist the report to `docs/claude/reports/`:

- Full run: `stack-assessment-<YYYY-MM-DD>.md`. A same-day rerun overwrites that day's file.
- Focused run: `stack-assessment-<YYYY-MM-DD>-focus-<element>.md` — a partial report must never
  masquerade as a full baseline, and trend comparison only ever baselines against full reports.

`docs/claude/reports/` is an append-only dated archive (see `docs/claude/README.md`): reports are
history, exempt from the plan lifecycle, and never archived or pruned by `/audit-claude-setup`.
