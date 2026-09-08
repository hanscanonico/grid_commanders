# Issue tracker: Linear

Issues and specs for this repo live in Linear, team **Grid_Commanders** (identifiers `COM-<n>`).
Use the Linear MCP tools (`mcp__linear__*`), not the `gh` CLI, for every issue operation. GitHub
holds only the code and its pull requests.

## Conventions

- **Create an issue**: `save_issue` with `team: "Grid_Commanders"`, a title and a markdown
  description. Attach it to a project when the work belongs to a plan; a plan's milestones are
  labels (`MB1 · foundation`, `arena:search`, …), one per slice.
- **Read an issue**: `get_issue` by identifier, then `list_comments` — reproduction steps,
  corrections and the acceptance bar usually live in a comment, not the description. Run
  `extract_images` on any embedded screenshot.
- **List issues**: `list_issues` filtered by team, state, label or project.
- **Comment on an issue**: `save_comment` with the issue id. Quote the ticket's words rather than
  paraphrasing them.
- **Apply / remove labels**: `save_issue` with the full `labels` list. New labels go through
  `save_issue_label` on the team.
- **Close**: `save_issue` with `state: "Done"`, linking the PR (`links: [{url, title}]`), then a
  summary comment. Not a bug or already fixed: leave the state, comment the evidence.

## States

Linear statuses, in order: `Backlog` → `Todo` → `In Progress` → `In Review` → `Done`, plus
`Canceled` and `Duplicate`. A ticket moves to `In Progress` when work starts and to `Done` when
its PR is merged; `In Review` is for a PR the user must merge themselves.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature
requests; `/triage` reads this flag.)_ A bare `#42` in this repo is a GitHub PR number, never a
Linear issue.

## When a skill says "publish to the issue tracker"

Create a Linear issue on the Grid_Commanders team.

## When a skill says "fetch the relevant ticket"

`get_issue` on the identifier, then `list_comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a Linear project; its tickets are the project's issues.

- **Map**: a project created with `save_project`, its Notes / Decisions-so-far / Fog body kept
  as the project description (or a `save_document` inside it when it outgrows the description).
- **Child ticket**: an issue in that project, labelled `wayfinder:<type>`
  (`research`/`prototype`/`grilling`/`task`). Once claimed, assign it to the driving dev.
- **Blocking**: Linear's native `blockedBy` relations, set through `save_issue`. A ticket is
  unblocked when every blocker is `Done` or `Canceled`.
- **Frontier query**: `list_issues` on the project with open states, drop any with an open
  blocker or an assignee; first in project order wins.
- **Claim**: `save_issue` assigning the ticket to yourself and setting `In Progress`, the
  session's first write.
- **Resolve**: `save_comment` with the answer, `save_issue` to `Done`, then append a context
  pointer to the map's Decisions-so-far.
