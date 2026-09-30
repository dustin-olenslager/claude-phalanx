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
