---
name: optimize-loop
description: >
  OPTIMIZE mode driver (CLAUDE.md §15) — performance work, measure-first. No fix
  without a number; revert any change that doesn't prove a real gain. REQUIRES
  observability (§12) to already exist. Use when the user says "optimize", "make
  it faster", "perf", "it's slow", "reduce latency/cost".
license: MIT
---

# optimize-loop

Guessing is banned. Measure → find the real hot path → change ONLY it → prove
the gain or revert. This skill sets the pipeline `planned` flag.

## Precondition
Observability (§12) must exist — structured logs + spans/metrics on I/O
boundaries and use cases. If it doesn't, STOP: you cannot optimize what you can't
measure. Add instrumentation first (that's a build/maintain task), then return.

## Phases (state machine)
1. **baseline** (exit: numbers on record) — capture current metrics from
   observability/benchmarks: p50/p95/p99 latency, throughput, alloc/GC, db time,
   $ per op. Write them down. This is the bar.
2. **profile** (exit: bottleneck identified) — profiler/trace/flamegraph or span
   breakdown to find the REAL hot path. Amdahl: optimizing a 2% cost is wasted.
   Name the single dominant cost.
3. **hypothesize** (exit: ADR recorded) — state the expected gain AND the
   trade-off (memory, complexity, cache staleness, consistency) in an ADR. A perf
   change with no stated trade-off is suspicious.
4. **implement** (exit: change made) — ponytail + caveman; touch ONLY the hot
   path. Don't rewrite cold code for elegance.
5. **benchmark** (exit: gain proven) — re-measure the SAME way vs baseline. Real,
   repeatable gain beyond noise? keep. Marginal/none? **revert** — complexity
   without payoff is a loss.
6. **verify / commit / memory** — as BUILD. Verify includes correctness didn't
   regress (the fast wrong answer is still wrong).

## Rules
- One variable at a time; re-measure between changes.
- Prefer algorithmic/IO/N+1/batching wins over micro-opts.
- Keep the benchmark + baseline numbers in the commit/ADR so the next person
  doesn't re-litigate.

## Output
baseline table → hot path → hypothesis+ADR → diff → before/after table → keep or
revert decision.
