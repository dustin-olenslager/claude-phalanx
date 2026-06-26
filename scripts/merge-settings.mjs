#!/usr/bin/env node
/*
 * Idempotent settings.json merge. ADD, never clobber.
 * argv: <settingsPath> <fragmentPath> <CLAUDE_DIR>
 *  - objects (extraKnownMarketplaces, enabledPlugins): existing keys WIN (operator
 *    choices preserved); fragment keys added only when absent.
 *  - hooks: append our command hooks into the matching event/matcher group only
 *    if that exact command string isn't already present. Safe to re-run.
 */
import fs from 'node:fs';

const [, , settingsPath, fragmentPath, claudeDir] = process.argv;
if (!settingsPath || !fragmentPath || !claudeDir) {
  console.error('usage: merge-settings.mjs <settings.json> <fragment.json> <CLAUDE_DIR>');
  process.exit(2);
}

const readJson = (p, fallback) => {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return fallback; }
};

const settings = readJson(settingsPath, {});
const fragmentRaw = fs.readFileSync(fragmentPath, 'utf8').split('__CLAUDE_DIR__').join(claudeDir);
const fragment = JSON.parse(fragmentRaw);

// --- object merges: existing wins ---
for (const key of ['extraKnownMarketplaces', 'enabledPlugins']) {
  if (!fragment[key]) continue;
  settings[key] = { ...fragment[key], ...(settings[key] || {}) };
}

// --- hooks merge: append missing command hooks per event/matcher ---
settings.hooks = settings.hooks || {};
for (const [event, groups] of Object.entries(fragment.hooks || {})) {
  settings.hooks[event] = settings.hooks[event] || [];
  const existingCmds = new Set();
  for (const g of settings.hooks[event]) for (const h of (g.hooks || [])) if (h.command) existingCmds.add(h.command);

  for (const fg of groups) {
    const wanted = (fg.hooks || []).filter((h) => h.command && !existingCmds.has(h.command));
    if (!wanted.length) continue;
    // Prefer a group with the same matcher; else create one.
    let target = settings.hooks[event].find((g) => (g.matcher || '') === (fg.matcher || ''));
    if (!target) { target = { ...(fg.matcher ? { matcher: fg.matcher } : {}), hooks: [] }; settings.hooks[event].push(target); }
    target.hooks = target.hooks || [];
    for (const h of wanted) { target.hooks.push(h); existingCmds.add(h.command); }
  }
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
console.log('merged settings -> ' + settingsPath);
