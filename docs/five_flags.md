# Five Flags — the campaign of record

*Five Flags* is the game's campaign: one war in six acts, 39 authored missions of which a single
run plays 36. It replaced the six earlier wars (The Six Marshals, The Collection, The Furnace
Winter, The Hollow Crown, The Long Front, The Quiet War) on 2026-09-28 — six variations of one
premise, *Iron invades*, which is what the rewrite set out to fix. This file is the story's design
of record: the premise, the secret the war reveals, the cast and how each of them talks, the acts,
the facts the war carries between missions, and the threads every one of them closes. The missions
themselves live in `data/campaigns/five_flags/`; how a mission is authored is
`docs/campaign_authoring.md`'s; how hard each one is, `docs/campaign_difficulty.md`'s.

## The premise

Five powers share one continent — the **Meridian Coalition** (the old republic: coast, farmland,
the capital Aldmoor), the **Aurora Compact** (a highland trading federation, fast and neutral by
habit; Skyreach), the **Verdant League** (forest cantons under a council; Greenhollow), the **Iron
Dominion** (the Directorate's industrial state; Ostrava) and the **Gilded Concord** (the banking
cities of the southern islands, owed money by everyone; Aurum).

Twenty years ago the Ash War ended with the **Lantern Accord**, signed in the Lantern Hall at
Candlemere, in **the Seam** — the neutral strip where four borders meet. The Accord created **the
Ninth**, a brigade whose officers come from all five powers and which flies five flags on one pole.
The Accord runs for twenty years. The campaign opens the week it is to be renewed, when the Hall
burns.

## The secret

**Lyra Quill**, Chancellor of the Concord, has run the numbers: the mainland goes back to war within
nine years whatever anyone signs, and that war kills two million. So she holds the war *now*, small
and on her terms — burn the Hall, let Iron take the blame, lend to every side, and when the mainland
is spent, offer the Settlement: every war debt held by the Concord, every army capped by contract.
Her instruments are **Dane Ferrow**, Iron's licensed privateer, paid in new Concord gold; **Sable
Wren**, the Ninth's own intelligence officer; and the loans behind **Konrad Vale**'s foundries and,
through them, **Radek Morn**'s Hammerfall battery — the plan needed Iron to be frightening. Her one
error is that Morn cannot be priced. When the mainland turns south, he seizes the Directorate and
turns Hammerfall on Aurum, and the last act is every flag against him.

## The acts

| Act | Title | Missions | The act in one line |
|---|---|---|---|
| I | The Seam | ff01–ff06 | Ferrow's raids, the Hall burns, every power grabs Candlemere, the Ninth scatters and Alina Ward is taken |
| II | Home Fires | ff07–ff13 | Iron invades Meridian by sea, river, road and air; the capital holds; Hammerfall fires for the first time |
| III | The Ninth | ff14–ff20 | Iris Colt rebuilds the Ninth: the Verdant rising against Thorne, Nia's road, Aurora's war game, Draeg's column over Skyreach |
| IV | Into Iron | ff21–ff26 | The invasion of Iron: the pass, Ferrow bought or fought, Vale's foundries, Kharn prison, Draeg — and the truth |
| V | The Vault | ff27–ff32 | The Concord: Sable hunted, the counting houses, the Glass Shore, Rhea's line, Lyra's citadel struck by Hammerfall; the player commands Lyra at the causeway |
| VI | Five Flags | ff33–ff39 | Every flag against Morn, the Ninth's veteran column carried to Hammer Hill |

The player commands a different general most missions — the Ninth's roll call — and plays every
faction: Meridian throughout, Iron (Viktor Draeg, ff02), Verdant (Nia Rowan, Tomas Reed, Ines
Calder), Aurora (Sera Lark, Perrin Ash, Cassian Rook, Orin Flux) and the Concord (Sable Wren in the
optional ff10, Lyra Quill in ff32). Every one of the 22 commanders appears.

## The route

- **ff10, The Mint at Aurum Ford**, is optional: it opens only for a player who destroyed Ferrow's
  paymaster in ff02 (`ff_gold_found`). The player commands Sable Wren — the traitor — tracing the
  gold she is hiding, and nothing on the page says so.
- **ff15 / ff16** fork on `ff_nia_fought` (ff11): spare Nia's rangers at the shrine and she guides
  the column down the Thornwood (ff15); shoot one and she hunts it (ff16).
- **ff37 / ff38** fork on `ff_rhea_turned` (ff30): reach the lower town before Rhea's guns are
  ordered onto it and she fights beside you at the Hammer (ff37); otherwise it is taken alone
  (ff38).
- **Carried armies**: the infiltration team walks from Orlov's hunting grounds into Kharn (ff24 →
  ff25), and the Ninth's veteran column marches through the whole last act (ff33 → ff39).

## The ledger across acts

Act-local facts are each mission's own; these are the facts one act writes and another reads.

| Fact | Written by | Read by |
|---|---|---|
| `ff_gold_found` | ff02 — the paymaster destroyed | ff09, **ff10 (gate)**, ff22, interlude I |
| `ff_powder_lost` | ff03 — a powder cart escapes | ff04, interlude I |
| `ff_convoys` | ff09 — one per convoy that reaches Hollin | ff13, interlude II |
| `ff_mint_page` | ff10 — the counting house taken before the ledgers burn | ff22, ff27 |
| `ff_nia_fought` | ff11 — one of Nia's rangers destroyed | **ff15 / ff16 (fork)**, ff17, ff39, interlude III |
| `ff_capital_ring` | ff13 — the Old Town still ours when the siege breaks | ff33, interlude II |
| `ff_cipher_read` | ff19 — Orin's listening post taken | ff26, ff27 |
| `ff_draeg_spared` | ff20 — Draeg's column withdraws with its command tank alive | ff26, ff35, ff39, interludes III & IV |
| `ff_ferrow_bought` | ff22 — Ferrow's counting house taken; his company defects | ff28, ff36, ff39 |
| `ff_rhea_turned` | ff30 — the lower town taken in time | ff32, **ff37 / ff38 (fork)**, ff39, interlude V |
| `ff_refugees` | ff32 — one per refugee convoy across the causeway | ff39, interlude VI |
| `ff_vance_joined` | ff34 — Vance's army comes over | ff39, interlude VI |
| `ff_vale_stood_down` | ff36 — Vale stands his arsenal guard down | ff39, interlude VI |

## The threads, and where each closes

| Thread | Opened | Closed |
|---|---|---|
| Who paid Ferrow? | ff02 (Concord gold) | ff22 (Ferrow admits it), ff26 (Draeg's proof) |
| Who burned the Hall? | ff04 | ff26 (Sable gave the order), ff27 (her confession), ff31 (Lyra's) |
| Alina Ward | ff06 (taken) | ff25 (freed), ff39 (re-founds the Ninth and gives it to Iris) |
| The Ninth scattered | ff06 | Nia ff15–ff17, Sera ff18, Draeg ff26, the Ninth whole at ff39 |
| Ivar Thorne | ff05 | ff17 (taken alive; the League tries him) |
| Lyra's arithmetic | ff05, ff14, ff23 (hints) | ff31 (fails), ff32 (she fights for her city), the epilogue (the ledgers surrendered, every war debt cancelled) |
| Hammerfall and Morn | ff13 | ff31 (the strike on Aurum), ff37 / ff38 (the Hammer taken), ff39 (Morn falls) |
| Mara Voss | ff08, ff13 | ff13 (respect), ff39 (she left Iron because of Morn; she is there when he falls) |
| Ferrow, Vance, Vale, Rhea | Acts I–V | their last missions, then the epilogue by what the ledger says |

The epilogue (the interlude after ff39) closes every row. The war ends; nothing is left pending.

## The cast and their voices

Every speaker is a commander on the roster; a line with no speaker is narration. Only commanders
are named characters. **Only Gideon Holt is funny. Konrad Vale and Lyra Quill never contract.**
Beats run one to three sentences. **Gideon Holt is the war's staff voice**: every defeat page is the
foe's line first, then his.

| Commander | Who | Voice |
|---|---|---|
| Iris Colt | Lt-Colonel of the Ninth, Alina's protégée; the protagonist | young, blunt, restless; refuses to stop |
| Alina Ward | General, founder-commander of the Ninth | warm, measured, first names |
| Gideon Holt | Quartermaster of the Ninth | dry; counts fuel, rations, invoices, coins |
| Sera Lark | Major, the Ninth's recon (Aurora) | fast, impatient, playful |
| Nia Rowan | Captain, the Ninth's rangers (Verdant) | quiet, few words; torn between League and Ninth |
| Viktor Draeg | Colonel, the Ninth's armour (Iron) | gruff, plain, honourable |
| Sable Wren | Major, the Ninth's intelligence (Concord) — the traitor | smooth, elliptical; unrepentant once known |
| Mara Voss | Marshal of Meridian; ex-Iron | hard, clipped; distrusts idealism |
| Halden Marr | Admiral of Meridian | patient; tide and coast |
| Dane Ferrow | Iron's licensed privateer | mercenary charm; receipts and invoices |
| Iona Vance | Field Marshal of Iron | cool, professional, percentages |
| Konrad Vale | Director of Industry, Iron | formal; quality and cost |
| Cass Orlov | Director of State Security, Iron | soft-spoken menace; the hunt |
| Radek Morn | Marshal of the Hammer | few words, absolute, calm |
| Lyra Quill | Chancellor of the Concord | precise, probabilities; sincere |
| Rhea Sol | Concord artillery general | fire plans; a conscience under orders |
| Ivar Thorne | the Verdant general who seized the council | grim; pain as virtue |
| Tomas Reed | Verdant people's tribune | rousing, warm |
| Ines Calder | First Speaker of the Verdant council | brisk, practical |
| Cassian Rook | Chancellor-General of Aurora | urbane; "the board just changed" |
| Orin Flux | Aurora's spymaster | dry radio chatter |
| Perrin Ash | Aurora's air marshal | cocky and kind |
