---
name: my-execute
description: Executes an approved, committed BrixBroker implementation plan through dependency-aware slices, one independent integration review, a commit on a clean tree, and a final gate against that exact commit. Use when the dev asks for "/my-execute <WI-number|plan-path>".
argument-hint: "<WI-number|plan-path> (ex.: 3572 ou .cursor/plans/wi_3572_x.plan.md)"
disable-model-invocation: true
---

# Execute an approved plan

## Authority

Write product code only when the project instructions loaded in this session authorize `/my-execute` to implement, from the repository's `CLAUDE.md` or the dev's personal `CLAUDE.local.md`. Without it, stop before any edit and tell the dev. Even with it:
- the plan must be approved and committed under `.cursor/plans/`;
- the plan is the scope ceiling. Anything it does not order is not implemented "in passing".

The dev configures permissions, never this skill. If a permission rule (such as a project `deny`) blocks `Edit` or `Write` on product paths, stop and report it. Never work around a permission rule through the shell or by editing settings files.

In BrixBroker, implement slices in the main session only, without `implementer` subagents in worktrees. Whether a worktree subagent inherits the session's permissions and instructions is unverified.

## Contract source

The repository's own `.cursor/commands/execute.md` is the contract for this workflow. Open it and follow it in full, including what it opens in turn:
- the preflight, via `.cursor/commands/analise.md` with `modo=preflight-execute`;
- TDD, via `.cursor/commands/execute-tdd.md`;
- the two-axis review, via `.cursor/commands/execute-code-review.md`;
- the gate rules `110` and `060`;
- the report template, the test traceability table, and the completeness check;
- the `rodadas.csv` line.

Do not copy those files here. The deltas below are the only intended differences.

| Topic | `.cursor/commands/execute.md` | This skill |
|---|---|---|
| Plan resolution | context, explicit path, or newest plan | exact WI resolver; never by recency (step 1) |
| Decisions | the plan | the Work Item's "Decisões do dev" section is the source of truth (step 1) |
| Implementation | one executor | main session; `implementer` subagents only for parallel slices outside BrixBroker (step 4) |
| Review | executor runs the two axes | one `reviewer` subagent pass in fresh context on the integrated diff (step 5) |
| Gate order | gate, then commit, with fingerprint binding | commit on a clean tree, then the final gate against that commit (steps 6–7) |
| Completeness check | items 1–4 and 6 before the commit, 5 after | items 1–3 before the commit; 4–6 after the gate (steps 6 and 8) |
| Verdict | `/revise` afterwards | `/revise post-gate` in a **new session**, never this one (step 10) |
| Metrics | `rodadas.csv` | `rodadas.csv` plus `execute-rodadas.csv` (step 9) |

Shared scripts live outside the checkout. Set `$skillRoot = Join-Path $env:USERPROFILE '.claude/skills/my-execute'`.

## 0. Start

Record the start timestamp (`Get-Date -Format o`) before anything else. Also record the repository root, branch, `HEAD`, plan path, and `git status --porcelain=v1 --untracked-files=all`.

Start only from a clean tree. If unrelated changes exist, stop and let the dev resolve the starting state. Never stash, discard, or include them.

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
- **`ambiguous`:** list the matching plans with their objectives and remaining items, and ask the dev. A unique `execution_order` or a unique dependency predecessor may resolve the choice.
- **`needs_evidence_review`:** completed metadata is not proof, and you must not replay slices or rerun a gate by habit.
  - Check the existing report and metrics against the plan, branch, commit SHA, gate SHA, and clean-tree evidence.
  - If valid evidence already proves the final gate, report that no work remains.
- **`blocked`, `needs_status_review`, `no_match`:** inspect the plan's native status and the current diff, and resolve the blocker before implementing.

Confirm the plan file is committed. If it is not, stop: only committed plans are executable.

Consult the "Decisões do dev" section **in the Work Item itself**, through the `azure-devops` MCP or the `az rest` fallback in `plan-task` §1. Under the decision record of `plan-task` (`references/decisions.md`), the Work Item is the source of truth; the plan and the mirror `backlog/tasks` file are copies.
- If the plan's "Decisões (não reabrir)" diverges from the Work Item, stop and show the divergence. The Work Item wins; fix the plan with the dev before continuing.
- If the mirror diverges, report it and correct it in its own commit.
- If the Work Item cannot be read, stop and tell the dev. Use the mirror as a substitute only with their authorization, and record that in the report.

## 2. Preflight and coverage

- **Preflight:** run it exactly as `execute.md` §1 orders. Every 🔴 or 🟡 is fixed in the plan before code, and the preflight runs again.
- **Coverage contract:** owned by `plan-for-cursor` (pass 11, `references/coverage-contract.md`). The plan needs:
  - the coverage matrix;
  - the slice graph (owner, write-set, dependencies, parallel safety);
  - the `reviewer` challenge record.
- **Reusing the challenge:** reuse it when the spec, baseline, and matrix are unchanged. Otherwise update only the affected coverage and challenge that delta.

Then proceed without asking for approval again.

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
- keep the literal red output for the elected discriminant;
- fill the slice's rows of the test traceability table from `execute.md` §5, one row per plan test ID, with the assertion's `path:line`, the label, and the literal red for each `[visto]`;
- record changed paths, results, and elapsed time.

Update slice status serially, using only the vocabulary the plan already supports: `in_progress` before starting, `completed` after the integration review passes. The plan's gate todo stays pending after a successful gate; the external report records the gate. A tracked post-gate edit would change the delivered tree.

If the same failure survives two correction attempts, or the code contradicts the plan, stop the dependent slices and take it to the dev. Do not silently change scope.

### Decisions during execution

When a finding needs a decision the plan does not cover (product, ADR, scope or release, public contract):
1. Stop the work that depends on it.
2. Bring the options and your recommendation to the dev, and decide together.
3. Record the decision in the Work Item's "Decisões do dev" section and its mirror, in the decision record's format, after the dev confirms the text. Commit the mirror on its own, staging only that file.
4. Correct the plan where the decision changes it, rerun the preflight on the changed part, and continue.

## 5. Integration review (before commit)

Send the integrated diff to the `reviewer` subagent once, in fresh context. Brief it with:
- `.cursor/commands/execute-code-review.md`, covering the Standards and Spec axes;
- the plan, its coverage matrix, and the test traceability table;
- the instruction to check the table against the plan, not the diff: every plan test ID needs a row, and each row's assertion must observe its obligation;
- the instruction to derive missing behavior scenarios from the spec, not only from the named tests.

Require the full list of rules the Standards axis opened, always including `110`.

Fix accepted findings in the main session, or return them to the slice's implementer, then re-review only the affected part. Do not treat a gate that has not run yet as a finding.

## 6. Commit

Run completeness items 1–3 of `execute.md` (discriminant, traceability, rules opened). An incomplete report is completed first, or its blocker is declared in the report.

Stage only the intended implementation and plan files and inspect the staged diff. Create a new descriptive commit in the repository's message style. Never `--amend` or `--no-verify`.

Confirm that `git rev-parse HEAD` is the new commit and that `git status --porcelain=v1 --untracked-files=all` is empty. If the tree is not clean, resolve ownership before any gate.

## 7. Final gate against the commit

1. Freeze the checkout: no writer runs during the gate.
2. Resolve the artifact paths:

   ```powershell
   & (Join-Path $skillRoot 'scripts/resolve-artifact-paths.ps1') -WorkItem <id> -CommitSha <sha> -AsJson
   ```

   The resolver accepts only the existing `claude-handoffs/Broker/` root that holds both `execute-gates` and `execute-reports`.
3. Choose the gate projects by the triggers in rules `110` and `060`, as `execute.md` §4 requires. Run `docker info` first when `Integration` or `HostSmoke` is in the list; if Docker does not answer, stop and report.
4. Send the gate to the `verifier` subagent with:
   - the commit SHA;
   - `devops/scripts/run-gate.ps1 -OutDir <GateOutDir>`;
   - the project list.

   It runs the gate in the background and checks `HEAD` and the clean tree before and after.
5. Read the manifest. The evidence is valid only when `status` is `VALID`, the manifest `HEAD` equals the commit, and the tree stayed clean. The gate passed only when `result` is `GREEN`: `status=VALID` with `result=RED` is a valid red gate. Then run `devops/scripts/run-gate.ps1 -FingerprintOnly` and confirm the output equals the manifest's `gateTreeFingerprint`.

The gate script stops early on environment problems. Treat these as environment issues, not code failures:
- **Exit 3:** Docker did not answer or could not start a container. Ask the dev to restart Docker Desktop (or the machine). If Docker is working but slow, the dev can raise `RUN_GATE_DOCKER_PROBE_TIMEOUT_SEC`.
- **Exit 5:** the frontend directory does not exist.
- **`dockerCanary: image-missing`:** only a warning; the gate continues.
- **Frontend red:** backend projects not yet started show as `skipped` in the manifest. Use the per-target log and the first error line in the manifest to diagnose.
- **No `result` field in the manifest:** the branch predates the gate-script update. Ask the dev to merge `origin/master` into the branch, then commit and gate again. Do not merge on your own.

On a red gate:
1. Fix the failure with filtered checks.
2. Commit the fix as a new commit.
3. Run the gate once more against that commit.

Never report an earlier commit's gate as validation for a fix. Never edit code or amend after a successful gate.

## 8. Report

Write the report at the resolved `ReportPath`, using exactly the template from `execute.md` §5, then run completeness items 4–6 (Docker evidence, fingerprint line, gates not run). Two adjustments:
- **Gate section:** the manifest `HEAD` equals the commit. Instead of the post-commit binding paragraph, record the observed `HEAD`, the branch, the clean-tree status, and the line `fingerprint pós-commit: <literal output> · igual ao do manifesto: sim|não`.
- **Slice table:** add the per-slice table from [references/metrics.md](references/metrics.md).

## 9. Metrics

Append the `rodadas.csv` line that `execute.md` §7 defines. Then append the detailed row with `scripts/append-metrics.ps1`, following [references/metrics.md](references/metrics.md).

Record blocked or interrupted runs too. Leave token counts blank when the host does not expose them.

## 10. Hand off

Tell the dev:
- the report path, commit SHA, and gate status;
- the slice outcomes, correction rounds, and deviations;
- the time spent per stage.

The next step is `/revise post-gate` in a **new session**, because the implementing session must not audit its own delivery. Do not push or open a PR unless the dev asks.

Never claim a gate passed if it was skipped, failed, or observed another commit or tree.
