---
name: recall-memory
description: >
  Unified MEMORY recall + write (ADR-0004) — query or append to the project's
  memory store (JSONL by default, Obsidian vault or sqlite swappable). Use when
  resuming a project, when the user asks "what do we know about X", or when
  substantial work should be persisted for the next session.
license: MIT
---

# recall-memory

Memory is the unified terminal phase of every mode and the resume mechanism
across sessions. One adapter backs it; the use-case (core/use-cases/recall.js)
never touches fs directly.

## Recall
`node <phalanx>/scripts/phalanx-core.js recall <query> --memory <dir> --cwd <repo>`
- No match → say so plainly; don't invent facts.
- Match → cite name + summary (or snippet). A one-line index entry per fact.

## Write
`node <phalanx>/scripts/phalanx-core.js add-memory --name <n> --type <t> --summary <s> --content <c> --memory <dir> --cwd <repo>`
Types: `user | feedback | project | reference`. One fact per item; absolute
dates; update don't duplicate; delete proven-wrong facts.

## Exit gate
`synced` — substantial work from this session is recorded (new facts added,
stale ones corrected) and recall of prior session answers "what do we know".

## Consolidation contract
The old GSD file-memory (kebab-case md + frontmatter) is the Obsidian adapter;
the Phalanx MEMORY.md index is the jsonl adapter's summary column. They are the
same core use-case — swap `--type obsidian|jsonl` freely.
