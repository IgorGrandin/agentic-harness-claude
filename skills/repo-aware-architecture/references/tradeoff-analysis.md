# Trade-off analysis

Compare only credible options that satisfy the core outcome. Include the current approach when keeping it is plausible.

## Decision drivers

Choose criteria from actual requirements rather than a universal checklist. Common drivers include:

- correctness and domain fit;
- compatibility and migration cost;
- operability, observability, and failure recovery;
- security and data exposure;
- latency, throughput, and scaling limits;
- implementation and maintenance complexity;
- reversibility and cost of being wrong;
- delivery time and team familiarity.

Mark driver importance qualitatively. Do not fabricate numerical precision or weighted scores without evidence supplied by the user or repository.

## Option format

For each option state:

- mechanism and affected boundaries;
- benefits tied to drivers;
- costs, risks, and failure modes;
- migration and rollout implications;
- evidence supporting feasibility;
- condition under which this option becomes preferable.

Lead with the recommended option and explain why it wins for the current drivers. Record rejected alternatives and the decisive reason; avoid lengthy catalogs of minor differences. Return unresolved trade-offs to the user; do not resolve consequential ambiguity by assumption.
