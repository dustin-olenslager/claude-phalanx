---
name: caveman-stats
description: >
  Report real token usage + estimated caveman savings for the current session by
  reading the Claude Code session transcript (JSONL). Computes nothing it cannot
  read from the log. Trigger: "/caveman-stats", "token stats", "how many tokens".
license: MIT
---

# caveman-stats

Reads the session transcript and reports actual token counts. Does NOT estimate
what it can't read.

## Where the data is
Claude Code writes a per-session JSONL transcript (assistant/user/tool messages),
typically under the projects/transcripts dir of CLAUDE_DIR (path varies by
build/version). Each assistant message carries a `usage` object with
`input_tokens`, `output_tokens`, `cache_read_input_tokens`,
`cache_creation_input_tokens`.

## Process
1. Locate the current session's JSONL (most-recently-modified transcript for
   this project, or the one whose session_id matches).
2. Sum `input_tokens`, `output_tokens`, and cache fields across assistant turns.
3. Report: total in/out, cache hit ratio, output tokens/turn.
4. Savings estimate (label it an ESTIMATE): caveman trims prose ~70%; apply only
   to the prose share of output (exclude code/tool args). State the assumption.

## If the fields aren't present
Different builds expose usage differently. If you cannot find token fields, SAY
SO and report what is available — never fabricate numbers.

## Output (caveman)
```
tokens: in <N> / out <N> · cache-read <N> (<P>%)
out/turn: <N> over <T> turns
est caveman saving: ~<P>% of prose output (assumption: prose≈<P> of out)
```
