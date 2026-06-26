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
