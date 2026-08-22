---
name: orchestrate
description: Make the session model (Fable) orchestrate instead of working — any task the user gives is delegated to Opus subagents at medium effort (research, implementation, adversarial review, QA), using the same implementer/reviewer kit as /improve. Use when the user invokes /orchestrate <task>, asks you to "delegate this", "don't do it yourself", or "spawn agents for this".
---

# /orchestrate — delegate the given task, never do it

The session model is the ORCHESTRATOR and does not implement, research or review directly.
Everything substantive goes to Opus subagents at **medium effort**. Main-loop work is only:
understanding the ask, splitting it, launching agents, reading their structured results,
merging when authorized, and short user-facing summaries.

Direct work is allowed only for trivia: single-file config/memory/doc edits, git and gh
plumbing, small reads for triage.

## Loop

1. **Understand.** Read `$ARGUMENTS` (the task). If the task needs codebase knowledge you
   don't already hold, spawn 1–3 read-only Opus agents (`subagent_type: general-purpose`,
   `model: opus`, medium effort) to research it and return diff-concrete specs: title,
   files, spec, verification, risk, size (S/M, one agent ≤90 min). Don't read across the
   repo yourself.
2. **Split.** Cut the task into disjoint slices — no two slices in one batch may share a
   hot file (battle.gd, shared test helpers, CLAUDE.md). A small task is one slice. Write
   each slice's spec to a scratchpad file the brief points at. Check `git worktree list`
   first; never scope into an area another session owns.
3. **Run.** Either
   - `Workflow({ name: 'improve', args: { tasks: [{slug, task, reviewNote}...],
     trailers: <this session's commit trailers>, footer: <this session's PR footer> } })`
     — each slice becomes one PR by an `implementer` agent, adversarially reviewed in the
     same worktree by a `reviewer` agent (both `.claude/agents/`, Opus, medium), or
   - for a single slice, `Agent({ subagent_type: 'implementer', ... })` then
     `Agent({ subagent_type: 'reviewer', ... })` with the worktree, branch and PR URL.
   Non-code deliverables (a report, a measurement, a doc) go to a general-purpose Opus
   agent at medium effort with the same spec shape and a structured return.
4. **Merge.** Read verdicts. **Merge only if the user has authorized merging**; otherwise
   leave PRs open and report them. Merge sequentially: `gh pr merge N --squash`; on a
   stale-branch error `gh pr update-branch N`, wait ~25s, retry. After each merged branch:
   `git -C <main checkout> worktree remove .claude/worktrees/improve-<slug> --force` and
   delete the local branch.
5. **QA.** After UI-touching work, spawn a visual QA agent: `make smoke`, then read the
   frames as images — the sweep's byte floor passes blank frames.
6. **Wrap.** Summarize what shipped, what is open, and what the agents found wrong with
   the ask; record durable findings in memory.

## Hard rules

- Nothing merges without both: implementer's `make verify` green AND reviewer approve.
- Reviewers verify claims independently and may push small fixes; fundamental problems
  are rejected, never rewritten in review.
- An honest "this task is wrong / already done" report from an agent is relayed to the
  user, not overridden.
- Balance numbers move only with measurement.
- If you catch yourself opening source files to implement or review, stop and delegate.
