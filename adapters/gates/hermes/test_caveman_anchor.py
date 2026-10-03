"""Canary for caveman_anchor.py.

Same doctrine as the kit's gate self-tests: a hook that injects nothing and a hook that injects
correctly are indistinguishable unless you assert BOTH directions. This proves the budget actually
reaches the model call, that both OFF switches work, and — most importantly — that the hook FAILS
OPEN, because a callback that raises on this channel would cost the whole turn.

Run:  python3 adapters/gates/hermes/test_caveman_anchor.py
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def _load():
    spec = importlib.util.spec_from_file_location("caveman_plugin", HERE / "caveman_anchor.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


passed = 0
failed = 0


def ok(name):
    global passed
    passed += 1
    print(f"  ok   {name}")


def bad(name):
    global failed
    failed += 1
    print(f"  FAIL {name}")


def main():
    mod = _load()

    # --- 1. the budget actually reaches the call (positive control) ----------
    result = mod.pre_llm_call(prompt="add a login form")
    if isinstance(result, dict) and "REPLY BUDGET" in result.get("context", ""):
        ok("injects the reply budget on a normal turn")
    else:
        bad(f"budget was not injected; got {result!r}")

    # --- 2. the exactness + exemption rules ride along ----------------------
    text = (result or {}).get("context", "")
    for needle, label in (
        ("EXACT - never compress", "exactness rule present"),
        ("FULL ENGLISH required", "exemption rule present"),
        ("BANNED always", "banned-construction list present"),
    ):
        if needle in text:
            ok(label)
        else:
            bad(f"{label} — '{needle}' missing")

    # --- 3. CAVEMAN_OFF=1 lifts it ------------------------------------------
    import os

    os.environ["CAVEMAN_OFF"] = "1"
    try:
        if mod.pre_llm_call(prompt="anything") is None:
            ok("CAVEMAN_OFF=1 lifts the injection")
        else:
            bad("CAVEMAN_OFF=1 did not lift the injection")
    finally:
        del os.environ["CAVEMAN_OFF"]

    # --- 4. the user's own override lifts it -------------------------------
    for phrase in ("stop caveman", "normal mode", "NORMAL MODE"):
        if mod.pre_llm_call(prompt=phrase) is None:
            ok(f"'{phrase}' turns it off for the turn")
        else:
            bad(f"'{phrase}' did not turn it off")

    # --- 5. a phrase merely CONTAINING the word is not an override ---------
    # "caveman" alone is Phalanx's RE-ANCHOR trigger, not its off switch. Getting this backwards
    # would silently disable the budget for anyone who mentions the mode.
    if mod.pre_llm_call(prompt="caveman") is not None:
        ok("'caveman' alone re-anchors rather than disabling")
    else:
        bad("'caveman' alone wrongly disabled the injection")

    # --- 6. other message shapes are read -----------------------------------
    shapes = {
        "messages list": {"messages": [{"role": "user", "content": "ship it"}]},
        "dict content": {"prompt": {"content": "patch the gate"}},
        "content parts": {"messages": [{"role": "user", "content": [{"type": "text", "text": "go"}]}]},
    }
    for label, kwargs in shapes.items():
        got = mod.pre_llm_call(**kwargs)
        if isinstance(got, dict) and "REPLY BUDGET" in got.get("context", ""):
            ok(f"reads the prompt from {label}")
        else:
            bad(f"did not read the prompt from {label}")

    # --- 7. FAIL OPEN: a malformed payload must not raise -------------------
    class Boom:
        def __str__(self):
            raise RuntimeError("hostile __str__")

    for label, payload in (
        ("None kwarg", {"prompt": None}),
        ("wrong-typed messages", {"messages": "not-a-list"}),
        ("hostile content object", {"prompt": {"content": Boom()}}),
        ("no kwargs at all", {}),
    ):
        try:
            mod.pre_llm_call(**payload)
            ok(f"fails open on {label}")
        except Exception as exc:  # noqa: BLE001
            bad(f"{label} RAISED ({exc!r}) — this would cost the turn")

    print(f"\ncaveman canary: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
