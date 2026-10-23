---
name: change-task
description: Plans an incremental change to an existing BrixBroker task after implementation has begun or completed, preserving its original spec and execution history and recording the new decisions in the Work Item. Use when the dev asks for "/change-task" or wants to alter a task that already has a plan or delivery.
argument-hint: "<WI-number|spec-path|plan-path> plus the requested change"
disable-model-invocation: true
---

# Change Task

Use `/change-task <WI-number|spec-path|plan-path>` with the requested change to produce a new, reviewable delta plan. This skill owns the post-execution change workflow; it does not invoke `/spec-task` or `/plan-task`.

## Establish the baseline

- Read the applicable project instructions and the concise index.
- Inspect the named source, the canonical spec, the parent plan and its status, the current branch and `HEAD`, the relevant source diff, and any available execution or gate evidence.
- Record:
  - the exact baseline SHA;
  - the original acceptance criteria and the decisions recorded in the Work Item;
  - the changed or completed work;
  - the affected production boundaries and consumers;
  - unresolved conflicts.
- Separate facts from inferences. Do not infer added scope from a completed plan or adjacent code.
- If the task identity, canonical spec, parent plan, or relevant evidence is ambiguous or materially inconsistent, present the evidence and ask the dev before planning.

## Decide the delta

- **Decide with the dev:** go through the changed behavior, acceptance criteria, boundaries, and exceptions one decision at a time, with repository evidence and a recommendation, following the decision record of skill `plan-task` (`references/decisions.md`). Reuse earlier decisions from the Work Item unless this delta reopens them.
- **Use `domain-modeling` only when needed:** only when the delta changes terminology, domain invariants, responsibilities, or architecture. Test those choices against the glossary, the code, and concrete scenarios.
  - Do not force an ADR for local fixes or UI-only changes.
  - Do not write the glossary or an ADR as a side effect; propose the change to the dev first.
- **Draft the delta for the dev's review** before treating it as accepted:
  - Preserve every still-applicable original AC.
  - Identify added, changed, superseded, and reopened ACs, with the rationale for each.
  - Include before/after behavior, scope, non-goals, affected consumers and state, the applicable contract, transaction, concurrency and retry risks, and unresolved decisions.
- **External writes after the dev confirms the text:**
  - update the canonical spec and the Azure Boards item;
  - record every delta decision in the Work Item's "Decisões do dev" section and its mirror, continuing the existing ID numbering.
  - Do not create a WI by default. If governance requires one, stop and explain why.

## Build the new plan

After the dev accepts the delta, write a new plan in the format `/execute-ig` consumes. The plan's "Decisões (não reabrir)" may copy the decisions that bind the executor, with their IDs; on divergence, the Work Item wins.

Preserve the original spec, plan, statuses, and history. Record:
- the canonical spec and parent-plan links;
- the baseline SHA and evidence sources;
- all new slices as `pending`.

Apply the coverage contract owned by `plan-for-cursor` (pass 11, `references/coverage-contract.md`):
- **Coverage matrix:** maps each preserved, changed, and new criterion to its observable behavior, expected result, production boundary, test or check, and discriminant.
- **Slice graph:** each behavior-bearing slice names its dependencies, one write owner, its bounded files or surfaces, AC IDs, focused checks, discriminating test, and parallel safety.

Run `plan-for-cursor` once, in full, on the plan. It owns:
- the independent `reviewer` challenge of the coverage matrix;
- seam checks;
- environment claims and commands;
- test tracing and discriminants;
- merge simulation and gate rationale, when relevant;
- the final verification table.

Do not duplicate its review or claim checks or approvals that were not performed.

Name the plan `.cursor/plans/wi_<ID>_<slug>-alteracoes.plan.md` for a WI, or `.cursor/plans/<slug>-alteracoes.plan.md` otherwise. Check the destination first and never overwrite an existing plan; choose a unique, meaningful suffix when needed.

Do not:
- edit product code or tests;
- execute slices or run full gates;
- deploy, act on PRs, commit, or push.

The next step is `/execute-ig <new-plan-path>` after the dev accepts the delta plan. Prefer the explicit path, because a WI lookup may be ambiguous.

## Handoff

Return:
- the accepted delta and the plan path;
- the baseline and source evidence;
- scope and non-goals;
- the decisions recorded in the Work Item, with their IDs;
- the reviewer's disposition;
- verification limits;
- the next action.

State any open decision that still blocks progress.
