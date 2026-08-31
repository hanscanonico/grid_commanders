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
## The whole vocabulary, in one list, because CutsceneFx draws by matching on it:
## a kind spelled here and nowhere there draws nothing, and one spelled in a
## `.tres` and not here used to fall through to tracer with nothing said.
## `BattleStyleDB.register` is what holds a style to it.
const PROJECTILES: Array[StringName] = [NONE, TRACER, SHELL, FLAK, ROCKET, BOMB, TORPEDO]

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
## How long this weapon winds up before it fires, in seconds at the default speed
## tier: the beat between the squad halting in its firing slot and the barrel
## lighting. Most of what tells the weapon classes apart happens here, before a
## single pixel of projectile exists — a rifle squad shoulders and goes, a
## howitzer visibly elevates and holds. CombatBeats owns how it lands on the
## clock, including the floor that keeps it readable at high playback rates.
@export_range(0.0, 0.5) var aim_seconds: float = 0.16
## How far the weapon rises over that beat, in pixels: positive lifts (a turret
## settling up, a bow coming out of the water as the tubes flood), negative
## settles (a bomber's nose dropping into its run).
@export var aim_lift: float = 0.0
## And how far it tips over the same beat, in radians, nose-toward-the-seam
## positive. A second scalar rather than one reinterpreted per domain: a bank and
## a barrel rise are different motions, and the branch that told them apart would
## be the same answer spelled in three places.
@export var aim_pitch: float = 0.0
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
## How far apart, in seconds, consecutive figures of a squad open fire. Zero is a
## rank that lights as one, which is what a single heavy gun wants. It is where
## the difference between a rifle squad and an autocannon lives: their wind-ups
## are 30 ms apart, which nobody can see, and their *cadence* is not — five
## barrels 45 ms apart read as a loose stream where four 30 ms apart read as one
## wall of fire.
@export_range(0.0, 0.2) var fire_stagger: float = 0.0
## Multiplies how far this weapon's squad rolls in over the arrive beat. A bomber
## comes in from further out than a rifle squad walks.
@export_range(0.5, 1.5) var arrive_scale: float = 1.0
## How much scuff the squad kicks arriving and firing, 0 for something that never
## touches the ground.
@export_range(0.0, 1.0) var dust: float = 0.0
## How many chips this weapon throws out of whatever it hits. Capped low on
## purpose: at 640x360 a hit that throws more than a handful stops reading as
## debris and starts reading as noise, and the kill blast — which throws twelve
## and owns the frame — suppresses these entirely rather than adding to them.
@export_range(0, 5) var impact_debris: int = 0


## True when this weapon puts anything on screen at all. An APC, a T-Copter and a
## Lander only ever take the hit, and their side of the frame stays quiet.
func fires() -> bool:
	return projectile != NONE
