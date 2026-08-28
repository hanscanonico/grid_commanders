# The roster

`portraitgen/roster.py` is the only per-general data in this pipeline: nineteen
columns per bust. Eighteen are transcribed from the game's retired GDScript face
table column for column; `chest` is the one this pipeline added, because that
table wore one diagonal sash five times over. Every column names into a vocabulary owned by the module that
draws it, so this table says *which* mark a general wears and never *how* it is
drawn. `tests/test_roster.py` holds it to the lints the GUT suite used to carry,
including set equality against `data/commanders`, so a general seated without a
row — or a row for a general since retired — fails rather than goes quiet.

**Must stay recognisable** is the contract the painter inherits: a player who
knows a general has to still name them at the 31px HUD chip. It is what a retune
may not spend, and it is the reason the columns below are a port rather than a
redesign.

## Meridian Coalition

| id | Must stay recognisable |
| --- | --- |
| `alina_ward` | The auburn mass, the earring, the sabre |
| `gideon_holt` | Everything — the sheet's exemplar: beard, glasses, and a pipe that merges into the beard's silhouette |
| `rhea_sol` | Goggles worn up on the forehead, the black ponytail, the wrench |
| `mara_voss` | The bandolier and its medallion, over the black bun |
| `halden_marr` | The beard and the anchor — he is the sea commander |
| `iris_colt` | The tail and the headset boom mic: one silhouette that survives decimation |

## Iron Dominion

| id | Must stay recognisable |
| --- | --- |
| `cass_orlov` | The scar and the cigar, clear of the mouth line |
| `viktor_draeg` | The eyepatch and the shoulder boards |
| `konrad_vale` | The mandarin collar and its gold buttons |
| `dane_ferrow` | The set jaw — the best angry read on the sheet |
| `iona_vance` | The scales, the right object for a logistician |
| `radek_morn` | Everything — the second exemplar: the widest skull, the beard, the hammer touching the shoulder |

## Aurora Compact

| id | Must stay recognisable |
| --- | --- |
| `cassian_rook` | The playing card |
| `lyra_quill` | Closed eyes, the white bob, and the grid backdrop |
| `orin_flux` | The spikes and the laugh — the sheet's reference for an open mouth |
| `perrin_ash` | The goggles |
| `sera_lark` | The bandana and the compass |

## Verdant League

| id | Must stay recognisable |
| --- | --- |
| `nia_rowan` | The freckles, the headband and the braid — they are what split her from Reed |
| `sable_wren` | The hood silhouette |
| `tomas_reed` | Everything — the shipped exemplar for a prop that touches by silhouette merge: the curly crop, the bandana, the handset with a cable following the shoulder |
| `ines_calder` | The glasses, the ledger and the grid backdrop |
| `ivar_thorne` | The long hair and beard mass — the sheet's most distinct outline |

## The empty seat

`roster.NEUTRAL` is not a `Face`: it names none of the vocabularies. It is the
default skull at the default pose over the `bars` backdrop, in the UI's slate
rather than a skin ramp, with no hair, no expression and no prop. It reads as a
deliberate empty seat rather than as a bust that failed to render, and that is
the whole of what it must keep — do not decorate it.
