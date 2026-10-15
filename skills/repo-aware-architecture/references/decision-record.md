# Decision record

Use the repository's existing ADR or decision convention. If none exists, keep a small decision inside the active spec unless the choice is durable and cross-cutting enough to justify a dedicated Markdown record.

## Minimal record

```markdown
# Decision: <title>

- Status: proposed | accepted | superseded
- Date: YYYY-MM-DD
- Scope: <systems or boundaries affected>

## Context
<problem, repository evidence, drivers, constraints>

## Decision
<chosen approach and important boundaries>

## Alternatives considered
<credible alternatives and decisive rejection reasons>

## Consequences
<benefits, costs, risks, operational and migration effects>

## Validation
<tests, probes, metrics, rollout gates>

## Follow-ups
<owned work or unresolved questions>
```

Link rather than duplicate detailed specs, diagrams, or research. Supersede an earlier decision explicitly instead of silently rewriting history when the repository convention preserves ADR history. Return unresolved consequential choices to the root before marking a decision accepted.
