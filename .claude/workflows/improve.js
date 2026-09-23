export const meta = {
	name: 'improve',
	description:
		'Implement→adversarial-review pipeline: one PR per task via Opus subagents, one retry at high effort on a red gate or a reject',
	whenToUse:
		'Delegated implementation of scouted, disjoint task specs; used by the /improve and /orchestrate skills',
	phases: [
		{ title: 'Implement', detail: 'one implementer per task in its own worktree, medium effort' },
		{ title: 'Review', detail: 'adversarial review + small fixes in the same worktree, high effort' },
		{ title: 'Retry', detail: 'the one high-effort implementer retry, then a fresh review' },
	],
}

// args: { tasks: [{ slug, task, reviewNote? }, ...], trailers?: string, footer?: string }
//   slug       names the worktree (improve-<slug>) and branch (improve/<slug>)
//   task       the full task brief (may point at a spec file the orchestrator wrote)
//   reviewNote extra context for the reviewer (what to independently verify)
//   trailers   optional commit-trailer block; empty means no trailer at all
//   footer     PR-body footer for this session (generated-with + session link)
//
// Every agent runs on the latest Opus available: the `opus` alias, never Fable, never a
// dated Opus id. Effort lives on the agent definitions (implementer medium, reviewer
// high); the one per-call override here is the retry, which runs the implementer at high.
//
// Each result: { impl, review, retry, verdict } — retry is null or a second { impl, review };
// verdict reads the last attempt: approve | reject | verify_failed | abandoned | unreviewed | no_result.
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
		pr_url: { type: 'string', description: 'Empty when no PR was opened' },
		branch: { type: 'string' },
		worktree: { type: 'string' },
		verify_pass: { type: 'boolean', description: 'make verify plus any area gate green in the worktree' },
		summary: { type: 'string' },
		notes: { type: 'string' },
		abandoned: {
			type: 'boolean',
			description: 'True when the task was judged wrong or already done and no change was made',
		},
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
const REPO = '/Users/hanscanonico/Projets/grid_commanders'

const trailerNote = trailers
	? 'Commit trailers to use (end the commit message with these lines):\n\n' + trailers
	: 'Do not add any Co-Authored-By, Generated-with or session trailer to commits or PR bodies — the user is the sole author.'
const footerNote = footer ? '\n\nPR body footer (end the PR body with these lines):\n\n' + footer : ''
const reviewTrailerNote = trailers
	? '\n\nIf you commit fixes, end the commit message with:\n\n' + trailers
	: '\n\nDo not add any Co-Authored-By or attribution trailer to commits.'

const implBrief = (t) => `Task slug: ${t.slug}\n\n${t.task}\n\n${trailerNote}${footerNote}`

const retryBrief = (t, impl, review) => {
	const worktree = (impl && impl.worktree) || `${REPO}/.claude/worktrees/improve-${t.slug}`
	const branch = (impl && impl.branch) || `improve/${t.slug}`
	const pr = impl && impl.pr_url ? `PR ${impl.pr_url}` : 'no PR yet'
	const why = review
		? `The first attempt was REJECTED in review. Reasons:\n${review.reasons}` +
			(review.fixed ? `\n\nThe reviewer already fixed and pushed:\n${review.fixed}` : '')
		: 'The first attempt did not get its gate green.' +
			(impl && impl.summary ? `\nWhat it did:\n${impl.summary}` : '') +
			(impl && impl.notes ? `\nIts notes:\n${impl.notes}` : '')
	return (
		`Task slug: ${t.slug}\n\nSECOND ATTEMPT. A first attempt exists in worktree ${worktree} on branch ${branch} (${pr}) — work there, do not recreate the worktree.\n\n${why}\n\n` +
		`Address every reason above, get the gate green, commit and push to the same branch (open the PR only if none exists).\n\n${t.task}\n\n${trailerNote}${footerNote}`
	)
}

const reviewBrief = (t, impl, prior) =>
	`Review the PR in worktree ${impl.worktree} (branch ${impl.branch}, PR ${impl.pr_url}).\n\nThe task it implements:\n${t.task}\n` +
	(t.reviewNote ? '\nWhat to verify independently: ' + t.reviewNote : '') +
	(prior
		? `\n\nThis is a second attempt. The first was rejected for:\n${prior.reasons}\nCheck each of those was addressed, then review the whole diff as usual.`
		: '') +
	reviewTrailerNote

const MODEL = 'opus' // the alias tracks the newest Opus release

const reviewable = (impl) => Boolean(impl && impl.verify_pass && !impl.abandoned)

const review = (t, impl, prior, phaseName, label) =>
	agent(reviewBrief(t, impl, prior), { label, phase: phaseName, agentType: 'reviewer', model: MODEL, schema: REVIEW })

// One retry, never more. A null impl means the user skipped the agent or it died on a
// terminal API error — not something a second attempt should override.
const needsRetry = (impl, rev) => {
	if (!impl || impl.abandoned) return false
	if (!impl.verify_pass) return true
	return Boolean(rev && rev.verdict === 'reject')
}

const verdictOf = (r) => {
	const last = r.retry || r
	if (!last.impl) return 'no_result'
	if (last.impl.abandoned) return 'abandoned'
	if (!last.impl.verify_pass) return 'verify_failed'
	if (!last.review) return 'unreviewed'
	return last.review.verdict
}

phase('Implement')
const results = await pipeline(
	input.tasks,
	(t) =>
		agent(implBrief(t), { label: `impl:${t.slug}`, phase: 'Implement', agentType: 'implementer', model: MODEL, schema: IMPL }),
	(impl, t) => {
		if (!reviewable(impl)) return { impl, review: null }
		return review(t, impl, null, 'Review', `review:${t.slug}`).then((rev) => ({ impl, review: rev }))
	},
	async (first, t) => {
		if (!needsRetry(first.impl, first.review)) return { ...first, retry: null }
		log(`${t.slug}: ${first.review ? 'rejected' : 'gate red'} — retrying once at high effort`)
		const impl = await agent(retryBrief(t, first.impl, first.review), {
			label: `retry:${t.slug}`,
			phase: 'Retry',
			agentType: 'implementer',
			model: MODEL,
			effort: 'high',
			schema: IMPL,
		})
		const rev = reviewable(impl) ? await review(t, impl, first.review, 'Retry', `re-review:${t.slug}`) : null
		return { ...first, retry: { impl, review: rev } }
	},
	(r) => ({ ...r, verdict: verdictOf(r) })
)

return results
