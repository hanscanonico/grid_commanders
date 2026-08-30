export const meta = {
	name: 'improve',
	description: 'Implement→adversarial-review pipeline: one PR per task via Opus subagents',
	whenToUse:
		'Delegated implementation of scouted, disjoint task specs; used by the /improve skill',
	phases: [
		{ title: 'Implement', detail: 'one implementer per task in its own worktree' },
		{ title: 'Review', detail: 'adversarial review + small fixes in the same worktree' },
	],
}

// args: { tasks: [{ slug, task, reviewNote? }, ...], trailers?: string, footer?: string }
//   slug       names the worktree (improve-<slug>) and branch (improve/<slug>)
//   task       the full task brief (may point at a spec file the orchestrator wrote)
//   reviewNote extra context for the reviewer (what to independently verify)
//   trailers   optional commit-trailer block; empty means no trailer at all
//   footer     PR-body footer for this session (generated-with + session link)
// Some harness routes deliver args as a JSON string rather than a parsed value.
const raw = typeof args === 'string' ? JSON.parse(args) : args
const input = raw && raw.tasks ? raw : { tasks: raw }
if (!Array.isArray(input.tasks) || input.tasks.length === 0) {
	throw new Error('improve: pass args = { tasks: [{ slug, task }, ...] }')
}

const IMPL = {
	type: 'object',
	required: ['pr_url', 'branch', 'worktree', 'verify_pass', 'summary'],
	properties: {
		pr_url: { type: 'string' },
		branch: { type: 'string' },
		worktree: { type: 'string' },
		verify_pass: { type: 'boolean' },
		summary: { type: 'string' },
		notes: { type: 'string' },
	},
}
const REVIEW = {
	type: 'object',
	required: ['verdict', 'reasons'],
	properties: {
		verdict: { type: 'string', enum: ['approve', 'reject'] },
		reasons: { type: 'string' },
		fixed: { type: 'string' },
	},
}

const trailers = input.trailers || ''
const footer = input.footer || ''

phase('Implement')
const results = await pipeline(
	input.tasks,
	(t) =>
		agent(
			`Task slug: ${t.slug}\n\n${t.task}\n\n${trailers ? 'Commit trailers to use (end the commit message with these lines):\n\n' + trailers : 'Do not add any Co-Authored-By, Generated-with or session trailer to commits or PR bodies — the user is the sole author.'}${footer ? '\n\nPR body footer (end the PR body with these lines):\n\n' + footer : ''}`,
			{ label: `impl:${t.slug}`, phase: 'Implement', agentType: 'implementer', schema: IMPL }
		),
	(impl, t) => {
		if (!impl || !impl.verify_pass) return { impl, review: null }
		return agent(
			`Review the PR in worktree ${impl.worktree} (branch ${impl.branch}, PR ${impl.pr_url}).\n\nThe task it implements:\n${t.task}\n${t.reviewNote ? '\nWhat to verify independently: ' + t.reviewNote : ''}${trailers ? '\n\nIf you commit fixes, end the commit message with:\n\n' + trailers : '\n\nDo not add any Co-Authored-By or attribution trailer to commits.'}`,
			{ label: `review:${t.slug}`, phase: 'Review', agentType: 'reviewer', schema: REVIEW }
		).then((review) => ({ impl, review }))
	}
)

return results
