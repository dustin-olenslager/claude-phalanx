"use strict";
// Standalone: `node adapters/models/router-policy.test.js`.
const assert = require("assert");
const R = require("./router-policy.js");

// resolve: valid profiles map to concrete providers
assert.deepStrictEqual(R.resolve("quality"), { provider: "anthropic", model: "claude-opus-5" });
assert.deepStrictEqual(R.resolve("balanced"), { provider: "anthropic", model: "claude-sonnet-5" });
assert.deepStrictEqual(R.resolve("budget"), { provider: "ollama", model: "qwen3-coder:30b" });
assert.deepStrictEqual(R.resolve("bogus"), { provider: "anthropic", model: "claude-sonnet-5" }); // fallback

// choose: escalation policy — budget escalates on hard build phases
assert.deepStrictEqual(R.choose({ profile: "budget", mode: "build", phase: "implement" }),
  { profile: "budget", provider: "ollama", model: "qwen3-coder:30b" }); // grunt stays cheap
assert.deepStrictEqual(R.choose({ profile: "budget", mode: "build", phase: "security" }),
  { profile: "balanced", provider: "anthropic", model: "claude-sonnet-5" }); // hard -> escalate
assert.deepStrictEqual(R.choose({ profile: "quality", mode: "build", phase: "implement" }),
  { profile: "quality", provider: "anthropic", model: "claude-opus-5" });
assert.deepStrictEqual(R.choose({}), { profile: "balanced", provider: "anthropic", model: "claude-sonnet-5" });

console.log("ok: router-policy adapter passes");