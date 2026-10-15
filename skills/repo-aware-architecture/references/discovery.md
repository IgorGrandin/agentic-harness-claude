# Repository-grounded discovery

Use this mode when the destination is unclear or credible alternatives remain.

## Evidence map

Inspect only what can change the decision:

- current responsibilities and boundaries;
- existing extension points and analogous flows;
- callers, consumers, data ownership, and external dependencies;
- runtime and deployment constraints;
- tests that encode intended behavior;
- active specs, ADRs, and recent decisions.

Record findings as:

- **Observed:** directly supported by code, documentation, configuration, tests, or runtime evidence.
- **Inferred:** likely but not yet verified.
- **Unknown:** material information still missing.

Ask the user about product intent, priorities, or external constraints only after repository inspection has eliminated questions the code can answer.

## Discovery output

State:

1. decision to make;
2. outcome and success measures;
3. drivers and constraints;
4. relevant current architecture;
5. credible options or the probe needed to discover them;
6. material unknowns.

Return all material unknowns and consequential ambiguity to the user instead of assuming answers. If the problem spans several independent subsystems, decompose it and make dependencies explicit before designing the first slice.
