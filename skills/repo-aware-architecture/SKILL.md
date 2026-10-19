---
name: repo-aware-architecture
description: Explores and resolves feature, integration, or system-design decisions that must be grounded in an existing repository. Use when multiple approaches are plausible, the change is cross-cutting or hard to reverse, or architecture must be validated and recorded before implementation. Do not use for straightforward changes with an established local pattern or for ideation that needs no repository context.
---

# Repo-aware architecture

Turn repository-grounded uncertainty into an explicit, reviewable decision that the active SDD workflow can plan and execute.

## Route the work

1. Inspect applicable `CLAUDE.md` and `AGENTS.md` files, the project's memory or documentation index, repository docs, active specs, and only the code needed to understand the decision surface.
2. State the outcome, decision drivers, constraints, non-goals, known facts, and open questions. Do not treat assumptions as repository evidence.
3. Choose the lightest applicable mode:
   - **Discovery:** the solution is unknown or multiple credible approaches exist. Read [references/discovery.md](references/discovery.md).
   - **Decision validation:** a preferred approach already exists. Test it against repository evidence and compare alternatives only where a material trade-off remains.
   - **Decision recording:** the choice is settled and durable consequences need documentation. Read [references/decision-record.md](references/decision-record.md).
4. For a material comparison, read [references/tradeoff-analysis.md](references/tradeoff-analysis.md).
5. Return the selected approach, rejected alternatives, consequences, risks, validation strategy, and unresolved questions to the SDD workflow.

## Decision discipline

- Reuse existing extension points and conventions unless a driver justifies changing them.
- Prefer the smallest change surface that satisfies the current requirements. Any new component, abstraction, dependency, persistence mechanism, or configuration/startup change must trace to a decision driver and explain why the existing path is insufficient.
- Treat future-proofing and hypothetical extensibility as non-goals unless they are explicit requirements.
- Compare two or three credible options, not artificial variants.
- Prefer reversible and incremental paths when expected value is otherwise similar.
- Include operational, data, security, compatibility, testing, migration, and rollback consequences when relevant.
- Ask for user approval before committing to a materially different product outcome, public contract, data model, or difficult-to-reverse architecture.
- Do not implement while the material decision remains unresolved. A bounded probe may be proposed when evidence cannot be obtained by inspection.
- Keep small decisions in the active spec. Use the repository's ADR convention for durable, cross-cutting choices; do not impose a new directory when one already exists.

## Delegation

Run this skill in the main session, which owns synthesis and the final spec. Delegate wide repository reading to `scout` only when it has material value. Use `architect_escalation` only when evidence cannot settle a consequential trade-off. Return every unresolved consequential question to the user instead of assuming an answer.
