"use strict";
/*
 * adapters/models/router-policy.js — concrete model routing (ADR-0004).
 *
 * Implements the core/ports/model-router.js contract with the operator's real
 * providers. Zero-dep: the "providers" are just labels the harness (opencode /
 * Claude Code) resolves to credentials; this file only decides WHICH provider +
 * model each profile points at.
 *
 * PROFILES:
 *   quality  -> best reasoning (architecture, security, adversarial review)
 *   balanced -> default day-to-day build work
 *   budget   -> cheap/fast local (ollama) for grunt work
 */
const { PROFILES, isProfile, defaultProfile } = require("../../core/ports/model-router.js");

const ROUTES = {
  quality:  { provider: "anthropic",  model: "claude-opus-5" },
  balanced: { provider: "anthropic",  model: "claude-sonnet-5" },
  budget:   { provider: "ollama",     model: "qwen3-coder:30b" },
};

// resolve(profile) -> { provider, model }
function resolve(profile) {
  const p = isProfile(profile) ? profile : "balanced";
  return { ...ROUTES[p] };
}

// choose({ profile, mode, phase }) -> { profile, provider, model }
// Applies the pure escalation policy from the port, then maps to a concrete
// route. Escalations only ever bump budget -> balanced, never costlier.
function choose({ profile = "balanced", mode, phase } = {}) {
  const effective = defaultProfile(profile, { mode, phase });
  return { profile: effective, ...ROUTES[effective] };
}

module.exports = { ROUTES, PROFILES, resolve, choose };