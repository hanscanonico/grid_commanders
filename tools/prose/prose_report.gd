class_name ProseReport
extends RefCounted
## The corpus-wide half of the reading: what the whole body of dialogue looks
## like, rather than what one line does.
##
## `ProseMetrics` can only ever say "this line is shaped like that". The findings
## that matter to a rewrite are comparative — every general opens the same way,
## two speakers share most of their phrasing, nobody's sentence length varies —
## and none of them is visible one line at a time. So this owns the means the
## per-line cadence reading needs, the spread and overlap tables, and the
## ordering of the worst-N list the tool prints.
##
## Node-free and RNG-free; ties are broken by provenance so two runs over one
## corpus print the same table in the same order.

## Word trigrams below this count from a speaker are not a voice, they are a
## sample, and their Jaccard against anybody is noise.
const MIN_TRIGRAMS := 12
## A ", Commander" rate above this in one mission's dialogue is the finding.
const VOCATIVE_RATE := 0.25
## What survives tokenisation, lower-cased. The apostrophe stays because
## "don't" and "dont" are not the same word to a voice-overlap reading.
const WORD_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789'"


## The corpus's mean sentence length in words — the number every line's cadence
## reading is measured against.
static func corpus_mean(lines: Array[ProseLine]) -> float:
	var total := 0.0
	var counted := 0
	for line: ProseLine in lines:
		var mean := ProseMetrics.mean_sentence_words(line.text)
		if mean > 0.0:
			total += mean
			counted += 1
	return 0.0 if counted == 0 else total / float(counted)


## Each voice's own mean sentence length, keyed by `ProseLine.voice()`.
static func speaker_means(lines: Array[ProseLine]) -> Dictionary:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for line: ProseLine in lines:
		var mean := ProseMetrics.mean_sentence_words(line.text)
		if mean <= 0.0:
			continue
		var voice := line.voice()
		sums[voice] = float(sums.get(voice, 0.0)) + mean
		counts[voice] = int(counts.get(voice, 0)) + 1
	var means: Dictionary = {}
	for voice: StringName in sums:
		means[voice] = float(sums[voice]) / float(counts[voice])
	return means


## Every line scored, in corpus order: the row the CSV, the worst-N list and
## every aggregate below are all built from.
static func rows(lines: Array[ProseLine]) -> Array[Dictionary]:
	var mean := corpus_mean(lines)
	var means := speaker_means(lines)
	var scored: Array[Dictionary] = []
	for line: ProseLine in lines:
		var voice_mean := float(means.get(line.voice(), mean))
		var measures := ProseMetrics.measure(line.text, voice_mean, mean)
		var row := {"line": line, "measures": measures, "score": ProseMetrics.score(measures)}
		scored.append(row)
	return scored


## The N worst-scoring lines, highest first. Ties fall back to provenance so the
## table is the same on every run over the same corpus.
static func worst(scored: Array[Dictionary], count: int) -> Array[Dictionary]:
	var ordered := scored.duplicate()
	ordered.sort_custom(_by_score_then_place)
	return ordered.slice(0, maxi(0, count))


## The missions (and interlude pages) whose dialogue scores worst on average,
## with at least `floor_lines` lines so a one-line page cannot top the table.
static func worst_sources(
	scored: Array[Dictionary], count: int, floor_lines: int = 4
) -> Array[Dictionary]:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for row: Dictionary in scored:
		var source: String = row["line"].source()
		sums[source] = float(sums.get(source, 0.0)) + float(row["score"])
		counts[source] = int(counts.get(source, 0)) + 1
	var table: Array[Dictionary] = []
	for source: String in sums:
		if int(counts[source]) < floor_lines:
			continue
		var count_here := int(counts[source])
		var mean_score := float(sums[source]) / float(count_here)
		table.append({"source": source, "lines": count_here, "mean_score": mean_score})
	table.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["mean_score"] > b["mean_score"]
				if a["mean_score"] != b["mean_score"]
				else a["source"] < b["source"]
			)
	)
	return table.slice(0, maxi(0, count))


## Per-speaker sentence-length spread: the mean, the standard deviation and the
## line count. **The σ column is the headline of the whole instrument** — a
## roster of generals whose spreads all sit near each other is a roster with one
## voice, and no per-line reading can see it.
static func speaker_spread(lines: Array[ProseLine]) -> Array[Dictionary]:
	var samples: Dictionary = {}
	for line: ProseLine in lines:
		var mean := ProseMetrics.mean_sentence_words(line.text)
		if mean <= 0.0:
			continue
		var voice := line.voice()
		if not samples.has(voice):
			samples[voice] = PackedFloat32Array()
		samples[voice].append(mean)
	var table: Array[Dictionary] = []
	for voice: StringName in samples:
		var values: PackedFloat32Array = samples[voice]
		var row := {"speaker": String(voice), "lines": values.size()}
		row["mean"] = _mean(values)
		row["sigma"] = _sigma(values)
		table.append(row)
	table.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["sigma"] < b["sigma"] if a["sigma"] != b["sigma"] else a["speaker"] < b["speaker"]
			)
	)
	return table


## Shannon entropy, in bits, of how many sentences a line has. A corpus where
## three quarters of the lines are two sentences lands near 1 bit; four evenly
## used lengths would be 2. The one number that says "the shape is the problem".
static func sentence_count_entropy(lines: Array[ProseLine]) -> float:
	var histogram: Dictionary = {}
	var total := 0
	for line: ProseLine in lines:
		var count := ProseMetrics.sentences(line.text).size()
		if count == 0:
			continue
		histogram[count] = int(histogram.get(count, 0)) + 1
		total += 1
	if total == 0:
		return 0.0
	var entropy := 0.0
	for count: int in histogram:
		var p := float(histogram[count]) / float(total)
		entropy -= p * (log(p) / log(2.0))
	return entropy


## Opening word-pairs used by more than one speaker, commonest first. Two
## generals who both start lines "We have" are two generals with one drafter.
static func shared_openings(lines: Array[ProseLine], count: int = 10) -> Array[Dictionary]:
	var voices: Dictionary = {}
	var uses: Dictionary = {}
	for line: ProseLine in lines:
		var words := _words(line.text)
		if words.size() < 2:
			continue
		var opening := "%s %s" % [words[0], words[1]]
		if not voices.has(opening):
			voices[opening] = {}
		voices[opening][line.voice()] = true
		uses[opening] = int(uses.get(opening, 0)) + 1
	var table: Array[Dictionary] = []
	for opening: String in voices:
		var speakers: int = voices[opening].size()
		if speakers < 2:
			continue
		table.append({"opening": opening, "speakers": speakers, "uses": int(uses[opening])})
	table.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a["uses"] > b["uses"] if a["uses"] != b["uses"] else a["opening"] < b["opening"]
	)
	return table.slice(0, maxi(0, count))


## The interchangeable-voices table: for every pair of speakers with enough
## words to judge, the Jaccard overlap of their word trigrams. Two characters
## sharing a tenth of their phrasing are two characters an ear cannot tell apart.
static func voice_overlap(lines: Array[ProseLine], count: int = 10) -> Array[Dictionary]:
	var grams: Dictionary = {}
	for line: ProseLine in lines:
		# Keyed by String rather than StringName: a StringName sorts by its
		# internal pointer, so the pair order would be whatever the run happened
		# to intern first.
		var voice := String(line.voice())
		if not grams.has(voice):
			grams[voice] = {}
		for gram in _trigrams(line.text):
			grams[voice][gram] = true
	var voices: Array[String] = []
	for voice: String in grams:
		if grams[voice].size() >= MIN_TRIGRAMS:
			voices.append(voice)
	voices.sort()
	var table: Array[Dictionary] = []
	for i in voices.size():
		for j in range(i + 1, voices.size()):
			var overlap := _jaccard(grams[voices[i]], grams[voices[j]])
			if overlap > 0.0:
				table.append({"a": voices[i], "b": voices[j], "jaccard": overlap})
	table.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["jaccard"] > b["jaccard"]
				if a["jaccard"] != b["jaccard"]
				else "%s%s" % [a["a"], a["b"]] < "%s%s" % [b["a"], b["b"]]
			)
	)
	return table.slice(0, maxi(0, count))


## Missions whose dialogue leans on ", Commander" past `VOCATIVE_RATE`.
static func vocative_sources(scored: Array[Dictionary]) -> Array[Dictionary]:
	var hits: Dictionary = {}
	var counts: Dictionary = {}
	for row: Dictionary in scored:
		var source: String = row["line"].source()
		counts[source] = int(counts.get(source, 0)) + 1
		if float(row["measures"]["vocative"]) > 0.0:
			hits[source] = int(hits.get(source, 0)) + 1
	var table: Array[Dictionary] = []
	for source: String in hits:
		var rate := float(hits[source]) / float(counts[source])
		if rate > VOCATIVE_RATE:
			table.append({"source": source, "rate": rate, "lines": int(counts[source])})
	table.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a["rate"] > b["rate"] if a["rate"] != b["rate"] else a["source"] < b["source"]
	)
	return table


## The headline numbers, in one dictionary: what the tool prints first and what
## `docs/prose_slop.md` records as the before-reading of a rewrite pass.
static func aggregate(lines: Array[ProseLine], scored: Array[Dictionary]) -> Dictionary:
	var rates: Dictionary = {}
	for key: String in ProseMetrics.HEURISTICS:
		rates[key] = _rate(scored, key)
	var spread := speaker_spread(lines)
	return {
		"lines": lines.size(),
		"speakers": spread.size(),
		"corpus_mean_sentence_words": corpus_mean(lines),
		"sentence_count_entropy": sentence_count_entropy(lines),
		"mean_score": _mean_score(scored),
		"rates": rates,
		"narrowest_speaker_sigma": 0.0 if spread.is_empty() else float(spread[0]["sigma"]),
		"widest_speaker_sigma": 0.0 if spread.is_empty() else float(spread[-1]["sigma"]),
	}


static func _by_score_then_place(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	return a["line"].where() < b["line"].where()


## The share of lines a reading fired on at all. Read alongside the mean score:
## a reading that never fires is measuring nothing here.
static func _rate(scored: Array[Dictionary], key: String) -> float:
	if scored.is_empty():
		return 0.0
	var fired := 0
	for row: Dictionary in scored:
		if float(row["measures"][key]) > 0.0:
			fired += 1
	return float(fired) / float(scored.size())


static func _mean_score(scored: Array[Dictionary]) -> float:
	if scored.is_empty():
		return 0.0
	var total := 0.0
	for row: Dictionary in scored:
		total += float(row["score"])
	return total / float(scored.size())


## Lower-cased word tokens, punctuation stripped — the unit both the opening
## pairs and the trigrams are built from, so the two tables agree on what a word
## is.
static func _words(text: String) -> PackedStringArray:
	var words := PackedStringArray()
	for token in text.to_lower().replace("\n", " ").split(" ", false):
		var clean := ""
		for i in token.length():
			if token[i] in WORD_CHARS:
				clean += token[i]
		if clean != "":
			words.append(clean)
	return words


static func _trigrams(text: String) -> PackedStringArray:
	var words := _words(text)
	var grams := PackedStringArray()
	for i in range(0, maxi(0, words.size() - 2)):
		grams.append("%s %s %s" % [words[i], words[i + 1], words[i + 2]])
	return grams


static func _jaccard(a: Dictionary, b: Dictionary) -> float:
	var shared := 0
	for gram: String in a:
		if b.has(gram):
			shared += 1
	var union := a.size() + b.size() - shared
	return 0.0 if union == 0 else float(shared) / float(union)


static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


static func _sigma(values: PackedFloat32Array) -> float:
	if values.size() < 2:
		return 0.0
	var mean := _mean(values)
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	return sqrt(variance / float(values.size()))
