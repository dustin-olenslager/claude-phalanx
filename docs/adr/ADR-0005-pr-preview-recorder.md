# ADR-0005 — PR preview recorder: before/after video evidence on a pull request

- **Status:** Accepted (2026-09-09)
- **Deciders:** Operator, Phalanx maintainer
- **Relates to:** [ADR-0001](ADR-0001-autonomous-merge-deploy-on-green.md), [ADR-0003](ADR-0003-worktree-isolation.md)

## Context

A Phalanx pass ships a UI change as a diff and a green verify flag. Neither shows what the
change *looks like* or *does*. The operator's standing rule is that nothing user-facing is done
until it has been seen at 390 and 1440 — today that is a manual Playwright screenshot chore
re-implemented per repo (`_eval/frame-forge/shot.mjs`, the koforje shot harness, the Plexo
faithful-390 harness), and its output never reaches the pull request. An unattended pass has no
way to show its work at all, which is exactly when visual evidence matters most.

`pr-preview.com` solves the same problem for Claude Code: an MCP server drives a real Chrome
window from a plain-English journey, records before/after MP4s, and the developer drags the
files into the PR by hand. The evaluation of that tool is what prompted this decision. Two
things make it a poor fit here. First, its capture is **agent-driven at record time** — a
journey is re-interpreted on every run, so the "before" and "after" clips are not guaranteed to
be the same journey, and an unattended supervisor pays an agent turn per recording. Second, its
auto-posting is a hosted paid tier that does not exist yet; the free path ends at a local file.

The second problem stopped being a problem on 2026-09-01, when the GitHub CLI shipped a
repeatable `--attach` flag on `gh pr create`, `gh pr edit`, and `gh pr comment`. It uploads a
local image or video through GitHub's own attachment system — the only path that renders an
inline player — and rewrites a matching local path in the body in place. PNG, JPEG, GIF, WebP,
SVG, MP4, MOV and WebM are accepted, at 10 MB for images and for video on Free plans, 100 MB for
video on paid plans. It requires `gh` v2.99.0 or later and is not available on GitHub Enterprise
Server.

That WebM is accepted is what makes this cheap: Playwright's `recordVideo` emits WebM natively,
so the minimum viable path needs a browser and nothing else.

## Decision

Phalanx grows a first-class recorder, `scripts/phalanx-record-preview`, that replays a
**committed, deterministic journey** against both `main` and the task branch, records each at
both viewports, and attaches the clips to the pull request. It is a per-repo opt-in and a soft
gate.

1. **The journey is code, not a prompt.** A repo describes a preview as
   `.phalanx/previews/<slug>.mjs`, a plain Playwright module exporting
   `run(page, ctx)` plus optional metadata (`title`, `sinceMain`, `viewports`, `budgetMs`). The
   recorder supplies the browser, the video context, the viewport, and the base URL; the journey
   only drives the page. Determinism is the whole point — the same file is executed against both
   checkouts, so the two clips differ only by the code under test. It is reviewable in the diff,
   replayable by a human, and costs no agent turn at record time. Authoring the journey is the
   agent's job during `implement`; executing it is not.
2. **The "before" is a cached baseline.** The before-clip is keyed by
   `git merge-base origin/main HEAD` plus the journey file's own hash plus the viewport. A hit is
   reused; a miss records the journey once against a detached worktree at that merge-base. A
   journey declaring `sinceMain: true` skips the before-run entirely and renders a
   "did not exist on `main`" card in its place, because a journey that exercises a new screen
   cannot pass against a checkout that lacks it — treating that failure as an error would make
   the feature unusable for exactly the changes it exists to show.
3. **WebM is the baseline format; ffmpeg is an enhancement.** With no ffmpeg on `PATH` the
   recorder attaches the raw Playwright WebM clips, two per viewport. With a full ffmpeg it
   produces one labelled split-screen clip per viewport (`hstack`, before left, after right),
   which is both fewer attachments and a better artifact.

   Playwright's own bundled ffmpeg is **not** a substitute for the composite. It is built
   `--disable-everything` and enables only the `pad`, `crop` and `scale` filters with a
   `libvpx_vp8` encoder and a WebM muxer (verified against `ffmpeg-1011`,
   `n7.0.1-playwright-build-1011`) — there is no `hstack` and no `drawtext`, so it cannot
   composite or caption. It **is** used for the byte-budget downscale in decision 5, where
   `scale` plus VP8 plus WebM is exactly enough. So the fallback order is: full ffmpeg on `PATH`
   for the composite; otherwise the raw pair, downscaled with Playwright's ffmpeg if the budget
   demands it; otherwise the raw pair as recorded.
4. **Both viewports, always.** 390 and 1440, matching the operator's existing standard and the
   `web-mobile-parity` skill. A journey may narrow this with `viewports`.
5. **Attachment is `gh --attach`, with honest degradation.** The recorder preflights
   `gh --version`; at v2.99.0 or later it posts with `gh pr comment --attach '<clip>#<caption>'`,
   below that it writes the clips to `.claude-runs/previews/` and prints the paths and the
   drag-in instruction. A byte budget is enforced before upload — default 10 MB, one downscale
   retry, then attach what fits and report what was dropped.
6. **Opt-in and soft.** Recording runs only in a repo carrying a `.phalanx-preview` marker, and
   only when the branch diff touches a path the marker's config calls user-facing. It is never
   required for `verify` to pass and never blocks a merge; a recorder failure is reported and
   the pass continues. This follows the graceful-degradation rule every other Phalanx capability
   is held to.

## Consequences

- A UI pull request carries playable before/after evidence without a human recording anything,
  including on an unattended pass — the case `pr-preview.com` cannot serve today.
- Repos stop re-implementing shot harnesses; a journey file replaces one, and the existing
  per-repo login helper is imported by it rather than re-derived.
- The cost is a committed journey per preview-worthy change. That is deliberate: it is the price
  of a before/after pair that actually compares like with like, and the file is small and
  disposable.
- Baseline caching means the common case boots one app, not two.
- `gh` v2.99.0 becomes a prerequisite for the auto-post path on every node. Below it the feature
  still produces clips, so the upgrade is not a blocker for landing this.
- GitHub Enterprise Server cannot use the attach path at all, and falls back to local files.

## Verification

- `install.sh` self-test sims: `preview:no-marker-skips` (absent `.phalanx-preview` records
  nothing), `preview:since-main-skips-before` (a `sinceMain` journey produces no before-run),
  `preview:baseline-cache-hit` (a second run at the same merge-base re-records nothing),
  `preview:no-ffmpeg-degrades` (WebM pair, no composite, exit 0), `preview:old-gh-degrades`
  (`gh` below 2.99.0 writes local files and exits 0), and `preview:never-blocks` (a journey that
  throws leaves the verify flag intact).
- `node --check` on the recorder and any new gate library.
