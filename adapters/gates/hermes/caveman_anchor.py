"""caveman_anchor.py — the Hermes binding for caveman mode.

`hooks/anchors/caveman-anchor.sh` is a Claude Code `SessionStart` program, wired only through
`$CLAUDE_DIR/settings.json`. A Hermes agent never fires it. This adapter is the Hermes binding — the
same intent (the reply budget, always on), expressed in the harness Hermes actually runs.

WHY `pre_llm_call` AND NOT A SKILL
----------------------------------
In Hermes, `skills.auto_load` is skipped for `delegate_task` subagents entirely
(`agent/system_prompt.py` returns early on `skip_context_files`), and memory is documented as
advisory. A skill therefore loads only when the agent chooses to load it — but the point of an anchor
is that the budget applies when nobody remembered to ask for it. `pre_llm_call` is the one channel
that reaches every agent, parent and child: plugin hooks are process-global, and the returned
`{"context": ...}` is appended to the user message on every model call.

The gate adapter next door uses `pre_tool_call` because its job is to BLOCK. This one uses
`pre_llm_call` because a cognitive budget cannot be blocked — it can only be put in front of the agent.

INSTALL (same shape as the gate adapter)
----------------------------------------
    mkdir -p ~/.hermes/plugins/caveman
    cp adapters/gates/hermes/caveman_anchor.py ~/.hermes/plugins/caveman/__init__.py
    printf 'name: caveman\nversion: "1.0.0"\ndescription: caveman reply budget\nprovides_hooks:\n  - pre_llm_call\n' \
      > ~/.hermes/plugins/caveman/plugin.yaml
    hermes plugins enable caveman

VERIFY
------
    python3 adapters/gates/hermes/test_caveman_anchor.py
"""

from __future__ import annotations

import os

# The budget block. Kept as one literal so the port is diffable against Phalanx's
# hooks/anchors/caveman-anchor.sh, which injects the same rules as a SessionStart directive.
BUDGET = """CAVEMAN MODE ACTIVE (always-on, CLAUDE.md §0).

REPLY BUDGET, hard: default reply <= 40 words AND <= 4 lines, simplest language that carries the fact.
  Done    -> 1 line (what changed + file:line/sha).
  Blocked -> 2 lines (failure line VERBATIM, then the ONE action needed from the operator).
  Decision-> 1-line question + <= 4 one-line options.
  Read-only ask -> the answer only, not the method.

BANNED always: restating the request, announcing what comes next, prose recap of what was just done,
justifying a choice that worked, caveats nothing hinges on, "let me know if" closers, offers of extra
work.

Overrun ONLY for: options/steps that cannot compress, dangerous ambiguity (security, irreversible,
order-dependent), or the full-English exemptions below. Length != effort: do the deep work, ship the
short answer.

Compress all prose: drop articles + auxiliaries, 1-4 word fragments, periods as separators, lists not
prose-strings, ELI5 explanations, fewest words.

EXACT - never compress: code, file paths, identifiers, numbers, SHAs, commands, error strings, URLs.

FULL ENGLISH required (do not compress): safety/destructive confirmations, plan-mode bodies,
commit/PR bodies, code comments, external-UI walkthroughs, self-contained handoffs or prompts written
for another agent.

Never restate the user's question. Never acknowledge instructions. Never apologize for length then
write long. Say "blocked on X", not a story about trying A then B then C."""


# The override phrase, checked on the user's own message. Phalanx: "Only the user saying 'stop
# caveman' / 'normal mode' disables this."
OFF_PHRASES = ("stop caveman", "normal mode", "stop token", "verbose mode")


def _user_text(kwargs: dict) -> str:
    """Best-effort read of the user's message for this turn.

    The hook passes different shapes depending on call site (``prompt``, ``user_message``,
    ``messages``, ``input``); try each and never raise.
    """
    for key in ("prompt", "user_message", "message", "input"):
        value = kwargs.get(key)
        if isinstance(value, str):
            return value
        if isinstance(value, dict):
            content = value.get("content")
            if isinstance(content, str):
                return content
    messages = kwargs.get("messages")
    if isinstance(messages, list) and messages:
        last = messages[-1]
        if isinstance(last, dict):
            content = last.get("content")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        return part["text"]
    return ""


def _is_off_request(text: str) -> bool:
    lowered = text.lower()
    return any(phrase in lowered for phrase in OFF_PHRASES)


def pre_llm_call(**kwargs):
    """Inject the reply budget + token discipline into this model call.

    Returns ``{"context": ...}`` (appended to the user message) or ``None`` to inject nothing.
    Never raises — a broken injection must not cost the turn.
    """
    try:
        if os.environ.get("CAVEMAN_OFF") == "1":
            return None
        if _is_off_request(_user_text(kwargs)):
            return None
        return {"context": BUDGET}
    except Exception:  # noqa: BLE001 - fail open, always
        return None


def register(ctx):
    ctx.register_hook("pre_llm_call", pre_llm_call)
