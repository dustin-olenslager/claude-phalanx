# Hermes harness adapter

The gates in `hooks/gates/` are Claude Code stdin-JSON programs, wired only through `$CLAUDE_DIR/settings.json`.
A Hermes agent never fires them. This adapter is the Hermes binding — the same intent (a hard
pre-flight gate), expressed in the harness Hermes actually runs.

## `panoply_gate.py` — the Panoply kit gate

**What it enforces:** a repo whose Panoply kit is absent, half-applied, stale, or unadapted must not
be modified. Adopting the kit *is* the first batch of work in that repo. The gate returns the adoption
command in its block message, so the agent is told exactly what to do instead of just being stopped.

**Why a plugin and not prose:** in Hermes, only a `pre_tool_call` **plugin hook** actually blocks —
memory is documented as advisory, and `skills.auto_load` is skipped for `delegate_task` subagents
entirely. Plugin hooks are process-global, so they **do** fire inside subagents. This is therefore the
one mechanism that reaches every agent, parent and child.

## Install (as a Hermes plugin)

```sh
mkdir -p ~/.hermes/plugins/panoply-gate
cp adapters/gates/hermes/panoply_gate.py ~/.hermes/plugins/panoply-gate/__init__.py
printf 'name: panoply-gate\nversion: "1.0.0"\ndescription: Panoply kit pre-flight gate\nprovides_hooks:\n  - pre_tool_call\n' \
  > ~/.hermes/plugins/panoply-gate/plugin.yaml
hermes plugins enable panoply-gate
hermes plugins doctor panoply-gate --ci     # expect: 1 hook(s), import OK
```

The gate finds a Panoply doctor in this order: the repo's own `scripts/panoply.sh`, then
`PANOPLY_KIT_ROOT`/`$HOME/.panoply`/`$HOME/.cache/panoply`/`$HOME/panoply`. A repo that has already
adopted the kit is checked by **its own** doctor, so it is judged against the version it pinned.

## Verify it actually works

```sh
python3 adapters/gates/hermes/test_panoply_gate.py
```

22 assertions: blocks `write_file`/`patch`/mutating `terminal` in an un-kitted repo; allows read-only
commands (pre-flight is read-only, so blocking inspection would be self-defeating), allows the
adoption commands themselves (otherwise the gate is unsatisfiable), allows non-repo paths, honours the
escape hatch, and — the positive control that separates "detects nothing" from "detects correctly" —
allows a compliant repo.

## Deliberate design choices

- **Fail open on its own errors.** A gate that blocks everything when broken is indistinguishable
  from a broken repo. It blocks on a *finding*, never on a failure.
- **Cheap.** The doctor is a subprocess, so the result is cached per repo for the process lifetime.
- **Read-only is never gated.** The dev-workflow's pre-flight is itself read-only; gating it would stop
  an agent from even discovering what state the repo is in.
- **Escape hatches are declared, not silent:** `PANOPLY_GATE_OFF=1` (this gate) and `PANOPLY_OFF=1`
  (the doctor). An agent that uses one should say so, so the exception is reviewed rather than assumed.

## `caveman_anchor.py` — the caveman reply budget

**What it enforces:** the budget that `hooks/anchors/caveman-anchor.sh` installs for Claude Code
(already always-on there via `settings/fragment.json`), put in front of a Hermes agent AND its
`delegate_task` subagents. ≤40 words / ≤4 lines by default; exact code, paths, SHAs, commands, errors;
full English for safety confirmations, plan/PR bodies, code comments and handoffs.

**Why `pre_llm_call` and not a skill:** `skills.auto_load` is skipped for subagents entirely, so a skill
only applies when the agent chooses to load it — and the point of an anchor is that the budget applies
when nobody remembered to ask. `pre_llm_call` is process-global, so it reaches parent and child alike.

The gate above uses `pre_tool_call` because its job is to **block**; a cognitive budget cannot be
blocked, only put in front of the agent. That is the whole difference between the two adapters.

### Install

```sh
mkdir -p ~/.hermes/plugins/caveman
cp adapters/gates/hermes/caveman_anchor.py ~/.hermes/plugins/caveman/__init__.py
printf 'name: caveman\nversion: "1.0.0"\ndescription: caveman reply budget\nprovides_hooks:\n  - pre_llm_call\n' \
  > ~/.hermes/plugins/caveman/plugin.yaml
hermes plugins enable caveman
```

### Verify

```sh
python3 adapters/gates/hermes/test_caveman_anchor.py
```

16 assertions: injects the budget on a normal turn; carries the exactness and exemption rules; both OFF
switches (`CAVEMAN_OFF=1`, and `stop caveman`/`normal mode` in the user's message) work; `caveman` alone
**re-anchors rather than disabling**; every message shape is read; and — the property that matters most —
it **fails open** on malformed payloads, because a raising callback on this channel would cost the turn.

## Deliberate design choices

- **Fails open, always.** A budget that occasionally fails to inject costs tokens; one that throws costs
  the conversation.
- **Exemptions are load-bearing.** Compressing a safety confirmation to save tokens is the one trade
  this must never make.
- **The override is the user's.** `stop caveman` / `normal mode` disables it for that turn, matching
  `skills/caveman/SKILL.md`.
