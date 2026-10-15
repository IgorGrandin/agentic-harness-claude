---
name: execute
description: Execute an approved, committed implementation plan in BrixBroker through dependency-aware slices, one independent integration review, a commit on a clean tree, and a final gate against that exact commit. Use when the owner asks for "/execute <WI-number|plan-path>".
argument-hint: "<WI-number|plan-path> (ex.: 3572 ou .cursor/plans/wi_3572_x.plan.md)"
disable-model-invocation: true
---

# Execute an approved plan

## Authority

Write product code only when the project instructions loaded in this session authorize `/execute` to implement. That authorization can come from the repository's `CLAUDE.md` or from the owner's personal `CLAUDE.local.md`. Without it, stop before any edit and tell the owner. Even with it:
- the plan must be approved and committed under `.cursor/plans/`;
- the plan is the scope ceiling. Anything it does not order is not implemented "in passing".

The owner configures permissions, never this skill. If a permission rule (such as a project `deny`) blocks `Edit` or `Write` on product paths, stop and report it. Never work around a permission rule through the shell or by editing settings files.

In BrixBroker, implement slices in the main session only, without `implementer` subagents in worktrees. Whether a worktree subagent inherits the session's permissions and instructions is unverified.

## Contract source

The repository's own `.cursor/commands/execute.md` is the contract for this workflow. Open it and follow it in full, including what it opens in turn:
- the preflight, via `.cursor/commands/analise.md` with `modo=preflight-execute`;
- TDD, via `.cursor/commands/execute-tdd.md`;
- the two-axis review, via `.cursor/commands/execute-code-review.md`;
- the gate rules `110` and `060`;
- the report template;
- the `rodadas.csv` line.

Do not copy those files here. The deltas below are the only intended differences.

| Topic | `.cursor/commands/execute.md` | This skill |
|---|---|---|
| Plan resolution | context, explicit path, or newest plan | exact WI resolver; never by recency (step 1) |
| Implementation | one executor | main session; `implementer` subagents only for parallel slices (step 4) |
| Review | executor runs the two axes | one `reviewer` subagent pass in fresh context on the integrated diff (step 5) |
| Gate order | gate, then commit, with fingerprint binding | commit on a clean tree, then the final gate against that commit (steps 6–7) |
| Verdict | `/revise` afterwards | `/revise post-gate` in a **new session**, never this one (step 10) |
| Metrics | `rodadas.csv` | `rodadas.csv` plus `execute-rodadas.csv` (step 9) |

Shared scripts live outside the checkout. Set `$skillRoot = Join-Path $env:USERPROFILE '.claude/skills/execute'`.

## 0. Start

Record the start timestamp (`Get-Date -Format o`) before anything else. Also record the repository root, branch, `HEAD`, plan path, and `git status --porcelain=v1 --untracked-files=all`.

Start only from a clean tree. If unrelated changes exist, stop and let the owner resolve the starting state. Never stash, discard, or include them.

## 1. Resolve the plan

For a WI number, run:

```powershell
& (Join-Path $skillRoot 'scripts/resolve-plan.ps1') -WorkItemOrPlan <WI> -PlanDirectory (Join-Path (git rev-parse --show-toplevel) '.cursor/plans') -AsJson
```

Handle each outcome:

- **`selected`:** read the full plan and validate it against the real code and diff state.
- **`explicit`:** the path selects the plan's identity, and `Candidates[0].Progress` gives its slice state.
  - Continue only the slices still pending in the current diff.
  - Progress `complete` or `gate_pending` means `needs_evidence_review`; `unknown` means `needs_status_review`.
  - An explicit path never authorizes replaying completed work.
- **`ambiguous`:** list the matching plans with their objectives and remaining items, and ask the owner. A unique `execution_order` or a unique dependency predecessor may resolve the choice.
- **`needs_evidence_review`:** completed metadata is not proof, and you must not replay slices or rerun a gate by habit.
  - Check the existing report and metrics against the plan, branch, commit SHA, gate SHA, and clean-tree evidence.
  - If valid evidence already proves the final gate, report that no work remains.
- **`blocked`, `needs_status_review`, `no_match`:** inspect the plan's native status and the current diff, and resolve the blocker before implementing.

Confirm the plan file is committed. If it is not, stop: only committed plans are executable.

## 2. Preflight and coverage

- **Preflight:** run it exactly as `execute.md` §1 orders. Every 🔴 or 🟡 is fixed in the plan before code, and the preflight runs again. A finding that needs a product, ADR, or release decision stops the run for the owner.
- **Coverage contract:** owned by `plan-for-cursor` (pass 11, `references/coverage-contract.md`). The plan needs:
  - the coverage matrix;
  - the slice graph (owner, write-set, dependencies, parallel safety);
  - the `reviewer` challenge record.
- **Reusing the challenge:** reuse it when the spec, baseline, and matrix are unchanged. Otherwise update only the affected coverage and challenge that delta.

Then give the owner a short summary and proceed without asking for another approval. Include the objective, remaining slices and parallel groups, focused checks, and the final gate.

## 3. Change-task deltas

When the plan comes from `/change-task`, treat it as a new delta:
- Revalidate its base SHA against the current diff.
- Reopen only the affected acceptance behaviors and their evidence.
- Run the focused checks for that delta.

A gate for an earlier SHA never validates the changed tree.

## 4. Implement slices

The main session implements, following `execute-tdd.md`. Work one slice at a time, observe red before green, and record the deviation rules of `execute.md` §2.

Outside BrixBroker (see Authority), use `implementer` subagents only for slices that meet all of these:
- the slice is ready;
- its write-set is disjoint from every other running slice;
- its shared contracts are already settled.

Run each such subagent with `isolation: worktree` and brief it with the slice, its write-set, its AC IDs, and its focused checks. Integration, shared files, plan status, commits, and gates stay in the main session, serially.

For each slice:
- run the focused checks;
- keep the red evidence for the elected discriminant;
- record changed paths, results, and elapsed time.

Update slice status serially, using only the vocabulary the plan already supports: `in_progress` before starting, `completed` after the integration review passes. The plan's gate todo stays pending after a successful gate; the external report records the gate. A tracked post-gate edit would change the delivered tree.

If the same failure survives two correction attempts, or the code contradicts the plan, stop the dependent slices and take it to the owner. Do not silently change scope.

## 5. Integration review (before commit)

Send the integrated diff to the `reviewer` subagent once, in fresh context. Brief it with:
- `.cursor/commands/execute-code-review.md`, covering the Standards and Spec axes;
- the plan and its coverage matrix;
- the instruction to derive missing behavior scenarios from the spec, not only from the named tests.

Require the list of rules the Standards axis opened; the report needs it.

Fix accepted findings in the main session, or return them to the slice's implementer, then re-review only the affected part. Do not treat a gate that has not run yet as a finding.

## 6. Commit

Stage only the intended implementation and plan files and inspect the staged diff. Create a new descriptive commit in the repository's message style. Never `--amend` or `--no-verify`.

Confirm that `git rev-parse HEAD` is the new commit and that `git status --porcelain=v1 --untracked-files=all` is empty. If the tree is not clean, resolve ownership before any gate.

## 7. Final gate against the commit

1. Freeze the checkout: no writer runs during the gate.
2. Resolve the artifact paths:

   ```powershell
   & (Join-Path $skillRoot 'scripts/resolve-artifact-paths.ps1') -WorkItem <id> -CommitSha <sha> -AsJson
   ```

   The resolver accepts only the existing `claude-handoffs\Broker\` root that holds both `execute-gates` and `execute-reports`.
3. Choose the gate projects by the triggers in rules `110` and `060`, as `execute.md` §4 requires. Run `docker version` first when `Integration` or `HostSmoke` is in the list.
4. Send the gate to the `verifier` subagent with:
   - the commit SHA;
   - `devops/scripts/run-gate.ps1 -OutDir <GateOutDir>`;
   - the project list.

   It runs the gate in the background and checks `HEAD` and the clean tree before and after.
5. The run is valid only when the manifest `HEAD` equals the commit and the tree stayed clean.

On a red gate:
1. Fix the failure with filtered checks.
2. Commit the fix as a new commit.
3. Run the gate once more against that commit.

Never report an earlier commit's gate as validation for a fix. Never edit code or amend after a successful gate.

## 8. Report

Write the report at the resolved `ReportPath`, using exactly the template from `execute.md` §5. Two adjustments:
- **Gate section:** the manifest `HEAD` equals the commit. Replace the post-commit binding paragraph with the observed `HEAD`, the branch, and the clean-tree status after the gate.
- **Slice table:** add the per-slice table from [references/metrics.md](references/metrics.md).

## 9. Metrics

Append the `rodadas.csv` line that `execute.md` §7 defines. Then append the detailed row with `scripts/append-metrics.ps1`, following [references/metrics.md](references/metrics.md).

Record blocked or interrupted runs too. Leave token counts blank when the host does not expose them.

## 10. Hand off

Tell the owner:
- the report path, commit SHA, and gate status;
- the slice outcomes, correction rounds, and deviations;
- the time spent per stage.

The next step is `/revise post-gate` in a **new session**, because the implementing session must not audit its own delivery. Do not push or open a PR unless the owner asks.

Never claim a gate passed if it was skipped, failed, or observed another commit or tree.
