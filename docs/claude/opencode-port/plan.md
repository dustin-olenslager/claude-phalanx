# Plan: Port the Phalanx config layer to opencode

- **Area:** `opencode-port` · **Started:** 2026-09-17 · **Status:** Complete
- **Owner:** operator-driven (OpenCode session)
- **Next step:** Shipped. Verify in a fresh opencode session that the agents appear in `@`-autocomplete (the session that wrote these files predates them — config is loaded once at startup).
- **Roadmap initiative:** Harness parity — run Phalanx's working discipline under opencode, not only Claude Code.

## Goal

After this ships, an opencode session in this workspace has the same focused subagents (implementer,
orchestrator, researcher, verifier), the same review personas (code-reviewer, cto-review,
security-engineer, software-architect, backend-architect), and the same setup commands
(`/work`, `/work-loop`, `/audit-claude-setup`, …) that a Claude Code session gets from Phalanx —
without the operator re-typing any of it per repo. Success: opencode starts clean with the new
`agent/` + `command/` dirs present, `@`-autocomplete shows the new subagents, and no name collides
with a built-in (`build`, `plan`, `general`, `explore`).

**Out of scope:** Porting `core/` + `adapters/` (the JS phase-state/memory engine) — that is a later
initiative and would need a plugin or MCP wrapper. Porting the `hooks/` gate + anchor scripts — the
Claude Code hook protocol does not map 1:1 to opencode plugin hooks; deferred. Rewriting the ~200KB
`AGENTS.md`/`CONVENTIONS.md`/`CLAUDE.md` doctrine.

## Context

Phalanx is a Claude-Code-native delivery engine. Its assets split cleanly into three strata:

1. **Already ported.** Fourteen `SKILL.md` files under `skills/` are already present at
   `/config/.claude/skills/` and are auto-loaded by opencode as external skills (opencode scans
   `~/.claude/skills/`). They are live in the current session — no work needed. Confirmed present:
   `adversary-review`, `arch-enforce`, `brief`, `caveman`, `caveman-commit`, `caveman-review`,
   `caveman-stats`, `clean-architecture`, `edge-hunter`, `effect-ts`, `execute-phase`,
   `maintain-mode`, `optimize-loop`, `recall-memory`.
2. **Needs translation (this plan).** `agents/` (4) and `.claude/agents/` (6 personas) and
   `commands/` (2) + `.claude/commands/` (3). These use Claude Code frontmatter
   (`tools:`, `model:`) and Claude's slash-command convention; opencode wants `agent/<name>.md` with
   `mode`/`permission` and `command/<name>.md` with a `template` body.
3. **Deferred (out of scope).** `core/`, `adapters/`, `hooks/`, `policy/`, `settings/`.

Key constraints discovered:

- The global config is `/config/.config/opencode/opencode.jsonc` (JSONC, not `.json`). It currently
  defines only one agent (`build`). There are **no** `agent/`, `command/`, or `plugin/`
  directories yet — so nothing to merge against; all files are net-new.
- opencode auto-discovers `agent/*.md` and `command/*.md` under the global config dir. Adding files
  needs **no** `opencode.jsonc` change. That keeps this port config-file-free and low-risk.
- **Name collisions to avoid:** opencode ships built-in `general` and `explore` agents. Phalanx's
  `researcher` overlaps `explore` in spirit but does not collide by name — keep it, since its
  report contract (≤250 words, file:line anchors) is stricter. `implementer` overlaps `build` but
  again does not collide by name. None of the six persona names collide.
- opencode config is loaded once at startup and is **not** hot-reloaded. The operator must restart
  opencode after this lands.
- Per the `/workspace` Panoply contract, plan artifacts live in the owning repo. The **owning repo
  here is `claude-phalanx`** (the source being ported) — the plan lives at
  `docs/claude/opencode-port/plan.md` and the roadmap row is in `docs/claude/roadmap.md`. The
  generated config itself lands in `/config/.config/opencode/` (not the repo), because that is where
  opencode reads global config.

## Architecture

This plan does not touch application source, so the Clean Architecture rows are mostly "none" — the
architecture question here is instead **which layer of the opencode config surface each adapter
sits on**.

- **Layers touched:** none of Entities/Domain · Use Cases · Interface Adapters · Frameworks. This is
  configuration data consumed by the opencode harness, not code under the project's architecture
  boundary.
- **New ports (interfaces):** none. The port/adapter mapping is conceptual: Phalanx's Claude Code
  `agents/*.md` and `commands/*.md` are the source format; opencode's `agent/*.md` and `command/*.md`
  are the target format. The translation preserves the *body* (the doctrine) verbatim and rewrites
  only the *frontmatter* (the harness binding).
- **Boundary data:** none.
- **Dependency direction:** n/a (no code dependencies added).
- **Swap test:** the vendor/framework this touches is the agent harness (Claude Code → opencode).
  Every translated file must live entirely in the opencode config dir; no Phalanx source file is
  modified. If a translation required editing Phalanx's own skills or `core/`, the split would be
  wrong.

**Frontmatter mapping (Claude Code → opencode):**

| Claude Code | opencode |
|---|---|
| `name:` | filename `agent/<name>.md` (frontmatter `name` optional) |
| `description:` | `description:` (unchanged) |
| `tools: Read, Edit, Write, …, Task` | `permission:` block; subagents get `mode: subagent` |
| `model:` (optional) | omitted → inherits `default_agent` model, or set `model: litellm/auto` |
| (multi-line persona files) | `mode: subagent`, body = prompt |

## Milestones

- [x] **M1 — subagents** — wrote `agent/implementer.md`, `agent/orchestrator.md`,
  `agent/researcher.md`, `agent/verifier.md` to `/config/.config/opencode/agent/`. Body copied
  verbatim from Phalanx `agents/*.md`; frontmatter translated to `description` + `mode: subagent`.
  `researcher`/`verifier` got `permission.edit: deny` to preserve their read-only contract.
  Orchestrator's `Workflow` reference rewritten for opencode (no such tool).
- [x] **M2 — personas** — wrote the five `.claude/agents/*.md` personas (`backend-architect`,
  `code-reviewer`, `cto-review`, `security-engineer`, `software-architect`) as `mode: subagent`
  agents. Dropped `name`/`color`/`emoji`/`vibe`; body verbatim.
- [x] **M3 — commands** — wrote `command/work.md`, `command/work-loop.md`, `command/assess-stack.md`.
  **Deliberately skipped `audit-claude-setup` and `adapt-claude-setup`:** both exist solely to audit
  and adapt Claude Code's own `.claude/` config tree, which opencode does not read — they are
  inapplicable, not untranslated. `work-loop` was rewritten `${CLAUDE_DIR}` → `${PHALANX_DIR}` and
  flagged as a Phalanx wrapper, not an opencode-native loop.
- [x] **M4 — verify** — `opencode debug config` confirms all 9 agents resolve as `mode: subagent`
  and all 3 commands resolve; `opencode agent list` shows them beside the built-ins with no name
  collision. Config loads clean (exit 0).
- [x] **M5 — docs + cleanup** — this file, `completed-features.md`, roadmap → Shipped, worklog line,
  `in-progress.md` row removed.

## Open questions

- [ ] Should the subagents pin a model (e.g. `verifier` on a cheap model, `orchestrator` on a strong
  one) or all inherit `litellm/auto`? — _blocks M1; default to inherit unless the operator says
  otherwise._
- [ ] Do we want the gate hooks (`secret-gate`, `stale-main-gate`, `arch-enforce`) ported as an
  opencode plugin in a follow-up? — _not blocking this plan; candidate for the next initiative._

## Build notes

> **Build note:** 2026-09-17 — the plan assumed the global config was `opencode.json`; it is
> `opencode.jsonc`. Also, fourteen Phalanx skills were already present under `/config/.claude/skills/`
> and auto-loaded, so "port the skills" was already done. The port is therefore *only* agents +
> personas + commands.

## On ship

**Shipped 2026-09-17.** Plan folder kept in place (single-milestone port; no `completed/` move —
this plan *is* the feature record). `completed-features.md` entry added, worklog line appended,
`in-progress.md` row removed, roadmap initiative moved to Shipped. The restart gotcha is recorded
here and in the worklog.

**Gotcha for the next session:** opencode loads config once at startup. The 9 agents + 3 commands
exist on disk now but are invisible to any session started before 2026-09-17 23:29 — restart
opencode to pick them up.
