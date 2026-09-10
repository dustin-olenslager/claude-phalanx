// Example journey for phalanx-record-preview (ADR-0005). Copy to
// .phalanx/previews/<slug>.mjs and edit — the recorder runs this file, unmodified,
// against both `main` and the task branch, so determinism is the whole point: no
// randomness, no `Date.now()`-keyed selectors, no depending on prior journey state.
//
// ctx contract (supplied by the recorder, not by you):
//   ctx.baseUrl   string  the URL for the side currently recording. Default mode: the
//                         app is booted locally and this is .phalanx-preview's "baseUrl"
//                         for both sides. Hosted-URL mode (both "beforeUrl" and
//                         "afterUrl" set in .phalanx-preview -- no local boot at all,
//                         e.g. a Vercel-hosted repo): this is "beforeUrl" while
//                         ctx.side === "before" and "afterUrl" while ctx.side === "after".
//                         Either way the journey code is unchanged.
//   ctx.viewport  number  390 or 1440 (or whatever this journey's `viewports` narrows to)
//   ctx.side      "before" | "after"
//   ctx.slug      string  this journey's file name, minus .mjs
//   ctx.outDir    string  scratch dir for this journey's run (rarely needed directly)
//
// Optional exports the recorder reads: `title` (defaults to the slug), `sinceMain`
// (true skips the before-run entirely, for a screen that doesn't exist on main yet),
// `viewports` (narrows the default [390, 1440]), `budgetMs` (per-clip timeout, default 60000).
//
// For an app behind SSO (e.g. Google) that can't log in by filling a form, set
// `storageState` in .phalanx-preview to a Playwright storage-state JSON path (resolved
// relative to the repo root) — the recorder starts the context already signed in. That
// file holds a live session: never commit it. Missing/unreadable → warns and records
// signed-out; never fails the pass.

export const title = "Example journey — homepage search";
export const sinceMain = false;

// To reuse a repo's existing authenticated-session helper instead of logging in by hand:
// import { loginAs } from "../../scripts/e2e/login.mjs";

export async function run(page, ctx) {
  await page.goto(ctx.baseUrl, { waitUntil: "networkidle" });
  await page.waitForTimeout(500);

  // await loginAs(page, "demo@example.com");

  const search = page.getByPlaceholder("Search");
  await search.click();
  await search.fill("invoice");
  await page.waitForTimeout(400);
  await search.press("Enter");
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(800);
}
