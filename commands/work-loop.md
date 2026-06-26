---
description: Kick off the UNATTENDED outer loop (run-work) for the current repo — runs /work in fresh processes until backlog empty, blocked, or capped. For a single in-session pass, use /work instead.
---

Start the outer autonomy loop for the current repo. This runs the wrapper, which re-invokes /work in fresh processes (fresh context each pass) until TASKS.md is empty, a BLOCKED line appears, or MaxPasses is hit.

Steps:
1. Confirm `./TASKS.md` exists with at least one `- [ ]`. If missing, copy the template from `${CLAUDE_DIR}/TASKS.template.md`, tell me to fill it, and stop.
2. Detect OS and launch the matching wrapper as a BACKGROUND process so this session stays responsive:
   - Windows: `powershell -ExecutionPolicy Bypass -File "${CLAUDE_DIR}/run-work.ps1" -Repo "<cwd>"`
   - Linux/macOS: `"${CLAUDE_DIR}/run-work.sh" -r "<cwd>"`
3. Report: the launched command, where logs go (`<repo>/.claude-runs/`), and the three stop conditions. Do NOT stream the whole run into this session — point me at the logs.

Note: /work-loop = walk-away mode (many passes, own processes). /work = one pass in THIS session. Use /work first on a new repo to watch one pass before trusting the loop.
