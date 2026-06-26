# Phalanx

**Turn Claude Code into a phase-aware, multi-team software factory:** a hard-gated
pipeline, Clean Architecture + Effect standards, adversarial review, and token
discipline — all **always-on** and **enforced by hooks**, so they survive every
session and apply to subagents.

A *phalanx* is a disciplined formation of specialists advancing in lockstep. That's
the model: you operate as a full org of world-class specialists, and at any moment
only the **active phase's team** is on the clock — so you don't burn tokens on a team
that isn't working.

> Not a prompt you paste and hope it sticks. Phalanx installs **SessionStart anchors**
> (re-inject the rules every session) and **PreToolUse gates** (block the wrong move
> before it happens): no code before a plan, no commit before a verify, no TypeScript
> without Effect, no code without Clean Architecture, no hard-coded secret.

## Install

```sh
git clone https://github.com/<you>/claude-phalanx ~/.claude/phalanx
~/.claude/phalanx/install.sh                 # add PHALANX_CRON=1 for daily auto-update
# Windows:  & $env:USERPROFILE\.claude\phalanx\install.ps1
```

Requires `node`. Idempotent — re-run any time. It **merges** into your `settings.json`
and `CLAUDE.md` (never clobbers; your keys win on conflict; a backup is made), copies
skills/hooks/templates, `node --check`s the gates, and runs the verify simulations.
Gates + plugins activate on the **next** session; skills are usable immediately.

Install as a **git checkout** (above) so updates are a `git pull`.

When `CLAUDE_DIR` is your home default (`~/.claude`), `install.sh` writes hook
commands as `$HOME/.claude/...` so they resolve even if the same config dir is
mounted at different paths for different users/containers (a shared mount).
Override with `PHALANX_HOOK_BASE=/abs/path` if you need a fixed absolute base.

## Staying current

Phalanx is the canonical source; track it with a daily cron (chosen update mode):

```sh
PHALANX_CRON=1 ~/.claude/phalanx/install.sh    # installs: 0 5 * * *  git pull --tags && ./install.sh
```

Pulls the latest **release tag** (not `main`) each morning and reinstalls if changed.
Windows: a daily Task Scheduler job running `git pull --tags; ./install.ps1`.

## Per-project / per-repo

```sh
cp ~/.claude/phalanx-templates/state/build.json   <project>/.claude-state.json   # or maintain / optimize
cp ~/.claude/phalanx-templates/.dependency-cruiser.js  <ts-repo>/.dependency-cruiser.js
echo '.claude-state.json' >> <project>/.gitignore     # machine-local; don't commit
```

`.claude-state.json` = `{ "mode": "build|maintain|optimize", "phase": "<id>", "flags": {} }`.
`install.sh` also creates `MEMORY_DIR` (default `~/.claude/memory`) with a `MEMORY.md` index.

## The model

**Modes & phases** (`.claude-state.json`; the SessionStart `phase-anchor` injects ONLY
the active phase, so dormant teams cost nothing):

- **build** — brainstorm → research → architecture → plan → design → implement → review → security → verify → commit → memory
- **maintain** — comprehend → characterize → plan-change → implement → review → security → verify → commit → memory
- **optimize** — baseline → profile → hypothesize → implement → benchmark → verify → commit → memory *(requires observability)*

Each phase has an exit gate that advances it. Trivial work (typo, one-liner, no
auth/API/data-model touch) skips phases. Say `/mode <m>`, `/phase <id>`, `/phase next`.

**Always-on standards (all modes):** Clean Architecture (deps inward, ports+adapters,
one composition root — checked mechanically by `arch-enforce`/dependency-cruiser);
typed errors + schema per language (TS = Effect 3.x); observability on every I/O
boundary; adversarial review (`edge-hunter` then `adversary-review` — harsh grade +
a working diff per finding).

**What's enforced by gates:** no code edit before a plan/spec · no `git commit` before a
verify (test / `tsc --noEmit` / lint / arch-enforce / Playwright) · TS edits need the
`effect-ts` skill consulted · any code edit needs `clean-architecture` consulted ·
hard-coded credentials blocked at write-time and at commit-time (gitleaks → trufflehog →
regex).

## Override flags

- `touch ~/.claude/.pipeline-off`      → "stop pipeline"
- `touch ~/.claude/.ts-arch-off`       → "stop effect" / "stop clean-arch"
- `touch ~/.claude/.secret-scan-off`   → disable secret scan
- `export PHALANX_WARN=1`              → gates warn instead of hard-block
- caveman comms: say "stop caveman" / "normal mode"

## Plugins

The pipeline phases use plugins (merged into `settings.json`): `product-management`,
`adr-kit`, `frontend-design`, `playwright`, `ponytail`. Other phase skills are built
into Claude Code; if one isn't present in your build, that phase is done manually — the
pipeline degrades gracefully, it never blocks on a missing plugin.

## Safety

**Built-in Claude Code safety/security rules always win.** Phalanx governs brevity,
discipline, and structure — never authorization or destructive-action confirmation. The
gates are conveniences with documented off-switches, not a sandbox.

## Leak guard (never push private data)

`install.sh` installs a git **leak guard** by default (`PHALANX_NO_GUARDS=1` to skip):

- a `pre-push` hook (installed globally via `core.hooksPath` → `~/.claude/githooks`, but
  **scoped to act ONLY on the claude-phalanx remote** — your other/private repos are never
  touched) that **blocks any push** to the public repo containing secrets (AWS/GCP keys,
  private keys, GitHub/Slack/Stripe/MCP tokens, hardcoded credential assignments) OR any
  added line matching your **local denylist** at `~/.claude/.phalanx-leakwords` (one term/ERE
  per line). **That denylist is never committed** — it holds your private infra hostnames,
  internal paths, client/project names, private emails. The repo ships only a generic stub.
  Do NOT add things already public by design (your repo URL, your LICENSE name) or every
  push blocks;
- a `pre-commit` secret scan, also scoped to claude-phalanx checkouts (via origin);
- a server-side **gitleaks GitHub Action** (`.github/workflows/secret-scan.yml`) backstop for
  anything pushed from an un-guarded clone.

Manual audit: `scripts/leak-scan.sh --personal`. False positive on a *non-public* repo:
`git push --no-verify` (never for claude-phalanx).

Auto-update: the daily/6-hourly cron plus a throttled, lock-guarded `phalanx-selfupdate.sh`
SessionStart hook keep every instance on the latest release tag. Disable updates with
`touch ~/.claude/.no-autoupdate`.

## Uninstall

```sh
~/.claude/phalanx/uninstall.sh             # remove skills/hooks/templates + CLAUDE.md block + cron
~/.claude/phalanx/uninstall.sh --settings  # also strip our hook commands (plugins/marketplaces kept)
```

## Layout

```
install.sh / install.ps1 / uninstall.sh
PROMPT.md                        operating prompt (paste into Claude Code)
claude-md/sections.md            §0–§16 source of truth
skills/<name>/SKILL.md           caveman, effect-ts, clean-architecture, caveman-{commit,review,stats},
                                 edge-hunter, adversary-review, optimize-loop, maintain-mode, arch-enforce
hooks/anchors/*.sh               caveman, app-pipeline, ts-arch, phase
hooks/gates/*.js                 pipeline, effect-ca, secret
settings/fragment.json           marketplaces + plugins + hook wiring (merged in)
scripts/*.mjs                    idempotent settings + CLAUDE.md merge
state/*.json                     phase-state templates
configs/.dependency-cruiser.js   Clean-Architecture dependency ruleset
```

MIT licensed.
