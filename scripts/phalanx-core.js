"use strict";
/*
 * scripts/phalanx-core.js — composition root + CLI (ADR-0004).
 *
 * The only place core use-cases meet concrete adapters. Commands:
 *   node scripts/phalanx-core.js state [--cwd <dir>]              show state
 *   node scripts/phalanx-core.js init [--mode build|maintain|optimize] [--cwd <dir>]
 *   node scripts/phalanx-core.js next [--cwd <dir>]               advance phase
 *   node scripts/phalanx-core.js jump <phase> [--cwd <dir>]       force valid jump
 *   node scripts/phalanx-core.js plan [--mode <m>] [--title <t>]  print phase plan
 *   node scripts/phalanx-core.js route [--profile <p>] [--mode <m>] [--phase <ph>]
 *   node scripts/phalanx-core.js recall <query> [--memory <dir|vault>] [--type jsonl|obsidian]
 *   node scripts/phalanx-core.js add-memory --name <n> [--type <t>] [--summary <s>] [--content <c>] [--memory <dir>]
 *   node scripts/phalanx-core.js migrate [--cwd <dir>] [--dry-run]
 *
 * Zero-dep. Exit 0 on success, 1 on failure (reason on stderr).
 */
const fs = require("fs");
const path = require("path");

const stateAdapter = require("../adapters/state/fs.js");
const router = require("../adapters/models/router-policy.js");
const jsonl = require("../adapters/memory/jsonl.js");
const obsidian = require("../adapters/memory/obsidian.js");

const phaseMachine = require("../core/domain/phase-machine.js");
const { brief } = require("../core/use-cases/brief.js");
const { execute, jump } = require("../core/use-cases/execute.js");
const { recall } = require("../core/use-cases/recall.js");
const { plan } = require("../core/use-cases/plan.js");
const { migrateLegacy, diffLegacy } = require("../core/use-cases/migrate.js");

function fail(msg) { console.error("phalanx-core: " + msg); process.exit(1); }

// Gate: run the phase's real exit gate against the repo. For now the CLI gate
// is: the phase's exit flag is present in flags, OR a gate script exists at
// hooks/gates/exit-<phase>.js and runs green. The harness (hooks) supplies the
// authoritative gate; this keeps the CLI deterministic in a bare repo.
function gateFor(cwd, phase) {
  const flag = `${phase}:done`;
  const state = stateAdapter.read(cwd);
  if (state.flags && state.flags[flag]) return { passed: true, evidence: `flag ${flag}` };
  const gate = path.join(cwd, "hooks", "gates", `exit-${phase}.js`);
  if (fs.existsSync(gate)) {
    try {
      const out = require("child_process").execFileSync("node", [gate], { stdio: ["ignore", "pipe", "pipe"] });
      return { passed: out.toString().trim() === "ok", evidence: "gate " + gate };
    } catch { return { passed: false, evidence: "gate " + gate + " failed" }; }
  }
  // No flag, no gate script -> gate not met (trivial work may still force-jump).
  return { passed: false, evidence: `exit gate not met (${phaseMachine.exitGate(state.mode, phase).exit})` };
}

function arg(argv, name) {
  const i = argv.indexOf(name);
  return i !== -1 && argv[i + 1] !== undefined ? argv[i + 1] : null;
}
function has(argv, name) { return argv.indexOf(name) !== -1; }

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  const cwd = arg(argv, "--cwd") || ".";
  const memDir = arg(argv, "--memory") || path.join(cwd, "memory");

  if (!cmd) { printUsage(); return; }

  switch (cmd) {
    case "state": {
      console.log(JSON.stringify(stateAdapter.read(cwd), null, 2));
      return;
    }
    case "init": {
      const mode = arg(argv, "--mode") || "build";
      if (!phaseMachine.isMode(mode)) fail(`unknown mode: ${mode}`);
      const s = stateAdapter.write(cwd, { mode, phase: phaseMachine.firstPhase(mode), flags: {} });
      console.log("state initialized:", JSON.stringify(s));
      return;
    }
    case "next": {
      const s = stateAdapter.read(cwd);
      const g = gateFor(cwd, s.phase);
      const r = execute(s, () => g);
      if (!r.ok) fail(r.reason);
      const written = stateAdapter.write(cwd, r.state);
      console.log(r.complete
        ? `complete: all phases done (mode=${written.mode})`
        : `advanced: ${written.mode}:${written.phase}`);
      return;
    }
    case "jump": {
      const target = argv[1];
      if (!target) fail("usage: phalanx-core.js jump <phase>");
      const s = stateAdapter.read(cwd);
      const r = jump(s, target);
      if (!r.ok) fail(r.reason);
      const written = stateAdapter.write(cwd, r.state);
      console.log(`jumped: ${written.mode}:${written.phase}`);
      return;
    }
    case "plan": {
      const mode = arg(argv, "--mode") || "build";
      const p = plan(brief(arg(argv, "--title") || "untitled"), mode);
      console.log(p.mode + " plan:");
      for (const ph of p.phases) console.log(`  ${ph.id}  (${ph.team})  -> ${ph.exit}`);
      return;
    }
    case "route": {
      const profile = arg(argv, "--profile") || "balanced";
      const mode = arg(argv, "--mode") || "build";
      const phase = arg(argv, "--phase") || phaseMachine.firstPhase(mode);
      console.log(JSON.stringify(router.choose({ profile, mode, phase }), null, 2));
      return;
    }
    case "recall": {
      const query = argv[1] || "";
      const type = arg(argv, "--type") || "jsonl";
      const handle = type === "obsidian" ? obsidian.store(memDir) : jsonl.store(memDir);
      const items = recall(handle, query, { limit: 20 });
      if (!items.length) { console.log("no matches"); return; }
      for (const i of items) console.log(`- [${i.type}] ${i.name}: ${i.summary || i.content.slice(0, 60)}`);
      return;
    }
    case "add-memory": {
      const name = arg(argv, "--name");
      if (!name) fail("usage: add-memory --name <n> [--type <t>] [--summary <s>] [--content <c>]");
      const type = arg(argv, "--type") || "reference";
      const item = jsonl.add(memDir, { name, type, summary: arg(argv, "--summary") || "", content: arg(argv, "--content") || "" });
      console.log("added:", item.name, `(${item.type})`);
      return;
    }
    case "migrate": {
      const candidates = ["build", "maintain", "optimize"].map((m) => path.join(cwd, "state", `${m}.json`))
        .filter((f) => fs.existsSync(f));
      if (!candidates.length) { console.log("no legacy state files found; nothing to migrate"); return; }
      for (const f of candidates) {
        const raw = JSON.parse(fs.readFileSync(f, "utf8"));
        const diff = diffLegacy(raw);
        const unified = migrateLegacy(raw);
        if (has(argv, "--dry-run")) {
          console.log(`${path.basename(f)}: ${diff.before.mode}:${diff.before.phase} -> ${diff.after.mode}:${diff.after.phase}${diff.changed ? " (changed)" : ""}`);
        } else {
          const s = stateAdapter.write(cwd, unified);
          console.log(`${path.basename(f)} -> unified ${s.mode}:${s.phase} written to .claude-state.json`);
        }
      }
      return;
    }
    default:
      fail(`unknown command: ${cmd}`);
  }
}

function printUsage() {
  console.log(`phalanx-core — unified phase machine (ADR-0004)
  state                          show current state
  init [--mode <m>]              create state at first phase
  next                           run exit gate, advance phase
  jump <phase>                   force a valid adjacent transition
  plan [--mode <m>]              print the ordered phase plan + exit gates
  route [--profile <p>]          resolve provider/model for a profile
  recall <query> [--type <t>]    search memory
  add-memory --name <n>          append a memory item
  migrate [--dry-run]            collapse legacy state files to unified`);
}

main();