#!/usr/bin/env python3
"""Prove the panoply-gate plugin's decision function actually blocks and actually allows.

The whole point of the gate is that it BLOCKS in the bad case and PASSES in the good case. A gate
that always blocks is indistinguishable from a broken repo; one that never blocks is decoration.
This asserts both directions, plus the escape hatches, by calling _on_pre_tool_call directly.
"""
import importlib.util, os, subprocess, sys, tempfile, shutil
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent / "panoply_gate.py"
spec = importlib.util.spec_from_file_location("panoply_gate", PLUGIN)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

pass_ = 0; fail = 0
def ok(n):   global pass_; pass_ += 1; print(f"  ok   {n}")
def bad(n, w): global fail; fail += 1; print(f"  FAIL {n} — {w}")

def mk_repo(name, with_kit=False):
    p = Path(tempfile.mkdtemp(prefix=f"gate-{name}-"))
    subprocess.run(["git", "init", "-q", str(p)], check=True)
    (p / "README.md").write_text("x\n")
    subprocess.run(["git", "-C", str(p), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(p), "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-qm", "init"], check=True)
    return p

def expect_block(name, tool, args, want_block=True):
    mod._CACHE.clear()
    r = mod._on_pre_tool_call(tool_name=tool, args=args)
    blocked = isinstance(r, dict) and r.get("action") == "block"
    if blocked == want_block:
        ok(f"{name} ({'blocked' if blocked else 'allowed'})")
    else:
        bad(name, f"want block={want_block} got {r!r}")

# A repo with NO kit -> writing into it must be BLOCKED.
bare = mk_repo("bare")
expect_block("bare repo: write_file blocked", "write_file", {"path": str(bare / "src" / "a.py")}, True)
expect_block("bare repo: patch blocked",      "patch",      {"path": str(bare / "src" / "a.py")}, True)
expect_block("bare repo: terminal blocked",   "terminal",   {"command": "echo hi > f", "workdir": str(bare)}, True)

# Outside any git repo -> must ALWAYS be allowed (never block non-repo work).
outside = Path(tempfile.mkdtemp(prefix="gate-norepo-"))
expect_block("non-repo dir: write allowed", "write_file", {"path": str(outside / "x.txt")}, False)

# The adoption command itself -> must ALWAYS be allowed, or the gate is unsatisfiable.
expect_block("adoption command allowed", "terminal",
             {"command": "sh /kit/scripts/panoply.sh apply", "workdir": str(bare)}, False)

# Read-only tools -> never blocked.
expect_block("read_file never blocked", "read_file", {"path": str(bare / "README.md")}, False)

# Escape hatch.
os.environ["PANOPLY_GATE_OFF"] = "1"
expect_block("PANOPLY_GATE_OFF allows everything", "write_file", {"path": str(bare / "a.py")}, False)
del os.environ["PANOPLY_GATE_OFF"]

# A repo that HAS the kit and is current -> must be ALLOWED (the positive control).
# Reuse the real panoply kit repo (it is the template, so it reports current).
kit = Path("/opt/data/cache/scratch/panoply-kit")
if (kit / ".git").exists():
    mod._CACHE.clear()
    ok_, detail = mod._check(str(kit))
    if ok_:
        ok(f"compliant repo allowed ({detail})")
        expect_block("compliant repo: write allowed", "write_file", {"path": str(kit / "scripts" / "x.sh")}, False)
    else:
        bad("compliant repo", f"expected the kit repo to pass, got: {detail}")
else:
    print("  skip compliant-repo case (kit clone not present)")


# Read-only terminal commands must NEVER be blocked — pre-flight is read-only.
for c in ("ls -la", "git status --porcelain", "git log --oneline -3", "cat README.md",
          "grep -rn foo .", "git diff --stat", "find . -name '*.py'", "git branch -a"):
    expect_block(f"readonly allowed: {c[:28]}", "terminal", {"command": c, "workdir": str(bare)}, False)

# Mutating terminal commands in a bare repo MUST be blocked.
for c in ("echo hi > f.txt", "rm -rf src", "git commit -m x", "mkdir -p app", "sed -i s/a/b/ f"):
    expect_block(f"mutating blocked: {c[:28]}", "terminal", {"command": c, "workdir": str(bare)}, True)

shutil.rmtree(bare, ignore_errors=True)
shutil.rmtree(outside, ignore_errors=True)
print()
if fail == 0:
    print(f"PANOPLY-GATE.TEST: all green ({pass_} checks)"); sys.exit(0)
print(f"PANOPLY-GATE.TEST: FAILED ({pass_} ok, {fail} failed)"); sys.exit(1)
