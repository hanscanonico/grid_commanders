---
name: orchestrate
description: Make the session model (Fable) orchestrate instead of working — any task the user gives is delegated to Opus subagents with effort set by role (scouts low, implementers medium with one retry at high, reviewers high, QA low), using the same agent kit as /improve. Use when the user invokes /orchestrate <task>, asks you to "delegate this", "don't do it yourself", or "spawn agents for this".
---

# /orchestrate — delegate the given task, never do it

The session model is the ORCHESTRATOR and does not implement, research or review directly.
Everything substantive goes to the agents in `.claude/agents/`, every one on the latest
Opus available (`model: opus` — the alias, never Fable, never a dated Opus id), effort set
by role: `scout` low, `implementer` medium (the `improve` workflow retries once at high on
a red gate or a reject), `reviewer` high, `qa` low. Main-loop work is only: understanding
the ask, splitting it, launching agents, reading their structured results, merging when
authorized, and short user-facing summaries.

Direct work is allowed only for trivia: single-file config/memory/doc edits, git and gh
plumbing, small reads for triage.

## Loop

1. **Understand.** Read `$ARGUMENTS` (the task). If the task needs codebase knowledge you
   don't already hold, spawn 1–3 `scout` agents (`subagent_type: 'scout'`) to research it
   and return diff-concrete specs: title, files, spec, verification, risk, size (S/M, one
   agent ≤90 min). Don't read across the repo yourself.
2. **Split.** Cut the task into disjoint slices — no two slices in one batch may share a
   hot file (battle.gd, shared test helpers, CLAUDE.md). A small task is one slice. Write
   each slice's spec to a scratchpad file the brief points at. Check `git worktree list`
   first; never scope into an area another session owns.
3. **Run.** `Workflow({ name: 'improve', args: { tasks: [{slug, task, reviewNote}...],
   trailers: <this session's commit trailers>, footer: <this session's PR footer> } })` —
   each slice becomes one PR by an `implementer` agent, adversarially reviewed in the same
   worktree by a `reviewer` agent, with one retry at high effort on a red gate or a reject.
   Use the workflow even for a single slice: the Agent tool has no effort override, so a
   direct `implementer` → `reviewer` pair cannot retry at high — reserve that pair for a
   slice where no retry would be wanted. Non-code deliverables (a report, a measurement, a
   doc) go to a `scout` when they are read-only, otherwise to a `general-purpose` agent
   (`model: 'opus'` as always, the session's effort) with the same spec shape and a structured return.
4. **Merge.** Read verdicts. **Merge only if the user has authorized merging**; otherwise
   leave PRs open and report them. Merge sequentially: `gh pr merge N --squash`; on a
   stale-branch error `gh pr update-branch N`, wait ~25s, retry. After each merged branch:
   `git -C <main checkout> worktree remove .claude/worktrees/improve-<slug> --force` and
   delete the local branch.
5. **QA.** After UI-touching work, spawn a `qa` agent over the main checkout: `make smoke`,
   then the frames read as images — the sweep's byte floor passes blank frames.
6. **Wrap.** Summarize what shipped, what is open, and what the agents found wrong with
   the ask; record durable findings in memory.

## Hard rules

- Nothing merges without both: implementer's `make verify` green AND reviewer approve — on
  a retried slice, the retry's own gate and review.
- One retry, never more: a slice still red or rejected after its high-effort attempt is
  reported to the user, not re-queued.
- Reviewers verify claims independently and may push small fixes; fundamental problems
  are rejected, never rewritten in review.
- An honest "this task is wrong / already done" report from an agent is relayed to the
  user, not overridden.
- Balance numbers move only with measurement.
- If you catch yourself opening source files to implement or review, stop and delegate.
