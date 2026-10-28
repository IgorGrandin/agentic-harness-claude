---
name: execute-ig
description: Executes an approved, committed BrixBroker implementation plan through dependency-aware slices with one commit per approved slice, one independent integration review of the whole run, and a final gate against the last commit on a clean tree. Use when the dev asks for "/execute-ig <WI-number|plan-path>".
argument-hint: "<WI-number|plan-path> (ex.: 3572 ou .cursor/plans/wi_3572_x.plan.md)"
disable-model-invocation: true
---

# Execute an approved plan

## Authority

Write product code only when the project instructions loaded in this session authorize `/execute-ig` to implement, from the repository's `CLAUDE.md` or the dev's personal `CLAUDE.local.md`. Without it, stop before any edit and tell the dev. Even with it:
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
| Commits | one, after the gate | one per approved slice (step 4), plus one for integration-review fixes (step 6) |
| Gate order | gate, then commit, with fingerprint binding | commit on a clean tree, then the final gate against the last commit (steps 6–7) |
| Completeness check | items 1–4 and 6 before the commit, 5 after | items 1–3 at step 6, over the whole run; 4–6 after the gate (steps 6 and 8) |
| Reuse | not covered | search before each new artifact; a missed equivalent is a deviation (step 4); reviewer checks the diff against the repository (step 5) |
| Mutant revert | `git checkout -- <file>`, then `git status --porcelain` must not list the file | `git add -- <file>` before each mutant (also for new files), then `git checkout -- <file>`, then `git diff --quiet -- <file>` (step 4) |
| Verdict | `/revise` afterwards | `/revise post-gate` in a **new session**, never this one (step 10) |
| Metrics | `rodadas.csv` | `rodadas.csv` plus `execute-rodadas.csv` (step 9) |

Shared scripts live outside the checkout. Set `$skillRoot = Join-Path $env:USERPROFILE '.claude/skills/execute-ig'`.

## 0. Start

Record the start timestamp (`Get-Date -Format o`) before anything else. Also record the repository root, branch, `HEAD`, plan path, and `git status --porcelain=v1 --untracked-files=all`.

Start only from a clean tree. If unrelated changes exist, stop and let the dev resolve the starting state. Never stash, discard, or include them.

**Base freshness (owner blockers item 10).** Before anything else touches the branch, run `git fetch --quiet origin master` and `git rev-list --count HEAD..origin/master`. If the fetch fails, tell the dev and continue; the check in step 5 reports it as UNVERIFIED. If the count is above 0, compare `git diff --name-only HEAD...origin/master` (files the new commits touch) with `git diff --name-only $(git merge-base HEAD origin/master)` (files the branch changed) and, when the argument is a plan path, with the files that plan names. Stop and show the dev, in one message: the count, `git log --oneline HEAD..origin/master`, whether the new commits touch only docs (`docs/`, `backlog/`, `*.md`), and the files in common, or "none". Then ask whether to merge `origin/master` now or continue without it:
- **Merge:** only in a fresh run (no earlier slice commits of this plan, see Run base below), because in a resumed run the merged commits would enter the integrated diff of step 5. Run `git merge --no-edit origin/master`; on a conflict, run `git merge --abort` and stop for the dev. Never push. Then record the new `HEAD` as the starting `HEAD`.
- **Continue:** item 10 stays a WARN; the run goes on and step 10 reports it.

In a resumed run, offer only continue or stop, and say why. Ask once per run: if `origin/master` moves again later, the WARN of step 5 goes to step 10 without stopping the run.

**Run base.** The run base is the `HEAD` before the first slice commit for this plan, and steps 5 and 6 cover everything from it. Look for earlier slice commits of this plan on the branch: `git log --format='%H%n%B' --grep='^Execute-Plan: <plan path>$'`. If there are none, the run base is the `HEAD` recorded above. If there are, this is a resumed run: the run base is the `Execute-Base` trailer of those commits (same command with `--format='%(trailers:key=Execute-Base,valueonly)'`), and their bodies hold the evidence of the slices already done (step 4). A resumed run never uses its own starting `HEAD` as the base, or the review would miss the earlier slices.

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
  - If every slice is committed but no valid gate evidence exists, a run stopped after its slice commits: confirm each `completed` slice has its commit on the branch, then resume at step 5 with the run base and the evidence from step 0. A `completed` slice without its commit has no evidence: treat it as pending.
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

**One commit per approved slice.** Commit only when a slice is approved, never mid-slice, per phase, or as a checkpoint. Inside a slice the checkpoint is the index (`git add`), described below. Never use `git commit -a`, `git add -A` or `git add .` during a run: during a mutant round they stage or commit the mutant itself. Stage by explicit path.

A slice is approved when all of these hold:
- its focused checks are green;
- the elected discriminant has its literal red recorded, or the plan says the slice has none;
- every mutant is reverted, and `git diff --quiet` holds for every file in the write-set (working tree equals index, so no mutant is left);
- its rows of the test traceability table are filled;
- `git status --porcelain=v1 --untracked-files=all` lists nothing outside the slice's write-set and the plan file.

Then mark the slice `completed` in the plan, stage the write-set and the plan file by explicit path, inspect `git diff --cached --stat`, and commit in the repository's message style, naming the WI and the slice ID. Never `--amend`, rebase, or squash an earlier slice commit: a later fix is a new commit. Record each slice's commit SHA.

The commit body is the slice's durable evidence, so a later session can review and report the run. It holds:
- the slice's traceability rows, with the literal red for each `[visto]`;
- the new artifacts with their reuse search terms and decisions;
- the deviations;
- the slice's implementation, review, and focused-check minutes.

It ends with three trailers: `Execute-Plan: <plan path>`, `Execute-Base: <run base SHA>`, and `Execute-Slice: <slice ID>`. Steps 5, 6, and 8 read the evidence of every slice from these bodies, not from memory.

Outside BrixBroker (see Authority), use `implementer` subagents only for slices that meet all of these:
- the slice is ready;
- its write-set is disjoint from every other running slice;
- its shared contracts are already settled.

Run each such subagent with `isolation: worktree` and brief it with the slice, its write-set, its AC IDs, its focused checks, and its **Reuso** block. Require its report to list every new artifact with the search terms used. Integration, shared files, plan status, commits, and gates stay in the main session, serially: integrate one slice's result, approve it, and commit it before integrating the next.

For each slice:
- before creating any new artifact (type, port method, handler, endpoint, component, helper, test builder or fixture, script, environment variable, configuration key, secret, feature flag, pipeline parameter), and before asking the dev to fill in any configuration value, check reuse against the slice's **Reuso** block (`plan-for-cursor` pass 12):
  - **reuse** or **extend:** use the named existing artifact. Do not create a parallel one.
  - **create new:** rerun the plan's search terms, and search once more by the behavior's verb and domain noun. The code may have moved since the SHA-base, and the plan's search may have been narrow.
  - **not in the block** (a helper the plan did not foresee, or a missing block): search the same way before creating it.
  - **configuration:** search for the value the setting carries (URL, host, timeout, connection string), not only its name, across the places listed in pass 12. The same key changes shape between layers (`Smtp:Host` in `appsettings` is `Smtp__Host` in the environment). Never tell the dev to set a variable the repository already defines.

  If the search finds an equivalent the plan missed, reuse it when that stays inside the slice's write-set and changes no shared or public contract, and record it as a deviation (`execute.md` §2). Otherwise it changes the plan: apply "Decisions during execution" below. Record the search terms for every artifact the slice creates, so the reviewer can check them;
- run the focused checks, scoped to the slice: the tests the slice adds or changes, with `--filter` or the project's targeted command. A focused check is not the gate. Never run `devops/scripts/run-gate.ps1`, a whole gate project, or the full suite per slice: the gate runs once, in step 7, against the last commit;
- keep the literal red output for the elected discriminant;
- when a mutant round applies (`execute.md` §"Rodadas de mutante"), before **each** mutant run `git add -- <file>` on the implementation file, then apply the mutant. Re-stage before every mutant: the implementation changes between mutants, so an earlier stage is stale. A new file needs the same `git add`, or the checkout fails with `pathspec did not match`. Revert only with `git checkout -- <file>`, which restores from the index, so the staged implementation survives (without the stage, the checkout also discards the implementation). Confirm the revert with `git diff --quiet -- <file>` (working tree equals index), never with `git status --porcelain`: with the stage it still lists `M  <file>`, and without it the list is empty exactly when the implementation was lost. Never restore from a copy (it keeps the old timestamp and MSBuild reuses the mutant binary). If a permission rule blocks that command, stop and tell the dev;
- fill the slice's rows of the test traceability table from `execute.md` §5, one row per plan test ID, with the assertion's `path:line`, the label, and the literal red for each `[visto]`;
- record changed paths, results, and elapsed time.

Update slice status serially, using only the vocabulary the plan already supports: `in_progress` before starting, `completed` in the slice's own commit. `completed` means the slice was approved, not that the integration review passed; a review finding reopens it as a new fix commit (step 6). The plan's gate todo stays pending after a successful gate; the external report records the gate. A tracked post-gate edit would change the delivered tree.

If the same failure survives two correction attempts, or the code contradicts the plan, stop the dependent slices and take it to the dev. Do not silently change scope.

### Decisions during execution

When a finding needs a decision the plan does not cover (product, ADR, scope or release, public contract):
1. Stop the work that depends on it.
2. Bring the options and your recommendation to the dev, and decide together.
3. Record the decision in the Work Item's "Decisões do dev" section and its mirror, in the decision record's format, after the dev confirms the text. Commit the mirror on its own with `git commit --only -- <mirror file>`, so the index (which may hold a slice's staged implementation) stays out of that commit.
4. Correct the plan where the decision changes it, rerun the preflight on the changed part, and continue.

## 5. Integration review (before step 6)

First run the deterministic part of the owner's blockers list from the repository root: `& (Join-Path $skillRoot 'scripts/check-owner-blockers.ps1')`. It compares the working tree with the merge-base of `origin/master`.
- **Exit 1 (BLOCK):** fix each finding in the main session and run it again.
- **Exit 2 (UNVERIFIED):** a check could not run, usually `az login` for the dev2 deploy lookup or the fetch of `origin/master`. Resolve it before step 6; never treat it as clean.
- **WARN:** goes to the reviewer below, who judges whether each one is justified. Item 10 (branch behind `origin/master`, with the commit count) was the dev's call in step 0: do not merge now, do not ask again, and do not hand it to the reviewer.

Send the integrated diff to the `reviewer` subagent once, in fresh context. The integrated diff is `git diff <run base>` (step 0), which spans every slice commit of the run, including those of an earlier session, plus any uncommitted change; `git diff` alone shows only the uncommitted part. Take the traceability table, the artifact search terms, and the deviations from the slice commit bodies. Brief it with:
- `.cursor/commands/execute-code-review.md`, covering the Standards and Spec axes;
- the owner's recurring blockers list in the repository's `CLAUDE.local.md`, when present, with the check's WARN findings: check the diff against each item the touched area reaches, and report a violation as a Standards finding citing the item number;
- the plan, its coverage matrix, and the test traceability table;
- the instruction to check the table against the plan, not the diff: every plan test ID needs a row, and each row's assertion must observe its obligation;
- the instruction to derive missing behavior scenarios from the spec, not only from the named tests;
- the list of new artifacts with the search terms recorded in the slice commits, and the instruction to search the repository, outside the diff, for an existing equivalent of each: a duplicate of existing code is a Standards finding, and a plan **reuse** or **extend** decision that the diff did not follow is a Spec finding.

Require the full list of rules the Standards axis opened, always including `110`.

Fix accepted findings in the main session, or return them to the slice's implementer, then re-review only the affected part. Do not treat a gate that has not run yet as a finding.

## 6. Commit

The slices are already committed (§4). This step commits only what the integration review changed. Run completeness items 1–3 of `execute.md` (discriminant, traceability, rules opened) over the whole run, reading the earlier slices' evidence from their commit bodies. An incomplete report is completed first, or its blocker is declared in the report.

If the review led to fixes, stage only the intended implementation and plan files, inspect the staged diff, and create a new descriptive commit in the repository's message style. If nothing changed, create no commit; the last slice commit is the one the gate observes. Never `--amend` or `--no-verify`.

Confirm that `git rev-parse HEAD` is the commit to gate and that `git status --porcelain=v1 --untracked-files=all` is empty. If the tree is not clean, resolve ownership before any gate.

## 7. Final gate against the commit

"The commit" from here on is the gated commit: `HEAD` after step 6, the last commit of the run. It is the `-CommitSha` below, the report's commit, and the metrics' `commit_sha`. Slice commit SHAs appear only in the report's slice table.

1. Freeze the checkout: no writer runs during the gate.
2. Resolve the artifact paths:

   ```powershell
   & (Join-Path $skillRoot 'scripts/resolve-artifact-paths.ps1') -WorkItem <id> -CommitSha <sha> -AsJson
   ```

   The resolver accepts only the existing `claude-handoffs/Broker/` root that holds both `execute-gates` and `execute-reports`.
3. Choose the gate projects by the triggers in rules `110` and `060`, as `execute.md` §4 requires. Run `docker info` first when `Integration` or `HostSmoke` is in the list; if Docker does not answer, stop and report.
4. Send the gate to the `verifier` subagent with:
   - the commit SHA;
   - the owner blockers trap, run before the gate: `& (Join-Path $env:USERPROFILE '.claude/skills/execute-ig/scripts/check-owner-blockers.ps1')`. Exit 0 is required; 1 is red and 2 is unverified;
   - `devops/scripts/run-gate.ps1 -OutDir <GateOutDir>`;
   - the project list, passed as an in-process splat (`$splat = @{ BackendProjects = @('a.csproj','b.csproj'); OutDir = '<GateOutDir>' }; & .\devops\scripts\run-gate.ps1 @splat`) or with `-File` (a comma list arrives as one string, which the script splits; valid since `c71b5c01`).

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

Write the report at the resolved `ReportPath`, using exactly the template from `execute.md` §5, then run completeness items 4–6 (Docker evidence, fingerprint line, gates not run). Three adjustments:
- **`Commit` field:** the gated commit, followed by `run base: <Execute-Base>` and the number of commits in `<run base>..<gated commit>`. The template has one field because `execute.md` makes one commit.
- **Gate section:** the manifest `HEAD` equals the commit. Instead of the post-commit binding paragraph, record the observed `HEAD`, the branch, the clean-tree status, and the line `fingerprint pós-commit: <literal output> · igual ao do manifesto: sim|não`.
- **Slice table:** add the per-slice table from [references/metrics.md](references/metrics.md), built from the slice commit bodies for slices done in an earlier session.

## 9. Metrics

Append the `rodadas.csv` line that `execute.md` §7 defines. Then append the detailed row with `scripts/append-metrics.ps1`, following [references/metrics.md](references/metrics.md).

Record blocked or interrupted runs too. Leave token counts blank when the host does not expose them.

## 10. Hand off

Tell the dev:
- the report path, commit SHA, and gate status;
- the slice outcomes, correction rounds, and deviations;
- the time spent per stage;
- every WARN of the owner blockers trap's last run, verbatim, including item 10 with how many commits `origin/master` is ahead.

The next step is `/revise post-gate` in a **new session**, because the implementing session must not audit its own delivery. Do not push or open a PR unless the dev asks.

Never claim a gate passed if it was skipped, failed, or observed another commit or tree.
