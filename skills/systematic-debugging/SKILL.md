---
name: systematic-debugging
description: Diagnose reproducible failures, regressions, incorrect behavior, and unclear defects by tracing evidence to a root cause before proposing a fix. Use when the cause is unknown, multiple layers may be involved, or an apparent fix could only mask a symptom. Do not use when the request is solely to implement an already-established correction.
---

# Systematic debugging

Produce a causal explanation supported by repository and runtime evidence, then define the smallest correction and regression proof. Diagnosis does not authorize implementation unless the user requested a fix.

## Workflow

1. Restate the observed behavior, expected behavior, impact, and known reproduction conditions. Separate observations from reports and assumptions.
2. Reproduce with the smallest safe case available. If reproduction is unavailable, identify the strongest observable evidence and the uncertainty it leaves.
3. Trace the failing value or state backward across boundaries until locating the first divergence from expected behavior.
4. Form one falsifiable hypothesis at a time. Predict what evidence would support or reject it before gathering more data.
5. Compare with a known-good path, recent change, sibling implementation, or invariant when available.
6. Identify the root cause, contributing conditions, and why existing checks did not catch it.
7. Define a minimal correction that restores the violated invariant without unrelated refactoring.
8. Verify the original failure, relevant boundary cases, and a regression test at the lowest useful level.

## Guardrails

- Do not stack speculative changes or change multiple independent variables in one experiment.
- Do not treat correlation, a disappearing symptom, or a passing retry as proof of cause.
- Prefer targeted instrumentation over broad raw logs; do not persist secrets or sensitive payloads.
- Inspect configuration, data shape, concurrency, caching, time, environment, and external boundaries when the symptom crosses layers.
- Stop and reframe when evidence contradicts the active hypothesis.
- Report unresolved uncertainty explicitly rather than inventing a definitive cause.

## Report

Run the diagnosis in the main session. When tracing needs wide reading, such as many logs or files across layers, delegate that reading to `scout` and keep the reasoning yourself.

Report the reproduction, evidence, root cause or ranked hypotheses, affected surface, proposed correction, regression strategy, and remaining uncertainty. Ask the user before acting on a consequential decision, including whether to implement the fix when only a diagnosis was requested.
