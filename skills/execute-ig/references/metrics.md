# Execution metrics record

Every `/execute-ig` run writes two durable records, both under `%USERPROFILE%\.claude\brixbroker\`, never in `%TEMP%`:

1. **One line in `rodadas.csv`**, as the repository's `.cursor/commands/execute.md` step 7 defines: `fase=execute` and the shared header the `/revise` also writes to.
2. **One detailed row in `execute-rodadas.csv`**, appended with `scripts/append-metrics.ps1`.

Preserve both headers and append only. Values describe observed time and outcomes, including blocked or interrupted runs.

The canonical semicolon-delimited header of `execute-rodadas.csv` is:

```text
started_at;finished_at;plan;branch;commit_sha;root_model;root_effort;peak_workers;slices_total;slices_passed;correction_rounds;implementation_minutes;slice_review_minutes;focused_verification_minutes;integration_review_minutes;final_gate_minutes;post_gate_review_minutes;total_minutes;gate_status;gate_sha;tree_clean;slice_models;input_tokens;output_tokens
```

Field rules:

- **Timestamps:** ISO 8601 with an explicit offset.
- **Durations:** decimal minutes, rounded to one decimal place.
- **`peak_workers`:** the largest number of `implementer` subagents running at once; `0` when the main session implemented everything.
- **`post_gate_review_minutes`:** stays `0`. The post-gate `/revise` runs in a separate session and records its own line in `rodadas.csv`.
- **`gate_status`:** `PASSED`, `FAILED`, `NOT_RUN`, or `INVALIDATED`.
- **`gate_sha`:** the commit the final gate actually observed. When the status is `PASSED`, it must equal `commit_sha`.
- **`tree_clean`:** the observed post-gate result (`true`/`false`).
- **`slice_models`:** compact JSON mapping slice IDs to the model and effort actually used. Example: `{"S1":{"model":"sonnet","effort":"medium"},"S2":{"model":"opus","effort":"high"}}`.
- **Token counts:** integers only when the host exposes them; blank means unavailable. Never substitute estimates.

The Markdown report follows the template in `.cursor/commands/execute.md` step 5. Add one row per slice with:
- slice ID, owner (`main` or `implementer`), write-set, and model/effort;
- implementation, review, and focused-check time;
- findings, correction rounds, and final status.
