/**
 * Clean Architecture ruleset for dependency-cruiser (CLAUDE.md §3/§14, arch-enforce).
 * Layers (inner→outer): domain → application → adapters → infra/main.
 * Adjust the `pathNot`/path globs to your repo's actual folder names.
 * Run: npx depcruise --config .dependency-cruiser.js src
 */
module.exports = {
  forbidden: [
    {
      name: 'domain-imports-nothing-outward',
      comment: 'domain may not import application/adapters/infra (Dependency Rule).',
      severity: 'error',
      from: { path: '^src/domain/' },
      to: { path: '^src/(application|adapters|infra|main)' },
    },
    {
      name: 'application-only-domain',
      comment: 'application may import domain only — never adapters/infra/frameworks.',
      severity: 'error',
      from: { path: '^src/application/' },
      to: { path: '^src/(adapters|infra|main)' },
    },
    {
      name: 'business-rules-no-framework-io',
      comment: 'domain + application must not reach node IO / db / http drivers.',
      severity: 'error',
      from: { path: '^src/(domain|application)/' },
      to: { path: 'node_modules/(express|fastify|pg|mysql2|mongodb|ioredis|axios|node-fetch|fs|@aws-sdk|prisma|typeorm|drizzle-orm)' },
    },
    {
      name: 'only-main-wires-infra',
      comment: 'only the composition root (main/bootstrap) may import concrete infra/adapters.',
      severity: 'error',
      from: { path: '^src/', pathNot: '^src/(main|infra/bootstrap)' },
      to: { path: '^src/infra/' },
    },
    {
      name: 'no-circular',
      comment: 'no cyclic dependencies.',
      severity: 'error',
      from: {},
      to: { circular: true },
    },
    {
      name: 'no-orphans',
      comment: 'no dead/unreachable modules.',
      severity: 'warn',
      from: { orphan: true, pathNot: '\\.(d\\.ts|config\\.[jt]s|test\\.[jt]s)$' },
      to: {},
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.json' },
  },
};
