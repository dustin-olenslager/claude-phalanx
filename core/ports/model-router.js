"use strict";
/*
 * core/ports/model-router.js — the model-routing port (ADR-0004).
 *
 * A port defines the contract; adapters provide the concrete provider mapping
 * (adapters/models/). Core only holds the pure policy decision so it stays
 * testable without any provider dependency.
 *
 * Contract an adapter must satisfy:
 *   resolve(profile) -> { provider, model }
 *   choose({ task, profile, mode, phase }) -> { profile, provider, model }
 */

const PROFILES = ["quality", "balanced", "budget"];

function isProfile(p) { return PROFILES.includes(p); }

// Pure default policy: pick the profile for a task. Cheap profile escalates to
// quality for hard/reasoning-heavy work (security, architecture, adversarial
// review, deep research); otherwise stays at the requested tier.
function defaultProfile(requested, { mode, phase } = {}) {
  const base = isProfile(requested) ? requested : "balanced";
  const hardPhases = [
    "architecture", "security", "review", "research", "design",
    "comprehend", "characterize", "plan-change", "profile", "hypothesize",
  ];
  const isHard = mode === "build" && hardPhases.includes(phase);
  if (isHard && base === "budget") return "balanced";
  return base;
}

module.exports = { PROFILES, isProfile, defaultProfile };