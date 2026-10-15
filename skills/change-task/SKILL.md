---
name: change-task
description: Plan an incremental change to an existing task after implementation has begun or completed, preserving its original specification and execution history.
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
  - the original acceptance criteria and approved decisions;
  - the changed or completed work;
  - the affected production boundaries and consumers;
  - unresolved conflicts.
- Separate facts from inferences. Do not infer added scope from a completed plan or adjacent code.
- If the task identity, canonical spec, parent plan, or relevant evidence is ambiguous or materially inconsistent, present the evidence and ask the owner before planning.

## Resolve and approve the delta

- **Clarify with `grilling`:** go through the changed behavior, acceptance criteria, boundaries, and exceptions one owner decision at a time. Bring repository evidence and a recommendation. Reuse approved decisions unless this delta reopens them.
- **Use `domain-modeling` only when needed:** only when the delta changes terminology, domain invariants, responsibilities, or architecture. Test those choices against the glossary, the code, and concrete scenarios.
  - Do not force an ADR for local fixes or UI-only changes.
  - Do not decide an ADR or write the glossary or ADR as a side effect. Present any proposed change for owner agreement and separate authorization.
- **Draft the delta for owner review** before treating it as approved:
  - Preserve every still-applicable original AC.
  - Identify added, changed, superseded, and reopened ACs, with the rationale for each.
  - Include before/after behavior, scope, non-goals, affected consumers and state, the applicable contract, transaction, concurrency and retry risks, and unresolved decisions.
- **Limit external writes:**
  - Do not update the canonical spec or the Azure Boards item until the owner accepts the wording and separately authorizes that write.
  - Do not create a WI by default. If governance requires one, stop and explain why.

## Build the new plan

After the owner accepts the delta, write a new plan in the format `/execute` consumes. Preserve the original spec, plan, statuses, and history. Record:
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

The next step is `/execute <new-plan-path>` after the delta plan is accepted. Prefer the explicit path, because a WI lookup may be ambiguous.

## Handoff

Return:
- the accepted delta and the plan path;
- the baseline and source evidence;
- scope and non-goals;
- owner decisions and authorizations;
- the reviewer's disposition;
- verification limits;
- the next action.

State any owner decision that still blocks progress.
