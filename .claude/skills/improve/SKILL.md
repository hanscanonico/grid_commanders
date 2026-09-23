---
name: improve
description: Orchestrate repo improvements through Opus subagents — scout tasks, run the implement→adversarial-review pipeline (one PR per task, one retry at high effort on a red gate or a reject), merge only with the user's authorization. Use when the user asks to improve the game, run an improvement batch, work through a backlog, or invokes /improve (optionally with a focus area or "overnight until <time>").
---

# /improve — delegated improvement pipeline

The session model (often Fable) is the ORCHESTRATOR: it never implements. Coding, review,
research and QA go to the agents in `.claude/agents/`, every one on the latest Opus
available (`model: opus` — the alias, never Fable, never a dated Opus id), effort set by
role: `scout` low, `implementer` medium (the workflow retries once at high on a red gate or
a reject), `reviewer` high, `qa` low. Main-loop work is only: choosing tasks, launching
workflows, reading structured verdicts, merging, cleanup, and summaries.

## Loop

1. **Scope.** Given concrete tasks, go to 3. Given a broad goal (or none), spawn 2–4 `scout`
   agents (`subagent_type: 'scout'`) over distinct areas (player-facing UX, tech health,
   content quality — pick lenses that fit the goal). Each returns 5–8 items with
   diff-concrete specs: title, value, files, spec, verification, risk, size (S/M, one agent
   ≤90 min).
2. **Triage.** Pick disjoint items — no two tasks in one batch may share a hot file
   (battle.gd, shared test helpers, CLAUDE.md). Write each spec to a scratchpad file the
   task brief points at. Check `git worktree list` and dirty sibling worktrees first;
   never scope into an area another session owns.
3. **Batch.** `Workflow({ name: 'improve', args: { tasks: [{slug, task, reviewNote}...],
   trailers: <this session's commit trailers>, footer: <this session's PR footer> } })` —
   4–6 tasks per batch. Each task becomes one PR by an `implementer` agent, adversarially
   reviewed in the same worktree by a `reviewer` agent. A red gate or a reject earns exactly
   one retry: the implementer again at high effort with the reviewer's reasons, then a
   fresh review. Each result carries a `verdict` read from the last attempt: approve,
   reject, verify_failed, abandoned, unreviewed or no_result.
4. **Merge.** Read verdicts from the workflow journal. **Merge only if the user has
   authorized merging** (e.g. "merge it yourself"); otherwise leave PRs open. Merge
   sequentially: `gh pr merge N --squash`; on a stale-branch error `gh pr update-branch N`,
   wait ~25s, retry. After each merged branch:
   `git -C <main checkout> worktree remove .claude/worktrees/improve-<slug> --force` and
   delete the local branch.
5. **Repeat** while there are tasks and time. After UI-touching batches, run a `qa` agent
   over the main checkout: full `make smoke`, then the frames read as images — the sweep's
   byte floor passes blank frames, so only eyes catch a layout regression. Feed findings
   into the next batch.
6. **Wrap.** Summarize merged PRs by theme; record durable findings in memory.

## Hard rules

- Nothing merges without both: implementer's `make verify` green AND reviewer approve — on
  a retried task, the retry's own gate and review.
- One retry, never more: a task still red or rejected after its high-effort attempt is
  reported to the user, not re-queued.
- Reviewers verify claims independently — revert-run-restore for tests, re-capture for
  pixels, re-record for measurements — and may push small fixes; fundamental problems are
  rejected, never rewritten in review.
- An honest "this task is wrong / already done" report is a good outcome, not a failure.
- Balance numbers move only with measurement; out-of-band results are recorded as review
  triggers, never tuned in passing.
