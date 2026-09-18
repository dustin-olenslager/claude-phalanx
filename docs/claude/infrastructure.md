# Infrastructure

How this project runs outside a developer's machine. Read before touching anything deploy-, data-,
or secret-related. Update in the same PR as the change — infra docs that lag the infra are worse
than no docs, because they are trusted.

Answer the questions; delete the ones that do not apply.

## Environments

- What environments exist (local, preview, staging, production), and which are real user traffic?
- How do they differ in data, scale, and configuration?
- How does a developer point at a non-local environment, and what is forbidden to do against prod?

## Deploy pipeline

- What triggers a deploy — merge, tag, manual command?
- What are the gates (typecheck, tests, migration checks) and which are blocking?
- How long does a deploy take, and how do you know it succeeded?
- **How do you roll back?** Write the exact command or steps. Nobody looks this up calmly.

## Hosting & runtime

- Where does each service run, and what is the runtime version pinned to?
- How are processes scaled, restarted, and health-checked?
- Where do logs go, and how do you read them for a single request?

## Data stores

- Primary database: engine, version, who manages it, where backups live and how a restore is tested.
- Caches, queues, blob/object storage: what is authoritative vs. reconstructible?
- Migration process: how a schema change is generated, applied, and verified as applied.

## Secrets & configuration

- Where secrets live (manager or vault), and how a new one is added.
- How local development gets its values, and what the example/config file is called.
- What must never be committed, and what enforces that.

## Background jobs & scheduled work

- What runs on a schedule, how often, and what breaks if it silently stops?
- Are jobs idempotent and safe to re-run? If not, say which ones are not.
- Where failures are reported, and who sees them.

## Monitoring & alerting

- What is monitored, what pages a human, and what is only logged.
- The first three things to check when production looks wrong.
