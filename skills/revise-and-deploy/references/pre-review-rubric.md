# Local pre-review rubric

Use this reference during the local review stage in `SKILL.md`, before any PR push or publication. It adapts the team's review-pr criteria to a completed execution. The active WI, ADRs, project rules, and canonical audit rubric remain authoritative; this file does not replace them.

## Establish review coordinates

Pin and record the exact source commit and base commit. Confirm the branch, work item, PR state if one exists, and whether the PR is open or already completed. An existing merge-preview commit does not by itself prove that a PR was merged. Read relevant prior review decisions and unresolved threads when available; do not repeat a previously decided residue without new evidence.

Treat PR reviewer approval as a separate governance status, not as gate evidence. Report pending approval, but do not wait for it before Dev2 deployment once every required pipeline check has reached terminal success for the exact reviewed SHA. Reviewer approval remains relevant to merge policy; this workflow does not merge, vote, or post review comments.

The review target is the complete diff between the pinned base and source commits. Obtain actual diff content using the available local checkout and documented Git operations, or read the exact source/base file contents when local diff access is unavailable. A changed-file list, PR description, generated summary, or bot review is not the diff and cannot substitute for it. When the diff is too large for one pass, inspect focused file/line ranges while retaining the complete diff as the review boundary. Delegate evidence collection where useful, but the assigned reviewer owns the verdict and checks returned evidence.

The review itself is read-only: examining the diff, execution report, gate manifest, CI records, rules, and decision records does not require a clean worktree. Do not run a test, build, lint, static analysis, or other local repository-backed check in the primary checkout or against uncommitted changes. Use an isolated clean worktree at the exact pushed source SHA for every such check, and verify its branch, `HEAD`, clean status, and tree fingerprint before running it. If the source SHA has not been pushed, defer local checks until it is pushed under the workflow's existing approval boundaries.

## Gather the governing evidence

Read the current WI/specification, plan, and applicable ADRs. For BrixBroker changes, confirm the branch and work-item convention against ADR-0039: locate the actual ADR file by its ID in `docs/adr/` and read it; do not guess its filename or rely on the `CLAUDE.md` summary alone. Open the canonical `.cursor/rules/005-documentation-context-hierarchy.mdc`, follow its area map, and read the rules for the touched areas. For backend changes, explicitly consult `.cursor/rules/060-dotnet-code-style-tests.mdc` and `.cursor/rules/110-cursor-workflow.mdc`; for the full ready criteria use the relevant section of `110`, and for backend test scope also use `060`. Read `docs/contexts/code-audit-mode.md` for the canonical audit rubric. Do not rely on memory or on rules assumed to have been injected. Verify decisions and accepted residues against their canonical records, such as the execution/build log and ADR decision/status sections.

Assess gate coverage in this order: (1) a PR pipeline/build validation that covers the actual diff; (2) gate output attached by the author or execution report; (3) derive only the uncovered delta from the current canonical gate rules. A pipeline is evidence only for the projects and checks it actually covers. Accept execution reports, gate output, or CI results only when they identify the exact pushed source commit/tree and cover the required checks; cross-check them against the diff rather than treating them as authoritative by themselves. If required evidence is absent or stale, continue reviewing available code and governance evidence and record the gap; do not claim a green or compliant verdict, and do not advance until mandatory gates pass and are tied to the reviewed tree. Run only that missing or invalidated delta, in a clean isolated worktree at the pushed SHA.

If a check fails and a correction is needed, stop that check cycle and route the correction to the implementation owner. Require the correction to be committed and pushed, then use a new clean isolated worktree at that exact SHA, verify its branch, `HEAD`, clean status, and tree fingerprint, and rerun only the affected or invalidated checks. Any commit or tree change makes prior check results stale. Azure pipelines run in their platform-managed checkout and must validate the same pushed SHA with a terminal result. Dev2 health and runtime checks are deployed-runtime evidence; bind them to the pipeline's `Build.SourceVersion` rather than treating them as local worktree checks.

For BrixBroker frontend changes whose gate coverage must be derived, map changed paths to project names using `platform/frontend/angular.json`, then include real consumers of changed libraries found by searching imports in the workspace. Include `core` or `design-system` only when the diff actually touches them. Read the current `110-cursor-workflow.mdc` requirements and produce the exact commands for uncovered projects; do not copy a static project list or treat a filtered subset as completion. For backend changes, derive the required projects and commands from the current `110` and `060`; include `Integration.Tests` only when the conditional trigger specified in `110` applies. Run only the missing delta, in the clean pushed-SHA worktree described above, and report pre-existing unrelated failures rather than normalizing them away.

If any mandatory governing source is absent or inaccessible, name the exact path/ID and record that limitation. Continue reviewing evidence that is available, but the verdict cannot be green/conforming while a required criterion cannot be checked. If a canonical reference cannot be found or read, do not invent its contents or silently substitute another source.

## Inspect the behavior and scope

Read the changed implementation and tests, plus neighboring examples when needed to establish a convention. Judge what the diff does, not how it is titled. Inspect security, identity, authorization, migrations, infrastructure, and deployment configuration when the diff reaches those boundaries. Confirm the change matches approved scope, honors current ADRs and rules, and has appropriate tests.

For changes that add a guard, fail-fast behavior, a limit, authorization check, header handling, or other defense, seek discriminating evidence that triggers the condition and observes its consequence. Check that new tests would fail if the intended behavior were absent; a test that only repeats the implementation or always passes is not evidence. Inspect whether described “optional” changes were necessary for the fix or are the established safe pattern in neighboring files. Do not label a convention violated without checking comparable siblings.

Check specification synchronization in both directions: implementation against the approved spec, and spec against behavior where the code exposes a meaningful undocumented change. Separate code quality from process compliance. A technically sound implementation can still have a blocking governance issue, such as an unapproved structural or security decision.

## Classify findings and decide

Use the project's canonical severity vocabulary and the audit verdicts **conforme**, **conforme com ressalvas**, and **não conforme**. Report evidence with file and line or other precise locator, explain user or system impact, and state the smallest corrective action or decision needed. Distinguish code findings, governance findings, missing evidence, and accepted decision residues. A recorded owner decision is not a finding unless new evidence changes its basis.

For an architectural finding, identify the valid goal separately from the problematic approach and describe an alternative only when repository evidence supports one. Do not invent an architecture, authorization, security, access, data, migration, or contract decision. Escalate unresolved consequential decisions to the user/owner. Any unresolved blocking finding stops progression in both workflow modes.

The report should include:

- source SHA, base SHA, branch, WI, and exact diff scope;
- verdict and blocking findings, then secondary findings and positive observations;
- WI/spec, ADR, rules, and governance/process alignment;
- available gates and CI coverage, missing checks and why, and verification limits;
- accepted decision residues that remain in force, with their canonical source;
- remaining risks, required action, and the next stage that is eligible.

Do not guarantee Azure Boards outcomes or claim a work-item link, pipeline result, deployment, or runtime behavior without observing that outcome directly. Never post a PR comment, vote, approve, or merge as part of this workflow.
