"""panoply_gate.py — a Hermes pre_tool_call gate that makes kit adoption unavoidable.

Why a plugin and not a skill or a memory line: only a `pre_tool_call` hook actually BLOCKS, and
Hermes fires plugin hooks inside `delegate_task` subagents too (same process, process-global hook
manager). `skills.auto_load` does not reach subagents at all (system_prompt.py skips auto-load when
skip_context_files is set), and memory is explicitly advisory. So this is the one mechanism that
reaches every agent, parent and child.

Contract (hermes_cli/plugins.py VALID_HOOKS / plugins_dispatch):
  register(ctx); ctx.register_hook("pre_tool_call", cb)
  cb(**kwargs) -> {"action": "block", "message": "..."} vetoes the call; anything else allows it.
  Hook callback errors/timeouts fail CLOSED on pre_tool_call.

Design rules this gate follows, learned from building it:
  * It must be CHEAP. It runs before every matching tool call, so the expensive check is cached per
    repo for the process lifetime.
  * It must never block legitimate work OUTSIDE a repo. No git root -> allow.
  * It must never block the ADOPTION itself. The tools used to apply the kit are allowed through, or
    the gate would be unsatisfiable and every agent would have to disable it.
  * It must fail OPEN on its own errors. A broken gate that blocks all writing is worse than no gate
    (and would be indistinguishable from a broken repo). We block on a *finding*, not on a failure.
  * Escape hatches exist and are deliberate: PANOPLY_GATE_OFF=1 disables it entirely.
"""

from __future__ import annotations

import logging
import os
import subprocess
import sys
import time
from pathlib import Path

logger = logging.getLogger("plugins.panoply-gate")

# Tools that can change a repository. Read-only tools are never blocked: reading is how an agent
# discovers the state in the first place.
MUTATING_TOOLS = {"write_file", "patch"}

# The documentation spine that EVERY gate's remedy depends on. Writing a plan doc, a rule module, a
# worklog, or a governance note is how an agent fixes a repo's state — including this gate's own
# "apply the kit, then retry" remedy, and including the Algorithm gate's remedy (adding a plan doc's
# Deletion candidates section). Blocking a write here makes the gate unsatisfiable: the agent cannot
# perform the fix it was just told to perform. Observed live 2026-10-01 — panoply-gate and the
# Algorithm gate deadlocked each other exactly here, in a half-applied repo.
#
# This is NOT a bypass. The kit's own landing gates (check-docs.sh, check-plan-home.sh,
# check-algorithm.sh, check-doc-refs.sh) judge the docs spine in CI, where they cannot be skipped —
# which is the correct plane for a docs rule. A pre-flight gate exists to stop CODE from landing in a
# repo that has not adopted the kit; prose is not that.
DOC_SPINE_PREFIXES = ("docs/", ".claude/", ".claude-kit-tmp/")
DOC_SPINE_NAMES = ("AGENTS.md", "CLAUDE.md", "CHANGELOG.md", "README.md", "CONVENTIONS.md", "GEMINI.md")
DOC_SPINE_EXTS = (".md", ".mdx", ".yaml", ".yml")

# The adoption commands. An agent must be able to run these in a repo that fails the check, or the
# gate is unsatisfiable — it would block the very work it is demanding.
ADOPTION_MARKERS = ("panoply.sh", "phalanx-project.sh", "adapt-claude-setup", "apply-kit.sh")

# Terminal commands that only READ. These must never be gated: the dev-workflow's pre-flight is
# itself read-only (survey branches, read the plan, inspect the tree), so blocking inspection would
# make the rule self-defeating — an agent could not even look at the repo to learn it needs the kit.
READONLY_CMDS = (
    "ls", "cat", "head", "tail", "less", "more", "wc", "file", "stat", "find", "fd", "tree",
    "grep", "rg", "ag", "pwd", "whoami", "env", "printenv", "echo", "which", "command",
    "git status", "git log", "git diff", "git show", "git branch", "git remote", "git config --get",
    "git rev-parse", "git describe", "git tag", "git worktree list", "git stash list",
    "git fetch", "git ls-files", "git blame", "date", "jq", "sed -n", "awk", "python3 -c", "test",
)
# A shell redirect or one of these verbs means the command can change the tree.
MUTATING_HINTS = (
    ">", ">>", "rm ", "rmdir", "mv ", "cp ", "mkdir", "touch", "chmod", "chown", "ln ",
    "sed -i", "tee ", "dd ", "truncate", "git add", "git commit", "git push", "git merge",
    "git rebase", "git reset", "git checkout", "git switch", "git restore", "git apply",
    "git clean", "git stash", "npm ", "pnpm ", "yarn ", "pip ", "uv ", "cargo ", "go build",
    "make", "docker ", "hermes config set",
)


def _terminal_is_mutating(cmd: str) -> bool:
    """True only if a terminal command can change the working tree.

    Default is ALLOW: an unknown command is treated as read-only, because wrongly blocking the
    read-only pre-flight is worse than wrongly allowing a rare mutation (which the STANDARD gate and
    CI still catch). The mutating hints are deliberately explicit rather than heuristic.
    """
    c = cmd.strip()
    if not c:
        return False
    # Our own adoption/inspection commands are always allowed.
    if any(m in c for m in ADOPTION_MARKERS):
        return False
    # Strip a leading env assignment or `cd X &&` so the real verb is what we test.
    for prefix in ("export ", "set "):
        if c.startswith(prefix):
            return False
    head = c.split("&&")[-1].strip()
    if any(h in head for h in MUTATING_HINTS):
        return True
    # Explicitly read-only verbs win over a stray hint elsewhere in the string.
    if head.split(" ", 1)[0].split("/")[-1] in {r.split()[0] for r in READONLY_CMDS}:
        return False
    return bool(any(h in head for h in MUTATING_HINTS))

# Per-process cache: repo root -> (ok: bool, detail: str, checked_at: float). The doctor is a
# subprocess; running it on every write would be wasteful and slow.
#
# The cache MUST expire, and it must expire FASTER on a deny than on an allow. This is not a
# performance nicety — it is what makes the gate satisfiable:
#   * A verdict is a snapshot of mutable state. Cache it forever and a repo that adopts the kit
#     mid-session keeps its pre-adoption DENY for the process lifetime, so the gate's own remedy
#     ("apply the kit, then retry") is impossible to complete — the agent applies the kit, the
#     doctor reports `kit applied and current`, and the next write is still refused by a finding
#     that is no longer true. That deadlock is reported verbatim by the gate's own message, which
#     tells the agent to retry after applying, and then silently refuses the retry.
#   * A stale ALLOW is the opposite hazard: the kit can be removed or bumped later in the session,
#     so even a passing repo is re-verified eventually.
# Denials are therefore re-checked on a short TTL (the doctor is cheap; a few dozen ms) while
# allows get a long one. Within a burst — the normal case, many writes to one repo — the cache
# still does its job.
_CACHE: dict[str, tuple[bool, str, float]] = {}
_DENY_TTL_SECONDS = 15.0
_ALLOW_TTL_SECONDS = 300.0


def _forget(root: str) -> None:
    """Drop any cached verdict for a repo so the next check re-runs the doctor.

    Called when an ADOPTION command runs against a repo: adoption is the one event the gate itself
    says changes the verdict, so continuing to serve the pre-adoption answer would be serving a
    result the gate has already declared obsolete.
    """
    _CACHE.pop(root, None)

# Where to find a kit clone. The gate locates the doctor (repo-local first, then these), so a repo
# that has already adopted the kit is checked with its OWN doctor — the version it pins — and a repo
# that has not is judged by this canonical clone.
KIT_CLONE_HINTS = (
    "/opt/data/panoply-kit",
    os.path.expanduser("~/.panoply"),
    os.path.expanduser("~/.cache/panoply"),
    os.path.expanduser("~/panoply"),
    "/opt/data/cache/scratch/panoply-kit",
)


def _repo_root(cwd: str) -> str | None:
    """The git root containing cwd/path, or None. Uses `git rev-parse` so worktrees work.

    The path may not exist yet (a new file in a new directory is the common case for write_file), so
    walk up to the nearest existing ancestor first. Without this, gating a fresh file silently finds
    no repo and allows it — a hole the canary caught.
    """
    if not cwd:
        return None
    probe = os.path.abspath(cwd)
    if not os.path.exists(probe):
        probe = os.path.dirname(probe)
    while probe and not os.path.isdir(probe):
        nxt = os.path.dirname(probe)
        if nxt == probe:
            return None
        probe = nxt
    if not probe or not os.path.isdir(probe):
        return None
    try:
        out = subprocess.run(
            ["git", "-C", probe, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    root = out.stdout.strip()
    return root or None


def _find_doctor(root: str) -> str | None:
    """Locate a panoply doctor: in the repo itself, else a known kit clone."""
    local = Path(root) / "scripts" / "panoply.sh"
    if local.is_file():
        return str(local)
    for hint in KIT_CLONE_HINTS:
        cand = Path(hint) / "scripts" / "panoply.sh"
        if cand.is_file():
            return str(cand)
    return None


def _check(root: str) -> tuple[bool, str]:
    """(ok, detail) for a repo. Cached with a TTL — see _CACHE. No doctor = ok (we cannot judge)."""
    hit = _CACHE.get(root)
    if hit is not None:
        ok_c, detail_c, at = hit
        ttl = _ALLOW_TTL_SECONDS if ok_c else _DENY_TTL_SECONDS
        if (time.monotonic() - at) < ttl:
            return ok_c, detail_c
        # Expired: re-run the doctor rather than serving a verdict about a state that may have
        # changed. The allow path only reaches here after minutes; the deny path after seconds, so
        # an agent that has just adopted the kit sees the truth on its next write.
        _CACHE.pop(root, None)

    doctor = _find_doctor(root)
    if not doctor:
        _CACHE[root] = (True, "no panoply doctor available", time.monotonic())
        return _CACHE[root][0], _CACHE[root][1]
    try:
        out = subprocess.run(
            ["sh", doctor, "check"],
            cwd=root, capture_output=True, text=True, timeout=20,
            env={**os.environ, "PANOPLY_GATE_CHILD": "1"},
        )
    except Exception as exc:  # noqa: BLE001 — fail OPEN, see module docstring
        logger.warning("panoply-gate: doctor errored in %s: %s", root, exc)
        _CACHE[root] = (True, f"doctor errored: {exc}", time.monotonic())
        return _CACHE[root][0], _CACHE[root][1]

    if out.returncode == 0:
        detail = "kit applied and current"
        _CACHE[root] = (True, detail, time.monotonic())
        return _CACHE[root][0], _CACHE[root][1]

    reason = (out.stderr or out.stdout or "").strip().splitlines()
    detail = reason[0] if reason else f"panoply check exited {out.returncode}"
    _CACHE[root] = (False, detail, time.monotonic())
    return _CACHE[root][0], _CACHE[root][1]


def _target_repo(tool_name: str, args: dict) -> str | None:
    """The repo a mutating call is actually aimed at."""
    if tool_name in MUTATING_TOOLS:
        p = args.get("path") or args.get("file_path") or ""
        if not p:
            return None
        d = p if os.path.isdir(p) else os.path.dirname(p) or "."
        return _repo_root(d)
    if tool_name == "terminal":
        cmd = args.get("command") or ""
        if not _terminal_is_mutating(cmd):
            return None
        return _repo_root(args.get("workdir") or os.getcwd())
    return None


def _is_doc_spine(path: str) -> bool:
    """True if *path* is documentation/rules prose rather than code.

    The docs spine is where every gate's remedy lands, so it is never blocked — see
    DOC_SPINE_PREFIXES. Deliberately generous: a false "it is docs" merely defers to CI's docs gates
    (which cannot be skipped), while a false "it is code" deadlocks the remedy the gate prescribes.
    """
    p = (path or "").replace("\\", "/").lstrip("./")
    if not p:
        return False
    base = p.rsplit("/", 1)[-1]
    if any(p.startswith(prefix) for prefix in DOC_SPINE_PREFIXES):
        return True
    if base in DOC_SPINE_NAMES:
        return True
    # A markdown/rule file anywhere (a rules module, a worklog, a plan) is prose, not code.
    return base.endswith(DOC_SPINE_EXTS)


def _is_adoption(tool_name: str, args: dict) -> bool:
    if tool_name == "terminal":
        return any(m in (args.get("command") or "") for m in ADOPTION_MARKERS)
    if tool_name == "read_file":
        return "panoply" in str(args.get("path", ""))
    if tool_name in MUTATING_TOOLS:
        # Writing the docs spine IS the remedy (both for this gate and for the Algorithm gate).
        return _is_doc_spine(str(args.get("path") or args.get("file_path") or ""))
    return False


def _on_pre_tool_call(tool_name: str = "", args: dict | None = None, **_kw):
    if os.environ.get("PANOPLY_GATE_OFF") == "1":
        return None
    if os.environ.get("PANOPLY_GATE_CHILD") == "1":
        return None  # never gate the doctor's own subprocess tree
    args = args or {}
    if _is_adoption(tool_name, args):
        # Adoption is the one event the gate itself declares changes the verdict, so drop any
        # cached answer for the repo being adopted. Without this, a session that started before the
        # adoption keeps serving the pre-adoption deny and the retry the gate asks for can never
        # succeed. (Belt and braces with the deny TTL: this makes it immediate, not eventual.)
        if tool_name == "terminal":
            root = _repo_root(args.get("workdir") or os.getcwd())
            if root:
                _forget(root)
        return None
    if tool_name not in MUTATING_TOOLS and tool_name != "terminal":
        return None

    root = _target_repo(tool_name, args)
    if not root:
        return None

    ok, detail = _check(root)
    if ok:
        return None

    msg = (
        f"Panoply kit gate: refusing to modify {root} — {detail}\n\n"
        "This repo does not carry the current Panoply kit. Per the standing house rule the FIRST "
        "batch of work in a repo is adopting the kit (never skipping it). Do this, then retry:\n\n"
        "    panoply_kit_root=\"${PANOPLY_KIT_ROOT:-$HOME/.panoply}\"\n"
        "    sh \"$panoply_kit_root/scripts/panoply.sh\" apply   # deterministic half + agent checklist\n"
        "    sh \"$panoply_kit_root/scripts/panoply.sh\" check   # must exit 0\n\n"
        "Then finish the judgement half the checklist names (fill every {{TOKEN}}, prune non-applying "
        "MODULE: blocks) and run `sh scripts/sync-agents.sh`. If this is a deliberate exception, say "
        "so to the owner and set PANOPLY_GATE_OFF=1 for that work — do not silently bypass."
    )
    logger.info("panoply-gate blocked %s in %s (%s)", tool_name, root, detail)
    return {"action": "block", "message": msg}


def register(ctx):
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    logger.info("panoply-gate registered pre_tool_call")
