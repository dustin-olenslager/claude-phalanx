# Feature area folder convention

Copy this folder to create a new area under `docs/claude/`, and rename it. Areas are broad and
long-lived — pick a handful that match how the project is actually divided, for example `api/`,
`ui/`, `data/`, `integrations/`, `platform/`. Do not create an area per feature; features are
folders *inside* an area.

Never put a plan file flat at the top of `docs/claude/` — it has no home and nobody finds it again.

## Shape

```
<area>/
  README.md                     what this area covers (one paragraph)
  <feature>/                    one folder per in-flight feature
    plan.md                     from ../_templates/plan.md
    research.md                 optional — findings, benchmarks, API notes
    references/                 optional — screenshots, sample payloads, sketches
  completed/                    archive; everything shipped lives here
    <feature>/
      <what-shipped>.md
```

## Rules

- **One folder per feature, and everything about it goes in that folder** — plan, research,
  references. Scattering related docs across areas makes the archive step lossy.
- **On ship, move the whole folder into `completed/`** — not just the plan. The research is what
  explains the plan, and a plan without its reasoning is unusable a year later.
- **Rename files on archive to describe what shipped.** `completed/` full of files named `plan.md`
  is unsearchable and every one of them looks current. `server-side-pagination.md` does not.
- **Archive, never delete.** The reasoning behind a shipped feature is the context for the next
  change to it.
- Update anything that pointed at the old path — `in-progress.md`, `completed-features.md`, and any
  closed issue or milestone descriptions.

## Area README starter

Replace this file's contents in a real area with something like:

> Covers <what this area owns>. Entry points: `<paths>`. Owner: <who>.
> Active work is in the feature folders below; shipped work is in `completed/`.
