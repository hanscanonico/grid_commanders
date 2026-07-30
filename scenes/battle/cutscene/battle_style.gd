class_name BattleStyle
extends Resource
## How one kind of weapon looks and sounds when it fires in the battle cut-in.
##
## Pure presentation, and deliberately so (plan D5): there is no gameplay number
## anywhere below. What a shot *does* is the damage chart's and the resolver's;
## this only says whether it reads as a burst of tracer, a single heavy shell or
## a smoke-trailed rocket, and how long it hangs in the air on the way. Six of
## these cover eighteen units, which is why the roster needed no per-unit art.
##
## The class lives under scenes/ and the resources under data/battle_anim/, the
## same split every other data-driven thing here uses — except that this one may
## never be loaded from core/, which is why it is not in core/ to be reached for.
## UnitType carries only the key (`battle_style`), exactly as it carries
## `atlas_col`: a StringName naming a presentation record, and nothing more.

## Projectile kinds. What each looks like is CutsceneFx's business; this is the
## vocabulary the two agree on.
const NONE := &"none"  # unarmed — nothing leaves the barrel, ever
const TRACER := &"tracer"  # rapid dashes, several per volley
const SHELL := &"shell"  # one heavy round on a lobbed arc
const FLAK := &"flak"  # rounds that burst in the air short of the target
const ROCKET := &"rocket"  # a dart dragging a column of its own smoke
const BOMB := &"bomb"  # dropped from above, accelerating into the ground
const TORPEDO := &"torpedo"  # a wake running flat under the waterline

@export var id: StringName
@export var projectile: StringName = NONE
## What the chip beside the unit's name in the cut-in's plate reads. Data rather
## than a table in the director, so the word a weapon is announced by and the way
## it looks are the same record — a style cannot be added without naming itself.
## Empty draws no chip, which is what `NONE` wants.
@export var label: StringName = &""
## Rounds each standing figure contributes to the volley. A squad of five
## infantry throws a wall of tracer; a battleship fires once.
@export_range(1, 4) var shots_per_figure: int = 1
## Sfx name for the volley. Missing entries are silently skipped by Sfx, so a
## style may name a sound that has not been generated yet without breaking.
@export var sfx: StringName = &"shot"
## Multiplies the volley's travel budget. Under 1.0 snaps, over 1.0 hangs — an
## arcing shell has to look like it took its time getting there.
@export_range(0.5, 2.0) var travel_scale: float = 1.0
## Peak height of a lobbed round above the firing line, in pixels. Zero is flat.
@export var arc: float = 0.0
## Colour of the round in flight and of the streak behind it.
@export var tint: Color = Color(1.0, 0.949, 0.659)
## Radius of the muzzle starburst. Zero draws none, which is what `NONE` wants.
@export var muzzle: float = 12.0
## True when this weapon fires *continuously* for as long as its volley is in the
## air, rather than launching one salvo and falling silent. It changes both halves
## of what that looks like: the barrel strobes for the whole window instead of
## flashing once, and the rounds cycle across it instead of crossing as one wave —
## a machine gun that flashed at the front of its burst and then went dark would
## read as a single shot however many dashes were on screen.
@export var sustained: bool = false
## How much of the recoil lunge this weapon earns. A cannon slams its whole hull
## back; a machine gun barely kicks and a launcher sits between them.
@export_range(0.0, 1.0) var recoil: float = 1.0
## Radius of the burst this weapon leaves on whatever it hits. Zero is no burst —
## which is what a stream of small rounds wants, since it flickers with sparks
## instead (see CutsceneFx). Suppressed entirely when the shot cost nothing.
@export var impact_radius: float = 0.0


## True when this weapon puts anything on screen at all. An APC, a T-Copter and a
## Lander only ever take the hit, and their side of the frame stays quiet.
func fires() -> bool:
	return projectile != NONE
