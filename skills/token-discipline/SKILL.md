---
name: token-discipline
description: Token and context discipline for AI coding agents. Apply always — governs input loading (just-in-time over just-in-case), output length (compress prose, never artifacts), tool design (every tool justifies existence), subagent use (context isolation not parallelism), and bridge files for long-horizon work. Use whenever the agent reads context files, makes file operations, decides what to load, plans multi-session work, or considers spawning subagents. Load references/full.md when working on agent rule files, prompt engineering, context optimization, or building skills.
---

# Token Discipline

Smallest set of high-signal tokens that maximizes likelihood of desired outcome. Context is budget not backpack. Attention degrade with length — fewer tokens often means *better* answers, not just cheaper.

## Always
- `/context` at session start substantive work. Trim before optimize.
- Just-in-time: `glob`, `grep`, `view` to discover; load files when task hit file, not before.
- Bundled (`skills/`, `references/`, `scripts/`) zero tokens til read.
- Compress prose, no compress artifacts. Code, paths, commands, URLs, version numbers, IDs, error messages pass through untouched.
- Output fixed shape — show shape direct (template, JSON skeleton), no describe in prose.
- Read before Edit. Edit before Write. Write only new files or wholesale rewrite.
- Deterministic ops twice+ same way — write script. Script output is only tokens hit context.
- MCP tools fully qualified: `Service:tool_name`, never bare.
- Multi-session work — bridge file (`progress.md` or equiv). End session: update. Start session: read it + `git log`.
- Subagent when task would dump 20K+ tokens intermediate work into main thread. Receive synthesis only.

## Never
- Dump whole repo "just in case" — `grep`/`glob`.
- Restate user question before answer.
- Acknowledge instructions ("Got it, I will now…").
- Apologize for length, then write long.
- Leave dead context loaded — `/clear`.
- Optimize before measure — `/context` first.

## Drop full prose only when ambiguity dangerous
Security warnings, irreversible actions (`rm -rf`, force-push, prod deploys), multi-step order-dependent sequences, user confused or repeating. Everywhere else, telegraphic prose wins.

## Full ruleset
For input/output/tool/memory/multi-agent discipline in depth, plus measurement methodology and anti-pattern catalog, read `references/full.md`.

## Source attribution
Distilled from Anthropic's *Effective Context Engineering for AI Agents* (Sept 2025), *Effective Harnesses for Long-Running Agents*, the Anthropic Skills authoring guide, the Microsoft `agent-skills` progressive-disclosure pattern, `JuliusBrussee/caveman` (~46K stars), `alexgreensh/token-optimizer`, `nadimtuhin/claude-token-optimizer`, and `drona23/claude-token-efficient`.
