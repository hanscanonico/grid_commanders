class_name ProseMetrics
extends RefCounted
## Nine per-line readings of how machine-written a line of dialogue *looks*,
## each pure arithmetic over the words and each 0.0–1.0.
##
## The slop this measures is **structural, not lexical**. A word blacklist finds
## almost nothing in this corpus — one line in a thousand — while the shape is
## everywhere: 68% of the spoken lines are exactly two sentences, per-speaker
## mean sentence length spans 6.3 to 10.2 words across twenty-two generals, and
## 43 lines run "long observation. Short aphorism." So the readings are about
## sentence counts, sentence lengths, negation shape and cadence spread, and only
## one of the nine (`stock`) looks at particular words at all.
##
## Every reading is a *signal*, not a verdict. Vale's formality, Rhea's Latinate
## register and a deliberate triad each score high and each are correct writing;
## `docs/prose_slop.md` is the list of known false positives, and the score is a
## reading order for a human, never a gate. Nothing here refuses anything.
##
## Node-free and RNG-free, so `tests/unit/test_prose_metrics.gd` checks each
## reading against a crafted line and an honest one without loading content.

## The nine readings, in the order the report prints them. `measure` returns a
## key per entry and `score` weights exactly these, so a reading added here and
## nowhere else is a missing weight rather than a silent zero.
const HEURISTICS: Array[String] = [
	"lockstep",
	"aphorism",
	"negation",
	"em_dash",
	"cadence",
	"triad",
	"stock",
	"vocative",
	"register",
]

## What each reading is worth in the composite. The aphoristic closer is the
## heaviest because it is the one shape that is almost never an accident: it is
## the two-sentence lockstep *and* a manufactured last beat in the same line.
## The lockstep and the triad are near-nothing per line — the lockstep's real
## evidence is the corpus-wide rate `ProseReport` computes, and a triad is
## often deliberate.
const WEIGHTS: Dictionary = {
	"aphorism": 0.28,
	"stock": 0.16,
	"negation": 0.14,
	"cadence": 0.12,
	"em_dash": 0.10,
	"vocative": 0.08,
	"register": 0.06,
	"lockstep": 0.04,
	"triad": 0.02,
}

## Written-out negations, the tell that survives every other edit: dialogue
## contracts, briefings do not, and a whole campaign that never says "don't"
## reads as dictation.
const NEGATIONS := (
	"\\b(do not|does not|did not|is not|are not|was not|were not"
	+ "|will not|cannot|can not|would not|should not|could not|have not|has not)\\b"
)

## The one lexical reading, as patterns rather than words because three of the
## eight are shapes: "not X, but Y", "isn't X. It's Y" and the "That is the
## <noun>." closer are constructions no single word gives away. Add here and the
## weight follows automatically.
##
## The five phrase entries carry `(?i)` because a phrase that opens a sentence is
## capitalised and is the same phrase; the two that read a sentence boundary do
## not, because their capital is what tells them from the middle of a clause.
const STOCK_CONSTRUCTIONS: Array[String] = [
	"(?i)\\bnot\\s+[^,.]{1,40},\\s*but\\b",
	"\\b\\w+n['’]t\\b[^.]{0,60}\\.\\s*(It|That|This)['’]s\\b",
	"(?i)\\bthe very\\b",
	"(?i)\\ba testament to\\b",
	"(?i)\\bdelve\\b",
	"(?i)\\bin the end\\b",
	"(?i)\\bmake no mistake\\b",
	"(?:^|[.!?]\\s)(?:That|This) is the \\w+\\.\\s*$",
]

## A sentence: a run of anything that is not terminal punctuation, plus whatever
## terminal punctuation closes it. Matching the run rather than splitting on the
## gap is what keeps the last fragment of a line that ends without a full stop —
## authored dialogue does that often, and dropping it would shorten a third of
## the corpus by one sentence.
const SENTENCE := "[^.!?…]+[.!?…]*"

const VOCATIVES := ",\\s*(Commander|Warden)\\b"
const CONTRACTION := "\\w['’](s|t|re|ll|ve|d|m)\\b"
const LATINATE := "\\b\\w{4,}(tion|sion|ment|ance|ence|ity|ism|ude|ency|ancy)s?\\b"

## How far a line's mean sentence length has to sit from the corpus mean before
## its cadence stops looking machined, in words. Four is roughly the per-speaker
## spread an author gets by writing normally; inside it, every voice is one voice.
const CADENCE_SPREAD := 4.0

## A line with fewer words than this is a shout or a name, and its "cadence" and
## "register" are noise — a two-word line has no rhythm to be uniform.
const SHORT_LINE_WORDS := 6

static var _patterns: Dictionary = {}


## The sentences of a line, split on terminal punctuation. Trailing fragments
## with no terminator count — an authored line often ends without a full stop.
static func sentences(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for match: RegExMatch in _regex(SENTENCE).search_all(text):
		var trimmed := match.get_string().strip_edges()
		if trimmed != "":
			found.append(trimmed)
	return found


## Words in a fragment: whitespace-separated runs that carry a letter or digit,
## so an em-dash standing alone is punctuation rather than a word.
static func word_count(fragment: String) -> int:
	var count := 0
	for token in fragment.split(" ", false):
		if _regex("[A-Za-z0-9]").search(token) != null:
			count += 1
	return count


## The mean sentence length of a line, in words. 0.0 for a line with nothing in
## it, which is what keeps an empty corpus from dividing by zero.
static func mean_sentence_words(text: String) -> float:
	var parts := sentences(text)
	if parts.is_empty():
		return 0.0
	var total := 0
	for part in parts:
		total += word_count(part)
	return float(total) / float(parts.size())


## Exactly two sentences — the corpus's default shape, and the one that makes
## every general sound like the same drafting machine.
static func lockstep(text: String) -> float:
	return 1.0 if sentences(text).size() == 2 else 0.0


## Long observation, then a short closing pronouncement ending in a period. The
## heaviest reading: it is the shape of a line written to sound wise rather than
## to say something, and the corpus has dozens of them.
static func aphorism(text: String) -> float:
	var parts := sentences(text)
	if parts.size() != 2 or not parts[1].ends_with("."):
		return 0.0
	var opener := word_count(parts[0])
	var closer := word_count(parts[1])
	if opener >= 12 and closer <= 7:
		return 1.0
	return 0.5 if opener >= 10 and closer <= 9 else 0.0


## Written-out negations. One is a choice; two in one line is a register nobody
## speaks in.
static func negation(text: String) -> float:
	return minf(1.0, 0.6 * float(_count(NEGATIONS, text)))


## Em-dashes, read against how long the line is: a dash inside a two-sentence
## line is the machine's favourite joint, while the same dash in a five-sentence
## speech is punctuation.
static func em_dash(text: String) -> float:
	var dashes := text.count("—")
	if dashes == 0:
		return 0.0
	var load := 0.6 if dashes == 1 else 1.0
	return load if sentences(text).size() <= 2 else load * 0.5


## How close this line's rhythm sits to the speaker's own mean and to the
## corpus's. Scoring *closeness* is the point: uniformity is the defect, so the
## line that sounds exactly like everything around it is the one to look at.
static func cadence(text: String, speaker_mean: float, corpus_mean: float) -> float:
	var line_mean := mean_sentence_words(text)
	if line_mean == 0.0 or word_count(text) < SHORT_LINE_WORDS:
		return 0.0
	var to_speaker := 1.0 - minf(1.0, absf(line_mean - speaker_mean) / CADENCE_SPREAD)
	var to_corpus := 1.0 - minf(1.0, absf(line_mean - corpus_mean) / CADENCE_SPREAD)
	return (to_speaker + to_corpus) * 0.5


## Three comma-separated clauses of matched length in one sentence. Weighted at
## almost nothing because a triad is a real rhetorical figure a general may
## honestly reach for; it earns its place only in the aggregate.
static func triad(text: String) -> float:
	var best := 0.0
	for part in sentences(text):
		var clauses := part.split(",", false)
		if clauses.size() != 3:
			continue
		var lengths: Array[int] = []
		for clause in clauses:
			lengths.append(word_count(clause))
		if lengths.min() < 2:
			continue
		best = maxf(best, 1.0 if lengths.max() - lengths.min() <= 2 else 0.4)
	return best


## Any of `STOCK_CONSTRUCTIONS`. A single flat reading rather than a count: one
## stock construction is already the whole finding.
static func stock(text: String) -> float:
	for pattern in STOCK_CONSTRUCTIONS:
		if _regex(pattern).search(text) != null:
			return 1.0
	return 0.0


## ", Commander" and its siblings — filler that costs a beat and says nothing.
## One per line is the finding; the rate per mission is `ProseReport`'s.
static func vocative(text: String) -> float:
	return 1.0 if _count(VOCATIVES, text) > 0 else 0.0


## Register: a line of any length that never contracts, and how thick its
## abstract Latinate nouns lie. Both are characterisation when a writer chose
## them and drift when nobody did, so this is the lightest of the real readings.
static func register(text: String) -> float:
	var words := word_count(text)
	if words < SHORT_LINE_WORDS:
		return 0.0
	var uncontracted := 0.0 if _count(CONTRACTION, text) > 0 else 1.0
	var density := float(_count(LATINATE, text)) / float(words)
	return 0.5 * uncontracted + 0.5 * minf(1.0, density / 0.12)


## Every reading of one line, keyed by `HEURISTICS`.
static func measure(text: String, speaker_mean: float, corpus_mean: float) -> Dictionary:
	return {
		"lockstep": lockstep(text),
		"aphorism": aphorism(text),
		"negation": negation(text),
		"em_dash": em_dash(text),
		"cadence": cadence(text, speaker_mean, corpus_mean),
		"triad": triad(text),
		"stock": stock(text),
		"vocative": vocative(text),
		"register": register(text),
	}


## The weighted composite, 0.0–1.0. Normalised by the weights actually present,
## so a caller measuring a subset still gets a comparable number.
static func score(measures: Dictionary) -> float:
	var total := 0.0
	var weight := 0.0
	for key in HEURISTICS:
		if not measures.has(key):
			continue
		total += WEIGHTS[key] * float(measures[key])
		weight += WEIGHTS[key]
	return 0.0 if weight == 0.0 else total / weight


## Which readings fired hard enough to name in a report row, strongest first.
static func fired(measures: Dictionary, floor_value: float = 0.5) -> Array[String]:
	var names: Array[String] = []
	for key in HEURISTICS:
		if float(measures.get(key, 0.0)) >= floor_value:
			names.append(key)
	names.sort_custom(
		func(a: String, b: String) -> bool:
			return WEIGHTS[a] * float(measures[a]) > WEIGHTS[b] * float(measures[b])
	)
	return names


static func _count(pattern: String, text: String) -> int:
	return _regex(pattern).search_all(text).size()


## Compiled once per pattern for the whole run. Scoring a thousand lines against
## a dozen patterns is a five-figure compile otherwise, and the patterns are
## consts — there is nothing to invalidate.
static func _regex(pattern: String) -> RegEx:
	if not _patterns.has(pattern):
		var regex := RegEx.new()
		var error := regex.compile(pattern)
		assert(error == OK, "prose: pattern does not compile: %s" % pattern)
		_patterns[pattern] = regex
	return _patterns[pattern]
