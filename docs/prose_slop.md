# Prose slop — how the campaign dialogue is measured

`make prose` scores every spoken line of the six authored wars for **structural AI-slop**: the
shapes that give away writing produced in bulk rather than the words. It is a measurement, not a
gate — it exits 0 whatever it finds, stays out of `make verify` and `make test`, and edits no
content. This file is the committed record: what each reading means, which false positives are
known, the rewrite rules the numbers are meant to drive, and the **before** figures a pass is
measured against.

```
make prose                                        # everything
make prose PROSE="--campaign=the_quiet_war"       # one war
make prose PROSE="--speaker=konrad_vale --worst=50"
make prose PROSE="--reference"                    # the commanders' quotes instead, as a control
```

The full per-line table lands in `reports/prose/slop.csv` (gitignored). The corpus is
`tools/prose/prose_corpus.gd`, the readings `tools/prose/prose_metrics.gd`, the corpus-wide tables
`tools/prose/prose_report.gd`, and the runner `tools/run_prose_check.gd`.

## Why structural and not a word list

The obvious instrument is a blacklist — "testament", "delve", "the very", "in the end". Run against
this corpus it finds **one line in 1067**. The corpus was not written with those words; it was
written with one rhythm. So eight of the nine readings are about shape, and the ninth (the
blacklist) is kept only so the day somebody does paste one in, it is caught.

## What is scored

Every `MissionLine` the game speaks: each mission's `briefing`, `victory` and `defeat` dialogue,
every scripted event's lines, and every `CampaignInterlude` page. The `defeat` slot is now lines
with speakers like its siblings; its 108 lines are still the migrated narrator sentences, so the
numbers below stand until the per-war content passes give them voices.
**Every authored variant**, not one route's — a line gated behind a ledger condition is writing
too. Narration ("" speaker) is scored as a voice of its own rather than skipped: it is 12% of
the corpus and the one nobody thinks to characterise.

`MissionObjective.text` is **excluded on purpose**. Objective wording is an imperative fragment by
convention, and `docs/campaign_authoring.md` owns that convention; scoring it would report the
convention as a defect.

## The nine readings

Each returns 0.0–1.0 for one line. The composite is their weighted mean; the weights sum to 1.

| reading | weight | fires on |
|---|---|---|
| `aphorism` | 0.28 | exactly two sentences, opener ≥12 words, closer ≤7 and ending in a period (half credit at ≥10 / ≤9) |
| `stock` | 0.16 | any of `ProseMetrics.STOCK_CONSTRUCTIONS` — "not X, but Y", "isn't X. It's Y", "the very", "a testament to", "delve", "in the end", "make no mistake", a "That is the &lt;noun&gt;." closer |
| `negation` | 0.14 | written-out negations ("do not", "cannot", "will not", …); 0.6 for one, 1.0 for two |
| `cadence` | 0.12 | how *close* the line's mean sentence length sits to its speaker's mean and to the corpus mean — closeness is the defect |
| `em_dash` | 0.10 | em-dashes, weighted down in a line of three sentences or more |
| `vocative` | 0.08 | ", Commander" / ", Warden" |
| `register` | 0.06 | a line of ≥6 words that never contracts, plus abstract Latinate noun density (-tion, -ment, -ity, …) |
| `lockstep` | 0.04 | exactly two sentences |
| `triad` | 0.02 | one sentence built from three comma-separated clauses of matched length |

`lockstep` and `triad` are weighted at almost nothing per line on purpose. The lockstep's real
evidence is the corpus-wide rate and the sentence-count entropy, not any one line; a triad is a
real rhetorical figure a general may honestly reach for.

Corpus-wide, `ProseReport` adds what no single line shows: per-speaker sentence-length σ, the
sentence-count entropy, opening word-pairs shared across voices, cross-speaker trigram Jaccard
overlap ("interchangeable voices"), and the missions whose dialogue leans on ", Commander".

## Known false positives — read before rewriting

- **Konrad Vale's formality.** Vale is written as a man who does not contract and does not
  abbreviate, and it shows in the numbers: mean `register` 0.46 and mean `negation` 0.25 against a
  corpus that mostly reads 0, which puts him third-highest overall (0.208 over 36 lines). That is
  characterisation, and flattening it would cost the roster a voice — read his rows and skip them.
- **Latinate registers generally.** The `register` reading cannot tell doctrine-speak somebody
  chose from doctrine-speak nobody noticed writing. Weighted at 0.06 for that reason; never act on
  it alone.
- **Deliberate triads.** A general listing three things is a figure, not a tic. `triad` is weighted
  at 0.02 because of exactly this.
- **`cadence` rewards being average.** A line that scores 1.0 there is a line the length of every
  other line — which is the finding, but it is not a defect *in that line*. Read it as "this line
  disappears", never as "this line is bad".
- **Narration is long by design.** The narrator's mean sentence is 14.7 words against the corpus's
  9.7, so `cadence` scores narration low and `register` scores it high. Neither says much.
- **Short lines are excluded, not scored well.** Under six words, `cadence` and `register` return
  0.0 rather than a reading. A shout is not a rhythm.

## Rewrite rules — what a dialogue pass is for

1. **Break the lockstep.** Beats of 1, 2 and 3 sentences, mixed. The target is sentence-count
   entropy well above the corpus's current 1.24 bits, not a lower two-sentence share on its own.
2. **Kill the aphoristic closer.** A long observation closed by a short pronouncement is the single
   loudest tell. Cut the closer, or let the observation end the line.
3. **Contract, except where a character is written not to.** Vale and Rhea keep their register;
   everybody else says "don't", "we're", "it's".
4. **Widen the per-speaker cadence spread.** A voice with σ under 2 words says everything at one
   length. Dane Ferrow (σ 1.89 over 62 lines) is the narrowest and the first to work on.
5. **", Commander" under 5% of a mission's lines.** It is currently 11% across the corpus and over
   38% in eight missions.
6. **At most one em-dash per mission's dialogue.** 104 lines carry one today.
7. **Keep every fact a briefing promises to an event.** A rewrite that drops a named place, unit or
   deadline breaks `make campaigns` at best and the mission's sense at worst. Re-run
   `make campaigns` after any pass.

## Before — measured 2026-08-31

`make prose` over all six campaigns at commit `7629f3ca`, with no dialogue edited.

```
prose: 1067 lines, 23 voices
prose: mean score 0.150 | mean sentence 9.7 words | sentence-count entropy 1.24 bits
prose: fired on — lockstep 68%, aphorism 13%, negation 11%, em_dash 10%,
                  cadence 86%, triad 5%, stock 0%, vocative 11%, register 68%
prose: speaker sentence-length σ spans 1.89 to 4.24 words
```

Behind those rates:

- **729 of 1067 lines (68%) are exactly two sentences.** 201 are one, 132 are three, 5 are four.
- **43 lines are strict aphoristic closers** (opener ≥12, closer ≤7, ending in a period); another
  94 are near misses at half credit.
- **117 lines carry a written-out negation**, **104 an em-dash**, **122 a ", Commander"**.
- **The blacklist fires once**, in `the_furnace_winter/interlude@1`.
- **Per-speaker mean sentence length spans 6.3 to 10.2 words** across the twenty-two named
  generals — narrower than the spread inside most single characters' dialogue elsewhere.

Worst missions by mean score:

| mission | lines | mean |
|---|---|---|
| `the_collection/interlude@1` | 7 | 0.238 |
| `the_hollow_crown/hc10_broken_column` | 9 | 0.230 |
| `the_furnace_winter/fw15_smelter_yard` | 11 | 0.224 |
| `six_marshals/interlude@2` | 4 | 0.220 |
| `the_collection/tc18_closing_the_ledger` | 10 | 0.213 |

Openings shared across voices: "then we" (23 uses, 11 voices), "the column" (12 / 7), "then i"
(10 / 7), "take the" (9 / 8). Narrowest cadence: `dane_ferrow` σ 1.89 over 62 lines, `tomas_reed`
σ 2.09, `ivar_thorne` σ 2.26.

## After the first rewrite pass — measured 2026-08-31

One PR per campaign (#594–#599) rewrote 470-odd spoken lines against the numbers above,
holding to the rewrite rules; `make prose` over merged main afterwards:

```
prose: 1067 lines, 23 voices
prose: mean score 0.091 | mean sentence 9.7 words | sentence-count entropy 1.48 bits
prose: fired on — lockstep 57%, aphorism 2%, negation 3%, em_dash 3%,
                  cadence 79%, triad 6%, stock 0%, vocative 1%, register 54%
prose: speaker sentence-length σ spans 2.42 to 5.31 words
```

Every campaign's mean fell (0.145–0.165 down to 0.079–0.092) while the per-speaker cadence
spread widened at both ends. Konrad Vale and Lyra Quill still do not contract on purpose;
a handful of ", Commander" vocatives survive as one signature moment per Iron marshal.
The worst remaining text was the interludes, and the pass below is what became of them.

## After the interlude pass — measured 2026-08-31

#605 rewrote the eight worst interlude pages — The Collection's three, `fw@1`, `hc@0`, `sm@3`,
`lf@0`, `lf@1` — plus one flagged line on `lf@2`. 49 lines, text only:

```
prose: 1067 lines, 23 voices
prose: mean score 0.086 | mean sentence 10.0 words | sentence-count entropy 1.53 bits
prose: fired on — lockstep 54%, aphorism 1%, negation 2%, em_dash 3%,
                  cadence 77%, triad 6%, stock 0%, vocative 1%, register 52%
prose: speaker sentence-length σ spans 2.68 to 5.95 words
```

The interlude slice is what moved: mean 0.105 → 0.072, two-sentence share 63% → 34%, entropy
1.38 → 1.70 bits, and its sentence counts spread from 12/78/31 one-, two- and three-sentence
lines to 34/42/45 at the same words per line. The Collection's three pages went 0.167 → 0.041
with no two-sentence line left. What tops the slice now is Konrad Vale's `negation` and
`register`, which is the first false positive on the list above.

## The control corpus

`make prose PROSE="--reference"` scores the commanders' `power_quotes` and `doctrine_text` — filed
under the pseudo-campaign `(commanders)` — *instead of* the campaigns. They are written to a
different brief, a power quote being *meant* to be one aphorism, so they are the control run rather
than rows in the same table:

```
prose: 88 lines, 22 voices
prose: mean score 0.094 | mean sentence 6.2 words | sentence-count entropy 1.16 bits
prose: fired on — lockstep 41%, aphorism 0%, ... cadence 73%, register 70%
```

Mean 0.094 against the campaigns' 0.150, and **zero** aphoristic closers against 13%: the reading
separates writing done one line at a time from writing done a mission at a time, which is the whole
claim the instrument makes.
