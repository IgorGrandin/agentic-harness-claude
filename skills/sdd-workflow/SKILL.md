---
name: sdd-workflow
description: Spec-driven procedure for repository work (bugs, features, discovery, refactors, reviews). Use when a task needs more than a one-sentence diff; skip it for local microtasks.
---

# SDD workflow

## Intake

Classify the request as bug, feature, discovery, refactor, or review. Read the applicable project instructions, then only the task, the project index, and the files needed for the decision. Label facts, inferences, and open questions. Repository evidence outranks imported prose.

If the diff fits in one sentence, use the fast lane: one targeted inspection, one scoped edit (if authorized), one focused check. No plan.

## Specify

For larger work, keep one concise Markdown source of truth with outcome, scope, acceptance criteria, non-goals, risks, and verification. Use plan mode or the project's planning skill to produce it. Preserve existing architecture and authorization boundaries. Ask the user about material ambiguity before planning around it.

Route specialized decisions:
- an unknown root cause goes to `systematic-debugging`;
- a cross-cutting or hard-to-reverse design choice goes to `repo-aware-architecture`;
- a domain term or invariant goes to `domain-modeling`.

## Implement

Implement the smallest change that satisfies the criteria, test-first where the project supports it, in the main session. Follow the global delegation policy for subagents. Stop and report when repository evidence invalidates the spec instead of silently changing scope.

## Verify and report

Verify each acceptance criterion with the smallest decisive check, using the repository's documented commands. Compilation alone is not evidence. Before calling a multi-file delivery done, get one fresh-context review of the integrated diff against the spec.

Report the outcome, changed artifacts, evidence, unverified items, and the next decision.
