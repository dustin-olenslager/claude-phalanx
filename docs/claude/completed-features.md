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
